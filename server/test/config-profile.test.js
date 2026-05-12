const test = require('node:test');
const assert = require('node:assert/strict');
const fs = require('node:fs');
const os = require('node:os');
const path = require('node:path');

function writeJson(file, value) {
  fs.mkdirSync(path.dirname(file), { recursive: true });
  fs.writeFileSync(file, JSON.stringify(value, null, 2) + '\n');
}

test('loadConfig keeps string config path compatibility', async () => {
  const { loadConfig } = await import('../dist/config.js');
  const dir = fs.mkdtempSync(path.join(os.tmpdir(), 'clawke-config-'));
  const configPath = path.join(dir, 'clawke.json');
  writeJson(configPath, {
    server: {
      mode: 'mock',
      clientPort: 19065,
    },
  });

  const config = loadConfig(configPath);

  assert.equal(config.server.mode, 'mock');
  assert.equal(config.server.clientPort, 19065);
  assert.equal(config.server.httpPort, 8780);
});

test('loadConfig overlays profile config on base config with array replacement', async () => {
  const { getConfigPath, loadConfig } = await import('../dist/config.js');
  const dir = fs.mkdtempSync(path.join(os.tmpdir(), 'clawke-config-profile-'));
  const baseHome = path.join(dir, '.clawke');
  const baseConfigPath = path.join(baseHome, 'clawke.json');
  const profileConfigPath = path.join(baseHome, 'profiles', 'dev', 'clawke.json');

  writeJson(baseConfigPath, {
    server: {
      clientPort: 19065,
      httpPort: 19080,
      logLevel: 'debug',
    },
    relay: {
      token: 'base-token',
      apiBaseUrl: 'https://api.clawke.ai',
    },
    gateways: {
      hermes: [{ id: 'base-hermes', start_shell: 'python /old/run.py' }],
      openclaw: [{ id: 'OpenClaw' }],
    },
  });
  writeJson(profileConfigPath, {
    server: {
      httpPort: 19880,
    },
    relay: {
      apiBaseUrl: 'https://local.clawke.ai',
    },
    gateways: {
      hermes: [{ id: 'dev-hermes', start_shell: 'python /dev/run.py' }],
    },
  });

  const config = loadConfig({ baseHome, profile: 'dev', ensure: false });

  assert.equal(getConfigPath({ baseHome, profile: 'dev' }), profileConfigPath);
  assert.equal(config.server.clientPort, 19065);
  assert.equal(config.server.httpPort, 19880);
  assert.equal(config.server.logLevel, 'debug');
  assert.equal(config.relay.token, 'base-token');
  assert.equal(config.relay.apiBaseUrl, 'https://local.clawke.ai');
  assert.deepEqual(config.gateways.hermes, [{ id: 'dev-hermes', start_shell: 'python /dev/run.py' }]);
  assert.deepEqual(config.gateways.openclaw, [{ id: 'OpenClaw' }]);
});
