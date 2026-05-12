const test = require('node:test');
const assert = require('node:assert/strict');
const fs = require('node:fs');
const os = require('node:os');
const path = require('node:path');

const serverRoot = path.resolve(__dirname, '..');
const projectRoot = path.resolve(serverRoot, '..');

function makeCaptureStream() {
  let output = '';
  return {
    stream: {
      write(chunk) {
        output += String(chunk);
        return true;
      },
    },
    output: () => output,
  };
}

test('clawke doctor reports missing user config without creating it', () => {
  const { runClawkeDoctor } = require('../dist/cli/clawke-doctor.js');
  const tmpDir = fs.mkdtempSync(path.join(os.tmpdir(), 'clawke-doctor-'));
  const clawkeHome = path.join(tmpDir, '.clawke');
  const capture = makeCaptureStream();

  const result = runClawkeDoctor({
    clawkeHome,
    homeDir: tmpDir,
    projectRoot,
    serverDir: serverRoot,
    stdout: capture.stream,
  });

  assert.equal(fs.existsSync(path.join(clawkeHome, 'clawke.json')), false);
  assert.equal(result.errorCount, 0);
  assert.equal(result.warningCount > 0, true);
  assert.match(capture.output(), /Clawke Doctor/);
  assert.match(capture.output(), /clawke\.json/);
});

test('clawke doctor reports configured gateways and stale gateway pid files', () => {
  const { runClawkeDoctor } = require('../dist/cli/clawke-doctor.js');
  const tmpDir = fs.mkdtempSync(path.join(os.tmpdir(), 'clawke-doctor-'));
  const clawkeHome = path.join(tmpDir, '.clawke');
  fs.mkdirSync(clawkeHome);
  fs.writeFileSync(
    path.join(clawkeHome, 'clawke.json'),
    JSON.stringify({
      server: {
        clientPort: 19065,
        upstreamPort: 19066,
        mediaPort: 19081,
      },
      gateways: {
        hermes: [
          {
            id: 'hermes-local',
            start_shell: 'node gateway.js',
          },
        ],
        openclaw: [
          {
            id: 'openclaw-remote',
          },
        ],
      },
    }),
  );
  fs.writeFileSync(path.join(clawkeHome, 'hermes-local-gateway.pid'), '999999');
  const capture = makeCaptureStream();

  const result = runClawkeDoctor({
    clawkeHome,
    homeDir: tmpDir,
    projectRoot,
    serverDir: serverRoot,
    stdout: capture.stream,
  });

  assert.equal(result.errorCount, 0);
  assert.equal(result.warningCount > 0, true);
  assert.match(capture.output(), /2 gateway instance/);
  assert.match(capture.output(), /Clawke Hermes Gateway \(hermes-local\) PID is stale/);
  assert.match(capture.output(), /✅ Clawke OpenClaw Gateway \(openclaw-remote\) is registered/);
  assert.doesNotMatch(capture.output(), /openclaw-remote.*start_shell/);
  assert.doesNotMatch(capture.output(), /openclaw-remote\) is not running/);
  assert.doesNotMatch(capture.output(), /openclaw-remote.*No gateway PID file/);
});

test('clawke doctor reports profile paths and reads effective profile config', () => {
  const { runClawkeDoctor } = require('../dist/cli/clawke-doctor.js');
  const tmpDir = fs.mkdtempSync(path.join(os.tmpdir(), 'clawke-doctor-'));
  const clawkeHome = path.join(tmpDir, '.clawke');
  const profileHome = path.join(clawkeHome, 'profiles', 'dev');
  fs.mkdirSync(profileHome, { recursive: true });
  fs.writeFileSync(
    path.join(clawkeHome, 'clawke.json'),
    JSON.stringify({
      server: {
        httpPort: 19080,
      },
      gateways: {
        openclaw: [{ id: 'openclaw-remote' }],
      },
    }),
  );
  fs.writeFileSync(
    path.join(profileHome, 'clawke.json'),
    JSON.stringify({
      server: {
        httpPort: 19880,
      },
    }),
  );
  const capture = makeCaptureStream();

  const result = runClawkeDoctor({
    profile: 'dev',
    homeDir: tmpDir,
    projectRoot,
    serverDir: serverRoot,
    stdout: capture.stream,
  });

  assert.equal(result.errorCount, 0);
  assert.match(capture.output(), /Profile: dev/);
  assert.match(capture.output(), new RegExp(profileHome.replace(/[.*+?^${}()|[\]\\]/g, '\\$&')));
  assert.match(capture.output(), /clawke\.json overlay parsed/);
  assert.match(capture.output(), /httpPort: 19880/);
  assert.match(capture.output(), /1 gateway instance configured/);
});
