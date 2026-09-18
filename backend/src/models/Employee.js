const mongoose = require('mongoose');

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
  dailyTarget: { type: Number, default: 40 },
  managerId: { type: String, default: '' },
  managerName: { type: String, default: '' },
  photoBase64: { type: String, default: '' },
  avatarUrl: { type: String, default: '' },
}, { timestamps: true });

// Belt and braces: even a document loaded with +password never serialises it
EmployeeSchema.set('toJSON', {
  transform: (doc, ret) => { delete ret.password; return ret; },
});

module.exports = mongoose.model('Employee', EmployeeSchema);
