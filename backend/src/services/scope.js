// Who may see what. The scope is always derived from the signed-in user's token (req.user);
// client-sent filters (callerIds, userId, team, managerId ...) can only NARROW it.
// Token-less legacy app builds are treated as a single caller identified by the params they send.
// Whenever a requested target cannot be resolved the scope is EMPTY (never company-wide).
const Employee = require('../models/Employee');
const { last10, isObjectId, exactNameRegex, anyPhoneRegex, phoneRegex } = require('../utils/common');

const EMP_FIELDS = '-photoBase64 -avatarUrl';
const MANAGER_ROLES = ['admin', 'manager', 'jr_manager', 'team_leader'];
const ALL_VALUES = new Set(['', 'ALL', 'ALL TEAMS', 'ALL MANAGERS', 'ALL USERS', 'ALL CALLERS']);
const isAllValue = (v) => v === undefined || v === null || ALL_VALUES.has(String(v).trim().toUpperCase());

const EMPTY = (role, me) => ({ role, me: me || null, all: false, employees: [], empty: true });

// Finds one employee by id, _id, phone (any formatting) or exact name (case-insensitive).
async function findEmployeeByRef(ref) {
  const term = String(ref === undefined || ref === null ? '' : ref).trim();
  if (!term) return null;
  const or = [{ id: term }];
  if (isObjectId(term)) or.push({ _id: term });
  const pr = last10(term).length === 10 && /^[+\d\s()-]+$/.test(term) ? phoneRegex(term) : null;
  if (pr) or.push({ phone: pr });
  or.push({ name: exactNameRegex(term) });
  return Employee.findOne({ $or: or }).select(EMP_FIELDS).lean();
}

// Same match, in memory, against an already-loaded list.
function matchesRef(emp, ref) {
  const term = String(ref === undefined || ref === null ? '' : ref).trim();
  if (!term || !emp) return false;
  if (emp.id === term || String(emp._id) === term) return true;
  if (last10(term).length === 10 && /^[+\d\s()-]+$/.test(term) && last10(emp.phone) === last10(term)) return true;
  return (emp.name || '').trim().toLowerCase() === term.toLowerCase();
}

// Direct reports of one manager: assigned to them (by id, _id or name) or, for the top manager
// only, on their team. Deeper levels follow explicit links only, so a sub-manager on the default
// team never pulls in the whole company. Admins are never included.
// The default team every new user gets is not a real team, so it never links anyone.
const DEFAULT_TEAM = 'telesales team';
function reportsQuery(mgr, withTeam) {
  const or = [{ managerId: mgr.id }, { managerId: String(mgr._id) }];
  if (mgr.name) or.push({ managerName: exactNameRegex(mgr.name) });
  const team = (mgr.team || '').trim();
  if (withTeam && team && team.toLowerCase() !== DEFAULT_TEAM) or.push({ team: exactNameRegex(team) });
  return { $or: or, role: { $ne: 'admin' } };
}

// Everyone under a manager, down the whole reporting tree (manager -> jr manager -> callers),
// the same tree the admin web walks. Cycles in bad data are ignored.
async function assignedTo(mgr) {
  const seen = new Set([mgr.id]);
  const out = [];
  let level = [mgr];
  for (let depth = 0; level.length && depth < 10; depth++) {
    // A Team Leader sees only the people assigned to them, never the rest of the team they share
    const found = await Employee.find({ $or: level.map(m => reportsQuery(m, depth === 0 && m.role !== 'team_leader')) }).select(EMP_FIELDS).lean();
    level = found.filter(e => !seen.has(e.id));
    level.forEach(e => { seen.add(e.id); out.push(e); });
    // Only people who manage others can have reports of their own
    level = level.filter(e => e.role === 'manager' || e.role === 'jr_manager' || e.role === 'team_leader');
  }
  return out;
}

// Employees a manager / jr manager is responsible for: their whole reporting tree plus themself.
async function teamOf(mgr) {
  return [mgr, ...(await assignedTo(mgr))];
}

// params: merged query/body. Returns { role, me, all, employees, empty }.
//  - all === true only for an admin with no narrowing filter (employees then holds everyone).
async function resolveScope(req, params = null) {
  const q = params || { ...(req.body && typeof req.body === 'object' && !Array.isArray(req.body) ? req.body : {}), ...req.query };

  let role;
  let me;
  if (req.user) {
    role = req.user.role;
    me = await Employee.findOne({ id: req.user.id }).select(EMP_FIELDS).lean();
    if (!me) return EMPTY(role, null);
  } else {
    // Legacy (token-less) client: a single caller identified by what the old app sends
    role = 'caller';
    const refs = [q.loggedInUserId, q.userId, q.callerId, q.callerPhone, q.phone, q.callerName, q.name]
      .filter(v => v && !isAllValue(v));
    for (const ref of refs) {
      me = await findEmployeeByRef(ref);
      if (me) break;
    }
    if (!me) return EMPTY(role, null);
  }

  if (!MANAGER_ROLES.includes(role)) {
    return { role, me, all: false, employees: [me], empty: false };
  }

  const isAdmin = role === 'admin';
  // Base: admin -> everyone, manager/jr_manager/team_leader -> own team
  const base = isAdmin ? await Employee.find({}).select(EMP_FIELDS).lean() : await teamOf(me);
  const inBase = (list) => {
    if (isAdmin) return list;
    const ids = new Set(base.map(e => e.id));
    return list.filter(e => ids.has(e.id));
  };
  const result = (employees, all = false) => ({ role, me, all, employees, empty: employees.length === 0 });

  // 1. Explicit list of employees (admin web manager/caller views) — only ids inside the base scope survive
  if (q.callerIds && !isAllValue(q.callerIds)) {
    const ids = String(q.callerIds).split(',').map(s => s.trim()).filter(Boolean);
    return result(base.filter(e => ids.includes(e.id) || ids.includes(String(e._id))));
  }

  // 2. One specific caller
  const target = [q.userId, q.callerId, q.callerPhone, q.callerName].find(v => v && !isAllValue(v));
  if (target) {
    const hit = base.find(e => matchesRef(e, target));
    return result(hit ? [hit] : []);
  }

  // 3. A team
  if (!isAllValue(q.team)) {
    const t = String(q.team).trim().toLowerCase();
    return result(base.filter(e => (e.team || '').trim().toLowerCase() === t));
  }

  // 4. A manager's people
  if (!isAllValue(q.managerId)) {
    const mgr = base.find(e => matchesRef(e, q.managerId)) || (isAdmin ? await findEmployeeByRef(q.managerId) : null);
    if (!mgr) return result([]);
    return result(inBase(await assignedTo(mgr)));
  }

  return result(base, isAdmin);
}

// ---- Query builders (an empty scope matches nothing) -------------------------------------------
const NOTHING = { _id: null };

function scopeParts(employees) {
  const ids = employees.map(e => e.id).filter(Boolean);
  const rawPhones = employees.map(e => e.phone).filter(Boolean);
  const phoneRe = anyPhoneRegex(rawPhones);
  const names = employees.map(e => (e.name || '').trim()).filter(Boolean);
  return { ids, rawPhones, phoneRe, names };
}

// CallLog rows made by employees in scope (by id, any phone format, or exact name).
function callLogQueryFor(scope) {
  if (!scope || scope.employees.length === 0) return NOTHING;
  const { ids, rawPhones, phoneRe, names } = scopeParts(scope.employees);
  const or = [];
  if (ids.length) or.push({ callerId: { $in: ids } });
  if (rawPhones.length) or.push({ callerPhone: { $in: rawPhones } });
  if (phoneRe) or.push({ callerPhone: phoneRe });
  if (names.length) or.push({ callerName: { $in: names.map(exactNameRegex) } });
  return or.length ? { $or: or } : NOTHING;
}

// Recordings made by employees in scope. (phoneNumber is the CUSTOMER — never used for scoping.)
function recordingQueryFor(scope) {
  if (!scope || scope.employees.length === 0) return NOTHING;
  const { ids, phoneRe, names } = scopeParts(scope.employees);
  const or = [];
  if (ids.length) or.push({ callerId: { $in: ids } });
  if (phoneRe) or.push({ callerPhone: phoneRe });
  // Older recordings only carry the caller's name
  if (names.length) or.push({ callerId: { $in: [null, ''] }, callerName: { $in: names.map(exactNameRegex) } });
  return or.length ? { $or: or } : NOTHING;
}

// Leads assigned to employees in scope (by assignedCallerId, fallback exact name for older rows).
function leadQueryFor(scope) {
  if (!scope || scope.employees.length === 0) return NOTHING;
  const { ids, names } = scopeParts(scope.employees);
  const or = [];
  if (ids.length) or.push({ assignedCallerId: { $in: ids } });
  if (names.length) or.push({ assignedCallerId: { $in: [null, ''] }, assignedCaller: { $in: names.map(exactNameRegex) } });
  // Not yet split: batches owned by a manager in scope (only managers appear as owners)
  if (ids.length) or.push({ assignedCallerId: { $in: [null, ''] }, managerId: { $in: ids } });
  return or.length ? { $or: or } : NOTHING;
}

// Does a record (recording / lead owner) belong to someone in scope?
function ownerInScope(scope, { id, phone, name }) {
  if (!scope || scope.employees.length === 0) return false;
  return scope.employees.some(e =>
    (id && e.id === id) ||
    (!id && phone && last10(phone).length >= 8 && last10(e.phone) === last10(phone)) ||
    (!id && name && (e.name || '').trim().toLowerCase() === String(name).trim().toLowerCase()));
}

module.exports = {
  MANAGER_ROLES,
  isAllValue,
  findEmployeeByRef,
  matchesRef,
  resolveScope,
  callLogQueryFor,
  recordingQueryFor,
  leadQueryFor,
  ownerInScope,
  NOTHING,
};
