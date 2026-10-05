// DASHBOARD state: server numbers cached per request key (period + scope) + the page's filters
import { createSlice } from '@reduxjs/toolkit';
import { resetSession } from '../actions';

const initialState = {
  data: null,
  dataKey: null,
  pendingKey: null,
  errorKey: null,
  error: null,
  period: 'today',
  customDate: null,
  teamPage: 1,
  mgrFilter: 'ALL',   // "Managed by" filter (person id or ALL)
};

const dashboardSlice = createSlice({
  name: 'dashboard',
  initialState,
  reducers: {
    dashRequested(state, { payload }) { state.pendingKey = payload; state.errorKey = null; },
    dashSucceeded(state, { payload }) {
      if (state.pendingKey !== payload.key) return;
      state.data = payload.data;
      state.dataKey = payload.key;
      state.error = null;
      state.pendingKey = null;
    },
    dashFailed(state, { payload }) {
      if (state.pendingKey !== payload.key) return;
      state.error = payload.error;
      state.errorKey = payload.key;
      state.pendingKey = null;
    },
    employeePresenceChanged(state, { payload }) {
      if (!state.data) return;
      const { id, online, lastSeenAt } = payload;
      const member = state.data.teamMembers?.find((row) => row.id === id);
      if (member) {
        member.online = online;
        member.lastSeenAt = lastSeenAt;
      }
      const liveStatus = state.data.callerLiveStatuses?.find((row) => row.id === id);
      if (liveStatus && liveStatus.status !== 'ON CALL') {
        liveStatus.status = online ? 'ONLINE' : 'OFFLINE';
        liveStatus.statusColor = online ? '#34C759' : '#8E8E93';
      }
    },
    dashInvalidated(state) { state.dataKey = null; },
    setDashPeriod(state, { payload }) { state.period = payload; state.customDate = null; },
    setDashDate(state, { payload }) { state.customDate = payload || null; },
    setDashTeamPage(state, { payload }) { state.teamPage = Math.max(1, payload); },
    setDashMgrFilter(state, { payload }) { state.mgrFilter = payload || 'ALL'; state.teamPage = 1; },
  },
  extraReducers: (b) => {
    b.addCase(resetSession, () => initialState);
  },
});

export const {
  dashRequested, dashSucceeded, dashFailed, dashInvalidated, employeePresenceChanged,
  setDashPeriod, setDashDate, setDashTeamPage, setDashMgrFilter,
} = dashboardSlice.actions;
export default dashboardSlice.reducer;
