import { io } from 'socket.io-client';
import { demoUpserted } from '../redux/slices/demosSlice';
import { employeePresenceChanged as dashboardPresenceChanged } from '../redux/slices/dashboardSlice';
import { leadRemoved, leadUpserted } from '../redux/slices/leadsSlice';
import { recordingUpserted } from '../redux/slices/recordingsSlice';
import { employeePresenceChanged } from '../redux/slices/usersSlice';
import { employeePresenceChanged as userDetailPresenceChanged } from '../redux/slices/userDetailSlice';
import store from '../redux/store';
import { mapDemo, mapLead, mapRecording } from './mappers';
import { syncWithBackend } from './actions/syncActions';
import { fetchDashboard } from './actions/statsActions';

let socket = null;
let activeToken = '';

function socketUrl() {
  const configured = import.meta.env.VITE_SOCKET_URL;
  if (configured) return configured.replace(/\/+$/, '');
  const apiBase = import.meta.env.VITE_API_BASE || '';
  if (/^https?:\/\//i.test(apiBase)) return new URL(apiBase).origin;
  return window.location.origin;
}

function handleDemo(payload) {
  if (!payload || !payload.demo) return;
  const demo = mapDemo(payload.demo);
  if (demo.id) store.dispatch(demoUpserted(demo));
}

function handleLead(payload) {
  const lead = payload && (payload.lead || payload);
  const mapped = mapLead(lead || {});
  if (mapped.id) store.dispatch(leadUpserted(mapped));
  fetchDashboard();
}

function handlePresence(payload, online) {
  if (!payload || !payload.userId) return;
  const presence = {
    id: String(payload.userId),
    online,
    ...(payload.lastLoginAt !== undefined ? { lastLoginAt: payload.lastLoginAt } : {}),
    ...(payload.loggedOutAt !== undefined ? { loggedOutAt: payload.loggedOutAt } : {}),
  };
  store.dispatch(employeePresenceChanged(presence));
  store.dispatch(dashboardPresenceChanged(presence));
  store.dispatch(userDetailPresenceChanged(presence));
}

function syncWhenIdle(client, attempts = 0) {
  if (socket !== client || !client.connected) return;
  if (store.getState().ui.syncing) {
    if (attempts >= 120) {
      console.error('[socket] REST resync deferred because another sync did not finish');
      return;
    }
    window.setTimeout(() => syncWhenIdle(client, attempts + 1), 300);
    return;
  }
  syncWithBackend({ background: true });
}

function registerEvents(client) {
  client.on('demoCreated', handleDemo);
  client.on('demoUpdated', handleDemo);
  client.on('leadCreated', handleLead);
  client.on('leadUpdated', handleLead);
  client.on('leadDeleted', (payload) => {
    if (payload && (payload.id || payload.leadId)) {
      store.dispatch(leadRemoved(String(payload.id || payload.leadId)));
      fetchDashboard();
    }
  });
  client.on('callStatusUpdated', (payload) => {
    if (payload && payload.lead) {
      const mapped = mapLead(payload.lead);
      if (mapped.id) store.dispatch(leadUpserted(mapped));
    }
    else if (payload && payload.leadId) {
      const state = store.getState();
      const current = state.leads.list.find((lead) => lead.id === String(payload.leadId));
      if (current) store.dispatch(leadUpserted({ ...current, status: payload.status }));
      fetchDashboard();
    }
  });
  client.on('employeeOnline', (payload) => handlePresence(payload, true));
  client.on('employeeOffline', (payload) => handlePresence(payload, false));
  client.on('dashboardUpdated', () => {
    syncWhenIdle(client);
  });
  client.on('recordingUploaded', (payload) => {
    if (!payload || !payload.recording) return;
    const recording = mapRecording(payload.recording);
    if (recording.id) store.dispatch(recordingUpserted(recording));
  });
}

export function connectRealtime(token) {
  if (!token) return null;
  if (socket && activeToken === token) return socket;
  disconnectRealtime();

  activeToken = token;
  socket = io(socketUrl(), {
    path: '/socket.io',
    auth: { token },
    reconnection: true,
    reconnectionDelay: 1000,
    reconnectionDelayMax: 10000,
  });
  registerEvents(socket);

  let connectedBefore = false;
  socket.on('connect', () => {
    if (connectedBefore) syncWhenIdle(socket);
    connectedBefore = true;
  });
  socket.on('connect_error', (err) => {
    console.error(`[socket] connection failed: ${err.message}`);
  });
  return socket;
}

export function disconnectRealtime() {
  if (socket) {
    socket.removeAllListeners();
    socket.disconnect();
    socket = null;
  }
  activeToken = '';
}
