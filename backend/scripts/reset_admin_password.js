// Sets a new password for one admin account (for when nobody can sign in to the portal).
//
//   node scripts/reset_admin_password.js admin@askeva.com                     -> dry run: shows the account
//   node scripts/reset_admin_password.js admin@askeva.com 'NewPass@123' --yes  -> sets the password
//
// The database comes ONLY from MONGODB_URI (backend/.env or the environment).
require('dotenv').config({ path: require('path').join(__dirname, '../.env') });
require('dns').setServers(['8.8.8.8', '8.8.4.4', '1.1.1.1']);
const mongoose = require('mongoose');
const Employee = require('../src/models/Employee');
const { hashPassword } = require('../src/middleware/auth');

const [email, password] = process.argv.slice(2).filter(a => !a.startsWith('--'));
const CONFIRMED = process.argv.includes('--yes');

(async () => {
  const uri = process.env.MONGODB_URI;
  if (!uri) {
    console.error('MONGODB_URI is not set. Aborting.');
    process.exit(1);
  }
  if (!email) {
    console.error('Usage: node scripts/reset_admin_password.js <admin email> [new password] [--yes]');
    process.exit(1);
  }
  await mongoose.connect(uri, { serverSelectionTimeoutMS: 10000 });
  console.log(`Database: ${mongoose.connection.host}/${mongoose.connection.name}`);

  const admins = await Employee.find({ role: 'admin' }).select('id name email').lean();
  console.log(`Admin accounts: ${admins.map(a => `${a.email || '(no email)'} [${a.id}]`).join(', ') || 'none'}`);

  const emp = await Employee.findOne({ email: email.toLowerCase().trim() });
  if (!emp) {
    console.error(`No account with email ${email}.`);
    process.exit(1);
  }
  if (emp.role !== 'admin') {
    console.error(`${email} is a ${emp.role}, not an admin. Not changing it.`);
    process.exit(1);
  }
  if (!password || !CONFIRMED) {
    console.log(`Dry run: would reset the password of ${emp.name} (${emp.email}). Pass a password and --yes to apply.`);
    process.exit(0);
  }
  if (password.trim().length < 8) {
    console.error('Password must be at least 8 characters.');
    process.exit(1);
  }
  emp.password = await hashPassword(password.trim());
  await emp.save({ validateBeforeSave: false });
  console.log(`Password updated for ${emp.name} (${emp.email}).`);
  process.exit(0);
})().catch(err => {
  console.error(err.message);
  process.exit(1);
});
