const test = require('node:test');
const assert = require('node:assert');
const { healthVerdict, healthSince } = require('../src/routes/diagnostics');

const base = {
  autoRecordEnabled: true,
  connectedCalls: 10,
  recordedPercent: 100,
  recordings: 10,
  micOnly: 0,
  issues: { lost: 0, micOnly: 0 },
  oldAppSeenAt: null,
  device: { phone: 'Samsung A24', accessibilityEnabled: true },
};

test('a phone recording every call is OK', () => {
  assert.deepStrictEqual(healthVerdict(base), { status: 'ok', statusReasons: [] });
});

test('recording switched off is a problem', () => {
  const v = healthVerdict({ ...base, autoRecordEnabled: false });
  assert.strictEqual(v.status, 'problem');
  assert.match(v.statusReasons[0], /switched off/);
});

test('under half of connected calls recorded is a problem; under 90% a warning', () => {
  assert.strictEqual(healthVerdict({ ...base, recordedPercent: 40 }).status, 'problem');
  assert.strictEqual(healthVerdict({ ...base, recordedPercent: 80 }).status, 'warning');
  // Too few calls to judge: a warning, never a problem
  assert.strictEqual(healthVerdict({ ...base, connectedCalls: 2, recordedPercent: 0 }).status, 'warning');
});

test('mic-only recordings, old app and missing setup report are warnings', () => {
  assert.strictEqual(healthVerdict({ ...base, micOnly: 2 }).status, 'warning');
  assert.strictEqual(healthVerdict({ ...base, oldAppSeenAt: new Date() }).status, 'warning');
  assert.strictEqual(healthVerdict({ ...base, device: null }).status, 'warning');
});

test('no calls in the period is OK with a note', () => {
  const v = healthVerdict({ ...base, connectedCalls: 0, recordedPercent: null, recordings: 0, device: null });
  assert.deepStrictEqual(v, { status: 'ok', statusReasons: ['No connected calls in this period'] });
});

test('"today" starts at midnight India time', () => {
  // 2026-11-24 03:00 IST = 2026-11-23 21:30 UTC -> today began 2026-11-23 18:30 UTC
  const now = Date.UTC(2026, 10, 23, 21, 30);
  assert.strictEqual(healthSince(1, now).toISOString(), '2026-11-23T18:30:00.000Z');
  assert.strictEqual(healthSince(7, now).getTime(), now - 7 * 86400000);
});
