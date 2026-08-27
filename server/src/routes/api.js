const express = require('express');
const router = express.Router();
const CallLog = require('../models/CallLog');
const Employee = require('../models/Employee');
const Lead = require('../models/Lead');
const Recording = require('../models/Recording');

// 1. POST /api/calls/sync - Mobile device pushes batch call logs
router.post('/calls/sync', async (req, res) => {
  try {
    const { callerId, callerName, callerPhone, calls } = req.body;
    if (!Array.isArray(calls)) {
      return res.status(400).json({ success: false, message: 'Calls array expected' });
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

    res.json({ success: true, count: inserted.length, message: 'Calls synchronized with MongoDB' });
  } catch (err) {
    res.status(500).json({ success: false, error: err.message });
  }
});

// 2. GET /api/dashboard/stats - Admin aggregated telemetry (100% Real Live Data)
router.get('/dashboard/stats', async (req, res) => {
  try {
    const totalCalls = await CallLog.countDocuments();
    const connectedCalls = await CallLog.countDocuments({ durationSeconds: { $gt: 0 } });
    const incoming = await CallLog.countDocuments({ type: 'incoming' });
    const outgoing = await CallLog.countDocuments({ type: 'outgoing' });
    const missed = await CallLog.countDocuments({ type: 'missed' });
    const neverAttended = await CallLog.countDocuments({ 
      $or: [{ type: 'rejected' }, { type: 'neverAttended' }, { durationSeconds: 0 }] 
    });

    const durationAgg = await CallLog.aggregate([
      { $group: { _id: null, totalSeconds: { $sum: '$durationSeconds' } } }
    ]);
    const totalSeconds = durationAgg.length > 0 ? durationAgg[0].totalSeconds : 0;
    const hours = Math.floor(totalSeconds / 3600);
    const minutes = Math.floor((totalSeconds % 3600) / 60);
    const talkTimeFormatted = `${hours}h ${minutes.toString().padStart(2, '0')}m`;

    const distinctClients = await CallLog.distinct('phoneNumber');
    const distinctCallers = await CallLog.distinct('callerPhone');

    // Aggregate Hourly Distribution from real call timestamps
    const hourlyDistribution = await CallLog.aggregate([
      {
        $project: {
          hour: { $hour: { date: '$timestamp', timezone: '+05:30' } }
        }
      },
      {
        $group: {
          _id: '$hour',
          count: { $sum: 1 }
        }
      }
    ]);

    const hourLabels = [
      { h: 9, label: '9A' },
      { h: 10, label: '10A' },
      { h: 11, label: '11A' },
      { h: 12, label: '12P' },
      { h: 13, label: '1P' },
      { h: 14, label: '2P' },
      { h: 15, label: '3P' },
      { h: 16, label: '4P' },
      { h: 17, label: '5P' },
      { h: 18, label: '6P' },
    ];

    let maxHourlyCalls = 0;
    const hourlyCalls = hourLabels.map(hl => {
      const found = hourlyDistribution.find(d => d._id === hl.h);
      const c = found ? found.count : 0;
      if (c > maxHourlyCalls) maxHourlyCalls = c;
      return { hour: hl.label, calls: c, isPeak: false };
    });

    hourlyCalls.forEach(item => {
      if (item.calls > 0 && item.calls === maxHourlyCalls) {
        item.isPeak = true;
      }
    });

    // Top talk time caller dynamically computed from actual database calls
    const topCallerAgg = await CallLog.aggregate([
      {
        $group: {
          _id: { callerName: '$callerName', callerPhone: '$callerPhone' },
          talkSeconds: { $sum: '$durationSeconds' },
          totalCalls: { $sum: 1 }
        }
      },
      { $sort: { talkSeconds: -1 } },
      { $limit: 1 }
    ]);

    let topPerformer = { name: 'NO CALLS YET', duration: '0H 00M' };
    if (topCallerAgg.length > 0) {
      const top = topCallerAgg[0];
      const topH = Math.floor(top.talkSeconds / 3600);
      const topM = Math.floor((top.talkSeconds % 3600) / 60);
      topPerformer = {
        name: (top._id.callerName || top._id.callerPhone || 'CALLER').toUpperCase(),
        duration: `${topH}H ${topM}M`,
      };
    }

    res.json({
      success: true,
      stats: {
        totalCalls,
        connectedCalls,
        talkTimeFormatted,
        uniqueClients: distinctClients.length,
        teamCount: Math.max(distinctCallers.length, 1),
        incoming,
        outgoing,
        missed,
        neverAttended,
        topTalkTime: topPerformer,
        hourlyCalls,
      }
    });
  } catch (err) {
    res.status(500).json({ success: false, error: err.message });
  }
});

// 3. GET /api/employees/leaderboard - Real live leaderboard aggregated directly from synced calls
router.get('/employees/leaderboard', async (req, res) => {
  try {
    const liveLeaderboard = await CallLog.aggregate([
      {
        $group: {
          _id: { callerName: '$callerName', callerPhone: '$callerPhone' },
          totalCalls: { $sum: 1 },
          connectedCalls: {
            $sum: { $cond: [{ $gt: ['$durationSeconds', 0] }, 1, 0] }
          },
          talkTimeSeconds: { $sum: '$durationSeconds' },
        }
      },
      { $sort: { talkTimeSeconds: -1, totalCalls: -1 } }
    ]);

    if (liveLeaderboard.length > 0) {
      const employees = liveLeaderboard.map((item, index) => ({
        id: (index + 1).toString(),
        name: item._id.callerName || item._id.callerPhone || `Caller ${index + 1}`,
        phone: item._id.callerPhone || '+91 98250 12340',
        role: 'caller',
        team: 'Telesales Team',
        totalCalls: item.totalCalls,
        connectedCalls: item.connectedCalls,
        talkTimeSeconds: item.talkTimeSeconds,
        rank: index + 1,
      }));
      return res.json({ success: true, count: employees.length, employees });
    }

    const employees = await Employee.find().sort({ rank: 1 });
    res.json({ success: true, employees });
  } catch (err) {
    res.status(500).json({ success: false, error: err.message });
  }
});

// 4. GET /api/leads - Real live CRM pipeline leads from MongoDB
router.get('/leads', async (req, res) => {
  try {
    const leads = await Lead.find().sort({ updatedAt: -1 });
    const won = leads.filter(l => l.status === 'won').length;
    const interested = leads.filter(l => l.status === 'interested').length;
    const followUp = leads.filter(l => l.status === 'followUp').length;
    const other = leads.length - (won + interested + followUp);

    res.json({
      success: true,
      pipeline: {
        total: leads.length,
        won,
        interested,
        followUp,
        other: Math.max(other, 0),
      },
      leads,
    });
  } catch (err) {
    res.status(500).json({ success: false, error: err.message });
  }
});

// 5. GET & POST /api/recordings - Real live audio recordings in MongoDB
router.get('/recordings', async (req, res) => {
  try {
    const recordings = await Recording.find().sort({ createdAt: -1 });
    const totalStorageBytes = recordings.reduce((acc, r) => acc + (r.storageSizeBytes || 450000), 0);
    const usedGB = +(totalStorageBytes / (1024 * 1024 * 1024)).toFixed(2);

    res.json({
      success: true,
      storage: {
        usedGB: Math.max(usedGB, 0.05),
        totalGB: 5.0,
        freeGB: +(5.0 - Math.max(usedGB, 0.05)).toFixed(2),
      },
      recordings,
    });
  } catch (err) {
    res.status(500).json({ success: false, error: err.message });
  }
});

router.post('/recordings', async (req, res) => {
  try {
    const { callerName, contactName, phoneNumber, durationSeconds, transcript, dateStr, timeStr, fileName } = req.body;

    const rec = await Recording.create({
      id: Date.now().toString(),
      callerName: callerName || 'Caller',
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

module.exports = router;
