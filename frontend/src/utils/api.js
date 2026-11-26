// ==========================================
// CONFIG · SESSION · API
// ==========================================
import { TOKEN_KEY, USER_KEY } from '../data/constants';
import ENDPOINTS from '../data/endpoints';

// /api goes through the Vite proxy in development (see vite.config.js); set VITE_API_BASE for a
// build hosted away from the backend. VITE_API_FALLBACK is tried when the first base is unreachable.
export const API_BASE = (import.meta.env.VITE_API_BASE || '/api').replace(/\/+$/, '');
const FALLBACK_API_BASE = (import.meta.env.VITE_API_FALLBACK || '').replace(/\/+$/, '') || null;

export function getToken() {
  try { return localStorage.getItem(TOKEN_KEY) || ''; } catch { return ''; }
}
export function setSession(token, user) {
  try {
    localStorage.setItem(TOKEN_KEY, token);
    localStorage.setItem(USER_KEY, JSON.stringify(user || {}));
  } catch { /* storage blocked */ }
}
export function clearSession() {
  try {
    localStorage.removeItem(TOKEN_KEY);
    localStorage.removeItem(USER_KEY);
  } catch { /* storage blocked */ }
}

export class ApiError extends Error {
  constructor(message, status, body, network) {
    super(message);
    this.status = status;
    this.body = body;
    this.network = !!network;
  }
}

// The store registers what happens when the server says the session is gone (back to sign-in)
let onSessionExpired = null;
export function setSessionExpiredHandler(fn) { onSessionExpired = fn; }

// Single entry point for every API call: base URL, auth JSON in/out, and session expiry.
export async function apiFetch(path, opts = {}) {
  const headers = Object.assign({ Accept: 'application/json' }, opts.headers || {});
  const token = getToken();
  if (token && !opts.noAuth) headers.Authorization = `Bearer ${token}`;
  let body = opts.body;
  if (body !== undefined && body !== null && typeof body !== 'string') {
    headers['Content-Type'] = 'application/json';
    body = JSON.stringify(body);
  }

  const bases = [API_BASE];
  if (FALLBACK_API_BASE && !bases.includes(FALLBACK_API_BASE)) bases.push(FALLBACK_API_BASE);

  for (const base of bases) {
    let res;
    try {
      res = await fetch(`${base}${path}`, { method: opts.method || 'GET', headers, body });
    } catch {
      continue;
    }

    let json = null;
    try { json = await res.json(); } catch { json = null; }
    // noSessionExpiry: a 401 is just an error for this call and never signs the user out (media token)
    if (res.status === 401 && !opts.noAuth && !opts.noSessionExpiry && (!json || json.code === 'AUTH_REQUIRED')) {
      if (onSessionExpired) onSessionExpired('Your session has expired — please sign in again.');
      throw new ApiError('Session expired', 401, json);
    }
    if (!res.ok || (json && json.success === false)) {
      const msg = (json && (json.message || json.error)) || `Request failed (HTTP ${res.status})`;
      throw new ApiError(msg, res.status, json);
    }
    return json || {};
  }

  throw new ApiError('Could not reach the server — check your connection.', 0, null, true);
}

// ---- Short-lived recording links ----
// GET /auth/media-token gives a token (about 2 hours) that only plays recording audio, so a copied
// audio link no longer carries the 30-day login. Kept in memory only: authActions fetches it when a
// session starts, renews it before it runs out and clears it on sign-out.
const MEDIA_TOKEN_SLACK_MS = 2 * 60 * 1000;   // stop handing out a media token 2 minutes before it expires
let mediaToken = null;                        // { token, expiresAt }
let onMediaTokenNeeded = null;

export function setMediaToken(token, expiresInSeconds) {
  const secs = Number(expiresInSeconds);
  mediaToken = token && typeof token === 'string' && secs > 0 ? { token, expiresAt: Date.now() + secs * 1000 } : null;
}
export function clearMediaToken() { mediaToken = null; }
// authActions registers what to do when a link is built without a fresh media token (fetch one)
export function setMediaTokenNeededHandler(fn) { onMediaTokenNeeded = fn; }

function freshMediaToken() {
  return mediaToken && Date.now() < mediaToken.expiresAt - MEDIA_TOKEN_SLACK_MS ? mediaToken.token : '';
}

// <audio> cannot send headers, so a token rides in the query string: the short-lived media token
// (?mt=) when a fresh one is cached, otherwise the login token (?token=) — an older server, or the
// media token could not be fetched — so playback never breaks
export function recordingAudioUrl(id) {
  const url = `${API_BASE}${ENDPOINTS.recordingAudio(id)}`;
  const mt = freshMediaToken();
  if (mt) return `${url}?mt=${encodeURIComponent(mt)}`;
  if (onMediaTokenNeeded) onMediaTokenNeeded();
  return `${url}?token=${encodeURIComponent(getToken())}`;
}

// A recording link built earlier whose token is no longer the one to use (the media token was renewed
// or ran out, or the link still carries the login token while a media token is now available) →
// the same recording's link built again; null when the link is still good or is not a recording link
export function renewAudioUrl(url) {
  const m = /\/recordings\/([^/?#]+)\/audio\?(?:[^#]*&)?(mt|token)=([^&#]*)/.exec(String(url || ''));
  if (!m) return null;
  let id;
  let value;
  try { id = decodeURIComponent(m[1]); value = decodeURIComponent(m[3]); } catch { return null; }
  const mt = freshMediaToken();
  if (m[2] === 'mt' ? value === mt : !mt) return null;
  return recordingAudioUrl(id);
}
