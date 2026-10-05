// CALL RECORDINGS state: list, per-recording review state, filters
import { createSlice } from '@reduxjs/toolkit';
import { CALL_RANGE_DAYS, REC_FETCH_LIMIT } from '../../data/constants';
import { newRecMeta, recMetaFrom } from '../../utils/mappers';
import { resetSession } from '../actions';

const initialState = {
  list: [],
  recMeta: {},          // per recording: { crit, status, comments, draft, saveState, dirty, pinned, pinBusy }
  hasMore: false,
  total: 0,
  scopeKey: null,
  loaded: false,
  error: null,
  reqId: 0,
  // filters
  filter: 'ALL',
  agent: 'ALL',         // one agent's recordings (loaded from the server for that agent)
  range: 'today',       // same choices and default as the Call Log
  page: 1,
};

function mergeMeta(state, recs) {
  recs.forEach(r => { state.recMeta[r.id] = recMetaFrom(r.review, state.recMeta[r.id]); });
}

const recordingsSlice = createSlice({
  name: 'recordings',
  initialState,
  reducers: {
    recsRequested(state, { payload }) { state.reqId = payload; },
    recsLoaded(state, { payload }) {
      const { append, list, rawCount, total, rangeApplied, scopeKey } = payload;
      mergeMeta(state, list);
      let next;
      if (append) {
        const seen = new Set(state.list.map(r => r.id));
        next = state.list.concat(list.filter(r => !seen.has(r.id)));
      } else {
        next = list;
      }
      next.sort((a, b) => (b.ts ? b.ts.getTime() : 0) - (a.ts ? a.ts.getTime() : 0));
      state.list = next;
      state.hasMore = rawCount >= REC_FETCH_LIMIT;
      if (!append) {
        // An older server ignores the date range: its total then covers all time, so it is not shown
        state.total = rangeApplied ? (Number(total) || list.length) : 0;
        state.scopeKey = scopeKey;
      }
      state.error = null;
      state.loaded = true;
    },
    recsFailed(state, { payload }) { state.error = payload; },
    // Review fields of recordings fetched elsewhere (user details page)
    recMetaMerged(state, { payload }) { mergeMeta(state, payload); },
    recordingUpdated(state, { payload }) {
      mergeMeta(state, [payload]);
      const idx = state.list.findIndex(r => r.id === payload.id);
      if (idx >= 0) state.list[idx] = payload;
    },
    recordingUpserted(state, { payload }) {
      mergeMeta(state, [payload]);
      const idx = state.list.findIndex(r => r.id === payload.id);
      if (idx >= 0) state.list[idx] = payload;
      else state.list.unshift(payload);
    },
    recMetaPatched(state, { payload }) {
      const { id, patch } = payload;
      const meta = state.recMeta[id] || newRecMeta();
      state.recMeta[id] = { ...meta, ...patch, crit: patch.crit ? { ...meta.crit, ...patch.crit } : meta.crit };
    },
    setRecordingDraft(state, { payload }) {
      const meta = state.recMeta[payload.id] || newRecMeta();
      state.recMeta[payload.id] = { ...meta, draft: payload.draft };
    },
    setRecFilter(state, { payload }) { state.filter = payload; state.page = 1; },
    setRecPage(state, { payload }) { state.page = Math.max(1, payload); },
    recRangeChanged(state, { payload }) {
      state.range = CALL_RANGE_DAYS[payload] !== undefined ? payload : 'today';
      state.page = 1;
      state.list = [];
      state.loaded = false;
    },
    recAgentChanged(state, { payload }) {
      state.agent = payload || 'ALL';
      state.page = 1;
      state.list = [];
      state.loaded = false;
    },
  },
  extraReducers: (b) => {
    b.addCase(resetSession, () => initialState);
  },
});

export const {
  recsRequested, recsLoaded, recsFailed, recMetaMerged, recordingUpdated, recordingUpserted, recMetaPatched, setRecordingDraft,
  setRecFilter, setRecPage, recRangeChanged, recAgentChanged,
} = recordingsSlice.actions;
export default recordingsSlice.reducer;
