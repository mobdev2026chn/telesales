// LEADS state: Lead Calling queue, uploads, the Leads Pipeline
import { createSlice } from '@reduxjs/toolkit';
import { resetSession } from '../actions';

const initialState = {
  list: [],
  loaded: false,
  error: null,
  pendingUpload: null,     // chosen file waiting for ASSIGN (then kept as a snapshot in upload history)
  assigningUpload: false,
  // Lead Calling queue filters
  ulFilter: 'ALL',
  ulSearch: '',
  ulPage: 1,
  // Conversion funnel: today / week / month, or one picked day (YYYY-MM-DD), which wins over the period
  funnelPeriod: 'today',
  funnelDate: null,
  // Leads Pipeline filters
  pipelineStage: 'ALL',
  pipelineAgent: 'ALL',
  pipelineSearch: '',
  pipelinePages: {},
};

function upsert(list, lead) {
  const idx = list.findIndex(x => x.id === lead.id);
  if (idx >= 0) list[idx] = lead;
}

const leadsSlice = createSlice({
  name: 'leads',
  initialState,
  reducers: {
    leadsLoaded(state, { payload }) { state.list = payload; state.loaded = true; state.error = null; },
    leadsFailed(state, { payload }) { state.error = payload; },
    leadsReplaced(state, { payload }) { state.list = payload; },
    leadUpdated(state, { payload }) { upsert(state.list, payload); },
    leadUpserted(state, { payload }) {
      const idx = state.list.findIndex(x => x.id === payload.id);
      if (idx >= 0) state.list[idx] = payload;
      else state.list.unshift(payload);
    },
    leadRemoved(state, { payload }) { state.list = state.list.filter(x => x.id !== payload); },
    leadsUpdated(state, { payload }) { payload.forEach(l => upsert(state.list, l)); },
    leadAdded(state, { payload }) { state.list.unshift(payload); },
    // Imported rows merged in while the next list request settles
    leadsMerged(state, { payload }) {
      const byId = new Map(state.list.map(l => [l.id, l]));
      payload.forEach(l => byId.set(l.id, l));
      state.list = Array.from(byId.values());
    },
    setPendingUpload(state, { payload }) { state.pendingUpload = payload; },
    setAssigningUpload(state, { payload }) { state.assigningUpload = !!payload; },

    setUlFilter(state, { payload }) { state.ulFilter = payload; state.ulPage = 1; },
    setUlSearch(state, { payload }) { state.ulSearch = payload; state.ulPage = 1; },
    setUlPage(state, { payload }) { state.ulPage = Math.max(1, payload); },
    setFunnelPeriod(state, { payload }) { state.funnelPeriod = payload; state.funnelDate = null; },
    setFunnelDate(state, { payload }) { state.funnelDate = payload; },

    setPipelineStage(state, { payload }) { state.pipelineStage = payload; state.pipelinePages = {}; },
    setPipelineAgent(state, { payload }) { state.pipelineAgent = payload || 'ALL'; state.pipelinePages = {}; },
    setPipelineSearch(state, { payload }) { state.pipelineSearch = (payload || '').trim().toLowerCase(); state.pipelinePages = {}; },
    loadMorePipelineStage(state, { payload }) { state.pipelinePages[payload] = (state.pipelinePages[payload] || 1) + 1; },
  },
  extraReducers: (b) => {
    b.addCase(resetSession, () => initialState);
  },
});

export const {
  leadsLoaded, leadsFailed, leadsReplaced, leadUpdated, leadUpserted, leadRemoved, leadsUpdated, leadAdded, leadsMerged,
  setPendingUpload, setAssigningUpload, setUlFilter, setUlSearch, setUlPage, setFunnelPeriod, setFunnelDate,
  setPipelineStage, setPipelineAgent, setPipelineSearch, loadMorePipelineStage,
} = leadsSlice.actions;
export default leadsSlice.reducer;
