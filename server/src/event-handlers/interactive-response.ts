/**
 * Interactive Response Handlers — approval_response / clarify_response
 *
 * Client → Server → Gateway 透传（不存储、不统计）
 */
import type { HandlerContext } from '../event-registry.js';

type ForwardFn = (accountId: string, msg: Record<string, unknown>) => void;

export function createApprovalResponseHandler(deps: {
  forwardToUpstream: ForwardFn;
}): (ctx: HandlerContext) => void {
  return (ctx) => {
    const accountId = ctx.payload.context?.account_id || 'default';
    const data = ctx.payload.data || {};
    const conversationId = data.conversation_id || '';
    const choice = data.choice || 'deny';

    console.log(`[Server] 🔐 approval_response: account=${accountId} conv=${conversationId} choice=${choice}`);

    deps.forwardToUpstream(accountId, {
      type: 'approval_response',
      conversation_id: conversationId,
      choice,
    });
  };
}

export function createClarifyResponseHandler(deps: {
  forwardToUpstream: ForwardFn;
}): (ctx: HandlerContext) => void {
  return (ctx) => {
    const accountId = ctx.payload.context?.account_id || 'default';
    const data = ctx.payload.data || {};
    const conversationId = data.conversation_id || '';
    const response = data.response || '';

    console.log(`[Server] ❓ clarify_response: account=${accountId} conv=${conversationId} response="${(response as string).slice(0, 40)}"`);

    deps.forwardToUpstream(accountId, {
      type: 'clarify_response',
      conversation_id: conversationId,
      response,
    });
  };
}
