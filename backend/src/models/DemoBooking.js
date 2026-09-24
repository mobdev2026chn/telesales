const mongoose = require('mongoose');

// A demo appointment a caller books from the app after a call.
const DemoBookingSchema = new mongoose.Schema({
  id: { type: String, required: true, unique: true },
  leadId: { type: String, default: '' },
  clientName: { type: String, default: '' },
  clientPhone: { type: String, default: '' },
  // Employee who booked it (from the token, never from the request body)
  callerId: { type: String, default: '' },
  callerName: { type: String, default: '' },
  callerPhone: { type: String, default: '' },
  // Start of the booked slot and the slot as the caller saw it ("12:00 PM - 1:00 PM")
  scheduledAt: { type: Date, required: true },
  slot: { type: String, default: '' },
  course: { type: String, default: '' }, // class / course the demo is for
  // Team Leader who runs the demo: the booking shows in their portal; one booking per slot per TL
  teamLeaderId: { type: String, default: '' },
  teamLeaderName: { type: String, default: '' },
  reason: { type: String, default: '' },
  status: { type: String, enum: ['BOOKED', 'DONE', 'CANCELLED'], default: 'BOOKED' },
}, { timestamps: true });

DemoBookingSchema.index({ callerId: 1, scheduledAt: -1 });
DemoBookingSchema.index({ scheduledAt: -1 });
DemoBookingSchema.index({ teamLeaderId: 1, scheduledAt: 1 });

module.exports = mongoose.model('DemoBooking', DemoBookingSchema);
