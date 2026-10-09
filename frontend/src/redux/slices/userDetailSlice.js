// USER DETAILS PAGE state (/user/:id): one person's numbers, calls and recordings
import { createSlice } from '@reduxjs/toolkit';
import { resetSession } from '../actions';

const initialState = {
  userId: null,
  ud: null,            // { key, dash, dashError, calls, callsTotal, callsHasMore, callsError, recs, recsError }
  pendingKey: null,
  period: 'today',
  date: null,
  page: 1,
};

const userDetailSlice = createSlice({
  name: 'userDetail',
  initialState,
  reducers: {
    udUserSet(state, { payload }) {
      if (state.userId !== payload) {
        state.userId = payload;
        state.page = 1;
      }
    },
    setUdPeriod(state, { payload }) { state.period = payload; state.date = null; state.page = 1; },
    setUdDate(state, { payload }) { state.date = payload; state.page = 1; },
    setUdPage(state, { payload }) { state.page = Math.max(1, payload); },
    udRequested(state, { payload }) { state.pendingKey = payload; },
    udSettled(state, { payload }) { if (state.pendingKey === payload) state.pendingKey = null; },
    udLoaded(state, { payload }) { state.ud = payload; },
    employeePresenceChanged(state, { payload }) {
      if (!state.ud?.dash) return;
      const { id, online, lastLoginAt, loggedOutAt } = payload;
      const member = state.ud.dash.teamMembers?.find((row) => row.id === id);
      if (member) {
        member.online = online;
        if (lastLoginAt !== undefined) member.lastLoginAt = lastLoginAt;
        if (loggedOutAt !== undefined) member.loggedOutAt = loggedOutAt;
      }
      const liveStatus = state.ud.dash.callerLiveStatuses?.find((row) => row.id === id);
      if (liveStatus && liveStatus.status !== 'ON CALL') {
        liveStatus.status = online ? 'ONLINE' : 'OFFLINE';
        liveStatus.statusColor = online ? '#34C759' : '#8E8E93';
      }
    },
  },
  extraReducers: (b) => {
    b.addCase(resetSession, () => initialState);
  },
});

export const {
  udUserSet, setUdPeriod, setUdDate, setUdPage, udRequested, udSettled, udLoaded, employeePresenceChanged,
} = userDetailSlice.actions;
export default userDetailSlice.reducer;
