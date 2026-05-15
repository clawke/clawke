#!/usr/bin/env node
import fs from 'node:fs';
import path from 'node:path';
import { spawnSync } from 'node:child_process';
import { fileURLToPath } from 'node:url';

const root = path.resolve(new URL('../../..', import.meta.url).pathname);
const defaultCaseDir = path.join(root, 'test', 'ui-e2e', 'test-cases');
const defaultSuiteRoot = path.join(root, 'test', 'ui-e2e', 'suites');

function parseArgs(argv) {
  const out = {
    cases: [],
    bail: false,
  };
  for (let i = 0; i < argv.length; i += 1) {
    const item = argv[i];
    if (!item.startsWith('--')) continue;
    const key = item.slice(2);
    const next = argv[i + 1];
    if (key === 'case' && next && !next.startsWith('--')) {
      out.cases.push(...next.split(',').map((value) => value.trim()).filter(Boolean));
      i += 1;
    } else if (key === 'bail') {
      out.bail = true;
    } else if (next && !next.startsWith('--')) {
      out[key] = next;
      i += 1;
    } else {
      out[key] = true;
    }
  }
  return out;
}

function escapeHtml(value) {
  return String(value ?? '')
    .replaceAll('&', '&amp;')
    .replaceAll('<', '&lt;')
    .replaceAll('>', '&gt;')
    .replaceAll('"', '&quot;');
}

function gitValue(argv) {
  return spawnSync('git', argv, {
    cwd: root,
    encoding: 'utf8',
  }).stdout.trim();
}

export function discoverCases({ caseDir = defaultCaseDir, selectedCaseIds = [] } = {}) {
  const allCases = fs.readdirSync(caseDir)
    .filter((file) => file.endsWith('.json'))
    .sort()
    .map((file) => {
      const data = JSON.parse(fs.readFileSync(path.join(caseDir, file), 'utf8'));
      return {
        id: data.id || path.basename(file, '.json'),
        title: data.title || data.id || path.basename(file, '.json'),
        module: data.module || data.page || '',
        file: path.join(caseDir, file),
      };
    });
  if (selectedCaseIds.length === 0) return allCases;

  const selected = allCases.filter((testCase) => selectedCaseIds.includes(testCase.id));
  const found = new Set(selected.map((testCase) => testCase.id));
  const missing = selectedCaseIds.filter((caseId) => !found.has(caseId));
  if (missing.length > 0) {
    throw new Error(`Unknown UI E2E case: ${missing.join(', ')}`);
  }
  return selected;
}

function reportStatus(ok) {
  return ok ? 'success' : 'fail';
}

function normalizeCaseResult(item) {
  return {
    ...item,
    status: reportStatus(item.ok),
    module: item.module || '',
    step_count: Number(item.step_count || 0),
    assertion_count: Number(item.assertion_count || 0),
    screenshot_count: Number(item.screenshot_count || 0),
    failure_type: item.failure_type || '',
    bug_report_allowed: item.bug_report_allowed ?? '',
    diagnostic_report: item.diagnostic_report || '',
    bug_report: item.bug_report || '',
  };
}

export function writeSuiteReport({
  suiteDir,
  suiteId,
  branch,
  commit,
  caseResults,
}) {
  fs.mkdirSync(suiteDir, { recursive: true });
  const normalized = caseResults.map(normalizeCaseResult);
  const passedCount = normalized.filter((item) => item.ok).length;
  const failedCount = normalized.length - passedCount;
  const totalStepCount = normalized.reduce((sum, item) => sum + item.step_count, 0);
  const totalAssertionCount = normalized.reduce((sum, item) => sum + item.assertion_count, 0);
  const totalScreenshotCount = normalized.reduce((sum, item) => sum + item.screenshot_count, 0);
  const status = failedCount === 0 ? 'success' : 'fail';

  const result = {
    ok: failedCount === 0,
    status,
    suite_id: suiteId,
    report_md: path.join(suiteDir, 'report.md'),
    report_html: path.join(suiteDir, 'report.html'),
    result_json: path.join(suiteDir, 'result.json'),
    total_count: normalized.length,
    passed_count: passedCount,
    failed_count: failedCount,
    total_step_count: totalStepCount,
    total_assertion_count: totalAssertionCount,
    total_screenshot_count: totalScreenshotCount,
    branch,
    commit,
    case_results: normalized,
  };

  const markdownRows = normalized.map((item) => [
    item.status,
    item.case_id,
    item.module || '',
    item.title || '',
    item.step_count,
    item.assertion_count,
    item.screenshot_count,
    item.failure_type,
    item.bug_report_allowed,
    item.report_html || '',
    item.diagnostic_report || '',
    item.bug_report || '',
    item.error || '',
  ].join(' | '));
  const markdown = `# UI E2E Suite Report

## Summary

- status: ${status}
- total_count: ${result.total_count}
- passed_count: ${result.passed_count}
- failed_count: ${result.failed_count}
- total_step_count: ${result.total_step_count}
- total_assertion_count: ${result.total_assertion_count}
- total_screenshot_count: ${result.total_screenshot_count}
- suite_id: ${suiteId}
- branch: ${branch}
- commit: ${commit}

## 用例列表

status | case_id | 所属模块/页面 | 测试内容 | step_count | assertion_count | screenshot_count | failure_type | bug_report_allowed | report_html | diagnostic_report | bug_report | error
--- | --- | --- | --- | ---: | ---: | ---: | --- | --- | --- | --- | --- | ---
${markdownRows.join('\n') || '无 | 无 | 无 | 无 | 0 | 0 | 0 | 无 | 无 | 无 | 无 | 无 | 无'}
`;
  fs.writeFileSync(result.report_md, markdown);

  const rows = normalized.map((item) => `<tr>
    <td>${escapeHtml(item.status)}</td>
    <td>${escapeHtml(item.case_id)}</td>
    <td>${escapeHtml(item.module || '')}</td>
    <td>${escapeHtml(item.title || '')}</td>
    <td>${item.step_count}</td>
    <td>${item.assertion_count}</td>
    <td>${item.screenshot_count}</td>
    <td>${escapeHtml(item.failure_type)}</td>
    <td>${escapeHtml(item.bug_report_allowed)}</td>
    <td>${item.report_html ? `<a href="${escapeHtml(item.report_html)}">report.html</a>` : ''}</td>
    <td>${item.diagnostic_report ? `<a href="${escapeHtml(item.diagnostic_report)}">diagnostic</a>` : ''}</td>
    <td>${item.bug_report ? `<a href="${escapeHtml(item.bug_report)}">bug</a>` : ''}</td>
    <td>${escapeHtml(item.error || '')}</td>
  </tr>`).join('\n');
  const html = `<!doctype html>
<html lang="zh-CN">
<head>
  <meta charset="utf-8">
  <title>UI E2E Suite Report</title>
  <style>
    :root { color-scheme: light dark; }
    body { font-family: -apple-system, BlinkMacSystemFont, "Segoe UI", sans-serif; margin: 32px; color: CanvasText; background: Canvas; }
    main { max-width: 1180px; margin: 0 auto; padding: 28px; border: 1px solid GrayText; border-radius: 8px; }
    h1 { margin-top: 0; }
    .badge { display: inline-block; padding: 4px 10px; border-radius: 999px; color: #fff; background: ${status === 'success' ? '#1f8f4d' : '#c93c37'}; font-weight: 700; }
    table { border-collapse: collapse; width: 100%; margin: 16px 0; }
    th, td { border: 1px solid GrayText; padding: 8px; text-align: left; vertical-align: top; }
    th { background: Field; color: FieldText; }
    a { color: LinkText; }
  </style>
</head>
<body>
<main>
  <h1>UI E2E Suite Report</h1>
  <p><span class="badge">${escapeHtml(status.toUpperCase())}</span></p>
  <table>
    <tr><th>status</th><td>${escapeHtml(status)}</td></tr>
    <tr><th>total_count</th><td>${result.total_count}</td></tr>
    <tr><th>passed_count</th><td>${result.passed_count}</td></tr>
    <tr><th>failed_count</th><td>${result.failed_count}</td></tr>
    <tr><th>total_step_count</th><td>${result.total_step_count}</td></tr>
    <tr><th>total_assertion_count</th><td>${result.total_assertion_count}</td></tr>
    <tr><th>total_screenshot_count</th><td>${result.total_screenshot_count}</td></tr>
    <tr><th>suite_id</th><td>${escapeHtml(suiteId)}</td></tr>
    <tr><th>branch</th><td>${escapeHtml(branch)}</td></tr>
    <tr><th>commit</th><td>${escapeHtml(commit)}</td></tr>
  </table>
  <table>
    <thead>
      <tr>
        <th>status</th>
        <th>case_id</th>
        <th>所属模块/页面</th>
        <th>测试内容</th>
        <th>step_count</th>
        <th>assertion_count</th>
        <th>screenshot_count</th>
        <th>failure_type</th>
        <th>bug_report_allowed</th>
        <th>report</th>
        <th>diagnostic</th>
        <th>bug</th>
        <th>error</th>
      </tr>
    </thead>
    <tbody>
      ${rows || '<tr><td colspan="13">无</td></tr>'}
    </tbody>
  </table>
</main>
</body>
</html>
`;
  fs.writeFileSync(result.report_html, html);
  fs.writeFileSync(result.result_json, `${JSON.stringify(result, null, 2)}\n`);
  return result;
}

function latestResultForCase(caseId) {
  const runsDir = path.join(root, 'test', 'ui-e2e', 'runs');
  if (!fs.existsSync(runsDir)) return null;
  const candidates = fs.readdirSync(runsDir)
    .filter((name) => name.endsWith(`-${caseId}`))
    .map((name) => {
      const resultPath = path.join(runsDir, name, 'result.json');
      if (!fs.existsSync(resultPath)) return null;
      return {
        resultPath,
        mtimeMs: fs.statSync(resultPath).mtimeMs,
      };
    })
    .filter(Boolean)
    .sort((a, b) => b.mtimeMs - a.mtimeMs);
  if (candidates.length === 0) return null;
  return JSON.parse(fs.readFileSync(candidates[0].resultPath, 'utf8'));
}

function readCaseResult(output, caseId) {
  const artifactsMatch = [...output.matchAll(/^Artifacts:\s*(.+)$/gm)].pop();
  if (artifactsMatch) {
    const resultPath = path.join(artifactsMatch[1].trim(), 'result.json');
    if (fs.existsSync(resultPath)) {
      return JSON.parse(fs.readFileSync(resultPath, 'utf8'));
    }
  }
  return latestResultForCase(caseId);
}

function runCase(testCase, { noPub = false } = {}) {
  console.log(`SUITE_CASE_START ${testCase.id}`);
  const runnerPath = path.join(root, 'test', 'ui-e2e', 'tools', 'runner.mjs');
  const runnerArgs = [runnerPath, '--case', testCase.id];
  if (noPub) runnerArgs.push('--no-pub');
  const child = spawnSync('node', runnerArgs, {
    cwd: root,
    encoding: 'utf8',
    maxBuffer: 1024 * 1024 * 30,
    timeout: 8 * 60 * 1000,
  });
  const output = `${child.stdout || ''}\n${child.stderr || ''}`;
  if (child.stdout) process.stdout.write(child.stdout);
  if (child.stderr) process.stderr.write(child.stderr);
  const result = readCaseResult(output, testCase.id);
  if (result) {
    return {
      title: testCase.title,
      module: testCase.module,
      ...result,
    };
  }
  return {
    ok: false,
    case_id: testCase.id,
    title: testCase.title,
    module: testCase.module,
    error: child.error?.message || `runner exited with status ${child.status}`,
  };
}

async function main() {
  const args = parseArgs(process.argv.slice(2));
  const suiteId = new Date().toISOString().replace(/[:.]/g, '-');
  const suiteDir = path.join(defaultSuiteRoot, suiteId);
  const cases = discoverCases({ selectedCaseIds: args.cases });
  const caseResults = [];

  for (const testCase of cases) {
    const result = runCase(testCase, { noPub: Boolean(args['no-pub']) });
    caseResults.push(result);
    if (args.bail && !result.ok) break;
  }

  const report = writeSuiteReport({
    suiteDir,
    suiteId,
    branch: gitValue(['branch', '--show-current']),
    commit: gitValue(['rev-parse', '--short', 'HEAD']),
    caseResults,
  });
  console.log(`SUITE ${report.status}`);
  console.log(`Suite report: ${report.report_html}`);
  console.log(`Suite artifacts: ${suiteDir}`);
  process.exitCode = report.ok ? 0 : 1;
}

const isMain = process.argv[1]
  && path.resolve(process.argv[1]) === fileURLToPath(import.meta.url);
if (isMain) {
  main().catch((error) => {
    console.error(error.stack || error.message || String(error));
    process.exitCode = 1;
  });
}
