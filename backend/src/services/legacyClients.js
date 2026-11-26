// Notes every request that an old app build makes without logging in (LEGACY_CLIENT_GRACE), so the
// Phone health page can show who still has to update before that access is switched off.
// Never blocks or fails the request: written in the background, at most once per person every
// few minutes (counts in between are added to the next write).
const LegacyClientHit = require('../models/LegacyClientHit');
const { findEmployeeByRef } = require('./scope');

const WRITE_EVERY_MS = 5 * 60 * 1000;
const pending = new Map(); // ref key -> { count, lastWriteAt, path, userAgent }

function refsOf(req) {
  const q = req.query || {};
  const b = req.body && typeof req.body === 'object' && !Array.isArray(req.body) ? req.body : {};
  return [q.loggedInUserId, q.userId, q.callerId, q.callerPhone, q.phone, q.callerName, q.name,
    b.loggedInUserId, b.userId, b.callerId, b.callerPhone, b.phone, b.callerName, b.name]
    .filter(v => typeof v === 'string' && v.trim())
    .map(v => v.trim().slice(0, 80));
}

async function write(refs, req, count) {
  let emp = null;
  for (const ref of refs.slice(0, 4)) {
    emp = await findEmployeeByRef(ref);
    if (emp) break;
  }
  const key = emp ? emp.id : `unknown:${refs[0] || req.ip || 'device'}`;
  await LegacyClientHit.updateOne(
    { key },
    {
      $set: {
        employeeId: emp ? emp.id : '',
        name: emp ? emp.name : (refs.find(r => !/\d{7,}/.test(r)) || ''),
        phone: emp ? (emp.phone || '') : (refs.find(r => /\d{7,}/.test(r)) || ''),
        lastPath: String(req.path || '').slice(0, 120),
        userAgent: String(req.headers['user-agent'] || '').slice(0, 160),
        lastSeenAt: new Date(),
      },
      $inc: { requests: count },
      $setOnInsert: { firstSeenAt: new Date() },
    },
    { upsert: true }
  );
}

function noteLegacyRequest(req) {
  try {
    const refs = refsOf(req);
    const memKey = refs[0] || `ip:${req.ip || ''}`;
    const now = Date.now();
    const entry = pending.get(memKey) || { count: 0, lastWriteAt: 0 };
    entry.count += 1;
    pending.set(memKey, entry);
    if (pending.size > 2000) pending.delete(pending.keys().next().value);
    if (now - entry.lastWriteAt < WRITE_EVERY_MS) return;
    const count = entry.count;
    entry.count = 0;
    entry.lastWriteAt = now;
    write(refs, req, count).catch(err => console.warn('[legacy] could not note old-app request:', err.message));
  } catch (_) {
    // never affects the request
  }
}

module.exports = { noteLegacyRequest };
