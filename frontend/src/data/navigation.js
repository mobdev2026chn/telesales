// Sidebar pages: one entry per route. `tab` is the short key the refresh logic uses.
export const NAV_ITEMS = [
  { tab: 'dash', path: '/dashboard', label: 'Dashboard' },
  { tab: 'calls', path: '/calls', label: 'Call Log' },
  { tab: 'dial', path: '/lead-calling', label: 'Lead Calling' },
  { tab: 'users', path: '/users', label: 'User Management', guard: 'users' },
  { tab: 'lb', path: '/leaderboard', label: 'Leaderboard' },
  { tab: 'recs', path: '/recordings', label: 'Call Recordings' },
  { tab: 'leads', path: '/leads', label: 'Leads Pipeline' },
  { tab: 'demos', path: '/demos', label: 'Demo Bookings', guard: 'demos' },
];

export const PATHS = {
  dash: '/dashboard',
  calls: '/calls',
  dial: '/lead-calling',
  users: '/users',
  lb: '/leaderboard',
  recs: '/recordings',
  leads: '/leads',
  demos: '/demos',
  notifications: '/notifications',
  profile: '/profile',
  user: '/user',
};

export const TAB_TITLES = {
  dash: 'Dashboard', calls: 'Call Log', dial: 'Lead Calling', users: 'User Management', lb: 'Leaderboard',
  recs: 'Call Recordings', leads: 'Leads Pipeline', demos: 'Demo Bookings', notifications: 'Notifications', profile: 'My Profile', user: 'User Details',
};

export function userPath(id) {
  return `${PATHS.user}/${encodeURIComponent(id)}`;
}

// Route path → tab key
export function tabFromPath(pathname) {
  const p = String(pathname || '');
  if (p.startsWith(`${PATHS.user}/`)) return 'user';
  const hit = Object.entries(PATHS).find(([, path]) => path === p);
  return hit ? hit[0] : 'dash';
}
