// ==========================================
// AUDIO: in-card players (Call Recordings) + the docked bottom player (everything else).
// The <audio> elements live in the DOM; this module drives them and mirrors what the docked
// bar should show into redux (ui.audio), so the bar component simply renders that state.
// ==========================================
import { recordingAudioUrl, renewAudioUrl } from './api';
import { formatPhone } from './format';
import { notify } from './notify';
import { audioBarHidden, audioBarShown, audioControlsSynced } from '../redux/slices/uiSlice';
import store from '../redux/store';

const Q = { source: null, id: null, el: null, dock: null, lists: { log: [], rec: [] } };

// The docked player's <audio> element (rendered once by AudioPlayerBar)
export function registerDock(el) { Q.dock = el; }

// Prev / Next walk through these ids: 'log' = the filtered Call Log, 'rec' = the Call Recordings list
export function setPlaylist(source, ids) {
  const prev = Q.lists[source] || [];
  if (prev.length === ids.length && prev.every((id, i) => id === ids[i])) return;
  Q.lists[source] = ids;
  syncAudioControls();
}

function queueList() { return Q.source === 'rec' ? Q.lists.rec : Q.lists.log; }

export function findCardAudio(recId) {
  return Array.from(document.querySelectorAll('audio[data-rec-id]')).find(a => a.dataset.recId === String(recId)) || null;
}

// Recording links carry a short-lived media token: a player whose link was built earlier (a page
// left open for hours) is pointed at a fresh link before it plays, keeping its position.
// True when the link changed.
function renewAudioSrc(el) {
  const next = el ? renewAudioUrl(el.getAttribute('src')) : null;
  if (!next) return false;
  const time = el.currentTime || 0;
  el.src = next;
  if (time > 0) {
    el.addEventListener('loadedmetadata', () => { try { el.currentTime = time; } catch { /* ignore */ } }, { once: true });
  }
  return true;
}

// A player failed: if only its link's token had run out, retry with a fresh link (and keep playing
// when it is the one the controls drive). False when the failure is something else.
export function retryExpiredAudio(el) {
  if (!renewAudioSrc(el)) return false;
  if (Q.el === el) el.play().catch(() => {});
  return true;
}

function showBottomAudioBar() {
  const state = store.getState();
  const r = state.recordings.list.find(x => x.id === Q.id);
  const c = r || state.calls.list.find(x => x.recordingId === Q.id);
  const title = c ? `${c.agent || 'Call'} → ${c.client || formatPhone(c.phone)}` : 'Call Recording';
  // Card recordings already show their own seek bar, so the dock only shows the buttons
  store.dispatch(audioBarShown({ title, showNative: !!Q.dock && Q.el === Q.dock }));
}

export function syncAudioControls() {
  const list = queueList();
  const idx = list.indexOf(Q.id);
  const playing = !!(Q.el && !Q.el.paused && !Q.el.ended);
  const cur = store.getState().ui.audio;
  if (cur.playing === playing && cur.idx === idx && cur.total === list.length) return;
  store.dispatch(audioControlsSynced({ playing, idx, total: list.length }));
}

export function onAnyAudioPlay(currentAudio) {
  // Started from the player's own controls with an out-of-date link: switch to a fresh link and play
  // again (this handler runs once more for that play)
  if (renewAudioSrc(currentAudio)) {
    currentAudio.play().catch(() => {});
    return;
  }
  document.querySelectorAll('audio').forEach(el => {
    if (el !== currentAudio && !el.paused) {
      try { el.pause(); } catch { /* ignore */ }
    }
  });
  if (currentAudio && currentAudio.dataset && currentAudio.dataset.recId) {
    Q.source = 'rec';
    Q.id = currentAudio.dataset.recId;
    Q.el = currentAudio;
    showBottomAudioBar();
  }
  syncAudioControls();
}

export function playCallAudioDirect(recId, source) {
  if (!recId) {
    notify('⚠️ NO VOICE RECORDING CAPTURED FOR THIS CALL');
    return;
  }
  // Recordings page: play the card's own player when it is on screen
  const cardAudio = source === 'rec' ? findCardAudio(recId) : null;
  if (cardAudio) {
    Q.source = 'rec';
    Q.id = String(recId);
    Q.el = cardAudio;
    try { cardAudio.scrollIntoView({ behavior: 'smooth', block: 'nearest' }); } catch { /* ignore */ }
    renewAudioSrc(cardAudio);
    cardAudio.play().catch(() => notify('⚠️ RECORDING AUDIO COULD NOT BE PLAYED'));
    showBottomAudioBar();
    syncAudioControls();
    return;
  }

  // Otherwise stream through the docked bottom player
  const player = Q.dock;
  if (!player) return;
  Q.source = source === 'rec' ? 'rec' : 'log';
  Q.id = String(recId);
  Q.el = player;
  showBottomAudioBar();
  player.src = recordingAudioUrl(recId);
  player.onerror = () => {
    if (retryExpiredAudio(player)) return;
    notify('⚠️ RECORDING AUDIO FILE NOT FOUND ON SERVER');
    syncAudioControls();
  };
  player.play().catch(() => {});
  syncAudioControls();
}

export function audioCtlToggle() {
  const el = Q.el;
  if (!el) return;
  if (el.paused || el.ended) {
    renewAudioSrc(el);
    el.play().catch(() => notify('⚠️ RECORDING AUDIO COULD NOT BE PLAYED'));
  } else el.pause();
}

export function audioCtlStep(delta) {
  const list = queueList();
  const idx = list.indexOf(Q.id);
  const nextId = list[idx + delta];
  if (idx < 0 || !nextId) return;
  if (Q.el) { try { Q.el.pause(); } catch { /* ignore */ } }
  if (Q.source === 'rec') {
    const el = findCardAudio(nextId);
    if (el) { try { el.currentTime = 0; } catch { /* ignore */ } }
  }
  playCallAudioDirect(nextId, Q.source);
}

export function closeBottomAudioBar() {
  if (Q.el) {
    try { Q.el.pause(); } catch { /* ignore */ }
  }
  store.dispatch(audioBarHidden());
}

// A playing recording card left the list (new filter / page / data): keep playing in the dock
export function handoffToDock(recId, time) {
  const player = Q.dock;
  if (!player) return;
  Q.source = 'rec';
  Q.id = String(recId);
  Q.el = player;
  player.src = recordingAudioUrl(recId);
  player.addEventListener('loadedmetadata', () => { try { player.currentTime = time; } catch { /* ignore */ } }, { once: true });
  player.play().catch(() => {});
  showBottomAudioBar();
  syncAudioControls();
}

// The card element that is currently driven by the dock controls (or null)
export function currentAudioEl() { return Q.el; }

export function seekCurrentAudio(time) {
  const el = Q.el;
  if (!el || !Number.isFinite(time)) return;
  try { el.currentTime = Math.max(0, time); } catch { /* ignore */ }
}

export function stopAllAudio() {
  document.querySelectorAll('audio').forEach(a => {
    try { a.pause(); } catch { /* ignore */ }
  });
  if (Q.dock) { Q.dock.removeAttribute('src'); try { Q.dock.load(); } catch { /* ignore */ } }
  Q.source = null; Q.id = null; Q.el = null;
  store.dispatch(audioBarHidden());
}
