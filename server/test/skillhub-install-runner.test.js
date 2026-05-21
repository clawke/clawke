const test = require('node:test');
const assert = require('node:assert/strict');
const fs = require('node:fs');
const { execFileSync } = require('node:child_process');
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

test('canUseManagedSkillHubInstall does not use another gateway root for an OpenClaw install', () => {
  const runner = require('../dist/services/skillhub-install-runner');
  const store = require('../dist/store/skillhub-install-store');
  assert.equal(runner.canUseManagedSkillHubInstall({
    installPackage: {
      slug: 'openclaw-github-assistant',
      source: 'clawhub',
      gatewayType: 'openclaw',
    },
    gateways: [
      {
        gateway_id: 'hermes',
        display_name: 'Hermes',
        gateway_type: 'hermes',
        status: 'online',
        capabilities: ['skills'],
        shared_skill_root: store.SKILLHUB_SKILLS_DIR,
      },
      {
        gateway_id: 'OpenClaw',
        display_name: 'OpenClaw',
        gateway_type: 'openclaw',
        status: 'online',
        capabilities: ['skills'],
        local_to_server: true,
      },
    ],
  }), false);
});

test('canUseManagedSkillHubInstall does not infer profile skill visibility from local loopback alone', () => {
  const runner = require('../dist/services/skillhub-install-runner');
  assert.equal(runner.canUseManagedSkillHubInstall({
    installPackage: {
      slug: 'openclaw-github-assistant',
      source: 'clawhub',
      gatewayType: 'openclaw',
    },
    gateways: [{
      gateway_id: 'OpenClaw',
      display_name: 'OpenClaw',
      gateway_type: 'openclaw',
      status: 'online',
      capabilities: ['skills'],
      local_to_server: true,
    }],
  }), false);
});

test('SkillHub managed install directory stays in base home when a profile is active', () => {
  const baseHome = fs.mkdtempSync(path.join(os.tmpdir(), 'clawke-profile-home-'));
  try {
    const output = execFileSync(process.execPath, [
      '-e',
      [
        'const store = require("./dist/store/skillhub-install-store");',
        'const runner = require("./dist/services/skillhub-install-runner");',
        'const gateway = { gateway_id: "OpenClaw", display_name: "OpenClaw", gateway_type: "openclaw", status: "online", capabilities: ["skills"], shared_skill_root: store.SKILLHUB_SKILLS_DIR };',
        'process.stdout.write(JSON.stringify({ dir: store.SKILLHUB_SKILLS_DIR, canUse: runner.canUseManagedSkillHubInstall({ installPackage: { slug: "github", gatewayType: "openclaw" }, gateways: [gateway] }) }));',
      ].join(' '),
    ], {
      cwd: path.join(__dirname, '..'),
      env: {
        ...process.env,
        CLAWKE_DATA_DIR: baseHome,
        CLAWKE_PROFILE: 'dev',
      },
      encoding: 'utf8',
    });
    assert.deepEqual(JSON.parse(output), {
      dir: path.join(baseHome, 'skills'),
      canUse: true,
    });
  } finally {
    fs.rmSync(baseHome, { recursive: true, force: true });
  }
});

test('validateSkillHubSlug blocks unsafe slugs before file operations', () => {
  const runner = require('../dist/services/skillhub-install-runner');
  assert.throws(() => runner.validateSkillHubSlug('../github'), /Invalid skill slug/);
  assert.throws(() => runner.validateSkillHubSlug('天气'), /Invalid skill slug/);
  assert.equal(runner.validateSkillHubSlug('github-helper'), 'github-helper');
});

test('rewriteSkillFrontmatter canonicalizes unsafe SkillHub display names to slug', () => {
  const runner = require('../dist/services/skillhub-install-runner');
  const content = [
    '---',
    'name: Word / DOCX',
    'description: Create Word documents.',
    '---',
    '',
    '# Word / DOCX',
    '',
  ].join('\n');

  const rewritten = runner.rewriteSkillFrontmatter(content, 'word-docx', 'Word / DOCX');

  assert.match(rewritten, /^name: word-docx$/m);
  assert.match(rewritten, /^slug: word-docx$/m);
  assert.match(rewritten, /^displayName: "Word \/ DOCX"$/m);
  assert.doesNotMatch(rewritten, /^name: Word \/ DOCX$/m);
  assert.match(rewritten, /^---\n\n# Word \/ DOCX/m);
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
