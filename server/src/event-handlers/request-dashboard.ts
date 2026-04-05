/**
 * request-dashboard handler
 */
import type { HandlerContext } from '../event-registry.js';
import type WebSocket from 'ws';

interface DashboardDeps {
  getDashboardJson: (clientCount: number, isUpstreamConnected: boolean, locale: string) => Record<string, unknown>;
  getClientCount: () => number;
  isUpstreamConnected: () => boolean;
}

export function createDashboardHandler(deps: DashboardDeps) {
  return (ctx: HandlerContext) => {
    const data = ctx.payload.data as Record<string, unknown> | undefined;
    const locale = (data?.locale as string) || 'zh';
    const dashboard = deps.getDashboardJson(
      deps.getClientCount(),
      deps.isUpstreamConnected(),
      locale,
    );
    ctx.respond({
      payload_type: 'ui_component',
      message_id: `dash_${Date.now()}`,
      component: dashboard,
    });
  };
}
