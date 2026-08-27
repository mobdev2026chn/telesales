const dns = require('dns');
// Set DNS to Google & Cloudflare DNS to resolve MongoDB Atlas SRV records
dns.setServers(['8.8.8.8', '1.1.1.1', '8.8.4.4']);

const mongoose = require('mongoose');

const ATLAS_URI = 'mongodb+srv://mobdev2026chn_db_user:mmj8E2ubvgsKD0P1@app.rryjsaq.mongodb.net/telesales_db?retryWrites=true&w=majority';

async function purgeAtlas() {
  try {
    console.log('Connecting to MongoDB Atlas Cloud Cluster...');
    console.log('URI:', ATLAS_URI);

    await mongoose.connect(ATLAS_URI, {
      serverSelectionTimeoutMS: 15000,
    });
    console.log('✓ Successfully connected to MongoDB Atlas Cloud Cluster!');

    const db = mongoose.connection.db;

    // Get all collections in the database
    const collections = await db.listCollections().toArray();
    console.log(`Found collections:`, collections.map(c => c.name));

    const CallLog = mongoose.model('CallLog', new mongoose.Schema({}, { strict: false }));
    const Lead = mongoose.model('Lead', new mongoose.Schema({}, { strict: false }));
    const Recording = mongoose.model('Recording', new mongoose.Schema({}, { strict: false }));
    const Notification = mongoose.model('Notification', new mongoose.Schema({}, { strict: false }));
    const Employee = mongoose.model('Employee', new mongoose.Schema({}, { strict: false }));

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

    // 5. Clean employees and preserve Admin + Mukhil
    const empRes = await Employee.deleteMany({ email: { $nin: ['admin@askeva.com', 'mukhil@askeva.com'] } });
    console.log(`🗑️ Deleted ${empRes.deletedCount} old test employees.`);

    // Ensure Admin and Mukhil are in database
    await Employee.findOneAndUpdate(
      { email: 'admin@askeva.com' },
      {
        id: 'admin_1',
        name: 'Admin',
        email: 'admin@askeva.com',
        phone: '+91 98250 00000',
        password: 'admin123',
        role: 'admin',
        team: 'Management',
        dailyTarget: 150,
        totalCalls: 0,
        connectedCalls: 0,
        talkTimeSeconds: 0,
      },
      { upsert: true, new: true }
    );

    await Employee.findOneAndUpdate(
      { phone: '8248399615' },
      {
        id: 'user_1787835404775',
        name: 'Mukhil',
        email: 'mukhil@askeva.com',
        phone: '8248399615',
        role: 'caller',
        team: 'Telesales Team',
        dailyTarget: 100,
        totalCalls: 0,
        connectedCalls: 0,
        talkTimeSeconds: 0,
      },
      { upsert: true, new: true }
    );

    console.log('✨ Clean database ready with Admin and Mukhil accounts!');
    process.exit(0);
  } catch (err) {
    console.error('❌ Error purging Atlas DB:', err);
    process.exit(1);
  }
}

purgeAtlas();
