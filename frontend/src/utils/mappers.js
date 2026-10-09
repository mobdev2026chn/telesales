// ==========================================
// DATA MAPPING: server JSON → the shapes every page uses
// ==========================================
import { DEFAULT_DAILY_TARGET, DEMO_SLOT_MIN, STATUS_TO_STAGE } from '../data/constants';
import { safeImage } from './format';

export function mapUser(u) {
  const role = String(u.role || 'caller').toUpperCase();
  const t = Number(u.dailyTarget);
  return {
    id: String(u.id || u._id || ''),
    name: u.name || '—',
    email: u.email || '',
    phone: u.phone || '',
    role,
    team: u.team || '',
    target: Number.isFinite(t) && u.dailyTarget !== null && u.dailyTarget !== '' ? t : (role === 'CALLER' ? DEFAULT_DAILY_TARGET : 0),
    mgr: u.managerId ? String(u.managerId) : null,
    photoBase64: safeImage(u.photoBase64 || ''),
    avatarUrl: safeImage(u.avatarUrl || ''),
  };
}

// Points every user's `mgr` at their manager's `id`, as the server does: the stored managerId may
// be the manager's database _id, and older records only carry the manager's name.
export function linkManagers(users, raw) {
  const byOid = new Map();
  raw.forEach(r => { if (r && r._id) byOid.set(String(r._id), String(r.id || r._id)); });
  const ids = new Set(users.map(u => u.id));
  const managersByName = new Map();
  users.filter(u => u.role === 'MANAGER' || u.role === 'JR_MANAGER' || u.role === 'TEAM_LEADER' || u.role === 'ADMIN').forEach(m => {
    const k = m.name.trim().toLowerCase();
    managersByName.set(k, managersByName.has(k) ? null : m.id);   // ambiguous names are not guessed
  });
  const byId = new Map(users.map(u => [u.id, u]));
  raw.forEach(r => {
    const u = r && byId.get(String(r.id || r._id || ''));
    if (!u) return;
    if (u.mgr && !ids.has(u.mgr) && byOid.has(u.mgr)) u.mgr = byOid.get(u.mgr);
    if (!u.mgr && r.managerName) u.mgr = managersByName.get(String(r.managerName).trim().toLowerCase()) || null;
    if (u.mgr === u.id) u.mgr = null;
  });
  return users;
}

export function isUnknownName(n) {
  const s = String(n || '').trim();
  return !s || /^unknown( contact| caller)?$/i.test(s);
}

export function mapCall(c) {
  if (!c || !c.timestamp) return null;       // rows without a timestamp are skipped, never shown as "today"
  const ts = new Date(c.timestamp);
  if (isNaN(ts.getTime())) return null;
  const rawType = String(c.rawType || c.type || '').toLowerCase();
  const dur = Math.max(0, Math.round(Number(c.durationSeconds ?? c.duration ?? 0) || 0));
  const dir = ['incoming', 'inbound', 'missed', 'rejected'].includes(rawType) ? 'IN' : 'OUT';
  const conn = dur > 0;
  const missed = !conn && ['incoming', 'inbound', 'missed'].includes(rawType);
  return {
    id: String(c.id || c._id || ''),
    callerId: c.callerId ? String(c.callerId) : '',
    agent: c.callerName || '—',
    callerPhone: c.callerPhone || '',
    client: isUnknownName(c.contactName) ? null : String(c.contactName),
    phone: c.phoneNumber || '',
    dir,
    out: conn ? 'CONNECTED' : (missed ? 'MISSED' : 'NO ANSWER'),
    dur,
    ts,
    sim: c.simSlot || '—',
    recordingId: c.recordingId ? String(c.recordingId) : null,
    note: c.note || '',
  };
}

// Recording files are named like OUT_CALL_REC_20260904_123620.wav — device wall-clock time (IST).
// Only a fallback: callStartedAt from the server is authoritative.
export function parseRecordingFileTs(name) {
  const m = String(name || '').match(/(\d{4})(\d{2})(\d{2})_(\d{2})(\d{2})(\d{2})/);
  if (!m) return null;
  const d = new Date(`${m[1]}-${m[2]}-${m[3]}T${m[4]}:${m[5]}:${m[6]}+05:30`);
  return isNaN(d.getTime()) ? null : d;
}

export const EMPTY_CRIT = () => ({ g: 0, p: 0, o: 0, c: 0, t: 0, s: 0 });

// The recording itself plus its review fields (`review`), which the recordings slice merges into
// its per-recording review state (see recMetaFrom)
export function mapRecording(r) {
  const id = String(r.id || r._id || '');
  const type = String(r.type || '').toUpperCase();
  let ts = r.callStartedAt ? new Date(r.callStartedAt) : null;
  if (!ts || isNaN(ts.getTime())) ts = parseRecordingFileTs(r.fileName) || (r.createdAt ? new Date(r.createdAt) : null);
  return {
    id,
    callerId: r.callerId ? String(r.callerId) : '',
    callerPhone: r.callerPhone || '',
    agent: (r.callerName || '—').trim(),
    client: isUnknownName(r.contactName) ? null : String(r.contactName),
    phone: r.phoneNumber || '',
    dir: (type === 'INCOMING' || type === 'INBOUND') ? 'IN' : ((type === 'OUTGOING' || type === 'OUTBOUND') ? 'OUT' : ''),
    dur: Math.max(0, Math.round(Number(r.durationSeconds) || 0)),
    ts,
    createdAt: r.createdAt || null,
    fileName: r.fileName || '',
    sim: r.simSlot || null,
    review: {
      criteria: Object.assign(EMPTY_CRIT(), r.criteria || {}),
      status: String(r.status || 'PENDING').toUpperCase(),
      comments: Array.isArray(r.comments) ? r.comments : (r.comment ? [{ text: r.comment, by: r.commentedBy || '' }] : []),
      pinned: !!r.pinned,
    },
  };
}

export function newRecMeta() {
  return { crit: EMPTY_CRIT(), status: 'PENDING', comments: [], draft: '', saveState: '', dirty: false, pinned: false, pinBusy: false };
}

// Server review fields merged over the local state: unsaved star clicks and a pin being saved win
export function recMetaFrom(review, prev) {
  const p = prev || {};
  return {
    crit: p.dirty ? p.crit : review.criteria,
    status: review.status,
    comments: review.comments,
    draft: p.draft || '',
    saveState: p.saveState || '',
    dirty: !!p.dirty,
    pinned: p.pinBusy ? !!p.pinned : review.pinned,
    pinBusy: !!p.pinBusy,
  };
}

export function mapLead(l) {
  let status = String(l.status || 'new');
  if (status === 'newLead') status = 'new';
  return {
    id: String(l.id || l._id || ''),
    name: l.name || '—',
    phone: l.phone || '',
    status,
    stage: STATUS_TO_STAGE[status] || 'NEW',
    attempts: Number(l.attempts) || 0,
    agentId: l.assignedCallerId ? String(l.assignedCallerId) : '',
    agent: l.assignedCaller || '',
    managerId: l.managerId ? String(l.managerId) : '',   // manager who owns the uploaded batch
    managerName: l.managerName || '',
    notes: l.notes || '',
    batchName: l.batchName || '',
    source: l.source || '',
    lastCallDate: l.lastCallDate ? new Date(l.lastCallDate) : null,
    createdAt: l.createdAt ? new Date(l.createdAt) : null,
    updatedAt: l.updatedAt ? new Date(l.updatedAt) : null,
  };
}

export function mapDemo(d) {
  const at = d.scheduledAt ? new Date(d.scheduledAt) : null;
  const bookedAt = d.createdAt ? new Date(d.createdAt) : null;
  return {
    id: String(d.id || ''),
    clientName: d.clientName || '',
    clientPhone: d.clientPhone || '',
    callerId: d.callerId || '',
    agent: d.callerName || '',
    teamLeaderId: d.teamLeaderId || '',
    teamLeaderName: d.teamLeaderName || '',
    at: at && !isNaN(at.getTime()) ? at : null,
    durationMinutes: Number(d.durationMinutes) > 0 ? Number(d.durationMinutes) : 60,
    slot: d.slot || '',
    course: d.course || '',
    reason: d.reason || '',
    status: d.status || 'BOOKED',
    bookedAt: bookedAt && !isNaN(bookedAt.getTime()) ? bookedAt : null,
  };
}

export function mapDemoBlock(b) {
  const at = b.scheduledAt ? new Date(b.scheduledAt) : null;
  return {
    id: String(b.id || ''),
    teamLeaderId: b.teamLeaderId || '',
    teamLeaderName: b.teamLeaderName || '',
    at: at && !isNaN(at.getTime()) ? at : null,
    durationMinutes: Number(b.durationMinutes) > 0 ? Number(b.durationMinutes) : DEMO_SLOT_MIN,
    blockedByName: b.blockedByName || '',
  };
}
