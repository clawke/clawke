import WebSocket from "ws";
import type { ChannelGatewayContext, ReplyPayload } from "openclaw/plugin-sdk";
import { createChannelReplyPipeline } from "openclaw/plugin-sdk/channel-reply-pipeline";
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

// 每个会话当前使用的模型（用于首次/变化时注入 /model）
const sessionModels = new Map<string, string>();

/** 从 OpenClaw 配置中提取可用模型列表 */
function getAvailableModels(ctx: ChannelGatewayContext<ResolvedClawkeAccount>): string[] {
  try {
    const fs = require("fs");
    const path = require("path");
    const os = require("os");
    const configPath = path.join(os.homedir(), ".openclaw", "openclaw.json");
    if (!fs.existsSync(configPath)) return [];

    const config = JSON.parse(fs.readFileSync(configPath, "utf-8"));
    const providers = config?.models?.providers;
    if (!providers || typeof providers !== "object") return [];

    const models = new Set<string>();
    for (const providerKey of Object.keys(providers)) {
      const providerModels = providers[providerKey]?.models;
      if (Array.isArray(providerModels)) {
        for (const m of providerModels) {
          if (m.id) models.add(m.id);
          else if (m.name) models.add(m.name);
        }
      }
    }
    return [...models];
  } catch (e: any) {
    ctx.log?.error(`getAvailableModels failed: ${e.message}`);
  }
  return [];
}

/** 扫描 .openclaw/workspace/skills/ 目录获取可用 Skills */
function getAvailableSkills(): Array<{ name: string; description: string }> {
  try {
    const fs = require("fs");
    const path = require("path");
    const os = require("os");
    const skillsDir = path.join(os.homedir(), ".openclaw", "workspace", "skills");
    if (!fs.existsSync(skillsDir)) return [];

    const entries = fs.readdirSync(skillsDir, { withFileTypes: true });
    const skills: Array<{ name: string; description: string }> = [];
    for (const entry of entries) {
      if (!entry.isDirectory()) continue;
      const skillMd = path.join(skillsDir, entry.name, "SKILL.md");
      if (!fs.existsSync(skillMd)) continue;
      const content = fs.readFileSync(skillMd, "utf-8");
      // Extract description from YAML frontmatter or first non-header line
      let desc = entry.name;
      const fmMatch = content.match(/^---\s*\n([\s\S]*?)\n---/);
      if (fmMatch) {
        const descMatch = fmMatch[1].match(/description:\s*(.+)/i);
        if (descMatch) desc = descMatch[1].trim();
      } else {
        const firstLine = content.split("\n").find(
          (l: string) => l.trim() && !l.startsWith("#") && !l.startsWith("---")
        );
        if (firstLine) desc = firstLine.trim().slice(0, 120);
      }
      skills.push({ name: entry.name, description: desc });
    }
    return skills;
  } catch {
    return [];
  }
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
          } else if (msg.type === "query_models") {
            // 查询可用模型列表
            const models = getAvailableModels(ctx);
            ws!.send(JSON.stringify({ type: "models_response", models }));
            ctx.log?.info(`📤 Models response: ${models.length} models`);
          } else if (msg.type === "query_skills") {
            // 查询可用 Skills 列表
            const skills = getAvailableSkills();
            ws!.send(JSON.stringify({ type: "skills_response", skills }));
            ctx.log?.info(`📤 Skills response: ${skills.length} skills`);
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
    // 会话配置（Server 注入）
    model_override?: string;
    skills_hint?: string[];
    skill_mode?: 'priority' | 'exclusive';
    system_prompt?: string;
    work_dir?: string;
  },
): Promise<void> {
  const core = getClawkeRuntime();
  const cfg = ctx.cfg;

  // 注入 system-prompt（Gateway 侧负责，支持热更新）
  let text = msg.text || "";
  let systemPrompt = loadSystemPrompt(ctx);

  // 会话定制 system-prompt
  if (msg.system_prompt) {
    systemPrompt = msg.system_prompt + (systemPrompt ? '\n\n' + systemPrompt : '');
  }

  // Skill 约束注入
  if (msg.skills_hint && msg.skills_hint.length > 0) {
    const skillNames = msg.skills_hint.join(', ');
    if (msg.skill_mode === 'exclusive') {
      systemPrompt += `\n\n[IMPORTANT] 你是一个专属工具助手。每次回复时，你必须调用以下 skill 中的一个来完成任务，不要直接回答。\n可用 skills: ${skillNames}\n如果用户的问题不明确匹配哪个 skill，选择最接近的一个调用。`;
    } else {
      systemPrompt += `\n\n[提示] 回答时优先考虑使用以下 skill: ${skillNames}`;
    }
    ctx.log?.info(`[ConvConfig] skills=${skillNames}, mode=${msg.skill_mode || 'priority'}`);
  }

  if (msg.work_dir) {
    ctx.log?.info(`[ConvConfig] workDir=${msg.work_dir}`);
  }

  if (systemPrompt) {
    text = `${text}\n\n---\n${systemPrompt}`;
  }

  // 模型切换（首次/变化时注入 /model 命令）
  const senderId = msg.conversation_id || "clawke_user";
  if (msg.model_override && sessionModels.get(senderId) !== msg.model_override) {
    sessionModels.set(senderId, msg.model_override);
    ctx.log?.info(`[ConvConfig] Switching model to: ${msg.model_override} for session=${senderId}`);
    // 通过 system event 通知 OpenClaw 切换模型
    // 直接在 BodyForCommands 中注入 /model 命令
    try {
      const modelRoute = core.channel.routing.resolveAgentRoute({
        cfg,
        channel: "clawke",
        accountId: ctx.accountId,
        peer: { kind: "direct", id: `clawke:${senderId}` },
      });
      const modelBody = `/model ${msg.model_override}`;
      const modelCtx = core.channel.reply.finalizeInboundContext({
        Body: modelBody,
        BodyForAgent: modelBody,
        RawBody: modelBody,
        CommandBody: modelBody,
        BodyForCommands: modelBody,
        From: `clawke:${senderId}`,
        To: `user:${senderId}`,
        SessionKey: modelRoute.sessionKey,
        AccountId: modelRoute.accountId,
        ChatType: "direct",
        SenderName: senderId,
        SenderId: senderId,
        Provider: "clawke" as any,
        Surface: "clawke" as any,
        MessageSid: `model_switch_${Date.now()}`,
        Timestamp: Date.now(),
        OriginatingChannel: "clawke" as any,
        OriginatingTo: `user:${senderId}`,
        CommandAuthorized: true,
      });
      const modelDispatcher = core.channel.reply.createReplyDispatcherWithTyping({
        ctx: modelCtx,
        cfg,
        sessionKey: modelRoute.sessionKey,
        dispatcher: { deliver: async () => {} },
        replyOptions: {},
      });
      await core.channel.reply.withReplyDispatcher(modelCtx, modelDispatcher, async () => {
        await core.channel.reply.dispatchReplyFromConfig({
          ctx: modelCtx, cfg, dispatcher: modelDispatcher, replyOptions: {},
        });
      });
      ctx.log?.info(`[ConvConfig] ✅ Model switched to: ${msg.model_override}`);
    } catch (e: any) {
      ctx.log?.error(`[ConvConfig] ❌ Model switch failed: ${e.message}`);
    }
  }

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

  // 3. 创建回复分发器（使用标准 Channel Reply Pipeline）
  // P0-0.3: 使用 createChannelReplyPipeline 替代手动 createReplyPrefixContext，
  // 获得标准的 typing/prefix/transform 支持
  const { onModelSelected, ...replyPipeline } = createChannelReplyPipeline({
    cfg,
    agentId: route.agentId,
    channel: "clawke",
    accountId: ctx.accountId,
  });

  // 流式输出状态：跟踪已发送长度，计算差量
  let streamMsgId = `reply_${Date.now()}`;
  let msgCounter = 0;  // 防止 streamMsgId 在毫秒内冲突
  let lastSentLength = 0;
  let lastFullText = "";
  let hasStreamedAny = false;

  // Thinking 流式状态
  const thinkingMsgId = `think_${Date.now()}`;
  let lastThinkingLength = 0;
  let hasStreamedThinking = false;

  const { dispatcher, replyOptions, markDispatchIdle } =
    core.channel.reply.createReplyDispatcherWithTyping({
      ...replyPipeline,  // P0-0.3: 标准 pipeline 配置（prefix + typing + transform）
      deliver: async (payload: ReplyPayload, info?: { kind?: string }) => {
        const kind = info?.kind ?? "final";
        const replyText = payload.text ?? "";
        ctx.log?.info(`deliver: kind=${kind}, hasStreamedAny=${hasStreamedAny}, textLen=${replyText.length}`);

        // P0-0.1: disableBlockStreaming=true 后，deliver 只会收到 kind="final"
        // 无需处理 block 逻辑

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
              conversation_id: senderId,
            });
          }

          sendToClawkeServer({
            type: "agent_text_done",
            message_id: streamMsgId,
            fullText: replyText,
            to: clawkeTo,
            account_id: ctx.accountId,
            conversation_id: senderId,
            ...(pendingModel ? { usage: pendingUsage ?? undefined, model: pendingModel, provider: pendingProvider } : {}),
          });
          ctx.log?.info(`📤 Reply done (stream): ${replyText.slice(0, 80)}`);
          pendingUsage = null;
          pendingModel = '';
          pendingProvider = '';
        } else if (replyText.trim()) {
          // 没有流式输出（fallback），直接发完整文本
          sendToClawkeServer({
            type: "agent_text",
            message_id: streamMsgId,
            text: replyText,
            to: clawkeTo,
            account_id: ctx.accountId,
            conversation_id: senderId,
            ...(pendingModel ? { usage: pendingUsage ?? undefined, model: pendingModel, provider: pendingProvider } : {}),
          });
          ctx.log?.info(`📤 deliver done (full): ${replyText.slice(0, 80)}`);
          pendingUsage = null;
          pendingModel = '';
          pendingProvider = '';
        }

        // 发送媒体附件
        for (const mediaUrl of mediaList) {
          sendToClawkeServer({
            type: "agent_media",
            message_id: `reply_${Date.now()}`,
            mediaUrl,
            to: clawkeTo,
            account_id: ctx.accountId,
            conversation_id: senderId,
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
        conversation_id: senderId,
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
      // 会话级工作目录覆盖：通过 configOverride 注入，不修改全局 cfg
      ...(msg.work_dir ? {
        configOverride: { agents: { defaults: { workspace: msg.work_dir } } },
      } : {}),
      replyOptions: {
        ...replyOptions,
        // P0-0.1: 禁用 block streaming — Clawke 通过 onPartialReply 自己做流式，
        // 不需要 SDK 通过 block 投递中间段。所有有自己流式实现的 channel 都设为 true。
        disableBlockStreaming: true,
        onModelSelected,
        // P0-0.2: assistant message 边界处理 — 多段回复（工具调用后继续回复）时
        // SDK 会在每个新 assistant message 开始时触发此回调，重置内部 delta 累积。
        // 所有 L3 channel（Discord/Slack/Telegram/Matrix）都实现了此回调。
        onAssistantMessageStart: () => {
          // 结束上一段流式（如果有）
          if (hasStreamedAny) {
            sendToClawkeServer({
              type: "agent_text_done",
              message_id: streamMsgId,
              fullText: lastFullText,
              to: clawkeTo,
              account_id: ctx.accountId,
              conversation_id: senderId,
            });
          }
          // 重置流式状态，准备接收新的 assistant message
          streamMsgId = `reply_${Date.now()}_${++msgCounter}`;
          lastSentLength = 0;
          lastFullText = "";
          hasStreamedAny = false;
        },
        // 流式回调：每个 LLM token 片段到达时触发
        onPartialReply: (payload: ReplyPayload) => {
          const text = payload.text ?? "";
          if (text.length > lastSentLength) {
            const delta = text.slice(lastSentLength);
            sendToClawkeServer({
              type: "agent_text_delta",
              message_id: streamMsgId,
              delta,
              to: clawkeTo,
              account_id: ctx.accountId,
              conversation_id: senderId,
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
              conversation_id: senderId,
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
              conversation_id: senderId,
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
            conversation_id: senderId,
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
      conversation_id: senderId,
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
      conversation_id: senderId,
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
