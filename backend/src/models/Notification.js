const mongoose = require('mongoose');

const NotificationSchema = new mongoose.Schema({
  id: { type: String, required: true, unique: true },
  recipientPhone: { type: String, default: '' },
  recipientName: { type: String, default: '' },
  senderName: { type: String, default: 'Admin' },
  senderRole: { type: String, default: 'admin' },
  recordingId: { type: String, default: '' },
  contactName: { type: String, default: 'Client' },
  title: { type: String, default: 'New Call Quality Feedback' },
  message: { type: String, default: '' },
  comment: { type: String, default: '' },
  rating: { type: Number, default: 0 },
  isRead: { type: Boolean, default: false },
}, { timestamps: true });

module.exports = mongoose.model('Notification', NotificationSchema);
