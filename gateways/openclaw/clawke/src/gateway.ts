import WebSocket from "ws";
import { readFileSync, existsSync, readdirSync, type Dirent } from "node:fs";
import { join } from "node:path";
import { homedir } from "node:os";
import type { ChannelGatewayContext, ReplyPayload } from "openclaw/plugin-sdk";
import { createChannelReplyPipeline } from "openclaw/plugin-sdk/channel-reply-pipeline";
import type { ResolvedClawkeAccount } from "./config.js";
import { GatewayMessageType, InboundMessageType, AgentStatus } from "./protocol.js";
import { getClawkeRuntime } from "./runtime.js";
import { OpenClawTaskAdapter, type OpenClawTaskDraft, type OpenClawTaskPatch } from "./task-adapter.js";

// 模块级状态（生命周期级，非请求级）
// ws/gatewayCtx: 在 startClawkeGateway 建立连接时设置，在整个 gateway 生命周期内共享
// pendingUsage/Model/Provider: 由 index.ts 的 llm_output hook 设置，deliver 时消费。
//   限制：当前为模块级，而非请求级，因为 hook 和 handler 在不同文件中。
//   缓解：handleClawkeInbound 入口处重置，确保每次请求从干净状态开始。
let ws: WebSocket | null = null;
let gatewayCtx: ChannelGatewayContext<ResolvedClawkeAccount> | null = null;

let pendingUsage: Record<string, number> | null = null;
let pendingModel = '';
let pendingProvider = '';
const taskAdapter = new OpenClawTaskAdapter();

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

// Per-session 串行派发队列：确保同一 session 的消息按序执行，
// 防止 OpenClaw ReplyRunRegistry 因并发 run 抛出 ReplyRunAlreadyActiveError。
// key = senderId (即 conversation_id)，value = 上一次 dispatch 的 Promise
const activeDispatches = new Map<string, Promise<void>>();

// per-dispatch AbortController：abort 时通过 SDK 原生 AbortSignal 切断 LLM 流。
// handleClawkeInbound 内通过局部 send() 检查 signal.aborted 拦截残余消息。
const dispatchAbortControllers = new Map<string, AbortController>();

// 流式输出过程中持续更新的部分回复文本缓存（abort 时读取）
const dispatchPartialTexts = new Map<string, string>();

// abort 后保存的部分回复，供下次消息注入 system prompt 告知 AI 不要重复回答
const abortedPartials = new Map<string, string>();

// 标记某个 senderId 正在执行合成 stop dispatch（回复应被静默丢弃）
const silentDispatches = new Set<string>();

/** 从 OpenClaw 配置中提取可用模型列表 */
function getAvailableModels(ctx: ChannelGatewayContext<ResolvedClawkeAccount>): string[] {
  try {
    const configPath = join(homedir(), ".openclaw", "openclaw.json");
    if (!existsSync(configPath)) return [];

    const config = JSON.parse(readFileSync(configPath, "utf-8"));
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

/**
 * 扫描 OpenClaw 所有 skill 目录获取可用 Skills（对齐 OpenClaw workspace.ts loadSkillEntries）
 *
 * OpenClaw 原生扫描 6 个来源（优先级从低到高，同名 skill 后者覆盖前者）：
 *   1. openclaw-extra     — openclaw.json > skills.load.extraDirs + plugin skills
 *   2. openclaw-bundled   — <openclaw-package>/skills/
 *   3. openclaw-managed   — ~/.openclaw/skills/   (openclaw skills install)
 *   4. agents-personal    — ~/.agents/skills/
 *   5. agents-project     — <workspace>/.agents/skills/
 *   6. openclaw-workspace — <workspace>/skills/
 *
 * 我们的 Gateway 作为 plugin 无法 import OpenClaw 内部 API，所以复刻目录扫描逻辑。
 * 对于 extraDirs / plugin skills 暂不扫描（需要 config 解析），对于 bundled skills 使用启发式。
 */
function getAvailableSkills(ctx: ChannelGatewayContext<ResolvedClawkeAccount>): Array<{ name: string; description: string }> {
  const home = homedir();
  const configDir = join(home, ".openclaw");

  // 推断 workspaceDir：从 OpenClaw 配置中读取，fallback 到 ~/.openclaw/workspace
  let workspaceDir = join(configDir, "workspace"); // OpenClaw 默认 workspace
  try {
    const configPath = join(configDir, "openclaw.json");
    if (existsSync(configPath)) {
      const config = JSON.parse(readFileSync(configPath, "utf-8"));
      const agents = config?.agents;
      if (agents && typeof agents === "object") {
        // OpenClaw 配置结构：agents.defaults.workspace
        if (agents.defaults?.workspace) {
          workspaceDir = agents.defaults.workspace;
        }
        // 也检查 per-agent 的 workspace 配置
        const agentList = agents.list;
        if (Array.isArray(agentList)) {
          const defaultAgent = agentList.find((a: any) => a.default) || agentList[0];
          if (defaultAgent?.workspace) {
            workspaceDir = defaultAgent.workspace;
          }
        }
      }
    }
  } catch { /* ignore */ }

  // 推断 bundled skills 目录
  let bundledSkillsDir: string | undefined;
  try {
    // 方法 1: 可执行文件旁的 skills/ 目录（bun --compile 场景）
    const execDir = join(process.execPath, "..");
    // 方法 2: 当前模块向上查找（npm/dev 场景）
    const moduleDir = new URL(".", import.meta.url).pathname;
    const candidates = [
      join(execDir, "skills"),
      join(moduleDir, "..", "skills"),
      join(moduleDir, "..", "..", "skills"),
      join(moduleDir, "..", "..", "..", "skills"),
    ];
    for (const c of candidates) {
      if (existsSync(c)) { bundledSkillsDir = c; break; }
    }
  } catch { /* ignore */ }

  // 6 个扫描目录（按优先级从低到高）
  const scanDirs: Array<{ dir: string; source: string }> = [];

  // 2. openclaw-bundled
  if (bundledSkillsDir) {
    scanDirs.push({ dir: bundledSkillsDir, source: "openclaw-bundled" });
  }
  // 3. openclaw-managed
  scanDirs.push({ dir: join(configDir, "skills"), source: "openclaw-managed" });
  // 4. agents-skills-personal
  scanDirs.push({ dir: join(home, ".agents", "skills"), source: "agents-skills-personal" });
  // 5. agents-skills-project
  scanDirs.push({ dir: join(workspaceDir, ".agents", "skills"), source: "agents-skills-project" });
  // 6. openclaw-workspace
  scanDirs.push({ dir: join(workspaceDir, "skills"), source: "openclaw-workspace" });

  const merged = new Map<string, { name: string; description: string }>();

  for (const { dir } of scanDirs) {
    try {
      if (!existsSync(dir)) continue;
      const entries = readdirSync(dir, { withFileTypes: true }) as Dirent[];
      for (const entry of entries) {
        if (!entry.isDirectory() || entry.name.startsWith(".")) continue;
        const skillMd = join(dir, entry.name, "SKILL.md");
        if (!existsSync(skillMd)) continue;
        const content = readFileSync(skillMd, "utf-8");
        // Extract name and description from YAML frontmatter
        let name = entry.name;
        let desc = entry.name;
        const fmMatch = content.match(/^---\s*\n([\s\S]*?)\n---/);
        if (fmMatch) {
          const nameMatch = fmMatch[1].match(/name:\s*(.+)/i);
          if (nameMatch) name = nameMatch[1].trim();
          const descMatch = fmMatch[1].match(/description:\s*(.+)/i);
          if (descMatch) desc = descMatch[1].trim();
        } else {
          const firstLine = content.split("\n").find(
            (l: string) => l.trim() && !l.startsWith("#") && !l.startsWith("---")
          );
          if (firstLine) desc = firstLine.trim().slice(0, 120);
        }
        // 后加载覆盖先加载（同名 skill 以高优先级为准）
        merged.set(name, { name, description: desc });
      }
    } catch { /* ignore individual dir failures */ }
  }

  const skills = Array.from(merged.values()).sort((a, b) => a.name.localeCompare(b.name));
  ctx.log?.info(`📦 Skills discovered: ${skills.length} skills from ${scanDirs.filter(d => existsSync(d.dir)).length} dirs`);
  return skills;
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
          type: GatewayMessageType.Identify,
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
          if (isTaskCommand(msg.type)) {
            handleTaskCommand(ctx, msg)
              .then((response) => ws?.send(JSON.stringify(response)))
              .catch((err: any) => {
                ws?.send(JSON.stringify({
                  type: responseTypeForTaskCommand(msg.type),
                  request_id: msg.request_id,
                  ok: false,
                  error: "task_error",
                  message: err?.message || String(err),
                }));
              });
          } else if (msg.type === InboundMessageType.Chat) {
            const text = msg.text || "";
            ctx.log?.info(`📥 Inbound message: ${text.slice(0, 80)}`);
            // 串行队列：同 session 的消息按序执行，不并发
            const senderId = msg.conversation_id || "clawke_user";
            const prevDispatch = activeDispatches.get(senderId);
            const thisDispatch = (async () => {
              if (prevDispatch) {
                ctx.log?.info(`⏳ Session ${senderId} busy, queuing message: ${text.slice(0, 40)}`);
                // 通知客户端：消息已排队等待
                sendToClawkeServer({
                  type: GatewayMessageType.AgentStatus,
                  status: AgentStatus.Queued,
                  to: `user:${senderId}`,
                  account_id: ctx.accountId,
                  conversation_id: senderId,
                });
                // 等待前一个 dispatch 完成
                await prevDispatch.catch(() => {});
                // abort 检查：如果入队后该会话被 abort，跳过执行
                const ac = dispatchAbortControllers.get(senderId);
                if (ac?.signal.aborted) {
                  ctx.log?.info(`🚫 Session ${senderId} aborted, dropping queued message: ${text.slice(0, 40)}`);
                  return;
                }
                ctx.log?.info(`▶️  Session ${senderId} idle, executing queued message: ${text.slice(0, 40)}`);
              }
              await handleClawkeInbound(ctx, msg);
            })();
            // 跟踪当前 dispatch，完成后自动清理
            activeDispatches.set(senderId, thisDispatch);
            thisDispatch.catch((err) => ctx.log?.error(`Failed to dispatch inbound: ${String(err)}`)).finally(() => {
                // 只在自己是最新的 dispatch 时清理（避免清掉后续入队的）
                if (activeDispatches.get(senderId) === thisDispatch) {
                  activeDispatches.delete(senderId);
                }
              });
          } else if (msg.type === InboundMessageType.Abort) {
            const abortSenderId = msg.conversation_id || "clawke_user";
            ctx.log?.info(`📥 Abort request: conversation=${abortSenderId}`);
            // 通过 SDK 原生 AbortSignal 切断 LLM 流
            const ac = dispatchAbortControllers.get(abortSenderId);
            if (ac && !ac.signal.aborted) {
              ac.abort();
              // 保存被中止的部分回复，供下次消息注入 system prompt
              const partial = dispatchPartialTexts.get(abortSenderId);
              if (partial && partial.trim()) {
                abortedPartials.set(abortSenderId, partial);
                ctx.log?.info(`📝 Saved aborted partial (${partial.length} chars) for ${abortSenderId}`);
              }
              dispatchPartialTexts.delete(abortSenderId);
              ctx.log?.info(`📥 AbortController.abort() called for ${abortSenderId}`);

              // 等当前 dispatch 结束后，发送合成 "stop" 消息触发 OpenClaw 内部 abort 处理
              // OpenClaw 的 handleAbortTrigger 会设置 sessionEntry.abortedLastRun = true，
              // 使下次 AI 回复时自动注入 "The previous agent run was aborted" 提示。
              // 通过 silentDispatches 标记静默丢弃合成 dispatch 的回复（不能 abort AC，
              // 否则会中断 SDK 内部的 stop 命令处理流程）。
              const currentDispatch = activeDispatches.get(abortSenderId);
              const dispatchStop = async () => {
                if (currentDispatch) {
                  try { await currentDispatch; } catch {}
                }
                ctx.log?.info(`📤 Dispatching synthetic 'stop' for abort cleanup: ${abortSenderId}`);
                silentDispatches.add(abortSenderId);
                try {
                  await handleClawkeInbound(ctx, {
                    type: 'chat',
                    text: 'stop',
                    conversation_id: msg.conversation_id,
                    _synthetic: true,
                  });
                  ctx.log?.info(`📤 Synthetic 'stop' dispatch completed`);
                } catch (e) {
                  ctx.log?.warn(`Synthetic 'stop' dispatch failed: ${e}`);
                } finally {
                  silentDispatches.delete(abortSenderId);
                }
              };
              // 注册到串行队列：后续用户消息会排在 stop 之后，
              // 防止并发 dispatch 导致 ReplyRunAlreadyActiveError
              const stopPromise = dispatchStop();
              activeDispatches.set(abortSenderId, stopPromise);
              stopPromise.finally(() => {
                if (activeDispatches.get(abortSenderId) === stopPromise) {
                  activeDispatches.delete(abortSenderId);
                }
              });
            }
          } else if (msg.type === InboundMessageType.QueryModels) {
            // 查询可用模型列表
            const models = getAvailableModels(ctx);
            ws!.send(JSON.stringify({ type: GatewayMessageType.ModelsResponse, models }));
            ctx.log?.info(`📤 Models response: ${models.length} models`);
          } else if (msg.type === InboundMessageType.QuerySkills) {
            // 查询可用 Skills 列表
            const skills = getAvailableSkills(ctx);
            ws!.send(JSON.stringify({ type: GatewayMessageType.SkillsResponse, skills }));
            ctx.log?.info(`📤 Skills response: ${skills.length} skills`);
          }
        } catch (err: any) {
          ctx.log?.error(`Failed to parse inbound message: ${err.message}. Raw: ${raw.toString().slice(0, 50)}...`);
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

type TaskCommandMessage = {
  type: string;
  request_id?: string;
  account_id?: string;
  task_id?: string;
  run_id?: string;
  task?: OpenClawTaskDraft;
  draft?: OpenClawTaskDraft;
  patch?: OpenClawTaskPatch;
  enabled?: boolean;
};

function isTaskCommand(type: unknown): type is string {
  return typeof type === "string" && type.startsWith("task_");
}

function responseTypeForTaskCommand(type: string): GatewayMessageType {
  switch (type) {
    case InboundMessageType.TaskList:
      return GatewayMessageType.TaskListResponse;
    case InboundMessageType.TaskGet:
      return GatewayMessageType.TaskGetResponse;
    case InboundMessageType.TaskRun:
      return GatewayMessageType.TaskRunResponse;
    case InboundMessageType.TaskRuns:
      return GatewayMessageType.TaskRunsResponse;
    case InboundMessageType.TaskOutput:
      return GatewayMessageType.TaskOutputResponse;
    default:
      return GatewayMessageType.TaskMutationResponse;
  }
}

async function handleTaskCommand(
  ctx: ChannelGatewayContext<ResolvedClawkeAccount>,
  msg: TaskCommandMessage,
): Promise<Record<string, unknown>> {
  const accountId = msg.account_id || ctx.accountId;
  const base = {
    type: responseTypeForTaskCommand(msg.type),
    request_id: msg.request_id,
    ok: true,
  };

  switch (msg.type) {
    case InboundMessageType.TaskList:
      return { ...base, tasks: await taskAdapter.listTasks(accountId) };
    case InboundMessageType.TaskGet:
      return { ...base, task: await taskAdapter.getTask(accountId, requireTaskId(msg)) };
    case InboundMessageType.TaskCreate:
      return { ...base, task: await taskAdapter.createTask(accountId, requireDraft(msg)) };
    case InboundMessageType.TaskUpdate:
      return { ...base, task: await taskAdapter.updateTask(accountId, requireTaskId(msg), msg.patch ?? {}) };
    case InboundMessageType.TaskDelete:
      return { ...base, task_id: requireTaskId(msg), deleted: await taskAdapter.deleteTask(accountId, requireTaskId(msg)) };
    case InboundMessageType.TaskSetEnabled:
      if (typeof msg.enabled !== "boolean") throw new Error("enabled must be boolean");
      return { ...base, task: await taskAdapter.setEnabled(accountId, requireTaskId(msg), msg.enabled) };
    case InboundMessageType.TaskRun: {
      const run = await taskAdapter.runTask(accountId, requireTaskId(msg));
      return { ...base, runs: [run] };
    }
    case InboundMessageType.TaskRuns:
      return { ...base, runs: await taskAdapter.listRuns(requireTaskId(msg)) };
    case InboundMessageType.TaskOutput:
      return { ...base, output: await taskAdapter.getOutput(requireTaskId(msg), requireRunId(msg)) };
    default:
      throw new Error(`Unsupported task command: ${msg.type}`);
  }
}

function requireTaskId(msg: TaskCommandMessage): string {
  if (!msg.task_id) throw new Error("task_id is required");
  return msg.task_id;
}

function requireRunId(msg: TaskCommandMessage): string {
  if (!msg.run_id) throw new Error("run_id is required");
  return msg.run_id;
}

function requireDraft(msg: TaskCommandMessage): OpenClawTaskDraft {
  const draft = msg.task ?? msg.draft;
  if (!draft) throw new Error("task draft is required");
  return draft;
}

/**
 * 处理从 Clawke Server 收到的用户消息，派发给 OpenClaw Agent。
 *
 * 简化版流程：
 * 1. resolveAgentRoute → 路由
 * 2. finalizeInboundContext → 构建上下文
 * 3. createReplyDispatcherWithTyping → 创建带 deliver 回调的分发器
 * 4. withReplyDispatcher + dispatchReplyFromConfig → 派发并等待回复
 */
/** 加载 system-prompt（Gateway 侧注入，支持热更新） */
function loadSystemPrompt(ctx: ChannelGatewayContext<ResolvedClawkeAccount>): string {
  try {
    const promptPath = join(process.cwd(), 'config', 'system-prompt.md');
    if (existsSync(promptPath)) {
      return readFileSync(promptPath, 'utf-8').trim();
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
    // 内部标记：合成 stop dispatch（跳过 abort context 和 system prompt 注入）
    _synthetic?: boolean;
  },
): Promise<void> {
  const core = getClawkeRuntime();
  const cfg = ctx.cfg;

  // P2-2.1: 每次请求入口重置 pending 状态，缓解模块级变量的跨请求污染
  pendingUsage = null;
  pendingModel = '';
  pendingProvider = '';

  // per-dispatch AbortController：传给 SDK 的 abortSignal，abort 时切断 LLM 流
  const dispatchSenderId = msg.conversation_id || "clawke_user";
  const dispatchAC = new AbortController();
  dispatchAbortControllers.set(dispatchSenderId, dispatchAC);

  // 局部 send：捕获自己的 AC 引用，abort 后静默丢弃，不依赖全局 Map 查找
  // 也检查 silentDispatches 标记，用于合成 stop dispatch 的回复静默丢弃
  const _sendToClawkeServer = (jsonObj: Record<string, unknown>) => {
    if (dispatchAC.signal.aborted) {
      ctx.log?.info(`🚫 send SKIP (aborted): type=${jsonObj.type}`);
      // 从被拦截的消息中提取文本，保存为 abort 上下文
      // （解决 deliver 在 abort handler 之后执行的竞态问题）
      const skippedText = (jsonObj.text as string) || (jsonObj.fullText as string) || (jsonObj.delta as string) || '';
      if (skippedText.trim() && !abortedPartials.has(dispatchSenderId)) {
        abortedPartials.set(dispatchSenderId, skippedText);
        ctx.log?.info(`📝 Captured aborted text from send SKIP (${skippedText.length} chars)`);
      }
      return;
    }
    if (silentDispatches.has(dispatchSenderId)) {
      ctx.log?.info(`🔇 send SKIP (silent stop dispatch): type=${jsonObj.type}`);
      return;
    }
    sendToClawkeServer(jsonObj);
  };

  // 注入 system-prompt（Gateway 侧负责，支持热更新）
  let text = msg.text || "";
  let systemPrompt = loadSystemPrompt(ctx);

  // abort 上下文注入：如果上一轮被中止，告知 AI 不要重复回答
  // 合成 stop dispatch 跳过此注入（否则会干扰 OpenClaw 的 isAbortTrigger 检测）
  if (!msg._synthetic) {
    const abortedText = abortedPartials.get(dispatchSenderId);
    if (abortedText) {
      const abortCtx = `[System] The previous conversation turn was aborted by the user. ` +
        `The partial response that was generated (but not delivered) was: "${abortedText.slice(0, 200)}". ` +
        `Do NOT repeat or continue the aborted response. Answer the user's new question directly.`;
      systemPrompt = systemPrompt ? `${systemPrompt}\n\n${abortCtx}` : abortCtx;
      abortedPartials.delete(dispatchSenderId);
      ctx.log?.info(`📝 Injected abort context for ${dispatchSenderId}: ${abortedText.slice(0, 60)}`);
    }
  }

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

  // 合成 stop dispatch 不注入 system prompt（保持纯 "stop" 文本以匹配 isAbortTrigger）
  if (systemPrompt && !msg._synthetic) {
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

  // Media resolution: try local file first, fall back to HTTP download.
  let resolvedMediaPaths = mediaPaths;
  const fs = await import("fs");
  const MAX_MEDIA_BYTES = 20 * 1024 * 1024;
  const httpBase = (csHttpBase || ctx.account.httpUrl).replace(/\/$/, "");

  if (mediaPaths && mediaPaths.length > 0) {
    ctx.log?.info(`handleClawkeInbound: httpBase=${csHttpBase}, relUrls=${JSON.stringify(mediaRelativeUrls)}, paths=${JSON.stringify(mediaPaths)}`);

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
          ctx.log?.info(`Local copy: ${localPaths[i]} → ${saved.path}`);
        } catch (e: any) {
          ctx.log?.error(`Local copy error: ${e.message}`);
        }
      }
    } else {
      // No local files found — clear resolvedMediaPaths so HTTP fallback kicks in
      ctx.log?.info(`Local files not found: ${mediaPaths.join(', ')} → falling back to HTTP`);
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
          ctx.log?.info(`Downloaded: ${fullUrl} → ${saved.path} (${buffer.length} bytes)`);
        } else {
          ctx.log?.error(`HTTP download failed: ${fullUrl} → ${resp.status}`);
        }
      } catch (e: any) {
        ctx.log?.error(`HTTP download error: ${fullUrl} → ${e.message}`);
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
    // P1-1.1: Typing 指示器 — AI 开始回复前通知客户端显示"正在思考..."
    typing: {
      start: () => _sendToClawkeServer({
        type: GatewayMessageType.AgentTyping,
        to: clawkeTo,
        account_id: ctx.accountId,
        conversation_id: senderId,
      }),
      onStartError: (err) => ctx.log?.error(`typing failed: ${String(err)}`),
    },
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

  // P1: 投递去重追踪器 — 防止同一内容被意外发送两次
  const deliveredTexts = new Set<string>();

  const { dispatcher, replyOptions, markDispatchIdle } =
    core.channel.reply.createReplyDispatcherWithTyping({
      ...replyPipeline,  // P0-0.3: 标准 pipeline 配置（prefix + typing + transform）
      deliver: async (payload: ReplyPayload, info?: { kind?: string }) => {
        const kind = info?.kind ?? "final";
        const replyText = payload.text ?? "";
        // 更新部分回复缓存（deliver 可能在 onPartialReply 之外被调用，如非流式回复）
        if (replyText) {
          dispatchPartialTexts.set(dispatchSenderId, replyText);
        }
        ctx.log?.info(`deliver: kind=${kind}, hasStreamedAny=${hasStreamedAny}, textLen=${replyText.length}`);

        // P0-0.1: disableBlockStreaming=true 后，deliver 只会收到 kind="final"
        // 无需处理 block 逻辑

        // P1: deliveryTracker 去重 — 防止同一文本被重复投递
        const dedupeKey = `${kind}:${replyText.slice(0, 200)}`;
        if (deliveredTexts.has(dedupeKey)) {
          ctx.log?.info(`⏭️ deliver SKIP duplicate: ${replyText.slice(0, 60)}`);
          return;
        }
        deliveredTexts.add(dedupeKey);

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
            _sendToClawkeServer({
              type: GatewayMessageType.AgentTextDelta,
              message_id: streamMsgId,
              delta,
              to: clawkeTo,
              account_id: ctx.accountId,
              conversation_id: senderId,
            });
          }

          _sendToClawkeServer({
            type: GatewayMessageType.AgentTextDone,
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
          _sendToClawkeServer({
            type: GatewayMessageType.AgentText,
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
          _sendToClawkeServer({
            type: GatewayMessageType.AgentMedia,
            message_id: streamMsgId,
            mediaUrl,
            to: clawkeTo,
            account_id: ctx.accountId,
            conversation_id: senderId,
          });
        }
      },
      onError: (error) => {
        ctx.log?.error(`Reply dispatch error: ${String(error)}`);
        lastError = error instanceof Error ? error : new Error(String(error));
      },
      // P1-1.6: onSkip — SDK 跳过某个 payload 时记录，便于排查和兜底
      onSkip: (payload: ReplyPayload, info: { kind: string; reason: string }) => {
        ctx.log?.info(`⏭️ SDK skipped ${info.kind} reply (reason=${info.reason}): ${(payload.text ?? '').slice(0, 60)}`);
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
  let lastSentItemTitle = "";

  // 结束上一个工具调用（如有），发送 agent_tool_result
  const finalizeLastTool = () => {
    const last = toolCalls[toolCalls.length - 1];
    if (last && !('endTime' in last)) {
      const durationMs = Date.now() - last.startTime;
      _sendToClawkeServer({
        type: GatewayMessageType.AgentToolResult,
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
        abortSignal: dispatchAC.signal,  // SDK 原生 abort：切断 LLM 流
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
            _sendToClawkeServer({
              type: GatewayMessageType.AgentTextDone,
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
            _sendToClawkeServer({
              type: GatewayMessageType.AgentTextDelta,
              message_id: streamMsgId,
              delta,
              to: clawkeTo,
              account_id: ctx.accountId,
              conversation_id: senderId,
            });
            lastSentLength = text.length;
            lastFullText = text;
            dispatchPartialTexts.set(dispatchSenderId, text);
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
            _sendToClawkeServer({
              type: GatewayMessageType.AgentThinkingDelta,
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
            _sendToClawkeServer({
              type: GatewayMessageType.AgentThinkingDone,
              message_id: thinkingMsgId,
              to: clawkeTo,
              account_id: ctx.accountId,
              conversation_id: senderId,
            });
            lastThinkingLength = 0;
            hasStreamedThinking = false;
          }
        },
        // 工具调用开始（仅追踪，不发消息 — onItemEvent 负责带 title 的通知）
        onToolStart: (payload: { name?: string; phase?: string }) => {
          finalizeLastTool();
          const toolName = payload.name || "tool";
          const toolCallId = `${streamMsgId}_tool_${++toolCallCounter}`;
          toolCalls.push({ name: toolName, startTime: Date.now(), id: toolCallId });
          ctx.log?.info(`🔧 onToolStart: name=${toolName}, phase=${payload.phase}, id=${toolCallId}`);
        },
        // P1-1.4: 上下文压缩通知 — 长对话上下文窗口满时通知客户端
        onCompactionStart: () => {
          _sendToClawkeServer({
            type: GatewayMessageType.AgentStatus,
            status: AgentStatus.Compacting,
            message_id: streamMsgId,
            to: clawkeTo,
            account_id: ctx.accountId,
            conversation_id: senderId,
          });
        },
        onCompactionEnd: () => {
          _sendToClawkeServer({
            type: GatewayMessageType.AgentStatus,
            status: AgentStatus.Thinking,
            message_id: streamMsgId,
            to: clawkeTo,
            account_id: ctx.accountId,
            conversation_id: senderId,
          });
        },
        // P0-0.3: 工具执行详情 — 提供 exec 的具体指令/标题
        // SDK 的 onItemEvent 含 title（如 "exec fetch url, `curl ...`"）
        // kind=tool 和 kind=command 内容相同，用 lastSentItemTitle 去重
        onItemEvent: (payload: {
          itemId?: string; kind?: string; title?: string; name?: string;
          phase?: string; status?: string; summary?: string; progressText?: string;
        }) => {
          if (payload.phase !== "start") return;
          const rawTitle = payload.title || payload.name || "";
          if (!rawTitle) return;
          // 提取干净的显示标题：截取反引号内的命令部分
          let displayTitle = rawTitle;
          const backtickMatch = rawTitle.match(/`([^`]+)`/);
          if (backtickMatch) {
            const cmd = backtickMatch[1];
            displayTitle = cmd.length > 60 ? cmd.slice(0, 57) + "..." : cmd;
          } else {
            displayTitle = rawTitle.replace(/^(exec|command)\s+/i, "");
            if (displayTitle.length > 60) displayTitle = displayTitle.slice(0, 57) + "...";
          }
          // 去重：同一个命令不重复发送
          if (displayTitle === lastSentItemTitle) return;
          lastSentItemTitle = displayTitle;
          const lastTool = toolCalls[toolCalls.length - 1];
          ctx.log?.info(`📋 onItemEvent: title=${displayTitle}`);
          _sendToClawkeServer({
            type: GatewayMessageType.AgentToolCall,
            message_id: streamMsgId,
            toolCallId: lastTool?.id || `${streamMsgId}_item_${Date.now()}`,
            toolName: lastTool?.name || payload.name || "tool",
            toolTitle: displayTitle,
            account_id: ctx.accountId,
            conversation_id: senderId,
          });
        },
      },
    });
    queuedFinal = result.queuedFinal;
    counts = result.counts;
  } catch (dispatchError: any) {
    ctx.log?.error(`dispatchReplyFromConfig threw: ${dispatchError?.message || dispatchError}`);
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
    _sendToClawkeServer({
      type: GatewayMessageType.AgentTurnStats,
      message_id: streamMsgId,
      toolCallCount: toolCalls.length,
      tools: toolCalls.map((t) => t.name),
      account_id: ctx.accountId,
      conversation_id: senderId,
    });
  }

  // 清理已完成 dispatch 的 partial text 缓存
  dispatchPartialTexts.delete(dispatchSenderId);

  ctx.log?.info(`Dispatch complete: queuedFinal=${queuedFinal}, replies=${counts.final}, tools=${toolCalls.length}`);

  // 兜底：AI 没有产生任何回复（NO_REPLY 被静默过滤）
  if (!hasStreamedAny && counts.final === 0) {
    if (lastError) {
      ctx.log?.error(`AI silent due to LLM error. Sending error to client: ${lastError}`);
    } else {
      ctx.log?.warn(`AI silent with no error (0 tokens generated). Session may have been busy or LLM returned empty.`);
    }
    const errorInfo = lastError
      ? _classifyError((lastError as Error).message)
      : { error_code: "no_reply", detail: "" };

    _sendToClawkeServer({
      type: GatewayMessageType.AgentText,
      message_id: streamMsgId,
      text: errorInfo.detail || `[${errorInfo.error_code}]`,
      error_code: errorInfo.error_code,
      error_detail: errorInfo.detail,
      to: clawkeTo,
      account_id: ctx.accountId,
      conversation_id: senderId,
    });
  }
}

/** 将异常消息分类为结构化错误码，供客户端 i18n 翻译 */
// ⚠️ 关键词表需与 Hermes Gateway (clawke_channel.py _classify_error) 保持同步
function _classifyError(msg: string): { error_code: string; detail: string } {
  const lower = msg.toLowerCase();
  const detail = msg.slice(0, 100);

  if (["api key", "authentication", "unauthorized", "403", "invalid_api_key"].some(kw => lower.includes(kw)))
    return { error_code: "auth_failed", detail };

  if (["timeout", "connect", "connection refused", "dns", "econnrefused"].some(kw => lower.includes(kw)))
    return { error_code: "network_error", detail };

  if (["rate limit", "429", "too many requests", "quota"].some(kw => lower.includes(kw)))
    return { error_code: "rate_limited", detail };

  if (["model not found", "model_not_found", "does not exist"].some(kw => lower.includes(kw)))
    return { error_code: "model_unavailable", detail };

  return { error_code: "agent_error", detail };
}

/**
 * 向 Clawke Server 发送 JSON 消息（供 deliver 和 outbound adapter 使用）
 * P2-2.3: 添加错误日志 + WebSocket 断连检测
 */
export function sendToClawkeServer(jsonObj: Record<string, unknown>): void {
  if (ws && ws.readyState === WebSocket.OPEN) {
    try {
      ws.send(JSON.stringify(jsonObj));
    } catch (err: any) {
      gatewayCtx?.log?.error(`sendToClawkeServer failed: type=${jsonObj.type}, error=${err.message}`);
    }
  } else {
    gatewayCtx?.log?.error(`sendToClawkeServer: WebSocket not connected, dropping message: type=${jsonObj.type}`);
  }
}
