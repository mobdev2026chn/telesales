const mongoose = require('mongoose');
const fs = require('fs');
const path = require('path');
const dotenv = require('dotenv');

dotenv.config({ path: path.join(__dirname, '.env') });

const uris = [
  { name: 'Configured MONGODB_URI', uri: process.env.MONGODB_URI },
  { name: 'Local MongoDB (localhost:27017)', uri: 'mongodb://127.0.0.1:27017/telesales_db' },
].filter((item, index, self) => item.uri && self.findIndex(t => t.uri === item.uri) === index);

async function purgeDatabase(uri, label) {
  try {
    console.log(`\n========================================`);
    console.log(`Connecting to ${label} (${uri.replace(/:[^:@]+@/, ':****@')})...`);
    
    const conn = await mongoose.createConnection(uri, {
      serverSelectionTimeoutMS: 5000,
      connectTimeoutMS: 5000,
    }).asPromise();
    
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
    console.log(`🗑️ Deleted ${empRes.deletedCount} employees.`);

    // 6. Seed ONLY the single clean Admin account (all counts 0)
    const cleanAdmin = await Employee.create({
      id: 'admin_1',
      name: 'Admin',
      email: 'admin@askeva.com',
      phone: '+91 98250 00000',
      password: 'admin123',
      role: 'admin',
      team: 'Management',
      totalCalls: 0,
      connectedCalls: 0,
      talkTimeSeconds: 0,
      dailyTarget: 150,
      createdAt: new Date(),
      updatedAt: new Date(),
    });
    console.log(`✅ Seeded Clean Single Admin Account: ${cleanAdmin.name} (${cleanAdmin.email} / admin123) [Total Calls: 0, Connected: 0, TalkTime: 0]`);

    await conn.close();
    console.log(`✓ Purge complete for ${label}`);
  } catch (err) {
    console.log(`⚠️ Notice for ${label}: ${err.message}`);
  }
}

// Clean local uploads directory
function cleanUploads() {
  const recordingsDir = path.join(__dirname, 'uploads/recordings');
  if (fs.existsSync(recordingsDir)) {
    const files = fs.readdirSync(recordingsDir);
    let count = 0;
    for (const f of files) {
      if (f !== '.gitkeep') {
        try {
          fs.unlinkSync(path.join(recordingsDir, f));
          count++;
        } catch (e) {}
      }
    }
    console.log(`🗑️ Cleaned ${count} audio recording files from disk.`);
  }
}

async function run() {
  console.log('🚀 Starting complete database purge & reset to zero...');
  for (const target of uris) {
    await purgeDatabase(target.uri, target.name);
  }
  cleanUploads();
  console.log('\n🎉 ALL DATA PURGED! Database is at 0 with ONLY the Admin account present.\n');
  process.exit(0);
}

run();
