const express = require('express');
const router = express.Router();

// 1. POST /api/auth/admin-login
router.post('/admin-login', (req, res) => {
  const { email, password } = req.body;
  const adminEmail = process.env.ADMIN_EMAIL || 'admin@askeva.com';

  if (!email) {
    return res.status(400).json({ success: false, message: 'Email is required' });
  }

  res.json({
    success: true,
    user: {
      id: 'admin_1',
      name: 'Rasmi Desai (Manager)',
      email: email || adminEmail,
      role: 'admin',
      token: 'jwt_mock_admin_token_askeva_2026',
    },
    message: 'Admin authentication successful',
  });
});

// 2. POST /api/auth/caller-verify
router.post('/caller-verify', (req, res) => {
  const { phoneNumber, simSlot } = req.body;

  if (!phoneNumber) {
    return res.status(400).json({ success: false, message: 'Phone number is required' });
  }

  res.json({
    success: true,
    user: {
      id: 'caller_1',
      name: 'Priyanka Panchal',
      phone: phoneNumber,
      simSlot: simSlot || 1,
      role: 'caller',
      token: 'jwt_mock_caller_token_askeva_2026',
    },
    message: 'Caller device SIM verified successfully',
  });
});

module.exports = router;
