const mongoose = require('mongoose');

// Daily call target when none is set (new users, older records)
const DEFAULT_DAILY_TARGET = 250;

const EmployeeSchema = new mongoose.Schema({
  id: { type: String, required: true, unique: true },
  name: { type: String, required: true },
  email: { type: String, sparse: true, lowercase: true, trim: true },
  phone: { type: String, required: true },
  // bcrypt hash (legacy plaintext values are upgraded on next login). Never returned unless
  // explicitly requested with .select('+password').
  password: { type: String, default: '', select: false },
  role: { type: String, enum: ['caller', 'jr_manager', 'manager', 'admin'], default: 'caller' },
  team: { type: String, default: 'Telesales Team' },
  totalCalls: { type: Number, default: 0 },
  connectedCalls: { type: Number, default: 0 },
  talkTimeSeconds: { type: Number, default: 0 },
  rank: { type: Number, default: 1 },
  dailyTarget: { type: Number, default: DEFAULT_DAILY_TARGET },
  managerId: { type: String, default: '' },
  managerName: { type: String, default: '' },
  photoBase64: { type: String, default: '' },
  avatarUrl: { type: String, default: '' },
  // Presence (services/presence.js): last signed-in request, last explicit logout
  lastSeenAt: { type: Date, default: null },
  loggedOutAt: { type: Date, default: null },
  // Break started from the app (Tea break / Lunch); empty / null = working (services/presence.js)
  breakType: { type: String, default: '' },
  breakStartedAt: { type: Date, default: null },
}, { timestamps: true });

// Belt and braces: even a document loaded with +password never serialises it
EmployeeSchema.set('toJSON', {
  transform: (doc, ret) => { delete ret.password; return ret; },
});

module.exports = mongoose.model('Employee', EmployeeSchema);
module.exports.DEFAULT_DAILY_TARGET = DEFAULT_DAILY_TARGET;
