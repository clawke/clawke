import test from 'node:test';
import assert from 'node:assert/strict';
import fs from 'node:fs';
import os from 'node:os';
import path from 'node:path';

test('registerGatewayInClawkeConfig creates and updates gateway entries', async () => {
  const { registerGatewayInClawkeConfig } = await import('../dist/cli/clawke-config-writer.js');
  const dir = fs.mkdtempSync(path.join(os.tmpdir(), 'clawke-config-writer-'));
  const configPath = path.join(dir, 'clawke.json');

  registerGatewayInClawkeConfig({
    configPath,
    gatewayType: 'openclaw',
    gatewayId: 'OpenClaw',
  });
  registerGatewayInClawkeConfig({
    configPath,
    gatewayType: 'openclaw',
    gatewayId: 'OpenClaw',
  });
  registerGatewayInClawkeConfig({
    configPath,
    gatewayType: 'hermes',
    gatewayId: 'hermes',
    values: { start_shell: 'python run.py' },
  });

  const config = JSON.parse(fs.readFileSync(configPath, 'utf-8'));

  assert.deepEqual(config.gateways.openclaw, [{ id: 'OpenClaw' }]);
  assert.deepEqual(config.gateways.hermes, [
    { id: 'hermes', start_shell: 'python run.py' },
  ]);
});

test('registerGatewayInClawkeConfig writes default path under active profile', async () => {
  const { registerGatewayInClawkeConfig } = await import('../dist/cli/clawke-config-writer.js');
  const dir = fs.mkdtempSync(path.join(os.tmpdir(), 'clawke-config-writer-'));
  const previousClawkeDataDir = process.env.CLAWKE_DATA_DIR;
  const previousProfile = process.env.CLAWKE_PROFILE;
  const profileConfigPath = path.join(dir, '.clawke', 'profiles', 'dev', 'clawke.json');

  try {
    process.env.CLAWKE_DATA_DIR = path.join(dir, '.clawke');
    process.env.CLAWKE_PROFILE = 'dev';

    registerGatewayInClawkeConfig({
      gatewayType: 'hermes',
      gatewayId: 'hermes',
      values: { start_shell: 'python run.py' },
    });

    const config = JSON.parse(fs.readFileSync(profileConfigPath, 'utf-8'));
    assert.deepEqual(config.gateways.hermes, [
      { id: 'hermes', start_shell: 'python run.py' },
    ]);
    assert.equal(fs.existsSync(path.join(dir, '.clawke', 'clawke.json')), false);
  } finally {
    if (previousClawkeDataDir === undefined) delete process.env.CLAWKE_DATA_DIR;
    else process.env.CLAWKE_DATA_DIR = previousClawkeDataDir;
    if (previousProfile === undefined) delete process.env.CLAWKE_PROFILE;
    else process.env.CLAWKE_PROFILE = previousProfile;
    fs.rmSync(dir, { recursive: true, force: true });
  }
});
