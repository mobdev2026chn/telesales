// PHONE HEALTH state: the server's per-agent recording health cached per request key + the page's filters
import { createSlice } from '@reduxjs/toolkit';
import { resetSession } from '../actions';

export const PHONE_HEALTH_DAYS = [1, 7, 30];

const initialState = {
  data: null,         // { agents, days, since, legacyGraceEnabled, oldAppClients }
  dataKey: null,
  pendingKey: null,
  errorKey: null,
  error: null,
  days: 7,            // 1 = today, 7 = last 7 days, 30 = last 30 days
  typeFilter: 'ALL',  // "Type" filter (sales_team, project_coordinator, others, or ALL)
};

const phoneHealthSlice = createSlice({
  name: 'phoneHealth',
  initialState,
  reducers: {
    phRequested(state, { payload }) { state.pendingKey = payload; state.errorKey = null; },
    phSucceeded(state, { payload }) {
      if (state.pendingKey !== payload.key) return;
      state.data = payload.data;
      state.dataKey = payload.key;
      state.error = null;
      state.pendingKey = null;
    },
    phFailed(state, { payload }) {
      if (state.pendingKey !== payload.key) return;
      state.error = payload.error;
      state.errorKey = payload.key;
      state.pendingKey = null;
    },
    setPhDays(state, { payload }) {
      const d = Number(payload);
      state.days = PHONE_HEALTH_DAYS.includes(d) ? d : 7;
    },
    setPhTypeFilter(state, { payload }) { state.typeFilter = payload || 'ALL'; },
  },
  extraReducers: (b) => {
    b.addCase(resetSession, () => initialState);
  },
});

export const { phRequested, phSucceeded, phFailed, setPhDays, setPhTypeFilter } = phoneHealthSlice.actions;
export default phoneHealthSlice.reducer;
