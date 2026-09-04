const express = require('express');
const router = express.Router();
const CallLog = require('../models/CallLog');
const Employee = require('../models/Employee');
const Lead = require('../models/Lead');
const Recording = require('../models/Recording');
const Notification = require('../models/Notification');

// 0. RESET / PURGE ALL TEST DATA (Retains ONLY Admin account)
router.all('/purge-all-data', async (req, res) => {
  try {
    const callRes = await CallLog.deleteMany({});
    const leadRes = await Lead.deleteMany({});
    const recRes = await Recording.deleteMany({});
    const notifRes = await Notification.deleteMany({});
    const empRes = await Employee.deleteMany({});

    const cleanAdmin = await Employee.create({
      id: 'admin_1',
      name: 'Admin',
      email: 'admin@askeva.com',
      phone: '+91 98250 00000',
      password: 'admin123',
      role: 'admin',
      team: 'Management',
      dailyTarget: 150,
      createdAt: new Date(),
      updatedAt: new Date(),
    });

    res.json({
      success: true,
      message: 'All test data purged successfully. Only clean Admin account remains.',
      deleted: {
        calls: callRes.deletedCount,
        leads: leadRes.deletedCount,
        recordings: recRes.deletedCount,
        notifications: notifRes.deletedCount,
        employees: empRes.deletedCount,
      },
      admin: {
        email: cleanAdmin.email,
        name: cleanAdmin.name,
        role: cleanAdmin.role,
      },
    });
  } catch (err) {
    res.status(500).json({ success: false, error: err.message });
  }
});

// Helper: Build query filters for Team-wise, Manager-wise, and Caller/User-wise telemetry
async function buildTelemetryQuery(queryParams) {
  const { team, managerId, callerPhone, callerId, callerName, userId, loggedInRole, loggedInTeam, loggedInUserId, userRole } = queryParams;
  let employeeQuery = {};
  let callLogQuery = {};

  const effectiveRole = (loggedInRole || userRole || '').toLowerCase();
  const isAdmin = effectiveRole === 'admin';
  const isManager = effectiveRole === 'manager';
  const isCaller = effectiveRole === 'caller';

  // 1. If Caller is requesting data, strictly scope to that caller
  if (isCaller) {
    const targetUser = loggedInUserId || userId || callerId || callerPhone || callerName;
    if (targetUser) {
      const isMongoId = /^[0-9a-fA-F]{24}$/.test(targetUser);
      const escapedTarget = targetUser.replace(/[.*+?^${}()|[\]\\]/g, '\\$&');
      const filters = [
        { id: targetUser },
        ...(isMongoId ? [{ _id: targetUser }] : []),
        { name: new RegExp(`^${escapedTarget}$`, 'i') },
        { phone: targetUser },
      ];
      const cleanPhone = targetUser.replace(/[^0-9]/g, '');
      if (cleanPhone.length >= 10) {
        const last10 = cleanPhone.substring(cleanPhone.length - 10);
        filters.push({ phone: new RegExp(last10 + '$') });
      }

      const callerEmp = await Employee.findOne({ $or: filters });
      if (callerEmp) {
        const cleanEmpPhone = (callerEmp.phone || '').replace(/[^0-9]/g, '');
        const last10 = cleanEmpPhone.length >= 10 ? cleanEmpPhone.substring(cleanEmpPhone.length - 10) : cleanEmpPhone;
        const escapedEmpName = callerEmp.name.replace(/[.*+?^${}()|[\]\\]/g, '\\$&');

        employeeQuery = {
          $or: [
            { id: callerEmp.id },
            { _id: callerEmp._id },
            { phone: callerEmp.phone },
            { name: callerEmp.name }
          ]
        };
        callLogQuery = {
          $or: [
            { callerId: callerEmp.id },
            { callerPhone: callerEmp.phone },
            ...(last10 ? [{ callerPhone: new RegExp(last10 + '$') }] : []),
            { callerName: new RegExp(`^${escapedEmpName}$`, 'i') }
          ]
        };
      } else {
        const cleanPhoneStr = (targetUser || '').replace(/[^0-9]/g, '');
        const last10 = cleanPhoneStr.length >= 10 ? cleanPhoneStr.substring(cleanPhoneStr.length - 10) : cleanPhoneStr;
        callLogQuery = {
          $or: [
            ...(last10 ? [{ callerPhone: new RegExp(last10 + '$') }] : []),
            { callerName: new RegExp(`^${escapedTarget}$`, 'i') },
            { callerId: targetUser }
          ]
        };
      }
      return { employeeQuery, callLogQuery };
    }
  }

  // 2. Caller / User Specific Filter (within Manager/Admin scope)
  const targetUser = userId || callerId || callerPhone || callerName;
  if (targetUser && targetUser !== 'ALL' && targetUser !== 'ALL USERS') {
    const isMongoId = /^[0-9a-fA-F]{24}$/.test(targetUser);
    const escapedTarget = targetUser.replace(/[.*+?^${}()|[\]\\]/g, '\\$&');
    const filters = [
      { id: targetUser },
      ...(isMongoId ? [{ _id: targetUser }] : []),
      { name: new RegExp(`^${escapedTarget}$`, 'i') },
      { phone: targetUser },
    ];
    const cleanPhone = targetUser.replace(/[^0-9]/g, '');
    if (cleanPhone.length >= 10) {
      const last10 = cleanPhone.substring(cleanPhone.length - 10);
      filters.push({ phone: new RegExp(last10 + '$') });
    }

    const callerEmp = await Employee.findOne({ $or: filters });
    if (callerEmp) {
      const cleanEmpPhone = (callerEmp.phone || '').replace(/[^0-9]/g, '');
      const last10 = cleanEmpPhone.length >= 10 ? cleanEmpPhone.substring(cleanEmpPhone.length - 10) : cleanEmpPhone;
      const escapedEmpName = callerEmp.name.replace(/[.*+?^${}()|[\]\\]/g, '\\$&');

      employeeQuery = {
        $or: [
          { id: callerEmp.id },
          { _id: callerEmp._id },
          { phone: callerEmp.phone },
          { name: callerEmp.name }
        ]
      };
      callLogQuery = {
        $or: [
          { callerId: callerEmp.id },
          { callerPhone: callerEmp.phone },
          ...(last10 ? [{ callerPhone: new RegExp(last10 + '$') }] : []),
          { callerName: new RegExp(`^${escapedEmpName}$`, 'i') }
        ]
      };
    } else {
      const cleanPhoneStr = (targetUser || '').replace(/[^0-9]/g, '');
      const last10 = cleanPhoneStr.length >= 10 ? cleanPhoneStr.substring(cleanPhoneStr.length - 10) : cleanPhoneStr;
      callLogQuery = {
        $or: [
          ...(last10 ? [{ callerPhone: new RegExp(last10 + '$') }] : []),
          { callerName: new RegExp(`^${escapedTarget}$`, 'i') },
          { callerId: targetUser }
        ]
      };
    }
    return { employeeQuery, callLogQuery };
  }

  // 3. Manager Automatic Team Scoping: If user is Manager, lock to manager's team/subordinates
  let effectiveTeam = team;
  let effectiveManagerId = managerId;

  if (isManager && !isAdmin) {
    if (!effectiveTeam || effectiveTeam === 'ALL' || effectiveTeam === 'ALL TEAMS') {
      effectiveTeam = loggedInTeam;
    }
    if (!effectiveManagerId || effectiveManagerId === 'ALL' || effectiveManagerId === 'ALL MANAGERS') {
      effectiveManagerId = loggedInUserId;
    }
  }

  // 4. Team-wise View
  if (effectiveTeam && effectiveTeam !== 'ALL' && effectiveTeam !== 'ALL TEAMS') {
    const escapedTeam = effectiveTeam.replace(/[.*+?^${}()|[\]\\]/g, '\\$&');
    const teamCallers = await Employee.find({ team: new RegExp(`^${escapedTeam}$`, 'i') });
    const phones = teamCallers.map(c => c.phone).filter(Boolean);
    const names = teamCallers.map(c => c.name).filter(Boolean);
    const ids = teamCallers.map(c => c.id).filter(Boolean);

    const callConditions = [];
    if (ids.length > 0) callConditions.push({ callerId: { $in: ids } });
    phones.forEach(p => {
      callConditions.push({ callerPhone: p });
      const clean = p.replace(/[^0-9]/g, '');
      if (clean.length >= 10) {
        const last10 = clean.substring(clean.length - 10);
        callConditions.push({ callerPhone: new RegExp(last10 + '$') });
      }
    });
    names.forEach(n => {
      const esc = n.replace(/[.*+?^${}()|[\]\\]/g, '\\$&');
      callConditions.push({ callerName: new RegExp(`^${esc}$`, 'i') });
    });

    employeeQuery = { team: new RegExp(`^${escapedTeam}$`, 'i') };
    callLogQuery = callConditions.length > 0 ? { $or: callConditions } : { _id: null };
    return { employeeQuery, callLogQuery };
  }

  // 5. Manager Assignment View
  if (effectiveManagerId && effectiveManagerId !== 'ALL' && effectiveManagerId !== 'ALL MANAGERS') {
    const isMongoId = /^[0-9a-fA-F]{24}$/.test(effectiveManagerId);
    const selectedMgr = await Employee.findOne({ 
      $or: [
        { id: effectiveManagerId }, 
        ...(isMongoId ? [{ _id: effectiveManagerId }] : []),
        { name: new RegExp(`^${effectiveManagerId}$`, 'i') }
      ] 
    });
    if (selectedMgr) {
      const assignedCallers = await Employee.find({ 
        $or: [
          { managerId: selectedMgr.id }, 
          { managerName: selectedMgr.name }, 
          { team: selectedMgr.team }
        ] 
      });
      const phones = assignedCallers.map(c => c.phone).filter(Boolean);
      const names = assignedCallers.map(c => c.name).filter(Boolean);
      const ids = assignedCallers.map(c => c.id).filter(Boolean);

      employeeQuery = { 
        $or: [
          { managerId: selectedMgr.id }, 
          { managerName: selectedMgr.name }, 
          { team: selectedMgr.team }
        ] 
      };
      callLogQuery = {
        $or: [
          { callerId: { $in: ids } },
          { callerPhone: { $in: phones } },
          { callerName: { $in: names.map(n => new RegExp(`^${n}$`, 'i')) } }
        ]
      };
    }
  }

  // 4. Date & Period Filter (Today / Week / Month / Custom Date)
  const { period, timeFilter, date, startDate, endDate } = queryParams;
  let dateCondition = null;
  const now = new Date();
  const todayStart = new Date(now.getFullYear(), now.getMonth(), now.getDate(), 0, 0, 0, 0);
  const todayEnd = new Date(now.getFullYear(), now.getMonth(), now.getDate(), 23, 59, 59, 999);

  if (startDate && endDate) {
    const s = new Date(startDate);
    const e = new Date(endDate);
    if (!isNaN(s.getTime()) && !isNaN(e.getTime())) {
      const sStart = new Date(s.getFullYear(), s.getMonth(), s.getDate(), 0, 0, 0, 0);
      const eEnd = new Date(e.getFullYear(), e.getMonth(), e.getDate(), 23, 59, 59, 999);
      dateCondition = { $gte: sStart, $lte: eEnd };
    }
  } else if (date) {
    const d = new Date(date);
    if (!isNaN(d.getTime())) {
      const dStart = new Date(d.getFullYear(), d.getMonth(), d.getDate(), 0, 0, 0, 0);
      const dEnd = new Date(d.getFullYear(), d.getMonth(), d.getDate(), 23, 59, 59, 999);
      dateCondition = { $gte: dStart, $lte: dEnd };
    }
  } else if (period === 'today' || timeFilter === '0' || timeFilter === 'today' || timeFilter === 0) {
    dateCondition = { $gte: todayStart, $lte: todayEnd };
  } else if (period === 'week' || timeFilter === '1' || timeFilter === 'week' || timeFilter === 1) {
    const dayOfWeek = now.getDay();
    const distanceToMonday = (dayOfWeek + 6) % 7;
    const weekStart = new Date(now.getFullYear(), now.getMonth(), now.getDate() - distanceToMonday, 0, 0, 0, 0);
    dateCondition = { $gte: weekStart, $lte: todayEnd };
  } else if (period === 'month' || timeFilter === '2' || timeFilter === 'month' || timeFilter === 2) {
    const monthStart = new Date(now.getFullYear(), now.getMonth(), 1, 0, 0, 0, 0);
    dateCondition = { $gte: monthStart, $lte: todayEnd };
  }

  if (dateCondition) {
    if (Object.keys(callLogQuery).length === 0) {
      callLogQuery = { timestamp: dateCondition };
    } else {
      callLogQuery = { $and: [callLogQuery, { timestamp: dateCondition }] };
    }
  }

  return { employeeQuery, callLogQuery };
}

// 1. GET /api/admin/dashboard - Real dynamically aggregated team telemetry from MongoDB
router.get('/dashboard', async (req, res) => {
  try {
    const managersList = await Employee.find({ role: { $in: ['manager', 'admin'] } }).select('id name email phone role team');
    const distinctTeams = await Employee.distinct('team');
    const validTeams = distinctTeams.filter(t => t && !['BD TEAM - AE', 'BDE', 'Telesales Mumbai'].includes(t));
    const teamsList = ['ALL TEAMS', ...(validTeams.length > 0 ? validTeams : ['Telesales Team', 'Management'])];

    const { employeeQuery, callLogQuery } = await buildTelemetryQuery(req.query);

    const totalCalls = await CallLog.countDocuments(callLogQuery);
    const connectedCalls = await CallLog.countDocuments({ ...callLogQuery, durationSeconds: { $gt: 0 } });
    const incoming = await CallLog.countDocuments({ ...callLogQuery, type: { $in: ['incoming', 'inbound'] } });
    const outgoing = await CallLog.countDocuments({ ...callLogQuery, type: { $in: ['outgoing', 'outbound'] } });
    const missed = await CallLog.countDocuments({ ...callLogQuery, type: 'missed' });
    const rejected = await CallLog.countDocuments({ ...callLogQuery, type: { $in: ['rejected', 'neverAttended'] } });
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
      { h: 19, label: '7P' },
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

    // Registered Team Members from Employee collection under current filter
    const registeredEmployees = await Employee.find(employeeQuery).sort({ createdAt: -1 });
    
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
      const cleanEmpPhone = (emp.phone || '').replace(/[^0-9]/g, '');
      const last10 = cleanEmpPhone.length >= 10 ? cleanEmpPhone.substring(cleanEmpPhone.length - 10) : cleanEmpPhone;

      const found = callerStatsAgg.find(c => {
        const cPhone = (c._id.callerPhone || '').replace(/[^0-9]/g, '');
        const cLast10 = cPhone.length >= 10 ? cPhone.substring(cPhone.length - 10) : cPhone;
        const phoneMatch = (c._id.callerPhone && c._id.callerPhone === emp.phone) || (last10 && cLast10 === last10);
        const nameMatch = c._id.callerName && c._id.callerName.toLowerCase() === emp.name.toLowerCase();
        return phoneMatch || nameMatch;
      });
      const calls = found ? found.totalCalls : (emp.totalCalls || 0);
      const connected = found ? found.connectedCalls : (emp.connectedCalls || 0);
      const talkSec = found ? found.talkSeconds : (emp.talkTimeSeconds || 0);
      const talkH = Math.floor(talkSec / 3600);
      const talkM = Math.floor((talkSec % 3600) / 60);

      return {
        id: emp.id,
        name: emp.name,
        email: emp.email,
        phone: emp.phone,
        role: emp.role || 'caller',
        team: emp.team || 'Telesales Team',
        managerId: emp.managerId,
        managerName: emp.managerName,
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

    const allUsers = await Employee.find().select('id _id name email phone role team managerId managerName dailyTarget').sort({ name: 1 });

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
        rejected,
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
        allUsers,
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
    
    let conditions = [];

    if (callLogQuery && Object.keys(callLogQuery).length > 0) {
      conditions.push(callLogQuery);
    }

    if (type && type !== 'all') {
      if (type === 'inbound') conditions.push({ type: { $in: ['incoming', 'inbound'] } });
      else if (type === 'outbound') conditions.push({ type: { $in: ['outgoing', 'outbound'] } });
      else if (type === 'missed') conditions.push({ type: { $in: ['missed', 'neverAttended', 'rejected'] } });
    }

    if (search && search.trim()) {
      const s = search.trim();
      conditions.push({
        $or: [
          { callerName: { $regex: s, $options: 'i' } },
          { contactName: { $regex: s, $options: 'i' } },
          { phoneNumber: { $regex: s, $options: 'i' } }
        ]
      });
    }

    const query = conditions.length > 0 ? (conditions.length === 1 ? conditions[0] : { $and: conditions }) : {};
    const rawCalls = await CallLog.find(query).sort({ timestamp: -1 }).limit(200);

    const employees = await Employee.find().select('id name phone');
    const phoneMap = {};
    employees.forEach(e => {
      if (e.phone) {
        const clean = e.phone.replace(/[^0-9]/g, '').slice(-10);
        if (clean) phoneMap[clean] = e.name;
        phoneMap[e.phone] = e.name;
      }
    });

    const formattedCalls = rawCalls.map(c => {
      const isConnected = c.durationSeconds > 0;
      const isOutbound = c.type === 'outgoing' || c.type === 'outbound';
      const durationStr = `${Math.floor(c.durationSeconds / 60)}m ${c.durationSeconds % 60}s`;
      const cleanPhone = (c.callerPhone || '').replace(/[^0-9]/g, '').slice(-10);
      const registeredName = phoneMap[cleanPhone] || phoneMap[c.callerPhone] || c.callerName || 'Caller';

      return {
        id: c._id,
        callerName: registeredName,
        callerPhone: c.callerPhone || '',
        contactName: c.contactName || 'Unknown Contact',
        phoneNumber: c.phoneNumber,
        type: isOutbound ? 'OUTBOUND' : (c.type === 'incoming' || c.type === 'inbound' ? 'INBOUND' : 'MISSED'),
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
          avatarUrl: emp.avatarUrl || '',
          photoBase64: emp.photoBase64 || '',
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

// Update Profile Photo Endpoint (POST /api/admin/users/photo & /api/users/photo)
router.all(['/users/photo', '/users/:id/photo'], async (req, res) => {
  try {
    const rawId = req.params.id || req.body.id || req.body.userId;
    const { photoBase64, avatarUrl } = req.body;
    if (!rawId) {
      return res.status(400).json({ success: false, message: 'User ID is required' });
    }
    const isMongoId = /^[0-9a-fA-F]{24}$/.test(rawId);
    const updated = await Employee.findOneAndUpdate(
      {
        $or: [
          { id: rawId },
          ...(isMongoId ? [{ _id: rawId }] : [])
        ]
      },
      { $set: { photoBase64: photoBase64 || '', avatarUrl: avatarUrl || '' } },
      { new: true }
    );
    if (!updated) {
      return res.status(404).json({ success: false, message: 'User not found' });
    }
    res.json({ success: true, message: 'Profile photo updated successfully', user: updated });
  } catch (err) {
    res.status(500).json({ success: false, error: err.message });
  }
});

// 4. GET & POST /api/admin/recordings - Real live audio recordings in MongoDB
router.get('/recordings', async (req, res) => {
  try {
    const { type, search } = req.query;
    const { employeeQuery } = await buildTelemetryQuery(req.query);
    let conditions = [];

    if (employeeQuery && Object.keys(employeeQuery).length > 0) {
      const teamCallers = await Employee.find({ ...employeeQuery });
      const names = teamCallers.map(c => c.name).filter(Boolean);
      const phones = teamCallers.map(c => c.phone).filter(Boolean);
      if (names.length > 0 || phones.length > 0) {
        conditions.push({
          $or: [
            { callerName: { $in: names.map(n => new RegExp(`^${n}$`, 'i')) } },
            { phoneNumber: { $in: phones } }
          ]
        });
      }
    }

    if (type && type !== 'all') {
      if (type === 'inbound') conditions.push({ type: { $in: ['incoming', 'inbound'] } });
      else if (type === 'outbound') conditions.push({ type: { $in: ['outgoing', 'outbound'] } });
    }

    if (search && search.trim()) {
      const s = search.trim();
      conditions.push({
        $or: [
          { callerName: { $regex: s, $options: 'i' } },
          { contactName: { $regex: s, $options: 'i' } },
          { phoneNumber: { $regex: s, $options: 'i' } }
        ]
      });
    }

    const query = conditions.length > 0 ? (conditions.length === 1 ? conditions[0] : { $and: conditions }) : {};
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

router.delete('/recordings/:id', async (req, res) => {
  try {
    const recId = req.params.id;
    const isMongoId = /^[0-9a-fA-F]{24}$/.test(recId);
    const deleted = await Recording.findOneAndDelete({
      $or: [
        { id: recId },
        ...(isMongoId ? [{ _id: recId }] : [])
      ]
    });
    if (!deleted) {
      return res.status(404).json({ success: false, message: 'Recording not found' });
    }
    res.json({ success: true, message: 'Recording deleted successfully' });
  } catch (err) {
    res.status(500).json({ success: false, error: err.message });
  }
});

// 5. GET /api/admin/leads - Real live CRM pipeline leads from MongoDB
router.get('/leads', async (req, res) => {
  try {
    const { search } = req.query;
    const { employeeQuery } = await buildTelemetryQuery(req.query);
    let conditions = [];

    if (employeeQuery && Object.keys(employeeQuery).length > 0) {
      const teamCallers = await Employee.find({ ...employeeQuery });
      const names = teamCallers.map(c => c.name).filter(Boolean);
      const phones = teamCallers.map(c => c.phone).filter(Boolean);
      if (names.length > 0 || phones.length > 0) {
        conditions.push({
          $or: [
            { assignedCaller: { $in: names.map(n => new RegExp(`^${n}$`, 'i')) } },
            { phone: { $in: phones } }
          ]
        });
      }
    }

    if (search && search.trim()) {
      const s = search.trim();
      conditions.push({
        $or: [
          { name: { $regex: s, $options: 'i' } },
          { phone: { $regex: s, $options: 'i' } },
          { assignedCaller: { $regex: s, $options: 'i' } }
        ]
      });
    }

    const query = conditions.length > 0 ? (conditions.length === 1 ? conditions[0] : { $and: conditions }) : {};
    const leads = await Lead.find(query).sort({ updatedAt: -1 });
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

// Update lead status in CRM pipeline (POST & PUT)
router.all(['/leads/:id/status', '/leads/status'], async (req, res) => {
  try {
    const rawId = req.params.id || req.body.id || req.body.phone || '';
    const { status, notes, note, name, phone, callerName } = req.body;
    const finalPhone = phone || (rawId.replace(/[^0-9]/g, '').length >= 6 ? rawId : '');
    const cleanPhone = finalPhone.replace(/[^0-9]/g, '');
    const last10 = cleanPhone.length >= 10 ? cleanPhone.substring(cleanPhone.length - 10) : cleanPhone;

    const isMongoId = /^[0-9a-fA-F]{24}$/.test(rawId);
    const orClauses = [];
    if (isMongoId) orClauses.push({ _id: rawId });
    if (rawId) orClauses.push({ id: rawId });
    if (last10) {
      orClauses.push(
        { phone: finalPhone },
        { phone: new RegExp(last10 + '$') },
        { phone: new RegExp('^' + last10) }
      );
    }

    const query = orClauses.length > 0 ? { $or: orClauses } : { id: Date.now().toString() };

    const updateObj = {
      updatedAt: new Date(),
      ...(status ? { status } : {}),
      ...(notes || note ? { notes: notes || note } : {}),
      ...(name ? { name } : {}),
      ...(finalPhone ? { phone: finalPhone } : {}),
      ...(callerName ? { assignedCaller: callerName } : {})
    };

    let lead = await Lead.findOneAndUpdate(
      query,
      {
        $set: updateObj,
        $setOnInsert: {
          id: req.body.id || Date.now().toString(),
          createdAt: new Date()
        }
      },
      { new: true, upsert: true }
    );

    res.json({ success: true, lead });
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
