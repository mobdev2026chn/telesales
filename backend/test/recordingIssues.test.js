// Run with: npm test   (Node's built-in test runner, no database needed)
const test = require('node:test');
const assert = require('node:assert');
const { issueOf } = require('../src/routes/diagnostics');

test("the phone's own recording is never a problem", () => {
  assert.strictEqual(issueOf({ result: 'builtin', talkSeconds: 120 }), null);
});

test('short calls raise no alert (wrong number, hang-up)', () => {
  assert.strictEqual(issueOf({ result: 'silent', talkSeconds: 4 }), null);
  assert.strictEqual(issueOf({ result: 'ok', talkSeconds: 9 }), null);
});

test('a silent recording that was discarded is a lost call, with the Accessibility reason', () => {
  const issue = issueOf({ result: 'silent', talkSeconds: 45, accessibilityEnabled: false });
  assert.strictEqual(issue.kind, 'lost');
  assert.match(issue.reason, /Accessibility/);
});

test('no recording at all because the phone recorder missed the call', () => {
  const issue = issueOf({ result: 'not_recorded', talkSeconds: 30, note: 'skipped: built-in recorder trusted' });
  assert.strictEqual(issue.kind, 'lost');
  assert.match(issue.reason, /auto-record/);
});

test('a mic-only upload is reported, and says whether the loudspeaker was on', () => {
  const missing = issueOf({ result: 'ok', talkSeconds: 60, speaker: '' });
  assert.strictEqual(missing.kind, 'mic_only');
  assert.match(missing.reason, /probably missing/);

  const onSpeaker = issueOf({ result: 'ok', talkSeconds: 60, speaker: 'on' });
  assert.strictEqual(onSpeaker.kind, 'mic_only');
  assert.match(onSpeaker.reason, /should be audible/);
});

test('"Phone by Google" is named as the reason the phone recording was not found', () => {
  const issue = issueOf({ result: 'ok', talkSeconds: 60, dialerPackage: 'com.google.android.dialer' });
  assert.match(issue.reason, /Phone by Google/);
});
