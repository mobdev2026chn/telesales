// LOGIN · SESSION: checks the saved token, signs in / out, handles an expired session
import { PORTAL_ROLES } from '../../data/constants';
import { resetSession } from '../../redux/actions';
import { loginShown, signedIn } from '../../redux/slices/authSlice';
import store from '../../redux/store';
import { ApiError, clearSession, getToken, setSession, setSessionExpiredHandler } from '../api';
import { stopAllAudio } from '../audioController';
import { notify } from '../notify';
import { authService } from '../services';

const { dispatch, getState } = store;

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
  if (!authUser && status !== 'signedIn') return;
  stopAllAudio();
  dispatch(resetSession());
  dispatch(loginShown(message));
}

setSessionExpiredHandler(expireSession);
