const mongoose = require('mongoose');

const CriteriaSchema = new mongoose.Schema({
  g: { type: Number, min: 0, max: 5, default: 0 }, // greeting
  p: { type: Number, min: 0, max: 5, default: 0 }, // product knowledge
  o: { type: Number, min: 0, max: 5, default: 0 }, // objection handling
  c: { type: Number, min: 0, max: 5, default: 0 }, // closing
  t: { type: Number, min: 0, max: 5, default: 0 }, // tone
  s: { type: Number, min: 0, max: 5, default: 0 }, // script adherence
}, { _id: false });

const CommentSchema = new mongoose.Schema({
  text: { type: String, required: true },
  by: { type: String, default: '' },
  byRole: { type: String, default: '' },
  at: { type: Date, default: Date.now },
}, { _id: false });

const RecordingSchema = new mongoose.Schema({
  id: {
    type: String,
    default: () => `rec_${Date.now()}_${Math.random().toString(36).substring(2, 8)}`,
    unique: true
  },
  // Who made the call (from the uploader's token; body only for legacy app builds)
  callerId: { type: String, default: '' },
  callerName: { type: String, required: true },
  callerPhone: { type: String, default: '' },
  // Customer
  contactName: { type: String, default: '' },
  phoneNumber: { type: String, required: true },
  type: { type: String, enum: ['INCOMING', 'OUTGOING', ''], default: '' },
  // Stored (unique) file name on disk, and the name the device sent (used for idempotent retries)
  fileName: { type: String, default: '' },
  originalFileName: { type: String, default: '' },
  callStartedAt: { type: Date, default: null },
  simSlot: { type: Number, default: null },
  // CallLog this recording is linked to (exactly one)
  callLogId: { type: String, default: '' },
  dateStr: { type: String, default: '' },
  timeStr: { type: String, default: '' },
  durationSeconds: { type: Number, default: 0 },
  audioUrl: { type: String, default: '' },
  audioData: { type: String, default: '' }, // Base64 audio (kept only when small); never returned by list APIs
  transcript: { type: String, default: '' },
  storageSizeBytes: { type: Number, default: 0 },
  // Review
  status: { type: String, enum: ['PENDING', 'APPROVED', 'FLAGGED'], default: 'PENDING' },
  criteria: { type: CriteriaSchema, default: () => ({}) },
  rating: { type: Number, min: 0, max: 5, default: 0 },
  comments: { type: [CommentSchema], default: [] },
  comment: { type: String, default: '' },
  commentedBy: { type: String, default: '' },
  commentedByRole: { type: String, default: '' },
  commentedAt: { type: Date, default: null },
}, { timestamps: true });

RecordingSchema.index({ callerId: 1, createdAt: -1 });
RecordingSchema.index({ createdAt: -1 });

module.exports = mongoose.model('Recording', RecordingSchema);
