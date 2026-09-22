// Mounted at /api/admin (dashboard + leaderboard are also reachable via /api/dashboard/stats and
// /api/employees/leaderboard). Recordings, leads, photo and notifications live in their own routers.
const express = require('express');
const router = express.Router();
const CallLog = require('../models/CallLog');
const Employee = require('../models/Employee');
const Lead = require('../models/Lead');
const { hashPassword, forgetProfile } = require('../middleware/auth');
const { getPeriodRange, aggregateCallStats, findCallerStats, buildDedupKey } = require('../services/callStats');
const { resolveScope, callLogQueryFor, leadQueryFor, MANAGER_ROLES } = require('../services/scope');
const { isOnline, breakInfo } = require('../services/presence');
const { escapeRegex, last10, byIdQuery, phoneRegex, serverError, parseLimit, parseDate } = require('../utils/common');

const DEFAULT_TEAM = 'Telesales Team';
const ROLES = ['caller', 'jr_manager', 'manager', 'admin'];
const and = (...conds) => {
  const list = conds.filter(c => c && Object.keys(c).length > 0);
  if (list.length === 0) return {};
  return list.length === 1 ? list[0] : { $and: list };
};

// Scope (from the token) + period (IST) for call logs
async function telemetry(req) {
  const scope = await resolveScope(req, req.query);
  const scopeQuery = callLogQueryFor(scope);
  const range = getPeriodRange(req.query);
  return { scope, range, callLogQuery: and(scopeQuery, range ? { timestamp: range } : null) };
}

function memberStats(emp, stats) {
  const found = findCallerStats(stats.byCaller, emp) || {};
  const n = (k) => Math.round(found[k] || 0);
  return {
    totalCalls: n('totalCalls'),
    connectedCalls: n('connectedCalls'),
    incomingCalls: n('incoming'),
    outgoingCalls: n('outgoing'),
    missedCalls: n('missed'),
    rejectedCalls: n('rejected'),
    neverAttendedCalls: n('neverAttended'),
    talkTimeSeconds: n('talkSeconds'),
  };
}

const fmtHM = (sec) => `${Math.floor(sec / 3600)}h ${Math.floor((sec % 3600) / 60).toString().padStart(2, '0')}m`;

// 1. GET /api/admin/dashboard
router.get('/dashboard', async (req, res) => {
  try {
    const { scope, range, callLogQuery } = await telemetry(req);
    const isMgr = MANAGER_ROLES.includes(scope.role) && !!req.user;

    const stats = await aggregateCallStats(callLogQuery);
    const { totalCalls, connectedCalls, incoming, outgoing, missed, rejected, neverAttended, talkSeconds } = stats;

    const avgDurationSec = connectedCalls > 0 ? Math.round(talkSeconds / connectedCalls) : 0;
    const avgH = Math.floor(avgDurationSec / 3600);
    const avgM = Math.floor((avgDurationSec % 3600) / 60);
    const avgS = avgDurationSec % 60;
    const avgDurationFormatted = avgH > 0
      ? `${avgH}h ${avgM.toString().padStart(2, '0')}m`
      : `${avgM}m ${avgS.toString().padStart(2, '0')}s`;

    // Hourly distribution in India time (8 AM – 9 PM)
    const hourLabels = [
      { h: 8, label: '8A' }, { h: 9, label: '9A' }, { h: 10, label: '10A' }, { h: 11, label: '11A' },
      { h: 12, label: '12P' }, { h: 13, label: '1P' }, { h: 14, label: '2P' }, { h: 15, label: '3P' },
      { h: 16, label: '4P' }, { h: 17, label: '5P' }, { h: 18, label: '6P' }, { h: 19, label: '7P' },
      { h: 20, label: '8P' }, { h: 21, label: '9P' },
    ];
    const hourlyCalls = hourLabels.map(hl => ({ hour: hl.label, hourOfDay: hl.h, calls: stats.hourly[hl.h] || 0, isPeak: false }));
    const maxHourlyCalls = Math.max(0, ...hourlyCalls.map(h => h.calls));
    hourlyCalls.forEach(item => { item.isPeak = item.calls > 0 && item.calls === maxHourlyCalls; });

    // Registered members in scope; their numbers come from the same aggregation so they add up to the totals
    const registeredEmployees = [...scope.employees].sort((a, b) => new Date(b.createdAt || 0) - new Date(a.createdAt || 0));
    const teamMemberStats = registeredEmployees.map(emp => {
      const m = memberStats(emp, stats);
      const target = Number.isFinite(emp.dailyTarget) ? emp.dailyTarget : Employee.DEFAULT_DAILY_TARGET;
      return {
        id: emp.id,
        name: emp.name,
        email: emp.email || '',
        phone: emp.phone,
        role: emp.role || 'caller',
        team: emp.team || DEFAULT_TEAM,
        managerId: emp.managerId || '',
        managerName: emp.managerName || '',
        dailyTarget: target,
        online: isOnline(emp),
        lastSeenAt: emp.lastSeenAt || null,
        ...breakInfo(emp),
        ...m,
        talkTimeFormatted: fmtHM(m.talkTimeSeconds),
        progressPercent: Math.min(Math.round((m.totalCalls / target) * 100), 100),
      };
    });

    let topPerformer = { name: 'NO CALLERS / CALLS LOGGED YET', duration: '0h 00m' };
    const top = [...teamMemberStats].filter(m => m.totalCalls > 0).sort((a, b) => b.talkTimeSeconds - a.talkTimeSeconds)[0];
    if (top) {
      topPerformer = {
        name: (top.name || top.phone || 'CALLER').toUpperCase(),
        duration: `${Math.floor(top.talkTimeSeconds / 3600)}H ${Math.floor((top.talkTimeSeconds % 3600) / 60)}M`,
      };
    }

    const teamDailyTarget = registeredEmployees.reduce((sum, emp) => sum + (Number.isFinite(emp.dailyTarget) ? emp.dailyTarget : Employee.DEFAULT_DAILY_TARGET), 0);

    // Ratios: numerator uses the same scope and period as the denominator
    const connectRatioPercent = totalCalls > 0 ? +((connectedCalls / totalCalls) * 100).toFixed(1) : 0;
    const leadScope = scope.all ? {} : leadQueryFor(scope);
    const interestedCount = await Lead.countDocuments(and(
      leadScope,
      { status: { $in: ['interested', 'won'] } },
      range ? { lastCallDate: range } : null,
    ));
    const conversionRatioPercent = connectedCalls > 0 ? +((interestedCount / connectedCalls) * 100).toFixed(1) : 0;
    const totalIO = incoming + outgoing;
    const inboundPercent = totalIO > 0 ? +((incoming / totalIO) * 100).toFixed(1) : 0;
    const outboundPercent = totalIO > 0 ? +((outgoing / totalIO) * 100).toFixed(1) : 0;

    // Live status: a call in the last 15 minutes
    const fifteenMinsAgo = new Date(Date.now() - 15 * 60 * 1000);
    const recent = await CallLog.find(and(callLogQueryFor(scope), { timestamp: { $gte: fifteenMinsAgo } }))
      .select('callerId callerPhone').lean();
    const recentIds = new Set(recent.map(r => r.callerId).filter(Boolean));
    const recentPhones = new Set(recent.map(r => last10(r.callerPhone)).filter(Boolean));
    const callerLiveStatuses = teamMemberStats.map(emp => {
      const active = recentIds.has(emp.id) || (last10(emp.phone) && recentPhones.has(last10(emp.phone)));
      return {
        id: emp.id,
        name: emp.name,
        phone: emp.phone,
        managerName: emp.managerName,
        status: active ? 'ON CALL' : (emp.onBreak ? 'ON BREAK' : (emp.online ? 'ONLINE' : 'OFFLINE')),
        statusColor: active ? '#FF3B30' : (emp.onBreak ? '#F5A524' : (emp.online ? '#34C759' : '#8E8E93')),
        onBreak: emp.onBreak,
        breakType: emp.breakType,
        breakStartedAt: emp.breakStartedAt,
        totalCalls: emp.totalCalls,
      };
    });

    // Directory data for filters: managers see the people in their scope, callers only themselves
    const visible = isMgr ? (scope.role === 'admin' ? await Employee.find({}).select('-photoBase64 -avatarUrl').lean() : await resolveScope(req, {}).then(s => s.employees)) : (scope.me ? [scope.me] : []);
    const allUsers = visible
      .filter(u => scope.role === 'admin' || u.role !== 'admin')
      .map(u => ({ id: u.id, _id: u._id, name: u.name, email: u.email || '', phone: u.phone, role: u.role, team: u.team || DEFAULT_TEAM, managerId: u.managerId || '', managerName: u.managerName || '', dailyTarget: Number.isFinite(u.dailyTarget) ? u.dailyTarget : Employee.DEFAULT_DAILY_TARGET }))
      .sort((a, b) => (a.name || '').localeCompare(b.name || ''));
    const managersList = allUsers.filter(u => MANAGER_ROLES.includes(u.role))
      .map(u => ({ id: u.id, name: u.name, email: u.email, phone: u.phone, role: u.role, team: u.team }));
    const teamNames = [...new Set(allUsers.map(u => (u.team || '').trim()).filter(Boolean))].sort();
    const teams = ['ALL TEAMS', ...(teamNames.length ? teamNames : [DEFAULT_TEAM])];

    res.json({
      success: true,
      data: {
        totalCalls,
        connectedCalls,
        talkSeconds,
        talkTimeFormatted: fmtHM(talkSeconds),
        avgDurationSeconds: avgDurationSec,
        avgDurationFormatted,
        uniqueClients: stats.uniqueClients,
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
        // Every hour 0-23 (India time); sums to totalCalls
        hourlyAll: Array.from({ length: 24 }, (_, h) => ({ hourOfDay: h, calls: stats.hourly[h] || 0 })),
        teamMembers: teamMemberStats,
        managersList,
        teams,
        allUsers,
      }
    });
  } catch (err) {
    serverError(res, err, 'admin.dashboard');
  }
});

// GET /api/admin/calls — managers. ?from=&to=&callerId=&limit=(1000, max 5000)&before=&type=&search=
router.get('/calls', async (req, res) => {
  try {
    const { type, search } = req.query;
    const { scope, callLogQuery } = await telemetry(req);

    const conditions = [callLogQuery];
    const from = parseDate(req.query.from);
    const to = parseDate(req.query.to);
    if (from || to) conditions.push({ timestamp: { ...(from ? { $gte: from } : {}), ...(to ? { $lte: to } : {}) } });

    if (type && type !== 'all') {
      if (type === 'inbound') conditions.push({ type: 'incoming' });
      else if (type === 'outbound') conditions.push({ type: 'outgoing' });
      else if (type === 'missed') conditions.push({ type: { $in: ['missed', 'neverAttended', 'rejected'] } });
    }
    if (search && String(search).trim()) {
      const re = new RegExp(escapeRegex(String(search).trim()), 'i');
      conditions.push({ $or: [{ callerName: re }, { contactName: re }, { phoneNumber: re }] });
    }
    const query = and(...conditions);
    const before = parseDate(req.query.before);
    const pageQuery = before ? and(query, { timestamp: { $lt: before } }) : query;
    const limit = parseLimit(req.query.limit, 1000, 5000);

    // Total counted exactly like the dashboard (aggregateCallStats): legacy duplicate rows count once
    const [rawCalls, totalAgg] = await Promise.all([
      CallLog.find(pageQuery).sort({ timestamp: -1, _id: -1 }).limit(limit + 1).lean(),
      CallLog.aggregate([
        { $match: query },
        { $group: { _id: { c: '$callerPhone', p: '$phoneNumber', t: '$timestamp' } } },
        { $count: 'n' },
      ]).allowDiskUse(true),
    ]);
    const total = totalAgg.length ? totalAgg[0].n : 0;
    const hasMore = rawCalls.length > limit;

    const byId = new Map(scope.employees.map(e => [e.id, e]));
    const byPhone = new Map(scope.employees.filter(e => last10(e.phone)).map(e => [last10(e.phone), e]));

    // Collapse legacy duplicate rows (same caller + number + exact timestamp). Quick redials are real calls and are kept.
    const seen = new Set();
    const calls = [];
    for (const c of rawCalls.slice(0, limit)) {
      const ts = c.timestamp || c.createdAt;
      const dupKey = buildDedupKey(c.callerPhone, c.phoneNumber, ts);
      if (seen.has(dupKey)) continue;
      seen.add(dupKey);
      const emp = byId.get(c.callerId) || byPhone.get(last10(c.callerPhone));
      const isOutbound = c.type === 'outgoing';
      const contact = (c.contactName || '').trim();
      const durationSeconds = Math.max(0, Math.round(c.durationSeconds || 0));
      calls.push({
        id: String(c._id),
        callerId: emp ? emp.id : (c.callerId || ''),
        callerName: emp ? emp.name : (c.callerName || ''),
        callerPhone: c.callerPhone || '',
        contactName: contact && !['unknown', 'unknown contact'].includes(contact.toLowerCase()) && contact !== c.phoneNumber ? contact : null,
        phoneNumber: c.phoneNumber,
        type: isOutbound ? 'OUTBOUND' : (c.type === 'incoming' ? 'INBOUND' : 'MISSED'),
        rawType: c.type,
        durationSeconds,
        durationStr: `${Math.floor(durationSeconds / 60)}m ${durationSeconds % 60}s`,
        timestamp: ts,
        simSlot: c.simSlot || 1,
        recordingId: c.recordingId || null,
        recordingUrl: c.recordingId ? `/api/recordings/${c.recordingId}/audio` : (c.recordingUrl || ''),
        note: c.note || '',
      });
    }

    res.json({ success: true, count: calls.length, total, hasMore, calls });
  } catch (err) {
    serverError(res, err, 'admin.calls');
  }
});

// ---- Users -------------------------------------------------------------------------------------
async function findDuplicate({ email, phone }, excludeId = null) {
  const or = [];
  if (email) or.push({ email: String(email).toLowerCase().trim() });
  const pr = last10(phone).length === 10 ? phoneRegex(phone) : null;
  if (pr) or.push({ phone: pr });
  if (!or.length) return null;
  return Employee.findOne({ $or: or, ...(excludeId ? { id: { $ne: excludeId } } : {}) }).lean();
}

async function managerNameFor(managerId) {
  if (!managerId) return '';
  const mgr = await Employee.findOne(byIdQuery(managerId)).lean();
  return mgr ? mgr.name : '';
}

// GET /api/admin/users — managers (never returns passwords)
router.get('/users', async (req, res) => {
  try {
    const users = await Employee.find().sort({ createdAt: -1 });
    res.json({ success: true, count: users.length, users });
  } catch (err) {
    serverError(res, err, 'admin.users.list');
  }
});

// POST /api/admin/users — managers; name + phone + password (min 6) required
router.post('/users', async (req, res) => {
  try {
    const b = req.body || {};
    const name = typeof b.name === 'string' ? b.name.trim() : '';
    const phone = typeof b.phone === 'string' ? b.phone.trim() : String(b.phone || '').trim();
    const password = typeof b.password === 'string' ? b.password : '';
    const email = typeof b.email === 'string' && b.email.trim() ? b.email.toLowerCase().trim() : undefined;
    const role = b.role ? String(b.role).toLowerCase() : 'caller';

    if (!name) return res.status(400).json({ success: false, message: 'Name is required' });
    if (last10(phone).length !== 10) return res.status(400).json({ success: false, message: 'A valid 10-digit phone number is required' });
    if (password.trim().length < 6) return res.status(400).json({ success: false, message: 'Password must be at least 6 characters' });
    if (!ROLES.includes(role)) return res.status(400).json({ success: false, message: `role must be one of ${ROLES.join(', ')}` });
    if (role === 'admin' && req.user.role !== 'admin') {
      return res.status(403).json({ success: false, message: 'Only an admin can create an admin.' });
    }
    if (email && !/^[^\s@]+@[^\s@]+\.[^\s@]+$/.test(email)) return res.status(400).json({ success: false, message: 'Invalid email' });

    const dup = await findDuplicate({ email, phone });
    if (dup) return res.status(409).json({ success: false, message: 'A user with this email or phone number already exists' });

    const managerId = b.managerId ? String(b.managerId) : '';
    const managerName = typeof b.managerName === 'string' && b.managerName ? b.managerName : await managerNameFor(managerId);
    const dailyTarget = b.dailyTarget !== undefined && b.dailyTarget !== '' ? Math.max(0, Math.round(Number(b.dailyTarget) || 0)) : Employee.DEFAULT_DAILY_TARGET;

    const newUser = await Employee.create({
      id: `user_${Date.now()}_${Math.random().toString(36).substring(2, 6)}`,
      name,
      ...(email ? { email } : {}),
      phone,
      password: await hashPassword(password.trim()),
      role,
      team: typeof b.team === 'string' && b.team.trim() ? b.team.trim() : DEFAULT_TEAM,
      dailyTarget,
      managerId,
      managerName,
    });

    res.status(201).json({ success: true, user: newUser, message: 'User created successfully' });
  } catch (err) {
    if (err && err.name === 'ValidationError') return res.status(400).json({ success: false, message: 'Invalid user data' });
    serverError(res, err, 'admin.users.create');
  }
});

// PUT /api/admin/users/:id — managers; omitted fields are left unchanged
router.put('/users/:id', async (req, res) => {
  try {
    const b = req.body || {};
    const target = await Employee.findOne(byIdQuery(req.params.id)).lean();
    if (!target) return res.status(404).json({ success: false, message: 'User not found' });

    const isAdmin = req.user.role === 'admin';
    if (target.role === 'admin' && !isAdmin) {
      return res.status(403).json({ success: false, message: 'Only an admin can modify an admin account.' });
    }

    const set = {};
    if (b.name !== undefined) {
      const name = String(b.name).trim();
      if (!name) return res.status(400).json({ success: false, message: 'Name cannot be empty' });
      set.name = name;
    }
    if (b.email !== undefined) {
      const email = String(b.email || '').toLowerCase().trim();
      if (email && !/^[^\s@]+@[^\s@]+\.[^\s@]+$/.test(email)) return res.status(400).json({ success: false, message: 'Invalid email' });
      set.email = email || undefined;
    }
    if (b.phone !== undefined) {
      const phone = String(b.phone || '').trim();
      if (last10(phone).length !== 10) return res.status(400).json({ success: false, message: 'A valid 10-digit phone number is required' });
      set.phone = phone;
    }
    if (b.role !== undefined) {
      const role = String(b.role).toLowerCase();
      if (!ROLES.includes(role)) return res.status(400).json({ success: false, message: `role must be one of ${ROLES.join(', ')}` });
      if (role === 'admin' && !isAdmin) return res.status(403).json({ success: false, message: 'Only an admin can promote a user to admin.' });
      set.role = role;
    }
    if (b.team !== undefined) set.team = String(b.team || '').trim() || DEFAULT_TEAM;
    if (b.dailyTarget !== undefined && b.dailyTarget !== '') {
      const n = Number(b.dailyTarget);
      if (!Number.isFinite(n) || n < 0) return res.status(400).json({ success: false, message: 'dailyTarget must be a positive number' });
      set.dailyTarget = Math.round(n);
    }
    if (b.managerId !== undefined) {
      set.managerId = b.managerId ? String(b.managerId) : '';
      set.managerName = b.managerName !== undefined ? String(b.managerName || '') : await managerNameFor(set.managerId);
    } else if (b.managerName !== undefined) {
      set.managerName = String(b.managerName || '');
    }
    if (b.password !== undefined && b.password !== null && String(b.password).trim() !== '') {
      if (String(b.password).trim().length < 6) return res.status(400).json({ success: false, message: 'Password must be at least 6 characters' });
      set.password = await hashPassword(String(b.password).trim());
    }

    if (set.email || set.phone) {
      const dup = await findDuplicate({ email: set.email, phone: set.phone }, target.id);
      if (dup) return res.status(409).json({ success: false, message: 'A user with this email or phone number already exists' });
    }

    const unset = {};
    if ('email' in set && set.email === undefined) { delete set.email; unset.email = 1; }
    const update = { ...(Object.keys(set).length ? { $set: set } : {}), ...(Object.keys(unset).length ? { $unset: unset } : {}) };
    const updated = Object.keys(update).length
      ? await Employee.findOneAndUpdate({ _id: target._id }, update, { new: true, runValidators: true })
      : await Employee.findById(target._id);
    forgetProfile(target.id); // new role / team applies to their open sessions straight away

    res.json({ success: true, user: updated, message: 'User updated successfully' });
  } catch (err) {
    if (err && err.name === 'ValidationError') return res.status(400).json({ success: false, message: 'Invalid user data' });
    serverError(res, err, 'admin.users.update');
  }
});

// DELETE /api/admin/users/:id — admin only (ROUTE_RULES)
router.delete('/users/:id', async (req, res) => {
  try {
    const paramId = req.params.id;
    const target = await Employee.findOne(byIdQuery(paramId)).lean();
    if (!target) return res.status(404).json({ success: false, message: 'User not found' });
    if (req.user && target.id === req.user.id) {
      return res.status(400).json({ success: false, message: 'You cannot delete your own account.' });
    }
    if (target.role === 'admin' && (await Employee.countDocuments({ role: 'admin' })) <= 1) {
      return res.status(400).json({ success: false, message: 'The last admin account cannot be deleted.' });
    }
    await Employee.deleteOne({ _id: target._id });
    forgetProfile(target.id);
    res.json({ success: true, message: 'User deleted successfully' });
  } catch (err) {
    serverError(res, err, 'admin.users.delete');
  }
});

// GET /api/admin/leaderboard — callers in scope, real per-caller counts for the period
router.get('/leaderboard', async (req, res) => {
  try {
    const { scope, callLogQuery } = await telemetry(req);
    // Everyone who can make calls (managers in caller mode too), the same people as the dashboard's
    // team table, so per-person numbers and their sum match the dashboard
    const callers = scope.employees.filter(e => (e.role || 'caller') !== 'admin');
    const stats = await aggregateCallStats(callLogQuery);
    const photos = callers.length
      ? await Employee.find({ id: { $in: callers.map(c => c.id) } }).select('id photoBase64 avatarUrl').lean()
      : [];
    const photoById = new Map(photos.map(p => [p.id, p]));

    const employees = callers.map(emp => {
      const m = memberStats(emp, stats);
      const photo = photoById.get(emp.id) || {};
      return {
        id: emp.id,
        name: emp.name,
        phone: emp.phone,
        role: emp.role || 'caller',
        team: emp.team || DEFAULT_TEAM,
        managerId: emp.managerId || '',
        managerName: emp.managerName || '',
        dailyTarget: Number.isFinite(emp.dailyTarget) ? emp.dailyTarget : Employee.DEFAULT_DAILY_TARGET,
        ...m,
        talkTimeFormatted: fmtHM(m.talkTimeSeconds),
        avatarUrl: photo.avatarUrl || '',
        photoBase64: photo.photoBase64 || '',
      };
    });

    // Places by connected calls, then talk time, then total calls
    employees.sort((a, b) => b.connectedCalls - a.connectedCalls || b.talkTimeSeconds - a.talkTimeSeconds || b.totalCalls - a.totalCalls || (a.name || '').localeCompare(b.name || ''));
    employees.forEach((emp, i) => { emp.rank = i + 1; });

    res.json({ success: true, count: employees.length, employees });
  } catch (err) {
    serverError(res, err, 'admin.leaderboard');
  }
});

module.exports = router;
