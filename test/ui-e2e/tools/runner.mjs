#!/usr/bin/env node
import fs from 'node:fs';
import http from 'node:http';
import path from 'node:path';
import { spawn, spawnSync } from 'node:child_process';

const root = path.resolve(new URL('../../..', import.meta.url).pathname);
const args = parseArgs(process.argv.slice(2));
const caseId = args.case || 'p0-send-message';
const casePath = path.join(root, 'test', 'ui-e2e', 'test-cases', `${caseId}.json`);
const caseJson = fs.readFileSync(casePath, 'utf8');
const caseJsonBase64 = Buffer.from(caseJson, 'utf8').toString('base64');
const testCase = JSON.parse(caseJson);
const setup = testCase.setup || {};
const runId = new Date().toISOString().replace(/[:.]/g, '-');
const runDir = path.join(root, 'test', 'ui-e2e', 'runs', `${runId}-${caseId}`);
const bugDir = path.join(root, 'test', 'ui-e2e', 'bug-reports');
const httpPort = Number(setup.httpPort || 18780);
const upstreamPort = Number(setup.upstreamPort || 18766);
const mediaPort = Number(setup.mediaPort || 18781);

fs.mkdirSync(runDir, { recursive: true });
fs.mkdirSync(path.join(runDir, 'server-home'), { recursive: true });
fs.mkdirSync(path.join(runDir, 'screenshots'), { recursive: true });
fs.mkdirSync(bugDir, { recursive: true });

const logs = {
  server: path.join(runDir, 'server.log'),
  client: path.join(runDir, 'client.log'),
  mockGateway: path.join(runDir, 'mock-gateway.log'),
};

function parseArgs(argv) {
  const out = {};
  for (let i = 0; i < argv.length; i += 1) {
    const item = argv[i];
    if (!item.startsWith('--')) continue;
    const key = item.slice(2);
    const next = argv[i + 1];
    if (!next || next.startsWith('--')) {
      out[key] = true;
    } else {
      out[key] = next;
      i += 1;
    }
  }
  return out;
}

function writeTestConfig() {
  const configPath = path.join(runDir, 'server-home', 'clawke.json');
  const config = {
    server: {
      mode: 'openclaw',
      httpPort,
      upstreamPort,
      mediaPort,
      fastMode: true,
      logLevel: 'info',
    },
    openclaw: {
      sharedFs: false,
      mediaBaseUrl: `http://127.0.0.1:${mediaPort}`,
    },
    relay: {
      enable: false,
      token: '',
      relayUrl: '',
      serverAddr: '',
      serverPort: 7000,
    },
  };
  fs.writeFileSync(configPath, `${JSON.stringify(config, null, 2)}\n`);
}

function openLog(file) {
  return fs.openSync(file, 'a');
}

function spawnLogged(command, argv, options, logFile) {
  const fd = openLog(logFile);
  const child = spawn(command, argv, {
    ...options,
    stdio: ['ignore', fd, fd],
  });
  child.on('exit', () => fs.closeSync(fd));
  return child;
}

async function waitForHealth() {
  const deadline = Date.now() + 20000;
  while (Date.now() < deadline) {
    if (await httpOk(`http://127.0.0.1:${httpPort}/health`)) return;
    await sleep(250);
  }
  throw new Error(`Server health check timed out on port ${httpPort}`);
}

function httpOk(url) {
  return new Promise((resolve) => {
    const req = http.get(url, (res) => {
      res.resume();
      resolve(res.statusCode === 200);
    });
    req.on('error', () => resolve(false));
    req.setTimeout(1000, () => {
      req.destroy();
      resolve(false);
    });
  });
}

function sleep(ms) {
  return new Promise((resolve) => setTimeout(resolve, ms));
}

function buildServer() {
  const result = spawnSync('npm', ['run', 'build'], {
    cwd: path.join(root, 'server'),
    stdio: 'inherit',
  });
  if (result.status !== 0) {
    throw new Error('server build failed');
  }
}

function writeBugReport(error) {
  const templatePath = path.join(root, 'test', 'ui-e2e', 'templates', 'bug-report.md');
  const template = fs.readFileSync(templatePath, 'utf8');
  const branch = spawnSync('git', ['branch', '--show-current'], {
    cwd: root,
    encoding: 'utf8',
  }).stdout.trim();
  const report = template
    .replaceAll('{{case_id}}', testCase.id)
    .replaceAll('{{case_title}}', testCase.title)
    .replaceAll('{{run_id}}', runId)
    .replaceAll('{{branch}}', branch)
    .replaceAll('{{summary}}', `Case failed: ${testCase.title}`)
    .replaceAll('{{expected}}', JSON.stringify(testCase.assert, null, 2))
    .replaceAll('{{actual}}', error.message || String(error))
    .replaceAll('{{repro_steps}}', (testCase.steps || []).map((step, index) => `${index + 1}. ${JSON.stringify(step)}`).join('\n'))
    .replaceAll('{{run_dir}}', runDir)
    .replaceAll('{{server_log}}', logs.server)
    .replaceAll('{{client_log}}', logs.client)
    .replaceAll('{{mock_gateway_log}}', logs.mockGateway)
    .replaceAll('{{screenshot_dir}}', path.join(runDir, 'screenshots'));
  const reportPath = path.join(bugDir, `${runId}-${testCase.id}.md`);
  fs.writeFileSync(reportPath, report);
  return reportPath;
}

async function main() {
  writeTestConfig();
  buildServer();

  const children = [];
  try {
    const server = spawnLogged('node', ['dist/index.js'], {
      cwd: path.join(root, 'server'),
      env: {
        ...process.env,
        CLAWKE_DATA_DIR: path.join(runDir, 'server-home'),
        MODE: 'openclaw',
        NODE_TEST: '1',
      },
    }, logs.server);
    children.push(server);

    await waitForHealth();

    const mockGateway = spawnLogged('node', [
      path.join(root, 'test', 'ui-e2e', 'tools', 'mock-gateway.mjs'),
      '--case', casePath,
      '--upstream-url', `ws://127.0.0.1:${upstreamPort}`,
      '--log', logs.mockGateway,
    ], { cwd: root }, logs.mockGateway);
    children.push(mockGateway);

    await sleep(1000);

    const flutterArgs = [
      'test',
      'integration_test/ui_e2e_app_test.dart',
      '-d',
      'macos',
      `--dart-define=CLAWKE_E2E_CASE_JSON_BASE64=${caseJsonBase64}`,
      `--dart-define=CLAWKE_E2E_HTTP_URL=http://127.0.0.1:${httpPort}`,
      `--dart-define=CLAWKE_E2E_WS_URL=ws://127.0.0.1:${httpPort}/ws`,
      `--dart-define=CLAWKE_E2E_RUN_DIR=${runDir}`,
    ];
    const flutter = spawnSync('flutter', flutterArgs, {
      cwd: path.join(root, 'client'),
      encoding: 'utf8',
      maxBuffer: 1024 * 1024 * 20,
    });
    fs.writeFileSync(logs.client, `${flutter.stdout || ''}\n${flutter.stderr || ''}`);
    if (flutter.status !== 0) {
      throw new Error(`flutter test failed with status ${flutter.status}`);
    }

    fs.writeFileSync(path.join(runDir, 'result.json'), JSON.stringify({
      ok: true,
      case_id: testCase.id,
      run_id: runId,
      run_dir: runDir,
    }, null, 2));
    console.log(`PASS ${testCase.id}`);
    console.log(`Artifacts: ${runDir}`);
  } catch (error) {
    fs.writeFileSync(path.join(runDir, 'result.json'), JSON.stringify({
      ok: false,
      case_id: testCase.id,
      run_id: runId,
      error: error.message || String(error),
      run_dir: runDir,
    }, null, 2));
    const reportPath = writeBugReport(error);
    console.error(`FAIL ${testCase.id}`);
    console.error(`Bug report: ${reportPath}`);
    process.exitCode = 1;
  } finally {
    for (const child of children.reverse()) {
      if (!child.killed) child.kill('SIGTERM');
    }
  }
}

main();
