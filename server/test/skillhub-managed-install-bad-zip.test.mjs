import test from 'node:test';
import assert from 'node:assert/strict';
import { createServer } from 'node:http';
import {
  existsSync,
  mkdtempSync,
  readdirSync,
  readFileSync,
  rmSync,
  writeFileSync,
} from 'node:fs';
import { rm } from 'node:fs/promises';
import { tmpdir } from 'node:os';
import { join } from 'node:path';

test('managed SkillHub install extracts ClawHub zip with malformed UTF-8 entry names on macOS', {
  skip: process.platform !== 'darwin',
}, async () => {
  const runtimeDir = mkdtempSync(join(tmpdir(), 'clawke-skillhub-bad-zip-runtime-'));
  const packageDir = mkdtempSync(join(tmpdir(), 'clawke-skillhub-bad-zip-package-'));
  const archivePath = join(packageDir, 'nuwa-skill.zip');
  writeStoredZip(archivePath, [
    { name: 'nuwa-skill/SKILL.md', data: '# Nuwa\n' },
    {
      name: Buffer.concat([
        Buffer.from('nuwa-skill/examples/references/Elon-Musk-'),
        Buffer.from([0xff]),
        Buffer.from('.md'),
      ]),
      data: '',
    },
  ]);
  const archiveBytes = readFileSync(archivePath);

  const server = createServer((req, res) => {
    const url = new URL(req.url || '/', 'http://127.0.0.1');
    if (url.pathname === '/api/v1/skills/nuwa-skill') {
      res.setHeader('Content-Type', 'application/json');
      res.end(JSON.stringify({
        skill: { slug: 'nuwa-skill', displayName: 'Nuwa Skill' },
        latestVersion: { version: '1.0.0' },
      }));
      return;
    }
    if (url.pathname === '/api/v1/download' && url.searchParams.get('slug') === 'nuwa-skill') {
      res.setHeader('Content-Type', 'application/zip');
      res.end(archiveBytes);
      return;
    }
    res.statusCode = 404;
    res.end('not found');
  });
  await new Promise((resolve) => server.listen(0, '127.0.0.1', resolve));
  const address = server.address();
  assert.ok(address && typeof address === 'object');

  const previousDataDir = process.env.CLAWKE_DATA_DIR;
  const previousClawHubUrl = process.env.OPENCLAW_CLAWHUB_URL;
  process.env.CLAWKE_DATA_DIR = runtimeDir;
  process.env.OPENCLAW_CLAWHUB_URL = `http://127.0.0.1:${address.port}`;

  try {
    const runner = await import(`../dist/services/skillhub-install-runner.js?case=${Date.now()}`);
    const result = await runner.startManagedSkillHubInstall({
      installId: 'skillhub_test_nuwa',
      installMode: 'managed',
      installPackage: { slug: 'nuwa-skill', source: 'clawhub' },
    });
    assert.equal(result.status, 'accepted');

    await waitFor(() => existsSync(join(runtimeDir, 'skills', 'nuwa-skill', 'SKILL.md')));
    assert.equal(
      readFileSync(join(runtimeDir, 'skills', 'nuwa-skill', 'SKILL.md'), 'utf8'),
      '# Nuwa\n',
    );
    assert.ok(listFiles(join(runtimeDir, 'skills', 'nuwa-skill')).length >= 4);
  } finally {
    if (previousDataDir === undefined) {
      delete process.env.CLAWKE_DATA_DIR;
    } else {
      process.env.CLAWKE_DATA_DIR = previousDataDir;
    }
    if (previousClawHubUrl === undefined) {
      delete process.env.OPENCLAW_CLAWHUB_URL;
    } else {
      process.env.OPENCLAW_CLAWHUB_URL = previousClawHubUrl;
    }
    await new Promise((resolve) => server.close(resolve));
    rmSync(runtimeDir, { recursive: true, force: true });
    await rm(packageDir, { recursive: true, force: true });
  }
});

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

function listFiles(root) {
  const result = [];
  for (const entry of readdirSync(root, { withFileTypes: true })) {
    const fullPath = join(root, entry.name);
    result.push(fullPath);
    if (entry.isDirectory()) result.push(...listFiles(fullPath));
  }
  return result;
}

async function waitFor(predicate) {
  const deadline = Date.now() + 5000;
  while (Date.now() < deadline) {
    if (predicate()) return;
    await new Promise((resolve) => setTimeout(resolve, 50));
  }
  assert.fail('timed out waiting for managed SkillHub install');
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
