import WebSocket from "ws";
import type { ChannelGatewayContext, ReplyPayload } from "openclaw/plugin-sdk";
import { createReplyPrefixContext } from "openclaw/plugin-sdk/channel-runtime";
import type { ResolvedClawkeAccount } from "./config.js";
import { getClawkeRuntime } from "./runtime.js";

let ws: WebSocket | null = null;
let gatewayCtx: ChannelGatewayContext<ResolvedClawkeAccount> | null = null;

// llm_output hook 捕获的 usage 数据，deliver 时合并到 text_done
let pendingUsage: Record<string, number> | null = null;
let pendingModel = '';
let pendingProvider = '';

/** 由 index.ts llm_output hook 调用，累加 usage 数据（多轮工具调用时合计） */
export function addPendingUsage(usage: Record<string, number> | null, model?: string, provider?: string): void {
  if (usage) {
    if (!pendingUsage) {
      pendingUsage = { ...usage };
    } else {
      for (const key of Object.keys(usage)) {
        pendingUsage[key] = (pendingUsage[key] || 0) + (usage[key] || 0);
      }
    }
  }
  // model/provider 取最后一次的（工具调用开头和最终回复可能用不同 model，取最后一次更准）
  if (model) pendingModel = model;
  if (provider) pendingProvider = provider;
}

// 指数退避重连参数
const BACKOFF_FIRST_MS = 100;
const BACKOFF_MAX_MS = 10_000;
const BACKOFF_BASE = 2;

function getBackoffMs(attempt: number): number {
  const exponential = BACKOFF_FIRST_MS * Math.pow(BACKOFF_BASE, attempt);
  const capped = Math.min(exponential, BACKOFF_MAX_MS);
  // ±25% 抖动
  return Math.round(capped * (0.75 + Math.random() * 0.5));
}

/**
 * Gateway 启动入口：建立 WebSocket 连接到 Clawke Server，断线自动重连。
 *
 * Promise 生命周期：
 * - open:  不 resolve（保持 pending = 账户运行中）
 * - close: 自动重连（指数退避 + 抖动，100ms → 10s 封顶）
 * - abort: resolve（Gateway 主动停止，正常结束）
 * - error: 记录日志，close 事件触发重连
 */
export async function startClawkeGateway(
  ctx: ChannelGatewayContext<ResolvedClawkeAccount>,
): Promise<void> {
  const url = ctx.account.url;
  gatewayCtx = ctx;

  return new Promise<void>((resolve) => {
    let reconnectAttempt = 0;
    let reconnectTimer: ReturnType<typeof setTimeout> | null = null;

    const cleanup = () => {
      if (reconnectTimer) {
        clearTimeout(reconnectTimer);
        reconnectTimer = null;
      }
      if (ws) {
        try { ws.close(); } catch { /* ignore */ }
        ws = null;
      }
      gatewayCtx = null;
    };

    const handleAbort = () => {
      ctx.log?.info(`Shutting down Clawke Server connection`);
      cleanup();
      resolve();
    };

    if (ctx.abortSignal.aborted) {
      cleanup();
      resolve();
      return;
    }

    ctx.abortSignal.addEventListener("abort", handleAbort, { once: true });

    function scheduleReconnect() {
      if (ctx.abortSignal.aborted) return;
      const delay = getBackoffMs(reconnectAttempt);
      reconnectAttempt++;
      ctx.log?.info(`Reconnecting to Clawke Server in ${delay}ms (attempt ${reconnectAttempt})`);
      reconnectTimer = setTimeout(() => {
        reconnectTimer = null;
        connect();
      }, delay);
    }

    function connect() {
      if (ctx.abortSignal.aborted) return;

      ctx.log?.info(`Connecting to Clawke Server: ${url}`);
      ws = new WebSocket(url);

      ws.on("open", () => {
        ctx.log?.info(`Connected to Clawke Server`);
        reconnectAttempt = 0;
        // 握手：告知 Clawke Server 我的 accountId
        ws!.send(JSON.stringify({
          type: "identify",
          accountId: ctx.accountId,
        }));
        ctx.setStatus({
          accountId: ctx.accountId,
          connected: true,
          running: true,
          lastConnectedAt: Date.now(),
        });
      });

      ws.on("message", (raw) => {
        try {
          const msg = JSON.parse(raw.toString());
          if (msg.type === "chat") {
            const text = msg.text || "";
            ctx.log?.info(`📥 Inbound message: ${text.slice(0, 80)}`);
            handleClawkeInbound(ctx, msg).catch((err) => {
              ctx.log?.error(`Failed to dispatch inbound: ${String(err)}`);
            });
          } else if (msg.type === "abort") {
            ctx.log?.info(`📥 Abort request: conversation=${msg.conversation_id}`);
          }
        } catch {
          /* 非 JSON 消息忽略 */
        }
      });

      ws.on("close", () => {
        ctx.log?.info(`Disconnected from Clawke Server`);
        ws = null;
        ctx.setStatus({
          accountId: ctx.accountId,
          connected: false,
          running: true,
          lastDisconnect: { at: Date.now() },
        });
        scheduleReconnect();
      });

      ws.on("error", (err) => {
        ctx.log?.error(`WebSocket error: ${err.message}`);
        // close 事件会紧随触发，由 close 处理重连
      });
    }

    connect();
  });
}

/**
 * 处理从 Clawke Server 收到的用户消息，派发给 OpenClaw Agent。
 *
 * 简化版流程（参考飞书 handleFeishuMessage + createFeishuReplyDispatcher）：
 * 1. resolveAgentRoute → 路由
 * 2. finalizeInboundContext → 构建上下文
 * 3. createReplyDispatcherWithTyping → 创建带 deliver 回调的分发器
 * 4. withReplyDispatcher + dispatchReplyFromConfig → 派发并等待回复
 */
/** 加载 system-prompt（Gateway 侧注入，支持热更新） */
function loadSystemPrompt(ctx: ChannelGatewayContext<ResolvedClawkeAccount>): string {
  try {
    const fs = require("fs");
    const path = require("path");
    // system-prompt.md 放在 Gateway 运行目录的 config/ 下
    const promptPath = path.join(process.cwd(), 'config', 'system-prompt.md');
    if (fs.existsSync(promptPath)) {
      return fs.readFileSync(promptPath, 'utf-8').trim();
    }
  } catch { /* ignore */ }
  return '';
}

async function handleClawkeInbound(
  ctx: ChannelGatewayContext<ResolvedClawkeAccount>,
  msg: {
    type: 'chat';
    text?: string;
    content_type?: string;
    conversation_id?: string;
    client_msg_id?: string;
    media?: {
      paths?: string[]; types?: string[]; names?: string[];
      relativeUrls?: string[]; httpBase?: string;
    };
  },
): Promise<void> {
  const core = getClawkeRuntime();
  const cfg = ctx.cfg;

  // 注入 system-prompt（Gateway 侧负责，支持热更新）
  let text = msg.text || "";
  const systemPrompt = loadSystemPrompt(ctx);
  if (systemPrompt) {
    text = `${text}\n\n---\n${systemPrompt}`;
  }

  const senderId = "clawke_user";
  const peerId = `clawke:${senderId}`;
  const messageId = msg.client_msg_id || `clawke_${Date.now()}`;
  const clawkeFrom = `clawke:${senderId}`;
  const clawkeTo = `user:${senderId}`;

  // media 直接从标准协议读取
  const mediaPaths = msg.media?.paths;
  const mediaTypes = msg.media?.types;
  const fileNames = msg.media?.names;
  const mediaRelativeUrls = msg.media?.relativeUrls;
  const csHttpBase = msg.media?.httpBase;

  console.log(`[Clawke-GW] 🔍 handleClawkeInbound: httpBase=${csHttpBase}, relUrls=${JSON.stringify(mediaRelativeUrls)}, paths=${JSON.stringify(mediaPaths)}`);

  // Media resolution: try local file first, fall back to HTTP download.
  let resolvedMediaPaths = mediaPaths;
  const fs = await import("fs");
  const MAX_MEDIA_BYTES = 20 * 1024 * 1024;
  const httpBase = (csHttpBase || ctx.account.httpUrl).replace(/\/$/, "");


  if (mediaPaths && mediaPaths.length > 0) {
    // Try reading files from local disk (works when CS and GW are co-located)
    const localPaths = mediaPaths.filter(p => fs.existsSync(p));
    if (localPaths.length > 0) {
      resolvedMediaPaths = [];
      for (let i = 0; i < localPaths.length; i++) {
        const buffer = fs.readFileSync(localPaths[i]);
        const fileName = fileNames?.[i] || `file_${i}`;
        const contentType = mediaTypes?.[i] || undefined;
        try {
          const saved = await core.channel.media.saveMediaBuffer(
            buffer,
            contentType,
            "inbound",
            MAX_MEDIA_BYTES,
            fileName,
          );
          resolvedMediaPaths.push(saved.path);
          console.log(`[Clawke-GW] 📁 Local copy: ${localPaths[i]} → ${saved.path}`);
        } catch (e: any) {
          console.error(`[Clawke-GW] ❌ Local copy error: ${e.message}`);
        }
      }
    } else {
      // No local files found — clear resolvedMediaPaths so HTTP fallback kicks in
      console.log(`[Clawke-GW] ⚠️ Local files not found: ${mediaPaths.join(', ')} → falling back to HTTP`);
      resolvedMediaPaths = [];
    }
  }

  // HTTP download fallback: if local files were not found or not provided
  if ((!resolvedMediaPaths || resolvedMediaPaths.length === 0)
      && mediaRelativeUrls && mediaRelativeUrls.length > 0) {
    resolvedMediaPaths = [];
    for (let i = 0; i < mediaRelativeUrls.length; i++) {
      const relUrl = mediaRelativeUrls[i];
      const fullUrl = `${httpBase}${relUrl}`;
      const fileName = fileNames?.[i] || `file_${i}`;
      const contentType = mediaTypes?.[i] || undefined;

      try {
        const resp = await fetch(fullUrl);
        if (resp.ok) {
          const buffer = Buffer.from(await resp.arrayBuffer());
          const saved = await core.channel.media.saveMediaBuffer(
            buffer,
            contentType || resp.headers.get("content-type") || undefined,
            "inbound",
            MAX_MEDIA_BYTES,
            fileName,
          );
          resolvedMediaPaths.push(saved.path);
          console.log(`[Clawke-GW] 📥 Downloaded: ${fullUrl} → ${saved.path} (${buffer.length} bytes)`);
        } else {
          console.error(`[Clawke-GW] ❌ HTTP download failed: ${fullUrl} → ${resp.status}`);
        }
      } catch (e: any) {
        console.error(`[Clawke-GW] ❌ HTTP download error: ${fullUrl} → ${e.message}`);
      }
    }
  }

  // 1. 路由到目标 Agent
  const route = core.channel.routing.resolveAgentRoute({
    cfg,
    channel: "clawke",
    accountId: ctx.accountId,
    peer: { kind: "direct", id: peerId },
  });

  // 2. 构建消息信封与上下文
  const envelopeOptions = core.channel.reply.resolveEnvelopeFormatOptions(cfg);
  const body = core.channel.reply.formatAgentEnvelope({
    channel: "Clawke",
    from: senderId,
    timestamp: new Date(),
    envelope: envelopeOptions,
    body: text,
  });

  // BodyForCommands / CommandBody 只放用户原文，不注入指令
  // ⚠️ 向 BodyForCommands 注入 /reasoning、/thinking 等指令会导致：
  //   - CommandAuthorized=false 时：被 get-reply-run.ts 当作未授权命令静默丢弃
  //   - CommandAuthorized=true 时：被当作"设置指令"命令，返回 ack 而不执行 agent
  // 如需启用 reasoning/thinking，应通过 OpenClaw 的 agents.list[].reasoningDefault 配置

  const ctxPayload = core.channel.reply.finalizeInboundContext({
    Body: body,
    BodyForAgent: text,
    RawBody: text,
    CommandBody: text,
    BodyForCommands: text,
    From: clawkeFrom,
    To: clawkeTo,
    SessionKey: route.sessionKey,
    AccountId: route.accountId,
    ChatType: "direct",
    SenderName: senderId,
    SenderId: senderId,
    Provider: "clawke" as any,
    Surface: "clawke" as any,
    MessageSid: messageId,
    Timestamp: Date.now(),
    OriginatingChannel: "clawke" as any,
    OriginatingTo: clawkeTo,
    CommandAuthorized: true,
    // Media paths (local or shared)
    ...(resolvedMediaPaths && resolvedMediaPaths.length > 0 ? {
      MediaPaths: resolvedMediaPaths,
      MediaPath: resolvedMediaPaths[0],
      MediaTypes: mediaTypes,
      MediaType: mediaTypes?.[0] || "application/octet-stream",
    } : {}),
  });

  // 3. 创建回复分发器（参考飞书 createFeishuReplyDispatcher）
  // deliver 回调是 Agent 回复到达时的实际发送函数
  const prefixContext = createReplyPrefixContext({ cfg, agentId: route.agentId });

  // 流式输出状态：跟踪已发送长度，计算差量
  const streamMsgId = `reply_${Date.now()}`;
  let lastSentLength = 0;
  let lastFullText = "";
  let hasStreamedAny = false;

  // Thinking 流式状态
  const thinkingMsgId = `think_${Date.now()}`;
  let lastThinkingLength = 0;
  let hasStreamedThinking = false;

  const { dispatcher, replyOptions, markDispatchIdle } =
    core.channel.reply.createReplyDispatcherWithTyping({
      responsePrefix: prefixContext.responsePrefix,
      responsePrefixContextProvider: prefixContext.responsePrefixContextProvider,
      humanDelay: core.channel.reply.resolveHumanDelayConfig(cfg, route.agentId),
      deliver: async (payload: ReplyPayload) => {
        const replyText = payload.text ?? "";

        const mediaList = payload.mediaUrls?.length
          ? payload.mediaUrls
          : payload.mediaUrl
            ? [payload.mediaUrl]
            : [];

        // 如果之前有流式输出，发送 done 终结流
        if (hasStreamedAny) {
          // 发送最后一批剩余差量（如果有）
          if (replyText.length > lastSentLength) {
            const delta = replyText.slice(lastSentLength);
            sendToClawkeServer({
              type: "agent_text_delta",
              message_id: streamMsgId,
              delta,
              to: clawkeTo,
              account_id: ctx.accountId,
            });
          }
          // 🔍 诊断日志：deliver 时 pendingUsage 状态（测试后移除）
          console.log(`[Clawke-Usage] 📤 deliver(stream): hasPendingUsage=${!!pendingUsage}, model=${pendingModel}, usage=${JSON.stringify(pendingUsage ?? null)}`);
          sendToClawkeServer({
            type: "agent_text_done",
            message_id: streamMsgId,
            fullText: replyText,
            to: clawkeTo,
            account_id: ctx.accountId,
            ...(pendingModel ? { usage: pendingUsage ?? undefined, model: pendingModel, provider: pendingProvider } : {}),
          });
          ctx.log?.info(`📤 Reply done (stream): ${replyText.slice(0, 80)}`);
          pendingUsage = null;
          pendingModel = '';
          pendingProvider = '';
        } else if (replyText.trim()) {
          // 没有流式输出（fallback），直接发完整文本
          // 🔍 诊断日志（测试后移除）
          console.log(`[Clawke-Usage] 📤 deliver(full): hasPendingUsage=${!!pendingUsage}, model=${pendingModel}, usage=${JSON.stringify(pendingUsage ?? null)}`);
          sendToClawkeServer({
            type: "agent_text",
            message_id: streamMsgId,
            text: replyText,
            to: clawkeTo,
            account_id: ctx.accountId,
            ...(pendingModel ? { usage: pendingUsage ?? undefined, model: pendingModel, provider: pendingProvider } : {}),
          });
          ctx.log?.info(`📤 Reply done (full): ${replyText.slice(0, 80)}`);
          pendingUsage = null;
          pendingModel = '';
          pendingProvider = '';
        }

        // 重置流式状态（支持多轮回复）
        lastSentLength = 0;
        lastFullText = "";
        hasStreamedAny = false;

        for (const mediaUrl of mediaList) {
          sendToClawkeServer({
            type: "agent_media",
            message_id: `reply_${Date.now()}`,
            mediaUrl,
            to: clawkeTo,
            account_id: ctx.accountId,
          });
        }
      },
      onError: (error) => {
        ctx.log?.error(`Reply dispatch error: ${String(error)}`);
        console.error(`[Clawke-GW] 🚨 LLM Reply Dispatch Error:`, error);
        lastError = error instanceof Error ? error : new Error(String(error));
      },
      onIdle: () => {
        ctx.log?.info(`Reply dispatch idle for message ${messageId}`);
      },
    });

  // 4. 通知系统事件 + 派发
  core.system.enqueueSystemEvent(`Clawke DM from ${senderId}: ${text.slice(0, 120)}`, {
    sessionKey: route.sessionKey,
    contextKey: `clawke:message:${messageId}`,
  });

  ctx.log?.info(`Dispatching to agent (session=${route.sessionKey})`);

  // 工具调用追踪
  const toolCalls: Array<{ name: string; startTime: number; id: string }> = [];
  let toolCallCounter = 0;

  // 结束上一个工具调用（如有），发送 agent_tool_result
  const finalizeLastTool = () => {
    const last = toolCalls[toolCalls.length - 1];
    if (last && !('endTime' in last)) {
      const durationMs = Date.now() - last.startTime;
      sendToClawkeServer({
        type: "agent_tool_result",
        message_id: streamMsgId,
        toolCallId: last.id,
        toolName: last.name,
        durationMs,
        account_id: ctx.accountId,
      });
    }
  };

  let queuedFinal = false;
  let counts = { final: 0 };
  let lastError: Error | null = null;
  try {
    const result = await core.channel.reply.dispatchReplyFromConfig({
      ctx: ctxPayload,
      cfg,
      dispatcher,
      replyOptions: {
        ...replyOptions,
        onModelSelected: prefixContext.onModelSelected,
        // 流式回调：每个 LLM token 片段到达时触发
        onPartialReply: (payload: ReplyPayload) => {
          const text = payload.text ?? "";
          ctx.log?.info(`[DEBUG] onPartialReply called: textLen=${text.length}, lastSent=${lastSentLength}`);
          if (text.length > lastSentLength) {
            const delta = text.slice(lastSentLength);
            sendToClawkeServer({
              type: "agent_text_delta",
              message_id: streamMsgId,
              delta,
              to: clawkeTo,
              account_id: ctx.accountId,
            });
            lastSentLength = text.length;
            lastFullText = text;
            hasStreamedAny = true;
          }
        },
        // Thinking 流式回调：深度思考推理过程
        onReasoningStream: (payload: ReplyPayload) => {
          let text = payload.text ?? "";
          if (text.startsWith("Reasoning:\n")) {
            text = text.slice("Reasoning:\n".length);
          }
          text = text.replace(/^_(.*)_$/gm, "$1");
          
          if (text.length > lastThinkingLength) {
            const delta = text.slice(lastThinkingLength);
            sendToClawkeServer({
              type: "agent_thinking_delta",
              message_id: thinkingMsgId,
              delta,
              to: clawkeTo,
              account_id: ctx.accountId,
            });
            lastThinkingLength = text.length;
            hasStreamedThinking = true;
          }
        },
        // Thinking 结束信号
        onReasoningEnd: () => {
          if (hasStreamedThinking) {
            sendToClawkeServer({
              type: "agent_thinking_done",
              message_id: thinkingMsgId,
              to: clawkeTo,
              account_id: ctx.accountId,
            });
            lastThinkingLength = 0;
            hasStreamedThinking = false;
          }
        },
        // 工具调用开始
        onToolStart: (payload: { name?: string; phase?: string }) => {
          finalizeLastTool();
          const toolName = payload.name || "tool";
          const toolCallId = `${streamMsgId}_tool_${++toolCallCounter}`;
          toolCalls.push({ name: toolName, startTime: Date.now(), id: toolCallId });
          sendToClawkeServer({
            type: "agent_tool_call",
            message_id: streamMsgId,
            toolCallId,
            toolName,
            account_id: ctx.accountId,
          });
        },
      },
    });
    queuedFinal = result.queuedFinal;
    counts = result.counts;
  } catch (dispatchError: any) {
    console.error(`[Clawke-DEBUG] ❌ dispatchReplyFromConfig THREW:`, dispatchError?.message || dispatchError, dispatchError?.stack);
  } finally {
    dispatcher.markComplete();
    try {
      await dispatcher.waitForIdle();
    } finally {
      markDispatchIdle();
    }
  }

  // 结束最后一个工具调用（如有）
  finalizeLastTool();

  // 发送本轮工具统计摘要给 Clawke Server（用于 Dashboard）
  if (toolCalls.length > 0) {
    sendToClawkeServer({
      type: "agent_turn_stats",
      message_id: streamMsgId,
      toolCallCount: toolCalls.length,
      tools: toolCalls.map((t) => t.name),
      account_id: ctx.accountId,
    });
  }

  ctx.log?.info(`Dispatch complete: queuedFinal=${queuedFinal}, replies=${counts.final}, tools=${toolCalls.length}`);

  // 兜底：AI 没有产生任何回复（NO_REPLY 被静默过滤） → 发送友好引导
  if (!hasStreamedAny && counts.final === 0) {
    if (lastError) {
      console.error(`[Clawke-GW] 🚨 AI silent due to LLM error. Sending error to client:`, lastError);
    } else {
      console.warn(`[Clawke-GW] ⚠️ AI silent with no error (0 tokens generated). Sending fallback reply.`);
    }
    const fallbackText = lastError 
      ? `请求大模型接口失败：${(lastError as Error).message}` 
      : "嗯，能再详细说一下吗？😊";
      
    sendToClawkeServer({
      type: "agent_text",
      message_id: streamMsgId,
      text: fallbackText,
      to: clawkeTo,
      account_id: ctx.accountId,
    });
  }
}

/**
 * 向 Clawke Server 发送 JSON 消息（供 deliver 和 outbound adapter 使用）
 */
export function sendToClawkeServer(jsonObj: Record<string, unknown>): void {
  if (ws && ws.readyState === WebSocket.OPEN) {
    try {
      ws.send(JSON.stringify(jsonObj));
    } catch {
      /* 发送失败忽略 */
    }
  }
}
