const express = require('express');
const fs = require('fs');
const path = require('path');
const RecordingIssue = require('../models/RecordingIssue');
const Employee = require('../models/Employee');
const Recording = require('../models/Recording');
const CallLog = require('../models/CallLog');
const LegacyClientHit = require('../models/LegacyClientHit');
const { isOnline } = require('../services/presence');
const { legacyGraceEnabled } = require('../middleware/auth');
const { resolveScope } = require('../services/scope');
const { parseLimit, parseDate } = require('../utils/common');

const router = express.Router();

// Per-call recording diagnostics from the app (no audio, no customer numbers): which mic source was
// used, how much speech it heard, accessibility state, phone model. Used to support phones whose
// recordings come out silent. Stored as JSON lines in backend/logs/recording-diagnostics.jsonl.
// Calls whose recording is missing or mic-only also become RecordingIssue rows, which admins and
// managers see on the Recordings page (GET /api/admin/recording-issues).
const LOG_DIR = path.join(__dirname, '../../logs');
const LOG_FILE = path.join(LOG_DIR, 'recording-diagnostics.jsonl');
const MAX_ITEMS = 50;
const MAX_FILE_BYTES = 5 * 1024 * 1024;
/** A connected call shorter than this without a recording is not worth an alert (wrong number, hang-up). */
const MIN_ALERT_TALK_SECONDS = 10;

const ALLOWED_KEYS = new Set([
  'at', 'manufacturer', 'brand', 'model', 'sdkInt', 'dialerPackage', 'accessibilityEnabled',
  'source', 'sourceName', 'sourceMode', 'recordedSeconds', 'voicedSeconds', 'peak', 'talkSeconds',
  'result', 'builtInFound', 'uploadedOwn', 'appVersion', 'note', 'backup', 'speaker', 'foundIn', 'foundAfterSec',
  'builtInDialer',
]);

function clean(item) {
  const out = {};
  if (!item || typeof item !== 'object') return out;
  for (const [k, v] of Object.entries(item)) {
    if (!ALLOWED_KEYS.has(k)) continue;
    if (typeof v === 'string') out[k] = v.slice(0, 200);
    else if (typeof v === 'number' || typeof v === 'boolean') out[k] = v;
  }
  return out;
}

// Loudspeaker outcomes after which a microphone recording should contain the customer too
const SPEAKER_ON = ['on', 'on_api', 'already_on'];

function speakerText(speaker, a11yOn) {
  switch (speaker) {
    case 'on': case 'on_api': case 'already_on': return 'loudspeaker was on, so the customer should be audible';
    case 'tapped': return 'loudspeaker was tapped but not confirmed: check the customer is audible';
    case 'tap_no_effect': return 'loudspeaker tap had no effect: customer voice is probably missing';
    case 'not_found': return 'the Speaker button was not found on the call screen: customer voice is probably missing';
    case 'headset': return 'a headset was connected: customer voice is missing';
    case 'no_accessibility': return 'Accessibility was off, so the loudspeaker could not be switched on: customer voice is probably missing';
    case 'requested': return a11yOn === false
      ? 'Accessibility was off, so the loudspeaker could not be switched on: customer voice is probably missing'
      : 'the loudspeaker could not be confirmed: check the customer is audible';
    default: return 'the loudspeaker was not used: customer voice is probably missing';
  }
}

// "Phone by Google" keeps its recordings private. builtInDialer (app 1.0.6+): whether the phone also has
// its maker's own Phone app, so the caller can fix it by switching; absent from older app builds.
function googleDialerWhy(d) {
  if (d.dialerPackage !== 'com.google.android.dialer') return null;
  const base = 'The phone uses "Phone by Google", which keeps its recordings private';
  if (d.builtInDialer === true) {
    return `${base}. The phone also has its own Phone app: the caller should make it the default Phone app `
      + '(AskEVA shows how on the dashboard) and turn on its automatic call recording';
  }
  if (d.builtInDialer === false) {
    return `${base}. It is the only Phone app on this phone, so only AskEVA's microphone recording is possible`;
  }
  return base;
}

/** { kind, reason } for a call whose recording is missing or mic-only, null when it is fine. */
function issueOf(d) {
  const talk = Number(d.talkSeconds) || 0;
  const why = googleDialerWhy(d) || "The phone's own call recording was not found (auto-record off, or no recorder on this phone)";
  if (d.result === 'ok') {
    // AskEVA's microphone recording was uploaded instead of the phone's own recording
    if (talk < MIN_ALERT_TALK_SECONDS) return null;
    return { kind: 'mic_only', reason: `${why}. AskEVA's microphone recording was uploaded; ${speakerText(d.speaker, d.accessibilityEnabled)}.` };
  }
  if (!['silent', 'empty', 'not_recorded'].includes(d.result) || talk < MIN_ALERT_TALK_SECONDS) return null;
  let reason;
  if (d.result === 'silent') {
    reason = d.accessibilityEnabled === false
      ? 'Not recorded: Android muted the microphone because "AskEVA Call Recording" was off in Accessibility.'
      : 'Not recorded: the microphone recording was silent and was discarded.';
  } else if (d.result === 'empty') {
    reason = "Not recorded: AskEVA's recorder produced an empty file.";
  } else if (/no mic permission/.test(d.note || '')) {
    reason = 'Not recorded: the microphone permission is off.';
  } else if (/built-in recorder trusted/.test(d.note || '')) {
    reason = "Not recorded: the phone's own recorder made no recording of this call (auto-record may have been switched off).";
  } else {
    reason = "Not recorded: AskEVA's recorder could not start.";
  }
  return { kind: 'lost', reason: `${reason} ${why}.` };
}

// POST /api/diagnostics/recording  { items: [ {...}, ... ] }  (any signed-in user)
router.post('/api/diagnostics/recording', async (req, res) => {
  try {
    const items = Array.isArray(req.body && req.body.items) ? req.body.items.slice(0, MAX_ITEMS) : [];
    if (items.length === 0) return res.status(400).json({ success: false, message: 'No diagnostics' });
    if (!fs.existsSync(LOG_DIR)) fs.mkdirSync(LOG_DIR, { recursive: true });
    try {
      if (fs.existsSync(LOG_FILE) && fs.statSync(LOG_FILE).size > MAX_FILE_BYTES) {
        fs.renameSync(LOG_FILE, LOG_FILE + '.old');
      }
    } catch (_) { /* rotation is best effort */ }
    const user = req.user || {};
    const cleaned = items.map(clean);
    const lines = cleaned.map(item => JSON.stringify({
      receivedAt: new Date().toISOString(),
      userId: user.id || null,
      userName: user.name || null,
      ...item,
    }));
    fs.appendFileSync(LOG_FILE, lines.join('\n') + '\n');

    // Missing / mic-only recordings: visible to admins and managers
    const issues = [];
    for (const d of cleaned) {
      const issue = issueOf(d);
      if (!issue) continue;
      const at = Number(d.at);
      issues.push({
        callerId: user.id || '',
        callerName: user.name || '',
        ...issue,
        result: d.result || '',
        note: d.note || '',
        speaker: d.speaker || '',
        talkSeconds: Math.round(Number(d.talkSeconds) || 0),
        accessibilityEnabled: typeof d.accessibilityEnabled === 'boolean' ? d.accessibilityEnabled : null,
        manufacturer: d.manufacturer || '',
        brand: d.brand || '',
        model: d.model || '',
        sdkInt: Number(d.sdkInt) || 0,
        dialerPackage: d.dialerPackage || '',
        appVersion: d.appVersion || '',
        callProcessedAt: Number.isFinite(at) && at > 0 ? new Date(at) : null,
      });
    }
    if (issues.length && user.id) {
      try {
        await RecordingIssue.insertMany(issues);
      } catch (err) {
        console.error('recording issues not stored:', err.message);
      }
    }

    // The phone's current setup (latest report), shown on the Phone health page
    const latest = cleaned.reduce((best, d) => (!best || (Number(d.at) || 0) >= (Number(best.at) || 0) ? d : best), null);
    if (latest && user.id && (latest.model || latest.appVersion)) {
      try {
        const at = Number(latest.at);
        await Employee.updateOne({ id: user.id }, {
          $set: {
            deviceInfo: {
              manufacturer: latest.manufacturer || '',
              brand: latest.brand || '',
              model: latest.model || '',
              sdkInt: Number(latest.sdkInt) || 0,
              appVersion: latest.appVersion || '',
              dialerPackage: latest.dialerPackage || '',
              accessibilityEnabled: typeof latest.accessibilityEnabled === 'boolean' ? latest.accessibilityEnabled : null,
              lastResult: latest.result || '',
              reportedAt: Number.isFinite(at) && at > 0 ? new Date(at) : new Date(),
            },
          },
        });
      } catch (err) {
        console.error('device info not stored:', err.message);
      }
    }
    res.json({ success: true, stored: lines.length, issues: issues.length });
  } catch (err) {
    console.error('diagnostics error:', err.message);
    res.status(500).json({ success: false, message: 'Could not store diagnostics' });
  }
});

const ANDROID_VERSIONS = { 29: '10', 30: '11', 31: '12', 32: '12L', 33: '13', 34: '14', 35: '15', 36: '16', 37: '17' };

function issueDTO(r) {
  return {
    id: String(r._id),
    callerId: r.callerId,
    callerName: r.callerName,
    kind: r.kind,
    reason: r.reason,
    talkSeconds: r.talkSeconds,
    speaker: r.speaker,
    accessibilityEnabled: r.accessibilityEnabled,
    phone: [r.brand || r.manufacturer, r.model].filter(Boolean).join(' '),
    android: r.sdkInt ? (ANDROID_VERSIONS[r.sdkInt] || `SDK ${r.sdkInt}`) : '',
    dialerPackage: r.dialerPackage,
    appVersion: r.appVersion || '',
    at: r.callProcessedAt || r.createdAt,
  };
}

// GET /api/admin/recording-issues?from=&to=&callerIds=&limit=  (admins / managers; managers see their team)
router.get('/api/admin/recording-issues', async (req, res) => {
  try {
    const scope = await resolveScope(req, req.query);
    if (scope.empty) return res.json({ success: true, issues: [] });
    const conditions = [];
    if (!scope.all) conditions.push({ callerId: { $in: scope.employees.map(e => e.id).filter(Boolean) } });
    const from = parseDate(req.query.from);
    const to = parseDate(req.query.to);
    if (from || to) conditions.push({ createdAt: { ...(from ? { $gte: from } : {}), ...(to ? { $lte: to } : {}) } });
    const query = conditions.length ? { $and: conditions } : {};
    const rows = await RecordingIssue.find(query).sort({ createdAt: -1 }).limit(parseLimit(req.query.limit, 200, 1000)).lean();
    res.json({ success: true, issues: rows.map(issueDTO) });
  } catch (err) {
    console.error('recording issues error:', err.message);
    res.status(500).json({ success: false, message: 'Could not load recording problems' });
  }
});

// ---- Phone health ---------------------------------------------------------------------------------
// Is every agent's phone recording calls? Per agent: connected calls vs. calls with a recording, how
// the recordings were made, problem reports, the phone's setup and whether it still runs an old app
// (no login). Same scope rules as the dashboard: managers see their team, admins everyone.

/** A connected call shorter than this is not counted (wrong number, quick hang-up). */
const HEALTH_MIN_TALK_SECONDS = 10;
const IST_OFFSET_MS = 330 * 60 * 1000;

/** Start of the period: today (India time) for 1 day, else the last N days. */
function healthSince(days, now = Date.now()) {
  if (days === 1) {
    const istMidnight = Math.floor((now + IST_OFFSET_MS) / 86400000) * 86400000 - IST_OFFSET_MS;
    return new Date(istMidnight);
  }
  return new Date(now - days * 86400000);
}

function deviceDTO(d, fallbackAt) {
  if (!d || !(d.model || d.appVersion)) return null;
  return {
    phone: [d.brand || d.manufacturer, d.model].filter(Boolean).join(' '),
    android: d.sdkInt ? (ANDROID_VERSIONS[d.sdkInt] || `SDK ${d.sdkInt}`) : '',
    appVersion: d.appVersion || '',
    dialer: d.dialerPackage || '',
    accessibilityEnabled: typeof d.accessibilityEnabled === 'boolean' ? d.accessibilityEnabled : null,
    reportedAt: d.reportedAt || d.callProcessedAt || fallbackAt || null,
  };
}

/** Overall verdict and its reasons, in plain words. */
function healthVerdict(a) {
  const problems = [];
  const warnings = [];
  if (!a.autoRecordEnabled) problems.push('Call recording is switched off in the app');
  if (a.recordedPercent !== null) {
    if (a.connectedCalls >= 3 && a.recordedPercent < 50) problems.push(`Only ${a.recordedPercent}% of connected calls were recorded`);
    else if (a.recordedPercent < 90) warnings.push(`${a.recordedPercent}% of connected calls were recorded`);
  }
  if (a.issues.lost >= 3) problems.push(`${a.issues.lost} calls were not recorded at all`);
  else if (a.issues.lost > 0) warnings.push(`${a.issues.lost} call(s) were not recorded`);
  if (a.micOnly > 0) warnings.push(`${a.micOnly} recording(s) from the app's microphone: the customer's voice may be missing`);
  if (a.oldAppSeenAt) warnings.push('Uses an old app version without logging in: update the app');
  if (!a.device && a.connectedCalls > 0) warnings.push('The phone has not reported its recording setup yet');
  if (a.device && a.device.accessibilityEnabled === false && a.micOnly > 0) {
    warnings.push('"AskEVA Call Recording" is off in Accessibility');
  }
  if (problems.length) return { status: 'problem', statusReasons: [...problems, ...warnings] };
  if (warnings.length) return { status: 'warning', statusReasons: warnings };
  return { status: 'ok', statusReasons: a.connectedCalls === 0 && a.recordings === 0 ? ['No connected calls in this period'] : [] };
}

// GET /api/admin/phone-health?days=1|7|30&callerIds=&employeeType=  (admins / managers)
router.get('/api/admin/phone-health', async (req, res) => {
  try {
    const days = [1, 7, 30].includes(Number(req.query.days)) ? Number(req.query.days) : 7;
    const since = healthSince(days);
    const isAdmin = req.user && req.user.role === 'admin';
    const extra = isAdmin ? { legacyGraceEnabled: legacyGraceEnabled() } : {};

    const scope = await resolveScope(req, req.query);
    const people = scope.empty ? [] : scope.employees.filter(e => e && e.id && e.role !== 'admin');
    const ids = people.map(e => e.id);

    const [calls, recs, issues, latestIssueDevices, oldApp, profiles] = ids.length ? await Promise.all([
      CallLog.aggregate([
        { $match: { callerId: { $in: ids }, timestamp: { $gte: since }, durationSeconds: { $gte: HEALTH_MIN_TALK_SECONDS } } },
        { $group: {
          _id: '$callerId',
          connected: { $sum: 1 },
          recorded: { $sum: { $cond: [{ $gt: [{ $strLenCP: { $ifNull: ['$recordingId', ''] } }, 0] }, 1, 0] } },
        } },
      ]),
      Recording.aggregate([
        { $match: { callerId: { $in: ids }, $or: [{ callStartedAt: { $gte: since } }, { callStartedAt: null, createdAt: { $gte: since } }] } },
        { $group: {
          _id: '$callerId',
          total: { $sum: 1 },
          builtin: { $sum: { $cond: [{ $eq: ['$captureSource', 'builtin'] }, 1, 0] } },
          mic: { $sum: { $cond: [{ $eq: ['$captureSource', 'mic'] }, 1, 0] } },
          last: { $max: { $ifNull: ['$callStartedAt', '$createdAt'] } },
        } },
      ]),
      RecordingIssue.aggregate([
        { $match: { callerId: { $in: ids }, createdAt: { $gte: since } } },
        { $group: {
          _id: '$callerId',
          lost: { $sum: { $cond: [{ $eq: ['$kind', 'lost'] }, 1, 0] } },
          micOnly: { $sum: { $cond: [{ $eq: ['$kind', 'mic_only'] }, 1, 0] } },
        } },
      ]),
      // Phones that reported before device details were stored on the account: their latest problem report
      RecordingIssue.aggregate([
        { $match: { callerId: { $in: ids } } },
        { $sort: { createdAt: -1 } },
        { $group: { _id: '$callerId', doc: { $first: '$$ROOT' } } },
      ]),
      LegacyClientHit.find({ employeeId: { $in: ids }, lastSeenAt: { $gte: since } }).lean(),
      Employee.find({ id: { $in: ids } }).select('id deviceInfo').lean(),
    ]) : [[], [], [], [], [], []];

    const byId = (rows) => new Map(rows.map(r => [r._id, r]));
    const callsBy = byId(calls);
    const recsBy = byId(recs);
    const issuesBy = byId(issues);
    const issueDeviceBy = new Map(latestIssueDevices.map(r => [r._id, r.doc]));
    const oldAppBy = new Map(oldApp.map(h => [h.employeeId, h]));
    const deviceBy = new Map(profiles.map(p => [p.id, p.deviceInfo]));

    const agents = [];
    for (const e of people) {
      const c = callsBy.get(e.id) || { connected: 0, recorded: 0 };
      const r = recsBy.get(e.id) || { total: 0, builtin: 0, mic: 0, last: null };
      const i = issuesBy.get(e.id) || { lost: 0, micOnly: 0 };
      // Managers appear only when they made calls (e.g. a team leader in caller mode)
      if (e.role !== 'caller' && c.connected === 0 && r.total === 0 && i.lost === 0 && i.micOnly === 0) continue;
      const fromIssue = issueDeviceBy.get(e.id);
      const agent = {
        id: e.id,
        name: e.name,
        phone: e.phone || '',
        role: e.role || 'caller',
        team: e.team || '',
        managerName: e.managerName || '',
        online: isOnline(e),
        lastSeenAt: e.lastSeenAt || null,
        autoRecordEnabled: e.autoRecordEnabled !== false,
        connectedCalls: c.connected,
        recordedCalls: Math.min(c.recorded, c.connected),
        recordedPercent: c.connected > 0 ? Math.round((Math.min(c.recorded, c.connected) / c.connected) * 100) : null,
        recordings: r.total,
        phoneRecorder: r.builtin,
        micOnly: r.mic,
        lastRecordingAt: r.last || null,
        issues: { lost: i.lost, micOnly: i.micOnly },
        device: deviceDTO(deviceBy.get(e.id)) || deviceDTO(fromIssue, fromIssue && fromIssue.createdAt),
        oldAppSeenAt: oldAppBy.has(e.id) ? oldAppBy.get(e.id).lastSeenAt : null,
      };
      agents.push({ ...agent, ...healthVerdict(agent) });
    }
    const order = { problem: 0, warning: 1, ok: 2 };
    agents.sort((a, b) => order[a.status] - order[b.status] || String(a.name).localeCompare(String(b.name)));

    if (isAdmin) {
      // Every old-app (no login) device seen in the last 30 days, including ones that matched no user
      const hits = await LegacyClientHit.find({ lastSeenAt: { $gte: new Date(Date.now() - 30 * 86400000) } })
        .sort({ lastSeenAt: -1 }).limit(200).lean();
      extra.oldAppClients = hits.map(h => ({ name: h.name || '', phone: h.phone || '', lastSeenAt: h.lastSeenAt, requests: h.requests || 0 }));
    }

    res.json({ success: true, days, since: since.toISOString(), ...extra, agents });
  } catch (err) {
    console.error('phone health error:', err.message);
    res.status(500).json({ success: false, message: 'Could not load phone health' });
  }
});

module.exports = router;
module.exports.issueOf = issueOf;
module.exports.healthVerdict = healthVerdict;
module.exports.healthSince = healthSince;
