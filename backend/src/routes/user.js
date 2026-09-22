// Caller-side endpoints: call sync, contact save, profile photo (absolute paths, one implementation each).
const express = require('express');
const CallLog = require('../models/CallLog');
const Recording = require('../models/Recording');
const Lead = require('../models/Lead');
const Employee = require('../models/Employee');
const { syncCallsForCaller, findLeadsByLast10 } = require('../services/callStats');
const { findEmployeeByRef } = require('../services/scope');
const { breakInfo } = require('../services/presence');
const { last10, byIdQuery, phoneRegex, serverError } = require('../utils/common');

const router = express.Router();

// The caller a request acts for: always the token's user; legacy app builds by the body fields.
async function actingEmployee(req, body = req.body || {}) {
  if (req.user) return Employee.findOne({ id: req.user.id }).lean();
  for (const ref of [body.callerId, body.callerPhone, body.callerName]) {
    if (!ref || ref === 'caller_1') continue; // 'caller_1' is a placeholder the old app always sends
    const emp = await findEmployeeByRef(ref);
    if (emp) return emp;
  }
  return null;
}

// POST /api/calls/sync, /api/user/calls/sync — store device call logs for the signed-in caller
router.post(['/api/calls/sync', '/api/user/calls/sync'], async (req, res) => {
  try {
    const { calls } = req.body || {};
    if (!Array.isArray(calls)) {
      return res.status(400).json({ success: false, message: 'Calls array is required' });
    }
    if (calls.length > 5000) {
      return res.status(400).json({ success: false, message: 'At most 5000 calls per sync' });
    }
    const callerEmp = await actingEmployee(req);
    if (!callerEmp || callerEmp.role === 'admin') {
      return res.json({ success: true, count: 0, syncedCount: 0, message: 'Caller not registered in system' });
    }
    const insertedCount = await syncCallsForCaller(callerEmp, calls);
    res.json({
      success: true,
      count: insertedCount,
      syncedCount: insertedCount,
      message: `Synced ${insertedCount} new call logs`,
    });
  } catch (err) {
    serverError(res, err, 'calls.sync');
  }
});

// POST /api/user/contacts/save — save a contact name for a number (lead, call logs, recordings)
router.post(['/api/user/contacts/save', '/api/user/leads/save-contact'], async (req, res) => {
  try {
    const { phoneNumber, notes } = req.body || {};
    const name = typeof req.body.name === 'string' ? req.body.name.trim().slice(0, 120) : '';
    const num = last10(phoneNumber);
    if (num.length !== 10 || !name) {
      return res.status(400).json({ success: false, message: 'A valid 10-digit phoneNumber and a name are required' });
    }
    const me = await actingEmployee(req);
    const re = phoneRegex(phoneNumber);

    let lead = (await findLeadsByLast10([num])).get(num);
    if (lead) {
      const set = { name };
      if (typeof notes === 'string' && notes.trim()) set.notes = notes.trim().slice(0, 2000);
      lead = await Lead.findByIdAndUpdate(lead._id, { $set: set }, { new: true, runValidators: true }).lean();
    } else {
      lead = await Lead.findOneAndUpdate(
        { phoneLast10: num },
        {
          $setOnInsert: {
            id: `lead_${Date.now()}_${Math.random().toString(36).substring(2, 8)}`,
            name,
            phone: String(phoneNumber).trim().slice(0, 40),
            status: 'new',
            attempts: 0,
            assignedCallerId: me ? me.id : '',
            assignedCaller: me ? me.name : 'Unassigned',
            notes: typeof notes === 'string' ? notes.trim().slice(0, 2000) : '',
            source: 'contact',
            batchName: '',
            dateAdded: new Date(),
          }
        },
        { upsert: true, new: true, setDefaultsOnInsert: true }
      ).lean();
    }

    // The saved name applies to this number everywhere (the number is always a full 10 digits here)
    await CallLog.updateMany({ phoneNumber: re }, { $set: { contactName: name } });
    await Recording.updateMany({ phoneNumber: re }, { $set: { contactName: name } });

    res.json({ success: true, lead, message: `Contact "${name}" saved successfully!` });
  } catch (err) {
    serverError(res, err, 'contacts.save');
  }
});

// Profile photo for the signed-in user; an admin may pass userId (or use /admin/users/:id/photo).
router.post(['/api/users/photo', '/api/user/photo', '/api/admin/users/photo', '/api/admin/users/:id/photo'], async (req, res) => {
  try {
    const b = req.body || {};
    const photoBase64 = typeof b.photoBase64 === 'string' ? b.photoBase64 : '';
    let emp = null;
    if (req.user) {
      const requested = req.params.id || b.userId || b.id;
      if (requested && requested !== req.user.id) {
        if (req.user.role !== 'admin') {
          return res.status(403).json({ success: false, message: 'You can only change your own photo.' });
        }
        emp = await Employee.findOne(byIdQuery(requested));
      } else {
        emp = await Employee.findOne({ id: req.user.id });
      }
    } else {
      // Legacy app builds: identified by the fields they send
      const refs = [b.id, b.userId, b.phone, b.email ? String(b.email).toLowerCase() : null, b.name].filter(Boolean);
      for (const ref of refs) {
        const found = ref.includes && ref.includes('@') ? await Employee.findOne({ email: ref }).lean() : await findEmployeeByRef(ref);
        if (found) { emp = await Employee.findById(found._id); break; }
      }
    }
    if (!emp) return res.status(404).json({ success: false, message: 'User not found' });

    const set = { photoBase64 };
    if (typeof b.avatarUrl === 'string') set.avatarUrl = b.avatarUrl.slice(0, 500);
    await Employee.updateOne({ _id: emp._id }, { $set: set });
    const summary = { id: emp.id, name: emp.name, photoBase64 };
    res.json({ success: true, message: 'Profile photo updated successfully', user: summary, employee: summary });
  } catch (err) {
    serverError(res, err, 'users.photo');
  }
});

// POST /api/user/break — the signed-in user started ({onBreak:true, type, startedAt?}) or ended
// ({onBreak:false}) a break in the app; the admin / manager dashboard shows it.
router.post('/api/user/break', async (req, res) => {
  try {
    if (!req.user) return res.status(401).json({ success: false, message: 'Please log in again.', code: 'AUTH_REQUIRED' });
    const b = req.body || {};
    const onBreak = b.onBreak === true || b.onBreak === 'true';
    let set;
    if (onBreak) {
      const type = String(b.type || '').trim().slice(0, 40) || 'Break';
      // The phone's start time (re-sent on app open) keeps the break clock; never in the future or too old
      const now = Date.now();
      const sent = b.startedAt ? new Date(b.startedAt).getTime() : NaN;
      const startedAt = Number.isFinite(sent) && sent <= now + 60 * 1000 && now - sent <= 12 * 60 * 60 * 1000 ? new Date(Math.min(sent, now)) : new Date(now);
      set = { breakType: type, breakStartedAt: startedAt };
    } else {
      set = { breakType: '', breakStartedAt: null };
    }
    const emp = await Employee.findOneAndUpdate({ id: req.user.id }, { $set: set }, { new: true, timestamps: false })
      .select('id breakType breakStartedAt loggedOutAt').lean();
    if (!emp) return res.status(404).json({ success: false, message: 'User not found' });
    res.json({ success: true, ...breakInfo(emp) });
  } catch (err) {
    serverError(res, err, 'user.break');
  }
});

module.exports = router;
