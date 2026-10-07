// Every backend route the portal calls (relative to the API base, e.g. /api).
// The paths are exactly the ones admin_web/index.html uses — the backend is unchanged.
const enc = encodeURIComponent;

export const ENDPOINTS = {
  // Auth
  me: '/auth/me',
  adminLogin: '/auth/admin-login',

  // Users
  users: '/admin/users',
  user: (id) => `/admin/users/${enc(id)}`,
  userPhoto: '/users/photo',

  // Numbers
  dashboard: (qs) => `/admin/dashboard${qs}`,
  leaderboard: (qs) => `/admin/leaderboard${qs}`,

  // Calls
  calls: (qs) => `/admin/calls${qs}`,

  // Leads
  leads: (qs = '') => `/admin/leads${qs}`,
  lead: (id) => `/admin/leads/${enc(id)}`,
  leadsImport: '/admin/leads/import',
  leadsDistribute: '/admin/leads/distribute',
  leadsBatch: (name) => `/admin/leads/batch/${enc(name)}`,

  // Recordings
  recordings: (qs) => `/admin/recordings${qs}`,
  recordingAudio: (id) => `/recordings/${enc(id)}/audio`,
  recordingReview: (id) => `/recordings/${enc(id)}/review`,
  recordingPin: (id) => `/recordings/${enc(id)}/pin`,

  // Demo bookings
  demos: (qs) => `/admin/demos${qs}`,
  demoBlocks: (qs = '') => `/demos/blocks${qs}`,
  demoBlock: (id) => `/demos/blocks/${enc(id)}`,
  demoCancel: (id) => `/demos/${enc(id)}/cancel`,
  demoReschedule: (id) => `/demos/${enc(id)}/reschedule`,
};

export default ENDPOINTS;
