// Online / offline presence. A user is ONLINE when a signed-in request from them arrived within
// ONLINE_WINDOW_MS and they have not logged out since. The app sends a heartbeat every 2 minutes
// while logged in (also in the background), so a phone that is switched off, loses its session or
// has the app killed turns offline after the window.
const Employee = require('../models/Employee');

const ONLINE_WINDOW_MS = 5 * 60 * 1000;
const TOUCH_EVERY_MS = 30 * 1000; // at most one write per user per 30 s

const lastWrite = new Map(); // userId -> ms of the last lastSeenAt write

function touch(userId) {
  if (!userId) return;
  const now = Date.now();
  if (now - (lastWrite.get(userId) || 0) < TOUCH_EVERY_MS) return;
  lastWrite.set(userId, now);
  Employee.updateOne({ id: userId }, { $set: { lastSeenAt: new Date(now) } }, { timestamps: false })
    .catch(() => lastWrite.delete(userId));
}

async function markLoggedOut(userId) {
  if (!userId) return;
  lastWrite.delete(userId);
  await Employee.updateOne({ id: userId }, { $set: { loggedOutAt: new Date() } }, { timestamps: false });
}

function isOnline(emp, now = Date.now()) {
  if (!emp || !emp.lastSeenAt) return false;
  const seen = new Date(emp.lastSeenAt).getTime();
  if (now - seen > ONLINE_WINDOW_MS) return false;
  return !emp.loggedOutAt || seen > new Date(emp.loggedOutAt).getTime();
}

module.exports = { touch, markLoggedOut, isOnline, ONLINE_WINDOW_MS };
