const Employee = require('../models/Employee');
const { forgetProfile } = require('../middleware/auth');

const INACTIVE_ACCOUNT_DAYS = 10;
const TEN_DAYS_MS = INACTIVE_ACCOUNT_DAYS * 24 * 60 * 60 * 1000;

function lastActivityDate(emp) {
  const raw = emp && (emp.lastSeenAt || emp.lastLoginAt || emp.createdAt);
  if (!raw) return null;
  const d = new Date(raw);
  return Number.isNaN(d.getTime()) ? null : d;
}

/**
 * Returns true if a non-admin account has not been seen in the app for more than 10 days.
 */
function isInactiveOverTenDays(emp, now = Date.now()) {
  if (!emp || String(emp.role || '').toLowerCase() === 'admin') return false;
  const last = lastActivityDate(emp);
  if (!last) return false;
  return now - last.getTime() > TEN_DAYS_MS;
}

async function deactivateEmployee(emp, reason = 'Inactive for more than 10 days', io = null) {
  if (!emp || !emp.id) return null;
  const now = new Date();
  await Employee.updateOne(
    { id: emp.id },
    {
      $set: {
        isActive: false,
        isBlocked: true,
        deactivatedAt: emp.deactivatedAt || now,
        deactivationReason: reason,
        activeSessionId: null,
        appInForeground: false,
        loggedOutAt: now,
      },
    },
  );
  forgetProfile(emp.id);
  if (io) {
    io.to('admin:global').emit('userDeactivated', {
      userId: emp.id,
      name: emp.name,
      phone: emp.phone,
      reason,
      deactivatedAt: now,
    });
  }
  return now;
}

/**
 * Finds all active non-admin users whose lastSeenAt (or lastLoginAt / createdAt) is older than 10 days
 * and marks them deactivated & blocked in the database.
 */
async function sweepInactiveAccounts(io = null) {
  try {
    const cutoff = new Date(Date.now() - TEN_DAYS_MS);
    const candidates = await Employee.find({
      role: { $ne: 'admin' },
      isActive: { $ne: false },
      $or: [
        { lastSeenAt: { $ne: null, $lt: cutoff } },
        { lastSeenAt: null, lastLoginAt: { $ne: null, $lt: cutoff } },
        { lastSeenAt: null, lastLoginAt: null, createdAt: { $lt: cutoff } },
      ],
    }).select('id name phone role deactivatedAt').lean();

    for (const emp of candidates) {
      await deactivateEmployee(emp, 'Inactive for more than 10 days', io);
      console.info(`[account-inactivity] deactivated userId=${emp.id} name=${emp.name}`);
    }
    return candidates.length;
  } catch (err) {
    console.error(`[account-inactivity] sweep failed: ${err.message}`);
    return 0;
  }
}

let accountSweepInterval = null;

function startAccountInactivityChecker(io, intervalMs = 60 * 60 * 1000) {
  if (accountSweepInterval) clearInterval(accountSweepInterval);
  setTimeout(() => { sweepInactiveAccounts(io); }, 15000);
  accountSweepInterval = setInterval(() => { sweepInactiveAccounts(io); }, intervalMs);
  return accountSweepInterval;
}

module.exports = {
  INACTIVE_ACCOUNT_DAYS,
  TEN_DAYS_MS,
  isInactiveOverTenDays,
  deactivateEmployee,
  sweepInactiveAccounts,
  startAccountInactivityChecker,
};
