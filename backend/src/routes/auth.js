const express = require('express');
const router = express.Router();
const Employee = require('../models/Employee');
const { signToken, verifyAndUpgradePassword, requireAuth, MANAGERS } = require('../middleware/auth');
const presence = require('../services/presence');

const escapeRegex = (s) => String(s).replace(/[.*+?^${}()|[\]\\]/g, '\\$&');
const last10 = (s) => String(s || '').replace(/[^0-9]/g, '').slice(-10);

function publicUser(emp, extra = {}) {
  return {
    id: emp.id,
    name: emp.name,
    email: emp.email || '',
    phone: emp.phone || '',
    role: emp.role || 'caller',
    team: emp.team || '',
    managerId: emp.managerId || '',
    managerName: emp.managerName || '',
    dailyTarget: Number.isFinite(emp.dailyTarget) ? emp.dailyTarget : Employee.DEFAULT_DAILY_TARGET,
    ...extra,
  };
}

// Finds an employee by email, exact name, id or phone (any formatting of the last 10 digits)
async function findByIdentifier(identifiers) {
  const or = [];
  for (const raw of identifiers) {
    const term = (raw || '').toString().trim();
    if (!term) continue;
    or.push({ email: term.toLowerCase() }, { id: term }, { phone: term }, { name: new RegExp(`^${escapeRegex(term)}$`, 'i') });
    const digits = last10(term);
    if (digits.length === 10) or.push({ phone: new RegExp(digits.split('').join('[^0-9]*') + '$') });
  }
  if (or.length === 0) return null;
  return Employee.findOne({ $or: or }).select('+password');
}

async function login(req, res, { allowedRoles, wrongRoleMessage }) {
  const { email, username, phoneNumber, identifier, password, simSlot } = req.body || {};
  const ids = [identifier, email, username, phoneNumber];
  if (!ids.some(v => v && String(v).trim())) {
    return res.status(400).json({ success: false, message: 'Email or mobile number is required' });
  }
  if (!password || !String(password).trim()) {
    return res.status(400).json({ success: false, message: 'Password is required' });
  }

  const emp = await findByIdentifier(ids);
  // Same message for unknown account and wrong password, so accounts can't be enumerated
  if (!emp || !(await verifyAndUpgradePassword(emp, password))) {
    return res.status(401).json({ success: false, message: 'Invalid email/mobile number or password.' });
  }

  const role = (emp.role || 'caller').toLowerCase();
  if (allowedRoles && !allowedRoles.includes(role)) {
    return res.status(403).json({ success: false, message: wrongRoleMessage(role) });
  }

  const token = signToken(emp);
  presence.touch(emp.id); // online from the moment of login
  return res.json({
    success: true,
    token,
    // `user.token` kept for clients that read it from the user object
    user: publicUser(emp, { token, ...(simSlot ? { simSlot } : {}) }),
    message: 'Authentication successful',
  });
}

// POST /api/auth/login — unified login for web and app
router.post('/login', async (req, res) => {
  try {
    await login(req, res, { allowedRoles: null });
  } catch (err) {
    console.error('login error:', err.message);
    res.status(500).json({ success: false, message: 'Login failed. Please try again.' });
  }
});

// POST /api/auth/admin-login — admin web portal and manager app login
router.post('/admin-login', async (req, res) => {
  try {
    await login(req, res, {
      allowedRoles: MANAGERS,
      wrongRoleMessage: (role) => `This account is registered as ${role.toUpperCase()}, not Admin/Manager.`,
    });
  } catch (err) {
    console.error('admin-login error:', err.message);
    res.status(500).json({ success: false, message: 'Login failed. Please try again.' });
  }
});

// POST /api/auth/caller-verify — caller app login (managers may also enter as caller)
router.post('/caller-verify', async (req, res) => {
  try {
    await login(req, res, {
      allowedRoles: ['caller', ...MANAGERS],
      wrongRoleMessage: (role) => `Access denied for role ${role.toUpperCase()}.`,
    });
  } catch (err) {
    console.error('caller-verify error:', err.message);
    res.status(500).json({ success: false, message: 'Login failed. Please try again.' });
  }
});

// GET /api/auth/me — validates the session token and returns the current profile
router.get('/me', requireAuth(), async (req, res) => {
  try {
    const emp = await Employee.findOne({ id: req.user.id });
    if (!emp) return res.status(401).json({ success: false, message: 'Account no longer exists.', code: 'AUTH_REQUIRED' });
    res.json({ success: true, user: publicUser(emp) });
  } catch (err) {
    res.status(500).json({ success: false, message: 'Could not load profile.' });
  }
});

// POST /api/auth/heartbeat — "still here" from a signed-in app (the auth middleware records it)
router.post('/heartbeat', requireAuth(), (req, res) => {
  res.json({ success: true });
});

// POST /api/auth/logout — marks the user offline straight away
router.post('/logout', requireAuth(), async (req, res) => {
  try {
    await presence.markLoggedOut(req.user.id);
    res.json({ success: true });
  } catch (err) {
    res.status(500).json({ success: false, message: 'Could not log out.' });
  }
});

// POST /api/auth/link-phone — link the signed-in user's own SIM number (admins may link anyone)
router.post('/link-phone', requireAuth({ legacy: true }), async (req, res) => {
  const { userId, email, phone } = req.body || {};
  const digits = last10(phone);
  if (!/^[6-9]\d{9}$/.test(digits)) {
    return res.status(400).json({ success: false, message: 'Please enter a valid 10-digit mobile number.' });
  }

  try {
    let emp = null;
    if (req.user && req.user.role !== 'admin') {
      emp = await Employee.findOne({ id: req.user.id });
    } else {
      if (userId) emp = await Employee.findOne({ id: userId });
      if (!emp && email) emp = await Employee.findOne({ email: String(email).toLowerCase() });
      // Old app builds (no token) may only set a number on an account that has none yet
      if (emp && req.legacyClient && last10(emp.phone).length === 10) {
        return res.status(403).json({ success: false, message: 'Please update the app to change a registered number.' });
      }
    }
    if (!emp) {
      return res.status(404).json({ success: false, message: 'Employee account not found.' });
    }

    const taken = await Employee.findOne({ id: { $ne: emp.id }, phone: new RegExp(digits.split('').join('[^0-9]*') + '$') });
    if (taken) {
      return res.status(409).json({ success: false, message: 'This mobile number is already registered to another user.' });
    }

    emp.phone = digits;
    await emp.save();
    res.json({ success: true, user: publicUser(emp), message: 'Mobile number linked successfully' });
  } catch (err) {
    res.status(500).json({ success: false, message: 'Could not link mobile number.' });
  }
});

// POST /api/auth/check-phone — onboarding: is this mobile number registered?
router.post('/check-phone', async (req, res) => {
  try {
    const { phoneNumber, phone } = req.body || {};
    const digits = last10(phoneNumber || phone);
    if (digits.length !== 10) {
      return res.status(400).json({ success: false, message: 'Please enter a valid 10-digit mobile number' });
    }

    const user = await Employee.findOne({ phone: new RegExp(digits.split('').join('[^0-9]*') + '$') });
    if (!user) {
      return res.status(404).json({
        success: false,
        message: `Mobile number '${digits}' is not registered. Please contact your manager or admin to add your number.`,
      });
    }

    // Only what onboarding needs — no email, team or ids for an unauthenticated caller
    return res.json({
      success: true,
      user: { name: user.name, phone: digits, role: user.role },
      message: `Mobile number '${digits}' verified for ${user.name}!`,
    });
  } catch (err) {
    res.status(500).json({ success: false, message: 'Could not check the number.' });
  }
});

module.exports = router;
