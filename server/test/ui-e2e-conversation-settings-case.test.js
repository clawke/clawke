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
  'p0-conversation-settings-model-skill-chat.json',
);
const harness = readFileSync(
  join(root, 'client', 'integration_test', 'ui_e2e_app_test.dart'),
  'utf8',
);
const mockGateway = readFileSync(
  join(root, 'test', 'ui-e2e', 'tools', 'mock-gateway.mjs'),
  'utf8',
);
const runner = readFileSync(
  join(root, 'test', 'ui-e2e', 'tools', 'runner.mjs'),
  'utf8',
);

test('conversation settings case covers model, skill, chat, and delete lifecycle', () => {
  const testCase = JSON.parse(readFileSync(casePath, 'utf8'));

  assert.equal(testCase.id, 'p0-conversation-settings-model-skill-chat');
  assert.equal(testCase.module, '会话设置');
  assert.ok(testCase.coverage.includes('新建会话并选择模型'));
  assert.ok(testCase.coverage.includes('选择 skill 并保存配置'));
  assert.ok(testCase.coverage.includes('发送消息并验证 Gateway 收到模型和 skill 配置'));
  assert.ok(testCase.coverage.includes('删除测试会话'));
  assert.doesNotMatch(JSON.stringify(testCase), /ui_e2e_/);

  const createStep = testCase.steps.find((step) => step.action === 'create_conversation');
  assert.equal(createStep.model, 'e2e-config-model');
  assert.deepEqual(createStep.skills, ['e2e-chat-skill']);

  assert.ok(testCase.steps.some((step) => step.action === 'send_message'));
  assert.ok(testCase.steps.some((step) => step.action === 'delete_conversation'));
  assert.deepEqual(testCase.mockGateway.models, ['e2e-config-model']);
  assert.ok(testCase.mockGateway.skills.some((skill) => skill.name === 'e2e-chat-skill'));
});

test('UI E2E harness supports configuring and deleting conversations without injected keys', () => {
  assert.match(harness, /case 'delete_conversation':/);
  assert.match(harness, /Future<void> _deleteConversation/);
  assert.match(harness, /Future<void> _selectConversationModel/);
  assert.match(harness, /Future<void> _selectConversationSkills/);
  assert.doesNotMatch(harness, /ui_e2e_/);
});

test('mock gateway supports configured model list and config-aware chat matching', () => {
  assert.match(mockGateway, /testCase\.mockGateway\?\.models/);
  assert.match(mockGateway, /model_override/);
  assert.match(mockGateway, /skills_hint/);
  assert.match(mockGateway, /skillsHintIncludes/);
});

test('UI E2E runner rejects stale occupied ports and waits for child cleanup', () => {
  assert.match(runner, /async function ensurePortsAvailable/);
  assert.match(runner, /Port \$\{port\} \(\$\{label\}\) is already in use/);
  assert.match(runner, /async function terminateChildren/);
  assert.match(runner, /function pidExists/);
  assert.match(runner, /SIGKILL/);
});
