// PHONE HEALTH: is every agent's phone recording calls? (GET /admin/phone-health, numbers from the server)
import { selectPhKey } from '../../redux/selectors';
import { phFailed, phRequested, phSucceeded } from '../../redux/slices/phoneHealthSlice';
import store from '../../redux/store';
import { recordingService } from '../services';

const { dispatch, getState } = store;

export async function fetchPhoneHealth() {
  const key = selectPhKey(getState());
  dispatch(phRequested(key));
  try {
    const json = await recordingService.phoneHealth(key);
    dispatch(phSucceeded({
      key,
      data: {
        agents: Array.isArray(json.agents) ? json.agents : [],
        days: Number(json.days) || null,
        since: json.since || null,
        // Admin-only fields: null when the server left them out
        legacyGraceEnabled: typeof json.legacyGraceEnabled === 'boolean' ? json.legacyGraceEnabled : null,
        oldAppClients: Array.isArray(json.oldAppClients) ? json.oldAppClients : null,
      },
    }));
  } catch (err) {
    const error = err.status === 404 ? 'Phone health is not available on this server yet' : err.message;
    dispatch(phFailed({ key, error }));
  }
}
