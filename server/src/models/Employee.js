const mongoose = require('mongoose');

const EmployeeSchema = new mongoose.Schema({
  id: { type: String, required: true, unique: true },
  name: { type: String, required: true },
  phone: { type: String, required: true },
  role: { type: String, enum: ['caller', 'manager', 'admin'], default: 'caller' },
  team: { type: String, default: 'Telesales Mumbai' },
  totalCalls: { type: Number, default: 0 },
  connectedCalls: { type: Number, default: 0 },
  talkTimeSeconds: { type: Number, default: 0 },
  rank: { type: Number, default: 1 },
  dailyTarget: { type: Number, default: 100 },
}, { timestamps: true });

module.exports = mongoose.model('Employee', EmployeeSchema);
