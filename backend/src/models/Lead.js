const mongoose = require('mongoose');

const LeadSchema = new mongoose.Schema({
  id: { 
    type: String, 
    default: () => `lead_${Date.now()}_${Math.random().toString(36).substring(2, 8)}`,
    unique: true 
  },
  name: { type: String, required: true },
  phone: { type: String, required: true },
  status: { 
    type: String, 
    enum: ['new', 'interested', 'followUp', 'notPickup', 'won', 'lost', 'renewalFollowUp', 'busyOnCall'],
    default: 'new' 
  },
  attempts: { type: Number, default: 0 },
  assignedCaller: { type: String, default: 'Unassigned' },
  notes: { type: String, default: '' },
  lastCallDate: { type: Date, default: Date.now },
  dateAdded: { type: Date, default: Date.now },
}, { timestamps: true });

module.exports = mongoose.model('Lead', LeadSchema);
