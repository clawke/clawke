const test = require('node:test');
const assert = require('node:assert/strict');

test('gateway model and skill query timeout is one minute', async () => {
  const listener = require('../dist/upstream/gateway-listener.js');

  assert.equal(listener.GATEWAY_QUERY_TIMEOUT_MS, 60_000);
});

test('gateway SkillHub install status is converted to client payload', async () => {
  const listener = require('../dist/upstream/gateway-listener.js');

  assert.deepEqual(listener.toSkillHubInstallStatusPayload({
    type: 'skillhub_install_status',
    install_id: 'skillhub_1',
    account_id: 'hermes',
    status: 'installing',
    slug: 'weather',
  }), {
    payload_type: 'skillhub_install_status',
    installId: 'skillhub_1',
    account_id: 'hermes',
    status: 'installing',
    slug: 'weather',
  });
});

test('gateway local_to_server is based on loopback remote address only', async () => {
  const listener = require('../dist/upstream/gateway-listener.js');

  assert.equal(listener.isLoopbackAddress('127.0.0.1'), true);
  assert.equal(listener.isLoopbackAddress('::1'), true);
  assert.equal(listener.isLoopbackAddress('::ffff:127.0.0.1'), true);
  assert.equal(listener.isLoopbackAddress('192.168.0.7'), false);
});
