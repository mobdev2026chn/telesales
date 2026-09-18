// Notifications for the signed-in user only (absolute paths).
const express = require('express');
const Notification = require('../models/Notification');
const { last10, isObjectId, exactNameRegex, phoneRegex, serverError } = require('../utils/common');

const router = express.Router();

// Filter for "my notifications". Token: by recipientId, plus older rows (no recipientId) addressed to
// my exact phone (last 10 digits) or exact name. Legacy client: exact phone / exact name it sends.
// Returns null when the recipient cannot be identified (-> nothing is returned or modified).
function recipientFilter(req, src) {
  let phone = '';
  let name = '';
  const or = [];
  if (req.user) {
    or.push({ recipientId: req.user.id });
    phone = req.user.phone || '';
    name = req.user.name || '';
  } else {
    phone = typeof src.phone === 'string' ? src.phone : '';
    name = typeof src.name === 'string' ? src.name : '';
  }
  const legacyOr = [];
  const pr = last10(phone).length === 10 ? phoneRegex(phone) : null;
  if (pr) legacyOr.push({ recipientPhone: pr });
  if (name && name.trim()) legacyOr.push({ recipientName: exactNameRegex(name) });
  if (legacyOr.length) or.push({ recipientId: { $in: [null, ''] }, $or: legacyOr });
  return or.length ? { $or: or } : null;
}

router.get(['/api/user/notifications', '/api/notifications'], async (req, res) => {
  try {
    const filter = recipientFilter(req, req.query);
    if (!filter) return res.json({ success: true, unreadCount: 0, notifications: [] });
    const [notifications, unreadCount] = await Promise.all([
      Notification.find(filter).sort({ createdAt: -1 }).limit(50).lean(),
      Notification.countDocuments({ $and: [filter, { isRead: false }] }),
    ]);
    res.json({ success: true, unreadCount, notifications });
  } catch (err) {
    serverError(res, err, 'notifications.list');
  }
});

router.post(['/api/user/notifications/read-all', '/api/notifications/read-all'], async (req, res) => {
  try {
    const filter = recipientFilter(req, { ...req.query, ...(req.body || {}) });
    if (!filter) return res.json({ success: true, modified: 0, message: 'Nothing to mark' });
    const r = await Notification.updateMany({ $and: [filter, { isRead: false }] }, { $set: { isRead: true } });
    res.json({ success: true, modified: r.modifiedCount, message: 'All notifications marked as read' });
  } catch (err) {
    serverError(res, err, 'notifications.readAll');
  }
});

router.post(['/api/user/notifications/:id/read', '/api/notifications/:id/read'], async (req, res) => {
  try {
    const id = String(req.params.id);
    const idQuery = { $or: [{ id }, ...(isObjectId(id) ? [{ _id: id }] : [])] };
    const filter = recipientFilter(req, { ...req.query, ...(req.body || {}) });
    // Legacy clients that send no identity may still mark a single notification by its id (old behaviour)
    const query = filter ? { $and: [idQuery, filter] } : idQuery;
    const notification = await Notification.findOneAndUpdate(query, { $set: { isRead: true } }, { new: true }).lean();
    if (!notification) return res.status(404).json({ success: false, message: 'Notification not found' });
    res.json({ success: true, notification });
  } catch (err) {
    serverError(res, err, 'notifications.read');
  }
});

module.exports = router;
module.exports.recipientFilter = recipientFilter;
