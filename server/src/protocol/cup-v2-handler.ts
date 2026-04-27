/**
 * CupV2Handler — CUP 协议核心处理器
 *
 * 负责 ACK/sync/seq 管理和消息存储。
 * 构造函数注入 MessageStore 和 ConversationStore。
 */
import { MessageStore } from '../store/message-store.js';
import { ConversationStore } from '../store/conversation-store.js';
import type { StoreResult } from '../store/message-store.js';
import type { ClientPayload } from '../types/cup.js';

export class CupV2Handler {
  constructor(
    private messageStore: MessageStore,
    private conversationStore: ConversationStore,
  ) {}

  /**
   * 处理 user_message — 存储消息 + 返回 ACK
   */
  handleUserMessage(payload: ClientPayload): Record<string, unknown> {
    const accountId = payload.context?.account_id || 'default';
    const clientMsgId = payload.context?.client_msg_id || `cmsg_${Date.now()}`;
    const data = payload.data as Record<string, unknown> | undefined;
    const type = (data?.type as string) || 'text';

    // image/file 类型的元数据序列化为 JSON 存储
    let content: string;
    if (type === 'image' && (data?.mediaUrl || data?.thumbHash)) {
      content = JSON.stringify({
        mediaUrl: data.mediaUrl,
        thumbUrl: data.thumbUrl,
        thumbHash: data.thumbHash,
        width: data.width,
        height: data.height,
        fileName: data.fileName,
      });
    } else if (type === 'file' && data?.mediaUrl) {
      content = JSON.stringify({
        mediaUrl: data.mediaUrl,
        mediaType: data.mediaType,
        name: data.fileName || 'unknown',
        size: data.fileSize || 0,
      });
    } else {
      content = (data?.content as string) || '';
    }

    const conversationId = (payload.context?.conversation_id as string) || accountId;

    this.conversationStore.ensure(conversationId);
    this.conversationStore.touch(conversationId);
    const { serverMsgId, seq } = this.messageStore.append(
      accountId, conversationId, clientMsgId, 'local_user', type, content
    );
    console.log(`[CUP] 📝 User msg stored: serverMsgId=${serverMsgId} seq=${seq} conv=${conversationId} clientMsgId=${clientMsgId} type=${type}`);

    return {
      payload_type: 'ctrl',
      id: payload.id || null,
      code: 200,
      params: { server_msg_id: serverMsgId, seq },
    };
  }

  /**
   * 处理 sync — 返回 lastSeq 之后的所有消息
   */
  handleSync(payload: ClientPayload): Record<string, unknown> {
    const data = payload.data as Record<string, unknown> | undefined;
    let lastSeq = (data?.last_seq as number) || 0;
    const currentSeq = this.messageStore.getCurrentSeq();

    // 客户端 seq 超过服务端（Server 重装导致 seq 重置）→ 从头返回，客户端按 message_id 去重
    if (lastSeq > currentSeq) {
      console.log(`[Tunnel] ⚠️ seq mismatch: client last_seq=${lastSeq} > server currentSeq=${currentSeq} → returning all messages`);
      lastSeq = 0;
    }

    // last_seq=0（新设备首次 sync）：返回全量历史，由 getAfterSeq 的 LIMIT 100 兜底
    // last_seq=0 (new device): return full history, capped by getAfterSeq's LIMIT 100
    const messages = this.messageStore.getAfterSeq(lastSeq);
    console.log(`[Tunnel] 📥 sync request: last_seq=${lastSeq}, returning ${messages.length} messages (currentSeq=${currentSeq})`);
    return {
      payload_type: 'sync_response',
      id: payload.id || null,
      current_seq: currentSeq,
      messages: messages.map(m => ({
        seq: m.seq,
        message_id: m.serverMsgId,
        client_msg_id: m.clientMsgId,
        account_id: m.accountId,
        conversation_id: m.conversationId,
        sender_id: m.senderId,
        type: m.type,
        content: m.content,
        ts: m.ts,
      })),
    };
  }

  /**
   * 存储 AI 回复并返回 seq 元数据
   */
  storeAgentMessage(
    accountId: string,
    conversationId: string,
    content: string,
    type: string = 'text',
    upstreamMsgId: string | null = null
  ): StoreResult {
    this.conversationStore.ensure(conversationId);
    this.conversationStore.touch(conversationId);
    return this.messageStore.append(accountId, conversationId, upstreamMsgId, 'agent', type, content);
  }

  /**
   * 生成 delivered 确认
   */
  makeDeliveredAck(requestId: string | null): Record<string, unknown> {
    return {
      payload_type: 'ctrl',
      id: requestId || null,
      code: 201,
      params: { status: 'delivered' },
    };
  }
}
