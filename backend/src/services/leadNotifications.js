const Notification = require('../models/Notification');
const Employee = require('../models/Employee');
const { publishForEmployee } = require('./realtime');

/**
 * Creates notifications for Admin and Caller when a lead status / follow-up / interest is updated,
 * and emits real-time events through Socket.IO.
 */
async function sendLeadStatusChangeNotification({
  req,
  lead,
  oldStatus,
  newStatus,
  user,
}) {
  if (!newStatus || oldStatus === newStatus) return null;

  try {
    const callerId = (user && user.id) || lead.assignedCallerId || '';
    let callerName = (user && user.name) || lead.assignedCaller || 'Caller';
    let callerPhone = (user && user.phone) || '';

    if (!callerPhone && callerId) {
      const emp = await Employee.findOne({ id: callerId }).select('id name phone').lean();
      if (emp) {
        if (!callerName || callerName === 'Caller') callerName = emp.name;
        callerPhone = emp.phone || '';
      }
    }

    const timeStr = new Date().toLocaleTimeString('en-US', { timeZone: 'Asia/Kolkata' });
    const leadDisplayName = lead.name || lead.phone || 'Lead';

    // 1. Create Admin Notification
    const adminNotifId = `notif_lead_${Date.now()}_${Math.random().toString(36).substring(2, 7)}`;
    const adminNotif = await Notification.create({
      id: adminNotifId,
      recipientId: 'ADMIN',
      senderName: callerName,
      senderRole: (user && user.role) || 'caller',
      contactName: leadDisplayName,
      title: `Lead Status: ${newStatus}`,
      message: `Caller ${callerName} changed lead "${leadDisplayName}" (${lead.phone || ''}) to "${newStatus}".`,
      comment: `Status changed from ${oldStatus || 'new'} to ${newStatus} at ${timeStr} IST`,
      isRead: false,
    });

    // 2. Create Caller Notification
    let callerNotif = null;
    if (callerId) {
      const callerNotifId = `notif_lead_caller_${Date.now()}_${Math.random().toString(36).substring(2, 7)}`;
      callerNotif = await Notification.create({
        id: callerNotifId,
        recipientId: callerId,
        recipientPhone: callerPhone,
        recipientName: callerName,
        senderName: 'System',
        senderRole: 'system',
        contactName: leadDisplayName,
        title: `Lead Updated: ${leadDisplayName}`,
        message: `Lead "${leadDisplayName}" status updated to "${newStatus}".`,
        comment: `Status: ${newStatus}`,
        isRead: false,
      });
    }

    // 3. Realtime Socket.IO broadcasts
    const io = req && req.app ? req.app.get('io') : null;
    if (io) {
      const adminPayload = adminNotif.toObject ? adminNotif.toObject() : adminNotif;
      io.to('admin:global').emit('leadNotification', adminPayload);
      io.to('admin:global').emit('notificationCreated', adminPayload);

      if (callerId && callerNotif) {
        const callerPayload = callerNotif.toObject ? callerNotif.toObject() : callerNotif;
        const targetEmp = { id: callerId };
        if (req) {
          try {
            await publishForEmployee(req, targetEmp, 'leadNotification', callerPayload);
            await publishForEmployee(req, targetEmp, 'notificationCreated', callerPayload);
          } catch {
            io.to(`employee:${callerId}`).emit('leadNotification', callerPayload);
            io.to(`employee:${callerId}`).emit('notificationCreated', callerPayload);
          }
        } else {
          io.to(`employee:${callerId}`).emit('leadNotification', callerPayload);
          io.to(`employee:${callerId}`).emit('notificationCreated', callerPayload);
        }
      }
    }

    return { adminNotif, callerNotif };
  } catch (err) {
    console.error(`[lead-notification] error creating lead change notification: ${err.message}`);
    return null;
  }
}

module.exports = {
  sendLeadStatusChangeNotification,
};
