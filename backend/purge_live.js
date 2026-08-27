const mongoose = require('mongoose');

const ATLAS_URI = 'mongodb+srv://mobdev2026chn_db_user:mmj8E2ubvgsKD0P1@app.rryjsaq.mongodb.net/telesales_db?retryWrites=true&w=majority';
const LOCAL_URI = 'mongodb://127.0.0.1:27017/telesales_db';

async function purgeDatabase(uri, label) {
  try {
    console.log(`\n========================================`);
    console.log(`Connecting to ${label}...`);
    const conn = await mongoose.createConnection(uri).asPromise();
    console.log(`✓ Connected to ${label}`);

    const CallLog = conn.model('CallLog', new mongoose.Schema({}, { strict: false }));
    const Lead = conn.model('Lead', new mongoose.Schema({}, { strict: false }));
    const Recording = conn.model('Recording', new mongoose.Schema({}, { strict: false }));
    const Notification = conn.model('Notification', new mongoose.Schema({}, { strict: false }));
    const Employee = conn.model('Employee', new mongoose.Schema({}, { strict: false }));

    // 1. Delete all calls
    const callRes = await CallLog.deleteMany({});
    console.log(`🗑️ Deleted ${callRes.deletedCount} call logs.`);

    // 2. Delete all leads
    const leadRes = await Lead.deleteMany({});
    console.log(`🗑️ Deleted ${leadRes.deletedCount} leads.`);

    // 3. Delete all recordings
    const recRes = await Recording.deleteMany({});
    console.log(`🗑️ Deleted ${recRes.deletedCount} recordings.`);

    // 4. Delete all notifications
    const notifRes = await Notification.deleteMany({});
    console.log(`🗑️ Deleted ${notifRes.deletedCount} notifications.`);

    // 5. Delete all employees
    const empRes = await Employee.deleteMany({});
    console.log(`🗑️ Deleted ${empRes.deletedCount} existing employees.`);

    // 6. Seed ONLY the single clean Admin account
    const cleanAdmin = await Employee.create({
      id: 'admin_1',
      name: 'Admin',
      email: 'admin@askeva.com',
      phone: '+91 98250 00000',
      password: 'admin123',
      role: 'admin',
      team: 'Management',
      dailyTarget: 150,
      createdAt: new Date(),
      updatedAt: new Date(),
    });
    console.log(`✅ Seeded Clean Single Admin Account: ${cleanAdmin.name} (${cleanAdmin.email} / admin123)`);

    await conn.close();
    console.log(`✓ Purge complete for ${label}`);
  } catch (err) {
    console.error(`⚠️ Error purging ${label}:`, err.message);
  }
}

async function run() {
  // Purge Atlas Cloud DB
  await purgeDatabase(ATLAS_URI, 'MongoDB Atlas Cloud Cluster');
  // Purge Local DB
  await purgeDatabase(LOCAL_URI, 'Local MongoDB');
  console.log('\n🎉 ALL DATA PURGED! Fresh start ready with only Admin account.\n');
  process.exit(0);
}

run();
