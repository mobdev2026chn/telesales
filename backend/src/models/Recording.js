const mongoose = require('mongoose');

const RecordingSchema = new mongoose.Schema({
  id: { type: String, required: true, unique: true },
  callerName: { type: String, required: true },
  contactName: { type: String, required: true },
  phoneNumber: { type: String, required: true },
  dateStr: { type: String, default: 'Today' },
  timeStr: { type: String, default: 'Now' },
  durationSeconds: { type: Number, default: 0 },
  audioUrl: { type: String, default: '' },
  audioData: { type: String, default: '' }, // Base64 encoded actual recorded audio
  transcript: { type: String, default: '' },
  storageSizeBytes: { type: Number, default: 450000 },
}, { timestamps: true });

module.exports = mongoose.model('Recording', RecordingSchema);
