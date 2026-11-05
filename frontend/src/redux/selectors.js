// Derived, memoised views of the store shared by every page
import { createSelector } from '@reduxjs/toolkit';
import {
  authId, buildScopeParam, getActiveUser, isDialable, isRealAdmin, makeCallInScope, makeLeadInScope,
  realRole, visibleUsers, whenParam,
} from '../utils/scope';

const selUsers = (s) => s.users.list;
const selAuthUser = (s) => s.auth.authUser;
const selViewAsId = (s) => s.auth.viewAsId;

// Who is signed in, whose view is active ("view as"), and everyone that view may see
export const selectScope = createSelector([selUsers, selAuthUser, selViewAsId], (users, authUser, viewAsId) => {
  const ctx = { users, authUser, viewAsId };
  const me = getActiveUser(ctx);
  const visible = visibleUsers(ctx, me);
  const scoped = visible.filter(u => u.role !== 'ADMIN');
  return {
    users,
    authUser,
    viewAsId,
    me,
    visible,
    visibleIds: new Set(visible.map(u => u.id)),
    scoped,                                   // everyone in view who makes calls
    dialable: scoped.filter(isDialable),      // callers, junior managers, team leaders
    scopeParam: buildScopeParam(me, scoped),  // "&callerIds=…" for "view as" requests
    isRealAdmin: isRealAdmin(ctx),
    authId: authId(ctx),
    realRole: realRole(ctx),
    isCallInScope: makeCallInScope(me, scoped),
    isLeadInScope: makeLeadInScope(me, scoped),
  };
});

export const selectScopedLeads = createSelector(
  [(s) => s.leads.list, selectScope],
  (leads, scope) => leads.filter(scope.isLeadInScope),
);

// Request keys: the server numbers are cached per period + scope
export const selectDashKey = (s) => {
  const typeParam = s.dashboard.typeFilter && s.dashboard.typeFilter !== 'ALL'
    ? `&employeeType=${encodeURIComponent(s.dashboard.typeFilter)}`
    : '';
  return `?${whenParam(s.dashboard.period, s.dashboard.customDate)}${selectScope(s).scopeParam}${typeParam}`;
};
export const selectLbKey = (s) => `?${whenParam(s.leaderboard.period, s.leaderboard.customDate)}${selectScope(s).scopeParam}`;
export const selectUdKey = (s) => `${s.userDetail.userId}|${s.userDetail.date || s.userDetail.period}`;

// Call Recordings: one agent picked → that agent only (inside the viewer's scope); otherwise the scope
export const selectRecsQueryKey = (s) => {
  const { agent } = s.recordings;
  return agent && agent !== 'ALL' ? `&callerIds=${encodeURIComponent(agent)}` : selectScope(s).scopeParam;
};
