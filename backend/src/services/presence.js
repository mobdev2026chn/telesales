//  Online presence is based on the most recent explicit login and logout timestamps.
const Employee = require('../models/Employee');

const MAX_BREAK_MS = 4 * 60 * 60 * 1000;

// Match the correct employee and, when supplied, the active session.
function sessionFilter(userId, sessionId) {
  return {
    id: userId,
    ...(sessionId
      ? { activeSessionId: sessionId }
      : { activeSessionId: { $in: [null] } }),
  };
}

// Successful login.
async function markSignedIn(userId, sessionId) {
  if (!userId) return false;

  const now = new Date();

  const result = await Employee.collection.updateOne(
    { id: userId },
    {
      $set: {
        lastLoginAt: now,
        loggedOutAt: null,
        activeSessionId: sessionId || null,
        appInForeground: true,
        presenceUpdatedAt: now,
      },
    }
  );

  if (result.matchedCount === 0) {
    throw new Error(
      `Cannot record login for missing employee userId=${userId}`
    );
  }

  return now;
}

// Update whether the Telesales app is in the foreground.
// Call this from an authenticated API endpoint.
async function updateAppPresence(userId, sessionId, isForeground) {
  if (!userId || typeof isForeground !== 'boolean') {
    return false;
  }

  const now = new Date();

  const result = await Employee.collection.updateOne(
    {
      id: userId,
      ...(sessionId ? { activeSessionId: sessionId } : {}),
      loggedOutAt: null,
    },
    {
      $set: {
        appInForeground: isForeground,
        presenceUpdatedAt: now,
      },
    }
  );

  return result.matchedCount > 0;
}

// Explicit logout.
async function markLoggedOut(
  userId,
  sessionId = null,
  tokenIssuedAt = null
) {
  if (!userId) return false;

  const now = new Date();
  const filter = sessionFilter(userId, sessionId);

  if (!sessionId && Number.isFinite(tokenIssuedAt)) {
    filter.$or = [
      { lastLoginAt: null },
      { lastLoginAt: { $lte: new Date(tokenIssuedAt + 999) } },
    ];
  }

  const result = await Employee.collection.updateOne(
    filter,
    {
      $set: {
        loggedOutAt: now,
        appInForeground: false,
        presenceUpdatedAt: now,
      },
    }
  );

  if (result.matchedCount === 0) {
    const exists = await Employee.exists({ id: userId });

    if (!exists) {
      throw new Error(
        `Cannot record logout for missing employee userId=${userId}`
      );
    }

    return false;
  }

  return now;
}

// Current app presence.
// Explicit logout always means offline.
function isOnline(emp) {
  if (!emp || !emp.lastLoginAt) return false;

  const loginTime = new Date(emp.lastLoginAt).getTime();

  if (!Number.isFinite(loginTime)) return false;

  if (emp.loggedOutAt) {
    const logoutTime = new Date(emp.loggedOutAt).getTime();

    if (Number.isFinite(logoutTime) && logoutTime >= loginTime) {
      return false;
    }
  }

  // Use foreground state when available.
  // Legacy records without this field retain timestamp-based behavior.
  if (typeof emp.appInForeground === 'boolean') {
    return emp.appInForeground;
  }

  return true;
}

// Break status.
function breakInfo(emp, now = Date.now()) {
  if (!emp || !emp.breakStartedAt) {
    return {
      onBreak: false,
      breakType: '',
      breakStartedAt: null,
    };
  }

  const started = new Date(emp.breakStartedAt).getTime();

  const stale =
    !Number.isFinite(started) ||
    now - started > MAX_BREAK_MS ||
    (emp.loggedOutAt &&
      new Date(emp.loggedOutAt).getTime() > started);

  if (stale) {
    return {
      onBreak: false,
      breakType: '',
      breakStartedAt: null,
    };
  }

  return {
    onBreak: true,
    breakType: emp.breakType || 'Break',
    breakStartedAt: new Date(started).toISOString(),
  };
}

module.exports = {
  markSignedIn,
  markLoggedOut,
  updateAppPresence,
  isOnline,
  breakInfo,
  MAX_BREAK_MS,
};