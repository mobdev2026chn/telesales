// DEMO BOOKINGS (booked by callers in the app; slots blocked here show red in the app)
import { DEMO_HISTORY_DAYS, DEMO_SLOT_MIN } from '../../data/constants';
import { selectScope } from '../../redux/selectors';
import { demosFailed, demosLoaded, demosRequested } from '../../redux/slices/demosSlice';
import store from '../../redux/store';
import { mapDemo, mapDemoBlock } from '../mappers';
import { notify } from '../notify';
import { demoService } from '../services';

const { dispatch, getState } = store;

export async function fetchDemos() {
  dispatch(demosRequested());
  try {
    const since = new Date(Date.now() - DEMO_HISTORY_DAYS * 24 * 60 * 60 * 1000).toISOString();
    const [json, blocks] = await Promise.all([
      demoService.list(selectScope(getState()).scopeParam),
      demoService.blocks(since).catch(() => null),
    ]);
    dispatch(demosLoaded({
      list: (json.demos || []).map(mapDemo).filter(d => d.id),
      blocks: blocks ? (blocks.blocks || []).map(mapDemoBlock).filter(b => b.id && b.at) : null,
    }));
  } catch (e) {
    dispatch(demosFailed(e.message));
  }
}

// Block / unblock / cancel, then reload the bookings
async function demoSlotAction(call, okMsg) {
  try {
    await call();
    notify(okMsg);
  } catch (e) {
    notify(`⚠️ ${e.message}`);
  }
  await fetchDemos();
}

export function blockDemoSlot(teamLeaderId, scheduledAt, label) {
  return demoSlotAction(
    () => demoService.block({ teamLeaderId, scheduledAt: scheduledAt.toISOString(), durationMinutes: DEMO_SLOT_MIN }),
    `SLOT BLOCKED · ${label}`,
  );
}

export function unblockDemoSlot(id) {
  return demoSlotAction(() => demoService.unblock(id), 'SLOT UNBLOCKED');
}

export function cancelDemoBooking(id) {
  return demoSlotAction(() => demoService.cancel(id), 'DEMO CANCELLED');
}

// Send a demo back to the caller who booked it to pick a new slot (the server notifies them)
export function rescheduleDemoBooking(id) {
  return demoSlotAction(() => demoService.reschedule(id), 'SENT TO CALLER TO RESCHEDULE');
}
