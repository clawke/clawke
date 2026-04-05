/**
 * 技能管理服务（Mock 实现）
 */
import { sendToClient } from '../downstream/client-server.js';
import type { WebSocket } from 'ws';

interface LocalSkill {
  id: string; name: string; author: string;
  description: string; version: string; status: string; has_config: boolean;
}
interface MarketSkill {
  id: string; name: string; author: string;
  description: string; version: string; downloads: number; price: string; installed: boolean;
}

const mockLocalSkills: LocalSkill[] = [
  { id: 'skill_web_fetch', name: 'Web Fetcher', author: 'Clawke Team', description: 'Allows the agent to fetch content from URLs.', version: '1.0.0', status: 'active', has_config: false },
  { id: 'skill_notion', name: 'Notion Integration', author: 'Third Party', description: 'Connects to your Notion workspace to read and write pages.', version: '0.9.5', status: 'inactive', has_config: true },
];

const mockMarketSkills: MarketSkill[] = [
  { id: 'skill_github', name: 'GitHub Copilot', author: 'GitHub', description: 'Manage repositories, issues, and PRs from chat.', version: '2.1.0', downloads: 15420, price: 'Free', installed: false },
  { id: 'skill_jira', name: 'Jira Tracker', author: 'Atlassian', description: 'Create and update Jira tickets automatically.', version: '1.2.0', downloads: 8300, price: 'Free', installed: false },
];

export function getSkillsViewJson(messageId = 'msg_sys', tab = 'local'): Record<string, unknown> {
  return {
    payload_type: 'ui_component', message_id: messageId,
    component: { widget_name: 'SkillsView', props: { active_tab: tab, local_skills: mockLocalSkills, market_skills: mockMarketSkills } },
  };
}

export function handleSkillAction(ws: WebSocket, payload: any): void {
  const { action_id, data } = payload.action;
  const messageId = payload.message_id || payload.context?.client_msg_id;

  if (action_id === 'refresh_skills') {
    sendToClient(ws, getSkillsViewJson(messageId, data.tab || 'local'));
  } else if (action_id === 'toggle_skill') {
    const skill = mockLocalSkills.find(s => s.id === data.skill_id);
    if (skill) {
      skill.status = data.active ? 'active' : 'inactive';
      sendToClient(ws, { payload_type: 'system_status', status: 'toast', message: `${skill.name} 已${data.active ? '启用' : '禁用'}` });
      sendToClient(ws, getSkillsViewJson(messageId, 'local'));
    }
  } else if (action_id === 'uninstall_skill') {
    const index = mockLocalSkills.findIndex(s => s.id === data.skill_id);
    if (index !== -1) {
      const removed = mockLocalSkills.splice(index, 1)[0];
      const marketSkill = mockMarketSkills.find(s => s.id === removed.id);
      if (marketSkill) marketSkill.installed = false;
      sendToClient(ws, { payload_type: 'system_status', status: 'toast', message: `${removed.name} 已卸载` });
      sendToClient(ws, getSkillsViewJson(messageId, 'local'));
    }
  } else if (action_id === 'install_skill') {
    const marketSkill = mockMarketSkills.find(s => s.id === data.skill_id);
    if (marketSkill && !marketSkill.installed) {
      marketSkill.installed = true;
      mockLocalSkills.push({ id: marketSkill.id, name: marketSkill.name, author: marketSkill.author, description: marketSkill.description, version: marketSkill.version, status: 'active', has_config: false });
      sendToClient(ws, { payload_type: 'system_status', status: 'toast', message: `${marketSkill.name} 安装成功并已启用` });
      sendToClient(ws, getSkillsViewJson(messageId, 'market'));
    }
  } else if (action_id === 'get_skill_config') {
    const skill = mockLocalSkills.find(s => s.id === data.skill_id);
    if (skill?.has_config) {
      sendToClient(ws, {
        payload_type: 'ui_component', message_id: messageId,
        component: {
          widget_name: 'SkillConfigDialog',
          props: {
            title: `配置: ${skill.name}`, skill_id: skill.id,
            fields: [
              { name: 'api_key', label: 'API Key', type: 'password', required: true, hint: '输入提供商的 API 密钥', current_value: '' },
              { name: 'environment', label: 'Environment', type: 'text', required: false, hint: '例如: production, staging', current_value: 'production' },
            ],
          },
        },
      });
    }
  } else if (action_id === 'save_skill_config') {
    sendToClient(ws, { payload_type: 'system_status', status: 'toast', message: '配置已保存' });
    sendToClient(ws, { payload_type: 'system_status', status: 'close_dialog' });
  }
}
