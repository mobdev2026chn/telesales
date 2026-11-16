// Global toast from anywhere (utils, actions, components)
import store from '../redux/store';
import { showToast } from '../redux/slices/uiSlice';

export function notify(msg) {
  if (!msg) return;
  store.dispatch(showToast(msg));
}
