// DEMO BOOKINGS state: bookings, blocked slots, selected day and team leader
import { createSlice } from '@reduxjs/toolkit';
import { nextDemoDay } from '../../utils/demos';
import { resetSession } from '../actions';

const initialState = {
  list: [],
  blocks: [],
  loaded: false,
  error: null,
  pending: false,
  day: null,           // selected day "YYYY-MM-DD" (null = today)
  dayTouched: false,   // until a day is picked, the page opens on the next booked demo's day
  tl: 'ALL',           // team leader filter
};

const demosSlice = createSlice({
  name: 'demos',
  initialState,
  reducers: {
    demosRequested(state) { state.pending = true; },
    demosLoaded(state, { payload }) {
      state.list = payload.list;
      if (!state.dayTouched) state.day = nextDemoDay(payload.list);
      if (payload.blocks) state.blocks = payload.blocks;
      state.error = null;
      state.loaded = true;
      state.pending = false;
    },
    demoUpserted(state, { payload }) {
      const index = state.list.findIndex((demo) => demo.id === payload.id);
      if (index < 0) state.list.unshift(payload);
      else state.list[index] = payload;
    },
    demosFailed(state, { payload }) { state.error = payload; state.pending = false; },
    setDemoDay(state, { payload }) {
      state.dayTouched = true;
      state.day = /^\d{4}-\d{2}-\d{2}$/.test(payload || '') ? payload : null;
    },
    setDemoTl(state, { payload }) { state.tl = payload || 'ALL'; },
  },
  extraReducers: (b) => {
    b.addCase(resetSession, () => initialState);
  },
});

export const {
  demosRequested, demosLoaded, demosFailed, demoUpserted, setDemoDay, setDemoTl,
} = demosSlice.actions;
export default demosSlice.reducer;
