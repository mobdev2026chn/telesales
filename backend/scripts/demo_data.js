// Sample data for LOCAL testing, so the admin portal and the app have something to show.
//
//   node scripts/demo_data.js add      -> (re)creates the sample team, leads, calls, recordings, demos ...
//   node scripts/demo_data.js live     -> keeps the sample team "working" (online, on calls) until stopped
//   node scripts/demo_data.js remove   -> deletes every sample record again
//
// Refuses to run unless MONGODB_URI points at this computer (localhost / 127.0.0.1) and NODE_ENV is not
// production. Every record it creates is marked ("demo_" ids, "demo:" call keys) and nothing else is
// touched, except that a local admin account without a user id gets one (it then needs to sign in again).
// Sample logins: any sample person's email (e.g. priya.sharma@demo.askeva.local) / Demo@1234
require('dotenv').config({ path: require('path').join(__dirname, '../.env') });
const fs = require('fs');
const path = require('path');
const mongoose = require('mongoose');
const Employee = require('../src/models/Employee');
const Lead = require('../src/models/Lead');
const CallLog = require('../src/models/CallLog');
const Recording = require('../src/models/Recording');
const RecordingIssue = require('../src/models/RecordingIssue');
const DemoBooking = require('../src/models/DemoBooking');
const Notification = require('../src/models/Notification');
const LegacyClientHit = require('../src/models/LegacyClientHit');
const { hashPassword } = require('../src/middleware/auth');

const MIN = 60 * 1000;
const HOUR = 60 * MIN;
const DAY = 24 * HOUR;
const IST = 330 * MIN;
const PASSWORD = 'Demo@1234';
const DAYS_OF_CALLS = 30;
const DAYS_OF_RECORDINGS = 14;

// ------------------------------------------------------------------ safety

function assertLocal() {
  const uri = process.env.MONGODB_URI || '';
  let host = '';
  try { host = new URL(uri.replace(/^mongodb(\+srv)?:\/\//, 'http://')).hostname; } catch (_) { host = ''; }
  if (!['localhost', '127.0.0.1', '::1'].includes(host) || process.env.NODE_ENV === 'production') {
    console.error('Refusing to run: sample data is only for the local database (MONGODB_URI must be localhost / 127.0.0.1).');
    process.exit(1);
  }
}

// ------------------------------------------------------------------ helpers

let seed = 20261124;
function rand() { // mulberry32: the same sample data on every run
  seed |= 0; seed = (seed + 0x6D2B79F5) | 0;
  let t = Math.imul(seed ^ (seed >>> 15), 1 | seed);
  t = (t + Math.imul(t ^ (t >>> 7), 61 | t)) ^ t;
  return ((t ^ (t >>> 14)) >>> 0) / 4294967296;
}
const pick = (arr) => arr[Math.floor(rand() * arr.length)];
const between = (a, b) => a + Math.floor(rand() * (b - a + 1));
const chance = (p) => rand() < p;

/** Midnight (India time) of the day [daysAgo] before today, as a UTC timestamp. */
function istMidnight(daysAgo, now = Date.now()) {
  return Math.floor((now + IST) / DAY) * DAY - IST - daysAgo * DAY;
}
const istHour = (ms) => new Date(ms + IST).getUTCHours();
const istWeekday = (ms) => new Date(ms + IST).getUTCDay(); // 0 = Sunday

const FIRST = ['Aarav', 'Vivaan', 'Aditya', 'Ishaan', 'Rohan', 'Kabir', 'Arnav', 'Dhruv', 'Siddharth', 'Nikhil', 'Pranav', 'Harsh',
  'Ananya', 'Diya', 'Isha', 'Kavya', 'Riya', 'Saanvi', 'Pooja', 'Neha', 'Shreya', 'Tanvi', 'Lakshmi', 'Nandini', 'Gayathri', 'Bhavana',
  'Ramesh', 'Ganesh', 'Prakash', 'Senthil', 'Murugan', 'Balaji', 'Venkatesh', 'Mohan', 'Arun', 'Deepak'];
const LAST = ['Sharma', 'Iyer', 'Reddy', 'Nair', 'Menon', 'Gupta', 'Patel', 'Rao', 'Krishnan', 'Subramanian', 'Pillai', 'Joshi',
  'Kulkarni', 'Banerjee', 'Das', 'Chopra', 'Agarwal', 'Bhat', 'Naidu', 'Shetty'];
const COMPANIES = ['Sri Ganesh Traders', 'Lotus Exports', 'Bright Minds Academy', 'Coastal Logistics', 'Green Leaf Organics',
  'Metro Builders', 'Sunrise Textiles', 'Pioneer Pharma', 'Royal Caterers', 'Zenith Motors', 'Apex Tutorials', 'Blue Ocean Travels'];
const COURSES = ['CRM Basics', 'Call Monitoring Suite', 'Lead Management', 'Team Analytics', 'WhatsApp Automation'];
const NOTES = ['Asked for pricing details', 'Call back after 4 PM', 'Interested in team plan', 'Comparing with another vendor',
  'Wants a demo for the manager', 'Busy, asked to call next week', 'Requested brochure on WhatsApp', 'Budget approval pending'];
const BATCHES = ['Nov Expo Leads', 'Website Inquiries', 'Referral List', 'Old Customers Renewal'];

// Sample audio already in backend/uploads/recordings (played by GET /api/recordings/:id/audio)
const UPLOADS = path.join(__dirname, '../uploads/recordings');
const AUDIO_FILES = ['sample_telesales_call.wav', 'outbound_lead_followup.wav', 'inbound_client_inquiry.wav',
  'varshini_telesales_call.wav', 'OUT_CALL_REC_20260905_124717.wav', 'OUT_CALL_REC_20260905_140810.wav']
  .filter(f => { try { return fs.statSync(path.join(UPLOADS, f)).size > 1000; } catch (_) { return false; } });

// ------------------------------------------------------------------ the sample team

const TEAM = [
  { key: 'mgr_priya', name: 'Priya Sharma', role: 'manager', team: 'Head Office', target: 0 },
  { key: 'tl_arjun', name: 'Arjun Mehta', role: 'team_leader', team: 'Team Alpha', manager: 'mgr_priya', target: 40 },
  { key: 'tl_kavya', name: 'Kavya Reddy', role: 'team_leader', team: 'Team Beta', manager: 'mgr_priya', target: 40 },
  // Callers. live: what they are doing right now. rec: share of connected calls recorded, mic: share made by the app's mic
  { key: 'cl_rahul', name: 'Rahul Verma', team: 'Team Alpha', manager: 'tl_arjun', target: 80, live: 'oncall', rec: 1, mic: 0,
    device: ['samsung', 'Samsung', 'SM-A245F', 34, '1.0.0 (4)', 'com.samsung.android.dialer', true] },
  { key: 'cl_sneha', name: 'Sneha Iyer', team: 'Team Alpha', manager: 'tl_arjun', target: 70, live: 'available', rec: 1, mic: 0,
    device: ['Xiaomi', 'Redmi', 'Redmi Note 12', 33, '1.0.0 (4)', 'com.android.contacts', true] },
  { key: 'cl_vikram', name: 'Vikram Singh', team: 'Team Alpha', manager: 'tl_arjun', target: 70, live: 'loggedout', rec: 0.35, mic: 0.4,
    device: ['vivo', 'vivo', 'V2111', 31, '1.0.0 (2)', 'com.android.dialer', false], oldApp: true },
  { key: 'cl_anjali', name: 'Anjali Nair', team: 'Team Alpha', manager: 'tl_arjun', target: 70, live: 'break', rec: 1, mic: 0,
    device: ['OnePlus', 'OnePlus', 'CPH2491', 34, '1.0.0 (4)', 'com.android.dialer', true] },
  { key: 'cl_karthik', name: 'Karthik Raj', team: 'Team Beta', manager: 'tl_kavya', target: 80, live: 'oncall', rec: 0.93, mic: 0.05,
    device: ['realme', 'realme', 'RMX3710', 33, '1.0.0 (4)', 'com.android.dialer', true] },
  { key: 'cl_divya', name: 'Divya Menon', team: 'Team Beta', manager: 'tl_kavya', target: 70, live: 'available', rec: 0.84, mic: 0.15,
    device: ['samsung', 'Samsung', 'SM-M346B', 34, '1.0.0 (4)', 'com.samsung.android.dialer', true] },
  { key: 'cl_suresh', name: 'Suresh Kumar', team: 'Team Beta', manager: 'tl_kavya', target: 70, live: 'available', rec: 0.7, mic: 0.9,
    device: ['Google', 'google', 'Pixel 7a', 35, '1.0.0 (4)', 'com.google.android.dialer', true] },
  { key: 'cl_meera', name: 'Meera Pillai', team: 'Team Beta', manager: 'tl_kavya', target: 60, live: 'offline', rec: 0, mic: 0,
    type: 'project_coordinator', recordingOff: true,
    device: ['motorola', 'motorola', 'moto g54 5G', 34, '1.0.0 (3)', 'com.android.dialer', false] },
];
const CALLERS = TEAM.filter(t => !t.role);
const LIVE_ONLINE = ['oncall', 'available', 'break'];

const demoId = (key) => `demo_${key}`;
const emailOf = (name) => `${name.toLowerCase().replace(/[^a-z]+/g, '.')}@demo.askeva.local`;

// ------------------------------------------------------------------ remove

async function removeAll() {
  const demoNames = TEAM.map(t => t.name);
  const results = await Promise.all([
    Employee.deleteMany({ id: /^demo_/ }),
    Lead.deleteMany({ id: /^demo_/ }),
    CallLog.deleteMany({ dedupKey: /^demo:/ }),
    Recording.deleteMany({ id: /^demo_/ }),
    RecordingIssue.deleteMany({ callerId: /^demo_/ }),
    DemoBooking.deleteMany({ id: /^demo_/ }),
    // Sample notifications, and alerts the server raised about sample people (e.g. inactivity)
    Notification.deleteMany({ $or: [{ id: /^demo_/ }, { recipientId: /^demo_/ }, { recipientId: 'ADMIN', senderName: { $in: demoNames } }] }),
    LegacyClientHit.deleteMany({ $or: [{ key: /^demo_/ }, { employeeId: /^demo_/ }] }),
  ]);
  const names = ['people', 'leads', 'calls', 'recordings', 'recording problems', 'demo bookings', 'notifications', 'old-app records'];
  return names.map((n, i) => `${results[i].deletedCount} ${n}`).join(', ');
}

// ------------------------------------------------------------------ add

async function ensureAdminId() {
  const admins = await Employee.find({ role: 'admin', $or: [{ id: { $exists: false } }, { id: '' }, { id: null }] }).select('_id email').lean();
  for (const a of admins) {
    await Employee.updateOne({ _id: a._id }, { $set: { id: `admin_${String(a._id).slice(-8)}` } });
    console.log(`Local admin ${a.email || a._id} had no user id: given one (sign out of the portal and sign in again).`);
  }
}

function deviceInfo(d, now) {
  if (!d) return null;
  const [manufacturer, brand, model, sdkInt, appVersion, dialerPackage, accessibilityEnabled] = d;
  return { manufacturer, brand, model, sdkInt, appVersion, dialerPackage, accessibilityEnabled, lastResult: 'builtin', reportedAt: new Date(now - between(5, 90) * MIN) };
}

async function addAll() {
  const now = Date.now();
  await ensureAdminId();
  console.log(`Removed old sample data: ${await removeAll()}`);

  // People
  const pwHash = await hashPassword(PASSWORD);
  const todayStart = istMidnight(0, now);
  const workStart = Math.min(todayStart + 9.5 * HOUR, now - 2 * HOUR);
  const people = TEAM.map((t, i) => {
    const doc = {
      id: demoId(t.key),
      name: t.name,
      email: emailOf(t.name),
      phone: `98400${String(11001 + i * 7)}`,
      password: pwHash,
      role: t.role || 'caller',
      employeeType: t.type || 'sales_team',
      team: t.team,
      dailyTarget: t.target || 0,
      managerId: t.manager ? demoId(t.manager) : '',
      managerName: t.manager ? TEAM.find(x => x.key === t.manager).name : '',
      autoRecordEnabled: !t.recordingOff,
      autoRecordDisabledAt: t.recordingOff ? new Date(now - 26 * HOUR) : null,
      deviceInfo: deviceInfo(t.device, now),
      createdAt: new Date(now - (40 + i) * DAY),
    };
    // Right now (see "live" to keep it that way while you look around)
    if (LIVE_ONLINE.includes(t.live) || t.role) {
      Object.assign(doc, { lastLoginAt: new Date(workStart), presenceUpdatedAt: new Date(now), appInForeground: true, lastSeenAt: new Date(now) });
    }
    if (t.live === 'break') Object.assign(doc, { breakType: 'Lunch', breakStartedAt: new Date(now - 12 * MIN) });
    if (t.live === 'loggedout') Object.assign(doc, { lastLoginAt: new Date(workStart), loggedOutAt: new Date(now - 40 * MIN), lastSeenAt: new Date(now - 40 * MIN), appInForeground: false });
    if (t.live === 'offline') Object.assign(doc, { lastLoginAt: new Date(now - 2 * DAY), loggedOutAt: new Date(now - 2 * DAY + 8 * HOUR), lastSeenAt: new Date(now - 2 * DAY + 8 * HOUR), appInForeground: false });
    return doc;
  });
  await Employee.insertMany(people);
  const personOf = new Map(people.map(p => [p.id, p]));

  // Leads: assigned to callers, spread over the batches
  const usedPhones = new Set();
  const newPhone = () => {
    let p;
    do { p = `${pick(['9', '8', '7'])}${String(between(100000000, 999999999))}`; } while (usedPhones.has(p));
    usedPhones.add(p);
    return p;
  };
  const leads = [];
  for (const c of CALLERS) {
    const caller = personOf.get(demoId(c.key));
    const manager = personOf.get(caller.managerId);
    for (let i = 0; i < 14; i++) {
      const phone = newPhone();
      leads.push({
        id: `demo_lead_${c.key}_${i}`,
        name: `${pick(FIRST)} ${pick(LAST)}`,
        phone,
        phoneLast10: phone.slice(-10),
        status: 'new',
        attempts: 0,
        assignedCallerId: caller.id,
        assignedCaller: caller.name,
        notes: chance(0.5) ? pick(NOTES) : '',
        batchName: pick(BATCHES),
        managerId: manager ? manager.id : '',
        managerName: manager ? manager.name : '',
        source: pick(['import', 'website', 'referral', 'expo']),
        lastCallDate: null,
        dateAdded: new Date(now - between(5, 35) * DAY),
      });
    }
  }
  const leadsOf = new Map(CALLERS.map(c => [demoId(c.key), leads.filter(l => l.assignedCallerId === demoId(c.key))]));

  // Calls (work days, 9:30 AM - 6:30 PM India time) and, for recent connected calls, their recordings
  const calls = [];
  const recordings = [];
  const issues = [];
  for (const c of CALLERS) {
    const caller = personOf.get(demoId(c.key));
    const myLeads = leadsOf.get(caller.id);
    const lastWorkDay = c.live === 'offline' ? 2 : 0; // Meera has not worked the last two days
    for (let d = DAYS_OF_CALLS; d >= lastWorkDay; d--) {
      const dayStart = istMidnight(d, now);
      if (istWeekday(dayStart + 12 * HOUR) === 0) continue; // Sunday off
      const from = dayStart + 9.5 * HOUR;
      let to = dayStart + 18.5 * HOUR;
      if (d === 0) to = Math.min(to, c.live === 'loggedout' ? now - 45 * MIN : now - 4 * MIN);
      if (to <= from) continue;
      const count = Math.round(between(22, 42) * Math.min(1, (to - from) / (9 * HOUR)));
      const times = Array.from({ length: count }, () => from + rand() * (to - from)).sort((a, b) => a - b);
      for (const ts of times) {
        if (c.live === 'break' && d === 0 && ts > now - 12 * MIN) continue; // on break: no calls since
        const lead = chance(0.75) ? pick(myLeads) : null;
        const phone = lead ? lead.phone : newPhone();
        const r = rand();
        const type = r < 0.7 ? 'outgoing' : r < 0.85 ? 'incoming' : r < 0.95 ? 'missed' : 'rejected';
        const connected = (type === 'outgoing' && chance(0.62)) || type === 'incoming';
        const duration = connected ? (chance(0.2) ? between(5, 20) : between(30, 540)) : 0;
        const callId = new mongoose.Types.ObjectId();
        const call = {
          _id: callId,
          dedupKey: `demo:${caller.id}:${Math.round(ts)}:${phone.slice(-10)}`,
          callerId: caller.id,
          callerName: caller.name,
          callerPhone: caller.phone,
          contactName: lead ? lead.name : (chance(0.3) ? `${pick(FIRST)} ${pick(LAST)}` : ''),
          phoneNumber: phone,
          type,
          timestamp: new Date(ts),
          durationSeconds: duration,
          simSlot: 1,
          note: '',
          recordingUrl: '',
          recordingId: '',
        };
        if (lead) {
          lead.attempts += 1;
          if (!lead.lastCallDate || lead.lastCallDate < call.timestamp) lead.lastCallDate = call.timestamp;
        }
        // Recordings of connected work calls (last two weeks), as each phone would upload them
        if (duration >= 10 && d <= DAYS_OF_RECORDINGS && AUDIO_FILES.length) {
          if (chance(c.rec)) {
            const mic = chance(c.mic);
            const reviewed = chance(0.25);
            const rating = reviewed ? between(2, 5) : 0;
            const rec = {
              id: `demo_rec_${calls.length}`,
              callerId: caller.id,
              callerName: caller.name,
              callerPhone: caller.phone,
              contactName: call.contactName || phone,
              phoneNumber: phone,
              type: type === 'incoming' ? 'INCOMING' : 'OUTGOING',
              fileName: pick(AUDIO_FILES),
              originalFileName: `demo_${calls.length}.m4a`,
              callStartedAt: call.timestamp,
              simSlot: 1,
              callLogId: String(callId),
              durationSeconds: duration,
              captureSource: mic ? 'mic' : 'builtin',
              speaker: mic ? pick(['on', 'on', 'not_found']) : '',
              status: reviewed ? (rating >= 3 ? 'APPROVED' : 'FLAGGED') : 'PENDING',
              rating,
              criteria: reviewed ? { g: between(2, 5), p: between(2, 5), o: between(1, 5), c: between(1, 5), t: between(2, 5), s: between(2, 5) } : {},
              comments: reviewed && chance(0.5)
                ? [{ text: pick(['Good opening, confirm the budget earlier.', 'Handle the price objection with the team plan.', 'Great closing!', 'Speak a little slower.']),
                  by: TEAM.find(x => x.key === c.manager).name, byRole: 'team_leader', at: new Date(ts + between(1, 30) * HOUR) }]
                : [],
              createdAt: new Date(ts + duration * 1000 + between(20, 90) * 1000),
              updatedAt: new Date(ts + duration * 1000 + between(20, 90) * 1000),
            };
            recordings.push(rec);
            call.recordingId = rec.id;
            call.recordingUrl = `/api/recordings/${rec.id}/audio`;
            if (mic && d <= 7 && duration >= 10) issues.push(issueDoc(caller, c, 'mic_only', call, now));
          } else if (d <= 7) {
            issues.push(issueDoc(caller, c, 'lost', call, now));
          }
        }
        calls.push(call);
      }
    }
    // Right now on a call: a call that started a few minutes ago
    if (c.live === 'oncall') {
      const lead = pick(myLeads);
      calls.push({
        _id: new mongoose.Types.ObjectId(),
        dedupKey: `demo:${caller.id}:${now - 3 * MIN}:${lead.phone.slice(-10)}`,
        callerId: caller.id, callerName: caller.name, callerPhone: caller.phone,
        contactName: lead.name, phoneNumber: lead.phone, type: 'outgoing',
        timestamp: new Date(now - 3 * MIN), durationSeconds: 95, simSlot: 1, note: '', recordingUrl: '', recordingId: '',
      });
      lead.attempts += 1;
      lead.lastCallDate = new Date(now - 3 * MIN);
    }
  }

  // Lead statuses that match how often each lead was called
  for (const l of leads) {
    if (!l.attempts) continue;
    l.status = pick(l.attempts >= 4
      ? ['interested', 'won', 'bookDemo', 'demoDone', 'followUp', 'notInterested', 'lost']
      : ['followUp', 'notPickup', 'busyOnCall', 'interested', 'newFollowUp', 'bookDemo', 'notInterested']);
  }

  await Lead.insertMany(leads, { ordered: false });
  for (let i = 0; i < calls.length; i += 1000) await CallLog.insertMany(calls.slice(i, i + 1000), { ordered: false });
  for (let i = 0; i < recordings.length; i += 500) await Recording.insertMany(recordings.slice(i, i + 500), { ordered: false, timestamps: false });
  const issueRows = issues.slice(-120);
  if (issueRows.length) await RecordingIssue.insertMany(issueRows, { timestamps: false });

  // Demo bookings: last 10 days and the next 5
  const demos = [];
  const interested = leads.filter(l => ['interested', 'bookDemo', 'demoDone', 'won'].includes(l.status));
  for (let i = 0; i < Math.min(28, interested.length); i++) {
    const lead = interested[i];
    const caller = personOf.get(lead.assignedCallerId);
    const tl = personOf.get(caller.managerId);
    const dayOffset = between(-10, 5);
    const start = istMidnight(-dayOffset, now) + between(10, 17) * HOUR;
    const past = start < now;
    demos.push({
      id: `demo_demo_${i}`,
      leadId: lead.id,
      clientName: lead.name,
      companyName: pick(COMPANIES),
      clientPhone: lead.phone,
      callerId: caller.id,
      callerName: caller.name,
      callerPhone: caller.phone,
      scheduledAt: new Date(start),
      slot: slotLabel(start, 60),
      durationMinutes: 60,
      course: pick(COURSES),
      teamLeaderId: tl.id,
      teamLeaderName: tl.name,
      reason: '',
      status: past ? pick(['DONE', 'DONE', 'DONE', 'CANCELLED', 'RESCHEDULE']) : 'BOOKED',
      createdAt: new Date(start - between(1, 4) * DAY),
      updatedAt: new Date(start - between(0, 1) * DAY),
    });
  }
  if (demos.length) await DemoBooking.insertMany(demos, { timestamps: false });

  // Notifications: review feedback for callers, target reached for a few
  const notifs = [];
  recordings.filter(r => r.comments.length).slice(-12).forEach((r, i) => notifs.push({
    id: `demo_ntf_review_${i}`, recipientId: r.callerId, recipientPhone: r.callerPhone, recipientName: r.callerName,
    senderName: r.comments[0].by, senderRole: 'team_leader', recordingId: r.id, contactName: r.contactName,
    title: 'New Call Quality Feedback', message: `Feedback on your call with ${r.contactName}`, comment: r.comments[0].text,
    rating: r.rating, isRead: chance(0.4), createdAt: r.comments[0].at, updatedAt: r.comments[0].at,
  }));
  ['cl_rahul', 'cl_karthik', 'cl_sneha'].forEach((k, i) => notifs.push({
    id: `demo_ntf_target_${i}`, recipientId: 'ADMIN', senderName: TEAM.find(t => t.key === k).name, senderRole: 'caller',
    title: 'Daily Target Achieved 🎯', message: `${TEAM.find(t => t.key === k).name} reached the daily call target yesterday.`,
    isRead: false, createdAt: new Date(now - (20 + i) * HOUR), updatedAt: new Date(now - (20 + i) * HOUR),
  }));
  if (notifs.length) await Notification.insertMany(notifs, { timestamps: false });

  // An agent still on an old app build (no login): shown on Phone health
  for (const c of CALLERS.filter(x => x.oldApp)) {
    const p = personOf.get(demoId(c.key));
    await LegacyClientHit.create({ key: `demo_legacy_${c.key}`, employeeId: p.id, name: p.name, phone: p.phone, lastPath: '/calls/sync',
      userAgent: 'Dart/3.4 (dart:io)', requests: between(40, 160), firstSeenAt: new Date(now - 9 * DAY), lastSeenAt: new Date(now - 50 * MIN) });
  }

  console.log(`Added: ${people.length} people, ${leads.length} leads, ${calls.length} calls, ${recordings.length} recordings, ` +
    `${issueRows.length} recording problems, ${demos.length} demo bookings, ${notifs.length} notifications.`);
  console.log(`Sample logins (password ${PASSWORD}): ${emailOf('Priya Sharma')} (manager), ${emailOf('Arjun Mehta')} (team leader), ${emailOf('Rahul Verma')} (agent).`);
}

function issueDoc(caller, c, kind, call, now) {
  const [manufacturer, brand, model, sdkInt, appVersion, dialerPackage, accessibilityEnabled] = c.device || [];
  const google = dialerPackage === 'com.google.android.dialer';
  const why = google ? 'The phone uses "Phone by Google", which keeps its recordings private'
    : "The phone's own call recording was not found (auto-record off, or no recorder on this phone)";
  return {
    callerId: caller.id,
    callerName: caller.name,
    kind,
    reason: kind === 'lost'
      ? `Not recorded: the microphone recording was silent and was discarded. ${why}.`
      : `${why}. AskEVA's microphone recording was uploaded; loudspeaker was on, so the customer should be audible.`,
    result: kind === 'lost' ? 'silent' : 'ok',
    speaker: kind === 'lost' ? '' : 'on',
    talkSeconds: call.durationSeconds,
    accessibilityEnabled: accessibilityEnabled === undefined ? null : accessibilityEnabled,
    manufacturer: manufacturer || '', brand: brand || '', model: model || '', sdkInt: sdkInt || 0,
    dialerPackage: dialerPackage || '', appVersion: appVersion || '',
    callProcessedAt: new Date(call.timestamp.getTime() + call.durationSeconds * 1000 + 30 * 1000),
    createdAt: new Date(Math.min(now, call.timestamp.getTime() + call.durationSeconds * 1000 + 60 * 1000)),
    updatedAt: new Date(Math.min(now, call.timestamp.getTime() + call.durationSeconds * 1000 + 60 * 1000)),
  };
}

function slotLabel(startMs, minutes) {
  const fmt = (ms) => new Intl.DateTimeFormat('en-US', { timeZone: 'Asia/Kolkata', hour: 'numeric', minute: '2-digit', hour12: true }).format(new Date(ms));
  return `${fmt(startMs)} - ${fmt(startMs + minutes * MIN)}`;
}

// ------------------------------------------------------------------ live

// Keeps the sample team "working" while the portal is open: online people stay online, the two agents
// on a call keep making calls, available agents call every ~10 minutes (so the server's inactivity
// alert stays quiet). Stop with Ctrl+C.
async function live() {
  console.log('Keeping the sample team live (updates every minute). Stop with Ctrl+C.');
  const tick = async () => {
    const now = Date.now();
    for (const c of CALLERS.filter(x => LIVE_ONLINE.includes(x.live)).concat(TEAM.filter(t => t.role))) {
      const id = demoId(c.key);
      const set = { presenceUpdatedAt: new Date(now), appInForeground: true, lastSeenAt: new Date(now) };
      if (c.live === 'break') set.breakStartedAt = new Date(now - 12 * MIN);
      await Employee.updateOne({ id }, { $set: set });
      const every = c.live === 'oncall' ? 4 * MIN : c.live === 'available' ? 10 * MIN : 0;
      if (!every) continue;
      const last = await CallLog.findOne({ callerId: id }).sort({ timestamp: -1 }).select('timestamp').lean();
      if (last && now - new Date(last.timestamp).getTime() < every) continue;
      const lead = await Lead.findOne({ assignedCallerId: id }).skip(between(0, 13)).lean();
      if (!lead) continue;
      const p = await Employee.findOne({ id }).select('name phone').lean();
      const duration = between(45, 300);
      const callId = new mongoose.Types.ObjectId();
      const recId = `demo_rec_live_${now}_${c.key}`;
      await CallLog.create({
        _id: callId, dedupKey: `demo:${id}:${now}:${lead.phone.slice(-10)}`, callerId: id, callerName: p.name, callerPhone: p.phone,
        contactName: lead.name, phoneNumber: lead.phone, type: 'outgoing', timestamp: new Date(now - duration * 1000),
        durationSeconds: duration, simSlot: 1, recordingId: recId, recordingUrl: `/api/recordings/${recId}/audio`,
      });
      if (AUDIO_FILES.length) {
        await Recording.create({
          id: recId, callerId: id, callerName: p.name, callerPhone: p.phone, contactName: lead.name, phoneNumber: lead.phone,
          type: 'OUTGOING', fileName: pick(AUDIO_FILES), originalFileName: `${recId}.m4a`, callStartedAt: new Date(now - duration * 1000),
          simSlot: 1, callLogId: String(callId), durationSeconds: duration, captureSource: 'builtin',
        });
      }
      await Lead.updateOne({ id: lead.id }, { $inc: { attempts: 1 }, $set: { lastCallDate: new Date(now - duration * 1000) } });
    }
  };
  for (;;) {
    try { await tick(); } catch (err) { console.warn('live update failed:', err.message); }
    await new Promise(r => setTimeout(r, MIN));
  }
}

// ------------------------------------------------------------------ main

(async () => {
  assertLocal();
  const cmd = (process.argv[2] || '').toLowerCase();
  if (!['add', 'remove', 'live'].includes(cmd)) {
    console.log('Usage: node scripts/demo_data.js add | live | remove');
    process.exit(1);
  }
  await mongoose.connect(process.env.MONGODB_URI, { serverSelectionTimeoutMS: 10000 });
  console.log(`Database: ${mongoose.connection.host}/${mongoose.connection.name}`);
  if (cmd === 'add') await addAll();
  if (cmd === 'remove') console.log(`Removed: ${await removeAll()}`);
  if (cmd === 'live') await live();
  await mongoose.disconnect();
  process.exit(0);
})().catch(err => {
  console.error(err.message);
  process.exit(1);
});
