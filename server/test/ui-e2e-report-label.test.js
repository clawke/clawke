const assert = require('node:assert/strict');
const { readFileSync } = require('node:fs');
const { join } = require('node:path');
const test = require('node:test');

const root = join(__dirname, '..', '..');
const runner = readFileSync(
  join(root, 'test', 'ui-e2e', 'tools', 'runner.mjs'),
  'utf8',
);

test('UI E2E human report displays result status instead of demo fail flag', () => {
  assert.doesNotMatch(runner, /Demo Fail/);
  assert.doesNotMatch(runner, /demo_fail:/);
  assert.doesNotMatch(runner, /测试结果/);
  assert.match(runner, /function reportStatus\(ok\)/);
  assert.match(runner, /- status: \$\{statusValue\}/);
  assert.match(
    runner,
    /<tr><th>status<\/th><td>\$\{escapeHtml\(statusValue\)\}<\/td><\/tr>/,
  );
});

test('UI E2E human report exposes case, step, assertion, and screenshot counts', () => {
  assert.match(runner, /function runStats\(screenshots\)/);
  assert.match(runner, /case_count: 1/);
  assert.match(runner, /step_count: steps\.length/);
  assert.match(runner, /assertion_count: assertions\.length/);
  assert.match(runner, /screenshot_count: screenshots\.length/);
  assert.match(runner, /screenshot_policy: 'final_or_failure_snapshot'/);
  assert.match(runner, /- case_count: \$\{stats\.case_count\}/);
  assert.match(runner, /- step_count: \$\{stats\.step_count\}/);
  assert.match(runner, /- assertion_count: \$\{stats\.assertion_count\}/);
  assert.match(runner, /- screenshot_count: \$\{stats\.screenshot_count\}/);
  assert.match(
    runner,
    /<tr><th>case_count<\/th><td>\$\{stats\.case_count\}<\/td><\/tr>/,
  );
  assert.match(
    runner,
    /<tr><th>step_count<\/th><td>\$\{stats\.step_count\}<\/td><\/tr>/,
  );
  assert.match(
    runner,
    /<tr><th>screenshot_count<\/th><td>\$\{stats\.screenshot_count\}<\/td><\/tr>/,
  );
  assert.match(runner, /\.\.\.runStats\(screenshots\)/);
});

test('UI E2E human report uses system colors instead of fixed light backgrounds', () => {
  assert.doesNotMatch(runner, /background:\s*#fff\b/i);
  assert.doesNotMatch(runner, /background:\s*#f6f7f9\b/i);
  assert.doesNotMatch(runner, /background:\s*#eef2f6\b/i);
  assert.match(runner, /color-scheme:\s*light dark/);
  assert.match(runner, /background:\s*Canvas/);
  assert.match(runner, /color:\s*CanvasText/);
});

test('UI E2E runner classifies failures before filing bug reports', () => {
  assert.match(runner, /function classifyFailure\(error\)/);
  assert.match(runner, /type: 'test_infrastructure'/);
  assert.match(runner, /ui_e2e_new_conversation_button/);
  assert.match(runner, /function writeDiagnosticReport\(error, failure, screenshots\)/);
  assert.match(runner, /const failure = classifyFailure\(error\)/);
  assert.match(runner, /failure\.type === 'product_bug'/);
  assert.match(runner, /writeBugReport\(error, failure\)/);
  assert.match(runner, /writeDiagnosticReport\(error, failure, screenshots\)/);
  assert.doesNotMatch(
    runner,
    /const reportPath = writeBugReport\(error\);\s*writeHumanReport/s,
  );
});

test('UI E2E diagnostic report is Chinese and embeds screenshots', () => {
  assert.match(runner, /# UI E2E 诊断报告/);
  assert.match(runner, /## 失败分类/);
  assert.match(runner, /## 失败截图/);
  assert.match(runner, /找不到新建会话测试标识/);
  assert.match(runner, /客户端日志包含/);
  assert.match(runner, /screenshots\.map\(\(shot\)/);
  assert.match(runner, /!\[失败截图 \$\{index \+ 1\}\]\(\$\{shot\}\)/);
  assert.match(runner, /没有采集到截图/);
});

test('UI E2E human report includes test objective, coverage, and reproducible steps', () => {
  assert.match(runner, /function caseModule\(\)/);
  assert.match(runner, /function caseObjective\(\)/);
  assert.match(runner, /function caseCoverageItems\(\)/);
  assert.match(runner, /function describeStep\(step\)/);
  assert.match(runner, /## 测试目标/);
  assert.match(runner, /## 测试内容/);
  assert.match(runner, /## 测试步骤 \/ 复现步骤/);
  assert.match(runner, /<h2>测试目标<\/h2>/);
  assert.match(runner, /<h2>测试内容<\/h2>/);
  assert.match(runner, /<h2>测试步骤 \/ 复现步骤<\/h2>/);
  assert.match(runner, /<tr><th>所属模块\/页面<\/th><td>\$\{escapeHtml\(caseModule\(\)\)\}<\/td><\/tr>/);
  assert.match(runner, /<tr><th>测试内容<\/th><td>\$\{escapeHtml\(testCase\.title\)\}<\/td><\/tr>/);
});

test('UI E2E runner can inject SkillHub API base URL for live catalog cases', () => {
  assert.match(runner, /apiBaseUrl: setup\.skillHubApiBaseUrl \|\| 'https:\/\/api\.clawke\.ai'/);
});
