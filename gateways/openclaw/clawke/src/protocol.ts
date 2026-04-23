/**
 * Clawke WebSocket 协议类型定义
 *
 * Gateway ↔ Server 之间通过 WebSocket 交换的所有消息类型。
 * 这是协议的唯一权威定义（Single Source of Truth）。
 */

// ─────────────────────────────────────────────
// Gateway → Server（下行：AI 输出）
// ─────────────────────────────────────────────

/** Gateway 发送给 Server 的消息类型 */
export const GatewayMessageType = {
  // 连接与控制
  Identify:           "identify",
  ModelsResponse:     "models_response",
  SkillsResponse:     "skills_response",
  SkillsDetailResponse: "skills_detail_response",
  SkillSaveResponse:    "skill_save_response",
  SkillDeleteResponse:  "skill_delete_response",
  SkillToggleResponse:  "skill_toggle_response",

  // 流式输出
  AgentTyping:        "agent_typing",
  AgentTextDelta:     "agent_text_delta",
  AgentTextDone:      "agent_text_done",
  AgentText:          "agent_text",

  // 媒体
  AgentMedia:         "agent_media",

  // 工具调用
  AgentToolCall:      "agent_tool_call",
  AgentToolResult:    "agent_tool_result",

  // 推理（Thinking）
  AgentThinkingDelta: "agent_thinking_delta",
  AgentThinkingDone:  "agent_thinking_done",

  // 状态与统计
  AgentStatus:        "agent_status",
  AgentTurnStats:     "agent_turn_stats",
} as const;

export type GatewayMessageType = (typeof GatewayMessageType)[keyof typeof GatewayMessageType];

// ─────────────────────────────────────────────
// Server → Gateway（上行：用户输入 / 控制）
// ─────────────────────────────────────────────

/** Server 发送给 Gateway 的消息类型 — Server → Gateway inbound message types */
// 注意：不含 approval_response / clarify_response — 那些是 Hermes Gateway 专用协议
// Note: no approval_response / clarify_response — those are Hermes-only;
// OpenClaw handles approvals via markdown buttons → plain text chat messages
export const InboundMessageType = {
  Chat:         "chat",
  Abort:        "abort",
  QueryModels:  "query_models",
  QuerySkills:  "query_skills",
  QuerySkillsDetail: "query_skills_detail",
  SkillSave:    "skill_save",
  SkillDelete:  "skill_delete",
  SkillToggle:  "skill_toggle",
} as const;

export type InboundMessageType = (typeof InboundMessageType)[keyof typeof InboundMessageType];

// ─────────────────────────────────────────────
// 状态值枚举（agent_status 消息的 status 字段）
// ─────────────────────────────────────────────

/** AgentStatus 消息的 status 字段值 */
export const AgentStatus = {
  Compacting: "compacting",  // 上下文窗口压缩中
  Thinking:   "thinking",    // AI 正在思考
  Queued:     "queued",      // 前一个请求仍在执行，当前消息已排队
} as const;

export type AgentStatus = (typeof AgentStatus)[keyof typeof AgentStatus];
