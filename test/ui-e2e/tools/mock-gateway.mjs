#!/usr/bin/env node
import { createRequire } from 'node:module';
import fs from 'node:fs';
import path from 'node:path';

const requireFromServer = createRequire(new URL('../../../server/package.json', import.meta.url));
const WebSocket = requireFromServer('ws');

const args = parseArgs(process.argv.slice(2));
const casePath = required(args, 'case');
const upstreamUrl = required(args, 'upstream-url');
const logPath = required(args, 'log');
const testCase = JSON.parse(fs.readFileSync(casePath, 'utf8'));
const setup = testCase.setup || {};
const accountId = setup.accountId || 'e2e_mock';
const agentName = setup.agentName || 'E2E Mock Gateway';
const gatewayType = setup.gatewayType || 'mock';
const capabilities = setup.capabilities || ['chat', 'tasks', 'skills', 'models'];
const consumedInteractions = new Set();
const models = Array.isArray(testCase.mockGateway?.models)
  ? testCase.mockGateway.models.map(String)
  : ['e2e-mock-model'];
const skills = new Map(
  (testCase.mockGateway?.skills || []).map((skill) => [skill.id, normalizeSkill(skill)]),
);
const tasks = new Map();
const taskRuns = new Map();
const taskOutputs = new Map();

for (const rawTask of testCase.mockGateway?.tasks || []) {
  const task = normalizeTask(rawTask);
  tasks.set(task.id, task);
  const runs = (rawTask.runs || []).map((run) => normalizeRun(run, task.id));
  if (runs.length > 0) taskRuns.set(task.id, runs);
  for (const run of runs) {
    if (run.output) taskOutputs.set(`${task.id}:${run.id}`, String(run.output));
  }
}

fs.mkdirSync(path.dirname(logPath), { recursive: true });
const logStream = fs.createWriteStream(logPath, { flags: 'a' });

function log(message) {
  const line = `[mock-gateway] ${new Date().toISOString()} ${message}`;
  console.log(line);
  logStream.write(`${line}\n`);
}

function parseArgs(argv) {
  const out = {};
  for (let i = 0; i < argv.length; i += 2) {
    out[argv[i].replace(/^--/, '')] = argv[i + 1];
  }
  return out;
}

function required(map, key) {
  if (!map[key]) {
    console.error(`Missing --${key}`);
    process.exit(2);
  }
  return map[key];
}

function withConversation(reply, incoming) {
  const { delayMs, ...wireReply } = reply;
  return {
    ...wireReply,
    conversation_id: incoming.conversation_id || accountId,
  };
}

function sleep(ms) {
  return new Promise((resolve) => setTimeout(resolve, ms));
}

async function sendReplyList(ws, incoming, replies) {
  for (const reply of replies || []) {
    await sleep(reply.delayMs || 40);
    const payload = withConversation(reply, incoming);
    log(`send ${JSON.stringify(payload)}`);
    ws.send(JSON.stringify(payload));
  }
}

function incomingText(msg) {
  return String(msg.text || msg.response || msg.choice || '');
}

function matches(on, incoming) {
  if (on.type && incoming.type !== on.type) return false;
  if (on.text && incoming.text !== on.text) return false;
  if (on.equals && incomingText(incoming) !== on.equals) return false;
  if (on.contains && !incomingText(incoming).includes(on.contains)) return false;
  if (on.choice && incoming.choice !== on.choice) return false;
  if (on.response && incoming.response !== on.response) return false;
  if (on.model_override && incoming.model_override !== on.model_override) return false;
  if (on.modelOverride && incoming.model_override !== on.modelOverride) return false;
  if (on.skill_mode && incoming.skill_mode !== on.skill_mode) return false;
  if (on.skillMode && incoming.skill_mode !== on.skillMode) return false;
  const exactSkills = on.skills_hint || on.skillsHint;
  if (Array.isArray(exactSkills)) {
    const incomingSkills = Array.isArray(incoming.skills_hint) ? incoming.skills_hint : [];
    if (exactSkills.length !== incomingSkills.length) return false;
    for (const skill of exactSkills.map(String)) {
      if (!incomingSkills.includes(skill)) return false;
    }
  }
  const requiredSkills = on.skills_hint_includes || on.skillsHintIncludes;
  if (Array.isArray(requiredSkills)) {
    const incomingSkills = Array.isArray(incoming.skills_hint) ? incoming.skills_hint : [];
    for (const skill of requiredSkills.map(String)) {
      if (!incomingSkills.includes(skill)) return false;
    }
  }
  return true;
}

async function sendScriptedInteraction(ws, incoming) {
  const interactions = testCase.mockGateway?.interactions;
  if (!Array.isArray(interactions)) return false;

  for (let i = 0; i < interactions.length; i += 1) {
    if (consumedInteractions.has(i)) continue;
    const interaction = interactions[i];
    if (!matches(interaction.on || {}, incoming)) continue;
    consumedInteractions.add(i);
    await sendReplyList(ws, incoming, interaction.replies || []);
    return true;
  }
  log(`unmatched ${JSON.stringify(incoming)}`);
  return false;
}

async function sendLegacyUserMessageReplies(ws, incoming) {
  const rule = testCase.mockGateway?.onUserMessage;
  if (!rule || incoming.type !== 'chat') return false;
  const text = incoming.text || '';
  if (rule.contains && !text.includes(rule.contains)) {
    log(`ignored chat text="${text}"`);
    return true;
  }

  await sendReplyList(ws, incoming, rule.replies || []);
  return true;
}

function normalizeSkill(skill) {
  const category = String(skill.category || 'general');
  const name = String(skill.name || skill.id?.split('/').pop() || 'unnamed');
  const id = String(skill.id || `${category}/${name}`);
  const body = skill.body || `# ${name}\n`;
  return {
    id,
    name,
    description: String(skill.description || `${name} description`),
    category,
    trigger: skill.trigger || '',
    enabled: skill.enabled !== false,
    source: skill.source || 'managed',
    sourceLabel: skill.sourceLabel || 'Clawke managed',
    writable: skill.writable !== false,
    deletable: skill.deletable !== false,
    path: skill.path || `${category}/${name}/SKILL.md`,
    absolutePath: skill.absolutePath || `/tmp/clawke-e2e-skills/${category}/${name}/SKILL.md`,
    root: skill.root || '/tmp/clawke-e2e-skills',
    updatedAt: Number(skill.updatedAt || Date.now()),
    hasConflict: skill.hasConflict === true,
    body,
    content: skill.content || renderSkillContent({ name, category, description: skill.description || `${name} description`, trigger: skill.trigger || '', body }),
  };
}

function renderSkillContent(skill) {
  return [
    '---',
    `name: ${skill.name}`,
    `description: ${skill.description}`,
    `category: ${skill.category || 'general'}`,
    ...(skill.trigger ? [`trigger: ${skill.trigger}`] : []),
    '---',
    '',
    skill.body || `# ${skill.name}`,
    '',
  ].join('\n');
}

function skillFromDraft(draft, existing = {}) {
  const category = String(draft.category || existing.category || 'general');
  const name = String(draft.name || existing.name || 'unnamed');
  const description = String(draft.description || existing.description || '');
  const trigger = draft.trigger || existing.trigger || '';
  const body = draft.body || existing.body || `# ${name}\n`;
  const next = {
    ...existing,
    id: `${category}/${name}`,
    name,
    category,
    description,
    trigger,
    body,
    updatedAt: Date.now(),
  };
  return normalizeSkill({
    ...next,
    content: renderSkillContent(next),
  });
}

function sendSkillResponse(ws, incoming, response) {
  const payload = {
    ...response,
    request_id: incoming.request_id,
  };
  log(`send ${JSON.stringify(payload)}`);
  ws.send(JSON.stringify(payload));
}

function sendSkillError(ws, incoming, error, message) {
  sendSkillResponse(ws, incoming, {
    type: incoming.type === 'skill_get' ? 'skill_get_response' : 'skill_mutation_response',
    ok: false,
    error,
    message,
  });
}

function handleSkillRequest(ws, incoming) {
  if (incoming.type === 'skill_list') {
    sendSkillResponse(ws, incoming, {
      type: 'skill_list_response',
      ok: true,
      skills: [...skills.values()].sort((a, b) => a.id.localeCompare(b.id)),
    });
    return true;
  }
  if (incoming.type === 'skill_get') {
    const skill = skills.get(incoming.skill_id);
    if (!skill) {
      sendSkillError(ws, incoming, 'not_found', `Skill ${incoming.skill_id} not found.`);
      return true;
    }
    sendSkillResponse(ws, incoming, {
      type: 'skill_get_response',
      ok: true,
      skill,
    });
    return true;
  }
  if (incoming.type === 'skill_create') {
    const skill = skillFromDraft(incoming.skill || {});
    if (skills.has(skill.id)) {
      sendSkillError(ws, incoming, 'conflict', `Skill ${skill.id} already exists.`);
      return true;
    }
    skills.set(skill.id, skill);
    sendSkillResponse(ws, incoming, {
      type: 'skill_mutation_response',
      ok: true,
      skill,
    });
    return true;
  }
  if (incoming.type === 'skill_update') {
    const existing = skills.get(incoming.skill_id);
    if (!existing) {
      sendSkillError(ws, incoming, 'not_found', `Skill ${incoming.skill_id} not found.`);
      return true;
    }
    const skill = skillFromDraft(incoming.skill || {}, existing);
    if (skill.id !== incoming.skill_id) {
      skills.delete(incoming.skill_id);
    }
    skills.set(skill.id, skill);
    sendSkillResponse(ws, incoming, {
      type: 'skill_mutation_response',
      ok: true,
      skill,
    });
    return true;
  }
  if (incoming.type === 'skill_set_enabled') {
    const existing = skills.get(incoming.skill_id);
    if (!existing) {
      sendSkillError(ws, incoming, 'not_found', `Skill ${incoming.skill_id} not found.`);
      return true;
    }
    const skill = normalizeSkill({
      ...existing,
      enabled: incoming.enabled === true,
      updatedAt: Date.now(),
    });
    skills.set(skill.id, skill);
    sendSkillResponse(ws, incoming, {
      type: 'skill_mutation_response',
      ok: true,
      skill,
    });
    return true;
  }
  if (incoming.type === 'skill_delete') {
    if (!skills.has(incoming.skill_id)) {
      sendSkillError(ws, incoming, 'not_found', `Skill ${incoming.skill_id} not found.`);
      return true;
    }
    skills.delete(incoming.skill_id);
    sendSkillResponse(ws, incoming, {
      type: 'skill_mutation_response',
      ok: true,
      deleted: true,
    });
    return true;
  }
  return false;
}

function slug(value) {
  const normalized = String(value || 'task')
    .trim()
    .toLowerCase()
    .replace(/[^a-z0-9]+/g, '-')
    .replace(/^-|-$/g, '');
  return normalized || 'task';
}

function normalizeRun(run, taskId) {
  const startedAt = run.started_at || run.startedAt || new Date().toISOString();
  return {
    id: String(run.id || `run-${slug(taskId)}-${Date.now()}`),
    task_id: String(run.task_id || run.taskId || taskId),
    started_at: String(startedAt),
    finished_at: run.finished_at || run.finishedAt || startedAt,
    status: String(run.status || 'success'),
    output_preview: run.output_preview || run.outputPreview || `E2E 任务执行成功：${taskId}`,
    error: run.error,
    output: run.output,
  };
}

function normalizeTask(task) {
  const name = String(task.name || task.id || 'unnamed-task');
  const id = String(task.id || `task-${slug(name)}`);
  const enabled = task.enabled !== false;
  return {
    id,
    account_id: String(task.account_id || task.accountId || accountId),
    agent: String(task.agent || agentName),
    name,
    schedule: String(task.schedule || '0 9 * * *'),
    schedule_text: task.schedule_text || task.scheduleText || task.schedule || '0 9 * * *',
    prompt: String(task.prompt || `${name} prompt`),
    enabled,
    status: String(task.status || (enabled ? 'active' : 'paused')),
    skills: Array.isArray(task.skills) ? task.skills.map(String) : [],
    deliver: task.deliver,
    next_run_at: task.next_run_at || task.nextRunAt,
    last_run: task.last_run || task.lastRun,
    created_at: task.created_at || task.createdAt || new Date().toISOString(),
    updated_at: task.updated_at || task.updatedAt || new Date().toISOString(),
  };
}

function taskFromDraft(draft, existing = {}) {
  const hasSchedulePatch = Object.prototype.hasOwnProperty.call(draft, 'schedule');
  const hasScheduleTextPatch = Object.prototype.hasOwnProperty.call(draft, 'schedule_text');
  const next = {
    ...existing,
    ...draft,
    account_id: draft.account_id || existing.account_id || accountId,
    id: existing.id || draft.id || `task-${slug(draft.name || existing.name || 'task')}`,
    agent: existing.agent || agentName,
    created_at: existing.created_at || new Date().toISOString(),
    updated_at: new Date().toISOString(),
  };
  if (hasSchedulePatch && !hasScheduleTextPatch) {
    next.schedule_text = draft.schedule;
  }
  const normalized = normalizeTask(next);
  normalized.status = normalized.enabled ? 'active' : 'paused';
  return normalized;
}

function sendTaskResponse(ws, incoming, response) {
  const payload = {
    ...response,
    request_id: incoming.request_id,
  };
  log(`send ${JSON.stringify(payload)}`);
  ws.send(JSON.stringify(payload));
}

function sendTaskError(ws, incoming, error, message) {
  sendTaskResponse(ws, incoming, {
    type: incoming.type === 'task_get' ? 'task_get_response' : 'task_mutation_response',
    ok: false,
    error,
    message,
  });
}

function runOutput(task, run) {
  return `E2E 任务输出完整内容：${task.name} 已按 ${task.schedule} 执行。`;
}

function handleTaskRequest(ws, incoming) {
  if (incoming.type === 'task_list') {
    sendTaskResponse(ws, incoming, {
      type: 'task_list_response',
      ok: true,
      tasks: [...tasks.values()].sort((a, b) => a.name.localeCompare(b.name)),
    });
    return true;
  }
  if (incoming.type === 'task_get') {
    const task = tasks.get(incoming.task_id);
    if (!task) {
      sendTaskError(ws, incoming, 'not_found', `Task ${incoming.task_id} not found.`);
      return true;
    }
    sendTaskResponse(ws, incoming, {
      type: 'task_get_response',
      ok: true,
      task,
    });
    return true;
  }
  if (incoming.type === 'task_create') {
    const task = taskFromDraft(incoming.task || {});
    if (tasks.has(task.id)) {
      sendTaskError(ws, incoming, 'conflict', `Task ${task.id} already exists.`);
      return true;
    }
    tasks.set(task.id, task);
    taskRuns.set(task.id, []);
    sendTaskResponse(ws, incoming, {
      type: 'task_mutation_response',
      ok: true,
      task,
    });
    return true;
  }
  if (incoming.type === 'task_update') {
    const existing = tasks.get(incoming.task_id);
    if (!existing) {
      sendTaskError(ws, incoming, 'not_found', `Task ${incoming.task_id} not found.`);
      return true;
    }
    const task = taskFromDraft(
      { ...(incoming.patch || {}), account_id: existing.account_id },
      existing,
    );
    tasks.set(task.id, task);
    sendTaskResponse(ws, incoming, {
      type: 'task_mutation_response',
      ok: true,
      task,
    });
    return true;
  }
  if (incoming.type === 'task_delete') {
    if (!tasks.has(incoming.task_id)) {
      sendTaskError(ws, incoming, 'not_found', `Task ${incoming.task_id} not found.`);
      return true;
    }
    tasks.delete(incoming.task_id);
    taskRuns.delete(incoming.task_id);
    sendTaskResponse(ws, incoming, {
      type: 'task_mutation_response',
      ok: true,
      deleted: true,
    });
    return true;
  }
  if (incoming.type === 'task_set_enabled') {
    const existing = tasks.get(incoming.task_id);
    if (!existing) {
      sendTaskError(ws, incoming, 'not_found', `Task ${incoming.task_id} not found.`);
      return true;
    }
    const task = normalizeTask({
      ...existing,
      enabled: incoming.enabled === true,
      status: incoming.enabled === true ? 'active' : 'paused',
      updated_at: new Date().toISOString(),
    });
    tasks.set(task.id, task);
    sendTaskResponse(ws, incoming, {
      type: 'task_mutation_response',
      ok: true,
      task,
    });
    return true;
  }
  if (incoming.type === 'task_run') {
    const task = tasks.get(incoming.task_id);
    if (!task) {
      sendTaskError(ws, incoming, 'not_found', `Task ${incoming.task_id} not found.`);
      return true;
    }
    const run = normalizeRun({
      id: `run-${slug(task.id)}-${Date.now()}`,
      task_id: task.id,
      status: 'success',
      output_preview: `E2E 任务执行成功：${task.name}`,
    }, task.id);
    const nextTask = normalizeTask({
      ...task,
      last_run: run,
      updated_at: new Date().toISOString(),
    });
    tasks.set(nextTask.id, nextTask);
    taskRuns.set(nextTask.id, [run, ...(taskRuns.get(nextTask.id) || [])]);
    taskOutputs.set(`${nextTask.id}:${run.id}`, runOutput(nextTask, run));
    sendTaskResponse(ws, incoming, {
      type: 'task_run_response',
      ok: true,
      runs: [run],
    });
    return true;
  }
  if (incoming.type === 'task_runs') {
    sendTaskResponse(ws, incoming, {
      type: 'task_runs_response',
      ok: true,
      runs: taskRuns.get(incoming.task_id) || [],
    });
    return true;
  }
  if (incoming.type === 'task_output') {
    sendTaskResponse(ws, incoming, {
      type: 'task_output_response',
      ok: true,
      output: taskOutputs.get(`${incoming.task_id}:${incoming.run_id}`) || '',
    });
    return true;
  }
  return false;
}

function sendTransientResponse(ws, incoming) {
  if (incoming.type === 'query_models') {
    const payload = { type: 'models_response', models };
    log(`send ${JSON.stringify(payload)}`);
    ws.send(JSON.stringify(payload));
    return true;
  }
  if (incoming.type === 'query_skills') {
    ws.send(JSON.stringify({
      type: 'skills_response',
      skills: [...skills.values()]
        .filter((skill) => skill.enabled)
        .map((skill) => ({ name: skill.name, description: skill.description })),
    }));
    return true;
  }
  return false;
}

function connect() {
  log(`connecting ${upstreamUrl}`);
  const ws = new WebSocket(upstreamUrl);

  ws.on('open', () => {
    const identify = { type: 'identify', accountId, agentName, gatewayType, capabilities };
    log(`identify ${JSON.stringify(identify)}`);
    ws.send(JSON.stringify(identify));
  });

  ws.on('message', async (raw) => {
    const text = raw.toString();
    log(`recv ${text}`);
    let msg;
    try {
      msg = JSON.parse(text);
    } catch {
      log('invalid json ignored');
      return;
    }
    if (handleSkillRequest(ws, msg)) return;
    if (handleTaskRequest(ws, msg)) return;
    if (sendTransientResponse(ws, msg)) return;
    if (await sendScriptedInteraction(ws, msg)) return;
    await sendLegacyUserMessageReplies(ws, msg);
  });

  ws.on('close', () => {
    log('closed');
    process.exit(0);
  });

  ws.on('error', (err) => {
    log(`error ${err.message}`);
    process.exit(1);
  });
}

process.on('SIGTERM', () => {
  log('SIGTERM');
  process.exit(0);
});

connect();
