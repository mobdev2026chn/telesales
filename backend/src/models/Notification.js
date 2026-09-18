const mongoose = require('mongoose');

const NotificationSchema = new mongoose.Schema({
  id: { type: String, required: true, unique: true },
  // Employee.id of the recipient (older rows only have phone/name)
  recipientId: { type: String, default: '' },
  recipientPhone: { type: String, default: '' },
  recipientName: { type: String, default: '' },
  senderName: { type: String, default: '' },
  senderRole: { type: String, default: '' },
  recordingId: { type: String, default: '' },
  contactName: { type: String, default: '' },
  title: { type: String, default: 'New Call Quality Feedback' },
  message: { type: String, default: '' },
  comment: { type: String, default: '' },
  rating: { type: Number, default: 0 },
  isRead: { type: Boolean, default: false },
}, { timestamps: true });

NotificationSchema.index({ recipientId: 1, createdAt: -1 });

module.exports = mongoose.model('Notification', NotificationSchema);
