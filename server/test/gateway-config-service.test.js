const test = require('node:test');
const assert = require('node:assert/strict');
const fs = require('node:fs');
const os = require('node:os');
const path = require('node:path');

test('listConfiguredGateways reads clawke.json from CLAWKE_DATA_DIR', async () => {
  const previousClawkeDataDir = process.env.CLAWKE_DATA_DIR;
  const tmpDir = fs.mkdtempSync(path.join(os.tmpdir(), 'clawke-gateways-'));

  try {
    process.env.CLAWKE_DATA_DIR = tmpDir;
    fs.writeFileSync(path.join(tmpDir, 'clawke.json'), JSON.stringify({
      gateways: {
        hermes: [{ id: 'hermes' }],
        nanobot: [{ id: 'nanobot' }],
      },
    }));

    const { listConfiguredGateways } = await import('../dist/services/gateway-config-service.js');
    const gateways = listConfiguredGateways();

    assert.deepEqual(gateways.map((gateway) => gateway.gateway_id), ['hermes', 'nanobot']);
    assert.equal(gateways[1].gateway_type, 'nanobot');
    assert.equal(gateways[1].display_name, 'nanobot');
  } finally {
    if (previousClawkeDataDir === undefined) delete process.env.CLAWKE_DATA_DIR;
    else process.env.CLAWKE_DATA_DIR = previousClawkeDataDir;
    fs.rmSync(tmpDir, { recursive: true, force: true });
  }
});

test('listConfiguredGateways reads the effective profile overlay', async () => {
  const previousClawkeDataDir = process.env.CLAWKE_DATA_DIR;
  const previousProfile = process.env.CLAWKE_PROFILE;
  const tmpDir = fs.mkdtempSync(path.join(os.tmpdir(), 'clawke-gateways-'));
  const profileDir = path.join(tmpDir, 'profiles', 'dev');

  try {
    process.env.CLAWKE_DATA_DIR = tmpDir;
    process.env.CLAWKE_PROFILE = 'dev';
    fs.mkdirSync(profileDir, { recursive: true });
    fs.writeFileSync(path.join(tmpDir, 'clawke.json'), JSON.stringify({
      gateways: {
        openclaw: [{ id: 'OpenClaw' }],
        hermes: [{ id: 'base-hermes' }],
      },
    }));
    fs.writeFileSync(path.join(profileDir, 'clawke.json'), JSON.stringify({
      gateways: {
        hermes: [{ id: 'dev-hermes' }],
      },
    }));

    const { listConfiguredGateways } = await import('../dist/services/gateway-config-service.js');
    const gateways = listConfiguredGateways();

    assert.deepEqual(gateways.map((gateway) => gateway.gateway_id), ['OpenClaw', 'dev-hermes']);
  } finally {
    if (previousClawkeDataDir === undefined) delete process.env.CLAWKE_DATA_DIR;
    else process.env.CLAWKE_DATA_DIR = previousClawkeDataDir;
    if (previousProfile === undefined) delete process.env.CLAWKE_PROFILE;
    else process.env.CLAWKE_PROFILE = previousProfile;
    fs.rmSync(tmpDir, { recursive: true, force: true });
  }
});
