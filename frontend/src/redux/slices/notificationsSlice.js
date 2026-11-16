import { createSlice } from '@reduxjs/toolkit';

const initialState = {
  list: [],
  unreadCount: 0,
  loaded: false,
  pending: false,
  error: null,
  drawerOpen: false,
};

const notificationsSlice = createSlice({
  name: 'notifications',
  initialState,
  reducers: {
    setNotifications(state, { payload }) {
      state.list = Array.isArray(payload.notifications) ? payload.notifications : [];
      state.unreadCount = typeof payload.unreadCount === 'number' ? payload.unreadCount : 0;
      state.loaded = true;
      state.pending = false;
      state.error = null;
    },
    notificationAdded(state, { payload }) {
      if (!payload) return;
      const targetId = payload.id || payload._id;
      const exists = state.list.some(n => (n.id && n.id === targetId) || (n._id && n._id === targetId));
      if (!exists) {
        state.list.unshift({ ...payload, id: targetId });
        if (!payload.isRead) state.unreadCount += 1;
      }
    },
    markRead(state, { payload: id }) {
      const item = state.list.find(n => (n.id && n.id === id) || (n._id && n._id === id));
      if (item && !item.isRead) {
        item.isRead = true;
        state.unreadCount = Math.max(0, state.unreadCount - 1);
      }
    },
    markAllRead(state) {
      state.list.forEach(n => { n.isRead = true; });
      state.unreadCount = 0;
    },
    setNotificationsDrawer(state, { payload }) {
      state.drawerOpen = Boolean(payload);
    },
    toggleNotificationsDrawer(state) {
      state.drawerOpen = !state.drawerOpen;
    },
    setNotificationsPending(state) {
      state.pending = true;
      state.error = null;
    },
    setNotificationsError(state, { payload }) {
      state.pending = false;
      state.error = payload || 'Failed to load notifications';
    },
  },
});

export const {
  setNotifications,
  notificationAdded,
  markRead,
  markAllRead,
  setNotificationsDrawer,
  toggleNotificationsDrawer,
  setNotificationsPending,
  setNotificationsError,
} = notificationsSlice.actions;

export default notificationsSlice.reducer;
