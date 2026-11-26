// The Redux store: state only. Every slice holds plain reducers; API calls live in utils/actions
// and update the store with ordinary actions (no thunks).
import { configureStore } from '@reduxjs/toolkit';
import authReducer from './slices/authSlice';
import callsReducer from './slices/callsSlice';
import dashboardReducer from './slices/dashboardSlice';
import demosReducer from './slices/demosSlice';
import leaderboardReducer from './slices/leaderboardSlice';
import leadsReducer from './slices/leadsSlice';
import recordingsReducer from './slices/recordingsSlice';
import notificationsReducer from './slices/notificationsSlice';
import phoneHealthReducer from './slices/phoneHealthSlice';
import uiReducer from './slices/uiSlice';
import userDetailReducer from './slices/userDetailSlice';
import usersReducer from './slices/usersSlice';

export const store = configureStore({
  reducer: {
    auth: authReducer,
    users: usersReducer,
    calls: callsReducer,
    leads: leadsReducer,
    recordings: recordingsReducer,
    notifications: notificationsReducer,
    dashboard: dashboardReducer,
    leaderboard: leaderboardReducer,
    demos: demosReducer,
    userDetail: userDetailReducer,
    phoneHealth: phoneHealthReducer,
    ui: uiReducer,
  },
  // No thunk middleware: only plain actions reach the store.
  // Rows carry Date objects (call / lead / recording times) and lists run to thousands of leads,
  // so the dev-only serializable / immutability checks are switched off.
  middleware: (getDefault) => getDefault({ thunk: false, serializableCheck: false, immutableCheck: false }),
});

export default store;
