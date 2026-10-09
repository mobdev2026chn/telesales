// Online presence is based on the most recent explicit login and logout timestamps.
const Employee = require('../models/Employee');

function sessionFilter(userId, sessionId) {
  return {
    id: userId,
    ...(sessionId ? { activeSessionId: sessionId } : { activeSessionId: { $in: [null] } }),
  };
}

async function markSignedIn(userId, sessionId) {
  if (!userId) return;
  const now = new Date();
  const result = await Employee.collection.updateOne(
    { id: userId },
    {
      $set: {
        lastLoginAt: now,
        loggedOutAt: null,
        activeSessionId: sessionId,
      },
      // $unset: { lastSeenAt: 1 },
    },
  );
  if (result.matchedCount === 0) {
    throw new Error(`Cannot record login for missing employee userId=${userId}`);
  }
  return now;
}

async function markLoggedOut(userId, sessionId = null, tokenIssuedAt = null) {
  if (!userId) return false;
  const now = new Date();
  const filter = sessionFilter(userId, sessionId);
  if (!sessionId && Number.isFinite(tokenIssuedAt)) {
    filter.$or = [
      { lastLoginAt: null },
      { lastLoginAt: { $lte: new Date(tokenIssuedAt + 999) } },
    ];
  }
  // Logging out also ends any break
  const result = await Employee.collection.updateOne(
    filter,
    {
      $set: {
        loggedOutAt: now,
      },
      // $unset: { activeSessionId: 1, lastSeenAt: 1 },
    },
  );
  if (result.matchedCount === 0) {
    const exists = await Employee.exists({ id: userId });
    if (!exists) throw new Error(`Cannot record logout for missing employee userId=${userId}`);
    return false;
  }
  return now;
}

// A break shown on the portal: started from the app, not older than MAX_BREAK_MS (a phone that
// never sent "break over" does not stay on break forever) and not ended by a logout.
const MAX_BREAK_MS = 4 * 60 * 60 * 1000;
function breakInfo(emp, now = Date.now()) {
  if (!emp || !emp.breakStartedAt) return { onBreak: false, breakType: '', breakStartedAt: null };
  const started = new Date(emp.breakStartedAt).getTime();
  const stale = !Number.isFinite(started) || now - started > MAX_BREAK_MS ||
    (emp.loggedOutAt && new Date(emp.loggedOutAt).getTime() > started);
  if (stale) return { onBreak: false, breakType: '', breakStartedAt: null };
  return { onBreak: true, breakType: emp.breakType || 'Break', breakStartedAt: new Date(started).toISOString() };
}

function isOnline(emp) {
  if (!emp || !emp.lastLoginAt) return false;
  const loggedInAt = new Date(emp.lastLoginAt).getTime();
  if (!Number.isFinite(loggedInAt)) return false;
  if (!emp.loggedOutAt) return true;
  const loggedOutAt = new Date(emp.loggedOutAt).getTime();
  return !Number.isFinite(loggedOutAt) || loggedInAt > loggedOutAt;
}

module.exports = {
  markSignedIn,
  markLoggedOut,
  isOnline,
  breakInfo,
  MAX_BREAK_MS,
};
