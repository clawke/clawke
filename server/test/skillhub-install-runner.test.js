const test = require('node:test');
const assert = require('node:assert/strict');
const fs = require('node:fs');
const os = require('node:os');
const path = require('node:path');

test('canUseManagedSkillHubInstall accepts gateways that report the Clawke shared skill root', () => {
  const runner = require('../dist/services/skillhub-install-runner');
  const store = require('../dist/store/skillhub-install-store');
  assert.equal(runner.canUseManagedSkillHubInstall({
    gateways: [{
      gateway_id: 'hermes',
      display_name: 'Hermes',
      gateway_type: 'hermes',
      status: 'online',
      capabilities: ['skills'],
      shared_skill_root: store.SKILLHUB_SKILLS_DIR,
    }],
  }), true);
});

test('canUseManagedSkillHubInstall rejects remote gateways without shared root evidence', () => {
  const runner = require('../dist/services/skillhub-install-runner');
  assert.equal(runner.canUseManagedSkillHubInstall({
    gateways: [{
      gateway_id: 'remote-hermes',
      display_name: 'Remote Hermes',
      gateway_type: 'hermes',
      status: 'online',
      capabilities: ['skills'],
    }],
  }), false);
});

test('validateSkillHubSlug blocks unsafe slugs before file operations', () => {
  const runner = require('../dist/services/skillhub-install-runner');
  assert.throws(() => runner.validateSkillHubSlug('../github'), /Invalid skill slug/);
  assert.throws(() => runner.validateSkillHubSlug('天气'), /Invalid skill slug/);
  assert.equal(runner.validateSkillHubSlug('github-helper'), 'github-helper');
});

test('managed SkillHub install runner has no Docker command dependency', () => {
  const source = fs.readFileSync(
    path.join(__dirname, '..', 'src', 'services', 'skillhub-install-runner.ts'),
    'utf8',
  );
  assert.equal(/\bdocker\b/i.test(source), false);
});

test('extractSkillHubArchive handles malformed UTF-8 zip entry names on macOS', {
  skip: process.platform !== 'darwin',
}, async () => {
  const runner = require('../dist/services/skillhub-install-runner');
  const tempRoot = fs.mkdtempSync(path.join(os.tmpdir(), 'skillhub-bad-zip-'));
  const archivePath = path.join(tempRoot, 'bad-name.zip');
  const targetDir = path.join(tempRoot, 'out');
  fs.mkdirSync(targetDir);
  writeMinimalZip({
    archivePath,
    nameBytes: Buffer.from([0x62, 0x61, 0x64, 0x2d, 0xff, 0x2e, 0x6d, 0x64]),
  });

  try {
    await runner.extractSkillHubArchive(archivePath, targetDir);

    assert.equal(fs.readdirSync(targetDir).length, 1);
  } finally {
    fs.rmSync(tempRoot, { recursive: true, force: true });
  }
});

function writeMinimalZip(input) {
  const nameBytes = input.nameBytes;
  const data = Buffer.alloc(0);
  const flags = 0x0800;
  const local = Buffer.concat([
    u32(0x04034b50), u16(20), u16(flags), u16(0), u16(0), u16(0),
    u32(0), u32(data.length), u32(data.length), u16(nameBytes.length), u16(0),
    nameBytes, data,
  ]);
  const central = Buffer.concat([
    u32(0x02014b50), u16(20), u16(20), u16(flags), u16(0), u16(0), u16(0),
    u32(0), u32(data.length), u32(data.length), u16(nameBytes.length), u16(0),
    u16(0), u16(0), u16(0), u32(0), u32(0), nameBytes,
  ]);
  const end = Buffer.concat([
    u32(0x06054b50), u16(0), u16(0), u16(1), u16(1),
    u32(central.length), u32(local.length), u16(0),
  ]);
  fs.writeFileSync(input.archivePath, Buffer.concat([local, central, end]));
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
