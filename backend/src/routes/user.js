const express = require('express');
const router = express.Router();
const CallLog = require('../models/CallLog');
const Lead = require('../models/Lead');
const Recording = require('../models/Recording');

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
        callerName: callerName || 'Priyanka Panchal',
        callerPhone: callerPhone || '+91 98250 12340',
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
      callerName: callerName || 'Priyanka',
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

module.exports = router;
