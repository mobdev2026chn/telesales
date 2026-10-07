// One function per backend call. utils/actions use these; nothing else talks to the API.
import ENDPOINTS from '../data/endpoints';
import { apiFetch } from './api';

const q = encodeURIComponent;

export const authService = {
  me: () => apiFetch(ENDPOINTS.me),
  adminLogin: (identifier, password) => apiFetch(ENDPOINTS.adminLogin, {
    method: 'POST',
    noAuth: true,
    body: { identifier, email: identifier, password },
  }),
};

export const userService = {
  list: () => apiFetch(ENDPOINTS.users),
  create: (payload) => apiFetch(ENDPOINTS.users, { method: 'POST', body: payload }),
  update: (id, payload) => apiFetch(ENDPOINTS.user(id), { method: 'PUT', body: payload }),
  remove: (id) => apiFetch(ENDPOINTS.user(id), { method: 'DELETE' }),
  uploadPhoto: (body) => apiFetch(ENDPOINTS.userPhoto, { method: 'POST', body }),
};

export const statsService = {
  // qs: "?period=today&callerIds=…" / "?date=2026-01-01"
  dashboard: (qs) => apiFetch(ENDPOINTS.dashboard(qs)),
  leaderboard: (qs) => apiFetch(ENDPOINTS.leaderboard(qs)),
};

export const callService = {
  list: (qs) => apiFetch(ENDPOINTS.calls(qs)),
  range: ({ from, to, limit, extra = '' }) =>
    apiFetch(ENDPOINTS.calls(`?from=${q(from.toISOString())}&to=${q(to.toISOString())}&limit=${limit}${extra}`)),
};

export const leadService = {
  page: (limit, page) => apiFetch(ENDPOINTS.leads(`?limit=${limit}&page=${page}`)),
  create: (body) => apiFetch(ENDPOINTS.leads(), { method: 'POST', body }),
  update: (id, body) => apiFetch(ENDPOINTS.lead(id), { method: 'PUT', body }),
  import: (body) => apiFetch(ENDPOINTS.leadsImport, { method: 'POST', body }),
  distribute: (batchName, allocations) => apiFetch(ENDPOINTS.leadsDistribute, { method: 'POST', body: { batchName, allocations } }),
  removeBatch: (name) => apiFetch(ENDPOINTS.leadsBatch(name), { method: 'DELETE' }),
};

export const recordingService = {
  list: (qs) => apiFetch(ENDPOINTS.recordings(qs)),
  review: (id, body) => apiFetch(ENDPOINTS.recordingReview(id), { method: 'POST', body }),
  pin: (id, pinned) => apiFetch(ENDPOINTS.recordingPin(id), { method: 'POST', body: { pinned } }),
};

export const demoService = {
  list: (extra = '') => apiFetch(ENDPOINTS.demos(`?limit=5000${extra}`)),
  blocks: (since) => apiFetch(ENDPOINTS.demoBlocks(`?from=${q(since)}`)),
  block: (body) => apiFetch(ENDPOINTS.demoBlocks(), { method: 'POST', body }),
  unblock: (id) => apiFetch(ENDPOINTS.demoBlock(id), { method: 'DELETE' }),
  cancel: (id) => apiFetch(ENDPOINTS.demoCancel(id), { method: 'POST', body: {} }),
  reschedule: (id) => apiFetch(ENDPOINTS.demoReschedule(id), { method: 'POST', body: {} }),
};
