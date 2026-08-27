const dns = require('dns');
dns.setServers(['8.8.8.8', '1.1.1.1', '8.8.4.4']);
const mongoose = require('mongoose');

const URI = 'mongodb+srv://mobdev2026chn_db_user:mmj8E2ubvgsKD0P1@app.rryjsaq.mongodb.net/telesales_db?retryWrites=true&w=majority';

async function run() {
  try {
    await mongoose.connect(URI);
    const Notification = mongoose.model('Notification', new mongoose.Schema({}, { strict: false }));
    const n = await Notification.create({
      id: `notif_${Date.now()}`,
      recipientPhone: '8248399615',
      recipientName: 'Mukhil',
      senderName: 'Admin',
      senderRole: 'admin',
      contactName: '+919944446953',
      title: 'Feedback from Admin (ADMIN)',
      message: 'Admin reviewed your call with +919944446953 (4 ⭐): "Good talk"',
      comment: 'Good talk',
      rating: 4,
      isRead: false,
      createdAt: new Date()
    });
    console.log('✓ Notification created in MongoDB Atlas for Mukhil:', n.id);
    process.exit(0);
  } catch (err) {
    console.error(err);
    process.exit(1);
  }
}

run();
