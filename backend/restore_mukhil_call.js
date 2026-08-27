const dns = require('dns');
dns.setServers(['8.8.8.8', '1.1.1.1', '8.8.4.4']);
const mongoose = require('mongoose');

const URI = 'mongodb+srv://mobdev2026chn_db_user:mmj8E2ubvgsKD0P1@app.rryjsaq.mongodb.net/telesales_db?retryWrites=true&w=majority';

async function run() {
  try {
    await mongoose.connect(URI);
    console.log('Connected to MongoDB Atlas');

    const CallLog = mongoose.model('CallLog', new mongoose.Schema({}, { strict: false }));
    const Recording = mongoose.model('Recording', new mongoose.Schema({}, { strict: false }));
    const Employee = mongoose.model('Employee', new mongoose.Schema({}, { strict: false }));
    const Lead = mongoose.model('Lead', new mongoose.Schema({}, { strict: false }));

    // 1. Restore Mukhil's real 1 call
    const call = await CallLog.create({
      id: `call_${Date.now()}`,
      callerName: 'Mukhil',
      callerId: 'user_1787835404775',
      callerPhone: '8248399615',
      contactName: '+919944446953',
      phoneNumber: '+919944446953',
      type: 'incoming',
      duration: 83,
      durationFormatted: '1m 23s',
      timestamp: new Date(),
      dateStr: 'Today',
      timeStr: '6:58 PM',
      recordingUrl: '/uploads/recordings/INC_CALL_REC_20260827_185852.wav'
    });

    // 2. Restore Recording attributed to Mukhil with Admin's feedback comment
    const rec = await Recording.create({
      id: Date.now().toString(),
      callerName: 'Mukhil',
      contactName: '+919944446953',
      phoneNumber: '+919944446953',
      durationSeconds: 83,
      audioUrl: '/uploads/recordings/INC_CALL_REC_20260827_185852.wav',
      transcript: 'Real voice audio recorded via hardware microphone (INC_CALL_REC_20260827_185852.wav)',
      storageSizeBytes: 1328000,
      dateStr: 'Today',
      timeStr: '6:58 PM',
      rating: 4,
      comment: 'Good talk',
      commentedBy: 'Admin',
      commentedByRole: 'admin',
      commentedAt: new Date()
    });

    // 3. Update Mukhil's stats in Employee collection
    await Employee.updateOne(
      { phone: '8248399615' },
      {
        $set: {
          totalCalls: 1,
          connectedCalls: 1,
          talkTimeSeconds: 83,
        }
      }
    );

    // 4. Create Lead for +919944446953 assigned to Mukhil
    await Lead.create({
      id: `lead_${Date.now()}`,
      name: '+919944446953',
      phone: '+919944446953',
      status: 'interested',
      attempts: 1,
      lastCallDate: new Date(),
      assignedCaller: 'Mukhil',
      notes: 'Incoming call attended by Mukhil (1m 23s)'
    });

    console.log('✓ 1 call and recording attributed to Mukhil restored cleanly in MongoDB Atlas!');
    process.exit(0);
  } catch (err) {
    console.error('Error:', err);
    process.exit(1);
  }
}

run();
