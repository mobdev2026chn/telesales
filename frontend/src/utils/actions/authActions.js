// LOGIN · SESSION: checks the saved token, signs in / out, handles an expired session
import { PORTAL_ROLES } from '../../data/constants';
import { resetSession } from '../../redux/actions';
import { loginShown, signedIn } from '../../redux/slices/authSlice';
import store from '../../redux/store';
import {
  ApiError, clearMediaToken, clearSession, getToken, setMediaToken, setMediaTokenNeededHandler, setSession, setSessionExpiredHandler,
} from '../api';
import { stopAllAudio } from '../audioController';
import { notify } from '../notify';
import { authService } from '../services';

const { dispatch, getState } = store;

// ---- Short-lived recording links (recordingAudioUrl in utils/api.js) ----
// Fetched when a session starts, renewed at 75% of its life, cleared on sign-out. Any failure is
// silent: links then carry the login token as before.
const MEDIA_RETRY_MS = 5 * 60 * 1000;
const media = { timer: null, inFlight: false, gen: 0, retryAt: 0, unsupported: false };

function scheduleMediaToken(ms) {
  clearTimeout(media.timer);
  media.timer = setTimeout(() => { media.timer = null; refreshMediaToken(); }, ms);
}

async function refreshMediaToken() {
  if (media.inFlight || media.unsupported || !getToken()) return;
  const gen = media.gen;
  media.inFlight = true;
  try {
    const json = await authService.mediaToken();
    if (gen !== media.gen) return;   // signed out meanwhile
    const secs = Number(json && json.expiresInSeconds);
    if (!json || typeof json.token !== 'string' || !json.token || !(secs > 0)) {
      media.unsupported = true;      // a server that does not hand out media tokens
      clearMediaToken();
      return;
    }
    setMediaToken(json.token, secs);
    scheduleMediaToken(Math.max(60, secs * 0.75) * 1000);
  } catch (err) {
    if (gen !== media.gen) return;
    if (err.status === 404) { media.unsupported = true; return; }   // older server: keep ?token= links
    media.retryAt = Date.now() + MEDIA_RETRY_MS;
    scheduleMediaToken(MEDIA_RETRY_MS);
  } finally {
    if (gen === media.gen) media.inFlight = false;
  }
}

function startMediaToken() {
  stopMediaToken();
  refreshMediaToken();
}

function stopMediaToken() {
  media.gen += 1;
  clearTimeout(media.timer);
  Object.assign(media, { timer: null, inFlight: false, retryAt: 0, unsupported: false });
  clearMediaToken();
}

// A link was built without a fresh media token (e.g. the computer slept past the renewal): fetch one
// in the background for the next link — only while signed in, and not again until the retry time
setMediaTokenNeededHandler(() => {
  if (getState().auth.status !== 'signedIn' || Date.now() < media.retryAt) return;
  setTimeout(refreshMediaToken, 0);
});

// On load: a saved token is checked against /auth/me before the portal opens
export async function checkSession() {
  if (!getToken()) {
    dispatch(loginShown());
    return;
  }
  try {
    const json = await authService.me();
    const user = json.user;
    const role = String((user && user.role) || '').toLowerCase();
    if (!user || !PORTAL_ROLES.includes(role)) {
      clearSession();
      dispatch(loginShown('This portal is for admins, managers and team leaders only.'));
      return;
    }
    setSession(getToken(), user);
    dispatch(signedIn(user));
    startMediaToken();
  } catch (e) {
    if (e.status === 401 || e.status === 403) {
      clearSession();
      dispatch(loginShown('Your session has expired — please sign in again.'));
    } else {
      dispatch(loginShown(`Could not verify your session: ${e.message}`));
    }
  }
}

// Resolves to { ok: true } or { error: 'message' }
export async function login(identifier, password) {
  try {
    const json = await authService.adminLogin(identifier, password);
    if (!json.success || !json.token || !json.user) throw new ApiError(json.message || 'Login failed', 0, json);
    setSession(json.token, json.user);
    dispatch(signedIn(json.user));
    startMediaToken();
    return { ok: true };
  } catch (err) {
    return {
      error: err.network
        ? 'Unable to reach the server. Check your connection and try again.'
        : (err.message || 'Invalid credentials'),
    };
  }
}

export async function logout() {
  let logoutError = null;
  try {
    await authService.logout();
  } catch (err) {
    logoutError = err;
  }
  clearSession();
  stopMediaToken();
  stopAllAudio();
  dispatch(resetSession());
  dispatch(loginShown());
  notify(logoutError
    ? `LOGGED OUT LOCALLY; SERVER LOGOUT TIME COULD NOT BE SAVED — ${logoutError.message}`
    : 'LOGGED OUT');
}

// Any API call answered 401: back to the sign-in screen with the reason
export function expireSession(message) {
  const { authUser, status } = getState().auth;
  clearSession();
  stopMediaToken();
  if (!authUser && status !== 'signedIn') return;
  stopAllAudio();
  dispatch(resetSession());
  dispatch(loginShown(message));
}

setSessionExpiredHandler(expireSession);
