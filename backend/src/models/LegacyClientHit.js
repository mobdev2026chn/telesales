const mongoose = require('mongoose');

// Requests from old app builds that use the server WITHOUT logging in (allowed only while
// LEGACY_CLIENT_GRACE is on). One row per person (or per unknown device), so admins can see on the
// Phone health page who still runs an old build and when the grace can be switched off.
const LegacyClientHitSchema = new mongoose.Schema({
  key: { type: String, required: true, unique: true }, // employee id, or "unknown:<ref or ip>"
  employeeId: { type: String, default: '' },
  name: { type: String, default: '' },
  phone: { type: String, default: '' },
  lastPath: { type: String, default: '' },
  userAgent: { type: String, default: '' },
  requests: { type: Number, default: 0 },
  firstSeenAt: { type: Date, default: Date.now },
  lastSeenAt: { type: Date, default: Date.now },
});

LegacyClientHitSchema.index({ lastSeenAt: -1 });

module.exports = mongoose.model('LegacyClientHit', LegacyClientHitSchema);
