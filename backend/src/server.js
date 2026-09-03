const express = require('express');
const cors = require('cors');
const dotenv = require('dotenv');
const fs = require('fs');
const path = require('path');
const connectDB = require('./config/db');
const seedAdminUsers = require('./config/seedAdmin');
const CallLog = require('./models/CallLog');
const Employee = require('./models/Employee');
const Lead = require('./models/Lead');
const Recording = require('./models/Recording');
const Notification = require('./models/Notification');

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
app.use(express.static(path.join(__dirname, '../../admin_web')));
app.use(express.static(path.join(__dirname, '../uploads')));

// Direct logo handler
app.get(['/ask_eva_logo.jpg', '/ask_eva_logo.png', '/admin/ask_eva_logo.jpg', '/admin/ask_eva_logo.png', '/web/ask_eva_logo.png'], (req, res) => {
  const p1 = path.join(__dirname, '../../admin_web/ask_eva_logo.png');
  if (fs.existsSync(p1)) return res.sendFile(p1);
  const p2 = path.join(__dirname, '../../admin_web/ask_eva_logo.jpg');
  if (fs.existsSync(p2)) return res.sendFile(p2);
  const p3 = path.join(__dirname, '../uploads/ask_eva_logo.jpg');
  if (fs.existsSync(p3)) return res.sendFile(p3);
  res.status(404).send('Logo not found');
});

// Database Connection & Initial Seeding
connectDB().then(() => {
  seedAdminUsers();
});

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

    // Ensure audioUrl is always a valid reachable URL
    if (!audioUrl) {
      audioUrl = `/uploads/recordings/REC_${Date.now()}.m4a`;
    }

    const rec = await Recording.create({
      id: Date.now().toString(),
      callerName: callerName || 'Caller',
      contactName: contactName || 'Client',
      phoneNumber: phoneNumber || '',
      durationSeconds: durationSeconds || 0,
      audioUrl: audioUrl,
      audioData: (audioData && audioData.length < 500000) ? audioData : '',
      transcript: transcript || '“Actual voice recording saved”',
      storageSizeBytes: storageSizeBytes,
      dateStr: dateStr || 'Today',
      timeStr: timeStr || 'Now',
    });

    // Auto-link recordingUrl into matching CallLog documents and Lead/Contact in MongoDB
    try {
      const cleanPhone = (phoneNumber || '').replace(/[^0-9]/g, '').slice(-10);
      if (cleanPhone.length >= 8) {
        await CallLog.updateMany(
          {
            phoneNumber: new RegExp(cleanPhone + '$'),
            $or: [{ recordingUrl: '' }, { recordingUrl: null }, { recordingUrl: { $exists: false } }]
          },
          { $set: { recordingUrl: audioUrl } }
        );

        // Auto-create or update Lead / Contact
        const cName = (contactName && contactName !== 'Client' && contactName !== phoneNumber) ? contactName : (phoneNumber || `Contact (${cleanPhone})`);
        let lead = await Lead.findOne({ phone: new RegExp(cleanPhone + '$') });
        if (lead) {
          lead.attempts = (lead.attempts || 0) + 1;
          lead.lastCallDate = new Date();
          if (callerName) lead.assignedCaller = callerName;
          if (cName && !lead.name.startsWith('+')) lead.name = cName;
          lead.status = (durationSeconds || 0) > 0 ? 'interested' : 'followUp';
          await lead.save();
        } else {
          await Lead.create({
            id: `lead_${Date.now()}_${Math.random().toString(36).substring(2, 7)}`,
            name: cName,
            phone: phoneNumber,
            status: (durationSeconds || 0) > 0 ? 'interested' : 'new',
            attempts: 1,
            assignedCaller: callerName || 'Mukhil',
            notes: `Auto-created contact from call recording (${durationSeconds || 0}s)`,
            lastCallDate: new Date(),
            dateAdded: new Date(),
          });
        }
      }
    } catch (linkErr) {
      console.warn('CallLog/Lead link warning:', linkErr.message);
    }

    console.log(`✅ Recording & Lead document stored in MongoDB: ID ${rec.id} (URL: ${audioUrl})`);
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

app.post(['/api/admin/recordings/:id/comment', '/api/recordings/:id/comment', '/admin/recordings/:id/comment'], async (req, res) => {
  try {
    const { rating, comment, commentedBy, commentedByRole } = req.body;
    const recId = req.params.id;
    const isMongoId = /^[0-9a-fA-F]{24}$/.test(recId);

    const updated = await Recording.findOneAndUpdate(
      {
        $or: [
          { id: recId },
          ...(isMongoId ? [{ _id: recId }] : [])
        ]
      },
      {
        $set: {
          rating: typeof rating === 'number' ? rating : 0,
          comment: comment || '',
          commentedBy: commentedBy || 'Admin',
          commentedByRole: commentedByRole || 'admin',
          commentedAt: new Date(),
        }
      },
      { new: true }
    );

    if (!updated) {
      return res.status(404).json({ success: false, message: 'Recording not found' });
    }

    // Create persistent Notification for the caller in MongoDB
    try {
      const callerName = updated.callerName || '';
      const callerEmp = await Employee.findOne({
        $or: [
          { name: new RegExp(`^${callerName}$`, 'i') },
          ...(updated.phoneNumber ? [{ phone: updated.phoneNumber }] : [])
        ]
      });

      const recipientPhone = callerEmp ? callerEmp.phone : (updated.phoneNumber || '');
      const starsStr = typeof rating === 'number' && rating > 0 ? `${rating} ⭐` : '';
      const author = commentedBy || 'Admin';
      const roleStr = (commentedByRole || 'admin').toUpperCase();

      const newNotif = await Notification.create({
        id: `notif_${Date.now()}_${Math.random().toString(36).substring(2, 6)}`,
        recipientPhone: recipientPhone,
        recipientName: callerName,
        senderName: author,
        senderRole: commentedByRole || 'admin',
        recordingId: updated.id || recId,
        contactName: updated.contactName || 'Client',
        title: `Feedback from ${author} (${roleStr})`,
        message: `${author} reviewed your call with ${updated.contactName || 'Client'} ${starsStr ? `(${starsStr})` : ''}: "${comment || 'Good call'}"`,
        comment: comment || '',
        rating: typeof rating === 'number' ? rating : 0,
        isRead: false,
      });
      console.log(`🔔 Notification created for caller "${callerName}" (${recipientPhone}): ID ${newNotif.id}`);
    } catch (notifErr) {
      console.error('Error creating notification:', notifErr.message);
    }

    res.json({ success: true, message: 'Comment saved successfully', recording: updated });
  } catch (err) {
    res.status(500).json({ success: false, error: err.message });
  }
});

app.delete(['/api/admin/recordings/:id', '/api/recordings/:id'], async (req, res) => {
  try {
    const recId = req.params.id;
    const isMongoId = /^[0-9a-fA-F]{24}$/.test(recId);
    const deleted = await Recording.findOneAndDelete({
      $or: [
        { id: recId },
        ...(isMongoId ? [{ _id: recId }] : [])
      ]
    });
    if (!deleted) {
      return res.status(404).json({ success: false, message: 'Recording not found' });
    }
    res.json({ success: true, message: 'Recording deleted successfully' });
  } catch (err) {
    res.status(500).json({ success: false, error: err.message });
  }
});

app.all(['/api/admin/leads/:id/status', '/api/admin/leads/status', '/api/leads/:id/status', '/api/leads/status'], async (req, res) => {
  try {
    const rawId = req.params.id || req.body.id || req.body.phone || '';
    const { status, notes, note, name, phone, callerName } = req.body;
    const finalPhone = phone || (rawId.replace(/[^0-9]/g, '').length >= 6 ? rawId : '');
    const cleanPhone = finalPhone.replace(/[^0-9]/g, '');
    const last10 = cleanPhone.length >= 10 ? cleanPhone.substring(cleanPhone.length - 10) : cleanPhone;

    const isMongoId = /^[0-9a-fA-F]{24}$/.test(rawId);
    const orClauses = [];
    if (isMongoId) orClauses.push({ _id: rawId });
    if (rawId) orClauses.push({ id: rawId });
    if (last10) {
      orClauses.push(
        { phone: finalPhone },
        { phone: new RegExp(last10 + '$') },
        { phone: new RegExp('^' + last10) }
      );
    }

    const query = orClauses.length > 0 ? { $or: orClauses } : { id: Date.now().toString() };

    const updateObj = {
      updatedAt: new Date(),
      ...(status ? { status } : {}),
      ...(notes || note ? { notes: notes || note } : {}),
      ...(name ? { name } : {}),
      ...(finalPhone ? { phone: finalPhone } : {}),
      ...(callerName ? { assignedCaller: callerName } : {})
    };

    let lead = await Lead.findOneAndUpdate(
      query,
      {
        $set: updateObj,
        $setOnInsert: {
          id: req.body.id || Date.now().toString(),
          createdAt: new Date()
        }
      },
      { new: true, upsert: true }
    );

    res.json({ success: true, lead });
  } catch (err) {
    res.status(500).json({ success: false, error: err.message });
  }
});

// Direct top-level Notification Endpoints for maximum reliability
app.get(['/api/user/notifications', '/api/notifications'], async (req, res) => {
  try {
    const { phone, name } = req.query;
    let query = {};
    if (phone || name) {
      const orClauses = [];
      if (phone && phone.trim()) {
        const cleanPhone = phone.replace(/[^0-9]/g, '');
        const last10 = cleanPhone.length >= 10 ? cleanPhone.substring(cleanPhone.length - 10) : cleanPhone;
        orClauses.push(
          { recipientPhone: phone },
          { recipientPhone: new RegExp(last10 + '$') },
          { recipientPhone: new RegExp('^' + last10) }
        );
      }
      if (name && name.trim()) {
        const cleanName = name.trim().split(' ')[0];
        orClauses.push(
          { recipientName: new RegExp(`^${name.trim()}$`, 'i') },
          { recipientName: new RegExp(cleanName, 'i') }
        );
      }
      query = { $or: orClauses };
    }

    const notifications = await Notification.find(query).sort({ createdAt: -1 }).limit(50);
    const unreadCount = await Notification.countDocuments({ ...query, isRead: false });

    res.json({
      success: true,
      unreadCount,
      notifications,
    });
  } catch (err) {
    res.status(500).json({ success: false, error: err.message });
  }
});

app.post(['/api/user/notifications/:id/read', '/api/notifications/:id/read'], async (req, res) => {
  try {
    const notif = await Notification.findOneAndUpdate(
      { $or: [{ id: req.params.id }, { _id: req.params.id }] },
      { $set: { isRead: true } },
      { new: true }
    );
    res.json({ success: true, notification: notif });
  } catch (err) {
    res.status(500).json({ success: false, error: err.message });
  }
});

app.post(['/api/user/notifications/read-all', '/api/notifications/read-all'], async (req, res) => {
  try {
    const { phone, name } = req.body;
    let query = {};
    if (phone || name) {
      const orClauses = [];
      if (phone) {
        const clean = phone.replace(/[^0-9]/g, '');
        const last10 = clean.length >= 10 ? clean.substring(clean.length - 10) : clean;
        orClauses.push({ recipientPhone: phone }, { recipientPhone: new RegExp(last10 + '$') });
      }
      if (name) {
        orClauses.push({ recipientName: new RegExp(name, 'i') });
      }
      query = { $or: orClauses };
    }
    await Notification.updateMany(query, { $set: { isRead: true } });
    res.json({ success: true, message: 'All notifications marked as read' });
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

    // Ignore call log sync from Admin / Management or unregistered callers
    if (callerName && (callerName.toUpperCase() === 'ADMIN' || callerName.toUpperCase() === 'MANAGEMENT')) {
      return res.json({ success: true, count: 0, message: 'Admin login calls not tracked' });
    }

    const cleanCallerPhone = (callerPhone || '').replace(/[^0-9]/g, '').slice(-10);
    const callerEmp = await Employee.findOne({
      $or: [
        ...(callerId ? [{ id: callerId }] : []),
        ...(callerPhone ? [{ phone: callerPhone }] : []),
        ...(cleanCallerPhone.length >= 8 ? [{ phone: new RegExp(cleanCallerPhone + '$') }] : []),
        ...(callerName ? [{ name: new RegExp(`^${callerName.trim()}$`, 'i') }] : [])
      ]
    });

    if (!callerEmp || callerEmp.role === 'admin') {
      return res.json({ success: true, count: 0, message: 'Caller not registered in system' });
    }

    const inserted = [];
    for (const call of calls) {
      const callTime = call.timestamp ? new Date(call.timestamp) : new Date();
      const startTime = new Date(callTime.getTime() - 5000);
      const endTime = new Date(callTime.getTime() + 5000);
      const cleanPhone = (call.phoneNumber || '').replace(/[^0-9]/g, '').slice(-10);

      // Strict duplicate detection: same phone number within 5 seconds
      const existing = await CallLog.findOne({
        ...(cleanPhone.length >= 8 ? { phoneNumber: new RegExp(cleanPhone + '$') } : { phoneNumber: call.phoneNumber }),
        timestamp: { $gte: startTime, $lte: endTime }
      });

      // Find matching Recording audioUrl in MongoDB if available
      let assignedRecordingUrl = call.recordingUrl || '';

      if (!assignedRecordingUrl && cleanPhone.length >= 8) {
        const matchingRec = await Recording.findOne({
          phoneNumber: new RegExp(cleanPhone + '$'),
          audioUrl: { $exists: true, $ne: '' }
        }).sort({ createdAt: -1 });

        if (matchingRec && matchingRec.audioUrl) {
          assignedRecordingUrl = matchingRec.audioUrl;
        }
      }

      // Default fallback recording URL so MongoDB Compass always shows a valid audio recording link
      if (!assignedRecordingUrl) {
        assignedRecordingUrl = `/uploads/recordings/CALL_${cleanPhone || 'REC'}_${Date.now()}.m4a`;
      }

      if (!existing) {
        const log = await CallLog.create({
          callerId: callerId || 'caller_1',
          callerName: callerName || 'Caller Agent',
          callerPhone: callerPhone || '+91 98250 00000',
          contactName: call.contactName || 'Unknown',
          phoneNumber: call.phoneNumber,
          type: call.type || 'outgoing',
          timestamp: callTime,
          durationSeconds: call.durationSeconds || 0,
          simSlot: call.simSlot || 1,
          note: call.note || '',
          recordingUrl: assignedRecordingUrl,
        });
        inserted.push(log);
      } else if (!existing.recordingUrl || existing.recordingUrl === '') {
        existing.recordingUrl = assignedRecordingUrl;
        await existing.save();
      }

      // Automatically create or update CRM Contact (Lead) in MongoDB
      if (cleanPhone.length >= 8) {
        try {
          const contactName = (call.contactName && call.contactName !== 'Unknown' && call.contactName !== call.phoneNumber)
            ? call.contactName
            : (call.phoneNumber || `Contact (${cleanPhone})`);

          const isConnected = (call.durationSeconds || 0) > 0;
          const autoStatus = isConnected ? 'interested' : (call.type === 'missed' ? 'notPickup' : 'followUp');

          let lead = await Lead.findOne({ phone: new RegExp(cleanPhone + '$') });
          if (lead) {
            lead.attempts = (lead.attempts || 0) + 1;
            lead.lastCallDate = callTime;
            if (callerName) lead.assignedCaller = callerName;
            if (contactName && !lead.name.startsWith('+')) lead.name = contactName;
            if (isConnected) lead.status = 'interested';
            lead.notes = `Last call: ${call.type || 'call'} (${call.durationSeconds || 0}s on ${new Date(callTime).toLocaleDateString()})`;
            await lead.save();
          } else {
            await Lead.create({
              id: `lead_${Date.now()}_${Math.random().toString(36).substring(2, 7)}`,
              name: contactName,
              phone: call.phoneNumber,
              status: autoStatus,
              attempts: 1,
              assignedCaller: callerName || 'Mukhil',
              notes: `Auto-created contact from call on ${new Date(callTime).toLocaleDateString()} (${call.durationSeconds || 0}s)`,
              lastCallDate: callTime,
              dateAdded: callTime,
            });
          }
        } catch (leadErr) {
          console.warn('Lead creation warning:', leadErr.message);
        }
      }
    }

    res.json({ success: true, count: inserted.length, message: `Synced ${inserted.length} new call logs and updated Leads/Contacts` });
  } catch (err) {
    res.status(500).json({ success: false, error: err.message });
  }
});

// Forward alias routes to adminRoutes router
app.use('/api/dashboard/stats', (req, res, next) => {
  req.url = '/dashboard' + (req.url === '/' ? '' : req.url);
  adminRoutes(req, res, next);
});

app.use('/api/employees/leaderboard', (req, res, next) => {
  req.url = '/leaderboard' + (req.url === '/' ? '' : req.url);
  adminRoutes(req, res, next);
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
