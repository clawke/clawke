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
const testCase = JSON.parse(caseJson);
if (args['demo-fail']) {
  testCase.steps = [
    ...(testCase.steps || []),
    {
      action: 'wait_for_text',
      text: '故意不存在的报告演示文本',
      timeoutMs: 2500,
    },
  ];
  testCase.assert = [
    ...(testCase.assert || []),
    { uiTextVisible: '故意不存在的报告演示文本' },
  ];
}
const caseJsonBase64 = Buffer.from(JSON.stringify(testCase), 'utf8').toString('base64');
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

function gitValue(argv) {
  return spawnSync('git', argv, {
    cwd: root,
    encoding: 'utf8',
  }).stdout.trim();
}

function materializeBase64Screenshots(text) {
  const screenshotDir = path.join(runDir, 'screenshots');
  fs.mkdirSync(screenshotDir, { recursive: true });
  return text.replace(
    /^E2E_SCREENSHOT_BASE64:([^:\r\n]+):([A-Za-z0-9+/=]+)$/gm,
    (_line, rawFileName, payload) => {
      const fileName = path.basename(rawFileName).replace(/[^A-Za-z0-9_.-]/g, '_');
      const target = path.join(screenshotDir, fileName || `${Date.now()}-screenshot.png`);
      try {
        fs.writeFileSync(target, Buffer.from(payload, 'base64'));
        return `E2E_SCREENSHOT:${target}`;
      } catch (error) {
        return `E2E_SCREENSHOT_FAILED:${error.message || String(error)}`;
      }
    },
  );
}

function copyScreenshotsFromClientLog() {
  if (!fs.existsSync(logs.client)) return [];
  const text = fs.readFileSync(logs.client, 'utf8');
  const matches = [...text.matchAll(/^E2E_SCREENSHOT:(.+)$/gm)];
  const out = [];
  const screenshotDir = path.join(runDir, 'screenshots');
  fs.mkdirSync(screenshotDir, { recursive: true });
  for (const match of matches) {
    const source = match[1].trim();
    if (!source) continue;
    try {
      const sourcePath = path.isAbsolute(source) ? source : path.join(runDir, source);
      if (!fs.existsSync(sourcePath)) continue;
      const target = path.join(screenshotDir, path.basename(sourcePath));
      if (path.resolve(sourcePath) !== path.resolve(target)) {
        fs.copyFileSync(sourcePath, target);
      }
      out.push(path.relative(runDir, target));
    } catch {
      // 忽略沙箱不可读截图路径，base64 通道会处理 — Ignore sandbox-inaccessible screenshot paths; base64 transport handles them.
    }
  }
  return [...new Set(out)];
}

function readLogLines(file, patterns, limit = 12) {
  if (!fs.existsSync(file)) return [];
  const lines = fs.readFileSync(file, 'utf8').split(/\r?\n/);
  return lines
    .filter((line) => patterns.some((pattern) => pattern.test(line)))
    .slice(-limit);
}

function escapeHtml(value) {
  return String(value)
    .replaceAll('&', '&amp;')
    .replaceAll('<', '&lt;')
    .replaceAll('>', '&gt;')
    .replaceAll('"', '&quot;');
}

function markdownList(items) {
  if (items.length === 0) return '- 无';
  return items.map((item) => `- ${item}`).join('\n');
}

function codeBlock(lines) {
  if (lines.length === 0) return '```text\n无\n```';
  return `\`\`\`text\n${lines.join('\n')}\n\`\`\``;
}

function reportStatus(ok) {
  return ok ? 'success' : 'fail';
}

function writeHumanReport({ ok, error, bugReportPath, screenshots }) {
  const branch = gitValue(['branch', '--show-current']);
  const commit = gitValue(['rev-parse', '--short', 'HEAD']);
  const mockHighlights = readLogLines(logs.mockGateway, [
    /\brecv\b/,
    /\bsend\b/,
    /unmatched/,
  ]);
  const clientHighlights = readLogLines(logs.client, [
    /Timed out waiting/,
    /Unsupported operation/,
    /Test failed/,
    /E2E_SCREENSHOT/,
    /Sent approval_response/,
    /Sent clarify_response/,
  ]);
  const screenshotMarkdown = screenshots.length === 0
    ? '当前 run 未采集到截图。'
    : screenshots.map((shot) => `![${shot}](${shot})`).join('\n\n');
  const statusValue = reportStatus(ok);
  const statusLabel = statusValue.toUpperCase();
  const markdown = `# UI E2E Report: ${testCase.id}

## Summary

- status: ${statusValue}
- case: ${testCase.id}
- title: ${testCase.title}
- run_id: ${runId}
- branch: ${branch}
- commit: ${commit}

## Conclusion

${ok ? '该 UI E2E 用例通过。' : `该 UI E2E 用例失败：${error?.message || String(error)}`}

## Scope

- Flutter UI: real
- Clawke Server: real
- WebSocket: real
- Mock Gateway: scripted
- Real Agent/LLM: disabled

## Steps

${(testCase.steps || []).map((step, index) => `${index + 1}. \`${JSON.stringify(step)}\``).join('\n')}

## Assertions

${(testCase.assert || []).map((assertion) => `- \`${JSON.stringify(assertion)}\``).join('\n') || '- 无'}

## Screenshots

${screenshotMarkdown}

## Gateway Evidence

${codeBlock(mockHighlights)}

## Client Evidence

${codeBlock(clientHighlights)}

## Artifacts

${markdownList([
  `run_dir: ${runDir}`,
  `server_log: ${logs.server}`,
  `client_log: ${logs.client}`,
  `mock_gateway_log: ${logs.mockGateway}`,
  ...(bugReportPath ? [`bug_report: ${bugReportPath}`] : []),
])}
`;
  const reportMd = path.join(runDir, 'report.md');
  fs.writeFileSync(reportMd, markdown);

  const screenshotHtml = screenshots.length === 0
    ? '<p>当前 run 未采集到截图。</p>'
    : screenshots.map((shot) => `<figure><img src="${escapeHtml(shot)}" alt="${escapeHtml(shot)}"><figcaption>${escapeHtml(shot)}</figcaption></figure>`).join('\n');
  const html = `<!doctype html>
<html lang="zh-CN">
<head>
  <meta charset="utf-8">
  <title>UI E2E Report - ${escapeHtml(testCase.id)}</title>
  <style>
    body { font-family: -apple-system, BlinkMacSystemFont, "Segoe UI", sans-serif; margin: 32px; color: #1f2933; background: #f6f7f9; }
    main { max-width: 1080px; margin: 0 auto; background: #fff; padding: 28px; border: 1px solid #d8dee4; border-radius: 8px; }
    h1, h2 { margin-top: 0; }
    .badge { display: inline-block; padding: 4px 10px; border-radius: 999px; color: #fff; background: ${ok ? '#1f8f4d' : '#c93c37'}; font-weight: 700; }
    table { border-collapse: collapse; width: 100%; margin: 16px 0; }
    th, td { border: 1px solid #d8dee4; padding: 8px; text-align: left; }
    th { background: #eef2f6; }
    pre { background: #111827; color: #e5e7eb; padding: 14px; overflow: auto; border-radius: 6px; }
    img { max-width: 100%; border: 1px solid #d8dee4; border-radius: 6px; }
    figure { margin: 16px 0; }
    figcaption { color: #637083; font-size: 13px; margin-top: 6px; }
  </style>
</head>
<body>
<main>
  <h1>UI E2E Report: ${escapeHtml(testCase.id)}</h1>
  <p><span class="badge">${statusLabel}</span></p>
  <table>
    <tr><th>Case</th><td>${escapeHtml(testCase.id)}</td></tr>
    <tr><th>Title</th><td>${escapeHtml(testCase.title)}</td></tr>
    <tr><th>Run ID</th><td>${escapeHtml(runId)}</td></tr>
    <tr><th>Branch</th><td>${escapeHtml(branch)}</td></tr>
    <tr><th>Commit</th><td>${escapeHtml(commit)}</td></tr>
    <tr><th>status</th><td>${escapeHtml(statusValue)}</td></tr>
  </table>
  <h2>Conclusion</h2>
  <p>${escapeHtml(ok ? '该 UI E2E 用例通过。' : `该 UI E2E 用例失败：${error?.message || String(error)}`)}</p>
  <h2>Screenshots</h2>
  ${screenshotHtml}
  <h2>Gateway Evidence</h2>
  <pre>${escapeHtml(mockHighlights.join('\n') || '无')}</pre>
  <h2>Client Evidence</h2>
  <pre>${escapeHtml(clientHighlights.join('\n') || '无')}</pre>
  <h2>Artifacts</h2>
  <ul>
    <li>run_dir: ${escapeHtml(runDir)}</li>
    <li>server_log: ${escapeHtml(logs.server)}</li>
    <li>client_log: ${escapeHtml(logs.client)}</li>
    <li>mock_gateway_log: ${escapeHtml(logs.mockGateway)}</li>
    ${bugReportPath ? `<li>bug_report: ${escapeHtml(bugReportPath)}</li>` : ''}
  </ul>
</main>
</body>
</html>
`;
  fs.writeFileSync(path.join(runDir, 'report.html'), html);
  return reportMd;
}

function writeBugReport(error) {
  const templatePath = path.join(root, 'test', 'ui-e2e', 'templates', 'bug-report.md');
  const template = fs.readFileSync(templatePath, 'utf8');
  const branch = gitValue(['branch', '--show-current']);
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
      timeout: 5 * 60 * 1000,
    });
    fs.writeFileSync(
      logs.client,
      materializeBase64Screenshots(`${flutter.stdout || ''}\n${flutter.stderr || ''}`),
    );
    if (flutter.error) {
      throw new Error(`flutter test failed: ${flutter.error.message}`);
    }
    if (flutter.status !== 0) {
      throw new Error(`flutter test failed with status ${flutter.status}`);
    }

    const screenshots = copyScreenshotsFromClientLog();
    fs.writeFileSync(path.join(runDir, 'result.json'), JSON.stringify({
      ok: true,
      case_id: testCase.id,
      run_id: runId,
      run_dir: runDir,
      report_md: path.join(runDir, 'report.md'),
      report_html: path.join(runDir, 'report.html'),
      screenshots,
    }, null, 2));
    writeHumanReport({ ok: true, screenshots });
    console.log(`PASS ${testCase.id}`);
    console.log(`Artifacts: ${runDir}`);
  } catch (error) {
    const screenshots = copyScreenshotsFromClientLog();
    fs.writeFileSync(path.join(runDir, 'result.json'), JSON.stringify({
      ok: false,
      case_id: testCase.id,
      run_id: runId,
      error: error.message || String(error),
      run_dir: runDir,
      report_md: path.join(runDir, 'report.md'),
      report_html: path.join(runDir, 'report.html'),
      screenshots,
    }, null, 2));
    const reportPath = writeBugReport(error);
    writeHumanReport({ ok: false, error, bugReportPath: reportPath, screenshots });
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
