const mongoose = require('mongoose');

const CallLogSchema = new mongoose.Schema({
  callerId: { type: String, default: 'caller_1' },
  callerName: { type: String, default: 'Priyanka Panchal' },
  callerPhone: { type: String, default: '+91 98250 12340' },
  contactName: { type: String, required: true },
  phoneNumber: { type: String, required: true },
  type: { 
    type: String, 
    enum: ['incoming', 'outgoing', 'missed', 'rejected', 'neverAttended'],
    required: true 
  },
  timestamp: { type: Date, default: Date.now },
  durationSeconds: { type: Number, default: 0 },
  simSlot: { type: Number, default: 1 },
  note: { type: String, default: '' },
  recordingUrl: { type: String, default: '' },
}, { timestamps: true });

module.exports = mongoose.model('CallLog', CallLogSchema);
