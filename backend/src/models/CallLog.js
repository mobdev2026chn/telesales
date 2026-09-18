const mongoose = require('mongoose');

const CallLogSchema = new mongoose.Schema({
  callerId: { type: String, default: '' },
  callerName: { type: String, default: '' },
  callerPhone: { type: String, default: '' },
  contactName: { type: String, default: '' },
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
  // Recording.id of the ONE recording linked to this call ('' when none)
  recordingId: { type: String, default: '' },
  // id:<employeeId>_<numberLast10>_<timestampMs> (older rows: <callerLast10>_<numberLast10>_<timestampMs>)
  dedupKey: { type: String },
}, { timestamps: true });

CallLogSchema.index({ dedupKey: 1 }, { unique: true, sparse: true });
CallLogSchema.index({ timestamp: -1 });
CallLogSchema.index({ callerId: 1, timestamp: -1 });

module.exports = mongoose.model('CallLog', CallLogSchema);
