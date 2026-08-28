const express = require('express');
const router = express.Router();
const CallLog = require('../models/CallLog');
const Lead = require('../models/Lead');
const Recording = require('../models/Recording');
const Notification = require('../models/Notification');
const Employee = require('../models/Employee');

// 1. POST /api/user/calls/sync - Sync device call logs
router.post('/calls/sync', async (req, res) => {
  try {
    const { callerId, callerName, callerPhone, calls } = req.body;
    if (!Array.isArray(calls)) {
      return res.status(400).json({ success: false, message: 'Calls array is required' });
    }

    const inserted = [];
    for (const call of calls) {
      const log = await CallLog.create({
        callerId: callerId || 'caller_1',
        callerName: callerName || 'Caller Agent',
        callerPhone: callerPhone || '+91 98250 00000',
        contactName: call.contactName || 'Unknown',
        phoneNumber: call.phoneNumber,
        type: call.type || 'outgoing',
        timestamp: call.timestamp ? new Date(call.timestamp) : new Date(),
        durationSeconds: call.durationSeconds || 0,
        simSlot: call.simSlot || 1,
        note: call.note || '',
      });
      inserted.push(log);
    }

    res.json({
      success: true,
      syncedCount: inserted.length,
      message: `Successfully synchronized ${inserted.length} call logs with MongoDB`,
    });
  } catch (err) {
    res.status(500).json({ success: false, error: err.message });
  }
});

// 2. POST /api/user/recordings/upload - Save auto-recorded call audio
router.post('/recordings/upload', async (req, res) => {
  try {
    const { callerName, contactName, phoneNumber, durationSeconds, transcript, dateStr, timeStr } = req.body;

    const rec = await Recording.create({
      id: Date.now().toString(),
      callerName: callerName || 'Caller Agent',
      contactName: contactName || 'Client',
      phoneNumber: phoneNumber || '',
      durationSeconds: durationSeconds || 0,
      transcript: transcript || '“Call auto-recorded successfully”',
      dateStr: dateStr || 'Today',
      timeStr: timeStr || 'Now',
    });

    res.json({ success: true, recording: rec });
  } catch (err) {
    res.status(500).json({ success: false, error: err.message });
  }
});

// 3. GET /api/user/leads - Caller's assigned leads
router.get('/leads', async (req, res) => {
  try {
    const leads = await Lead.find().sort({ updatedAt: -1 });
    res.json({ success: true, count: leads.length, leads });
  } catch (err) {
    res.status(500).json({ success: false, error: err.message });
  }
});

// 4. PUT /api/user/leads/:id/status - Update lead pipeline status & notes
router.put('/leads/:id/status', async (req, res) => {
  try {
    const { status, notes, attempts } = req.body;
    const updateData = {};
    if (status) updateData.status = status;
    if (notes !== undefined) updateData.notes = notes;
    if (attempts !== undefined) updateData.attempts = attempts;
    updateData.lastCallDate = new Date();

    const lead = await Lead.findOneAndUpdate(
      { id: req.params.id },
      { $set: updateData },
      { new: true }
    );

    res.json({ success: true, lead });
  } catch (err) {
    res.status(500).json({ success: false, error: err.message });
  }
});

// 5. GET /api/user/notifications - Fetch notifications for caller
router.get('/notifications', async (req, res) => {
  try {
    const { phone, name } = req.query;
    let query = {};
    if (phone || name) {
      const orClauses = [];
      if (phone && phone.trim()) {
        const cleanPhone = phone.replace(/[^0-9]/g, '');
        const last10 = cleanPhone.length >= 10 ? cleanPhone.substring(cleanPhone.length - 10) : cleanPhone;
        orClauses.push(
          { recipientPhone: phone },
          { recipientPhone: new RegExp(last10 + '$') },
          { recipientPhone: new RegExp('^' + last10) }
        );
      }
      if (name && name.trim()) {
        const cleanName = name.trim().split(' ')[0];
        orClauses.push(
          { recipientName: new RegExp(`^${name.trim()}$`, 'i') },
          { recipientName: new RegExp(cleanName, 'i') }
        );
      }
      query = { $or: orClauses };
    }

    const notifications = await Notification.find(query).sort({ createdAt: -1 }).limit(50);
    const unreadCount = await Notification.countDocuments({ ...query, isRead: false });

    res.json({
      success: true,
      unreadCount,
      notifications,
    });
  } catch (err) {
    res.status(500).json({ success: false, error: err.message });
  }
});

// 6. POST /api/user/notifications/:id/read - Mark notification as read
router.post('/notifications/:id/read', async (req, res) => {
  try {
    const notif = await Notification.findOneAndUpdate(
      { id: req.params.id },
      { $set: { isRead: true } },
      { new: true }
    );
    res.json({ success: true, notification: notif });
  } catch (err) {
    res.status(500).json({ success: false, error: err.message });
  }
});

// 7. POST /api/user/notifications/read-all - Mark all notifications as read
router.post('/notifications/read-all', async (req, res) => {
  try {
    const { phone, name } = req.body;
    let query = {};
    if (phone || name) {
      const orClauses = [];
      if (phone) {
        const cleanPhone = phone.replace(/[^0-9]/g, '');
        const last10 = cleanPhone.length >= 10 ? cleanPhone.substring(cleanPhone.length - 10) : cleanPhone;
        orClauses.push({ recipientPhone: phone }, { recipientPhone: new RegExp(last10 + '$') });
      }
      if (name) {
        orClauses.push({ recipientName: new RegExp(`^${name}$`, 'i') });
      }
      query = { $or: orClauses };
    }

    await Notification.updateMany(query, { $set: { isRead: true } });
    res.json({ success: true, message: 'All notifications marked as read' });
  } catch (err) {
    res.status(500).json({ success: false, error: err.message });
  }
});

// 8. POST /api/user/contacts/save - Save or update contact name across leads, call logs, and recordings
router.post(['/contacts/save', '/leads/save-contact'], async (req, res) => {
  try {
    const { phoneNumber, name, notes } = req.body;
    if (!phoneNumber || !name) {
      return res.status(400).json({ success: false, message: 'phoneNumber and name are required' });
    }

    const cleanPhone = phoneNumber.replace(/[^0-9]/g, '').slice(-10);
    const phoneRegex = new RegExp(cleanPhone + '$');

    // 1. Update/Create in Lead collection
    let lead = await Lead.findOne({ phone: phoneRegex });
    if (lead) {
      lead.name = name.trim();
      if (notes) lead.notes = notes;
      await lead.save();
    } else {
      lead = await Lead.create({
        id: `lead_${Date.now()}_${Math.random().toString(36).substring(2, 7)}`,
        name: name.trim(),
        phone: phoneNumber,
        status: 'interested',
        attempts: 1,
        notes: notes || 'Contact saved by agent',
        lastCallDate: new Date(),
        dateAdded: new Date()
      });
    }

    // 2. Update all matching CallLogs with the new Contact Name
    await CallLog.updateMany(
      { phoneNumber: phoneRegex },
      { $set: { contactName: name.trim() } }
    );

    // 3. Update all matching Recordings with the new Contact Name
    await Recording.updateMany(
      { phoneNumber: phoneRegex },
      { $set: { contactName: name.trim() } }
    );

    res.json({ success: true, lead, message: `Contact "${name}" saved successfully!` });
  } catch (err) {
    res.status(500).json({ success: false, error: err.message });
  }
});

// 10. POST /api/user/photo - Update Profile Photo Base64
router.post('/photo', async (req, res) => {
  try {
    const { id, userId, name, phone, email, photoBase64 } = req.body;
    const query = [];
    if (id) query.push({ id });
    if (userId) query.push({ id: userId });
    if (phone) query.push({ phone });
    if (email) query.push({ email: email.toLowerCase() });
    if (name) query.push({ name: new RegExp(`^${name}$`, 'i') });

    if (query.length === 0) {
      return res.status(400).json({ success: false, message: 'User identifier is required' });
    }

    const emp = await Employee.findOne({ $or: query });
    if (!emp) {
      return res.status(404).json({ success: false, message: 'Employee not found' });
    }

    emp.photoBase64 = photoBase64 || '';
    await emp.save();

    res.json({
      success: true,
      message: 'Profile photo updated successfully',
      employee: {
        id: emp.id,
        name: emp.name,
        photoBase64: emp.photoBase64,
      }
    });
  } catch (err) {
    res.status(500).json({ success: false, error: err.message });
  }
});

module.exports = router;
