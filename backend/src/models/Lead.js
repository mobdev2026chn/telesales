const mongoose = require('mongoose');
const { LEAD_STATUSES } = require('../services/matching');

const LeadSchema = new mongoose.Schema({
  id: {
    type: String,
    default: () => `lead_${Date.now()}_${Math.random().toString(36).substring(2, 8)}`,
    unique: true
  },
  name: { type: String, required: true, trim: true },
  phone: { type: String, required: true, trim: true },
  // Last 10 digits of phone; used for de-duplication (older rows get it back-filled lazily)
  phoneLast10: { type: String, default: undefined },
  status: { type: String, enum: LEAD_STATUSES, default: 'new' },
  attempts: { type: Number, default: 0, min: 0 },
  assignedCallerId: { type: String, default: '' },
  assignedCaller: { type: String, default: 'Unassigned' },
  notes: { type: String, default: '' },
  batchName: { type: String, default: '' },
  source: { type: String, default: '' },
  lastCallDate: { type: Date, default: null },
  dateAdded: { type: Date, default: Date.now },
}, { timestamps: true });

// Non-unique on purpose: existing data may contain duplicates. Uniqueness is enforced in the application.
LeadSchema.index({ phoneLast10: 1 });
LeadSchema.pre('validate', function setPhoneLast10(next) {
  if (this.phone) this.phoneLast10 = String(this.phone).replace(/[^0-9]/g, '').slice(-10);
  next();
});

module.exports = mongoose.model('Lead', LeadSchema);
