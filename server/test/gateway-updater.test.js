const test = require('node:test');
const assert = require('node:assert/strict');
const fs = require('node:fs');
const os = require('node:os');
const path = require('node:path');

function makeCapture() {
  let text = '';
  return {
    stream: {
      write(chunk) {
        text += String(chunk);
      },
    },
    text() {
      return text;
    },
  };
}

function writeJson(file, value) {
  fs.mkdirSync(path.dirname(file), { recursive: true });
  fs.writeFileSync(file, JSON.stringify(value, null, 2) + '\n');
}

test('gateway update syncs configured local OpenClaw gateway and restarts it', async () => {
  const { runGatewayUpdate } = await import('../dist/cli/gateway-updater.js');
  const dir = fs.mkdtempSync(path.join(os.tmpdir(), 'clawke-gateway-update-'));
  const projectRoot = path.join(dir, 'clawke');
  const clawkeHome = path.join(dir, '.clawke');
  const configPath = path.join(dir, 'clawke.json');
  const openclawHome = path.join(dir, '.openclaw');
  const sourceDir = path.join(projectRoot, 'gateways', 'openclaw', 'clawke');
  const targetDir = path.join(openclawHome, 'extensions', 'clawke');
  const stdout = makeCapture();
  const stderr = makeCapture();
  const restartCommands = [];
  const spawnSyncProcess = (command) => {
    restartCommands.push(command);
    return { status: 0 };
  };

  fs.mkdirSync(sourceDir, { recursive: true });
  fs.writeFileSync(path.join(sourceDir, 'index.ts'), 'export const version = "new";\n');
  fs.mkdirSync(targetDir, { recursive: true });
  fs.writeFileSync(path.join(targetDir, 'stale.txt'), 'old\n');
  writeJson(path.join(openclawHome, 'openclaw.json'), {});
  writeJson(configPath, {
    gateways: {
      openclaw: [{ id: 'OpenClaw' }],
    },
  });

  const code = runGatewayUpdate({
    projectRoot,
    clawkeHome,
    clawkeConfigPath: configPath,
    openclawHome,
    spawnSyncProcess,
    stdout: stdout.stream,
    stderr: stderr.stream,
  });

  assert.equal(code, 0);
  assert.equal(fs.readFileSync(path.join(targetDir, 'index.ts'), 'utf-8'), 'export const version = "new";\n');
  assert.equal(fs.existsSync(path.join(targetDir, 'stale.txt')), false);
  assert.deepEqual(restartCommands, ['which openclaw', 'openclaw gateway restart']);
  assert.match(stdout.text(), /Restarting OpenClaw gateway/);
  assert.match(stdout.text(), /OpenClaw gateway restarted/);
});

test('gateway update merges missing OpenClaw Clawke hook config', async () => {
  const { runGatewayUpdate } = await import('../dist/cli/gateway-updater.js');
  const dir = fs.mkdtempSync(path.join(os.tmpdir(), 'clawke-gateway-update-'));
  const projectRoot = path.join(dir, 'clawke');
  const configPath = path.join(dir, 'clawke.json');
  const openclawHome = path.join(dir, '.openclaw');
  const sourceDir = path.join(projectRoot, 'gateways', 'openclaw', 'clawke');
  const stdout = makeCapture();
  const stderr = makeCapture();

  fs.mkdirSync(sourceDir, { recursive: true });
  fs.writeFileSync(path.join(sourceDir, 'index.ts'), 'export const version = "new";\n');
  writeJson(path.join(openclawHome, 'openclaw.json'), {});
  writeJson(configPath, {
    gateways: {
      openclaw: [{ id: 'OpenClaw' }],
    },
  });

  const code = runGatewayUpdate({
    projectRoot,
    clawkeConfigPath: configPath,
    openclawHome,
    localOnly: true,
    stdout: stdout.stream,
    stderr: stderr.stream,
  });

  const openclawConfig = JSON.parse(fs.readFileSync(path.join(openclawHome, 'openclaw.json'), 'utf-8'));
  assert.equal(code, 0);
  assert.equal(openclawConfig.plugins.entries.clawke.enabled, true);
  assert.equal(openclawConfig.plugins.entries.clawke.hooks.allowConversationAccess, true);
  assert.match(stdout.text(), /OpenClaw config updated/);
});

test('gateway update preserves explicit OpenClaw conversation hook opt-out', async () => {
  const { runGatewayUpdate } = await import('../dist/cli/gateway-updater.js');
  const dir = fs.mkdtempSync(path.join(os.tmpdir(), 'clawke-gateway-update-'));
  const projectRoot = path.join(dir, 'clawke');
  const configPath = path.join(dir, 'clawke.json');
  const openclawHome = path.join(dir, '.openclaw');
  const sourceDir = path.join(projectRoot, 'gateways', 'openclaw', 'clawke');
  const stdout = makeCapture();
  const stderr = makeCapture();

  fs.mkdirSync(sourceDir, { recursive: true });
  fs.writeFileSync(path.join(sourceDir, 'index.ts'), 'export const version = "new";\n');
  writeJson(path.join(openclawHome, 'openclaw.json'), {
    plugins: {
      entries: {
        clawke: {
          enabled: true,
          hooks: {
            allowConversationAccess: false,
          },
        },
      },
    },
  });
  writeJson(configPath, {
    gateways: {
      openclaw: [{ id: 'OpenClaw' }],
    },
  });

  const code = runGatewayUpdate({
    projectRoot,
    clawkeConfigPath: configPath,
    openclawHome,
    localOnly: true,
    stdout: stdout.stream,
    stderr: stderr.stream,
  });

  const openclawConfig = JSON.parse(fs.readFileSync(path.join(openclawHome, 'openclaw.json'), 'utf-8'));
  assert.equal(code, 0);
  assert.equal(openclawConfig.plugins.entries.clawke.enabled, true);
  assert.equal(openclawConfig.plugins.entries.clawke.hooks.allowConversationAccess, false);
});

test('gateway update local-only skips configured OpenClaw when local install is missing', async () => {
  const { runGatewayUpdate } = await import('../dist/cli/gateway-updater.js');
  const dir = fs.mkdtempSync(path.join(os.tmpdir(), 'clawke-gateway-update-'));
  const projectRoot = path.join(dir, 'clawke');
  const configPath = path.join(dir, 'clawke.json');
  const openclawHome = path.join(dir, '.openclaw');
  const sourceDir = path.join(projectRoot, 'gateways', 'openclaw', 'clawke');
  const stdout = makeCapture();
  const stderr = makeCapture();

  fs.mkdirSync(sourceDir, { recursive: true });
  fs.writeFileSync(path.join(sourceDir, 'index.ts'), 'export const version = "new";\n');
  writeJson(configPath, {
    gateways: {
      openclaw: [{ id: 'OpenClaw' }],
    },
  });

  const code = runGatewayUpdate({
    projectRoot,
    clawkeConfigPath: configPath,
    openclawHome,
    localOnly: true,
    spawnSyncProcess() {
      throw new Error('spawnSync should not be called');
    },
    stdout: stdout.stream,
    stderr: stderr.stream,
  });

  assert.equal(code, 0);
  assert.match(stdout.text(), /Skipping OpenClaw gateway sync/);
  assert.doesNotMatch(stderr.text(), /Remote gateway cannot be updated automatically/);
});

test('gateway update strict mode fails when configured OpenClaw local install is missing', async () => {
  const { runGatewayUpdate } = await import('../dist/cli/gateway-updater.js');
  const dir = fs.mkdtempSync(path.join(os.tmpdir(), 'clawke-gateway-update-'));
  const projectRoot = path.join(dir, 'clawke');
  const configPath = path.join(dir, 'clawke.json');
  const openclawHome = path.join(dir, '.openclaw');
  const sourceDir = path.join(projectRoot, 'gateways', 'openclaw', 'clawke');
  const stdout = makeCapture();
  const stderr = makeCapture();

  fs.mkdirSync(sourceDir, { recursive: true });
  fs.writeFileSync(path.join(sourceDir, 'index.ts'), 'export const version = "new";\n');
  writeJson(configPath, {
    gateways: {
      openclaw: [{ id: 'OpenClaw' }],
    },
  });

  const code = runGatewayUpdate({
    projectRoot,
    clawkeConfigPath: configPath,
    openclawHome,
    spawnSyncProcess() {
      throw new Error('spawnSync should not be called');
    },
    stdout: stdout.stream,
    stderr: stderr.stream,
  });

  assert.equal(code, 1);
  assert.match(stderr.text(), /Remote gateway cannot be updated automatically/);
  assert.match(stderr.text(), /Gateway update failed/);
});

test('gateway update refreshes configured Hermes start_shell in local-only mode', async () => {
  const { runGatewayUpdate } = await import('../dist/cli/gateway-updater.js');
  const dir = fs.mkdtempSync(path.join(os.tmpdir(), 'clawke-gateway-update-'));
  const projectRoot = path.join(dir, 'clawke');
  const clawkeHome = path.join(dir, '.clawke');
  const configPath = path.join(dir, 'clawke.json');
  const hermesSourceDir = path.join(projectRoot, 'gateways', 'hermes', 'clawke');
  const stdout = makeCapture();
  const stderr = makeCapture();

  fs.mkdirSync(hermesSourceDir, { recursive: true });
  fs.writeFileSync(path.join(hermesSourceDir, 'run.py'), 'print("gateway")\n');
  writeJson(configPath, {
    gateways: {
      hermes: [{ id: 'hermes', start_shell: '/opt/hermes/bin/python /old/clawke/run.py' }],
    },
  });

  const code = runGatewayUpdate({
    projectRoot,
    clawkeHome,
    clawkeConfigPath: configPath,
    localOnly: true,
    spawnProcess() {
      throw new Error('spawn should not be called');
    },
    stdout: stdout.stream,
    stderr: stderr.stream,
  });

  const config = JSON.parse(fs.readFileSync(configPath, 'utf-8'));
  assert.equal(code, 0);
  assert.equal(
    config.gateways.hermes[0].start_shell,
    `/opt/hermes/bin/python ${path.join(hermesSourceDir, 'run.py')}`,
  );
  assert.match(stdout.text(), /hermes gateway uses in-place source/);
  assert.match(stdout.text(), /Hermes gateway updated\. Next `clawke server start` will load it/);
});

test('gateway update restarts Clawke Server when Hermes is updated and server is running', async () => {
  const { runGatewayUpdate } = await import('../dist/cli/gateway-updater.js');
  const dir = fs.mkdtempSync(path.join(os.tmpdir(), 'clawke-gateway-update-'));
  const projectRoot = path.join(dir, 'clawke');
  const clawkeHome = path.join(dir, '.clawke');
  const configPath = path.join(dir, 'clawke.json');
  const hermesSourceDir = path.join(projectRoot, 'gateways', 'hermes', 'clawke');
  const cliPath = path.join(projectRoot, 'server', 'dist', 'cli', 'clawke.js');
  const stdout = makeCapture();
  const stderr = makeCapture();
  const spawnCalls = [];
  const spawnProcess = (command, args, options) => {
    spawnCalls.push({ command, args, options, unrefed: false });
    return {
      unref() {
        spawnCalls[0].unrefed = true;
      },
    };
  };

  fs.mkdirSync(hermesSourceDir, { recursive: true });
  fs.writeFileSync(path.join(hermesSourceDir, 'run.py'), 'print("gateway")\n');
  fs.mkdirSync(path.dirname(cliPath), { recursive: true });
  fs.writeFileSync(cliPath, '#!/usr/bin/env node\n');
  fs.mkdirSync(clawkeHome, { recursive: true });
  fs.writeFileSync(path.join(clawkeHome, 'server.pid'), String(process.pid));
  writeJson(configPath, {
    gateways: {
      hermes: [{ id: 'hermes', start_shell: '/opt/hermes/bin/python /old/clawke/run.py' }],
    },
  });

  const code = runGatewayUpdate({
    projectRoot,
    clawkeHome,
    clawkeConfigPath: configPath,
    spawnProcess,
    stdout: stdout.stream,
    stderr: stderr.stream,
  });

  assert.equal(code, 0);
  assert.equal(spawnCalls.length, 1);
  assert.equal(spawnCalls[0].command, process.execPath);
  assert.deepEqual(spawnCalls[0].args, [cliPath, 'server', 'restart']);
  assert.equal(spawnCalls[0].options.detached, true);
  assert.equal(spawnCalls[0].unrefed, true);
  assert.match(stdout.text(), /Restarting Clawke Server to reload the updated Hermes gateway/);
});

test('cli exposes gateway update and clawke update calls it after rebuild', () => {
  const repoRoot = path.resolve(__dirname, '..', '..');
  const cliSource = fs.readFileSync(path.join(repoRoot, 'server', 'src', 'cli', 'clawke.ts'), 'utf-8');
  const updateSource = fs.readFileSync(path.join(repoRoot, 'server', 'src', 'cli', 'clawke-update.ts'), 'utf-8');

  assert.match(cliSource, /command === 'gateway' && subCommand === 'update'/);
  assert.match(cliSource, /runGatewayUpdate\(\{ localOnly: args\.includes\('--local-only'\) \}\)/);
  assert.match(updateSource, /runGatewayUpdate\(/);
  assert.match(updateSource, /commitCount === 0[\s\S]*return runGatewayUpdateAfterBuild\(projectRoot/);
  assert.match(updateSource, /Rebuilding server[\s\S]*const gatewayUpdateCode = runGatewayUpdateAfterBuild\(projectRoot/);
});
