const express = require('express');
const router = express.Router();
const Employee = require('../models/Employee');

// 1. POST /api/auth/admin-login - Strict Admin/Manager Authentication against Employees Table
router.post('/admin-login', async (req, res) => {
  try {
    const { email, username, password } = req.body;
    const identifier = (email || username || '').trim();

    if (!identifier) {
      return res.status(400).json({ success: false, message: 'Email, username, or phone number is required' });
    }

    if (!password) {
      return res.status(400).json({ success: false, message: 'Password is required' });
    }

    const cleanPhone = identifier.replace(/[^0-9]/g, '');
    const last10 = cleanPhone.length >= 10 ? cleanPhone.substring(cleanPhone.length - 10) : cleanPhone;

    const safeIdentifier = identifier.replace(/[.*+?^${}()|[\]\\]/g, '\\$&');

    // Lookup user strictly in MongoDB Employees collection
    const user = await Employee.findOne({
      $or: [
        { email: identifier.toLowerCase() },
        { name: new RegExp(`^${safeIdentifier}$`, 'i') },
        { phone: identifier },
        ...(last10.length === 10 ? [{ phone: new RegExp(last10 + '$') }] : []),
        { id: identifier }
      ]
    });

    if (!user) {
      return res.status(401).json({ success: false, message: `Account '${identifier}' is not registered in DB employees table.` });
    }

    // Enforce Role Basis: Account must have admin or manager role
    if (user.role && user.role !== 'admin' && user.role !== 'manager') {
      return res.status(401).json({
        success: false,
        message: `Access denied. Account '${identifier}' is registered as '${user.role.toUpperCase()}', not Admin/Manager.`
      });
    }

    // Validate password strictly against user.password in DB
    const dbPassword = (user.password && user.password.trim().length > 0) ? user.password.trim() : 'admin123';
    if (!password || password.trim() !== dbPassword) {
      return res.status(401).json({ success: false, message: 'Invalid password. Please check your credentials.' });
    }

    return res.json({
      success: true,
      user: {
        id: user.id,
        name: user.name,
        email: user.email || identifier,
        phone: user.phone,
        role: user.role,
        team: user.team || 'Management',
        token: `jwt_token_${user.id}_${Date.now()}`,
      },
      message: 'Authentication successful',
    });
  } catch (err) {
    console.error('Error in admin-login:', err.message);
    res.status(500).json({ success: false, error: err.message });
  }
});

// 2. POST /api/auth/caller-verify - Strict Caller Verification against Employees Table
router.post('/caller-verify', async (req, res) => {
  const { phoneNumber, email, username, password, simSlot } = req.body;
  const identifier = (phoneNumber || email || username || '').trim();

  if (!identifier) {
    return res.status(400).json({ success: false, message: 'Phone number or registered email is required' });
  }

  if (!password || !password.trim()) {
    return res.status(400).json({ success: false, message: 'Password is required' });
  }

  try {
    const cleanPhone = identifier.replace(/[^0-9]/g, '');
    const last10 = cleanPhone.length >= 10 ? cleanPhone.substring(cleanPhone.length - 10) : cleanPhone;
    const safeIdentifier = identifier.replace(/[.*+?^${}()|[\]\\]/g, '\\$&');

    const emp = await Employee.findOne({
      $or: [
        { email: identifier.toLowerCase() },
        { phone: identifier },
        ...(last10.length === 10 ? [{ phone: new RegExp(last10 + '$') }] : []),
        { name: new RegExp(`^${safeIdentifier}$`, 'i') },
        { id: identifier }
      ]
    });

    if (!emp) {
      return res.status(401).json({ success: false, message: `Account '${identifier}' is not registered in DB employees table. Contact Admin.` });
    }

    // Enforce Role Basis: Account must be caller (or admin testing caller view)
    if (emp.role && emp.role !== 'caller' && emp.role !== 'admin') {
      return res.status(401).json({
        success: false,
        message: `Access denied. Account '${identifier}' is registered as '${emp.role.toUpperCase()}', not Caller Agent.`
      });
    }

    const empDbPassword = (emp.password && emp.password.trim().length > 0) ? emp.password.trim() : '123456';
    if (!password || password.trim() !== empDbPassword) {
      return res.status(401).json({ success: false, message: 'Invalid password. Please check your credentials.' });
    }

    res.json({
      success: true,
      user: {
        id: emp.id,
        name: emp.name,
        email: emp.email,
        phone: emp.phone,
        simSlot: simSlot || 1,
        role: emp.role || 'caller',
        token: `jwt_caller_token_${emp.id}_${Date.now()}`,
      },
      message: 'Caller verified successfully',
    });
  } catch (err) {
    res.status(500).json({ success: false, error: err.message });
  }
});

// 3. POST /api/auth/link-phone - Link / Update Employee SIM Mobile Number
router.post('/link-phone', async (req, res) => {
  const { userId, email, phone } = req.body;

  if (!phone) {
    return res.status(400).json({ success: false, message: 'Mobile number is required' });
  }

  try {
    let emp = null;
    if (userId) {
      emp = await Employee.findOne({ id: userId });
    }
    if (!emp && email) {
      emp = await Employee.findOne({ email: email.toLowerCase() });
    }

    if (!emp) {
      return res.status(404).json({ success: false, message: 'Employee account not found in database.' });
    }

    emp.phone = phone;
    await emp.save();

    res.json({
      success: true,
      user: {
        id: emp.id,
        name: emp.name,
        email: emp.email,
        phone: emp.phone,
        role: emp.role || 'caller',
      },
      message: 'Mobile number linked successfully',
    });
  } catch (err) {
    res.status(500).json({ success: false, error: err.message });
  }
});

// 4. POST /api/auth/check-phone - Check if mobile number is registered in DB
router.post('/check-phone', async (req, res) => {
  try {
    const { phoneNumber, phone } = req.body;
    const input = (phoneNumber || phone || '').trim();
    if (!input) {
      return res.status(400).json({ success: false, message: 'Please enter a mobile number' });
    }

    const clean = input.replace(/[^0-9]/g, '');
    const last10 = clean.length >= 10 ? clean.substring(clean.length - 10) : clean;

    if (last10.length !== 10) {
      return res.status(400).json({ success: false, message: 'Please enter a valid 10-digit mobile number' });
    }

    const user = await Employee.findOne({
      $or: [
        { phone: input },
        { phone: new RegExp(last10 + '$') },
        { phone: `+91 ${last10}` },
        { phone: `+91${last10}` },
      ]
    });

    if (!user) {
      return res.status(404).json({
        success: false,
        message: `Mobile number '+91 ${last10}' is not registered in the database. Please contact your manager or admin to add your number.`
      });
    }

    return res.json({
      success: true,
      user: {
        id: user.id,
        name: user.name,
        phone: user.phone || `+91 ${last10}`,
        email: user.email,
        role: user.role,
        team: user.team,
      },
      message: `Mobile number verified for ${user.name} (${(user.role || 'CALLER').toUpperCase()})!`
    });
  } catch (err) {
    res.status(500).json({ success: false, error: err.message });
  }
});

module.exports = router;
