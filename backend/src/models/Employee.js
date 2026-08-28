const mongoose = require('mongoose');

const EmployeeSchema = new mongoose.Schema({
  id: { type: String, required: true, unique: true },
  name: { type: String, required: true },
  email: { type: String, sparse: true, lowercase: true, trim: true },
  phone: { type: String, required: true },
  password: { type: String, default: 'admin123' },
  role: { type: String, enum: ['caller', 'manager', 'admin'], default: 'caller' },
  team: { type: String, default: 'Telesales Mumbai' },
  totalCalls: { type: Number, default: 0 },
  connectedCalls: { type: Number, default: 0 },
  talkTimeSeconds: { type: Number, default: 0 },
  rank: { type: Number, default: 1 },
  dailyTarget: { type: Number, default: 100 },
  managerId: { type: String, default: '' },
  managerName: { type: String, default: '' },
  photoBase64: { type: String, default: '' },
  avatarUrl: { type: String, default: '' },
}, { timestamps: true });

module.exports = mongoose.model('Employee', EmployeeSchema);
