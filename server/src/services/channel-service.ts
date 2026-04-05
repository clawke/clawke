/**
 * 渠道管理服务（Mock 实现）
 */
import { sendToClient } from '../downstream/client-server.js';
import type { WebSocket } from 'ws';

interface Channel {
  id: string;
  type: string;
  name: string;
  status: string;
  connection_string: string;
  stats: { messages: number; last_active: string | null };
}

const mockChannels: Channel[] = [
  {
    id: 'ch_tg_1', type: 'telegram', name: 'Telegram Bot',
    status: 'connected', connection_string: '@clawke_bot',
    stats: { messages: 124, last_active: new Date().toISOString() },
  },
  {
    id: 'ch_wx_1', type: 'wechat', name: 'WeChat Personal',
    status: 'disconnected', connection_string: '未连接',
    stats: { messages: 0, last_active: null },
  },
];

export function getChannelsViewJson(messageId = 'msg_sys'): Record<string, unknown> {
  return {
    payload_type: 'ui_component',
    message_id: messageId,
    component: {
      widget_name: 'ChannelsView',
      props: {
        channels: mockChannels,
        available_types: [
          { id: 'telegram', name: 'Telegram Bot', icon: 'telegram', type: 'form' },
          { id: 'whatsapp', name: 'WhatsApp', icon: 'whatsapp', type: 'qr_scan' },
          { id: 'wechat', name: 'WeChat', icon: 'wechat', type: 'qr_scan' },
          { id: 'discord', name: 'Discord', icon: 'discord', type: 'form' },
        ],
      },
    },
  };
}

export function handleChannelAction(ws: WebSocket, payload: any): void {
  const { action_id, data } = payload.action;
  const messageId = payload.message_id || payload.context?.client_msg_id;

  if (action_id === 'refresh_channels') {
    sendToClient(ws, getChannelsViewJson(messageId));
  } else if (action_id === 'disconnect_channel') {
    const channel = mockChannels.find(c => c.id === data.channel_id);
    if (channel) {
      channel.status = 'disconnected';
      sendToClient(ws, { payload_type: 'system_status', status: 'toast', message: `已断开 ${channel.name} 连接` });
      sendToClient(ws, getChannelsViewJson(messageId));
    }
  } else if (action_id === 'get_channel_form') {
    const channelType = data.channel_type;
    if (channelType === 'telegram' || channelType === 'discord') {
      sendToClient(ws, {
        payload_type: 'ui_component', message_id: messageId,
        component: {
          widget_name: 'ChannelConnectDialog',
          props: {
            title: `连接 ${channelType === 'telegram' ? 'Telegram' : 'Discord'}`,
            channel_type: channelType, content_type: 'form',
            fields: [{ name: 'bot_token', label: 'Bot Token', type: 'password', required: true, hint: '完整的 Bot Token' }],
          },
        },
      });
    } else if (channelType === 'whatsapp' || channelType === 'wechat') {
      sendToClient(ws, {
        payload_type: 'ui_component', message_id: messageId,
        component: {
          widget_name: 'ChannelConnectDialog',
          props: {
            title: '扫描二维码登录', channel_type: channelType, content_type: 'qr_scan',
            qr_data_base64: 'R0lGODlhAQABAIAAAAAAAP///yH5BAEAAAAALAAAAAABAAEAAAIBRAA7',
            hint: '请使用手机端扫描二维码',
          },
        },
      });
      setTimeout(() => {
        mockChannels.push({
          id: `ch_${channelType}_${Date.now()}`, type: channelType,
          name: `${channelType} Account`, status: 'connected',
          connection_string: '模拟登录账号',
          stats: { messages: 0, last_active: new Date().toISOString() },
        });
        sendToClient(ws, { payload_type: 'system_status', status: 'toast', message: '扫码成功，已连接！' });
        sendToClient(ws, { payload_type: 'system_status', status: 'close_dialog' });
        sendToClient(ws, getChannelsViewJson(messageId));
      }, 5000);
    }
  } else if (action_id === 'submit_channel_form') {
    const channelType = data.channel_type;
    const formData = data.form_data;
    if (formData.bot_token) {
      mockChannels.push({
        id: `ch_${channelType}_${Date.now()}`, type: channelType,
        name: `${channelType} Bot`, status: 'connected',
        connection_string: 'Connected via Token',
        stats: { messages: 0, last_active: new Date().toISOString() },
      });
      sendToClient(ws, { payload_type: 'system_status', status: 'toast', message: 'Token 验证成功并连接' });
      sendToClient(ws, { payload_type: 'system_status', status: 'close_dialog' });
      sendToClient(ws, getChannelsViewJson(messageId));
    }
  }
}
