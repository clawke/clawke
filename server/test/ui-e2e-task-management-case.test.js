const assert = require('node:assert/strict');
const { readFileSync } = require('node:fs');
const { join } = require('node:path');
const test = require('node:test');

const root = join(__dirname, '..', '..');
const casePath = join(
  root,
  'test',
  'ui-e2e',
  'test-cases',
  'p0-tasks-management-lifecycle.json',
);
const mockGateway = readFileSync(
  join(root, 'test', 'ui-e2e', 'tools', 'mock-gateway.mjs'),
  'utf8',
);

test('task management lifecycle case documents module, objective, and coverage', () => {
  const testCase = JSON.parse(readFileSync(casePath, 'utf8'));

  assert.equal(testCase.id, 'p0-tasks-management-lifecycle');
  assert.equal(testCase.module, '任务管理');
  assert.match(testCase.title, /新增、查看、编辑、暂停、启用、立即执行和删除任务/);
  assert.ok(testCase.objective.includes('任务管理页面'));
  assert.ok(testCase.coverage.length >= 6);
  assert.ok(testCase.setup.capabilities.includes('tasks'));
  assert.ok(testCase.mockGateway.tasks.length >= 1);
  assert.doesNotMatch(JSON.stringify(testCase), /ui_e2e_/);
});

test('task management lifecycle case covers core UI task operations', () => {
  const testCase = JSON.parse(readFileSync(casePath, 'utf8'));
  const actions = testCase.steps.map((step) => `${step.action}:${step.text || step.buttonText || step.tooltip || step.icon || ''}`);

  assert.ok(actions.includes('tap_text:任务管理'));
  assert.ok(actions.includes('tap_text:新建任务'));
  assert.ok(actions.includes('tap_text:编辑'));
  assert.ok(actions.includes('tap_dialog_button:立即执行'));
  assert.ok(actions.includes('wait_for_text:确认立即执行任务'));
  assert.ok(actions.includes('tap_dialog_button:确认执行'));
  assert.ok(actions.includes('tap_icon:arrow_back'));
  assert.ok(actions.includes('wait_for_text:已暂停'));
  assert.ok(actions.includes('tap_filter_chip:已启用'));
  assert.ok(actions.includes('tap_text:删除任务'));
  assert.ok(actions.includes('tap_dialog_button:删除'));
});

test('UI E2E mock gateway supports task management protocol', () => {
  for (const type of [
    'task_list',
    'task_get',
    'task_create',
    'task_update',
    'task_delete',
    'task_set_enabled',
    'task_run',
    'task_runs',
    'task_output',
  ]) {
    assert.match(mockGateway, new RegExp(`incoming\\.type === '${type}'`));
  }

  assert.match(mockGateway, /task_list_response/);
  assert.match(mockGateway, /task_mutation_response/);
  assert.match(mockGateway, /task_run_response/);
  assert.match(mockGateway, /task_runs_response/);
  assert.match(mockGateway, /task_output_response/);
  assert.doesNotMatch(mockGateway, /taskFromDraft\(\{ \.\.\.existing, \.\.\.\(incoming\.patch/);
  assert.match(mockGateway, /account_id: existing\.account_id/);
});
