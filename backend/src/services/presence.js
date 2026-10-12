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

  const updateFields = {
    appInForeground: isForeground,
    presenceUpdatedAt: now,
  };
  if (isForeground) {
    updateFields.loggedOutAt = null;
  }

  const result = await Employee.collection.updateOne(
    {
      id: userId,
      ...(sessionId ? { activeSessionId: sessionId } : {}),
    },
    {
      $set: updateFields,
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
  if (!emp) return false;

  const now = Date.now();
  const presenceTime = emp.presenceUpdatedAt ? new Date(emp.presenceUpdatedAt).getTime() : 0;
  const loginTime = emp.lastLoginAt ? new Date(emp.lastLoginAt).getTime() : 0;
  const logoutTime = emp.loggedOutAt ? new Date(emp.loggedOutAt).getTime() : 0;

  // Explicit logout newer than both login and presence heartbeat means offline
  if (logoutTime > 0 && logoutTime >= loginTime && logoutTime >= presenceTime) {
    return false;
  }

  // Active heartbeat within the last 3 minutes
  if (presenceTime > 0 && (now - presenceTime) < 3 * 60 * 1000) {
    return emp.appInForeground !== false;
  }

  // Foreground state when recently updated
  if (typeof emp.appInForeground === 'boolean') {
    if (emp.appInForeground && presenceTime > 0 && (now - presenceTime) < 5 * 60 * 1000) {
      return true;
    }
    if (!emp.appInForeground) {
      return false;
    }
  }

  // Recent login within 15 minutes if no subsequent logout
  if (loginTime > 0 && (now - loginTime) < 15 * 60 * 1000) {
    return true;
  }

  return false;
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