import store from '../../redux/store';
import {
  setNotifications,
  setNotificationsPending,
  setNotificationsError,
  markRead,
  markAllRead,
} from '../../redux/slices/notificationsSlice';
import { notificationService } from '../services';

const { dispatch } = store;

export async function fetchNotifications() {
  dispatch(setNotificationsPending());
  try {
    const res = await notificationService.list();
    if (res && res.success) {
      dispatch(setNotifications({
        notifications: Array.isArray(res.notifications) ? res.notifications : [],
        unreadCount: typeof res.unreadCount === 'number' ? res.unreadCount : 0,
      }));
    }
  } catch (err) {
    console.error('Failed to fetch notifications:', err?.message || err);
    dispatch(setNotificationsError(err?.message || 'Failed to fetch notifications'));
  }
}

export async function markNotificationAsRead(id) {
  if (!id) return;
  dispatch(markRead(id));
  try {
    await notificationService.markRead(id);
  } catch (err) {
    console.error(`Failed to mark notification ${id} as read:`, err?.message || err);
  }
}

export async function markAllNotificationsAsRead() {
  dispatch(markAllRead());
  try {
    await notificationService.readAll();
  } catch (err) {
    console.error('Failed to mark all notifications as read:', err?.message || err);
  }
}

