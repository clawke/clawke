const test = require('node:test');
const assert = require('node:assert/strict');
const fs = require('node:fs');
const os = require('node:os');
const path = require('node:path');
const { spawnSync } = require('node:child_process');

const serverRoot = path.resolve(__dirname, '..');
const cliPath = path.join(serverRoot, 'dist', 'cli', 'clawke.js');

test('server status without profile reads the base pid file', () => {
  const homeDir = fs.mkdtempSync(path.join(os.tmpdir(), 'clawke-cli-profile-'));
  const clawkeHome = path.join(homeDir, '.clawke');
  fs.mkdirSync(clawkeHome, { recursive: true });
  fs.writeFileSync(path.join(clawkeHome, 'server.pid'), String(process.pid));

  const result = spawnSync(process.execPath, [cliPath, 'server', 'status'], {
    cwd: serverRoot,
    env: { ...process.env, HOME: homeDir, CLAWKE_DATA_DIR: clawkeHome },
    encoding: 'utf-8',
  });

  assert.equal(result.status, 0, result.stderr || result.stdout);
  assert.match(result.stdout, new RegExp(`PID ${process.pid}`));
});

test('server status with profile reads the profile pid file', () => {
  const homeDir = fs.mkdtempSync(path.join(os.tmpdir(), 'clawke-cli-profile-'));
  const clawkeHome = path.join(homeDir, '.clawke');
  const profileHome = path.join(clawkeHome, 'profiles', 'dev');
  fs.mkdirSync(clawkeHome, { recursive: true });
  fs.mkdirSync(profileHome, { recursive: true });
  fs.writeFileSync(path.join(clawkeHome, 'server.pid'), '999999');
  fs.writeFileSync(path.join(profileHome, 'server.pid'), String(process.pid));

  const result = spawnSync(process.execPath, [cliPath, 'server', 'status', '--profile', 'dev'], {
    cwd: serverRoot,
    env: { ...process.env, HOME: homeDir, CLAWKE_DATA_DIR: clawkeHome },
    encoding: 'utf-8',
  });

  assert.equal(result.status, 0, result.stderr || result.stdout);
  assert.match(result.stdout, new RegExp(`PID ${process.pid}`));
});
