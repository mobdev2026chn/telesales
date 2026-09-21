// Recordings: the ONE implementation of list / upload / audio / comment / review / delete.
// Paths are absolute (mounted with app.use(router)) so every URL alias the clients use lives here.
const express = require('express');
const fs = require('fs');
const path = require('path');
const crypto = require('crypto');
const Recording = require('../models/Recording');
const CallLog = require('../models/CallLog');
const Employee = require('../models/Employee');
const Notification = require('../models/Notification');
const { MANAGERS } = require('../middleware/auth');
const {
  escapeRegex, last10, byIdQuery, exactNameRegex, phoneRegex, anyPhoneRegex, serverError, parseLimit, parseDate, parseDeviceTime,
} = require('../utils/common');
const { resolveScope, recordingQueryFor, ownerInScope, findEmployeeByRef } = require('../services/scope');
const { pickClosestCall, recordingStartMs, parseRange, LINK_WINDOW_MS } = require('../services/matching');
const { applyRecordingToLead } = require('../services/callStats');

const router = express.Router();
const uploadsDir = path.join(__dirname, '../../uploads/recordings');
if (!fs.existsSync(uploadsDir)) fs.mkdirSync(uploadsDir, { recursive: true });

// ---- Shapes ------------------------------------------------------------------------------------
const CRITERIA_KEYS = ['g', 'p', 'o', 'c', 't', 's'];
const STATUSES = ['PENDING', 'APPROVED', 'FLAGGED'];

function deriveType(r) {
  if (r.type === 'INCOMING' || r.type === 'OUTGOING') return r.type;
  const name = String(r.originalFileName || r.fileName || '');
  if (/^INC_/i.test(name) || /(^|_)INC_/i.test(name)) return 'INCOMING';
  if (/^OUT_/i.test(name) || /(^|_)OUT_/i.test(name)) return 'OUTGOING';
  return 'OUTGOING';
}

function toRecordingDTO(r, extra = {}) {
  const id = r.id || String(r._id);
  const criteria = {};
  CRITERIA_KEYS.forEach(k => { criteria[k] = Math.round(Number(r.criteria && r.criteria[k]) || 0); });
  let comments = Array.isArray(r.comments) ? r.comments.map(c => ({ text: c.text, by: c.by || '', byRole: c.byRole || '', at: c.at || null })) : [];
  // Older reviews only have the single comment field
  if (comments.length === 0 && r.comment) {
    comments = [{ text: r.comment, by: r.commentedBy || '', byRole: r.commentedByRole || '', at: r.commentedAt || r.updatedAt || null }];
  }
  return {
    id,
    callerId: r.callerId || '',
    callerName: r.callerName || '',
    callerPhone: r.callerPhone || '',
    contactName: r.contactName || '',
    phoneNumber: r.phoneNumber || '',
    type: deriveType(r),
    fileName: r.fileName || '',
    callStartedAt: r.callStartedAt ? new Date(r.callStartedAt).toISOString() : null,
    durationSeconds: Math.max(0, Math.round(Number(r.durationSeconds) || 0)),
    audioUrl: `/api/recordings/${encodeURIComponent(id)}/audio`,
    createdAt: r.createdAt || null,
    status: STATUSES.includes(r.status) ? r.status : 'PENDING',
    criteria,
    rating: Math.round((Number(r.rating) || 0) * 10) / 10,
    comments,
    comment: r.comment || '',
    commentedBy: r.commentedBy || '',
    callLogId: r.callLogId || null,
    simSlot: r.simSlot || null,
    transcript: r.transcript || '',
    dateStr: r.dateStr || '',
    timeStr: r.timeStr || '',
    storageSizeBytes: r.storageSizeBytes || 0,
    ...extra,
  };
}

// ---- Audio helpers -----------------------------------------------------------------------------
function getAudioMimeType(fileName = '', filePath = '') {
  try {
    const header = Buffer.alloc(12);
    const fd = fs.openSync(filePath, 'r');
    fs.readSync(fd, header, 0, header.length, 0);
    fs.closeSync(fd);
    if (header.toString('ascii', 0, 4) === 'RIFF' && header.toString('ascii', 8, 12) === 'WAVE') return 'audio/wav';
    if (header.toString('ascii', 4, 8) === 'ftyp') return 'audio/mp4';
    if (header[0] === 0x49 && header[1] === 0x44 && header[2] === 0x33) return 'audio/mpeg';
    if (header[0] === 0xff && (header[1] & 0xe0) === 0xe0) return (header[1] & 0x06) === 0 ? 'audio/aac' : 'audio/mpeg';
    if (header.toString('ascii', 0, 4) === 'OggS') return 'audio/ogg';
    if (header.toString('ascii', 0, 5) === '#!AMR') return 'audio/amr';
  } catch (_) {}
  const ext = path.extname(fileName).toLowerCase();
  if (ext === '.wav') return 'audio/wav';
  if (ext === '.m4a' || ext === '.mp4' || ext === '.aac') return 'audio/mp4';
  if (ext === '.mp3') return 'audio/mpeg';
  if (ext === '.3gp' || ext === '.3gpp') return 'audio/3gpp';
  if (ext === '.amr') return 'audio/amr';
  if (ext === '.ogg') return 'audio/ogg';
  return 'audio/wav';
}

// Safe on-disk path for a stored file name (no directories, no traversal)
function diskPath(fileName) {
  if (!fileName || typeof fileName !== 'string') return null;
  const base = path.basename(fileName);
  if (!/^[\w-]+(\.[\w-]+)*$/.test(base)) return null;
  return path.join(uploadsDir, base);
}

function fileSize(p) {
  try { return p ? fs.statSync(p).size : 0; } catch (_) { return 0; }
}

function sendAudio(req, res, { size, mimeType, readRange, readAll }) {
  res.setHeader('Accept-Ranges', 'bytes');
  const range = parseRange(req.headers.range, size);
  if (range === null) {
    res.writeHead(416, { 'Content-Range': `bytes */${size}` });
    return res.end();
  }
  if (range) {
    res.writeHead(206, {
      'Content-Range': `bytes ${range.start}-${range.end}/${size}`,
      'Content-Length': range.end - range.start + 1,
      'Content-Type': mimeType,
    });
    return readRange(range.start, range.end);
  }
  res.writeHead(200, { 'Content-Length': size, 'Content-Type': mimeType });
  return readAll();
}

function streamAudioFile(filePath, req, res, mimeType) {
  const size = fileSize(filePath);
  return sendAudio(req, res, {
    size,
    mimeType,
    readRange: (start, end) => fs.createReadStream(filePath, { start, end }).pipe(res),
    readAll: () => fs.createReadStream(filePath).pipe(res),
  });
}

function streamAudioBuffer(buffer, req, res, mimeType) {
  return sendAudio(req, res, {
    size: buffer.length,
    mimeType,
    readRange: (start, end) => res.end(buffer.subarray(start, end + 1)),
    readAll: () => res.end(buffer),
  });
}

function getWavDurationSeconds(filePath) {
  try {
    const size = fileSize(filePath);
    if (size <= 44) return 0;
    const fd = fs.openSync(filePath, 'r');
    const buf = Buffer.alloc(44);
    fs.readSync(fd, buf, 0, 44, 0);
    fs.closeSync(fd);
    if (buf.toString('ascii', 0, 4) === 'RIFF') {
      const byteRate = buf.readUInt32LE(28);
      if (byteRate > 0) return Math.max(1, Math.round((size - 44) / byteRate));
    }
    return 0;
  } catch (_) {
    return 0;
  }
}

// Talk time (call-log duration, counted from answer) of the calls these recordings are linked to.
async function linkedCallTalkSeconds(recs) {
  const ids = [...new Set(recs.map(r => String(r.callLogId || '')).filter(id => /^[a-f0-9]{24}$/i.test(id)))];
  if (ids.length === 0) return new Map();
  const calls = await CallLog.find({ _id: { $in: ids } }).select('durationSeconds').lean();
  return new Map(calls.filter(c => c.durationSeconds > 0).map(c => [String(c._id), Math.round(c.durationSeconds)]));
}

// Record-level permission for managers / callers holding a token (legacy clients are not checked
// during the grace period, as before).
async function canAccessRecording(req, rec) {
  if (!req.user) return true;
  if (req.user.role === 'admin') return true;
  if (req.user.role === 'caller') {
    if (rec.callerId) return rec.callerId === req.user.id;
    return (rec.callerName || '').trim().toLowerCase() === (req.user.name || '').trim().toLowerCase();
  }
  const scope = await resolveScope(req, {});
  return ownerInScope(scope, { id: rec.callerId, phone: rec.callerPhone, name: rec.callerName });
}

// ---- GET audio ---------------------------------------------------------------------------------
router.get(['/api/recordings/:id/audio', '/api/admin/recordings/:id/audio', '/api/recordings/:id/stream'], async (req, res) => {
  try {
    const recId = String(req.params.id);
    let rec = await Recording.findOne(byIdQuery(recId));

    if (!rec) {
      // The admin web may pass a CallLog id (or a stored file name) instead of a recording id
      const callLog = await CallLog.findOne(byIdQuery(recId)).lean();
      if (callLog) {
        if (callLog.recordingId) rec = await Recording.findOne({ id: callLog.recordingId });
        if (!rec) rec = await Recording.findOne({ callLogId: String(callLog._id) });
        if (!rec && callLog.recordingUrl) {
          const base = path.basename(String(callLog.recordingUrl));
          rec = await Recording.findOne({ $or: [{ fileName: base }, { audioUrl: callLog.recordingUrl }] });
        }
      } else if (/^[\w-]+(\.[\w-]+)*$/.test(recId)) {
        rec = await Recording.findOne({ $or: [{ fileName: recId }, { audioUrl: `/uploads/recordings/${recId}` }] });
      }
    }
    if (!rec) return res.status(404).json({ success: false, message: 'Recording not found' });
    if (!(await canAccessRecording(req, rec))) {
      return res.status(403).json({ success: false, message: 'You do not have permission for this recording.' });
    }

    const names = [rec.fileName, rec.audioUrl ? path.basename(rec.audioUrl) : null].filter(Boolean);
    for (const name of names) {
      const p = diskPath(name);
      if (p && fileSize(p) > 100) return streamAudioFile(p, req, res, getAudioMimeType(name, p));
    }

    if (rec.audioData && typeof rec.audioData === 'string' && rec.audioData.length > 100) {
      const buffer = Buffer.from(rec.audioData.replace(/^data:audio\/[\w.+-]+;base64,/, ''), 'base64');
      if (buffer.length > 100) {
        const name = rec.fileName || `${rec.id}.wav`;
        const p = diskPath(name);
        if (p) { try { fs.writeFileSync(p, buffer); } catch (_) { /* cache only */ } }
        return streamAudioBuffer(buffer, req, res, getAudioMimeType(name, p));
      }
    }

    return res.status(404).json({ success: false, message: 'Original call audio recording not found' });
  } catch (err) {
    return serverError(res, err, 'recordings.audio');
  }
});

// ---- GET list ----------------------------------------------------------------------------------
router.get(['/api/recordings', '/api/admin/recordings'], async (req, res) => {
  try {
    const scope = await resolveScope(req, req.query);
    // Admin without filters: every recording (including those of since-deleted employees)
    const conditions = [scope.all ? {} : recordingQueryFor(scope)];
    // callerName / userId / callerIds narrowing is done by resolveScope (exact match, inside the user's scope)
    const { phoneNumber, type, search, before } = req.query;
    if (phoneNumber && String(phoneNumber).trim()) {
      const re = phoneRegex(phoneNumber);
      conditions.push(re ? { phoneNumber: re } : { phoneNumber: String(phoneNumber).trim() });
    }
    if (type && type !== 'all') {
      const t = String(type).toLowerCase();
      if (t === 'inbound' || t === 'incoming') conditions.push({ $or: [{ type: 'INCOMING' }, { type: { $in: ['', null] }, $or: [{ originalFileName: /^INC_/i }, { fileName: /^INC_/i }] }] });
      if (t === 'outbound' || t === 'outgoing') conditions.push({ $nor: [{ type: 'INCOMING' }, { type: { $in: ['', null] }, $or: [{ originalFileName: /^INC_/i }, { fileName: /^INC_/i }] }] });
    }
    if (search && String(search).trim()) {
      const re = new RegExp(escapeRegex(String(search).trim()), 'i');
      conditions.push({ $or: [{ callerName: re }, { contactName: re }, { phoneNumber: re }] });
    }
    const scopeQuery = conditions.length === 1 ? conditions[0] : { $and: conditions };

    const beforeDate = parseDate(before);
    const pageQuery = beforeDate ? { $and: [scopeQuery, { createdAt: { $lt: beforeDate } }] } : scopeQuery;
    const limit = parseLimit(req.query.limit, 500, 2000);

    const rows = await Recording.aggregate([
      { $match: pageQuery },
      { $sort: { createdAt: -1 } },
      { $limit: limit + 1 },
      { $addFields: { hasAudioData: { $gt: [{ $ifNull: ['$audioData', ''] }, ''] } } },
      { $project: { audioData: 0 } },
    ]);
    const hasMore = rows.length > limit;
    const page = rows.slice(0, limit);
    const talkSecondsByCall = await linkedCallTalkSeconds(page);

    const recordings = page.map(r => {
      const p = diskPath(r.fileName) || diskPath(r.audioUrl ? path.basename(r.audioUrl) : '');
      const size = fileSize(p);
      // Duration = talk time of the call (from answer), not the length of the audio file, which can include ringing
      let durationSeconds = talkSecondsByCall.get(String(r.callLogId || '')) || r.durationSeconds || 0;
      if (durationSeconds <= 1 && size > 44) durationSeconds = getWavDurationSeconds(p) || durationSeconds;
      return toRecordingDTO({ ...r, durationSeconds }, { hasAudio: size > 100 || !!r.hasAudioData });
    });

    const [agg] = await Recording.aggregate([
      { $match: scopeQuery },
      { $group: { _id: null, count: { $sum: 1 }, bytes: { $sum: { $ifNull: ['$storageSizeBytes', 0] } } } },
    ]);
    const usedBytes = agg ? agg.bytes : 0;

    res.json({
      success: true,
      count: recordings.length,
      total: agg ? agg.count : 0,
      hasMore,
      storage: { usedBytes, usedGB: +(usedBytes / (1024 ** 3)).toFixed(3), count: agg ? agg.count : 0 },
      recordings,
    });
  } catch (err) {
    serverError(res, err, 'recordings.list');
  }
});

// ---- POST upload -------------------------------------------------------------------------------
function sanitizeOriginalName(name) {
  const base = path.basename(String(name || '')).replace(/[^a-zA-Z0-9_.-]/g, '').replace(/^\.+/, '');
  return base.slice(-120);
}

// Who is uploading: the token's user (fresh from the DB); legacy clients by the body fields.
async function uploaderFor(req) {
  if (req.user) {
    const emp = await Employee.findOne({ id: req.user.id }).lean();
    return emp || { id: req.user.id, name: req.user.name, phone: req.user.phone || '' };
  }
  const { callerId, callerPhone, callerName } = req.body || {};
  for (const ref of [callerId, callerPhone, callerName]) {
    if (!ref) continue;
    const emp = await findEmployeeByRef(ref);
    if (emp) return emp;
  }
  return null;
}

router.post(['/api/recordings', '/api/user/recordings/upload', '/api/admin/recordings'], async (req, res) => {
  try {
    const body = req.body || {};
    const { contactName, phoneNumber, transcript, dateStr, timeStr, audioData } = body;
    const uploader = await uploaderFor(req);
    if (!uploader && !body.callerName) {
      return res.status(400).json({ success: false, message: 'Caller could not be identified' });
    }
    const callerId = uploader ? uploader.id : '';
    const callerName = uploader ? uploader.name : String(body.callerName).slice(0, 120);
    const callerPhone = uploader ? (uploader.phone || '') : String(body.callerPhone || '').slice(0, 40);

    if (!phoneNumber || !String(phoneNumber).trim()) {
      return res.status(400).json({ success: false, message: 'phoneNumber is required' });
    }

    // Idempotent retry: same caller + same original file name -> the existing recording
    const originalName = sanitizeOriginalName(body.fileName);
    if (originalName) {
      const dupe = await Recording.findOne(callerId
        ? { $or: [{ callerId, originalFileName: originalName }, { callerId: { $in: ['', null] }, callerName: exactNameRegex(callerName), fileName: originalName }] }
        : { callerName: exactNameRegex(callerName), $or: [{ originalFileName: originalName }, { fileName: originalName }] }
      ).select('-audioData').lean();
      if (dupe) return res.status(200).json({ success: true, duplicate: true, recording: toRecordingDTO(dupe) });
    }

    const recId = `rec_${Date.now()}_${crypto.randomBytes(4).toString('hex')}`;
    let storedName = '';
    let storageSizeBytes = 0;
    if (audioData && typeof audioData === 'string' && audioData.length > 50) {
      try {
        const buffer = Buffer.from(audioData.replace(/^data:audio\/[\w.+-]+;base64,/, ''), 'base64');
        const safeOriginal = originalName || `CALL_REC_${Date.now()}.wav`;
        storedName = `${String(callerId || 'legacy').replace(/[^\w-]/g, '')}_${crypto.randomUUID()}_${safeOriginal}`;
        fs.writeFileSync(path.join(uploadsDir, storedName), buffer);
        storageSizeBytes = buffer.length;
      } catch (fileErr) {
        console.warn('Could not write audio file to disk:', fileErr.message);
        storedName = '';
      }
    }

    // Call start: explicit ISO, else the call log timestamp the app matched, else unknown
    const callStartedAt = parseDeviceTime(body.callStartedAt) || parseDeviceTime(body.callLogTimestampMs) || null;
    const durationSeconds = Math.max(0, Math.round(Number(body.durationSeconds) || 0));
    const bodyType = String(body.type || '').toUpperCase();
    const type = bodyType === 'INCOMING' || bodyType === 'OUTGOING' ? bodyType : deriveType({ originalFileName: originalName });
    const simSlot = Number.isFinite(Number(body.simSlot)) && body.simSlot !== null && body.simSlot !== '' ? Math.round(Number(body.simSlot)) : null;

    const rec = await Recording.create({
      id: recId,
      callerId,
      callerName: callerName || 'Caller',
      callerPhone,
      contactName: typeof contactName === 'string' ? contactName.slice(0, 120) : '',
      phoneNumber: String(phoneNumber).trim().slice(0, 40),
      type,
      fileName: storedName || originalName,
      originalFileName: originalName,
      callStartedAt,
      simSlot,
      durationSeconds,
      audioUrl: `/api/recordings/${recId}/audio`,
      audioData: (audioData && typeof audioData === 'string' && audioData.length < 10000000) ? audioData : '',
      transcript: typeof transcript === 'string' ? transcript.slice(0, 5000) : '',
      storageSizeBytes,
      dateStr: typeof dateStr === 'string' ? dateStr.slice(0, 40) : '',
      timeStr: typeof timeStr === 'string' ? timeStr.slice(0, 40) : '',
    });

    // Link to exactly ONE CallLog: same caller + same number + start within ±5 min, closest wins
    try {
      const refMs = recordingStartMs(rec);
      const numRe = phoneRegex(rec.phoneNumber);
      if (numRe && Number.isFinite(refMs)) {
        const callerConds = [
          ...(callerId ? [{ callerId }] : []),
          ...(last10(callerPhone).length >= 8 ? [{ callerPhone: anyPhoneRegex([callerPhone]) }] : []),
          ...(!callerId && callerName ? [{ callerName: exactNameRegex(callerName) }] : []),
        ];
        if (callerConds.length) {
          const candidates = await CallLog.find({
            phoneNumber: numRe,
            $or: callerConds,
            timestamp: { $gte: new Date(refMs - LINK_WINDOW_MS), $lte: new Date(refMs + LINK_WINDOW_MS) },
          }).select('phoneNumber timestamp recordingId').lean();
          const best = pickClosestCall(candidates, { phoneNumber: rec.phoneNumber, refMs, recordingId: rec.id });
          if (best) {
            const upd = await CallLog.updateOne(
              { _id: best._id, recordingId: { $in: ['', null] } },
              { $set: { recordingId: rec.id, recordingUrl: rec.audioUrl } }
            );
            if (upd.modifiedCount > 0) {
              rec.callLogId = String(best._id);
              await Recording.updateOne({ _id: rec._id }, { $set: { callLogId: rec.callLogId } });
            }
          }
        }
      }
      await applyRecordingToLead(uploader, { phoneNumber: rec.phoneNumber, contactName: rec.contactName, durationSeconds, type });
    } catch (linkErr) {
      console.warn('CallLog/Lead link warning:', linkErr.message);
    }

    res.status(201).json({ success: true, recording: toRecordingDTO(rec.toObject()) });
  } catch (err) {
    serverError(res, err, 'recordings.upload');
  }
});

// ---- Reviews -----------------------------------------------------------------------------------
async function notifyCaller(rec, { author, role, comment, rating }) {
  let emp = null;
  if (rec.callerId) emp = await Employee.findOne({ id: rec.callerId }).lean();
  if (!emp && rec.callerName) emp = await Employee.findOne({ name: exactNameRegex(rec.callerName) }).lean();
  const starsStr = rating > 0 ? ` (${rating} stars)` : '';
  const client = rec.contactName || rec.phoneNumber || 'a client';
  await Notification.create({
    id: `notif_${Date.now()}_${crypto.randomBytes(3).toString('hex')}`,
    recipientId: emp ? emp.id : (rec.callerId || ''),
    // The caller's own number — never the customer's
    recipientPhone: emp ? (emp.phone || '') : (rec.callerPhone || ''),
    recipientName: emp ? emp.name : (rec.callerName || ''),
    senderName: author,
    senderRole: role,
    recordingId: rec.id,
    contactName: rec.contactName || '',
    title: `Feedback from ${author} (${String(role).toUpperCase()})`,
    message: `${author} reviewed your call with ${client}${starsStr}: "${comment}"`,
    comment,
    rating: rating || 0,
    isRead: false,
  });
}

// Reviewer identity: token (managers only, enforced by ROUTE_RULES); legacy clients must claim a manager role
function reviewerFor(req) {
  if (req.user) return { name: req.user.name || 'Manager', role: req.user.role };
  const role = String((req.body && req.body.commentedByRole) || '').toLowerCase();
  if (!MANAGERS.includes(role)) return null;
  return { name: String(req.body.commentedBy || 'Manager').slice(0, 80), role };
}

async function loadReviewable(req, res) {
  const rec = await Recording.findOne(byIdQuery(req.params.id)).select('-audioData');
  if (!rec) { res.status(404).json({ success: false, message: 'Recording not found' }); return null; }
  if (!(await canAccessRecording(req, rec))) {
    res.status(403).json({ success: false, message: 'This recording is outside your team.' });
    return null;
  }
  return rec;
}

// POST /api/recordings/:id/comment  { rating, comment }
router.post(['/api/recordings/:id/comment', '/api/admin/recordings/:id/comment'], async (req, res) => {
  try {
    const reviewer = reviewerFor(req);
    if (!reviewer) {
      return res.status(403).json({ success: false, message: 'Only Admin and Manager roles may rate and comment on calls.' });
    }
    const rec = await loadReviewable(req, res);
    if (!rec) return undefined;
    const { rating } = req.body || {};
    const comment = typeof req.body.comment === 'string' ? req.body.comment.trim().slice(0, 2000) : '';
    if (rating !== undefined && rating !== null && rating !== '') {
      const r = Number(rating);
      if (!Number.isFinite(r) || r < 0 || r > 5) return res.status(400).json({ success: false, message: 'rating must be 0-5' });
      rec.rating = Math.round(r * 10) / 10;
    }
    if (comment) {
      rec.comment = comment;
      rec.commentedBy = reviewer.name;
      rec.commentedByRole = reviewer.role;
      rec.commentedAt = new Date();
      rec.comments.push({ text: comment, by: reviewer.name, byRole: reviewer.role, at: new Date() });
    }
    await rec.save();
    if (comment || rec.rating > 0) {
      try {
        await notifyCaller(rec, { author: reviewer.name, role: reviewer.role, comment: comment || 'Rated your call', rating: rec.rating });
      } catch (notifErr) {
        console.error('Error creating notification:', notifErr.message);
      }
    }
    res.json({ success: true, message: 'Comment saved successfully', recording: toRecordingDTO(rec.toObject()) });
  } catch (err) {
    serverError(res, err, 'recordings.comment');
  }
});

// POST /api/recordings/:id/review  { criteria?, status?, comment? }  (managers)
router.post(['/api/recordings/:id/review', '/api/admin/recordings/:id/review'], async (req, res) => {
  try {
    const reviewer = reviewerFor(req);
    if (!reviewer) return res.status(403).json({ success: false, message: 'You do not have permission for this action.' });
    const { criteria, status } = req.body || {};
    const comment = typeof req.body.comment === 'string' ? req.body.comment.trim().slice(0, 2000) : '';

    if (status !== undefined && status !== null && !STATUSES.includes(status)) {
      return res.status(400).json({ success: false, message: `status must be one of ${STATUSES.join(', ')}` });
    }
    let cleanCriteria = null;
    if (criteria !== undefined && criteria !== null) {
      if (typeof criteria !== 'object' || Array.isArray(criteria)) {
        return res.status(400).json({ success: false, message: 'criteria must be an object { g, p, o, c, t, s }' });
      }
      cleanCriteria = {};
      for (const k of CRITERIA_KEYS) {
        if (criteria[k] === undefined || criteria[k] === null) continue;
        const v = Number(criteria[k]);
        if (!Number.isFinite(v) || v < 0 || v > 5) {
          return res.status(400).json({ success: false, message: `criteria.${k} must be 0-5` });
        }
        cleanCriteria[k] = Math.round(v);
      }
    }

    const rec = await loadReviewable(req, res);
    if (!rec) return undefined;

    if (cleanCriteria) {
      const merged = {};
      CRITERIA_KEYS.forEach(k => { merged[k] = cleanCriteria[k] !== undefined ? cleanCriteria[k] : Math.round(Number(rec.criteria && rec.criteria[k]) || 0); });
      rec.criteria = merged;
      const scored = CRITERIA_KEYS.map(k => merged[k]).filter(v => v > 0);
      rec.rating = scored.length ? Math.round((scored.reduce((a, b) => a + b, 0) / scored.length) * 10) / 10 : 0;
    }
    if (status) rec.status = status;
    if (comment) {
      rec.comment = comment;
      rec.commentedBy = reviewer.name;
      rec.commentedByRole = reviewer.role;
      rec.commentedAt = new Date();
      rec.comments.push({ text: comment, by: reviewer.name, byRole: reviewer.role, at: new Date() });
    }
    await rec.save();

    if (comment) {
      try {
        await notifyCaller(rec, { author: reviewer.name, role: reviewer.role, comment, rating: rec.rating });
      } catch (notifErr) {
        console.error('Error creating notification:', notifErr.message);
      }
    }
    res.json({ success: true, recording: toRecordingDTO(rec.toObject()) });
  } catch (err) {
    serverError(res, err, 'recordings.review');
  }
});

// ---- DELETE ------------------------------------------------------------------------------------
router.delete(['/api/recordings/:id', '/api/admin/recordings/:id'], async (req, res) => {
  try {
    const rec = await loadReviewable(req, res);
    if (!rec) return undefined;
    await Recording.deleteOne({ _id: rec._id });

    // Remove the audio file (only if no other recording still points at it)
    for (const name of [rec.fileName, rec.audioUrl ? path.basename(rec.audioUrl) : null].filter(Boolean)) {
      const p = diskPath(name);
      if (!p || !fs.existsSync(p)) continue;
      const stillUsed = await Recording.exists({ fileName: path.basename(p) });
      if (!stillUsed) { try { fs.unlinkSync(p); } catch (e) { console.warn('Could not delete audio file:', e.message); } }
    }

    // Unlink the call log(s) that pointed at it
    const urls = [rec.audioUrl, `/api/recordings/${rec.id}/audio`, rec.fileName ? `/uploads/recordings/${rec.fileName}` : null].filter(Boolean);
    await CallLog.updateMany(
      { $or: [{ recordingId: rec.id }, { recordingUrl: { $in: urls } }] },
      { $set: { recordingId: '', recordingUrl: '' } }
    );

    res.json({ success: true, message: 'Recording deleted successfully' });
  } catch (err) {
    serverError(res, err, 'recordings.delete');
  }
});

module.exports = router;
module.exports.toRecordingDTO = toRecordingDTO;
module.exports.deriveType = deriveType;
module.exports.sanitizeOriginalName = sanitizeOriginalName;
