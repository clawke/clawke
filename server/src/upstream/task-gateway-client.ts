import { randomUUID } from 'node:crypto';
import type { WebSocket } from 'ws';
import type { TaskGatewayRequest, TaskGatewayResponse } from '../types/tasks.js';
import { getUpstreamConnection } from './openclaw-listener.js';

type TaskGatewayWebSocket = Pick<WebSocket, 'send' | 'on' | 'removeListener' | 'readyState'>;

export class TaskGatewayError extends Error {
  constructor(
    public code: string,
    message: string,
    public status = 500,
    public details?: unknown,
  ) {
    super(message);
    this.name = 'TaskGatewayError';
  }
}

const RESPONSE_BY_COMMAND: Record<string, string[]> = {
  task_list: ['task_list_response'],
  task_get: ['task_get_response'],
  task_create: ['task_mutation_response'],
  task_update: ['task_mutation_response'],
  task_delete: ['task_mutation_response'],
  task_set_enabled: ['task_mutation_response'],
  task_run: ['task_run_response'],
  task_runs: ['task_runs_response'],
  task_output: ['task_output_response'],
};

export async function sendTaskGatewayRequest(
  request: TaskGatewayRequest,
  timeoutMs = 5000,
): Promise<TaskGatewayResponse> {
  const ws = getUpstreamConnection(request.account_id);
  if (!ws) {
    throw new TaskGatewayError(
      'gateway_unavailable',
      `No gateway connected for account_id=${request.account_id}`,
      503,
    );
  }

  return sendTaskGatewayRequestForTest(ws, request, timeoutMs);
}

export function sendTaskGatewayRequestForTest(
  ws: TaskGatewayWebSocket,
  request: TaskGatewayRequest,
  timeoutMs = 5000,
): Promise<TaskGatewayResponse> {
  const requestId = request.request_id || randomUUID();
  const expectedTypes = RESPONSE_BY_COMMAND[request.type] || [];
  const outbound = { ...request, request_id: requestId };

  return new Promise((resolve, reject) => {
    const cleanup = () => {
      clearTimeout(timeout);
      ws.removeListener('message', onMessage);
    };

    const timeout = setTimeout(() => {
      cleanup();
      reject(new TaskGatewayError('gateway_timeout', `Gateway timeout for ${request.type}`, 504));
    }, timeoutMs);

    const onMessage = (raw: Buffer) => {
      let response: TaskGatewayResponse;
      try {
        response = JSON.parse(raw.toString());
      } catch {
        return;
      }

      if (response.request_id !== requestId || !expectedTypes.includes(response.type)) {
        return;
      }

      cleanup();
      if (response.error || response.ok === false) {
        reject(new TaskGatewayError(
          response.error || 'gateway_error',
          response.message || response.error || 'Gateway task request failed',
          502,
          response.details,
        ));
        return;
      }

      resolve(response);
    };

    ws.on('message', onMessage);
    ws.send(JSON.stringify(outbound));
  });
}
