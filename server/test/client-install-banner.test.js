const assert = require('node:assert/strict');
const test = require('node:test');

const {
  DEFAULT_LOCAL_SERVER_ADDRESS,
  DOWNLOAD_URL,
  RELEASES_URL,
  formatClientInstallBanner,
  formatTerminalTokenLines,
  maskToken,
} = require('../dist/client-install-banner');

test('client install banner is boxed and highlights links when color is enabled', () => {
  const output = formatClientInstallBanner(true).join('\n');

  assert.match(output, /╔════════════════════════════════════════════════════╗/);
  assert.match(output, /Clawke Server is ready/);
  assert.match(output, /Install Clawke Client to connect/);
  assert.match(output, /Local connection:/);
  assert.match(output, new RegExp(`\\x1b\\[1m\\x1b\\[33m${DEFAULT_LOCAL_SERVER_ADDRESS.replace(/[.*+?^${}()|[\]\\]/g, '\\$&')}\\x1b\\[0m`));
  assert.match(output, /Open App Store on your device and search "Clawke"/);
  assert.doesNotMatch(output, /apps\.apple\.com/);
  assert.match(output, new RegExp(`\\x1b\\[1m\\x1b\\[33m${DOWNLOAD_URL.replace(/[.*+?^${}()|[\]\\]/g, '\\$&')}\\x1b\\[0m`));
  assert.match(output, new RegExp(`\\x1b\\[1m\\x1b\\[33m${RELEASES_URL.replace(/[.*+?^${}()|[\]\\]/g, '\\$&')}\\x1b\\[0m`));
});

test('client install banner stays plain when color is disabled', () => {
  const lines = formatClientInstallBanner(false);
  const output = lines.join('\n');

  assert.doesNotMatch(output, /\x1b\[/);
  assert.equal([...lines[1]].length, [...lines[2]].length);
  assert.equal([...lines[1]].length, [...lines[3]].length);
  assert.equal([...lines[1]].length, [...lines[4]].length);
  assert.match(output, /Server address:\s+http:\/\/127\.0\.0\.1:8780/);
  assert.match(output, /Token:\s+not required/);
  assert.match(output, /iOS\/iPadOS:/);
  assert.match(output, /Download:/);
  assert.match(output, /Other platforms:/);
});

test('client install banner masks token in log-safe output', () => {
  const token = 'clk_1234567890abcdef';
  const output = formatClientInstallBanner({
    useColor: false,
    serverAddress: 'http://127.0.0.1:8780',
    token,
  }).join('\n');

  assert.doesNotMatch(output, new RegExp(token));
  assert.match(output, /Token:\s+shown below in terminal only \(clk_...cdef\)/);
  assert.equal(maskToken(token), 'clk_...cdef');
});

test('terminal token lines show full token only for tty output', () => {
  const token = 'clk_1234567890abcdef';
  const ttyOutput = formatTerminalTokenLines({ token, isTty: true }).join('\n');
  const nonTtyOutput = formatTerminalTokenLines({
    token,
    isTty: false,
    configPath: '/tmp/clawke.json',
  }).join('\n');

  assert.match(ttyOutput, new RegExp(token));
  assert.match(ttyOutput, /terminal only/);
  assert.doesNotMatch(nonTtyOutput, new RegExp(token));
  assert.match(nonTtyOutput, /Read relay\.token from:/);
  assert.match(nonTtyOutput, /\/tmp\/clawke\.json/);
});
