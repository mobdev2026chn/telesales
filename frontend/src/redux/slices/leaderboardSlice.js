// LEADERBOARD state: server numbers cached per request key + the page's filters
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
  mgrFilter: 'ALL',
  typeFilter: 'ALL',
};

const leaderboardSlice = createSlice({
  name: 'leaderboard',
  initialState,
  reducers: {
    lbRequested(state, { payload }) { state.pendingKey = payload; state.errorKey = null; },
    lbSucceeded(state, { payload }) {
      if (state.pendingKey !== payload.key) return;
      state.data = payload.data;
      state.dataKey = payload.key;
      state.error = null;
      state.pendingKey = null;
    },
    lbFailed(state, { payload }) {
      if (state.pendingKey !== payload.key) return;
      state.error = payload.error;
      state.errorKey = payload.key;
      state.pendingKey = null;
    },
    // Refetched when the page is opened
    lbInvalidated(state) { state.dataKey = null; state.errorKey = null; },
    setLbPeriod(state, { payload }) { state.period = payload; state.customDate = null; },
    setLbDate(state, { payload }) { state.customDate = payload || null; },
    setLbMgrFilter(state, { payload }) { state.mgrFilter = payload || 'ALL'; },
    setLbTypeFilter(state, { payload }) { state.typeFilter = payload || 'ALL'; },
  },
  extraReducers: (b) => {
    b.addCase(resetSession, () => initialState);
  },
});

export const { lbRequested, lbSucceeded, lbFailed, lbInvalidated, setLbPeriod, setLbDate, setLbMgrFilter, setLbTypeFilter } = leaderboardSlice.actions;
export default leaderboardSlice.reducer;
