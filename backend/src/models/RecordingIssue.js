const mongoose = require('mongoose');

// A work call whose recording is missing or may lack the customer's voice, reported by the app's per-call
// diagnostics (routes/diagnostics.js). Shown to admins / managers on the Recordings page. Never holds a
// customer number or audio: only the caller, the reason and the phone it happened on.
const RecordingIssueSchema = new mongoose.Schema({
  callerId: { type: String, default: '' },
  callerName: { type: String, default: '' },
  // 'lost' = a connected call has no recording at all; 'mic_only' = AskEVA's microphone recording was
  // uploaded because the phone's own recording was not found (customer voice may be missing)
  kind: { type: String, enum: ['lost', 'mic_only'], required: true },
  reason: { type: String, default: '' },
  // Raw diagnostics, for support
  result: { type: String, default: '' },
  note: { type: String, default: '' },
  speaker: { type: String, default: '' },
  talkSeconds: { type: Number, default: 0 },
  accessibilityEnabled: { type: Boolean, default: null },
  manufacturer: { type: String, default: '' },
  brand: { type: String, default: '' },
  model: { type: String, default: '' },
  sdkInt: { type: Number, default: 0 },
  dialerPackage: { type: String, default: '' },
  appVersion: { type: String, default: '' },
  // When the phone processed the call (device clock); createdAt is when the server got the report
  callProcessedAt: { type: Date, default: null },
}, { timestamps: true });

RecordingIssueSchema.index({ createdAt: -1 });
RecordingIssueSchema.index({ callerId: 1, createdAt: -1 });

module.exports = mongoose.model('RecordingIssue', RecordingIssueSchema);
