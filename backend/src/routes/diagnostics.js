const express = require('express');
const fs = require('fs');
const path = require('path');

const router = express.Router();

// Per-call recording diagnostics from the app (no audio, no customer numbers): which mic source was
// used, how much speech it heard, accessibility state, phone model. Used to support phones whose
// recordings come out silent. Stored as JSON lines in backend/logs/recording-diagnostics.jsonl.
const LOG_DIR = path.join(__dirname, '../../logs');
const LOG_FILE = path.join(LOG_DIR, 'recording-diagnostics.jsonl');
const MAX_ITEMS = 50;
const MAX_FILE_BYTES = 5 * 1024 * 1024;

const ALLOWED_KEYS = new Set([
  'at', 'manufacturer', 'brand', 'model', 'sdkInt', 'dialerPackage', 'accessibilityEnabled',
  'source', 'sourceName', 'sourceMode', 'recordedSeconds', 'voicedSeconds', 'peak', 'talkSeconds',
  'result', 'builtInFound', 'uploadedOwn', 'appVersion', 'note',
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

// POST /api/diagnostics/recording  { items: [ {...}, ... ] }  (any signed-in user)
router.post('/api/diagnostics/recording', (req, res) => {
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
    const lines = items.map(item => JSON.stringify({
      receivedAt: new Date().toISOString(),
      userId: user.id || null,
      userName: user.name || null,
      ...clean(item),
    }));
    fs.appendFileSync(LOG_FILE, lines.join('\n') + '\n');
    res.json({ success: true, stored: lines.length });
  } catch (err) {
    console.error('diagnostics error:', err.message);
    res.status(500).json({ success: false, message: 'Could not store diagnostics' });
  }
});

module.exports = router;
