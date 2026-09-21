const CallLog = require('../models/CallLog');
const Lead = require('../models/Lead');
const Recording = require('../models/Recording');
const { last10, exactNameRegex, anyPhoneRegex, parseDeviceTime } = require('../utils/common');
const {
  buildDedupKey, buildDedupKeyById, normalizeCallType, pairCallsWithRecordings,
  initialLeadStatus, nextAutoStatus, LINK_WINDOW_MS,
} = require('./matching');

// All reporting periods are calendar periods in India time, independent of the server's timezone.
const IST_OFFSET_MS = 330 * 60000;

function istParts(date) {
  const shifted = new Date(date.getTime() + IST_OFFSET_MS);
  return { y: shifted.getUTCFullYear(), m: shifted.getUTCMonth(), d: shifted.getUTCDate(), dow: shifted.getUTCDay() };
}

function istMidnight(y, m, d) {
  return new Date(Date.UTC(y, m, d) - IST_OFFSET_MS);
}

// Accepts 'YYYY-MM-DD' (treated as an India calendar day) or any parseable date.
function parseIstDay(value) {
  const match = /^(\d{4})-(\d{2})-(\d{2})/.exec(value || '');
  if (match) return { y: +match[1], m: +match[2] - 1, d: +match[3] };
  const parsed = new Date(value);
  return isNaN(parsed.getTime()) ? null : istParts(parsed);
}

// Returns a Mongo condition { $gte, $lt } for the requested period, or null for "all time".
// `now` is injectable for tests.
function getPeriodRange({ period, timeFilter, date, startDate, endDate } = {}, now = new Date()) {
  if (startDate && endDate) {
    const s = parseIstDay(startDate);
    const e = parseIstDay(endDate);
    if (s && e) return { $gte: istMidnight(s.y, s.m, s.d), $lt: istMidnight(e.y, e.m, e.d + 1) };
  }
  if (date) {
    const d = parseIstDay(date);
    if (d) return { $gte: istMidnight(d.y, d.m, d.d), $lt: istMidnight(d.y, d.m, d.d + 1) };
  }

  const tf = timeFilter === undefined || timeFilter === null ? '' : String(timeFilter);
  const today = istParts(now);
  const tomorrow = istMidnight(today.y, today.m, today.d + 1);

  if (period === 'today' || tf === '0' || tf === 'today') {
    return { $gte: istMidnight(today.y, today.m, today.d), $lt: tomorrow };
  }
  if (period === 'week' || tf === '1' || tf === 'week') {
    const daysSinceMonday = (today.dow + 6) % 7;
    return { $gte: istMidnight(today.y, today.m, today.d - daysSinceMonday), $lt: tomorrow };
  }
  if (period === 'month' || tf === '2' || tf === 'month') {
    return { $gte: istMidnight(today.y, today.m, 1), $lt: tomorrow };
  }
  return null;
}

// Metric definitions shared by the admin web and the mobile app:
//   incoming = received / missed / declined calls, outgoing = everything dialled
//   connected = duration > 0
//   missed = unanswered incoming, rejected = declined or unanswered outgoing
//   neverAttended = missed + rejected
const isConnected = { $gt: [{ $ifNull: ['$durationSeconds', 0] }, 0] };
const notConnected = { $not: [isConnected] };
const typeIn = (types) => ({ $in: ['$type', types] });
const isInbound = typeIn(['incoming', 'missed', 'rejected']);
const countIf = (cond) => ({ $sum: { $cond: [cond, 1, 0] } });
const metricFields = () => ({
  totalCalls: { $sum: 1 },
  connectedCalls: countIf(isConnected),
  incoming: countIf(isInbound),
  outgoing: countIf({ $not: [isInbound] }),
  missed: countIf({ $and: [notConnected, typeIn(['incoming', 'missed'])] }),
  rejected: countIf({ $and: [notConnected, { $not: [typeIn(['incoming', 'missed'])] }] }),
  neverAttended: countIf(notConnected),
  talkSeconds: { $sum: { $ifNull: ['$durationSeconds', 0] } },
});
const METRICS = ['totalCalls', 'connectedCalls', 'incoming', 'outgoing', 'missed', 'rejected', 'neverAttended', 'talkSeconds'];
const zeroMetrics = () => Object.fromEntries(METRICS.map(k => [k, 0]));
const roundMetrics = (o) => { METRICS.forEach(k => { o[k] = Math.round(o[k] || 0); }); return o; };

// Counts calls inside MongoDB (no row limits). Legacy duplicate rows that share
// caller + number + timestamp are collapsed so they are counted once.
async function aggregateCallStats(match) {
  const [result] = await CallLog.aggregate([
    { $match: match },
    {
      $group: {
        _id: { c: '$callerPhone', p: '$phoneNumber', t: '$timestamp' },
        callerId: { $first: '$callerId' },
        callerPhone: { $first: '$callerPhone' },
        callerName: { $first: '$callerName' },
        phoneNumber: { $first: '$phoneNumber' },
        type: { $first: '$type' },
        timestamp: { $first: '$timestamp' },
        durationSeconds: { $max: '$durationSeconds' },
      }
    },
    {
      $facet: {
        totals: [{ $group: { _id: null, ...metricFields() } }],
        byCaller: [{ $group: { _id: { callerId: '$callerId', callerPhone: '$callerPhone', callerName: '$callerName' }, ...metricFields() } }],
        byHour: [{ $group: { _id: { $hour: { date: '$timestamp', timezone: 'Asia/Kolkata' } }, calls: { $sum: 1 } } }],
        clients: [{ $group: { _id: '$phoneNumber' } }],
      }
    }
  ]).allowDiskUse(true);

  const totals = roundMetrics({ ...zeroMetrics(), ...(result.totals[0] || {}) });
  delete totals._id;
  const byCaller = result.byCaller.map(row => roundMetrics({
    callerId: row._id.callerId || '',
    callerPhone: row._id.callerPhone || '',
    callerName: row._id.callerName || '',
    ...Object.fromEntries(METRICS.map(k => [k, row[k]])),
  }));

  const hourly = {};
  result.byHour.forEach(h => { hourly[h._id] = h.calls; });

  const uniqueClients = new Set(result.clients.map(c => last10(c._id)).filter(Boolean)).size;

  return { ...totals, byCaller, hourly, uniqueClients };
}

// Sums every stats row that belongs to an employee (by id, else phone last 10 digits, else exact name).
// Each row is a distinct set of calls, so summing never double counts.
function findCallerStats(byCaller, emp) {
  const empLast10 = last10(emp.phone);
  const empName = (emp.name || '').trim().toLowerCase();
  const rows = byCaller.filter(c =>
    (c.callerId && c.callerId === emp.id) ||
    (empLast10.length >= 8 && last10(c.callerPhone) === empLast10) ||
    (empName && (c.callerName || '').trim().toLowerCase() === empName));
  if (rows.length === 0) return null;
  const sum = zeroMetrics();
  rows.forEach(r => METRICS.forEach(k => { sum[k] += r[k] || 0; }));
  return sum;
}

// ---- Sync ---------------------------------------------------------------------------------------

// Normalises the device payload: valid rows only, one row per dedupe key.
function prepareCalls(callerEmp, calls, fallbackPhone = '') {
  const callerPhone = callerEmp.phone || fallbackPhone || '';
  const seen = new Set();
  const out = [];
  for (const call of calls || []) {
    if (!call || !call.phoneNumber) continue;
    const callTime = parseDeviceTime(call.timestamp);
    if (!callTime || isNaN(callTime.getTime())) continue;
    const phoneNumber = String(call.phoneNumber).trim().slice(0, 40);
    const key = buildDedupKeyById(callerEmp.id, phoneNumber, callTime);
    if (seen.has(key)) continue;
    seen.add(key);
    const contactName = typeof call.contactName === 'string' ? call.contactName.trim().slice(0, 120) : '';
    out.push({
      key,
      oldKey: buildDedupKey(callerPhone, phoneNumber, callTime),
      phoneNumber,
      last10: last10(phoneNumber),
      timestamp: callTime,
      contactName: ['unknown', 'unknown contact'].includes(contactName.toLowerCase()) ? '' : contactName,
      type: normalizeCallType(call.type),
      durationSeconds: Math.max(0, Math.round(Number(call.durationSeconds) || 0)),
      simSlot: Math.max(1, Math.round(Number(call.simSlot) || 1)),
      note: typeof call.note === 'string' ? call.note.slice(0, 1000) : '',
    });
  }
  return { callerPhone, rows: out };
}

// Inserts device call logs for a registered caller. Safe to call repeatedly and concurrently:
// the unique dedupKey index guarantees a call is stored only once. A handful of batched round trips
// per sync (not per call).
async function syncCallsForCaller(callerEmp, calls) {
  const { callerPhone, rows } = prepareCalls(callerEmp, calls);
  if (rows.length === 0) return 0;

  // 1. Which calls already exist? New id-based key, the old phone-based key, and rows stored before keys existed.
  const legacyRows = await CallLog.find({
    dedupKey: { $exists: false },
    timestamp: { $in: rows.map(r => r.timestamp) },
    $or: [{ callerId: callerEmp.id }, ...(callerPhone ? [{ callerPhone }] : [])],
  }).select('_id phoneNumber timestamp').lean();
  const legacyIds = new Map(legacyRows.map(l => [
    `${last10(l.phoneNumber) || l.phoneNumber}_${new Date(l.timestamp).getTime()}`,
    l._id,
  ]));

  // Call-log entries can be observed before their final duration/type is available.
  const syncable = rows;

  // 2. Upsert in one bulk write. Existing rows get the latest call facts from the device (type, talk
  // time); names and notes are only written on insert so edits made since (e.g. a saved contact) survive.
  // New rows are still protected by the unique dedupKey index.
  const ops = syncable.map(r => ({
    updateOne: {
      filter: {
        $or: [
          { dedupKey: r.key },
          { dedupKey: r.oldKey },
          ...(legacyIds.has(`${r.last10 || r.phoneNumber}_${r.timestamp.getTime()}`)
            ? [{ _id: legacyIds.get(`${r.last10 || r.phoneNumber}_${r.timestamp.getTime()}`) }]
            : []),
        ],
      },
      update: {
        $set: {
          dedupKey: r.key,
          callerId: callerEmp.id,
          callerName: callerEmp.name || '',
          callerPhone,
          phoneNumber: r.phoneNumber,
          type: r.type,
          timestamp: r.timestamp,
          durationSeconds: r.durationSeconds,
          simSlot: r.simSlot,
        },
        $setOnInsert: {
          contactName: r.contactName,
          note: r.note,
          recordingUrl: '',
          recordingId: '',
          createdAt: new Date(),
          updatedAt: new Date(),
        },
      },
      upsert: true,
    }
  }));
  let writeResult = {};
  let upserted = {};
  try {
    const res = await CallLog.bulkWrite(ops, { ordered: false, timestamps: false });
    writeResult = res;
    upserted = res.upsertedIds || {};
  } catch (err) {
    // 11000 = the same call was inserted by a concurrent sync; everything else is a real error
    const writeErrors = err.writeErrors || (err.result && err.result.getWriteErrors ? err.result.getWriteErrors() : []);
    if (!writeErrors.length || writeErrors.some(e => (e.code || (e.err && e.err.code)) !== 11000)) throw err;
    writeResult = err.result || {};
    upserted = writeResult.upsertedIds || (writeResult.result && writeResult.result.upsertedIds) || {};
  }
  const inserted = Object.entries(upserted).map(([idx, _id]) => ({ ...syncable[Number(idx)], _id }));
  const modified = Number(writeResult.modifiedCount || writeResult.nModified || 0);
  if (inserted.length === 0 && modified === 0) return 0;

  // 3. Link recordings uploaded before this sync (same caller + number, start within ±5 min, closest wins)
  try {
    await linkRecordingsToNewCalls(callerEmp, inserted);
  } catch (linkErr) {
    console.warn('Recording link warning:', linkErr.message);
  }

  // 4. Leads: one attempt per newly stored call
  try {
    await applyCallsToLeads(callerEmp, inserted);
  } catch (leadErr) {
    console.warn('Lead update warning:', leadErr.message);
  }

  return inserted.length + modified;
}

async function linkRecordingsToNewCalls(callerEmp, inserted) {
  const withNumbers = inserted.filter(c => c.last10.length >= 8);
  if (withNumbers.length === 0) return;
  const times = withNumbers.map(c => c.timestamp.getTime());
  const minT = new Date(Math.min(...times) - LINK_WINDOW_MS);
  const maxT = new Date(Math.max(...times) + LINK_WINDOW_MS);
  const phoneRe = anyPhoneRegex(withNumbers.map(c => c.last10));
  const recordings = await Recording.find({
    phoneNumber: phoneRe,
    callLogId: { $in: [null, ''] },
    $and: [
      { $or: [{ callerId: callerEmp.id }, { callerId: { $in: [null, ''] }, callerName: exactNameRegex(callerEmp.name || '') }] },
      // uploads happen after the call started; allow a day for queued uploads from old app builds
      { $or: [{ callStartedAt: { $gte: minT, $lte: maxT } }, { callStartedAt: null, createdAt: { $gte: minT, $lte: new Date(maxT.getTime() + 86400000) } }] },
    ],
  }).select('id phoneNumber callStartedAt createdAt durationSeconds').lean();
  if (recordings.length === 0) return;

  const pairs = pairCallsWithRecordings(withNumbers, recordings);
  if (pairs.length === 0) return;
  await CallLog.bulkWrite(pairs.map(({ call, recording }) => ({
    updateOne: {
      filter: { _id: call._id },
      update: { $set: { recordingId: recording.id, recordingUrl: `/api/recordings/${recording.id}/audio` } },
    }
  })), { ordered: false });
  await Recording.bulkWrite(pairs.map(({ call, recording }) => ({
    updateOne: { filter: { _id: recording._id, callLogId: { $in: [null, ''] } }, update: { $set: { callLogId: String(call._id) } } }
  })), { ordered: false });
}

const looksLikeNumber = (s) => !s || /^[+\d\s()-]+$/.test(String(s).trim()) || /^Contact \(/.test(String(s));

// Loads leads for the given last-10 numbers, back-filling phoneLast10 on older rows (lazy migration).
async function findLeadsByLast10(numbers) {
  const list = [...new Set(numbers.filter(n => n.length >= 8))];
  if (list.length === 0) return new Map();
  const map = new Map();
  const found = await Lead.find({ phoneLast10: { $in: list } }).sort({ createdAt: 1 }).lean();
  found.forEach(l => { if (!map.has(l.phoneLast10)) map.set(l.phoneLast10, l); });
  const missing = list.filter(n => !map.has(n));
  if (missing.length) {
    for (let i = 0; i < missing.length; i += 200) {
      const chunk = missing.slice(i, i + 200);
      const legacy = await Lead.find({ phoneLast10: { $in: [null, ''] }, phone: anyPhoneRegex(chunk) }).sort({ createdAt: 1 }).lean();
      const backfill = [];
      legacy.forEach(l => {
        const k = last10(l.phone);
        backfill.push({ updateOne: { filter: { _id: l._id }, update: { $set: { phoneLast10: k } } } });
        if (!map.has(k)) map.set(k, { ...l, phoneLast10: k });
      });
      if (backfill.length) await Lead.bulkWrite(backfill, { ordered: false });
    }
  }
  return map;
}

// Applies newly stored calls to leads: attempts +1 per call, lastCallDate, forward-only status.
// New numbers get a lead via an upsert on phoneLast10 (so concurrent syncs don't create two).
async function applyCallsToLeads(callerEmp, inserted) {
  const byNumber = new Map();
  inserted.filter(c => c.last10.length >= 8)
    .sort((a, b) => a.timestamp - b.timestamp)
    .forEach(c => { if (!byNumber.has(c.last10)) byNumber.set(c.last10, []); byNumber.get(c.last10).push(c); });
  if (byNumber.size === 0) return;

  const leads = await findLeadsByLast10([...byNumber.keys()]);
  const ops = [];
  for (const [num, callsForNumber] of byNumber) {
    const lastCall = callsForNumber[callsForNumber.length - 1];
    const lead = leads.get(num);
    if (lead) {
      let status = lead.status;
      callsForNumber.forEach(c => { status = nextAutoStatus(status, { connected: c.durationSeconds > 0, type: c.type }); });
      const set = { lastCallDate: lastCall.timestamp, phoneLast10: num };
      if (status !== lead.status) set.status = status;
      const realName = callsForNumber.map(c => c.contactName).filter(n => n && !looksLikeNumber(n)).pop();
      if (realName && looksLikeNumber(lead.name)) set.name = realName;
      // Assign only unassigned leads; never take a lead away from the caller a manager assigned it to
      if (!lead.assignedCallerId && (!lead.assignedCaller || lead.assignedCaller === 'Unassigned' ||
          lead.assignedCaller.trim().toLowerCase() === (callerEmp.name || '').trim().toLowerCase())) {
        set.assignedCallerId = callerEmp.id;
        set.assignedCaller = callerEmp.name || '';
      }
      ops.push({ updateOne: { filter: { _id: lead._id }, update: { $set: set, $inc: { attempts: callsForNumber.length } } } });
    } else {
      const first = callsForNumber[0];
      let status = initialLeadStatus({ connected: first.durationSeconds > 0, type: first.type });
      callsForNumber.slice(1).forEach(c => { status = nextAutoStatus(status, { connected: c.durationSeconds > 0, type: c.type }); });
      const realName = callsForNumber.map(c => c.contactName).filter(n => n && !looksLikeNumber(n)).pop();
      ops.push({
        updateOne: {
          filter: { phoneLast10: num },
          update: {
            $setOnInsert: {
              id: `lead_${Date.now()}_${Math.random().toString(36).substring(2, 8)}`,
              name: realName || first.phoneNumber,
              phone: first.phoneNumber,
              status,
              assignedCallerId: callerEmp.id,
              assignedCaller: callerEmp.name || '',
              notes: `Auto-created from call on ${first.timestamp.toISOString().slice(0, 10)}`,
              source: 'call',
              batchName: '',
              dateAdded: first.timestamp,
            },
            $set: { lastCallDate: lastCall.timestamp },
            $inc: { attempts: callsForNumber.length },
          },
          upsert: true,
        }
      });
    }
  }
  if (ops.length) await Lead.bulkWrite(ops, { ordered: false });
}

// Recording upload: forward-only status change on an existing lead; no attempt is counted
// (the call itself is counted once, by the sync). Creates the lead if the number is new.
async function applyRecordingToLead(callerEmp, { phoneNumber, contactName, durationSeconds, type }) {
  const num = last10(phoneNumber);
  if (num.length < 8) return;
  const leads = await findLeadsByLast10([num]);
  const lead = leads.get(num);
  const connected = (Number(durationSeconds) || 0) > 0;
  const callType = type === 'INCOMING' ? 'incoming' : 'outgoing';
  const name = contactName && !looksLikeNumber(contactName) ? String(contactName).trim().slice(0, 120) : '';
  if (lead) {
    const set = {};
    const status = nextAutoStatus(lead.status, { connected, type: callType });
    if (status !== lead.status) set.status = status;
    if (name && looksLikeNumber(lead.name)) set.name = name;
    if (Object.keys(set).length) await Lead.updateOne({ _id: lead._id }, { $set: set });
    return;
  }
  await Lead.updateOne(
    { phoneLast10: num },
    {
      $setOnInsert: {
        id: `lead_${Date.now()}_${Math.random().toString(36).substring(2, 8)}`,
        name: name || String(phoneNumber).trim(),
        phone: String(phoneNumber).trim(),
        status: initialLeadStatus({ connected, type: callType }),
        attempts: 0,
        assignedCallerId: callerEmp ? callerEmp.id : '',
        assignedCaller: callerEmp ? callerEmp.name : 'Unassigned',
        notes: 'Auto-created from a call recording',
        source: 'recording',
        batchName: '',
        lastCallDate: new Date(),
        dateAdded: new Date(),
      }
    },
    { upsert: true }
  );
}

module.exports = {
  last10,
  buildDedupKey,
  getPeriodRange,
  aggregateCallStats,
  findCallerStats,
  prepareCalls,
  syncCallsForCaller,
  applyRecordingToLead,
  findLeadsByLast10,
};
