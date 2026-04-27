#!/usr/bin/env node
import fs from 'node:fs';
import http from 'node:http';
import net from 'node:net';
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

function canBindPort(port, host) {
  return new Promise((resolve) => {
    const server = net.createServer();
    server.once('error', (error) => {
      resolve(error?.code !== 'EADDRINUSE');
    });
    server.once('listening', () => {
      server.close(() => resolve(true));
    });
    server.listen(port, host);
  });
}

async function ensurePortAvailable(port, label) {
  const hosts = ['127.0.0.1', '::'];
  for (const host of hosts) {
    if (!(await canBindPort(port, host))) {
      throw new Error(`Port ${port} (${label}) is already in use before starting UI E2E server`);
    }
  }
}

async function ensurePortsAvailable() {
  await ensurePortAvailable(httpPort, 'http');
  await ensurePortAvailable(upstreamPort, 'upstream');
  await ensurePortAvailable(mediaPort, 'media');
}

function waitForChildExit(child, timeoutMs) {
  if (child.exitCode !== null || child.signalCode !== null) {
    return Promise.resolve(true);
  }
  return new Promise((resolve) => {
    const timer = setTimeout(() => {
      child.off('exit', onExit);
      resolve(false);
    }, timeoutMs);
    const onExit = () => {
      clearTimeout(timer);
      resolve(true);
    };
    child.once('exit', onExit);
  });
}

function pidExists(pid) {
  if (!pid) return false;
  try {
    process.kill(pid, 0);
    return true;
  } catch {
    return false;
  }
}

async function terminateChild(child) {
  const pid = child.pid;
  if (!pidExists(pid)) return;
  child.kill('SIGTERM');
  await waitForChildExit(child, 1500);
  if (!pidExists(pid)) return;
  process.kill(pid, 'SIGKILL');
  await waitForChildExit(child, 1500);
}

async function terminateChildren(children) {
  for (const child of children.reverse()) {
    await terminateChild(child);
  }
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

function readLogText(file) {
  if (!fs.existsSync(file)) return '';
  return fs.readFileSync(file, 'utf8');
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

function caseModule() {
  return testCase.module || testCase.page || '未标注';
}

function caseObjective() {
  return testCase.objective || testCase.title || testCase.id;
}

function caseCoverageItems() {
  if (Array.isArray(testCase.coverage) && testCase.coverage.length > 0) {
    return testCase.coverage;
  }
  if (typeof testCase.coverage === 'string' && testCase.coverage.trim()) {
    return [testCase.coverage.trim()];
  }
  return [testCase.title || testCase.id];
}

function describeStep(step) {
  const action = step.action;
  switch (action) {
    case 'launch_app':
      return '启动测试客户端并等待主界面加载。';
    case 'create_conversation':
      return `新建会话：${step.name}${step.model ? `，选择模型 ${step.model}` : ''}${Array.isArray(step.skills) && step.skills.length > 0 ? `，选择 Skill ${step.skills.join(', ')}` : ''}。`;
    case 'send_message':
      return `在当前会话发送消息：${step.text}。`;
    case 'delete_conversation':
      return `删除会话：${step.name}。`;
    case 'wait_for_text':
      return `等待界面出现文本：${step.text}。`;
    case 'wait_for_absent_text':
      return `确认界面在 ${step.durationMs || 300}ms 内不出现文本：${step.text}。`;
    case 'tap_text':
      return `点击文本或按钮：${step.text}。`;
    case 'tap_filter_chip':
      return `点击筛选项：${step.text}。`;
    case 'tap_dialog_button':
      return `点击弹窗按钮：${step.text}。`;
    case 'enter_text_field':
      return `在第 ${Number(step.index) + 1} 个输入框输入：${step.text}。`;
    case 'tap_card_button':
      return `在包含「${step.cardText}」的卡片中点击「${step.buttonText}」。`;
    case 'tap_card_tooltip':
      return `在包含「${step.cardText}」的卡片中点击 tooltip 为「${step.tooltip}」的控件。`;
    case 'tap_card_switch':
      return `切换包含「${step.cardText}」的卡片开关。`;
    case 'wait_for_icon':
      return `等待图标出现：${step.icon}。`;
    case 'wait_for_absent_icon':
      return `确认图标在 ${step.durationMs || 300}ms 内不出现：${step.icon}。`;
    case 'tap_icon':
      return `点击图标：${step.icon}。`;
    case 'pump':
      return `等待 ${step.durationMs}ms。`;
    case 'wait_for_key':
      return `等待历史 key 出现：${step.key}。`;
    case 'tap_key':
      return `点击历史 key：${step.key}。`;
    case 'wait_for_absent_key':
      return `确认历史 key 在 ${step.durationMs || 300}ms 内不出现：${step.key}。`;
    default:
      return `执行动作：${JSON.stringify(step)}`;
  }
}

function runStats(screenshots) {
  const steps = Array.isArray(testCase.steps) ? testCase.steps : [];
  const assertions = Array.isArray(testCase.assert) ? testCase.assert : [];
  return {
    case_count: 1,
    step_count: steps.length,
    assertion_count: assertions.length,
    screenshot_count: screenshots.length,
    screenshot_policy: 'final_or_failure_snapshot',
  };
}

function classifyFailure(error) {
  const message = error?.message || String(error);
  const clientLog = readLogText(logs.client);
  const serverLog = readLogText(logs.server);
  const mockGatewayLog = readLogText(logs.mockGateway);
  const evidenceText = `${message}\n${clientLog}\n${serverLog}\n${mockGatewayLog}`;

  if (testCase.failurePolicy?.bugReport === 'product_bug') {
    return {
      type: 'product_bug',
      confidence: 'confirmed_by_case_policy',
      bugReportAllowed: true,
      summary: 'Case policy explicitly marks this failure as a product bug.',
      evidence: message,
    };
  }

  if (evidenceText.includes('ui_e2e_new_conversation_button')) {
    return {
      type: 'test_infrastructure',
      confidence: 'confirmed',
      bugReportAllowed: false,
      summary: '找不到新建会话测试标识，失败发生在 Gateway 交互之前。',
      evidence: "客户端日志包含：Found 0 widgets with key [<'ui_e2e_new_conversation_button'>]",
    };
  }

  if (/Unsupported operation: Unknown UI E2E action/.test(evidenceText)) {
    return {
      type: 'test_infrastructure',
      confidence: 'confirmed',
      bugReportAllowed: false,
      summary: 'The case uses an action that the UI E2E harness does not support.',
      evidence: 'client.log contains Unsupported operation for an unknown UI E2E action.',
    };
  }

  if (/Server health check timed out|server build failed|Port \d+ .*already in use|EADDRINUSE/.test(evidenceText)) {
    return {
      type: 'environment_or_setup',
      confidence: 'confirmed',
      bugReportAllowed: false,
      summary: 'The test environment did not start correctly.',
      evidence: message,
    };
  }

  if (!/\brecv\b/.test(mockGatewayLog)) {
    return {
      type: 'test_infrastructure',
      confidence: 'needs_investigation',
      bugReportAllowed: false,
      summary: 'The failure happened before Mock Gateway received any interaction.',
      evidence: 'mock-gateway.log has no recv evidence.',
    };
  }

  return {
    type: 'unclassified',
    confidence: 'needs_investigation',
    bugReportAllowed: false,
    summary: 'The runner cannot prove this is a product bug yet.',
    evidence: message,
  };
}

function writeHumanReport({
  ok,
  error,
  bugReportPath,
  diagnosticReportPath,
  screenshots,
  failure,
}) {
  const branch = gitValue(['branch', '--show-current']);
  const commit = gitValue(['rev-parse', '--short', 'HEAD']);
  const stats = runStats(screenshots);
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
  const coverageMarkdown = markdownList(caseCoverageItems());
  const stepMarkdown = (testCase.steps || [])
    .map((step, index) => `${index + 1}. ${describeStep(step)}`)
    .join('\n');
  const coverageHtml = `<ul>${caseCoverageItems()
    .map((item) => `<li>${escapeHtml(item)}</li>`)
    .join('')}</ul>`;
  const stepHtml = `<ol>${(testCase.steps || [])
    .map((step) => `<li>${escapeHtml(describeStep(step))}</li>`)
    .join('')}</ol>`;
  const statusValue = reportStatus(ok);
  const statusLabel = statusValue.toUpperCase();
  const diagnosisMarkdown = failure
    ? `\n## Diagnosis\n\n- failure_type: ${failure.type}\n- confidence: ${failure.confidence}\n- bug_report_allowed: ${failure.bugReportAllowed}\n- summary: ${failure.summary}\n- evidence: ${failure.evidence}\n`
    : '';
  const markdown = `# UI E2E Report: ${testCase.id}

## Summary

- status: ${statusValue}
- case_count: ${stats.case_count}
- step_count: ${stats.step_count}
- assertion_count: ${stats.assertion_count}
- screenshot_count: ${stats.screenshot_count}
- screenshot_policy: ${stats.screenshot_policy}
- case: ${testCase.id}
- module: ${caseModule()}
- title: ${testCase.title}
- objective: ${caseObjective()}
- run_id: ${runId}
- branch: ${branch}
- commit: ${commit}

## 测试目标

${caseObjective()}

## 测试内容

${coverageMarkdown}

## 测试步骤 / 复现步骤

${stepMarkdown}

## Conclusion

${ok ? '该 UI E2E 用例通过。' : `该 UI E2E 用例失败：${error?.message || String(error)}`}
${diagnosisMarkdown}

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
  ...(diagnosticReportPath ? [`diagnostic_report: ${diagnosticReportPath}`] : []),
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
    :root { color-scheme: light dark; }
    body { font-family: -apple-system, BlinkMacSystemFont, "Segoe UI", sans-serif; margin: 32px; color: CanvasText; background: Canvas; }
    main { max-width: 1080px; margin: 0 auto; padding: 28px; border: 1px solid GrayText; border-radius: 8px; }
    h1, h2 { margin-top: 0; }
    .badge { display: inline-block; padding: 4px 10px; border-radius: 999px; color: #fff; background: ${ok ? '#1f8f4d' : '#c93c37'}; font-weight: 700; }
    table { border-collapse: collapse; width: 100%; margin: 16px 0; }
    th, td { border: 1px solid GrayText; padding: 8px; text-align: left; }
    th { background: Field; color: FieldText; }
    pre { background: Field; color: FieldText; padding: 14px; overflow: auto; border-radius: 6px; }
    img { max-width: 100%; border: 1px solid GrayText; border-radius: 6px; }
    figure { margin: 16px 0; }
    figcaption { color: GrayText; font-size: 13px; margin-top: 6px; }
  </style>
</head>
<body>
<main>
  <h1>UI E2E Report: ${escapeHtml(testCase.id)}</h1>
  <p><span class="badge">${statusLabel}</span></p>
  <table>
    <tr><th>Case</th><td>${escapeHtml(testCase.id)}</td></tr>
    <tr><th>所属模块/页面</th><td>${escapeHtml(caseModule())}</td></tr>
    <tr><th>测试内容</th><td>${escapeHtml(testCase.title)}</td></tr>
    <tr><th>测试目标</th><td>${escapeHtml(caseObjective())}</td></tr>
    <tr><th>Run ID</th><td>${escapeHtml(runId)}</td></tr>
    <tr><th>Branch</th><td>${escapeHtml(branch)}</td></tr>
    <tr><th>Commit</th><td>${escapeHtml(commit)}</td></tr>
    <tr><th>status</th><td>${escapeHtml(statusValue)}</td></tr>
    <tr><th>case_count</th><td>${stats.case_count}</td></tr>
    <tr><th>step_count</th><td>${stats.step_count}</td></tr>
    <tr><th>assertion_count</th><td>${stats.assertion_count}</td></tr>
    <tr><th>screenshot_count</th><td>${stats.screenshot_count}</td></tr>
    <tr><th>screenshot_policy</th><td>${escapeHtml(stats.screenshot_policy)}</td></tr>
    ${failure ? `<tr><th>failure_type</th><td>${escapeHtml(failure.type)}</td></tr>
    <tr><th>confidence</th><td>${escapeHtml(failure.confidence)}</td></tr>
    <tr><th>bug_report_allowed</th><td>${escapeHtml(failure.bugReportAllowed)}</td></tr>` : ''}
  </table>
  <h2>测试目标</h2>
  <p>${escapeHtml(caseObjective())}</p>
  <h2>测试内容</h2>
  ${coverageHtml}
  <h2>测试步骤 / 复现步骤</h2>
  ${stepHtml}
  <h2>Conclusion</h2>
  <p>${escapeHtml(ok ? '该 UI E2E 用例通过。' : `该 UI E2E 用例失败：${error?.message || String(error)}`)}</p>
  ${failure ? `<h2>Diagnosis</h2>
  <table>
    <tr><th>failure_type</th><td>${escapeHtml(failure.type)}</td></tr>
    <tr><th>confidence</th><td>${escapeHtml(failure.confidence)}</td></tr>
    <tr><th>bug_report_allowed</th><td>${escapeHtml(failure.bugReportAllowed)}</td></tr>
    <tr><th>summary</th><td>${escapeHtml(failure.summary)}</td></tr>
    <tr><th>evidence</th><td>${escapeHtml(failure.evidence)}</td></tr>
  </table>` : ''}
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
    ${diagnosticReportPath ? `<li>diagnostic_report: ${escapeHtml(diagnosticReportPath)}</li>` : ''}
  </ul>
</main>
</body>
</html>
`;
  fs.writeFileSync(path.join(runDir, 'report.html'), html);
  return reportMd;
}

function writeBugReport(error, failure) {
  const templatePath = path.join(root, 'test', 'ui-e2e', 'templates', 'bug-report.md');
  const template = fs.readFileSync(templatePath, 'utf8');
  const branch = gitValue(['branch', '--show-current']);
  const report = template
    .replaceAll('{{case_id}}', testCase.id)
    .replaceAll('{{case_title}}', testCase.title)
    .replaceAll('{{run_id}}', runId)
    .replaceAll('{{branch}}', branch)
    .replaceAll('{{summary}}', `Case failed: ${testCase.title} (${failure.type})`)
    .replaceAll('{{expected}}', JSON.stringify(testCase.assert, null, 2))
    .replaceAll('{{actual}}', `${error.message || String(error)}\n\nDiagnosis: ${failure.summary}\nEvidence: ${failure.evidence}`)
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

function writeDiagnosticReport(error, failure, screenshots) {
  const reportPath = path.join(runDir, 'diagnostic-report.md');
  const screenshotMarkdown = screenshots.length === 0
    ? '没有采集到截图。'
    : screenshots.map((shot, index) => `![失败截图 ${index + 1}](${shot})`).join('\n\n');
  const report = `# UI E2E 诊断报告：${testCase.id}

## 失败分类

- failure_type: ${failure.type}
- confidence: ${failure.confidence}
- bug_report_allowed: ${failure.bugReportAllowed}

## 结论

这次失败暂不提交为产品 Bug，因为当前证据显示它属于测试基础设施、环境配置，或尚未完成归因。

## 原因摘要

${failure.summary}

## 证据

${failure.evidence}

## 失败截图

${screenshotMarkdown}

## 原始错误

\`\`\`text
${error.message || String(error)}
\`\`\`

## 运行产物

- run_dir: ${runDir}
- server_log: ${logs.server}
- client_log: ${logs.client}
- mock_gateway_log: ${logs.mockGateway}
- screenshot_dir: ${path.join(runDir, 'screenshots')}
`;
  fs.writeFileSync(reportPath, report);
  return reportPath;
}

async function main() {
  writeTestConfig();
  buildServer();
  await ensurePortsAvailable();

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
          module: caseModule(),
          title: testCase.title,
          objective: caseObjective(),
          coverage: caseCoverageItems(),
          run_id: runId,
      run_dir: runDir,
      report_md: path.join(runDir, 'report.md'),
      report_html: path.join(runDir, 'report.html'),
      screenshots,
      ...runStats(screenshots),
    }, null, 2));
    writeHumanReport({ ok: true, screenshots });
    console.log(`PASS ${testCase.id}`);
    console.log(`Artifacts: ${runDir}`);
  } catch (error) {
    const screenshots = copyScreenshotsFromClientLog();
    const failure = classifyFailure(error);
    const bugReportPath = failure.type === 'product_bug'
      ? writeBugReport(error, failure)
      : null;
    const diagnosticReportPath = failure.type === 'product_bug'
      ? null
      : writeDiagnosticReport(error, failure, screenshots);
        fs.writeFileSync(path.join(runDir, 'result.json'), JSON.stringify({
          ok: false,
          case_id: testCase.id,
          module: caseModule(),
          title: testCase.title,
          objective: caseObjective(),
          coverage: caseCoverageItems(),
          run_id: runId,
      error: error.message || String(error),
      failure_type: failure.type,
      failure_confidence: failure.confidence,
      bug_report_allowed: failure.bugReportAllowed,
      failure_summary: failure.summary,
      failure_evidence: failure.evidence,
      run_dir: runDir,
      report_md: path.join(runDir, 'report.md'),
      report_html: path.join(runDir, 'report.html'),
      ...(bugReportPath ? { bug_report: bugReportPath } : {}),
      ...(diagnosticReportPath ? { diagnostic_report: diagnosticReportPath } : {}),
      screenshots,
      ...runStats(screenshots),
    }, null, 2));
    writeHumanReport({
      ok: false,
      error,
      bugReportPath,
      diagnosticReportPath,
      screenshots,
      failure,
    });
    console.error(`FAIL ${testCase.id}`);
    if (bugReportPath) console.error(`Bug report: ${bugReportPath}`);
    if (diagnosticReportPath) console.error(`Diagnostic report: ${diagnosticReportPath}`);
    console.error(`Artifacts: ${runDir}`);
    process.exitCode = 1;
  } finally {
    await terminateChildren(children);
  }
}

main();
