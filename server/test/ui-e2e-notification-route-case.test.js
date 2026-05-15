const assert = require('node:assert/strict');
const { readFileSync } = require('node:fs');
const { join } = require('node:path');
const test = require('node:test');

const root = join(__dirname, '..', '..');
const casePath = join(
  root,
  'test',
  'ui-e2e',
  'test-cases',
  'p0-notification-click-route.json',
);
const harness = readFileSync(
  join(root, 'client', 'integration_test', 'ui_e2e_app_test.dart'),
  'utf8',
);

test('notification click route case simulates native notification tap payload', () => {
  const testCase = JSON.parse(readFileSync(casePath, 'utf8'));
  const step = testCase.steps.find((item) => item.action === 'simulate_remote_push');

  assert.equal(testCase.id, 'p0-notification-click-route');
  assert.equal(step.event_type, 'notification_tap');
  assert.match(harness, /'event_type': step\['event_type'\] as String\? \?\? 'notification_tap'/);
});
