// Users (team members) + today's per-person numbers
import { createSlice } from '@reduxjs/toolkit';
import { resetSession } from '../actions';

const initialState = {
  list: [],
  loaded: false,
  error: null,
  todayMembers: null,   // today's numbers per person (User Management, user details)
  todayError: null,
};

const usersSlice = createSlice({
  name: 'users',
  initialState,
  reducers: {
    usersLoaded(state, { payload }) { state.list = payload; state.loaded = true; state.error = null; },
    usersFailed(state, { payload }) { state.error = payload; },
    userRemoved(state, { payload }) { state.list = state.list.filter(u => u.id !== payload); },
    // Server copy of one user merged in (the photo is kept when the reply has none)
    userMerged(state, { payload }) {
      const idx = state.list.findIndex(u => u.id === payload.id);
      if (idx >= 0) state.list[idx] = { ...state.list[idx], ...payload, photoBase64: payload.photoBase64 || state.list[idx].photoBase64 };
    },
    userPatched(state, { payload }) {
      const u = state.list.find(x => x.id === payload.id);
      if (u) Object.assign(u, payload.fields);
    },
    employeePresenceChanged(state, { payload }) {
      const patch = { online: payload.online, lastSeenAt: payload.lastSeenAt };
      const user = state.list.find((row) => row.id === payload.id);
      if (user) Object.assign(user, patch);
      if (state.todayMembers) {
        const todayUser = state.todayMembers.find((row) => row.id === payload.id);
        if (todayUser) Object.assign(todayUser, patch);
      }
    },
    todayLoaded(state, { payload }) { state.todayMembers = payload; state.todayError = null; },
    todayFailed(state, { payload }) { state.todayError = payload; },
  },
  extraReducers: (b) => {
    b.addCase(resetSession, () => initialState);
  },
});

export const {
  usersLoaded, usersFailed, userRemoved, userMerged, userPatched, employeePresenceChanged, todayLoaded, todayFailed,
} = usersSlice.actions;
export default usersSlice.reducer;
