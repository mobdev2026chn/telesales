// Leads: the ONE implementation of list / create / import / update / status (absolute paths).
const express = require('express');
const Lead = require('../models/Lead');
const Employee = require('../models/Employee');
const { escapeRegex, last10, byIdQuery, serverError, parseLimit, exactNameRegex } = require('../utils/common');
const { resolveScope, leadQueryFor, ownerInScope, MANAGER_ROLES, findEmployeeByRef } = require('../services/scope');
const { LEAD_STATUSES } = require('../services/matching');
const { findLeadsByLast10 } = require('../services/callStats');

const router = express.Router();

function toLeadDTO(l) {
  return {
    id: l.id || String(l._id),
    name: l.name || '',
    phone: l.phone || '',
    status: LEAD_STATUSES.includes(l.status) ? l.status : 'other',
    attempts: Math.max(0, Math.round(Number(l.attempts) || 0)),
    assignedCallerId: l.assignedCallerId || '',
    assignedCaller: l.assignedCaller || '',
    notes: l.notes || '',
    batchName: l.batchName || '',
    managerId: l.managerId || '',
    managerName: l.managerName || '',
    source: l.source || '',
    lastCallDate: l.lastCallDate || null,
    createdAt: l.createdAt || null,
    updatedAt: l.updatedAt || null,
  };
}

const isManager = (req) => !!req.user && MANAGER_ROLES.includes(req.user.role);
const cleanText = (v, max) => (typeof v === 'string' ? v.trim().slice(0, max) : '');

// Is this lead visible/editable for the requester?
async function canTouchLead(req, lead, scope = null) {
  if (req.user && req.user.role === 'admin') return true;
  // Token users: their base scope (body filters must not narrow it). Legacy clients: identified by body params.
  const s = scope || await resolveScope(req, req.user ? {} : null);
  if (s.empty) return false;
  const owner = { id: lead.assignedCallerId || '', name: lead.assignedCaller || '' };
  if (!owner.id && (!owner.name || owner.name === 'Unassigned')) {
    // Unassigned: managers only, and for a batch owned by a manager only that manager's side of the tree
    if (!MANAGER_ROLES.includes(s.role)) return false;
    return !lead.managerId || s.employees.some(e => e.id === lead.managerId);
  }
  return ownerInScope(s, owner);
}

// Resolves an assignee id to an employee inside the requester's scope.
async function resolveAssignee(req, assignedCallerId) {
  if (assignedCallerId === '' || assignedCallerId === null) return { id: '', name: 'Unassigned' };
  const emp = await findEmployeeByRef(assignedCallerId);
  if (!emp) return null;
  if (req.user.role !== 'admin') {
    const scope = await resolveScope(req, {});
    if (!ownerInScope(scope, { id: emp.id })) return null;
  }
  return { id: emp.id, name: emp.name };
}

// ---- GET list ----------------------------------------------------------------------------------
router.get(['/api/leads', '/api/admin/leads', '/api/user/leads'], async (req, res) => {
  try {
    const scope = await resolveScope(req, req.query);
    const conditions = [scope.all ? {} : leadQueryFor(scope)];
    const { status, assignedCallerId } = req.query;
    const q = req.query.q || req.query.search;
    if (status && status !== 'all') conditions.push({ status: String(status) });
    if (assignedCallerId && isManager(req)) conditions.push({ assignedCallerId: String(assignedCallerId) });
    if (q && String(q).trim()) {
      const re = new RegExp(escapeRegex(String(q).trim()), 'i');
      conditions.push({ $or: [{ name: re }, { phone: re }, { assignedCaller: re }] });
    }
    const query = conditions.length === 1 ? conditions[0] : { $and: conditions };

    const limit = parseLimit(req.query.limit, 500, 2000);
    const page = Math.max(1, parseInt(req.query.page, 10) || 1);
    const [rows, total, byStatus] = await Promise.all([
      Lead.find(query).sort({ updatedAt: -1 }).skip((page - 1) * limit).limit(limit).lean(),
      Lead.countDocuments(query),
      Lead.aggregate([{ $match: query }, { $group: { _id: '$status', n: { $sum: 1 } } }]),
    ]);
    const counts = Object.fromEntries(byStatus.map(s => [s._id, s.n]));
    const won = counts.won || 0;
    const interested = counts.interested || 0;
    const followUp = counts.followUp || 0;
    const leads = rows.map(toLeadDTO);

    res.json({
      success: true,
      count: leads.length,
      total,
      page,
      limit,
      hasMore: page * limit < total,
      pipeline: { total, won, interested, followUp, other: Math.max(total - won - interested - followUp, 0), byStatus: counts },
      leads,
      data: leads,
    });
  } catch (err) {
    serverError(res, err, 'leads.list');
  }
});

// ---- POST create (managers) --------------------------------------------------------------------
router.post('/api/admin/leads', async (req, res) => {
  try {
    if (!isManager(req)) return res.status(403).json({ success: false, message: 'You do not have permission for this action.' });
    const name = cleanText(req.body.name, 120);
    const phone = cleanText(req.body.phone, 40);
    const num = last10(phone);
    if (!name) return res.status(400).json({ success: false, message: 'name is required' });
    if (num.length !== 10) return res.status(400).json({ success: false, message: 'A valid 10-digit phone is required' });
    const status = req.body.status || 'new';
    if (!LEAD_STATUSES.includes(status)) return res.status(400).json({ success: false, message: 'Invalid status' });

    const existing = (await findLeadsByLast10([num])).get(num);
    if (existing) return res.status(409).json({ success: false, message: 'A lead with this phone number already exists', lead: toLeadDTO(existing) });

    let assignee = { id: '', name: 'Unassigned' };
    if (req.body.assignedCallerId !== undefined) {
      assignee = await resolveAssignee(req, req.body.assignedCallerId);
      if (!assignee) return res.status(400).json({ success: false, message: 'assignedCallerId is not a caller in your team' });
    }

    const lead = await Lead.create({
      name,
      phone,
      phoneLast10: num,
      status,
      attempts: 0,
      assignedCallerId: assignee.id,
      assignedCaller: assignee.name,
      notes: cleanText(req.body.notes, 2000),
      batchName: cleanText(req.body.batchName, 120),
      source: 'manual',
      lastCallDate: null,
    });
    res.status(201).json({ success: true, lead: toLeadDTO(lead.toObject()) });
  } catch (err) {
    serverError(res, err, 'leads.create');
  }
});

// ---- POST import (managers) --------------------------------------------------------------------
router.post('/api/admin/leads/import', async (req, res) => {
  try {
    if (!isManager(req)) return res.status(403).json({ success: false, message: 'You do not have permission for this action.' });
    const { leads } = req.body || {};
    const batchName = cleanText(req.body.batchName, 120) || `Import ${new Date().toISOString().slice(0, 10)}`;
    if (!Array.isArray(leads)) return res.status(400).json({ success: false, message: 'leads array is required' });
    if (leads.length > 5000) return res.status(400).json({ success: false, message: 'At most 5000 leads per import' });

    // Assignees must be in the importer's scope
    const scope = await resolveScope(req, {});

    // Owning manager (optional): the upload belongs to that manager, who then splits it among their callers
    let owner = null;
    if (req.body.managerId) {
      const m = scope.employees.find(e => e.id === String(req.body.managerId)) ||
        (scope.all ? await Employee.findOne({ id: String(req.body.managerId) }).lean() : null);
      if (!m || !MANAGER_ROLES.includes(m.role || '')) {
        return res.status(400).json({ success: false, message: 'Choose a manager in your team to assign this upload to.' });
      }
      owner = { id: m.id, name: m.name || '' };
    }
    const assigneeCache = new Map();
    const assigneeFor = async (ref) => {
      if (!ref) return { id: '', name: 'Unassigned' };
      if (assigneeCache.has(ref)) return assigneeCache.get(ref);
      const emp = scope.employees.find(e => e.id === ref || String(e._id) === ref) || null;
      const v = emp ? { id: emp.id, name: emp.name } : null;
      assigneeCache.set(ref, v);
      return v;
    };

    const rows = [];
    const seen = new Set();
    let skipped = 0;
    for (const raw of leads) {
      const phone = cleanText(raw && raw.phone !== undefined ? String(raw.phone) : '', 40);
      const num = last10(phone);
      if (num.length !== 10 || seen.has(num)) { skipped++; continue; }
      const assignee = await assigneeFor(raw.assignedCallerId ? String(raw.assignedCallerId) : '');
      if (!assignee) { skipped++; continue; }
      seen.add(num);
      rows.push({
        name: cleanText(raw.name, 120) || phone,
        phone,
        phoneLast10: num,
        status: 'new',
        attempts: 0,
        assignedCallerId: assignee.id,
        assignedCaller: assignee.name,
        notes: cleanText(raw.notes, 2000),
        batchName,
        managerId: owner ? owner.id : '',
        managerName: owner ? owner.name : '',
        source: 'import',
        lastCallDate: null,
      });
    }

    // Skip numbers that already exist
    const existing = await findLeadsByLast10(rows.map(r => r.phoneLast10));
    const toInsert = rows.filter(r => !existing.has(r.phoneLast10));
    skipped += rows.length - toInsert.length;

    const created = toInsert.length
      ? await Lead.insertMany(toInsert.map(r => ({ ...r, id: `lead_${Date.now()}_${Math.random().toString(36).substring(2, 10)}` })), { ordered: false })
      : [];
    res.status(201).json({ success: true, created: created.length, skipped, leads: created.map(l => toLeadDTO(l.toObject ? l.toObject() : l)) });
  } catch (err) {
    serverError(res, err, 'leads.import');
  }
});

// ---- POST distribute (managers): split an upload's unassigned leads among callers ------------------
// body: { batchName, allocations: [{ callerId, count }] }. Oldest unassigned, never-dialled leads of
// the batch go first. Only leads the requester may manage and callers in the requester's team.
router.post('/api/admin/leads/distribute', async (req, res) => {
  try {
    if (!isManager(req)) return res.status(403).json({ success: false, message: 'You do not have permission for this action.' });
    const batchName = cleanText(req.body && req.body.batchName, 120);
    const allocations = Array.isArray(req.body && req.body.allocations) ? req.body.allocations : [];
    if (!batchName) return res.status(400).json({ success: false, message: 'batchName is required' });

    const scope = await resolveScope(req, {});
    const wanted = [];
    for (const a of allocations) {
      const count = Math.max(0, Math.floor(Number(a && a.count) || 0));
      if (!count) continue;
      const emp = scope.employees.find(e => e.id === String(a.callerId)) ||
        (scope.all ? await Employee.findOne({ id: String(a.callerId) }).lean() : null);
      if (!emp || (emp.role || 'caller') === 'admin') {
        return res.status(400).json({ success: false, message: 'One of the callers is not in your team.' });
      }
      wanted.push({ emp, count });
    }
    if (!wanted.length) return res.status(400).json({ success: false, message: 'Enter how many leads each caller should get.' });

    const unassigned = { assignedCallerId: { $in: [null, ''] }, status: 'new', attempts: { $lte: 0 } };
    const managerIds = scope.employees.filter(e => MANAGER_ROLES.includes(e.role || '')).map(e => e.id);
    const ownerCond = scope.all ? {} : { $or: [{ managerId: { $in: managerIds } }, { managerId: { $in: [null, ''] } }] };
    const pool = await Lead.find({ batchName, ...unassigned, ...ownerCond })
      .sort({ createdAt: 1, _id: 1 }).select('_id').lean();

    const needed = wanted.reduce((s, w) => s + w.count, 0);
    if (needed > pool.length) {
      return res.status(400).json({ success: false, message: `Only ${pool.length} unassigned leads are left in this file (you entered ${needed}).` });
    }

    let offset = 0;
    const assigned = [];
    for (const w of wanted) {
      const ids = pool.slice(offset, offset + w.count).map(p => p._id);
      offset += w.count;
      // Re-check "still unassigned" so a concurrent split never hands the same lead to two callers
      const r = await Lead.updateMany({ _id: { $in: ids }, ...unassigned }, { $set: { assignedCallerId: w.emp.id, assignedCaller: w.emp.name || '' } });
      assigned.push({ callerId: w.emp.id, name: w.emp.name || '', count: r.modifiedCount || 0 });
    }
    res.json({ success: true, assigned, remaining: pool.length - offset });
  } catch (err) {
    serverError(res, err, 'leads.distribute');
  }
});

// ---- PUT update --------------------------------------------------------------------------------
// Managers: any field. Callers: status / notes / logAttempt on leads assigned to them.
router.put('/api/admin/leads/:id', async (req, res, next) => {
  if (req.params.id === 'status') return next(); // PUT /api/admin/leads/status is the status endpoint below
  try {
    if (!req.user) return res.status(401).json({ success: false, message: 'Please log in again.', code: 'AUTH_REQUIRED' });
    const lead = await Lead.findOne(byIdQuery(req.params.id));
    if (!lead) return res.status(404).json({ success: false, message: 'Lead not found' });
    if (!(await canTouchLead(req, lead))) return res.status(403).json({ success: false, message: 'This lead is not assigned to you.' });

    const b = req.body || {};
    const manager = isManager(req);
    if (!manager && (b.name !== undefined || b.assignedCallerId !== undefined)) {
      return res.status(403).json({ success: false, message: 'Callers may only change status and notes.' });
    }
    if (b.status !== undefined) {
      if (!LEAD_STATUSES.includes(b.status)) return res.status(400).json({ success: false, message: 'Invalid status' });
      lead.status = b.status;
    }
    if (b.notes !== undefined) lead.notes = cleanText(String(b.notes), 2000);
    if (manager && b.name !== undefined) {
      const name = cleanText(String(b.name), 120);
      if (!name) return res.status(400).json({ success: false, message: 'name cannot be empty' });
      lead.name = name;
    }
    if (manager && b.assignedCallerId !== undefined) {
      const assignee = await resolveAssignee(req, b.assignedCallerId);
      if (!assignee) return res.status(400).json({ success: false, message: 'assignedCallerId is not a caller in your team' });
      lead.assignedCallerId = assignee.id;
      lead.assignedCaller = assignee.name;
    }
    if (b.logAttempt === true) {
      lead.attempts = (lead.attempts || 0) + 1;
      lead.lastCallDate = new Date();
    }
    await lead.save();
    res.json({ success: true, lead: toLeadDTO(lead.toObject()) });
  } catch (err) {
    serverError(res, err, 'leads.update');
  }
});

// ---- Status (existing clients) -----------------------------------------------------------------
// POST/PUT only; an id is required. The body may also carry the lead's phone for leads the app created
// locally; the id itself is never treated as a phone number.
const STATUS_PATHS = ['/api/admin/leads/:id/status', '/api/admin/leads/status', '/api/leads/:id/status', '/api/leads/status', '/api/user/leads/:id/status'];
async function updateStatus(req, res) {
  try {
    const b = req.body || {};
    const id = String(req.params.id || b.id || '').trim();
    if (!id) return res.status(400).json({ success: false, message: 'Lead id is required' });
    const status = b.status;
    if (status !== undefined && status !== null && status !== '' && !LEAD_STATUSES.includes(status)) {
      return res.status(400).json({ success: false, message: 'Invalid status' });
    }

    let lead = await Lead.findOne(byIdQuery(id));
    const num = last10(b.phone);
    if (!lead && num.length === 10) lead = (await findLeadsByLast10([num])).get(num) || null;
    if (lead && !lead.save) lead = await Lead.findById(lead._id);

    if (!lead) {
      // Only a well-formed new lead may be created here (valid 10-digit phone + name)
      const name = cleanText(b.name, 120);
      if (num.length !== 10 || !name) return res.status(404).json({ success: false, message: 'Lead not found' });
      const me = req.user ? await Employee.findOne({ id: req.user.id }).lean() : null;
      lead = await Lead.findOneAndUpdate(
        { phoneLast10: num },
        {
          $setOnInsert: {
            id: `lead_${Date.now()}_${Math.random().toString(36).substring(2, 8)}`,
            name,
            phone: String(b.phone).trim().slice(0, 40),
            status: status || 'new',
            attempts: 0,
            assignedCallerId: me ? me.id : '',
            assignedCaller: me ? me.name : 'Unassigned',
            notes: cleanText(b.notes || b.note, 2000),
            source: 'app',
            batchName: '',
            dateAdded: new Date(),
          }
        },
        { upsert: true, new: true, runValidators: true, setDefaultsOnInsert: true }
      );
      return res.json({ success: true, lead: toLeadDTO(lead.toObject()) });
    }

    if (!(await canTouchLead(req, lead))) return res.status(403).json({ success: false, message: 'This lead is not assigned to you.' });
    if (status) lead.status = status;
    if (b.notes !== undefined || b.note !== undefined) lead.notes = cleanText(String(b.notes !== undefined ? b.notes : b.note), 2000);
    if (b.name && isManager(req)) lead.name = cleanText(b.name, 120) || lead.name;
    if (b.callerName && isManager(req)) {
      const emp = await Employee.findOne({ name: exactNameRegex(b.callerName) }).lean();
      if (emp && (req.user.role === 'admin' || ownerInScope(await resolveScope(req, {}), { id: emp.id }))) {
        lead.assignedCallerId = emp.id;
        lead.assignedCaller = emp.name;
      }
    }
    await lead.save();
    res.json({ success: true, lead: toLeadDTO(lead.toObject()) });
  } catch (err) {
    serverError(res, err, 'leads.status');
  }
}
router.post(STATUS_PATHS, updateStatus);
router.put(STATUS_PATHS, updateStatus);

module.exports = router;
module.exports.toLeadDTO = toLeadDTO;
