/**
 * 会话 REST API
 *
 * - GET    /api/conversations      → 列出所有会话
 * - POST   /api/conversations      → 创建会话
 * - PUT    /api/conversations/:id   → 更新会话（name, pin, mute）
 * - DELETE /api/conversations/:id   → 删除会话（级联删 messages + configs）
 */
import type { Request, Response } from 'express';
import type { ConversationStore } from '../store/conversation-store.js';
import { broadcastToClients } from '../downstream/client-server.js';

/** 通知所有客户端会话列表已变更 */
function notifyConvChanged(): void {
  broadcastToClients({ payload_type: 'conv_changed' });
}

// ─── 依赖注入 ───

let convStore: ConversationStore | null = null;

export function initConversationRoutes(deps: {
  conversationStore: ConversationStore;
}): void {
  convStore = deps.conversationStore;
}

// ─── Handlers ───

/** GET /api/conversations — 列出所有会话 */
export function listConversations(_req: Request, res: Response): void {
  if (!convStore) {
    res.status(500).json({ error: 'ConversationStore not initialized' });
    return;
  }
  const conversations = convStore.list();
  res.json(conversations.map(c => ({
    id: c.id,
    type: c.type,
    name: c.name,
    account_id: c.accountId,
    is_pinned: c.isPinned,
    is_muted: c.isMuted,
    created_at: c.createdAt,
    updated_at: c.updatedAt,
  })));
}

/** POST /api/conversations — 创建会话 */
export function createConversation(req: Request, res: Response): void {
  if (!convStore) {
    res.status(500).json({ error: 'ConversationStore not initialized' });
    return;
  }
  const { id, name, type, account_id } = req.body;
  const convId = id || `conv_${Date.now()}_${Math.random().toString(36).slice(2, 8)}`;
  const conv = convStore.create(convId, type || 'dm', name || null, account_id || null);
  console.log(`[ConvAPI] Created conversation: ${convId} (account=${account_id || 'none'})`);
  res.json({
    id: conv.id,
    type: conv.type,
    name: conv.name,
    account_id: conv.accountId,
    is_pinned: conv.isPinned,
    is_muted: conv.isMuted,
    created_at: conv.createdAt,
    updated_at: conv.updatedAt,
  });
  notifyConvChanged();
}

/** PUT /api/conversations/:id — 更新会话 */
export function updateConversation(req: Request, res: Response): void {
  if (!convStore) {
    res.status(500).json({ error: 'ConversationStore not initialized' });
    return;
  }
  const convId = req.params.id as string;
  const existing = convStore.get(convId);
  if (!existing) {
    res.status(404).json({ error: 'Conversation not found' });
    return;
  }

  const updates: { name?: string; isPinned?: boolean; isMuted?: boolean } = {};
  if (req.body.name !== undefined) updates.name = req.body.name;
  if (req.body.is_pinned !== undefined) updates.isPinned = !!req.body.is_pinned;
  if (req.body.is_muted !== undefined) updates.isMuted = !!req.body.is_muted;

  convStore.update(convId as string, updates);
  console.log(`[ConvAPI] Updated conversation ${convId}:`, updates);
  res.json({ ok: true });
  notifyConvChanged();
}

/** DELETE /api/conversations/:id — 删除会话 */
export function deleteConversation(req: Request, res: Response): void {
  if (!convStore) {
    res.status(500).json({ error: 'ConversationStore not initialized' });
    return;
  }
  const convId = req.params.id as string;
  convStore.delete(convId);
  console.log(`[ConvAPI] Deleted conversation: ${convId}`);
  res.json({ ok: true });
  notifyConvChanged();
}
