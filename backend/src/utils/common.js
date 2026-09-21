// Small shared helpers used by every route. Pure functions only (no DB access).

// Escapes a user-supplied string so it can be embedded in a RegExp literally.
const escapeRegex = (s) => String(s === undefined || s === null ? '' : s).replace(/[.*+?^${}()|[\]\\]/g, '\\$&');

// Last 10 digits of a phone number ('' when there are no digits).
const last10 = (phone) => String(phone === undefined || phone === null ? '' : phone).replace(/[^0-9]/g, '').slice(-10);

const isObjectId = (v) => typeof v === 'string' && /^[0-9a-fA-F]{24}$/.test(v);

// Matches a document by its string `id` field, or by `_id` when the value is a valid ObjectId
// (casting a non-ObjectId to _id throws a CastError, which used to surface as a 500).
function byIdQuery(id) {
  const value = String(id === undefined || id === null ? '' : id);
  return { $or: [{ id: value }, ...(isObjectId(value) ? [{ _id: value }] : [])] };
}

// Case-insensitive exact match of a name.
const exactNameRegex = (name) => new RegExp(`^${escapeRegex(String(name).trim())}$`, 'i');

// Matches any stored formatting of the given 10 digits at the end of the value
// ('+91 98250 12345', '9825012345', '098250-12345' ...).
function digitsPattern(digits) {
  return String(digits).replace(/[^0-9]/g, '').split('').join('[^0-9]*');
}
function phoneRegex(phone) {
  const d = last10(phone);
  if (d.length < 8) return null;
  return new RegExp(`${digitsPattern(d)}$`);
}
// One regex for many numbers (null when the list is empty).
function anyPhoneRegex(phones) {
  const list = [...new Set((phones || []).map(last10).filter(d => d.length >= 8))];
  if (list.length === 0) return null;
  return new RegExp(`(?:${list.map(digitsPattern).join('|')})$`);
}

// Logs the real error server-side and sends a generic message to the client.
function serverError(res, err, context = 'request') {
  console.error(`[${context}]`, err && err.stack ? err.stack : err);
  if (res.headersSent) return undefined;
  return res.status(500).json({ success: false, message: 'Something went wrong. Please try again.' });
}

const toInt = (v, def = 0) => {
  const n = Math.round(Number(v));
  return Number.isFinite(n) ? n : def;
};

// Parses paging params: limit in [1, max] (default def).
function parseLimit(value, def, max) {
  const n = parseInt(value, 10);
  if (!Number.isFinite(n) || n <= 0) return def;
  return Math.min(n, max);
}

function parseDate(value) {
  if (value === undefined || value === null || value === '') return null;
  const d = typeof value === 'number' || /^\d+$/.test(String(value)) ? new Date(Number(value)) : new Date(String(value));
  return isNaN(d.getTime()) ? null : d;
}

// A call time sent by a phone. Older app builds send the phone's local (India) wall-clock time
// without a zone, e.g. "2026-09-19T12:22:00.000". The server runs in UTC and would read that as
// 12:22 UTC = 5:52 PM India time, so a zone-less value is read as India time (+05:30).
function parseDeviceTime(value) {
  if (value === undefined || value === null || value === '') return null;
  if (typeof value === 'number' || /^\d+$/.test(String(value))) return parseDate(value);
  const s = String(value).trim();
  const hasZone = /(Z|[+-]\d{2}:?\d{2})$/i.test(s);
  const isDateTime = /^\d{4}-\d{2}-\d{2}[T ]\d{2}:\d{2}/.test(s);
  return parseDate(isDateTime && !hasZone ? `${s.replace(' ', 'T')}+05:30` : s);
}

module.exports = {
  parseDeviceTime,
  escapeRegex,
  last10,
  isObjectId,
  byIdQuery,
  exactNameRegex,
  phoneRegex,
  anyPhoneRegex,
  serverError,
  toInt,
  parseLimit,
  parseDate,
};
