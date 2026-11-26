// ==========================================
// SMALL HELPERS · FORMATTING (India time: the server computes "today" / periods in Asia/Kolkata)
// ==========================================

export function last10(p) {
  const d = String(p || '').replace(/\D/g, '');
  return d.length >= 10 ? d.slice(-10) : '';
}

export function domKey(id) {
  return String(id || '').replace(/[^A-Za-z0-9_-]/g, '_');
}

// Only base64 images and https URLs are ever used as a picture
export function safeImage(s) {
  if (typeof s !== 'string') return '';
  const clean = s.replace(/\s/g, '');
  if (/^data:image\/(png|jpe?g|gif|webp);base64,[A-Za-z0-9+/=]+$/i.test(clean)) return clean;
  try {
    const url = new URL(clean);
    return url.protocol === 'https:' ? url.href : '';
  } catch {
    return '';
  }
}

export function initialOf(name) {
  return String(name || '?').trim().charAt(0).toUpperCase() || '?';
}

export function roleLabel(r) { return String(r || '').replace('_', ' '); }

export function formatPhone(p) {
  if (!p) return '—';
  const ten = last10(p);
  if (ten) return `+91 ${ten.slice(0, 5)} ${ten.slice(5)}`;
  return String(p);
}

export function fmtDur(s) {
  s = Math.round(Number(s) || 0);
  if (s <= 0) return '0s';
  const m = Math.floor(s / 60);
  const sec = s % 60;
  return m > 0 ? `${m}m ${String(sec).padStart(2, '0')}s` : `${sec}s`;
}

export function fmtTalk(s) {
  s = Math.round(Number(s) || 0);
  if (s <= 0) return '0h 00m';
  const h = Math.floor(s / 3600);
  const m = Math.floor((s % 3600) / 60);
  return `${h}h ${String(m).padStart(2, '0')}m`;
}

// Player clock: m:ss (e.g. 0:00, 1:28, 12:05)
export function fmtClock(s) {
  s = Math.max(0, Math.floor(Number(s) || 0));
  return `${Math.floor(s / 60)}:${String(s % 60).padStart(2, '0')}`;
}

export function istDateStr(d) {
  return new Intl.DateTimeFormat('en-CA', { timeZone: 'Asia/Kolkata', year: 'numeric', month: '2-digit', day: '2-digit' }).format(d);
}
export function istMidnight(dateStr) { return new Date(`${dateStr}T00:00:00+05:30`); }
export function istDaysAgoStr(n) {
  const [y, m, d] = istDateStr(new Date()).split('-').map(Number);
  return new Date(Date.UTC(y, m - 1, d - n)).toISOString().slice(0, 10);
}
export function fmtIstFull(d) {
  if (!d || isNaN(d.getTime())) return '';
  return new Intl.DateTimeFormat('en-IN', { timeZone: 'Asia/Kolkata', year: 'numeric', month: '2-digit', day: '2-digit', hour: '2-digit', minute: '2-digit', hour12: false }).format(d);
}

export function fmtTs(d) {
  if (!d) return '—';
  const dateObj = (d instanceof Date) ? d : new Date(d);
  if (isNaN(dateObj.getTime())) return '—';
  const dayFmt = new Intl.DateTimeFormat('en-IN', { timeZone: 'Asia/Kolkata', day: 'numeric', month: 'short' });
  const timeStr = new Intl.DateTimeFormat('en-IN', { timeZone: 'Asia/Kolkata', hour: 'numeric', minute: '2-digit', hour12: true }).format(dateObj).toUpperCase();
  const isToday = istDateStr(dateObj) === istDateStr(new Date());
  return `${isToday ? 'TODAY' : dayFmt.format(dateObj).toUpperCase()} · ${timeStr}`;
}

export function fmtTime12(d) {
  return new Intl.DateTimeFormat('en-IN', { timeZone: 'Asia/Kolkata', hour: 'numeric', minute: '2-digit', hour12: true }).format(d);
}

export function fmtLongDay(d) {
  return new Intl.DateTimeFormat('en-IN', { timeZone: 'Asia/Kolkata', weekday: 'short', day: 'numeric', month: 'short', year: 'numeric' }).format(d);
}

// Valid YYYY-MM-DD between 2020 and 2030 (parsed from the string, not through UTC Date)
export function validPickerDate(val) {
  const m = /^(\d{4})-(\d{2})-(\d{2})$/.exec(val || '');
  if (!m) return false;
  const y = Number(m[1]);
  return y >= 2020 && y <= 2030;
}

export function plural(n, word, many = `${word}S`) {
  return n === 1 ? word : many;
}

// How long ago: "just now" / "5 min ago" / "3 h ago" / "2 days ago" ('' for a missing or bad date)
export function timeAgo(d) {
  if (!d) return '';
  const t = (d instanceof Date ? d : new Date(d)).getTime();
  if (Number.isNaN(t)) return '';
  const min = Math.floor(Math.max(0, Date.now() - t) / 60000);
  if (min < 1) return 'just now';
  if (min < 60) return `${min} min ago`;
  const h = Math.floor(min / 60);
  if (h < 48) return `${h} h ago`;
  return `${Math.floor(h / 24)} days ago`;
}
