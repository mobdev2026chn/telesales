// Online / offline presence. A user is ONLINE when a signed-in request from them arrived within
// ONLINE_WINDOW_MS and they have not logged out since. The app sends an authenticated heartbeat
// while active; a phone that is switched off, loses its session or has the app killed turns offline
// after the window.
const Employee = require('../models/Employee');

const ONLINE_WINDOW_MS = 5 * 60 * 1000;
const TOUCH_EVERY_MS = 30 * 1000; // at most one write per user per 30 s

const lastWrite = new Map(); // userId -> ms of the last lastSeenAt write

function touch(userId, force = false) {
  if (!userId) return;
  const now = Date.now();
  if (!force && now - (lastWrite.get(userId) || 0) < TOUCH_EVERY_MS) return;
  lastWrite.set(userId, now);
  Employee.updateOne({ id: userId }, { $set: { lastSeenAt: new Date(now) } }, { timestamps: false })
    .catch(() => lastWrite.delete(userId));
}

function markSignedIn(userId) {
  if (!userId) return;
  const now = new Date(Date.now() + 1);
  lastWrite.set(userId, now.getTime());
  Employee.updateOne(
    { id: userId },
    { $set: { lastSeenAt: now, socketConnected: null } },
    { timestamps: false },
  ).catch((err) => {
    lastWrite.delete(userId);
    console.error(`[presence] login timestamp update failed userId=${userId}: ${err.message}`);
  });
}

async function socketConnected(userId) {
  if (!userId) return null;
  const now = new Date(Date.now() + 1);
  lastWrite.set(userId, now.getTime());
  return Employee.updateOne(
    { id: userId },
    { $set: { lastSeenAt: now, socketConnected: true } },
    { timestamps: false },
  );
}

async function socketDisconnected(userId) {
  if (!userId) return null;
  const now = new Date();
  lastWrite.set(userId, now.getTime());
  return Employee.updateOne(
    { id: userId },
    { $set: { lastSeenAt: now, loggedOutAt: now, socketConnected: false } },
    { timestamps: false },
  );
}

async function markLoggedOut(userId) {
  if (!userId) return;
  lastWrite.delete(userId);
  // Logging out also ends any break
  await Employee.updateOne(
    { id: userId },
    { $set: { loggedOutAt: new Date(), socketConnected: false, breakType: '', breakStartedAt: null } },
    { timestamps: false },
  );
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

function isOnline(emp, now = Date.now()) {
  if (!emp || !emp.lastSeenAt) return false;
  if (emp.socketConnected === false) return false;
  const seen = new Date(emp.lastSeenAt).getTime();
  if (now - seen > ONLINE_WINDOW_MS) return false;
  return !emp.loggedOutAt || seen > new Date(emp.loggedOutAt).getTime();
}

module.exports = {
  touch,
  markSignedIn,
  socketConnected,
  socketDisconnected,
  markLoggedOut,
  isOnline,
  breakInfo,
  ONLINE_WINDOW_MS,
  MAX_BREAK_MS,
};
