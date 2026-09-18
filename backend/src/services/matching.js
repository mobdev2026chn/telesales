// Pure matching / transition logic (no DB access) so it can be unit tested offline.
const { last10 } = require('../utils/common');

// A recording belongs to the call of the same caller + same number whose start is within 5 minutes.
const LINK_WINDOW_MS = 5 * 60 * 1000;

const ms = (d) => {
  if (d === undefined || d === null || d === '') return NaN;
  const t = d instanceof Date ? d.getTime() : new Date(d).getTime();
  return t;
};

// The time a recording's call started: the explicit callStartedAt, otherwise estimated as
// upload time minus duration (old app builds upload right after the call ends).
function recordingStartMs(rec) {
  const started = ms(rec && rec.callStartedAt);
  if (Number.isFinite(started)) return started;
  const created = ms(rec && rec.createdAt);
  if (!Number.isFinite(created)) return NaN;
  return created - Math.max(0, Number(rec.durationSeconds) || 0) * 1000;
}

// Picks the ONE call log a recording should be linked to: same customer number (last 10 digits),
// |timestamp - refMs| <= window, closest wins. Calls already linked to a different recording are skipped.
// `calls` must already be restricted to the recording's caller.
function pickClosestCall(calls, { phoneNumber, refMs, recordingId = null, windowMs = LINK_WINDOW_MS }) {
  const target = last10(phoneNumber);
  if (target.length < 8 || !Number.isFinite(refMs)) return null;
  let best = null;
  let bestGap = Infinity;
  for (const c of calls || []) {
    if (last10(c.phoneNumber) !== target) continue;
    if (c.recordingId && c.recordingId !== recordingId) continue;
    const gap = Math.abs(ms(c.timestamp) - refMs);
    if (!(gap <= windowMs)) continue;
    if (gap < bestGap) { best = c; bestGap = gap; }
  }
  return best;
}

// For a batch of newly stored calls, assigns each unlinked recording to at most one call and each call
// to at most one recording (closest pairs first). Returns [{ call, recording }].
function pairCallsWithRecordings(calls, recordings, windowMs = LINK_WINDOW_MS) {
  const candidates = [];
  for (const call of calls || []) {
    const num = last10(call.phoneNumber);
    if (num.length < 8) continue;
    const t = ms(call.timestamp);
    if (!Number.isFinite(t)) continue;
    for (const rec of recordings || []) {
      if (last10(rec.phoneNumber) !== num) continue;
      const gap = Math.abs(recordingStartMs(rec) - t);
      if (gap <= windowMs) candidates.push({ call, rec, gap });
    }
  }
  candidates.sort((a, b) => a.gap - b.gap);
  const usedCalls = new Set();
  const usedRecs = new Set();
  const pairs = [];
  for (const { call, rec } of candidates) {
    if (usedCalls.has(call) || usedRecs.has(rec)) continue;
    usedCalls.add(call);
    usedRecs.add(rec);
    pairs.push({ call, recording: rec });
  }
  return pairs;
}

// ---- Leads -------------------------------------------------------------------------------------
const LEAD_STATUSES = ['new', 'followUp', 'bookDemo', 'demoReschedule', 'demoDone', 'newFollowUp', 'notPickup',
  'busyOnCall', 'renewalFollowUp', 'interested', 'warned', 'lost', 'won', 'notInterested', 'other'];
const TERMINAL_STATUSES = ['won', 'lost', 'notInterested'];
// Statuses the system may move automatically (only forward, only from these)
const AUTO_MOVABLE = ['new', 'followUp', 'notPickup'];

// Status for a lead created automatically from a call.
function initialLeadStatus({ connected, type }) {
  if (connected) return 'interested';
  if (type === 'missed' || type === 'rejected' || type === 'neverAttended') return 'notPickup';
  return 'followUp';
}

// Automatic status change caused by a call (sync or recording upload). Terminal and manual statuses are
// never changed; new/followUp/notPickup move to interested on a connected call. `new` moves to notPickup
// on an unanswered call.
function nextAutoStatus(current, { connected, type }) {
  const cur = current || 'new';
  if (!AUTO_MOVABLE.includes(cur)) return cur;
  if (connected) return 'interested';
  if (cur === 'new' && (type === 'missed' || type === 'rejected' || type === 'neverAttended')) return 'notPickup';
  return cur;
}

// ---- Calls -------------------------------------------------------------------------------------
const CALL_TYPES = ['incoming', 'outgoing', 'missed', 'rejected', 'neverAttended'];
function normalizeCallType(type) {
  const t = String(type || '').trim();
  if (CALL_TYPES.includes(t)) return t;
  const l = t.toLowerCase();
  if (l === 'incoming' || l === 'inbound') return 'incoming';
  if (l === 'outgoing' || l === 'outbound') return 'outgoing';
  if (l === 'missed') return 'missed';
  if (l === 'rejected' || l === 'blocked' || l === 'declined') return 'rejected';
  if (l === 'neverattended') return 'neverAttended';
  return 'outgoing';
}

// New dedupe key: stable employee id + number + exact timestamp.
function buildDedupKeyById(employeeId, phoneNumber, timestamp) {
  const target = last10(phoneNumber) || String(phoneNumber || '').trim();
  return `id:${employeeId}_${target}_${new Date(timestamp).getTime()}`;
}
// Old key (rows stored before the id-based key): caller phone + number + timestamp.
function buildDedupKey(callerPhone, phoneNumber, timestamp) {
  const target = last10(phoneNumber) || String(phoneNumber || '').trim();
  return `${last10(callerPhone)}_${target}_${new Date(timestamp).getTime()}`;
}

// ---- HTTP Range ---------------------------------------------------------------------------------
// Returns undefined when there is no Range header, null when it is unsatisfiable/invalid (-> 416),
// otherwise { start, end } (inclusive). Only the first range of a multi-range request is served.
function parseRange(header, size) {
  if (header === undefined || header === null || header === '') return undefined;
  const m = /^bytes=\s*(\d*)\s*-\s*(\d*)\s*(?:,.*)?$/i.exec(String(header).trim());
  if (!m || size <= 0) return null;
  const [, a, b] = m;
  let start;
  let end;
  if (a === '' && b === '') return null;
  if (a === '') {
    // Suffix range: the last N bytes
    const n = parseInt(b, 10);
    if (!(n > 0)) return null;
    start = Math.max(0, size - n);
    end = size - 1;
  } else {
    start = parseInt(a, 10);
    end = b === '' ? size - 1 : Math.min(parseInt(b, 10), size - 1);
  }
  if (!Number.isFinite(start) || !Number.isFinite(end) || start >= size || start > end) return null;
  return { start, end };
}

module.exports = {
  LINK_WINDOW_MS,
  recordingStartMs,
  pickClosestCall,
  pairCallsWithRecordings,
  LEAD_STATUSES,
  TERMINAL_STATUSES,
  AUTO_MOVABLE,
  initialLeadStatus,
  nextAutoStatus,
  CALL_TYPES,
  normalizeCallType,
  buildDedupKeyById,
  buildDedupKey,
  parseRange,
};
