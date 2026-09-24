// Demo appointments booked by callers after a call (absolute paths).
const express = require('express');
const crypto = require('crypto');
const DemoBooking = require('../models/DemoBooking');
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
    scheduledAt: d.scheduledAt ? new Date(d.scheduledAt).toISOString() : null,
    slot: d.slot || '',
    reason: d.reason || '',
    status: d.status || 'BOOKED',
    createdAt: d.createdAt || null,
  };
}

// Bookings made by employees in scope (by id; exact name for rows without an id).
function demoQueryFor(scope) {
  if (!scope || scope.employees.length === 0) return NOTHING;
  const ids = scope.employees.map(e => e.id).filter(Boolean);
  const names = scope.employees.map(e => (e.name || '').trim()).filter(Boolean);
  const or = [];
  if (ids.length) or.push({ callerId: { $in: ids } });
  if (names.length) or.push({ callerId: { $in: [null, ''] }, callerName: { $in: names.map(exactNameRegex) } });
  return or.length ? { $or: or } : NOTHING;
}

// POST /api/demos: the signed-in caller books a demo.
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
    const demo = await DemoBooking.create({
      id: crypto.randomUUID(),
      leadId: cleanText(b.leadId, 80),
      clientName,
      clientPhone: cleanText(b.clientPhone, 40),
      callerId: req.user.id,
      callerName: cleanText(req.user.name, 120),
      callerPhone: cleanText(req.user.phone, 40),
      scheduledAt,
      slot: cleanText(b.slot, 60),
      reason: cleanText(b.reason, 2000),
    });
    res.status(201).json({ success: true, demo: toDemoDTO(demo.toObject()) });
  } catch (err) { serverError(res, err, 'demos.create'); }
});

// GET /api/demos: bookings in the user's scope (admin: all, manager: team, caller: own).
// ?from=&to= filter on the demo time.
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
