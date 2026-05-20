const assert = require('node:assert/strict');
const { createServer } = require('node:http');
const { Buffer } = require('node:buffer');
const { existsSync, mkdtempSync, readdirSync, readFileSync, rmSync, writeFileSync } = require('node:fs');
const { mkdir, rm } = require('node:fs/promises');
const { tmpdir } = require('node:os');
const { dirname, join } = require('node:path');
const test = require('node:test');
const WebSocket = require('ws');

const root = join(__dirname, '..');

test('SkillHub managed install can be deleted through Skills management API', async () => {
  const runtimeDir = mkdtempSync(join(tmpdir(), 'clawke-skillhub-delete-e2e-runtime-'));
  const packageDir = mkdtempSync(join(tmpdir(), 'clawke-skillhub-delete-e2e-package-'));
  const archivePath = join(packageDir, 'weather.zip');
  const skillDir = join(runtimeDir, 'skills', 'weather');
  const skillFile = join(skillDir, 'SKILL.md');
  writeStoredZip(archivePath, [{
    name: 'weather/SKILL.md',
    data: [
      '---',
      'name: weather',
      'description: Weather lookup',
      'category: general',
      '---',
      '',
      '# Weather',
      '',
      'Use for weather lookup.',
      '',
    ].join('\n'),
  }]);
  const archiveBytes = readFileSync(archivePath);
  const clawHub = createFakeClawHub(archiveBytes);

  const previousEnv = snapshotEnv([
    'CLAWKE_DATA_DIR',
    'OPENCLAW_CLAWHUB_URL',
    'NODE_TEST',
  ]);

  let httpServer;
  let upstreamWss;
  let gatewayWs;

  try {
    await listen(clawHub, 0);
    const clawHubAddress = clawHub.address();
    assert.ok(clawHubAddress && typeof clawHubAddress === 'object');

    process.env.CLAWKE_DATA_DIR = runtimeDir;
    process.env.OPENCLAW_CLAWHUB_URL = `http://127.0.0.1:${clawHubAddress.port}`;
    process.env.NODE_TEST = '1';
    writeConfig(runtimeDir);
    clearDistModuleCache();

    const gatewayListener = require('../dist/upstream/gateway-listener.js');
    const { sendSkillGatewayRequest } = require('../dist/upstream/skill-gateway-client.js');
    const { initSkillsRoutes } = require('../dist/routes/skills-routes.js');
    const { initSkillHubRoutes } = require('../dist/routes/skillhub-routes.js');
    const { startUnifiedServer } = require('../dist/http-server.js');

    upstreamWss = gatewayListener.startGatewayListener(0, () => {});
    await waitForListening(upstreamWss);
    const upstreamAddress = upstreamWss.address();
    assert.ok(upstreamAddress && typeof upstreamAddress === 'object');

    gatewayWs = await connectMockSkillGateway({
      upstreamPort: upstreamAddress.port,
      runtimeDir,
      skillsRoot: join(runtimeDir, 'skills'),
    });
    await waitFor(() => gatewayListener.getConnectedAccountIds().includes('e2e_gateway'));

    initSkillsRoutes({
      getConnectedAccountIds: gatewayListener.getConnectedAccountIds,
      sendSkillRequest: sendSkillGatewayRequest,
    });
    initSkillHubRoutes({
      getConnectedAccountIds: gatewayListener.getConnectedAccountIds,
      getConnectedGateways: gatewayListener.getConnectedGateways,
      sendSkillRequest: sendSkillGatewayRequest,
    });

    ({ server: httpServer } = startUnifiedServer(0));
    await waitForListening(httpServer);
    const httpAddress = httpServer.address();
    assert.ok(httpAddress && typeof httpAddress === 'object');
    const baseUrl = `http://127.0.0.1:${httpAddress.port}`;

    const install = await request(baseUrl, '/api/skillhub/install', {
      method: 'POST',
      body: { slug: 'weather', source: 'clawhub', gateway_id: 'e2e_gateway' },
    });
    assert.equal(install.status, 202, install.text);
    assert.equal(install.json.success, true, install.text);
    assert.equal(install.json.value.status, 'accepted', install.text);

    await waitFor(() => existsSync(skillFile));

    const installed = await waitForSkill(baseUrl, 'general/weather');
    assert.equal(installed.deletable, true);
    assert.equal(installed.absolutePath, skillFile);

    const deleted = await request(baseUrl, '/api/skills/general/weather', {
      method: 'DELETE',
      query: { gateway_id: 'e2e_gateway' },
    });
    assert.equal(deleted.status, 200, deleted.text);
    assert.equal(deleted.json.ok, true, deleted.text);

    await waitFor(() => !existsSync(skillDir));
    const after = await listSkills(baseUrl);
    assert.equal(after.some((skill) => skill.id === 'general/weather'), false);
  } finally {
    if (gatewayWs) gatewayWs.close();
    if (upstreamWss) await closeServer(upstreamWss);
    if (httpServer) await closeServer(httpServer);
    await closeServer(clawHub);
    restoreEnv(previousEnv);
    clearDistModuleCache();
    rmSync(runtimeDir, { recursive: true, force: true });
    await rm(packageDir, { recursive: true, force: true });
  }
});

function createFakeClawHub(archiveBytes) {
  return createServer((req, res) => {
    const url = new URL(req.url || '/', 'http://127.0.0.1');
    if (url.pathname === '/api/v1/skills/weather') {
      res.setHeader('Content-Type', 'application/json');
      res.end(JSON.stringify({
        skill: { slug: 'weather', displayName: 'Weather' },
        latestVersion: { version: '1.0.0' },
      }));
      return;
    }
    if (url.pathname === '/api/v1/download' && url.searchParams.get('slug') === 'weather') {
      res.setHeader('Content-Type', 'application/zip');
      res.end(archiveBytes);
      return;
    }
    res.statusCode = 404;
    res.end('not found');
  });
}

async function connectMockSkillGateway({ upstreamPort, runtimeDir, skillsRoot }) {
  const ws = new WebSocket(`ws://127.0.0.1:${upstreamPort}`);
  ws.on('message', (raw) => {
    const incoming = JSON.parse(raw.toString());
    if (incoming.type === 'skill_list') {
      ws.send(JSON.stringify({
        type: 'skill_list_response',
        request_id: incoming.request_id,
        ok: true,
        skills: scanSkills(skillsRoot),
      }));
      return;
    }
    if (incoming.type === 'skill_delete') {
      const name = String(incoming.skill_id || '').split('/').pop();
      if (!name) {
        ws.send(JSON.stringify({
          type: 'skill_mutation_response',
          request_id: incoming.request_id,
          ok: false,
          error: 'not_found',
          message: 'Skill not found.',
        }));
        return;
      }
      rmSync(join(skillsRoot, name), { recursive: true, force: true });
      ws.send(JSON.stringify({
        type: 'skill_mutation_response',
        request_id: incoming.request_id,
        ok: true,
        deleted: true,
      }));
    }
  });
  await new Promise((resolve, reject) => {
    ws.once('open', resolve);
    ws.once('error', reject);
  });
  ws.send(JSON.stringify({
    type: 'identify',
    accountId: 'e2e_gateway',
    agentName: 'E2E Gateway',
    gatewayType: 'hermes',
    capabilities: ['skills'],
    clawkeHome: runtimeDir,
    managedSkillsRoot: skillsRoot,
    sharedSkillRoot: skillsRoot,
  }));
  return ws;
}

function scanSkills(skillsRoot) {
  if (!existsSync(skillsRoot)) return [];
  return readdirSync(skillsRoot, { withFileTypes: true })
    .filter((entry) => entry.isDirectory() && !entry.name.startsWith('.'))
    .filter((entry) => existsSync(join(skillsRoot, entry.name, 'SKILL.md')))
    .map((entry) => {
      const absolutePath = join(skillsRoot, entry.name, 'SKILL.md');
      return {
        id: `general/${entry.name}`,
        name: entry.name,
        description: 'Weather lookup',
        category: 'general',
        enabled: true,
        source: 'managed',
        sourceLabel: 'Clawke skills',
        writable: true,
        deletable: true,
        path: `${entry.name}/SKILL.md`,
        absolutePath,
        root: skillsRoot,
        updatedAt: 1,
        hasConflict: false,
        body: readFileSync(absolutePath, 'utf8'),
      };
    });
}

async function waitForSkill(baseUrl, skillId) {
  let found = null;
  await waitFor(async () => {
    const skills = await listSkills(baseUrl);
    found = skills.find((skill) => skill.id === skillId) || null;
    return Boolean(found);
  });
  return found;
}

async function listSkills(baseUrl) {
  const response = await request(baseUrl, '/api/skills', {
    query: { gateway_id: 'e2e_gateway' },
  });
  assert.equal(response.status, 200, response.text);
  return response.json.skills || [];
}

async function request(baseUrl, path, { method = 'GET', query, body } = {}) {
  const url = new URL(path, baseUrl);
  for (const [key, value] of Object.entries(query || {})) {
    url.searchParams.set(key, String(value));
  }
  const response = await fetch(url, {
    method,
    headers: body === undefined ? undefined : { 'Content-Type': 'application/json' },
    body: body === undefined ? undefined : JSON.stringify(body),
  });
  const text = await response.text();
  let json = null;
  try {
    json = text ? JSON.parse(text) : null;
  } catch {}
  return { status: response.status, text, json };
}

function writeConfig(runtimeDir) {
  writeFileSync(join(runtimeDir, 'clawke.json'), JSON.stringify({
    server: {
      mode: 'openclaw',
      httpPort: 0,
      upstreamPort: 0,
      mediaPort: 0,
    },
    relay: {
      enable: false,
      token: '',
      apiBaseUrl: 'http://127.0.0.1',
    },
  }, null, 2));
}

function clearDistModuleCache() {
  for (const key of Object.keys(require.cache)) {
    if (key.startsWith(join(root, 'dist'))) {
      delete require.cache[key];
    }
  }
}

function snapshotEnv(keys) {
  return Object.fromEntries(keys.map((key) => [key, process.env[key]]));
}

function restoreEnv(snapshot) {
  for (const [key, value] of Object.entries(snapshot)) {
    if (value === undefined) {
      delete process.env[key];
    } else {
      process.env[key] = value;
    }
  }
}

function listen(server, port) {
  return new Promise((resolve, reject) => {
    server.once('error', reject);
    server.listen(port, '127.0.0.1', resolve);
  });
}

function waitForListening(server) {
  if (server.listening || server.address()) return Promise.resolve();
  return new Promise((resolve, reject) => {
    server.once('listening', resolve);
    server.once('error', reject);
  });
}

function closeServer(server) {
  if (!server) return Promise.resolve();
  return new Promise((resolve) => {
    if (typeof server.close !== 'function') {
      resolve();
      return;
    }
    server.close(() => resolve());
  });
}

async function waitFor(predicate) {
  const deadline = Date.now() + 5000;
  while (Date.now() < deadline) {
    if (await predicate()) return;
    await new Promise((resolve) => setTimeout(resolve, 50));
  }
  assert.fail('timed out waiting for condition');
}

function writeStoredZip(archivePath, entries) {
  const locals = [];
  const centrals = [];
  let offset = 0;
  for (const entry of entries) {
    const name = Buffer.isBuffer(entry.name)
      ? entry.name
      : Buffer.from(entry.name, 'utf8');
    const data = Buffer.from(entry.data || '', 'utf8');
    const local = Buffer.concat([
      u32(0x04034b50), u16(20), u16(0x0800), u16(0), u16(0), u16(0),
      u32(crc32(data)), u32(data.length), u32(data.length), u16(name.length), u16(0),
      name, data,
    ]);
    const central = Buffer.concat([
      u32(0x02014b50), u16(20), u16(20), u16(0x0800), u16(0), u16(0), u16(0),
      u32(crc32(data)), u32(data.length), u32(data.length), u16(name.length), u16(0),
      u16(0), u16(0), u16(0), u32(0), u32(offset), name,
    ]);
    locals.push(local);
    centrals.push(central);
    offset += local.length;
  }
  const central = Buffer.concat(centrals);
  const end = Buffer.concat([
    u32(0x06054b50), u16(0), u16(0), u16(entries.length), u16(entries.length),
    u32(central.length), u32(offset), u16(0),
  ]);
  writeFileSync(archivePath, Buffer.concat([...locals, central, end]));
}

function crc32(data) {
  let crc = 0xffffffff;
  for (const byte of data) {
    crc ^= byte;
    for (let index = 0; index < 8; index += 1) {
      crc = (crc >>> 1) ^ (0xedb88320 & -(crc & 1));
    }
  }
  return (crc ^ 0xffffffff) >>> 0;
}

function u16(value) {
  const buffer = Buffer.alloc(2);
  buffer.writeUInt16LE(value);
  return buffer;
}

function u32(value) {
  const buffer = Buffer.alloc(4);
  buffer.writeUInt32LE(value);
  return buffer;
}
