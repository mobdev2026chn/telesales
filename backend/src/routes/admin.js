const express = require('express');
const router = express.Router();
const CallLog = require('../models/CallLog');
const Employee = require('../models/Employee');
const Lead = require('../models/Lead');
const Recording = require('../models/Recording');
const Notification = require('../models/Notification');

// Helper: Build query filters for Team-wise, Manager-wise, and Caller-wise telemetry
async function buildTelemetryQuery(queryParams) {
  const { team, managerId, callerPhone, callerId, callerName } = queryParams;
  let employeeQuery = {};
  let callLogQuery = {};

  // 1. Caller Agent View (Personal Dashboard)
  if (callerPhone || callerId || callerName) {
    const filters = [];
    if (callerPhone) {
      const cleanPhone = callerPhone.replace(/[^0-9]/g, '');
      const last10 = cleanPhone.length >= 10 ? cleanPhone.substring(cleanPhone.length - 10) : cleanPhone;
      filters.push({ phone: callerPhone }, { phone: new RegExp(last10 + '$') });
    }
    if (callerId) filters.push({ id: callerId });
    if (callerName) filters.push({ name: new RegExp(`^${callerName}$`, 'i') });

    const callerEmp = await Employee.findOne({ $or: filters });
    if (callerEmp) {
      employeeQuery = { id: callerEmp.id };
      callLogQuery = {
        $or: [
          { callerPhone: callerEmp.phone },
          { callerName: new RegExp(`^${callerEmp.name}$`, 'i') }
        ]
      };
    } else {
      const cleanPhone = (callerPhone || '').replace(/[^0-9]/g, '');
      const last10 = cleanPhone.length >= 10 ? cleanPhone.substring(cleanPhone.length - 10) : cleanPhone;
      callLogQuery = {
        $or: [
          ...(last10 ? [{ callerPhone: new RegExp(last10 + '$') }] : []),
          ...(callerName ? [{ callerName: new RegExp(`^${callerName}$`, 'i') }] : [])
        ]
      };
    }
    return { employeeQuery, callLogQuery };
  }

  // 2. Team-wise View (Manager View or Admin Team Filter)
  if (team && team !== 'ALL' && team !== 'ALL TEAMS') {
    const teamCallers = await Employee.find({ team: new RegExp(`^${team}$`, 'i') });
    const phones = teamCallers.map(c => c.phone).filter(Boolean);
    const names = teamCallers.map(c => c.name).filter(Boolean);

    employeeQuery = { team: new RegExp(`^${team}$`, 'i') };
    callLogQuery = {
      $or: [
        { callerPhone: { $in: phones } },
        { callerName: { $in: names.map(n => new RegExp(`^${n}$`, 'i')) } }
      ]
    };
    return { employeeQuery, callLogQuery };
  }

  // 3. Manager Assignment View
  if (managerId && managerId !== 'ALL') {
    const selectedMgr = await Employee.findOne({ $or: [{ id: managerId }, { _id: managerId.match(/^[0-9a-fA-F]{24}$/) ? managerId : null }] });
    if (selectedMgr) {
      const assignedCallers = await Employee.find({ $or: [{ managerId: selectedMgr.id }, { managerName: selectedMgr.name }, { team: selectedMgr.team }] });
      const phones = assignedCallers.map(c => c.phone).filter(Boolean);
      const names = assignedCallers.map(c => c.name).filter(Boolean);

      employeeQuery = { $or: [{ managerId: selectedMgr.id }, { managerName: selectedMgr.name }, { team: selectedMgr.team }] };
      callLogQuery = {
        $or: [
          { callerPhone: { $in: phones } },
          { callerName: { $in: names } }
        ]
      };
      return { employeeQuery, callLogQuery };
    }
  }

  return { employeeQuery: {}, callLogQuery: {} };
}

// 1. GET /api/admin/dashboard - Real dynamically aggregated team telemetry from MongoDB
router.get('/dashboard', async (req, res) => {
  try {
    const managersList = await Employee.find({ role: { $in: ['manager', 'admin'] } }).select('id name email phone role team');
    const distinctTeams = await Employee.distinct('team');
    const teamsList = ['ALL TEAMS', ...distinctTeams.filter(Boolean)];

    const { employeeQuery, callLogQuery } = await buildTelemetryQuery(req.query);

    const totalCalls = await CallLog.countDocuments(callLogQuery);
    const connectedCalls = await CallLog.countDocuments({ ...callLogQuery, durationSeconds: { $gt: 0 } });
    const incoming = await CallLog.countDocuments({ ...callLogQuery, type: 'incoming' });
    const outgoing = await CallLog.countDocuments({ ...callLogQuery, type: 'outgoing' });
    const missed = await CallLog.countDocuments({ ...callLogQuery, type: 'missed' });
    const neverAttended = await CallLog.countDocuments({ 
      ...callLogQuery,
      $or: [{ type: 'rejected' }, { type: 'neverAttended' }, { durationSeconds: 0 }] 
    });

    const durationAgg = await CallLog.aggregate([
      { $match: callLogQuery },
      { $group: { _id: null, totalSeconds: { $sum: '$durationSeconds' } } }
    ]);
    const totalSeconds = durationAgg.length > 0 ? durationAgg[0].totalSeconds : 0;
    const hours = Math.floor(totalSeconds / 3600);
    const minutes = Math.floor((totalSeconds % 3600) / 60);
    const talkTimeFormatted = `${hours}h ${minutes.toString().padStart(2, '0')}m`;

    const distinctClients = await CallLog.distinct('phoneNumber', callLogQuery);
    const distinctCallers = await CallLog.distinct('callerPhone', callLogQuery);

    // Aggregate Hourly Distribution from real call timestamps
    const hourlyDistribution = await CallLog.aggregate([
      { $match: callLogQuery },
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
      { $match: callLogQuery },
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

    let topPerformer = { name: 'NO CALLERS / CALLS LOGGED YET', duration: '0h 00m' };
    if (topCallerAgg.length > 0) {
      const top = topCallerAgg[0];
      const topH = Math.floor(top.talkSeconds / 3600);
      const topM = Math.floor((top.talkSeconds % 3600) / 60);
      topPerformer = {
        name: (top._id.callerName || top._id.callerPhone || 'CALLER').toUpperCase(),
        duration: `${topH}H ${topM}M`,
      };
    }

    // Registered Team Members from Employee collection (Callers Only)
    const registeredEmployees = await Employee.find({ ...employeeQuery, role: 'caller' }).sort({ createdAt: -1 });
    
    // Aggregate CallLog stats per caller
    const callerStatsAgg = await CallLog.aggregate([
      { $match: callLogQuery },
      {
        $group: {
          _id: { callerPhone: '$callerPhone', callerName: '$callerName' },
          totalCalls: { $sum: 1 },
          connectedCalls: { $sum: { $cond: [{ $gt: ['$durationSeconds', 0] }, 1, 0] } },
          talkSeconds: { $sum: '$durationSeconds' }
        }
      }
    ]);

    const teamMemberStats = registeredEmployees.map(emp => {
      const found = callerStatsAgg.find(c =>
        (c._id.callerPhone && c._id.callerPhone === emp.phone) ||
        (c._id.callerName && c._id.callerName.toLowerCase() === emp.name.toLowerCase())
      );
      const calls = found ? found.totalCalls : (emp.totalCalls || 0);
      const connected = found ? found.connectedCalls : (emp.connectedCalls || 0);
      const talkSec = found ? found.talkSeconds : (emp.talkTimeSeconds || 0);
      const talkH = Math.floor(talkSec / 3600);
      const talkM = Math.floor((talkSec % 3600) / 60);

      return {
        id: emp.id,
        name: emp.name,
        email: emp.email || `${emp.name.toLowerCase().replace(/\s+/g, '')}@askeva.com`,
        phone: emp.phone,
        role: emp.role,
        team: emp.team || 'Telesales',
        managerName: emp.managerName || 'Unassigned',
        dailyTarget: emp.dailyTarget || 100,
        totalCalls: calls,
        connectedCalls: connected,
        talkTimeFormatted: `${talkH}h ${talkM.toString().padStart(2, '0')}m`,
        progressPercent: Math.min(Math.round((calls / (emp.dailyTarget || 100)) * 100), 100)
      };
    });

    const teamDailyTarget = registeredEmployees.reduce((sum, emp) => sum + (emp.dailyTarget || 100), 0);

    // Salestrail R&D Metrics
    const connectRatioPercent = totalCalls > 0 ? +((connectedCalls / totalCalls) * 100).toFixed(1) : 0;
    const interestedCount = await Lead.countDocuments({ status: { $in: ['interested', 'won'] } });
    const conversionRatioPercent = connectedCalls > 0 ? +((interestedCount / connectedCalls) * 100).toFixed(1) : 0;
    const totalIO = incoming + outgoing;
    const inboundPercent = totalIO > 0 ? +((incoming / totalIO) * 100).toFixed(1) : 0;
    const outboundPercent = totalIO > 0 ? +((outgoing / totalIO) * 100).toFixed(1) : 0;

    // Caller Live Status tracking
    const fifteenMinsAgo = new Date(Date.now() - 15 * 60 * 1000);
    const activeCallers = await CallLog.distinct('callerPhone', { timestamp: { $gte: fifteenMinsAgo } });

    const callerLiveStatuses = teamMemberStats.map(emp => {
      const isRecentlyActive = activeCallers.includes(emp.phone);
      return {
        id: emp.id,
        name: emp.name,
        phone: emp.phone,
        managerName: emp.managerName,
        status: isRecentlyActive ? 'ON CALL' : (emp.totalCalls > 0 ? 'ONLINE' : 'OFFLINE'),
        statusColor: isRecentlyActive ? '#FF3B30' : (emp.totalCalls > 0 ? '#34C759' : '#8E8E93'),
        totalCalls: emp.totalCalls,
      };
    });

    res.json({
      success: true,
      data: {
        totalCalls,
        connectedCalls,
        talkTimeFormatted,
        uniqueClients: distinctClients.length,
        teamCount: registeredEmployees.length,
        teamDailyTarget,
        incoming,
        outgoing,
        missed,
        neverAttended,
        connectRatioPercent,
        conversionRatioPercent,
        inboundPercent,
        outboundPercent,
        callerLiveStatuses,
        topPerformer,
        hourlyCalls,
        teamMembers: teamMemberStats,
        managersList,
        teams: teamsList,
      }
    });
  } catch (err) {
    res.status(500).json({ success: false, error: err.message });
  }
});

// GET /api/admin/calls - Dedicated Live Calls Details Feed
router.get('/calls', async (req, res) => {
  try {
    const { type, search } = req.query;
    const { callLogQuery } = await buildTelemetryQuery(req.query);
    let query = { ...callLogQuery };

    if (type && type !== 'all') {
      if (type === 'inbound') query.type = { $in: ['incoming', 'inbound'] };
      else if (type === 'outbound') query.type = { $in: ['outgoing', 'outbound'] };
      else if (type === 'missed') query.type = { $in: ['missed', 'neverAttended', 'rejected'] };
    }

    if (search) {
      const searchCond = {
        $or: [
          { callerName: { $regex: search, $options: 'i' } },
          { contactName: { $regex: search, $options: 'i' } },
          { phoneNumber: { $regex: search, $options: 'i' } }
        ]
      };
      if (query.$or) {
        query = { $and: [{ $or: query.$or }, searchCond] };
        if (type && type !== 'all') {
          if (type === 'inbound') query.type = { $in: ['incoming', 'inbound'] };
          else if (type === 'outbound') query.type = { $in: ['outgoing', 'outbound'] };
          else if (type === 'missed') query.type = { $in: ['missed', 'neverAttended', 'rejected'] };
        }
      } else {
        query.$or = searchCond.$or;
      }
    }

    const rawCalls = await CallLog.find(query).sort({ timestamp: -1 }).limit(100);
    const formattedCalls = rawCalls.map(c => {
      const isConnected = c.durationSeconds > 0;
      const isOutbound = c.type === 'outgoing' || c.type === 'outbound';
      const durationStr = `${Math.floor(c.durationSeconds / 60)}m ${c.durationSeconds % 60}s`;
      return {
        id: c._id,
        callerName: c.callerName || 'Caller',
        callerPhone: c.callerPhone || '',
        contactName: c.contactName || 'Unknown Contact',
        phoneNumber: c.phoneNumber,
        type: isOutbound ? 'OUTBOUND' : (c.type === 'incoming' ? 'INBOUND' : 'MISSED'),
        durationStr,
        durationSeconds: c.durationSeconds,
        timestamp: c.timestamp || c.createdAt,
        simSlot: c.simSlot || 1,
        note: c.note || '',
      };
    });

    res.json({ success: true, count: formattedCalls.length, calls: formattedCalls });
  } catch (err) {
    res.status(500).json({ success: false, error: err.message });
  }
});

// 2. GET & POST /api/admin/users - User Management (Add / List Users)
router.get('/users', async (req, res) => {
  try {
    let users = await Employee.find().sort({ createdAt: -1 });

    // Seed sample admin if empty
    if (users.length === 0) {
      const initialUsers = [
        {
          id: 'admin_1',
          name: 'Admin',
          email: 'admin@askeva.com',
          phone: '+91 98250 00000',
          password: 'admin123',
          role: 'admin',
          team: 'Management',
          dailyTarget: 150,
        },
      ];
      users = await Employee.insertMany(initialUsers);
    }

    res.json({ success: true, count: users.length, users });
  } catch (err) {
    res.status(500).json({ success: false, error: err.message });
  }
});

router.post('/users', async (req, res) => {
  try {
    const { name, email, phone, password, role, team, dailyTarget, managerId, managerName } = req.body;
    if (!name) {
      return res.status(400).json({ success: false, message: 'Name is required' });
    }

    let assignedManagerId = managerId || '';
    let assignedManagerName = managerName || '';

    if (assignedManagerId && !assignedManagerName) {
      const mgr = await Employee.findOne({ $or: [{ id: assignedManagerId }, { _id: assignedManagerId.match(/^[0-9a-fA-F]{24}$/) ? assignedManagerId : null }] });
      if (mgr) assignedManagerName = mgr.name;
    }

    const newUser = await Employee.create({
      id: `user_${Date.now()}`,
      name,
      email: email ? email.toLowerCase().trim() : `${name.toLowerCase().replace(/\s+/g, '')}@askeva.com`,
      phone: phone || '+91 00000 00000',
      password: password || 'admin123',
      role: role || 'caller',
      team: team || 'Telesales Team',
      dailyTarget: dailyTarget || 100,
      managerId: assignedManagerId,
      managerName: assignedManagerName,
    });

    res.status(201).json({ success: true, user: newUser, message: 'User created successfully' });
  } catch (err) {
    res.status(500).json({ success: false, error: err.message });
  }
});

router.put('/users/:id', async (req, res) => {
  try {
    const { name, email, phone, password, role, team, dailyTarget, managerId, managerName } = req.body;
    
    let assignedManagerId = managerId !== undefined ? managerId : '';
    let assignedManagerName = managerName !== undefined ? managerName : '';

    if (assignedManagerId && !assignedManagerName) {
      const mgr = await Employee.findOne({ $or: [{ id: assignedManagerId }, { _id: assignedManagerId.match(/^[0-9a-fA-F]{24}$/) ? assignedManagerId : null }] });
      if (mgr) assignedManagerName = mgr.name;
    }

    const updateData = {
      name,
      email,
      phone,
      role,
      team,
      dailyTarget,
      managerId: assignedManagerId,
      managerName: assignedManagerName,
    };

    if (password && password.trim().length > 0) {
      updateData.password = password;
    }

    const paramId = req.params.id;
    const isMongoId = /^[0-9a-fA-F]{24}$/.test(paramId);

    const updated = await Employee.findOneAndUpdate(
      {
        $or: [
          { id: paramId },
          ...(isMongoId ? [{ _id: paramId }] : [])
        ]
      },
      { $set: updateData },
      { new: true }
    );

    if (!updated) {
      return res.status(404).json({ success: false, message: 'User not found' });
    }

    res.json({ success: true, user: updated, message: 'User updated successfully' });
  } catch (err) {
    res.status(500).json({ success: false, error: err.message });
  }
});

router.delete('/users/:id', async (req, res) => {
  try {
    const paramId = req.params.id;
    const isMongoId = /^[0-9a-fA-F]{24}$/.test(paramId);

    const deleted = await Employee.findOneAndDelete({
      $or: [
        { id: paramId },
        ...(isMongoId ? [{ _id: paramId }] : [])
      ]
    });

    if (!deleted) {
      return res.status(404).json({ success: false, message: 'User not found' });
    }

    res.json({ success: true, message: 'User deleted successfully' });
  } catch (err) {
    res.status(500).json({ success: false, error: err.message });
  }
});

// 3. GET /api/admin/leaderboard - Dynamic CALLERS ONLY rankings from MongoDB
router.get('/leaderboard', async (req, res) => {
  try {
    const { employeeQuery, callLogQuery } = await buildTelemetryQuery(req.query);
    const callerEmployees = await Employee.find({ ...employeeQuery, role: 'caller' });
    const nonCallers = await Employee.find({ role: { $ne: 'caller' } });
    const nonCallerPhones = nonCallers.map(e => e.phone);
    const nonCallerNames = nonCallers.map(e => e.name.toLowerCase());

    const liveLeaderboard = await CallLog.aggregate([
      { $match: callLogQuery },
      {
        $group: {
          _id: { callerName: '$callerName', callerPhone: '$callerPhone' },
          totalCalls: { $sum: 1 },
          connectedCalls: {
            $sum: { $cond: [{ $gt: ['$durationSeconds', 0] }, 1, 0] }
          },
          talkTimeSeconds: { $sum: '$durationSeconds' },
        }
      }
    ]);

    let employeesList = [];

    if (callerEmployees.length > 0) {
      employeesList = callerEmployees.map(emp => {
        const found = liveLeaderboard.find(item =>
          (item._id.callerPhone && item._id.callerPhone === emp.phone) ||
          (item._id.callerName && item._id.callerName.toLowerCase() === emp.name.toLowerCase())
        );
        const calls = found ? found.totalCalls : 0;
        const connected = found ? found.connectedCalls : 0;
        const talkSec = found ? found.talkTimeSeconds : 0;
        const hours = Math.floor(talkSec / 3600);
        const mins = Math.floor((talkSec % 3600) / 60);

        return {
          id: emp.id,
          name: emp.name,
          phone: emp.phone,
          role: 'caller',
          team: emp.team || 'Telesales',
          totalCalls: calls,
          connectedCalls: connected,
          talkTimeSeconds: talkSec,
          talkTimeFormatted: `${hours}h ${mins.toString().padStart(2, '0')}m`,
          dailyTarget: emp.dailyTarget || 100,
        };
      });
    } else {
      employeesList = [];
    }

    // Sort by talk time, then total calls
    employeesList.sort((a, b) => b.talkTimeSeconds - a.talkTimeSeconds || b.totalCalls - a.totalCalls);

    // Assign rank
    employeesList.forEach((emp, i) => emp.rank = i + 1);

    res.json({ success: true, count: employeesList.length, employees: employeesList });
  } catch (err) {
    res.status(500).json({ success: false, error: err.message });
  }
});

// 4. GET & POST /api/admin/recordings - Real live audio recordings in MongoDB
router.get('/recordings', async (req, res) => {
  try {
    const { type } = req.query;
    const { employeeQuery } = await buildTelemetryQuery(req.query);
    let query = {};

    if (employeeQuery.id || employeeQuery.team) {
      const teamCallers = await Employee.find({ ...employeeQuery, role: 'caller' });
      const names = teamCallers.map(c => c.name).filter(Boolean);
      const phones = teamCallers.map(c => c.phone).filter(Boolean);
      if (names.length > 0 || phones.length > 0) {
        query.$or = [
          { callerName: { $in: names.map(n => new RegExp(`^${n}$`, 'i')) } },
          { phoneNumber: { $in: phones } }
        ];
      }
    }

    if (type && type !== 'all') {
      if (type === 'inbound') query.type = { $in: ['incoming', 'inbound'] };
      else if (type === 'outbound') query.type = { $in: ['outgoing', 'outbound'] };
    }

    const recordings = await Recording.find(query).sort({ createdAt: -1 });
    const totalStorageBytes = recordings.reduce((acc, r) => acc + (r.storageSizeBytes || 450000), 0);
    const usedGB = +(totalStorageBytes / (1024 * 1024 * 1024)).toFixed(2);

    res.json({
      success: true,
      storage: {
        usedGB: Math.max(usedGB, 0.05),
        totalGB: 5.0,
        freeGB: +(5.0 - Math.max(usedGB, 0.05)).toFixed(2),
        count: recordings.length,
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

// 5. GET /api/admin/leads - Real live CRM pipeline leads from MongoDB
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

// POST /api/admin/recordings/:id/comment - Save rating & comment for recording (Admin & Manager Only)
router.post('/recordings/:id/comment', async (req, res) => {
  try {
    const { rating, comment, commentedBy, commentedByRole } = req.body;
    const recId = req.params.id;

    const role = (commentedByRole || '').toLowerCase();
    if (role !== 'admin' && role !== 'manager') {
      return res.status(403).json({
        success: false,
        message: 'Unauthorized: Only Admin and Manager roles are permitted to submit call quality ratings and comments.'
      });
    }

    const isMongoId = /^[0-9a-fA-F]{24}$/.test(recId);
    const updated = await Recording.findOneAndUpdate(
      {
        $or: [
          { id: recId },
          ...(isMongoId ? [{ _id: recId }] : [])
        ]
      },
      {
        $set: {
          rating: typeof rating === 'number' ? rating : 0,
          comment: comment || '',
          commentedBy: commentedBy || 'Admin',
          commentedByRole: commentedByRole || 'admin',
          commentedAt: new Date(),
        }
      },
      { new: true }
    );

    if (!updated) {
      return res.status(404).json({ success: false, message: 'Recording not found' });
    }

    // Create persistent Notification for the respective caller
    try {
      const callerName = updated.callerName || '';
      const callerEmp = await Employee.findOne({
        $or: [
          { name: new RegExp(`^${callerName}$`, 'i') },
          ...(updated.callerPhone ? [{ phone: updated.callerPhone }] : [])
        ]
      });

      const recipientPhone = callerEmp ? callerEmp.phone : (updated.callerPhone || '');
      const starsStr = typeof rating === 'number' && rating > 0 ? `${rating} ⭐` : '';
      const author = commentedBy || 'Admin';
      const roleStr = (commentedByRole || 'admin').toUpperCase();

      await Notification.create({
        id: `notif_${Date.now()}_${Math.random().toString(36).substring(2, 6)}`,
        recipientPhone: recipientPhone,
        recipientName: callerName,
        senderName: author,
        senderRole: commentedByRole || 'admin',
        recordingId: updated.id || recId,
        contactName: updated.contactName || 'Client',
        title: `Feedback from ${author} (${roleStr})`,
        message: `${author} reviewed your call with ${updated.contactName || 'Client'} ${starsStr ? `(${starsStr})` : ''}: "${comment || 'Good call'}"`,
        comment: comment || '',
        rating: typeof rating === 'number' ? rating : 0,
        isRead: false,
      });
    } catch (notifErr) {
      console.error('Error creating notification:', notifErr);
    }

    res.json({
      success: true,
      recording: updated,
      message: 'Call quality rating and comment saved successfully'
    });
  } catch (err) {
    res.status(500).json({ success: false, error: err.message });
  }
});

module.exports = router;
