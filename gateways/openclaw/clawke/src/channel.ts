import type { ChannelPlugin } from "openclaw/plugin-sdk";
import { clawkeConfig, type ResolvedClawkeAccount } from "./config.js";

export const clawkePlugin: ChannelPlugin<ResolvedClawkeAccount> = {
  id: "clawke",
  meta: {
    id: "clawke",
    label: "Clawke",
    selectionLabel: "Clawke (Rich Client)",
    detailLabel: "Clawke Desktop",
    docsPath: "/channels/clawke",
    blurb: "富客户端原生工作空间，支持 SDUI 渲染。",
    systemImage: "display",
  },
  capabilities: {
    chatTypes: ["dm"],
    media: true,
    reactions: false,
    edit: false,
    reply: false,
    threads: false,
    blockStreaming: true,
  },
  streaming: {
    blockStreamingCoalesceDefaults: { minChars: 1, idleMs: 100 },
  },
  config: clawkeConfig,
  outbound: {
    deliveryMode: "direct",
    sendText: async (ctx) => {
      // 从 to 参数提取 conversation_id（兼容 user: 和 conversation: 前缀）
      const conversationId = ctx.to?.replace(/^(user:|conversation:)/, '') || ctx.to;
      console.log(`[Clawke-sendText] ⚡ CALLED: to=${ctx.to}, conversation_id=${conversationId}, text=${ctx.text?.slice(0, 60)}`);
      const { sendToClawkeServer } = await import("./gateway.js");
      sendToClawkeServer({
        type: "agent_text",
        message_id: `msg_${Date.now()}`,
        text: ctx.text,
        to: ctx.to,
        account_id: ctx.accountId,
        conversation_id: conversationId,
      });
      return { ok: true };
    },
    sendMedia: async (ctx) => {
      const { sendToClawkeServer } = await import("./gateway.js");
      sendToClawkeServer({
        type: "agent_media",
        message_id: `msg_${Date.now()}`,
        mediaUrl: ctx.mediaUrl,
        to: ctx.to,
        account_id: ctx.accountId,
      });
      return { ok: true };
    },
  },
  gateway: {
    startAccount: async (ctx) => {
      const { startClawkeGateway } = await import("./gateway.js");
      return startClawkeGateway(ctx);
    },
  },
};
