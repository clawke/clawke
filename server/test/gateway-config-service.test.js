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
