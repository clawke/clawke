import test from 'node:test';
import assert from 'node:assert/strict';
import { EventEmitter } from 'node:events';

class FakeWs extends EventEmitter {
  constructor() {
    super();
    this.readyState = 1;
    this.sent = [];
  }

  send(raw) {
    this.sent.push(JSON.parse(raw));
  }
}

class ThrowingFakeWs extends FakeWs {
  send() {
    throw new Error('send failed');
  }
}

test('task gateway request resolves only matching request_id', async () => {
  const mod = await import('../dist/upstream/task-gateway-client.js');
  const ws = new FakeWs();
  const promise = mod.sendTaskGatewayRequestForTest(ws, {
    type: 'task_list',
    account_id: 'hermes',
  }, 1000);

  assert.equal(ws.sent[0].type, 'task_list');
  assert.equal(typeof ws.sent[0].request_id, 'string');

  ws.emit('message', Buffer.from(JSON.stringify({
    type: 'task_get_response',
    request_id: ws.sent[0].request_id,
    task: { id: 'wrong_response_type' },
  })));
  ws.emit('message', Buffer.from(JSON.stringify({
    type: 'task_list_response',
    request_id: 'other',
    tasks: [],
  })));
  ws.emit('message', Buffer.from(JSON.stringify({
    type: 'task_list_response',
    request_id: ws.sent[0].request_id,
    tasks: [{
      id: 'job_1',
      name: 'Daily',
      schedule: '0 9 * * *',
      prompt: 'hello',
      enabled: true,
      status: 'active',
    }],
  })));

  const result = await promise;
  assert.equal(result.type, 'task_list_response');
  assert.equal(result.tasks.length, 1);
});

test('task gateway error response rejects with TaskGatewayError', async () => {
  const mod = await import('../dist/upstream/task-gateway-client.js');
  const ws = new FakeWs();
  const promise = mod.sendTaskGatewayRequestForTest(ws, {
    type: 'task_get',
    account_id: 'hermes',
    task_id: 'job_1',
  }, 1000);

  ws.emit('message', Buffer.from(JSON.stringify({
    type: 'task_get_response',
    request_id: ws.sent[0].request_id,
    error: 'not_found',
    message: 'Task not found',
    details: { task_id: 'job_1' },
  })));

  await assert.rejects(promise, (err) => {
    assert.equal(err.name, 'TaskGatewayError');
    assert.equal(err.code, 'not_found');
    assert.equal(err.message, 'Task not found');
    assert.equal(err.status, 502);
    assert.equal(err.details.task_id, 'job_1');
    return true;
  });
});

test('task gateway request times out when matching response never arrives', async () => {
  const mod = await import('../dist/upstream/task-gateway-client.js');
  const ws = new FakeWs();

  await assert.rejects(
    mod.sendTaskGatewayRequestForTest(ws, {
      type: 'task_runs',
      account_id: 'hermes',
      task_id: 'job_1',
    }, 10),
    (err) => {
      assert.equal(err.name, 'TaskGatewayError');
      assert.equal(err.code, 'gateway_timeout');
      assert.equal(err.status, 504);
      return true;
    },
  );
});

test('task gateway request rejects when upstream connection is unavailable', async () => {
  const mod = await import('../dist/upstream/task-gateway-client.js');

  await assert.rejects(
    mod.sendTaskGatewayRequest({
      type: 'task_list',
      account_id: 'missing',
    }, 10),
    (err) => {
      assert.equal(err.name, 'TaskGatewayError');
      assert.equal(err.code, 'gateway_unavailable');
      assert.equal(err.status, 503);
      return true;
    },
  );
});

test('task gateway request cleans up listener when send throws', async () => {
  const mod = await import('../dist/upstream/task-gateway-client.js');
  const ws = new ThrowingFakeWs();

  await assert.rejects(
    mod.sendTaskGatewayRequestForTest(ws, {
      type: 'task_list',
      account_id: 'hermes',
    }, 1000),
    /send failed/,
  );

  assert.equal(ws.listenerCount('message'), 0);
});

test('openclaw listener identifies task gateway responses as transient responses', async () => {
  const { isTransientGatewayResponseType } = await import('../dist/upstream/openclaw-listener.js');

  assert.equal(isTransientGatewayResponseType('models_response'), true);
  assert.equal(isTransientGatewayResponseType('skills_response'), true);
  assert.equal(isTransientGatewayResponseType('task_list_response'), true);
  assert.equal(isTransientGatewayResponseType('task_get_response'), true);
  assert.equal(isTransientGatewayResponseType('task_mutation_response'), true);
  assert.equal(isTransientGatewayResponseType('task_run_response'), true);
  assert.equal(isTransientGatewayResponseType('task_runs_response'), true);
  assert.equal(isTransientGatewayResponseType('task_output_response'), true);
  assert.equal(isTransientGatewayResponseType('agent_message'), false);
  assert.equal(isTransientGatewayResponseType(undefined), false);
});
