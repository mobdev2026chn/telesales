// CALL RECORDINGS · REVIEWS (saved to the server)
import { CRIT, REC_FETCH_LIMIT, REC_SAVE_DEBOUNCE_MS } from '../../data/constants';
import { selectRecsQueryKey } from '../../redux/selectors';
import {
  recAgentChanged, recCustomRangeChanged, recMetaPatched, recordingUpdated, recRangeChanged, recsFailed, recsLoaded, recsRequested,
} from '../../redux/slices/recordingsSlice';
import store from '../../redux/store';
import { istMidnight } from '../format';
import { mapRecording, newRecMeta } from '../mappers';
import { notify } from '../notify';
import { rangeBounds } from '../periods';
import { recordingService } from '../services';

const { dispatch, getState } = store;

export function effectiveRangeBounds(rs) {
  if (rs && (rs.customFrom || rs.customTo)) {
    if (rs.customFrom && rs.customTo) {
      const a = rs.customFrom <= rs.customTo ? rs.customFrom : rs.customTo;
      const b = rs.customFrom <= rs.customTo ? rs.customTo : rs.customFrom;
      const from = istMidnight(a);
      const to = new Date(istMidnight(b).getTime() + 24 * 3600 * 1000);
      return { from, to };
    }
    const single = rs.customFrom || rs.customTo;
    const from = istMidnight(single);
    const to = new Date(from.getTime() + 24 * 3600 * 1000);
    return { from, to };
  }
  return rangeBounds(rs ? rs.range : 'today', 0);
}

export async function fetchRecordings(append = false) {
  const reqId = getState().recordings.reqId + 1;
  dispatch(recsRequested(reqId));
  try {
    const state = getState();
    const query = selectRecsQueryKey(state);
    const rs = state.recordings;
    const scopeKey = `${query}|${rs.range}|${rs.customFrom || ''}|${rs.customTo || ''}`;
    const { from, to } = effectiveRangeBounds(rs);
    let qs = `?limit=${REC_FETCH_LIMIT}${query}&from=${encodeURIComponent(from.toISOString())}&to=${encodeURIComponent(to.toISOString())}`;
    const loadedList = state.recordings.list;
    if (append && loadedList.length) {
      const oldest = loadedList.reduce((min, r) => {
        const t = r.createdAt ? new Date(r.createdAt).getTime() : Infinity;
        return t < min ? t : min;
      }, Infinity);
      if (isFinite(oldest)) qs += `&before=${encodeURIComponent(new Date(oldest).toISOString())}`;
    }
    const json = await recordingService.list(qs);
    if (getState().recordings.reqId !== reqId) return; // another agent / range was picked meanwhile
    const raw = json.recordings || [];
    dispatch(recsLoaded({
      append,
      list: raw.map(mapRecording).filter(r => r.id),
      rawCount: raw.length,
      total: json.total,
      rangeApplied: !!json.rangeApplied,
      scopeKey,
    }));
  } catch (e) {
    dispatch(recsFailed(e.message));
  }
}

export async function changeRecRange(val) {
  dispatch(recRangeChanged(val));
  await fetchRecordings(false);
}

export async function changeRecCustomRange(from, to) {
  let a = from || '';
  let b = to || '';
  if (a && b && a > b) [a, b] = [b, a];
  dispatch(recCustomRangeChanged({ from: a, to: b }));
  await fetchRecordings(false);
}

export async function changeRecAgent(val) {
  dispatch(recAgentChanged(val));
  await fetchRecordings(false);
}

const patch = (id, p) => dispatch(recMetaPatched({ id, patch: p }));
const metaOf = (id) => getState().recordings.recMeta[id] || newRecMeta();
const saveTimers = new Map();

async function postReview(id, body) {
  patch(id, { saveState: 'SAVING…' });
  try {
    const json = await recordingService.review(id, body);
    if (json.recording) dispatch(recordingUpdated(mapRecording(json.recording)));
    patch(id, { saveState: 'SAVED' });
    return true;
  } catch (e) {
    patch(id, { saveState: 'NOT SAVED' });
    notify(`⚠️ REVIEW NOT SAVED: ${e.message}`);
    return false;
  }
}

// Debounced: several quick star clicks become one save
export function setRecordingStar(id, critKey, rating) {
  if (!CRIT.some(([k]) => k === critKey) || !(rating >= 1 && rating <= 5)) return;
  patch(id, { crit: { [critKey]: rating }, saveState: 'UNSAVED', dirty: true });
  clearTimeout(saveTimers.get(id));
  saveTimers.set(id, setTimeout(() => {
    saveTimers.delete(id);
    patch(id, { dirty: false });
    postReview(id, { criteria: { ...metaOf(id).crit } });
  }, REC_SAVE_DEBOUNCE_MS));
}

export async function reviewRecording(id, status) {
  const meta = metaOf(id);
  clearTimeout(saveTimers.get(id));
  saveTimers.delete(id);
  patch(id, { dirty: false });
  const ok = await postReview(id, { criteria: { ...meta.crit }, status });
  if (ok) notify(status === 'APPROVED' ? 'CALL APPROVED' : 'FLAGGED FOR COACHING');
}

export async function setRecordingOutcome(id, outcome) {
  patch(id, { outcome });
  const ok = await postReview(id, { outcome });
  if (ok) notify(outcome === 'SUCCESSFUL' ? 'MARKED SUCCESSFUL' : 'MARKED UNSUCCESSFUL');
}

export async function saveRecordingFeedback(id) {
  const text = (metaOf(id).draft || '').trim();
  if (!text) return;
  patch(id, { draft: text });
  const ok = await postReview(id, { comment: text });
  if (ok) {
    patch(id, { draft: '' });
    notify('FEEDBACK SAVED & SENT TO CALLER');
  }
}

// Pin / unpin from the portal; the app reads the same flag and lists pinned recordings first
export async function toggleRecordingPin(id) {
  const meta = metaOf(id);
  if (meta.pinBusy) return;
  const next = !meta.pinned;
  patch(id, { pinned: next, pinBusy: true });
  try {
    const json = await recordingService.pin(id, next);
    patch(id, { pinBusy: false });
    if (json.recording) dispatch(recordingUpdated(mapRecording(json.recording)));
    notify(next ? 'RECORDING PINNED · SHOWN FIRST IN THE APP' : 'RECORDING UNPINNED');
  } catch (e) {
    patch(id, { pinned: !next, pinBusy: false });
    notify(`⚠️ PIN NOT SAVED: ${e.message}`);
  }
}
