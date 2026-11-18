const express = require('express');
const fs = require('fs');
const path = require('path');
const RecordingIssue = require('../models/RecordingIssue');
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

/** { kind, reason } for a call whose recording is missing or mic-only, null when it is fine. */
function issueOf(d) {
  const talk = Number(d.talkSeconds) || 0;
  const googleDialer = d.dialerPackage === 'com.google.android.dialer';
  const why = googleDialer
    ? 'The phone uses "Phone by Google", which keeps its recordings private'
    : "The phone's own call recording was not found (auto-record off, or no recorder on this phone)";
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

module.exports = router;
module.exports.issueOf = issueOf;
