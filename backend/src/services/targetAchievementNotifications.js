const Employee = require('../models/Employee');
const Notification = require('../models/Notification');
const {
  aggregateCallStats,
  findCallerStats,
  getPeriodRange,
} = require('./callStats');
const { anyPhoneRegex, exactNameRegex } = require('../utils/common');

const IST_OFFSET_MS = 330 * 60 * 1000;

async function createTargetAchievementNotification(employee) {
  if (!employee || employee.role === 'admin') return false;

  const now = new Date();
  const range = getPeriodRange({ period: 'today' }, now);
  const callerRefs = [{ callerId: employee.id }];
  const phonePattern = employee.phone ? anyPhoneRegex([employee.phone]) : null;
  if (phonePattern) callerRefs.push({ callerPhone: phonePattern });
  if (employee.name) callerRefs.push({ callerName: exactNameRegex(employee.name) });

  const stats = await aggregateCallStats({
    timestamp: range,
    $or: callerRefs,
  });
  const completedCalls = (findCallerStats(stats.byCaller, employee) || {}).totalCalls || 0;
  const dailyTarget = Number.isFinite(employee.dailyTarget) && employee.dailyTarget > 0
    ? employee.dailyTarget
    : Employee.DEFAULT_DAILY_TARGET;
  if (completedCalls < dailyTarget) return false;

  const dateKey = new Date(now.getTime() + IST_OFFSET_MS).toISOString().slice(0, 10);
  const notificationId = `target_achievement_${employee.id}_${dateKey}`;
  let result;
  try {
    result = await Notification.updateOne(
      { id: notificationId },
      {
        $setOnInsert: {
          id: notificationId,
          recipientId: employee.id,
          recipientPhone: employee.phone || '',
          recipientName: employee.name || '',
          senderName: 'Telesales',
          senderRole: 'system',
          title: 'Daily target achieved',
          message: `Congratulations! You achieved your daily target of ${dailyTarget} calls. Great work!`,
          isRead: false,
        },
      },
      { upsert: true }
    );
  } catch (err) {
    if (err.code === 11000) return false;
    throw err;
  }

  if (result.upsertedCount > 0) {
    console.info(`[notification] target achieved callerId=${employee.id} calls=${completedCalls} target=${dailyTarget}`);
    return true;
  }
  return false;
}

module.exports = { createTargetAchievementNotification };
