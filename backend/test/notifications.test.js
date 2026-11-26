const test = require('node:test');
const assert = require('node:assert');
const { recipientFilter, notificationIdFilter } = require('../src/routes/notifications');

test('recipientFilter includes ADMIN and broadcast recipients for admin user', () => {
  const req = {
    user: {
      id: 'emp_admin_123',
      role: 'admin',
      phone: '9876543210',
      name: 'Admin User',
    },
  };
  const filter = recipientFilter(req, {});
  assert.ok(filter && filter.$or, 'filter should have an $or array');

  const recipients = filter.$or.map(clause => clause.recipientId).filter(Boolean);
  assert.ok(recipients.includes('emp_admin_123'), 'should include user id');
  assert.ok(recipients.includes('ADMIN'), 'should include ADMIN');
  assert.ok(recipients.includes('admin'), 'should include admin');
});

test('recipientFilter includes ADMIN for manager user', () => {
  const req = {
    user: {
      id: 'emp_mgr_456',
      role: 'manager',
      phone: '9876543211',
      name: 'Manager User',
    },
  };
  const filter = recipientFilter(req, {});
  assert.ok(filter && filter.$or);
  const recipients = filter.$or.map(clause => clause.recipientId).filter(Boolean);
  assert.ok(recipients.includes('ADMIN'), 'manager should also receive ADMIN notifications');
});

test('recipientFilter restricts caller user from viewing global ADMIN notifications', () => {
  const req = {
    user: {
      id: 'emp_caller_789',
      role: 'caller',
      phone: '9876543212',
      name: 'Caller User',
    },
  };
  const filter = recipientFilter(req, {});
  assert.ok(filter && filter.$or);
  const recipients = filter.$or.map(clause => clause.recipientId).filter(Boolean);
  assert.strictEqual(recipients.includes('ADMIN'), false, 'caller should not receive global ADMIN alerts');
  assert.ok(recipients.includes('emp_caller_789'), 'caller receives their own notifications');
});

test('recipientFilter returns null when no user or identity is supplied', () => {
  const filter = recipientFilter({}, {});
  assert.strictEqual(filter, null);
});

test('notificationIdFilter scopes an individual delete to the signed-in recipient', () => {
  const req = { user: { id: 'emp_caller_789', role: 'caller', phone: '', name: '' } };
  const filter = notificationIdFilter(req, 'notif_123', {});

  assert.ok(filter && filter.$and);
  assert.deepStrictEqual(filter.$and[0], { $or: [{ id: 'notif_123' }] });
  assert.deepStrictEqual(filter.$and[1], { $or: [{ recipientId: 'emp_caller_789' }] });
});

test('notificationIdFilter refuses deletes when the recipient is unknown', () => {
  assert.strictEqual(notificationIdFilter({}, 'notif_123', {}), null);
});

