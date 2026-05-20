import { randomUUID } from 'node:crypto';
import type { WebSocket } from 'ws';
import type { SkillGatewayRequest, SkillGatewayResponse } from '../types/skills.js';
import { getUpstreamConnection } from './gateway-listener.js';

type SkillGatewayWebSocket = Pick<WebSocket, 'send' | 'on' | 'removeListener' | 'readyState'>;

export class SkillGatewayError extends Error {
  constructor(
    public code: string,
    message: string,
    public status = 500,
    public details?: unknown,
  ) {
    super(message);
    this.name = 'SkillGatewayError';
  }
}

const RESPONSE_BY_COMMAND: Record<string, string[]> = {
  skill_list: ['skill_list_response'],
  skill_get: ['skill_get_response'],
  skill_create: ['skill_mutation_response'],
  skill_update: ['skill_mutation_response'],
  skill_delete: ['skill_mutation_response'],
  skill_set_enabled: ['skill_mutation_response'],
  skillhub_install: ['skillhub_install_response'],
};

export function skillGatewayTimeoutMsFor(_type: SkillGatewayRequest['type']): number {
  return 5_000;
}

export async function sendSkillGatewayRequest(
  request: SkillGatewayRequest,
  timeoutMs = skillGatewayTimeoutMsFor(request.type),
): Promise<SkillGatewayResponse> {
  const ws = getUpstreamConnection(request.account_id);
  if (!ws) {
    throw new SkillGatewayError(
      'gateway_unavailable',
      `No gateway connected for account_id=${request.account_id}`,
      503,
    );
  }

  return sendSkillGatewayRequestForTest(ws, request, timeoutMs);
}

export function sendSkillGatewayRequestForTest(
  ws: SkillGatewayWebSocket,
  request: SkillGatewayRequest,
  timeoutMs = skillGatewayTimeoutMsFor(request.type),
): Promise<SkillGatewayResponse> {
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
      reject(new SkillGatewayError('gateway_timeout', `Gateway timeout for ${request.type}`, 504));
    }, timeoutMs);

    const onMessage = (raw: Buffer) => {
      let response: SkillGatewayResponse;
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
        reject(new SkillGatewayError(
          response.error || 'gateway_error',
          response.message || response.error || 'Gateway skill request failed',
          502,
          response.details,
        ));
        return;
      }

      resolve(response);
    };

    ws.on('message', onMessage);
    try {
      ws.send(JSON.stringify(outbound));
    } catch (err) {
      cleanup();
      reject(err);
    }
  });
}
