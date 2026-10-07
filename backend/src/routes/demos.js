// Demo appointments booked by callers after a call (absolute paths).
// Each booking is for a Team Leader, who runs the demo: it shows in that Team Leader's portal,
// and a Team Leader can have only one booking per slot.
const express = require('express');
const crypto = require('crypto');
const DemoBooking = require('../models/DemoBooking');
const DemoBlock = require('../models/DemoBlock');
const { MANAGERS } = require('../middleware/auth');
const Employee = require('../models/Employee');
const Notification = require('../models/Notification');
const { resolveScope, NOTHING } = require('../services/scope');
const { exactNameRegex, parseDate, parseLimit, serverError } = require('../utils/common');
const { publishForEmployee } = require('../services/realtime');

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
    durationMinutes: durOf(d),
    course: d.course || '',
    reason: d.reason || '',
    status: d.status || 'BOOKED',
    createdAt: d.createdAt || null,
  };
}

const MIN = 60 * 1000;
const HALF_HOUR = 30 * MIN;
const IST_OFFSET = 330 * MIN;
// Length of a booking or block; bookings saved before durationMinutes existed were one hour
const durOf = d => (Number(d.durationMinutes) > 0 ? Number(d.durationMinutes) : 60);
const endMs = d => new Date(d.scheduledAt).getTime() + durOf(d) * MIN;
const cleanDuration = (v, fallback) => ([30, 60].includes(Number(v)) ? Number(v) : fallback);
const isManager = req => !!(req.user && MANAGERS.includes(req.user.role));

function blockDTO(b) {
  return {
    id: b.id,
    teamLeaderId: b.teamLeaderId || '',
    teamLeaderName: b.teamLeaderName || '',
    scheduledAt: b.scheduledAt ? new Date(b.scheduledAt).toISOString() : null,
    durationMinutes: durOf(b),
    reason: b.reason || '',
    blockedByName: b.blockedByName || '',
    createdAt: b.createdAt || null,
  };
}

// Live bookings and blocks overlapping [from, to) for a Team Leader ('' = bookings made without one).
// A block with teamLeaderId '' applies to every Team Leader.
async function occupied(teamLeaderId, from, to) {
  const since = new Date(from.getTime() - 3 * 60 * MIN); // bookings that started earlier but still run
  const [bookings, blocks] = await Promise.all([
    DemoBooking.find({ teamLeaderId, status: 'BOOKED', scheduledAt: { $gte: since, $lt: to } }).lean(),
    DemoBlock.find({ teamLeaderId: { $in: [teamLeaderId, ''] }, scheduledAt: { $gte: since, $lt: to } }).lean(),
  ]);
  const live = d => endMs(d) > from.getTime();
  return { bookings: bookings.filter(live), blocks: blocks.filter(live) };
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
    if (!req.user) return res.status(401).json({ success: false, message: 'Please sign in again.', code: 'AUTH_REQUIRED' });
    const rows = await Employee.find({ role: 'team_leader' }).select('id name').lean();
    const teamLeaders = rows.filter(r => r.id).map(r => ({ id: r.id, name: r.name || '' }))
      .sort((a, b) => a.name.localeCompare(b.name));
    res.json({ success: true, teamLeaders });
  } catch (err) { serverError(res, err, 'demos.teamLeaders'); }
});

// GET /api/demos/booked-slots?teamLeaderId=&date=YYYY-MM-DD: slot starts already booked for that TL.
router.get('/api/demos/booked-slots', async (req, res) => {
  try {
    if (!req.user) return res.status(401).json({ success: false, message: 'Please sign in again.', code: 'AUTH_REQUIRED' });
    const teamLeaderId = cleanText(req.query.teamLeaderId, 80);
    const range = istDayRange(req.query.date);
    if (!teamLeaderId || !range) return res.status(400).json({ success: false, message: 'teamLeaderId and date (YYYY-MM-DD) are required.' });
    const { bookings, blocks } = await occupied(teamLeaderId, range[0], range[1]);
    // Every half-hour and India hour start a booking or block touches, so the hourly picker sees it too
    const starts = new Set();
    for (const d of [...bookings, ...blocks]) {
      const end = endMs(d);
      for (let t = Math.floor(new Date(d.scheduledAt).getTime() / HALF_HOUR) * HALF_HOUR; t < end; t += HALF_HOUR) {
        starts.add(new Date(t).toISOString());
        starts.add(new Date(t - ((t + IST_OFFSET) % (60 * MIN))).toISOString());
      }
    }
    res.json({ success: true, slots: [...starts] });
  } catch (err) { serverError(res, err, 'demos.bookedSlots'); }
});

// GET /api/demos/day?date=YYYY-MM-DD&teamLeaderId=: the Book Demo page's slot grid for one day.
// Other callers' bookings show only who booked them; the caller's own show the client too.
router.get('/api/demos/day', async (req, res) => {
  try {
    if (!req.user) return res.status(401).json({ success: false, message: 'Please sign in again.', code: 'AUTH_REQUIRED' });
    const range = istDayRange(req.query.date);
    if (!range) return res.status(400).json({ success: false, message: 'date (YYYY-MM-DD) is required.' });
    const { bookings, blocks } = await occupied(cleanText(req.query.teamLeaderId, 80), range[0], range[1]);
    res.json({
      success: true,
      bookings: bookings.map(b => {
        const mine = !!b.callerId && b.callerId === req.user.id;
        return {
          id: b.id,
          scheduledAt: new Date(b.scheduledAt).toISOString(),
          durationMinutes: durOf(b),
          callerName: b.callerName || '',
          mine,
          ...(mine ? { clientName: b.clientName || '', clientPhone: b.clientPhone || '', course: b.course || '', reason: b.reason || '' } : {}),
        };
      }),
      blocks: blocks.map(blockDTO),
    });
  } catch (err) { serverError(res, err, 'demos.day'); }
});

// GET /api/demos/blocks?from=&to=: blocked slots (any signed-in user).
router.get('/api/demos/blocks', async (req, res) => {
  try {
    if (!req.user) return res.status(401).json({ success: false, message: 'Please sign in again.', code: 'AUTH_REQUIRED' });
    const from = parseDate(req.query.from);
    const to = parseDate(req.query.to);
    const q = (from || to) ? { scheduledAt: { ...(from ? { $gte: from } : {}), ...(to ? { $lte: to } : {}) } } : {};
    const rows = await DemoBlock.find(q).sort({ scheduledAt: 1 }).limit(5000).lean();
    res.json({ success: true, blocks: rows.map(blockDTO) });
  } catch (err) { serverError(res, err, 'demos.blocks'); }
});

// POST /api/demos/blocks: block a slot from the portal. A Team Leader blocks only their own slots;
// admins and managers block one Team Leader's slot, or every Team Leader's when teamLeaderId is ''.
router.post('/api/demos/blocks', async (req, res) => {
  try {
    if (!isManager(req)) return res.status(403).json({ success: false, message: 'You do not have permission for this action.' });
    const b = req.body || {};
    const scheduledAt = parseDate(b.scheduledAt);
    if (!scheduledAt) return res.status(400).json({ success: false, message: 'Pick a slot to block.' });
    const durationMinutes = cleanDuration(b.durationMinutes, 30);
    const end = new Date(scheduledAt.getTime() + durationMinutes * MIN);
    if (end.getTime() <= Date.now()) return res.status(400).json({ success: false, message: 'This slot has already passed.' });

    let teamLeader = null;
    const teamLeaderId = req.user.role === 'team_leader' ? req.user.id : cleanText(b.teamLeaderId, 80);
    if (teamLeaderId) {
      teamLeader = await Employee.findOne({ id: teamLeaderId, role: 'team_leader' }).select('id name').lean();
      if (!teamLeader) return res.status(400).json({ success: false, message: 'Choose a valid Team Leader.' });
    }

    const near = { scheduledAt: { $gte: new Date(scheduledAt.getTime() - 3 * 60 * MIN), $lt: end } };
    const live = d => endMs(d) > scheduledAt.getTime();
    const blocks = (await DemoBlock.find({ ...near, teamLeaderId: { $in: [teamLeaderId, ''] } }).lean()).filter(live);
    if (blocks.length) return res.status(409).json({ success: false, message: 'This slot is already blocked.' });
    // Blocking for everyone checks every Team Leader's bookings
    const bookings = (await DemoBooking.find({ ...near, status: 'BOOKED', ...(teamLeaderId ? { teamLeaderId } : {}) }).lean()).filter(live);
    if (bookings.length) {
      const one = bookings.length === 1;
      return res.status(409).json({
        success: false,
        message: `This slot already has ${one ? 'a demo' : bookings.length + ' demos'} booked (${bookings.map(x => x.clientName || '—').join(', ')}). Cancel ${one ? 'it' : 'them'} first.`,
      });
    }

    const block = await DemoBlock.create({
      id: crypto.randomUUID(),
      teamLeaderId,
      teamLeaderName: teamLeader ? cleanText(teamLeader.name, 120) : '',
      scheduledAt,
      durationMinutes,
      reason: cleanText(b.reason, 300),
      blockedById: req.user.id,
      blockedByName: cleanText(req.user.name, 120),
    });
    res.status(201).json({ success: true, block: blockDTO(block.toObject()) });
  } catch (err) { serverError(res, err, 'demos.block'); }
});

// DELETE /api/demos/blocks/:id: unblock a slot (a Team Leader only their own).
router.delete('/api/demos/blocks/:id', async (req, res) => {
  try {
    if (!isManager(req)) return res.status(403).json({ success: false, message: 'You do not have permission for this action.' });
    const block = await DemoBlock.findOne({ id: cleanText(req.params.id, 80) }).lean();
    if (!block) return res.status(404).json({ success: false, message: 'This block no longer exists.' });
    if (req.user.role === 'team_leader' && block.teamLeaderId !== req.user.id) {
      return res.status(403).json({ success: false, message: 'You can unblock only your own slots.' });
    }
    await DemoBlock.deleteOne({ id: block.id });
    res.json({ success: true });
  } catch (err) { serverError(res, err, 'demos.unblock'); }
});

// POST /api/demos/:id/cancel: the caller who booked it, or a portal user who can see it, cancels a demo.
router.post('/api/demos/:id/cancel', async (req, res) => {
  try {
    if (!req.user) return res.status(401).json({ success: false, message: 'Please sign in again.', code: 'AUTH_REQUIRED' });
    const demo = await DemoBooking.findOne({ id: cleanText(req.params.id, 80) }).lean();
    if (!demo) return res.status(404).json({ success: false, message: 'This demo no longer exists.' });
    let allowed = !!demo.callerId && demo.callerId === req.user.id;
    if (!allowed && isManager(req)) {
      const scope = await resolveScope(req, {});
      allowed = scope.all || !!(await DemoBooking.exists({ $and: [{ id: demo.id }, demoQueryFor(scope)] }));
    }
    if (!allowed) return res.status(403).json({ success: false, message: 'You can cancel only your own demos.' });
    // A demo sent back for rescheduling is closed this way too, once the caller rebooks or drops it
    if (!['BOOKED', 'RESCHEDULE'].includes(demo.status)) return res.status(400).json({ success: false, message: 'This demo is not active any more.' });
    await DemoBooking.updateOne({ id: demo.id }, { $set: { status: 'CANCELLED' } });
    const updated = await DemoBooking.findOne({ id: demo.id }).lean();
    const eventDemo = toDemoDTO(updated);
    try {
      await publishForEmployee(req, req.user, 'demoUpdated', { demo: eventDemo, id: eventDemo.id }, [demo.teamLeaderId]);
    } catch (err) {
      console.error(`[socket] demoUpdated publish failed demoId=${demo.id}: ${err.message}`);
    }
    res.json({ success: true });
  } catch (err) { serverError(res, err, 'demos.cancel'); }
});

// "10:00 AM - 10:30 AM" in India time, the same label the app saves on a booking
function istSlotLabel(start, minutes) {
  const fmt = (d) => new Intl.DateTimeFormat('en-US', { timeZone: 'Asia/Kolkata', hour: 'numeric', minute: '2-digit', hour12: true }).format(d);
  return `${fmt(start)} - ${fmt(new Date(start.getTime() + minutes * MIN))}`;
}

// POST /api/demos/:id/reschedule: a portal user who can see a demo sends it back to the caller who
// booked it. The slot becomes free (status RESCHEDULE) and the caller books a new slot from the app;
// they get a live update and a notification.
router.post('/api/demos/:id/reschedule', async (req, res) => {
  try {
    if (!isManager(req)) return res.status(403).json({ success: false, message: 'You do not have permission for this action.' });
    const demo = await DemoBooking.findOne({ id: cleanText(req.params.id, 80) }).lean();
    if (!demo) return res.status(404).json({ success: false, message: 'This demo no longer exists.' });
    const scope = await resolveScope(req, {});
    const allowed = scope.all || !!(await DemoBooking.exists({ $and: [{ id: demo.id }, demoQueryFor(scope)] }));
    if (!allowed) return res.status(403).json({ success: false, message: 'You can reschedule only demos in your team.' });
    if (demo.status !== 'BOOKED') return res.status(400).json({ success: false, message: 'This demo is not active any more.' });
    if (!demo.callerId) return res.status(400).json({ success: false, message: 'No caller is linked to this demo. Cancel it instead.' });

    await DemoBooking.updateOne({ id: demo.id }, { $set: { status: 'RESCHEDULE' } });
    const eventDemo = toDemoDTO(await DemoBooking.findOne({ id: demo.id }).lean());
    const oldSlot = `${new Intl.DateTimeFormat('en-IN', { timeZone: 'Asia/Kolkata', weekday: 'short', day: 'numeric', month: 'short' }).format(new Date(demo.scheduledAt))}, ${demo.slot || istSlotLabel(new Date(demo.scheduledAt), durOf(demo))}`;

    // Tell the caller who booked it: live update in the app and portal, plus a notification
    const caller = demo.callerId ? await Employee.findOne({ id: demo.callerId }).lean() : null;
    try {
      await publishForEmployee(req, caller || req.user, 'demoUpdated', { demo: eventDemo, id: eventDemo.id }, [demo.teamLeaderId, demo.callerId]);
    } catch (err) {
      console.error(`[socket] demoUpdated publish failed demoId=${demo.id}: ${err.message}`);
    }
    if (caller) {
      try {
        await Notification.create({
          id: `notif_${Date.now()}_${crypto.randomBytes(3).toString('hex')}`,
          recipientId: caller.id,
          recipientPhone: caller.phone || '',
          recipientName: caller.name || '',
          senderName: cleanText(req.user.name, 120),
          senderRole: req.user.role,
          contactName: demo.clientName || '',
          title: `Reschedule demo · ${demo.clientName || 'client'}`,
          message: `${cleanText(req.user.name, 120) || 'Your team'} asked you to reschedule the demo with ${demo.clientName || 'the client'} (was ${oldSlot}). Open BOOK DEMO and book a new slot.`,
          isRead: false,
        });
      } catch (err) {
        console.error(`demo reschedule notification failed demoId=${demo.id}: ${err.message}`);
      }
    }
    res.json({ success: true, demo: eventDemo });
  } catch (err) { serverError(res, err, 'demos.reschedule'); }
});

// POST /api/demos: the signed-in caller books a demo with a Team Leader.
router.post(['/api/demos', '/api/user/demos'], async (req, res) => {
  try {
    if (!req.user) return res.status(401).json({ success: false, message: 'Please sign in again.', code: 'AUTH_REQUIRED' });
    const b = req.body || {};
    const clientName = cleanText(b.clientName, 120);
    const scheduledAt = parseDate(b.scheduledAt);
    if (!clientName) return res.status(400).json({ success: false, message: 'Client name is required.' });
    if (!scheduledAt) return res.status(400).json({ success: false, message: 'Pick a date and time slot.' });
    // A small allowance for phone clocks that run slightly ahead
    if (scheduledAt.getTime() < Date.now() - 5 * 60 * 1000) {
      return res.status(400).json({ success: false, message: 'The demo slot must be in the future.' });
    }
    const durationMinutes = cleanDuration(b.durationMinutes, 60);
    // Team Leader: optional for older app builds, must be a real Team Leader when given
    let teamLeader = null;
    const teamLeaderId = cleanText(b.teamLeaderId, 80);
    if (teamLeaderId) {
      teamLeader = await Employee.findOne({ id: teamLeaderId, role: 'team_leader' }).select('id name').lean();
      if (!teamLeader) return res.status(400).json({ success: false, message: 'Choose a valid Team Leader.' });
    }
    // One demo at a time per Team Leader, and never in a blocked slot
    const { bookings, blocks } = await occupied(teamLeaderId, scheduledAt, new Date(scheduledAt.getTime() + durationMinutes * MIN));
    if (blocks.length) {
      return res.status(409).json({ success: false, message: 'This slot is blocked by the team leader. Pick another slot.' });
    }
    if (bookings.length) {
      const by = teamLeader ? ` for ${teamLeader.name}` : (bookings[0].callerName ? ` by ${bookings[0].callerName}` : '');
      return res.status(409).json({ success: false, message: `This slot is already booked${by}. Pick another slot.` });
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
      durationMinutes,
      course: cleanText(b.course, 120),
      reason: cleanText(b.reason, 2000),
    });
    const eventDemo = toDemoDTO(demo.toObject());
    try {
      await publishForEmployee(req, req.user, 'demoCreated', { demo: eventDemo, id: eventDemo.id }, [eventDemo.teamLeaderId]);
    } catch (err) {
      console.error(`[socket] demoCreated publish failed demoId=${eventDemo.id}: ${err.message}`);
    }
    res.status(201).json({ success: true, demo: eventDemo });
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
