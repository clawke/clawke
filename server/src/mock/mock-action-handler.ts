/**
 * Mock 动作处理器
 */
import type { WebSocket } from 'ws';
import { handleChannelAction } from '../services/channel-service.js';
import { handleSkillAction } from '../services/skill-service.js';
import type { CronService } from '../services/cron-service.js';

export function createMockActionHandler(cronService: CronService) {
  return function handleAction(ws: WebSocket, payload: any): void {
    console.log('\n[Tunnel] ✅ Received user_action event:');
    console.log(JSON.stringify(payload, null, 2));

    const actionId = payload.action?.action_id || '';
    if (actionId.includes('cron')) {
      cronService.handleCronAction(ws, payload);
    } else if (actionId.includes('channel')) {
      handleChannelAction(ws, payload);
    } else if (actionId.includes('skill')) {
      handleSkillAction(ws, payload);
    }
  };
}
