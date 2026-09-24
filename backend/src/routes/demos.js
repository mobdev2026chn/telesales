// Demo appointments booked by callers after a call (absolute paths).
// Each booking is for a Team Leader, who runs the demo: it shows in that Team Leader's portal,
// and a Team Leader can have only one booking per slot.
const express = require('express');
const crypto = require('crypto');
const DemoBooking = require('../models/DemoBooking');
const Employee = require('../models/Employee');
const { resolveScope, NOTHING } = require('../services/scope');
const { exactNameRegex, parseDate, parseLimit, serverError } = require('../utils/common');

const router = express.Router();

const cleanText = (v, max) => String(v === undefined || v === null ? '' : v).trim().slice(0, max);

function toDemoDTO(d) {
  return {
    id: d.id,
    leadId: d.leadId || '',
    clientName: d.clientName || '',
    clientPhone: d.clientPhone || '',
    callerId: d.callerId || '',
    callerName: d.callerName || '',
    teamLeaderId: d.teamLeaderId || '',
    teamLeaderName: d.teamLeaderName || '',
    scheduledAt: d.scheduledAt ? new Date(d.scheduledAt).toISOString() : null,
    slot: d.slot || '',
    course: d.course || '',
    reason: d.reason || '',
    status: d.status || 'BOOKED',
    createdAt: d.createdAt || null,
  };
}

// Bookings in scope: made by someone in scope, or run by a Team Leader in scope.
function demoQueryFor(scope) {
  if (!scope || scope.employees.length === 0) return NOTHING;
  const ids = scope.employees.map(e => e.id).filter(Boolean);
  const names = scope.employees.map(e => (e.name || '').trim()).filter(Boolean);
  const or = [];
  if (ids.length) or.push({ callerId: { $in: ids } }, { teamLeaderId: { $in: ids } });
  if (names.length) or.push({ callerId: { $in: [null, ''] }, callerName: { $in: names.map(exactNameRegex) } });
  return or.length ? { $or: or } : NOTHING;
}

// "YYYY-MM-DD" (India date) -> [start, end) of that day
function istDayRange(dateStr) {
  if (!/^\d{4}-\d{2}-\d{2}$/.test(String(dateStr || ''))) return null;
  const start = new Date(`${dateStr}T00:00:00+05:30`);
  if (isNaN(start.getTime())) return null;
  return [start, new Date(start.getTime() + 24 * 60 * 60 * 1000)];
}

// GET /api/demos/team-leaders: Team Leaders a demo can be booked with (any signed-in user).
router.get('/api/demos/team-leaders', async (req, res) => {
  try {
    if (!req.user) return res.status(401).json({ success: false, message: 'Please sign in again.' });
    const rows = await Employee.find({ role: 'team_leader' }).select('id name').lean();
    const teamLeaders = rows.filter(r => r.id).map(r => ({ id: r.id, name: r.name || '' }))
      .sort((a, b) => a.name.localeCompare(b.name));
    res.json({ success: true, teamLeaders });
  } catch (err) { serverError(res, err, 'demos.teamLeaders'); }
});

// GET /api/demos/booked-slots?teamLeaderId=&date=YYYY-MM-DD: slot starts already booked for that TL.
router.get('/api/demos/booked-slots', async (req, res) => {
  try {
    if (!req.user) return res.status(401).json({ success: false, message: 'Please sign in again.' });
    const teamLeaderId = cleanText(req.query.teamLeaderId, 80);
    const range = istDayRange(req.query.date);
    if (!teamLeaderId || !range) return res.status(400).json({ success: false, message: 'teamLeaderId and date (YYYY-MM-DD) are required.' });
    const rows = await DemoBooking.find({ teamLeaderId, status: 'BOOKED', scheduledAt: { $gte: range[0], $lt: range[1] } })
      .select('scheduledAt').lean();
    res.json({ success: true, slots: rows.map(r => new Date(r.scheduledAt).toISOString()) });
  } catch (err) { serverError(res, err, 'demos.bookedSlots'); }
});

// POST /api/demos: the signed-in caller books a demo with a Team Leader.
router.post(['/api/demos', '/api/user/demos'], async (req, res) => {
  try {
    if (!req.user) return res.status(401).json({ success: false, message: 'Please sign in again.' });
    const b = req.body || {};
    const clientName = cleanText(b.clientName, 120);
    const scheduledAt = parseDate(b.scheduledAt);
    if (!clientName) return res.status(400).json({ success: false, message: 'Client name is required.' });
    if (!scheduledAt) return res.status(400).json({ success: false, message: 'Pick a date and time slot.' });
    // A small allowance for phone clocks that run slightly ahead
    if (scheduledAt.getTime() < Date.now() - 5 * 60 * 1000) {
      return res.status(400).json({ success: false, message: 'The demo slot must be in the future.' });
    }
    // Team Leader: optional for older app builds, must be a real Team Leader when given
    let teamLeader = null;
    const teamLeaderId = cleanText(b.teamLeaderId, 80);
    if (teamLeaderId) {
      teamLeader = await Employee.findOne({ id: teamLeaderId, role: 'team_leader' }).select('id name').lean();
      if (!teamLeader) return res.status(400).json({ success: false, message: 'Choose a valid Team Leader.' });
      const taken = await DemoBooking.exists({ teamLeaderId, status: 'BOOKED', scheduledAt });
      if (taken) {
        return res.status(409).json({ success: false, message: `This slot is already booked for ${teamLeader.name}. Pick another slot.` });
      }
    }
    const demo = await DemoBooking.create({
      id: crypto.randomUUID(),
      leadId: cleanText(b.leadId, 80),
      clientName,
      clientPhone: cleanText(b.clientPhone, 40),
      callerId: req.user.id,
      callerName: cleanText(req.user.name, 120),
      callerPhone: cleanText(req.user.phone, 40),
      teamLeaderId: teamLeader ? teamLeader.id : '',
      teamLeaderName: teamLeader ? cleanText(teamLeader.name, 120) : '',
      scheduledAt,
      slot: cleanText(b.slot, 60),
      course: cleanText(b.course, 120),
      reason: cleanText(b.reason, 2000),
    });
    res.status(201).json({ success: true, demo: toDemoDTO(demo.toObject()) });
  } catch (err) { serverError(res, err, 'demos.create'); }
});

// GET /api/demos: bookings in the user's scope (admin: all, manager / team leader: own team plus
// demos they run, caller: own). ?from=&to= filter on the demo time.
router.get(['/api/demos', '/api/admin/demos'], async (req, res) => {
  try {
    const scope = await resolveScope(req, req.query);
    const conditions = [scope.all ? {} : demoQueryFor(scope)];
    const from = parseDate(req.query.from);
    const to = parseDate(req.query.to);
    if (from || to) conditions.push({ scheduledAt: { ...(from ? { $gte: from } : {}), ...(to ? { $lte: to } : {}) } });
    const limit = parseLimit(req.query.limit, 1000, 5000);
    const rows = await DemoBooking.find(conditions.length === 1 ? conditions[0] : { $and: conditions })
      .sort({ scheduledAt: -1 }).limit(limit).lean();
    res.json({ success: true, demos: rows.map(toDemoDTO) });
  } catch (err) { serverError(res, err, 'demos.list'); }
});

module.exports = router;
module.exports.toDemoDTO = toDemoDTO;
