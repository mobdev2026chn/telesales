const Employee = require('../models/Employee');
const { hashPassword } = require('../middleware/auth');

// Creates the first admin account ONLY when no admin exists. Never modifies existing users.
// Credentials come from the environment: ADMIN_PASSCODE (required, min 8 chars), ADMIN_EMAIL, ADMIN_NAME, ADMIN_PHONE.
const seedAdminUsers = async () => {
  try {
    if (await Employee.exists({ role: 'admin' })) return;

    const passcode = process.env.ADMIN_PASSCODE || '';
    if (passcode.trim().length < 8) {
      console.error('No admin account exists and ADMIN_PASSCODE is missing or shorter than 8 characters. Set it in backend/.env to create the first admin.');
      return;
    }
    const email = (process.env.ADMIN_EMAIL || 'admin@askeva.com').toLowerCase().trim();
    if (await Employee.exists({ email })) {
      console.error(`No admin account exists, but ${email} belongs to a non-admin user. Not touching it; promote a user to admin manually.`);
      return;
    }

    const id = (await Employee.exists({ id: 'admin_1' })) ? `admin_${Date.now()}` : 'admin_1';
    const admin = new Employee({
      id,
      name: process.env.ADMIN_NAME || 'Admin',
      email,
      phone: process.env.ADMIN_PHONE || '',
      password: await hashPassword(passcode.trim()),
      role: 'admin',
      team: 'Management',
      dailyTarget: 0,
    });
    // phone is optional for the bootstrap admin (it signs in by email)
    await admin.save({ validateBeforeSave: false });
    console.log(`Created the first admin account (${email}).`);
  } catch (err) {
    console.error('Error seeding admin user:', err.message);
  }
};

module.exports = seedAdminUsers;
