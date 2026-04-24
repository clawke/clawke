import test from 'node:test';
import assert from 'node:assert/strict';

test('missing account_id with no connected account returns account_required 400', async () => {
  const routes = await import('../dist/routes/tasks-routes.js');
  routes.initTasksRoutes({
    getConnectedAccountIds: () => [],
    sendTaskRequest: async () => ({ type: 'task_list_response', request_id: 'r', tasks: [] }),
  });

  const res = fakeRes();
  await routes.listTasks(fakeReq(), res);

  assert.equal(res.statusCode, 400);
  assert.equal(res.body.error, 'account_required');
});

test('list maps to task_list with account_id and returns tasks', async () => {
  const calls = [];
  const task = {
    id: 'task_1',
    account_id: 'hermes',
    agent: 'Hermes',
    name: 'Daily',
    schedule: '0 9 * * *',
    prompt: 'summarize',
    enabled: true,
    status: 'active',
  };
  const routes = await import('../dist/routes/tasks-routes.js');
  routes.initTasksRoutes({
    getConnectedAccountIds: () => ['hermes'],
    sendTaskRequest: async (payload) => {
      calls.push(payload);
      return { type: 'task_list_response', request_id: 'r', tasks: [task] };
    },
  });

  const res = fakeRes();
  await routes.listTasks(fakeReq({ query: { account_id: 'hermes' } }), res);

  assert.deepEqual(calls, [{ type: 'task_list', account_id: 'hermes' }]);
  assert.deepEqual(res.body.tasks, [task]);
});

test('create validates missing schedule or prompt', async () => {
  const routes = await import('../dist/routes/tasks-routes.js');
  routes.initTasksRoutes({
    getConnectedAccountIds: () => ['hermes'],
    sendTaskRequest: async () => {
      throw new Error('sendTaskRequest should not be called');
    },
  });

  const missingSchedule = fakeRes();
  await routes.createTask(fakeReq({ body: { account_id: 'hermes', prompt: 'hello' } }), missingSchedule);
  assert.equal(missingSchedule.statusCode, 400);
  assert.equal(missingSchedule.body.error, 'validation_error');
  assert.match(missingSchedule.body.message, /schedule/);

  const missingPrompt = fakeRes();
  await routes.createTask(fakeReq({ body: { account_id: 'hermes', schedule: '0 9 * * *' } }), missingPrompt);
  assert.equal(missingPrompt.statusCode, 400);
  assert.equal(missingPrompt.body.error, 'validation_error');
  assert.match(missingPrompt.body.message, /prompt/);
});

test('create validates schedule and prompt types', async () => {
  const routes = await import('../dist/routes/tasks-routes.js');
  routes.initTasksRoutes({
    getConnectedAccountIds: () => ['hermes'],
    sendTaskRequest: async () => {
      throw new Error('sendTaskRequest should not be called');
    },
  });

  const nonStringSchedule = fakeRes();
  await routes.createTask(fakeReq({ body: { account_id: 'hermes', schedule: 123, prompt: 'hello' } }), nonStringSchedule);
  assert.equal(nonStringSchedule.statusCode, 400);
  assert.equal(nonStringSchedule.body.error, 'validation_error');
  assert.match(nonStringSchedule.body.message, /schedule/);

  const nonStringPrompt = fakeRes();
  await routes.createTask(fakeReq({ body: { account_id: 'hermes', schedule: '0 9 * * *', prompt: false } }), nonStringPrompt);
  assert.equal(nonStringPrompt.statusCode, 400);
  assert.equal(nonStringPrompt.body.error, 'validation_error');
  assert.match(nonStringPrompt.body.message, /prompt/);
});

test('set enabled validates enabled is present and boolean', async () => {
  const routes = await import('../dist/routes/tasks-routes.js');
  routes.initTasksRoutes({
    getConnectedAccountIds: () => ['hermes'],
    sendTaskRequest: async () => {
      throw new Error('sendTaskRequest should not be called');
    },
  });

  const missingEnabled = fakeRes();
  await routes.setTaskEnabled(fakeReq({ params: { taskId: 'task_1' }, body: { account_id: 'hermes' } }), missingEnabled);
  assert.equal(missingEnabled.statusCode, 400);
  assert.equal(missingEnabled.body.error, 'validation_error');
  assert.match(missingEnabled.body.message, /enabled/);

  const stringEnabled = fakeRes();
  await routes.setTaskEnabled(fakeReq({ params: { taskId: 'task_1' }, body: { account_id: 'hermes', enabled: 'false' } }), stringEnabled);
  assert.equal(stringEnabled.statusCode, 400);
  assert.equal(stringEnabled.body.error, 'validation_error');
  assert.match(stringEnabled.body.message, /enabled/);
});

test('delete setEnabled run runs and output map to expected command payloads', async () => {
  const calls = [];
  const routes = await import('../dist/routes/tasks-routes.js');
  routes.initTasksRoutes({
    getConnectedAccountIds: () => ['hermes'],
    sendTaskRequest: async (payload) => {
      calls.push(payload);
      if (payload.type === 'task_run') {
        return { type: 'task_run_response', request_id: 'r', runs: [{ id: 'run_1', task_id: 'task_1', started_at: '2026-04-24T00:00:00Z', status: 'running' }] };
      }
      if (payload.type === 'task_runs') {
        return { type: 'task_runs_response', request_id: 'r', runs: [] };
      }
      if (payload.type === 'task_output') {
        return { type: 'task_output_response', request_id: 'r', output: 'done' };
      }
      return { type: 'task_mutation_response', request_id: 'r', ok: true };
    },
  });

  await routes.deleteTask(fakeReq({ params: { taskId: 'task_1' }, query: { account_id: 'hermes' } }), fakeRes());
  await routes.setTaskEnabled(fakeReq({ params: { taskId: 'task_1' }, body: { account_id: 'hermes', enabled: false } }), fakeRes());
  await routes.runTask(fakeReq({ params: { taskId: 'task_1' }, query: { account_id: 'hermes' } }), fakeRes());
  await routes.listTaskRuns(fakeReq({ params: { taskId: 'task_1' }, query: { account_id: 'hermes' } }), fakeRes());
  await routes.getTaskRunOutput(fakeReq({ params: { taskId: 'task_1', runId: 'run_1' }, query: { account_id: 'hermes' } }), fakeRes());

  assert.deepEqual(calls, [
    { type: 'task_delete', account_id: 'hermes', task_id: 'task_1' },
    { type: 'task_set_enabled', account_id: 'hermes', task_id: 'task_1', enabled: false },
    { type: 'task_run', account_id: 'hermes', task_id: 'task_1' },
    { type: 'task_runs', account_id: 'hermes', task_id: 'task_1' },
    { type: 'task_output', account_id: 'hermes', task_id: 'task_1', run_id: 'run_1' },
  ]);
});

test('TaskGatewayError maps status code message and details', async () => {
  const routes = await import('../dist/routes/tasks-routes.js');
  const { TaskGatewayError } = await import('../dist/upstream/task-gateway-client.js');
  routes.initTasksRoutes({
    getConnectedAccountIds: () => ['hermes'],
    sendTaskRequest: async () => {
      throw new TaskGatewayError('gateway_bad_request', 'Bad task request', 422, { field: 'schedule' });
    },
  });

  const res = fakeRes();
  await routes.listTasks(fakeReq({ query: { account_id: 'hermes' } }), res);

  assert.equal(res.statusCode, 422);
  assert.deepEqual(res.body, {
    error: 'gateway_bad_request',
    message: 'Bad task request',
    details: { field: 'schedule' },
  });
});

test('returned gateway error responses produce HTTP errors', async () => {
  const routes = await import('../dist/routes/tasks-routes.js');
  routes.initTasksRoutes({
    getConnectedAccountIds: () => ['mock'],
    sendTaskRequest: async () => ({
      type: 'task_mutation_response',
      request_id: 'r',
      ok: false,
      error: 'tasks_unsupported',
      message: 'Mock mode does not manage agent tasks.',
      details: { mode: 'mock' },
    }),
  });

  const res = fakeRes();
  await routes.createTask(fakeReq({
    body: {
      account_id: 'mock',
      schedule: '0 9 * * *',
      prompt: 'summarize',
    },
  }), res);

  assert.equal(res.statusCode, 501);
  assert.deepEqual(res.body, {
    error: 'tasks_unsupported',
    message: 'Mock mode does not manage agent tasks.',
    details: { mode: 'mock' },
  });
});

function fakeReq({ query = {}, body = {}, params = {} } = {}) {
  return { query, body, params };
}

function fakeRes() {
  return {
    statusCode: 200,
    body: undefined,
    status(code) {
      this.statusCode = code;
      return this;
    },
    json(body) {
      this.body = body;
      return this;
    },
  };
}
