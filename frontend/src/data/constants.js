// ==========================================
// APP-WIDE CONSTANTS (same values as admin_web/index.html)
// ==========================================
export const TOKEN_KEY = 'askeva_admin_token';
export const USER_KEY = 'askeva_admin_user';
export const REFRESH_MS = 60 * 1000;
export const DASH_LIVE_MS = 20 * 1000;
export const DEFAULT_DAILY_TARGET = 250;   // same default as the server
export const TOAST_MS = 3200;

// Roles allowed into the portal (lower case, as the server sends them)
export const PORTAL_ROLES = ['admin', 'manager', 'jr_manager', 'team_leader'];
export const MANAGER_ROLES = ['MANAGER', 'JR_MANAGER', 'TEAM_LEADER'];
export const HEAD_ROLES = ['ADMIN', 'MANAGER', 'JR_MANAGER', 'TEAM_LEADER'];
export const DIALABLE_ROLES = ['CALLER', 'JR_MANAGER', 'TEAM_LEADER'];

// Hierarchy: SUPER ADMIN → MANAGER → JR MANAGER → TEAM LEADER → CALLER
export const ROLE_RANK = { ADMIN: 0, MANAGER: 1, JR_MANAGER: 2, TEAM_LEADER: 3, CALLER: 4 };
export const ROLE_BADGE_CLASS = {
  ADMIN: 'role-badge-admin',
  MANAGER: 'role-badge-manager',
  JR_MANAGER: 'role-badge-jrmanager',
  TEAM_LEADER: 'role-badge-teamleader',
  CALLER: 'role-badge-caller',
};
export const MGR_FILTER_PLURAL = { MANAGER: 'MANAGERS', JR_MANAGER: 'JR MANAGERS', TEAM_LEADER: 'TEAM LEADERS', CALLER: 'CALLERS' };

// User form role choices
export const ROLE_OPTIONS = [
  { value: 'CALLER', label: 'CALLER' },
  { value: 'TEAM_LEADER', label: 'TEAM LEADER' },
  { value: 'JR_MANAGER', label: 'JUNIOR MANAGER' },
  { value: 'MANAGER', label: 'MANAGER' },
  { value: 'ADMIN', label: 'ADMIN' },
];

// Dashboard / leaderboard / funnel / user details period chips
export const PERIOD_OPTIONS = [
  { value: 'today', label: 'Today' },
  { value: 'week', label: 'Week' },
  { value: 'month', label: 'Month' },
];
export const PERIOD_LABEL = { today: 'TODAY', week: 'THIS WEEK', month: 'THIS MONTH' };

// Call Log / Call Recordings date ranges (days back from today, India time)
export const CALL_RANGE_DAYS = { today: 0, '7d': 6, '30d': 29, '90d': 89 };
export const CALL_RANGE_OPTIONS = [
  { value: 'today', label: 'Today' },
  { value: '7d', label: 'Last 7 days' },
  { value: '30d', label: 'Last 30 days' },
  { value: '90d', label: 'Last 90 days' },
];
export const CALL_RANGE_LABEL = { today: 'TODAY', '7d': 'LAST 7 DAYS', '30d': 'LAST 30 DAYS', '90d': 'LAST 90 DAYS' };

export const CALL_DIR_FILTERS = [
  { value: 'ALL', label: 'All calls' },
  { value: 'IN', label: 'Inbound' },
  { value: 'OUT', label: 'Outbound' },
  { value: 'MISSED', label: 'Missed' },
  { value: 'NO ANSWER', label: 'No answer' },
];
export const CALL_PAGE_SIZE = 8;
export const CALLS_FETCH_LIMIT = 1000;

// ==========================================
// LEADS
// ==========================================
export const STAGE_CLASS = {
  'NEW': 'stage-new', 'INTERESTED': 'stage-interested', 'FOLLOW-UP': 'stage-follow-up',
  'CONVERTED': 'stage-converted', 'NOT INTERESTED': 'stage-not-interested',
};
export const STAGE_TITLE = {
  'NEW': 'New', 'INTERESTED': 'Interested', 'FOLLOW-UP': 'Follow-up', 'CONVERTED': 'Converted', 'NOT INTERESTED': 'Not interested',
};
export const STATUS_TO_STAGE = {
  new: 'NEW', interested: 'INTERESTED',
  followUp: 'FOLLOW-UP', bookDemo: 'FOLLOW-UP', demoReschedule: 'FOLLOW-UP', newFollowUp: 'FOLLOW-UP', renewalFollowUp: 'FOLLOW-UP',
  demoDone: 'CONVERTED', won: 'CONVERTED',
  notInterested: 'NOT INTERESTED', lost: 'NOT INTERESTED',
};
export const STAGE_TO_STATUS = { 'NEW': 'new', 'INTERESTED': 'interested', 'FOLLOW-UP': 'followUp', 'CONVERTED': 'won', 'NOT INTERESTED': 'notInterested' };
export const STATUS_LABEL = {
  new: 'NEW', interested: 'INTERESTED', followUp: 'FOLLOW-UP', bookDemo: 'BOOK DEMO', demoReschedule: 'DEMO RESCHEDULE',
  demoDone: 'DEMO DONE', newFollowUp: 'NEW FOLLOW-UP', notPickup: 'NO ANSWER', busyOnCall: 'BUSY', renewalFollowUp: 'RENEWAL FOLLOW-UP',
  interestedLater: 'INTERESTED', warned: 'WARNED', lost: 'LOST', won: 'CONVERTED', notInterested: 'NOT INTERESTED', other: 'OTHER',
};
export const DIAL_OUTCOME_TO_STATUS = {
  'INTERESTED': 'interested', 'FOLLOW-UP': 'followUp', 'CONVERTED': 'won',
  'NO ANSWER': 'notPickup', 'NOT INTERESTED': 'notInterested', 'WRONG NUMBER': 'lost',
};
export const DIAL_OUTCOMES = [
  { value: 'INTERESTED', label: 'Interested' },
  { value: 'FOLLOW-UP', label: 'Follow-up' },
  { value: 'CONVERTED', label: 'Converted' },
  { value: 'NO ANSWER', label: 'No answer' },
  { value: 'NOT INTERESTED', label: 'Not interested' },
  { value: 'WRONG NUMBER', label: 'Wrong number' },
];
export const PIPELINE_STAGES = ['NEW', 'INTERESTED', 'FOLLOW-UP', 'CONVERTED', 'NOT INTERESTED'];
// Stage chips on the Leads Pipeline (value = column id)
export const PIPELINE_STAGE_FILTERS = [
  { value: 'ALL', label: 'All stages' },
  { value: 'NEW', label: 'New' },
  { value: 'INTERESTED', label: 'Interested' },
  { value: 'FOLLOW_UP', label: 'Follow-up' },
  { value: 'CONVERTED', label: 'Converted' },
  { value: 'NOT_INTERESTED', label: 'Not interested' },
];
export const PIPELINE_PAGE_SIZE = 10;
export const LEADS_FETCH_LIMIT = 500;
export const LEADS_MAX_PAGES = 20;

// Lead statuses that mean the person was reached / showed interest (conversion funnel)
export const LEAD_REACHED_STATUSES = new Set(['interested', 'followUp', 'bookDemo', 'demoReschedule', 'demoDone', 'newFollowUp', 'renewalFollowUp', 'warned', 'won', 'notInterested']);
export const LEAD_INTEREST_STATUSES = new Set(['interested', 'followUp', 'bookDemo', 'demoReschedule', 'demoDone', 'newFollowUp', 'renewalFollowUp', 'won']);
// Callbacks: follow-up leads that have been called before; overdue once the last call is over a day old
export const CALLBACK_OVERDUE_MS = 24 * 60 * 60 * 1000;

export const LEAD_QUEUE_FILTERS = [
  { value: 'ALL', label: 'All' },
  { value: 'FRESH', label: 'Fresh' },
  { value: 'CALLED', label: 'Called' },
];
export const LEAD_QUEUE_PAGE_SIZE = 10;
// "AUTO · ROUND-ROBIN" in ASSIGN TO: rows are dealt to the dialable callers in turn
export const ROUND_ROBIN = 'auto';

// ==========================================
// RECORDINGS
// ==========================================
export const REC_FETCH_LIMIT = 200;
export const REC_PAGE_SIZE = 20;
// Recordings of 1 second or less are missed / cut-off calls with nothing to hear: never listed
export const MIN_RECORDING_SECONDS = 1;
export const CRIT = [
  ['g', 'Greeting / opening'],
  ['p', 'Product pitch'],
  ['o', 'Objection handling'],
  ['c', 'Closing / next step'],
  ['t', 'Politeness & tone'],
  ['s', 'Script followed'],
];
export const REC_FILTERS = [
  { value: 'ALL', label: 'All' },
  { value: 'PENDING', label: 'Pending' },
  { value: 'APPROVED', label: 'Approved' },
  { value: 'FLAGGED', label: 'Flagged' },
  { value: 'IN', label: 'Inbound' },
  { value: 'OUT', label: 'Outbound' },
  { value: '5+', label: 'Over 5 min' },
  { value: '-5', label: 'Under 5 min' },
];
export const REC_SAVE_DEBOUNCE_MS = 700;

// ==========================================
// USERS · DETAILS
// ==========================================
export const DASH_TEAM_PAGE_SIZE = 10;
export const USER_DETAIL_PAGE_SIZE = 25;
export const USER_LIST_PAGE_SIZE = 10;
export const LEADERBOARD_PAGE_SIZE = 10;
export const TREE_FILTERS = [
  { value: 'ALL', label: 'All users' },
  { value: 'MGR', label: 'Managers' },
  { value: 'CALLER', label: 'Callers' },
];

// ==========================================
// DEMO BOOKINGS (10:00 AM – 7:00 PM, 30-minute slots)
// ==========================================
export const DEMO_SLOT_MIN = 30;
export const DEMO_SLOTS = [];
for (let m = 10 * 60; m < 19 * 60; m += DEMO_SLOT_MIN) DEMO_SLOTS.push(m);
export const DEMO_HISTORY_DAYS = 60;
