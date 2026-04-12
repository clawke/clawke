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
      // ⚠️ NO-OP: Clawke 的消息发送由 gateway.ts 的 deliver 回调统一处理。
      // 如果这里也发送，会和 deliver 回调产生重复消息。
      // sendText 仅在没有自定义 deliver 的渠道中作为 fallback 使用。
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
