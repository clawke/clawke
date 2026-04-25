const assert = require('node:assert/strict');
const { readFileSync } = require('node:fs');
const { join } = require('node:path');
const test = require('node:test');

const root = join(__dirname, '..', '..');
const harness = readFileSync(
  join(root, 'client', 'integration_test', 'ui_e2e_app_test.dart'),
  'utf8',
);

test('UI E2E harness injects server config without touching app preferences', () => {
  assert.doesNotMatch(harness, /SharedPreferences/);
  assert.doesNotMatch(harness, /prefs\.clear\(/);
  assert.doesNotMatch(harness, /setString\('clawke_http_url'/);
  assert.doesNotMatch(harness, /setString\('clawke_ws_url'/);
  assert.match(harness, /serverConfigProvider\.overrideWith/);
  assert.match(harness, /loadFromPrefs: false/);
});
