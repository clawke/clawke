/**
 * ping handler
 */
import type { HandlerContext } from '../event-registry.js';

interface PingDeps {
  getConnectedAccountIds: () => string[];
  agentName: string;
}

export function createPingHandler(deps: PingDeps) {
  return (ctx: HandlerContext) => {
    const accounts = deps.getConnectedAccountIds();
    for (const accountId of accounts) {
      ctx.respond({
        payload_type: 'system_status',
        status: 'ai_connected',
        agent_name: deps.agentName,
        account_id: accountId,
      });
    }
    if (accounts.length === 0) {
      ctx.respond({
        payload_type: 'system_status',
        status: 'ai_disconnected',
        agent_name: deps.agentName,
      });
    }
  };
}
