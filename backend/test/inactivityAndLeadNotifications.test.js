const test = require('node:test');
const assert = require('node:assert');
const Employee = require('../src/models/Employee');
const CallLog = require('../src/models/CallLog');
const Notification = require('../src/models/Notification');
const { checkCallerInactivity, lastAlertMap } = require('../src/services/inactivityAlerts');
const { sendLeadStatusChangeNotification } = require('../src/services/leadNotifications');

test('sendLeadStatusChangeNotification returns null if status has not changed', async () => {
  const result = await sendLeadStatusChangeNotification({
    lead: { id: 'lead_1', name: 'John Doe', status: 'interested' },
    oldStatus: 'interested',
    newStatus: 'interested',
    user: { id: 'emp_1', name: 'Praveen', role: 'caller' },
  });
  assert.strictEqual(result, null);
});

test('sendLeadStatusChangeNotification creates Admin and Caller notifications on status change', async () => {
  const created = [];
  const originalCreate = Notification.create;
  Notification.create = async (doc) => {
    created.push(doc);
    return doc;
  };

  const emitted = [];
  const fakeIo = {
    to: (room) => ({
      emit: (event, payload) => {
        emitted.push({ room, event, payload });
      },
    }),
  };

  const req = {
    app: {
      get: (k) => (k === 'io' ? fakeIo : null),
    },
  };

  try {
    const result = await sendLeadStatusChangeNotification({
      req,
      lead: { id: 'lead_100', name: 'Siva Tech', phone: '9876543210', assignedCallerId: 'caller_1' },
      oldStatus: 'new',
      newStatus: 'interested',
      user: { id: 'caller_1', name: 'Kabilan', phone: '8637629228', role: 'caller' },
    });

    assert.ok(result);
    assert.strictEqual(created.length, 2, 'Should create 2 notifications (Admin + Caller)');

    const adminNotif = created.find((n) => n.recipientId === 'ADMIN');
    assert.ok(adminNotif, 'Should create admin notification');
    assert.ok(adminNotif.title.includes('interested'));
    assert.ok(adminNotif.message.includes('Kabilan'));
    assert.ok(adminNotif.message.includes('Siva Tech'));

    const callerNotif = created.find((n) => n.recipientId === 'caller_1');
    assert.ok(callerNotif, 'Should create caller notification');
    assert.ok(callerNotif.title.includes('Siva Tech'));
    assert.ok(callerNotif.message.includes('interested'));

    assert.ok(emitted.some((e) => e.room === 'admin:global'), 'Should emit to admin:global');
  } finally {
    Notification.create = originalCreate;
  }
});

test('checkCallerInactivity alerts for inactive caller (>15 mins without calls)', async () => {
  lastAlertMap.clear();

  const now = Date.now();
  const inactiveLogin = new Date(now - 20 * 60 * 1000); // 20 mins ago

  const origEmpFind = Employee.find;
  const origCallLogFindOne = CallLog.findOne;
  const origNotifCreate = Notification.create;

  Employee.find = () => ({
    lean: async () => [
      {
        id: 'caller_inactive_1',
        name: 'Inactive Caller',
        phone: '9988776655',
        role: 'caller',
        lastLoginAt: inactiveLogin,
        loggedOutAt: null,
        presenceUpdatedAt: new Date(now - 60 * 1000), // active within 1 min
        appInForeground: true,
      },
    ],
  });

  // No call made yet
  CallLog.findOne = () => ({
    sort: () => ({
      lean: async () => null,
    }),
  });

  const createdNotifs = [];
  Notification.create = async (doc) => {
    createdNotifs.push(doc);
    return doc;
  };

  const emitted = [];
  const fakeIo = {
    to: (room) => ({
      emit: (event, payload) => {
        emitted.push({ room, event, payload });
      },
    }),
  };

  try {
    const alerts = await checkCallerInactivity(fakeIo);
    assert.strictEqual(alerts.length, 1, 'Should generate 1 alert');
    assert.strictEqual(alerts[0].callerId, 'caller_inactive_1');
    assert.ok(alerts[0].inactiveMinutes >= 15);

    // Verify notifications created
    assert.strictEqual(createdNotifs.length, 2, 'Admin and caller notifications created');
    assert.ok(createdNotifs.some((n) => n.recipientId === 'ADMIN'));
    assert.ok(createdNotifs.some((n) => n.recipientId === 'caller_inactive_1'));

    // Verify cooldown prevents duplicate alert on subsequent check
    const secondCheckAlerts = await checkCallerInactivity(fakeIo);
    assert.strictEqual(secondCheckAlerts.length, 0, 'Should not generate alert while under cooldown');
  } finally {
    Employee.find = origEmpFind;
    CallLog.findOne = origCallLogFindOne;
    Notification.create = origNotifCreate;
    lastAlertMap.clear();
  }
});

test('checkCallerInactivity skips caller who spoke recently (<15 mins ago)', async () => {
  lastAlertMap.clear();

  const now = Date.now();
  const recentCallTime = new Date(now - 5 * 60 * 1000); // 5 mins ago

  const origEmpFind = Employee.find;
  const origCallLogFindOne = CallLog.findOne;

  Employee.find = () => ({
    lean: async () => [
      {
        id: 'caller_active_1',
        name: 'Active Caller',
        phone: '9988776654',
        role: 'caller',
        lastLoginAt: new Date(now - 60 * 60 * 1000),
        loggedOutAt: null,
        presenceUpdatedAt: new Date(now - 30 * 1000),
      },
    ],
  });

  CallLog.findOne = () => ({
    sort: () => ({
      lean: async () => ({
        timestamp: recentCallTime,
        durationSeconds: 120, // 2-min call
      }),
    }),
  });

  try {
    const alerts = await checkCallerInactivity(null);
    assert.strictEqual(alerts.length, 0, 'Active caller should not trigger inactivity alert');
  } finally {
    Employee.find = origEmpFind;
    CallLog.findOne = origCallLogFindOne;
  }
});

test('checkCallerInactivity skips caller who is on break', async () => {
  lastAlertMap.clear();

  const now = Date.now();
  const origEmpFind = Employee.find;

  Employee.find = () => ({
    lean: async () => [
      {
        id: 'caller_on_break',
        name: 'Break Caller',
        phone: '9988776653',
        role: 'caller',
        lastLoginAt: new Date(now - 30 * 60 * 1000),
        loggedOutAt: null,
        breakType: 'Lunch',
        breakStartedAt: new Date(now - 10 * 60 * 1000), // on lunch break started 10m ago
      },
    ],
  });

  try {
    const alerts = await checkCallerInactivity(null);
    assert.strictEqual(alerts.length, 0, 'Caller on break should not trigger alert');
  } finally {
    Employee.find = origEmpFind;
  }
});
