// ==========================================
// IDENTITY · ROLES · SCOPE (pure functions; the redux selector `selectScope` wires them to the store)
// ctx = { users, authUser, viewAsId }
// ==========================================
import { DIALABLE_ROLES, HEAD_ROLES, MGR_FILTER_PLURAL, ROLE_BADGE_CLASS, ROLE_RANK } from '../data/constants';
import { last10, roleLabel } from './format';
import { mapUser } from './mappers';

export function realRole(ctx) { return String((ctx.authUser && ctx.authUser.role) || '').toUpperCase(); }
export function isRealAdmin(ctx) { return realRole(ctx) === 'ADMIN'; }
export function authId(ctx) { return String((ctx.authUser && (ctx.authUser.id || ctx.authUser._id)) || ''); }

export function getActiveUser(ctx) {
  if (ctx.viewAsId && isRealAdmin(ctx)) {
    const v = ctx.users.find(u => u.id === ctx.viewAsId);
    if (v) return v;
  }
  const mine = ctx.users.find(u => u.id === authId(ctx));
  if (mine) return mine;
  return ctx.authUser ? mapUser(ctx.authUser) : { id: '', name: '—', email: '', phone: '', role: 'CALLER', target: 0, mgr: null };
}

// Same rule as the server: everyone under the manager down the reporting tree, plus (for the
// manager themself only) the people on their team. The shared default team links nobody.
export function descendantsOf(users, rootId) {
  const out = [];
  const seen = new Set([rootId]);
  const root = users.find(u => u.id === rootId);
  const team = String((root && root.team) || '').trim().toLowerCase();
  if (team && team !== 'telesales team' && !(root && root.role === 'TEAM_LEADER')) {
    users.forEach(u => {
      if (u.role !== 'ADMIN' && !seen.has(u.id) && String(u.team || '').trim().toLowerCase() === team) {
        seen.add(u.id);
        out.push(u);
      }
    });
  }
  const walk = (id) => {
    users.forEach(u => {
      if (u.mgr === id && !seen.has(u.id)) {
        seen.add(u.id);
        out.push(u);
        walk(u.id);
      }
    });
  };
  const teamMembers = out.slice();
  walk(rootId);
  teamMembers.forEach(u => walk(u.id));
  return out;
}

// Everyone the active view may see (admin: all; manager: self + reporting tree; caller: self)
export function visibleUsers(ctx, me = getActiveUser(ctx)) {
  if (me.role === 'ADMIN') return ctx.users.slice();
  if (me.role === 'CALLER') return [me];
  return [me, ...descendantsOf(ctx.users, me.id)];
}

// One exact matcher shared by every page, same order as the server's counting:
// callerId first, then last-10 phone, then exact name (older rows carry only the name)
export function callBelongsTo(c, u) {
  if (!c || !u) return false;
  if (c.callerId) return c.callerId === u.id;
  const a = last10(c.callerPhone);
  if (a) return a === last10(u.phone);
  const n = String(c.agent || '').trim().toLowerCase();
  return !!n && n !== '—' && n === String(u.name || '').trim().toLowerCase();
}

// A person's row in a server stats list (by id, then by phone)
export function statsFor(list, u) {
  if (!Array.isArray(list) || !u) return null;
  const byId = list.find(t => String(t.id || '') === u.id);
  if (byId) return byId;
  const p = last10(u.phone);
  return p ? (list.find(t => last10(t.phone) === p) || null) : null;
}

// Server-side scope for "view as" (the server pins real managers to their team regardless)
export function buildScopeParam(me, scopedCallers) {
  if (!me || me.role === 'ADMIN') return '';
  const ids = scopedCallers.map(u => u.id).filter(Boolean);
  return ids.length ? `&callerIds=${encodeURIComponent(ids.join(','))}` : '';
}

export function whenParam(period, date) {
  return date ? `date=${encodeURIComponent(date)}` : `period=${encodeURIComponent(period || 'today')}`;
}

export function makeCallInScope(me, scopedCallers) {
  return (c) => me.role === 'ADMIN' || scopedCallers.some(u => callBelongsTo(c, u));
}

export function makeLeadInScope(me, scopedCallers) {
  return (l) => me.role === 'ADMIN' || scopedCallers.some(u =>
    (l.agentId && l.agentId === u.id) ||
    (!l.agentId && l.agent && l.agent.trim().toLowerCase() === (u.name || '').trim().toLowerCase()) ||
    (!l.agentId && l.managerId && l.managerId === u.id));   // not split yet: owned by a manager in view
}

export function canSeeUsersTab(me) { return me.role === 'ADMIN' || me.role === 'MANAGER'; }
export function canSeeDemosTab(me) { return me.role !== 'CALLER'; }
// Phone health: admins, managers, junior managers and team leaders — never callers
export function canSeePhoneHealthTab(me) { return HEAD_ROLES.includes(me.role); }

// Finds the registered user behind a name shown anywhere (same order as callBelongsTo: id, phone, name)
export function findUserRef(users, ref) {
  if (!ref) return null;
  if (ref.id) {
    const byId = users.find(x => x.id === String(ref.id));
    if (byId) return byId;
  }
  const p = last10(ref.phone);
  if (p) {
    const byPhone = users.find(x => last10(x.phone) === p);
    if (byPhone) return byPhone;
  }
  const n = String(ref.name || '').trim().toLowerCase();
  if (!n || n === '—') return null;
  return users.find(x => String(x.name || '').trim().toLowerCase() === n) || null;
}

export function roleRank(role) {
  return ROLE_RANK[role] !== undefined ? ROLE_RANK[role] : 4;
}
export function byRankThenName(a, b) {
  return roleRank(a.role) - roleRank(b.role) || String(a.name).localeCompare(String(b.name));
}
export function roleBadgeClass(role) {
  return ROLE_BADGE_CLASS[role] || ROLE_BADGE_CLASS.CALLER;
}

// The reporting chain from the top down to the direct manager
export function managerChain(users, u) {
  const chain = [];
  const seen = new Set([u && u.id]);
  let m = u ? users.find(x => x.id === u.mgr) : null;
  while (m && !seen.has(m.id) && chain.length < 8) {
    seen.add(m.id);
    chain.unshift(m);
    m = users.find(x => x.id === m.mgr);
  }
  return chain;
}
export function managerChainText(users, u) {
  const chain = managerChain(users, u);
  if (!chain.length) return 'Top Level / Admin';
  return chain.map(m => `${m.name} (${roleLabel(m.role)})`).join(' → ');
}

export function isDialable(u) { return DIALABLE_ROLES.includes(u.role); }
export function isHead(u) { return HEAD_ROLES.includes(u.role); }

// Managed-by filter: every manager-level person in view who has people under them, with head counts
export function mgrFilterOptions(users, visible) {
  const visibleIds = new Set(visible.map(u => u.id));
  return visible
    .filter(isHead)
    .sort(byRankThenName)
    .map(h => {
      const under = descendantsOf(users, h.id).filter(u => visibleIds.has(u.id) && u.role !== 'ADMIN');
      if (!under.length) return null;
      const counts = ['MANAGER', 'JR_MANAGER', 'TEAM_LEADER', 'CALLER'].map(r => {
        const n = under.filter(u => (u.role === r) || (r === 'CALLER' && !MGR_FILTER_PLURAL[u.role])).length;
        return n ? `${n} ${n === 1 ? roleLabel(r) : MGR_FILTER_PLURAL[r]}` : '';
      }).filter(Boolean).join(' · ');
      return { value: h.id, label: `${h.name.toUpperCase()} (${roleLabel(h.role)}) · ${counts}` };
    })
    .filter(Boolean);
}

// Ids of everyone under the chosen person, or null for "all"
export function mgrFilterSet(users, id) {
  if (!id || id === 'ALL') return null;
  if (!users.some(u => u.id === id)) return null;
  return new Set(descendantsOf(users, id).map(u => u.id));
}
