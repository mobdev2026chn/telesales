// USERS: load the team, today's numbers, add / edit / delete, profile fields and photo
import { setViewAs } from '../../redux/slices/authSlice';
import {
  todayFailed, todayLoaded, userMerged, userPatched, userRemoved, usersFailed, usersLoaded,
} from '../../redux/slices/usersSlice';
import store from '../../redux/store';
import { safeImage } from '../format';
import { linkManagers, mapUser } from '../mappers';
import { notify } from '../notify';
import { statsService, userService } from '../services';

const { dispatch, getState } = store;

export async function fetchUsers() {
  try {
    const json = await userService.list();
    const list = json.users || (Array.isArray(json) ? json : []);
    const users = linkManagers(list.map(mapUser).filter(u => u.id), list);
    dispatch(usersLoaded(users));
    const { viewAsId } = getState().auth;
    if (viewAsId && !users.some(u => u.id === viewAsId)) dispatch(setViewAs(null));
  } catch (e) {
    dispatch(usersFailed(e.message));
  }
}

export async function fetchTodayStats() {
  try {
    const json = await statsService.dashboard('?period=today');
    dispatch(todayLoaded((json.data && json.data.teamMembers) || []));
  } catch (e) {
    dispatch(todayFailed(e.message));
  }
}

// Add / edit from User Management. Resolves to { ok } or { error }.
export async function saveUser(editingId, payload) {
  try {
    if (editingId) {
      await userService.update(editingId, payload);
      notify(`✓ UPDATED ${payload.name.toUpperCase()}`);
    } else {
      await userService.create(payload);
      notify(`✓ ADDED ${payload.name.toUpperCase()}`);
    }
    await fetchUsers();
    return { ok: true };
  } catch (err) {
    return { error: err.network ? 'Could not reach the server — nothing was saved.' : (err.message || 'Save failed.') };
  }
}

export async function deleteUser(user) {
  try {
    await userService.remove(user.id);
    dispatch(userRemoved(user.id));
    notify(`✓ ${user.name.toUpperCase()} DELETED`);
  } catch (e) {
    notify(`⚠️ DELETE FAILED: ${e.message}`);
  }
}

export async function approveUser(user) {
  try {
    await userService.approve(user.id);
    await fetchUsers();
    notify(`✓ ${user.name.toUpperCase()} APPROVED & ACTIVATED`);
  } catch (e) {
    notify(`⚠️ APPROVAL FAILED: ${e.message}`);
  }
}

export async function rejectUser(user) {
  try {
    await userService.reject(user.id);
    await fetchUsers();
    notify(`✓ ${user.name.toUpperCase()} REACTIVATION REJECTED`);
  } catch (e) {
    notify(`⚠️ REJECT FAILED: ${e.message}`);
  }
}

// Profile page: reports-to / daily target
export async function updateUserFields(user, fields, okMsg) {
  try {
    const json = await userService.update(user.id, fields);
    if (json.user) {
      dispatch(userMerged(mapUser(json.user)));
    } else {
      const patch = {};
      if ('dailyTarget' in fields) patch.target = fields.dailyTarget;
      if ('managerId' in fields) patch.mgr = fields.managerId || null;
      dispatch(userPatched({ id: user.id, fields: patch }));
    }
    notify(okMsg);
  } catch (e) {
    notify(`⚠️ NOT SAVED: ${e.message}`);
  }
}

export async function uploadUserPhoto(userId, photoBase64, isSelf) {
  const body = { photoBase64 };
  if (userId && !isSelf) body.userId = userId;
  try {
    const result = await userService.uploadPhoto(body);
    const avatarUrl = (result.user && result.user.avatarUrl) || '';
    dispatch(userPatched({ id: userId, fields: { photoBase64: '', avatarUrl: safeImage(avatarUrl) } }));
    notify(photoBase64 === '' ? 'PROFILE PHOTO REMOVED' : 'PROFILE PHOTO UPDATED');
  } catch (err) {
    notify(`⚠️ PHOTO NOT SAVED: ${err.message}`);
  }
}
