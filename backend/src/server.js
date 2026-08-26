const express = require('express');
const cors = require('cors');
const dotenv = require('dotenv');
const fs = require('fs');
const path = require('path');
const connectDB = require('./config/db');
const CallLog = require('./models/CallLog');
const Employee = require('./models/Employee');
const Lead = require('./models/Lead');
const Recording = require('./models/Recording');

const adminRoutes = require('./routes/admin');
const userRoutes = require('./routes/user');
const authRoutes = require('./routes/auth');

dotenv.config();

const app = express();
const PORT = process.env.PORT || 5000;

// Ensure uploads/recordings directory exists
const uploadsDir = path.join(__dirname, '../uploads/recordings');
if (!fs.existsSync(uploadsDir)) {
  fs.mkdirSync(uploadsDir, { recursive: true });
}

// Middlewares - Increase payload limit for actual base64 audio uploads
app.use(cors());
app.use(express.json({ limit: '50mb' }));
app.use(express.urlencoded({ limit: '50mb', extended: true }));
app.use('/uploads', express.static(path.join(__dirname, '../uploads')));
app.use('/api/uploads', express.static(path.join(__dirname, '../uploads')));
app.use('/admin', express.static(path.join(__dirname, '../../admin_web')));
app.use('/web', express.static(path.join(__dirname, '../../admin_web')));
app.use('/assets/images', express.static(path.join(__dirname, '../../telesales_monitor/assets/images')));

// Database Connection
connectDB();

// 1. Direct High-Priority Top-Level Endpoints for Mobile App & Admin Parity
app.post(['/api/recordings', '/api/user/recordings/upload', '/api/admin/recordings'], async (req, res) => {
  try {
    const { callerName, contactName, phoneNumber, durationSeconds, transcript, dateStr, timeStr, fileName, audioData } = req.body;
    console.log(`🎙️ Saving Actual Audio: caller="${callerName}", contact="${contactName}", duration=${durationSeconds}s, hasAudio=${!!audioData}`);

    let audioUrl = '';
    let storageSizeBytes = 450000;

    // Save actual binary audio file if base64 data is present
    if (audioData && typeof audioData === 'string' && audioData.length > 50) {
      try {
        const cleanBase64 = audioData.replace(/^data:audio\/\w+;base64,/, '');
        const buffer = Buffer.from(cleanBase64, 'base64');
        const saveName = fileName ? fileName.replace(/[^a-zA-Z0-9_.-]/g, '') : `CALL_REC_${Date.now()}.m4a`;
        const filePath = path.join(uploadsDir, saveName);
        fs.writeFileSync(filePath, buffer);
        audioUrl = `/uploads/recordings/${saveName}`;
        storageSizeBytes = buffer.length;
        console.log(`📁 Audio file saved to disk: ${filePath} (${storageSizeBytes} bytes)`);
      } catch (fileErr) {
        console.warn('Could not write audio file to disk:', fileErr.message);
      }
    }

    const rec = await Recording.create({
      id: Date.now().toString(),
      callerName: callerName || 'Caller',
      contactName: contactName || 'Client',
      phoneNumber: phoneNumber || '',
      durationSeconds: durationSeconds || 0,
      audioUrl: audioUrl,
      audioData: (audioData && audioData.length < 500000) ? audioData : '', // Store compact audio in DB if applicable
      transcript: transcript || '“Actual voice recording saved”',
      storageSizeBytes: storageSizeBytes,
      dateStr: dateStr || 'Today',
      timeStr: timeStr || 'Now',
    });

    console.log(`✅ Recording document stored in MongoDB: ID ${rec.id}`);
    res.status(201).json({ success: true, recording: rec });
  } catch (err) {
    console.error('Error saving recording:', err.message);
    res.status(500).json({ success: false, error: err.message });
  }
});

app.get(['/api/recordings', '/api/admin/recordings'], async (req, res) => {
  try {
    const recordings = await Recording.find().sort({ createdAt: -1 });
    const totalStorageBytes = recordings.reduce((acc, r) => acc + (r.storageSizeBytes || 450000), 0);
    const usedGB = +(totalStorageBytes / (1024 * 1024 * 1024)).toFixed(2);

    res.json({
      success: true,
      storage: {
        usedGB: Math.max(usedGB, 0.05),
        totalGB: 5.0,
        freeGB: +(5.0 - Math.max(usedGB, 0.05)).toFixed(2),
        count: recordings.length,
      },
      recordings,
    });
  } catch (err) {
    res.status(500).json({ success: false, error: err.message });
  }
});

app.post(['/api/calls/sync', '/api/user/calls/sync'], async (req, res) => {
  try {
    const { callerId, callerName, callerPhone, calls } = req.body;
    if (!Array.isArray(calls)) {
      return res.status(400).json({ success: false, message: 'Calls array required' });
    }

    const inserted = [];
    for (const call of calls) {
      const log = await CallLog.create({
        callerId: callerId || 'caller_1',
        callerName: callerName || 'Priyanka Panchal',
        callerPhone: callerPhone || '+91 98250 12340',
        contactName: call.contactName || 'Unknown',
        phoneNumber: call.phoneNumber,
        type: call.type || 'outgoing',
        timestamp: call.timestamp ? new Date(call.timestamp) : new Date(),
        durationSeconds: call.durationSeconds || 0,
        simSlot: call.simSlot || 1,
        note: call.note || '',
      });
      inserted.push(log);
    }

    res.json({ success: true, count: inserted.length, message: `Synced ${inserted.length} call logs` });
  } catch (err) {
    res.status(500).json({ success: false, error: err.message });
  }
});

app.get(['/api/dashboard/stats', '/api/admin/dashboard'], async (req, res) => {
  try {
    const totalCalls = await CallLog.countDocuments();
    const connectedCalls = await CallLog.countDocuments({ durationSeconds: { $gt: 0 } });
    const incoming = await CallLog.countDocuments({ type: 'incoming' });
    const outgoing = await CallLog.countDocuments({ type: 'outgoing' });
    const missed = await CallLog.countDocuments({ type: 'missed' });
    const neverAttended = await CallLog.countDocuments({ 
      $or: [{ type: 'rejected' }, { type: 'neverAttended' }, { durationSeconds: 0 }] 
    });

    const durationAgg = await CallLog.aggregate([
      { $group: { _id: null, totalSeconds: { $sum: '$durationSeconds' } } }
    ]);
    const totalSeconds = durationAgg.length > 0 ? durationAgg[0].totalSeconds : 0;
    const hours = Math.floor(totalSeconds / 3600);
    const minutes = Math.floor((totalSeconds % 3600) / 60);
    const talkTimeFormatted = `${hours}h ${minutes.toString().padStart(2, '0')}m`;

    const distinctClients = await CallLog.distinct('phoneNumber');
    const distinctCallers = await CallLog.distinct('callerPhone');

    const topCallerAgg = await CallLog.aggregate([
      {
        $group: {
          _id: { callerName: '$callerName', callerPhone: '$callerPhone' },
          talkSeconds: { $sum: '$durationSeconds' },
          totalCalls: { $sum: 1 }
        }
      },
      { $sort: { talkSeconds: -1 } },
      { $limit: 1 }
    ]);

    let topPerformer = { name: 'NO CALLS YET', duration: '0H 00M' };
    if (topCallerAgg.length > 0) {
      const top = topCallerAgg[0];
      const topH = Math.floor(top.talkSeconds / 3600);
      const topM = Math.floor((top.talkSeconds % 3600) / 60);
      topPerformer = {
        name: (top._id.callerName || top._id.callerPhone || 'CALLER').toUpperCase(),
        duration: `${topH}H ${topM}M`,
      };
    }

    const statsObj = {
      totalCalls,
      connectedCalls,
      talkTimeFormatted,
      uniqueClients: distinctClients.length,
      teamCount: Math.max(distinctCallers.length, 1),
      incoming,
      outgoing,
      missed,
      neverAttended,
      topTalkTime: topPerformer,
      topPerformer,
      hourlyCalls: [
        { hour: '9A', calls: 0, isPeak: false },
        { hour: '10A', calls: 0, isPeak: false },
        { hour: '11A', calls: 0, isPeak: false },
        { hour: '12P', calls: 0, isPeak: false },
        { hour: '1P', calls: 0, isPeak: false },
        { hour: '2P', calls: 0, isPeak: true },
        { hour: '3P', calls: 0, isPeak: false },
        { hour: '4P', calls: 0, isPeak: false },
        { hour: '5P', calls: 0, isPeak: false },
        { hour: '6P', calls: 0, isPeak: false },
      ]
    };

    res.json({ success: true, stats: statsObj, data: statsObj });
  } catch (err) {
    res.status(500).json({ success: false, error: err.message });
  }
});

app.get(['/api/employees/leaderboard', '/api/admin/leaderboard'], async (req, res) => {
  try {
    const liveLeaderboard = await CallLog.aggregate([
      {
        $group: {
          _id: { callerName: '$callerName', callerPhone: '$callerPhone' },
          totalCalls: { $sum: 1 },
          connectedCalls: {
            $sum: { $cond: [{ $gt: ['$durationSeconds', 0] }, 1, 0] }
          },
          talkTimeSeconds: { $sum: '$durationSeconds' },
        }
      },
      { $sort: { talkTimeSeconds: -1, totalCalls: -1 } }
    ]);

    if (liveLeaderboard.length > 0) {
      const employees = liveLeaderboard.map((item, index) => ({
        id: (index + 1).toString(),
        name: item._id.callerName || item._id.callerPhone || `Caller ${index + 1}`,
        phone: item._id.callerPhone || '+91 98250 12340',
        role: 'caller',
        team: 'Active Team',
        totalCalls: item.totalCalls,
        connectedCalls: item.connectedCalls,
        talkTimeSeconds: item.talkTimeSeconds,
        rank: index + 1,
      }));
      return res.json({ success: true, count: employees.length, employees, data: employees });
    }

    const employees = await Employee.find().sort({ rank: 1 });
    res.json({ success: true, count: employees.length, employees, data: employees });
  } catch (err) {
    res.status(500).json({ success: false, error: err.message });
  }
});

app.get(['/api/leads', '/api/admin/leads', '/api/user/leads'], async (req, res) => {
  try {
    const leads = await Lead.find().sort({ updatedAt: -1 });
    res.json({ success: true, count: leads.length, leads, data: leads });
  } catch (err) {
    res.status(500).json({ success: false, error: err.message });
  }
});

// Route Mounts
app.use('/api/admin', adminRoutes);
app.use('/api/user', userRoutes);
app.use('/api/auth', authRoutes);

// Root & Health Check
app.get('/', (req, res) => {
  res.json({
    status: 'ONLINE',
    service: 'Telesales Monitoring Backend API',
    database: 'MongoDB',
    version: '2.0.0',
  });
});

app.listen(PORT, '0.0.0.0', () => {
  console.log(`🚀 Telesales Backend API running on http://0.0.0.0:${PORT}`);
  console.log(`📊 Admin APIs: http://localhost:${PORT}/api/admin/dashboard`);
  console.log(`📱 User APIs:  http://localhost:${PORT}/api/recordings`);
});
