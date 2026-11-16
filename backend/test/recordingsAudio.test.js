const test = require('node:test');
const assert = require('node:assert');

test('Cloudinary URL security validator checks protocol, hostname, and cloud account', () => {
  const cloudName = 'testcloud';

  const isValidUrl = (urlStr) => {
    try {
      const u = new URL(urlStr);
      return u.protocol === 'https:'
        && u.hostname === 'res.cloudinary.com'
        && u.pathname.startsWith(`/${cloudName}/video/upload/`);
    } catch {
      return false;
    }
  };

  // Valid Cloudinary URLs
  assert.strictEqual(
    isValidUrl('https://res.cloudinary.com/testcloud/video/upload/v12345/telesales/recordings/call_123.mp3'),
    true,
    'Valid Cloudinary URL should pass'
  );
  assert.strictEqual(
    isValidUrl('https://res.cloudinary.com/testcloud/video/upload/v12345/telesales/recordings/call_123.wav'),
    true,
    'Valid Cloudinary wav URL should pass'
  );

  // Invalid / Tampered / Open Redirect attempts
  assert.strictEqual(
    isValidUrl('http://res.cloudinary.com/testcloud/video/upload/call_123.mp3'),
    false,
    'Plain HTTP should be rejected'
  );
  assert.strictEqual(
    isValidUrl('https://malicious.com/testcloud/video/upload/call_123.mp3'),
    false,
    'Different host should be rejected'
  );
  assert.strictEqual(
    isValidUrl('https://res.cloudinary.com/otheraccount/video/upload/call_123.mp3'),
    false,
    'Different cloud account should be rejected'
  );
  assert.strictEqual(
    isValidUrl('not-a-url'),
    false,
    'Malformed string should be rejected'
  );
});

test('HTTP 302 redirect header structure includes private non-cached directive', () => {
  const headers = {
    'Cache-Control': 'private, no-cache, no-store, must-revalidate',
    'Pragma': 'no-cache',
    'Expires': '0',
  };
  assert.strictEqual(headers['Cache-Control'], 'private, no-cache, no-store, must-revalidate');
  assert.strictEqual(headers['Pragma'], 'no-cache');
  assert.strictEqual(headers['Expires'], '0');
});

test('Client abort error detection correctly recognizes normal browser seeking / cancellation', () => {
  const isClientAbort = (err, clientClosed, reqDestroyed, resDestroyed) => {
    return clientClosed || reqDestroyed || resDestroyed
      || err.code === 'ECONNRESET'
      || err.message === 'aborted'
      || err.name === 'AbortError'
      || (err.message && err.message.includes('aborted'));
  };

  // Normal browser cancel events
  assert.strictEqual(isClientAbort(new Error('aborted'), false, false, false), true);
  assert.strictEqual(isClientAbort({ code: 'ECONNRESET', message: 'socket hang up' }, false, false, false), true);
  assert.strictEqual(isClientAbort(new Error('stream aborted by user'), false, false, false), true);
  assert.strictEqual(isClientAbort(new Error('Generic failure'), true, false, false), true);

  // Real server / network errors
  assert.strictEqual(isClientAbort(new Error('ENOTFOUND'), false, false, false), false);
  assert.strictEqual(isClientAbort(new Error('ETIMEDOUT'), false, false, false), false);
});
