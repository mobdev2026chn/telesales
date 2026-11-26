import store from '../../redux/store';
import {
  setNotifications,
  setNotificationsPending,
  setNotificationsError,
  markRead,
  markAllRead,
  notificationDeleted,
  notificationsCleared,
} from '../../redux/slices/notificationsSlice';
import { notificationService } from '../services';
import { notify } from '../notify';

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

export async function deleteNotification(id) {
  if (!id) return false;
  try {
    await notificationService.remove(id);
    dispatch(notificationDeleted(id));
    notify('NOTIFICATION DELETED');
    return true;
  } catch (err) {
    console.error(`Failed to delete notification ${id}:`, err?.message || err);
    notify(`⚠️ DELETE FAILED: ${err?.message || 'Could not delete notification'}`);
    return false;
  }
}

export async function clearAllNotifications() {
  try {
    const res = await notificationService.clear();
    dispatch(notificationsCleared());
    notify(`CLEARED ${Number(res.deleted) || 0} NOTIFICATIONS`);
    return true;
  } catch (err) {
    console.error('Failed to clear notifications:', err?.message || err);
    notify(`⚠️ CLEAR FAILED: ${err?.message || 'Could not clear notifications'}`);
    return false;
  }
}

