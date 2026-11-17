const Employee = require('../models/Employee');
const CallLog = require('../models/CallLog');
const Notification = require('../models/Notification');
const { isOnline, breakInfo } = require('./presence');
const { employeeRoom } = require('./realtime');

// 15 minutes inactivity threshold
const INACTIVITY_THRESHOLD_MS = 15 * 60 * 1000;
// 15 minutes cooldown between alerts for the same caller
const ALERT_COOLDOWN_MS = 15 * 60 * 1000;

// Track last alert timestamp per callerId in-memory: callerId -> timestamp
const lastAlertMap = new Map();

/**
 * Checks active callers for 15+ minutes of inactivity (no call made or answered).
 * If inactive, creates notifications for Admin & Caller and emits realtime events.
 */
async function checkCallerInactivity(io) {
  try {
    const now = Date.now();

    // Query active callers who have logged in
    const callers = await Employee.find({
      role: 'caller',
      lastLoginAt: { $ne: null },
    }).lean();

    const alertsGenerated = [];

    for (const caller of callers) {
      const online = isOnline(caller);
      const loginTime = caller.lastLoginAt ? new Date(caller.lastLoginAt).getTime() : 0;
      const logoutTime = caller.loggedOutAt ? new Date(caller.loggedOutAt).getTime() : 0;
      const isLoggedOut = logoutTime > 0 && logoutTime >= loginTime;

      // Skip callers who are explicitly logged out or haven't logged in recently
      if (!online && isLoggedOut) continue;
      if (now - loginTime > 24 * 60 * 60 * 1000 && !online) continue;

      // Skip callers currently on an official break (Lunch / Tea break)
      const bInfo = breakInfo(caller, now);
      if (bInfo && bInfo.onBreak) continue;

      // Find the caller's most recent call
      const callerQuery = [];
      if (caller.id) callerQuery.push({ callerId: caller.id });
      if (caller.phone) callerQuery.push({ callerPhone: caller.phone });
      if (!callerQuery.length) continue;

      const latestCall = await CallLog.findOne({ $or: callerQuery })
        .sort({ timestamp: -1 })
        .lean();

      let lastActiveTime = loginTime;
      if (latestCall && latestCall.timestamp) {
        const callStart = new Date(latestCall.timestamp).getTime();
        const durationMs = Math.max(0, latestCall.durationSeconds || 0) * 1000;
        const callEnd = callStart + durationMs;
        lastActiveTime = Math.max(lastActiveTime, callEnd);
      }

      const inactiveMs = now - lastActiveTime;
      if (inactiveMs < INACTIVITY_THRESHOLD_MS) {
        continue;
      }

      // Check alert cooldown
      const lastAlert = lastAlertMap.get(caller.id) || 0;
      if (now - lastAlert < ALERT_COOLDOWN_MS) {
        continue;
      }

      // Set cooldown
      lastAlertMap.set(caller.id, now);

      const inactiveMinutes = Math.floor(inactiveMs / (60 * 1000));
      const timeStr = new Date(lastActiveTime).toLocaleTimeString('en-US', { timeZone: 'Asia/Kolkata' });

      // 1. Create Admin Notification
      const adminNotifId = `notif_inact_admin_${Date.now()}_${Math.random().toString(36).substring(2, 7)}`;
      const adminNotif = await Notification.create({
        id: adminNotifId,
        recipientId: 'ADMIN',
        senderName: caller.name,
        senderRole: 'caller',
        title: `Caller Inactivity Alert (${inactiveMinutes}m)`,
        message: `Caller ${caller.name} (${caller.phone || 'No Phone'}) has not spoken in any call for ${inactiveMinutes} minutes.`,
        comment: `Last call activity at ${timeStr} IST`,
        isRead: false,
      });

      // 2. Create Caller Notification
      const callerNotifId = `notif_inact_caller_${Date.now()}_${Math.random().toString(36).substring(2, 7)}`;
      const callerNotif = await Notification.create({
        id: callerNotifId,
        recipientId: caller.id,
        recipientPhone: caller.phone || '',
        recipientName: caller.name || '',
        senderName: 'System',
        senderRole: 'system',
        title: 'Inactivity Alert',
        message: `You have been inactive for ${inactiveMinutes} minutes without any call. Please check your assigned leads and resume calling.`,
        comment: `No call activity detected since ${timeStr} IST`,
        isRead: false,
      });

      // 3. Emit Realtime alerts
      if (io) {
        const adminPayload = adminNotif.toObject ? adminNotif.toObject() : adminNotif;
        const callerPayload = callerNotif.toObject ? callerNotif.toObject() : callerNotif;

        // Emit to admin
        io.to('admin:global').emit('callerInactivityAlert', {
          callerId: caller.id,
          callerName: caller.name,
          callerPhone: caller.phone,
          inactiveMinutes,
          notification: adminPayload,
        });
        io.to('admin:global').emit('notificationCreated', adminPayload);

        // Emit to caller room
        const room = employeeRoom(caller.id);
        io.to(room).emit('callerInactivityAlert', {
          callerId: caller.id,
          inactiveMinutes,
          notification: callerPayload,
          message: `You have been inactive for ${inactiveMinutes} minutes without any call.`,
        });
        io.to(room).emit('notificationCreated', callerPayload);
      }

      alertsGenerated.push({ callerId: caller.id, inactiveMinutes, adminNotif, callerNotif });
      console.info(`[inactivity] alerted callerId=${caller.id} inactiveMinutes=${inactiveMinutes}`);
    }

    return alertsGenerated;
  } catch (err) {
    console.error(`[inactivity] check failed: ${err.message}`);
    return [];
  }
}

let checkerInterval = null;

function startInactivityChecker(io, intervalMs = 60000) {
  if (checkerInterval) clearInterval(checkerInterval);

  // Run initial check after 10s delay to let server settle
  const initialTimeout = setTimeout(() => {
    checkCallerInactivity(io);
  }, 10000);

  checkerInterval = setInterval(() => {
    checkCallerInactivity(io);
  }, intervalMs);

  return { checkerInterval, initialTimeout };
}

function stopInactivityChecker() {
  if (checkerInterval) {
    clearInterval(checkerInterval);
    checkerInterval = null;
  }
}

module.exports = {
  checkCallerInactivity,
  startInactivityChecker,
  stopInactivityChecker,
  INACTIVITY_THRESHOLD_MS,
  ALERT_COOLDOWN_MS,
  lastAlertMap,
};
