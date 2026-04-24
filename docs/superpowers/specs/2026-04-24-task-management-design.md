# 任务管理功能设计

日期：2026-04-24

## 背景

Clawke 需要一个一等公民级别的任务管理页面，用来管理 agent 侧的定时任务和后台任务。页面需要支持任务列表、创建、编辑、删除、启用、暂停、手动触发，以及查看执行记录和执行结果。

实现逻辑可以参考 Hermes WebUI 的 Tasks 页面，但不能照搬它的 Web UI 样式。Clawke 应该使用现有 Flutter 原生管理页的风格。

当前的 `server/src/services/cron-service.ts` 是早期 mock/SDUI 原型：它把 cron 数据存在本地 SQLite，只在 mock 模式出现，而且没有接入当前 `ActionRouter` 流程。新任务管理功能不以它为设计基础。

## 已确认决策

- 任务管理是独立 app 页面，不是聊天会话里的消息体验。
- Flutter 到 Clawke Server 的任务管理请求走 HTTP，对齐现有 Skills 等独立管理页。
- Clawke Server 不执行任务、不跑调度 tick、不持久化任务真相。
- agent/gateway 侧是任务存储和任务执行的权威来源。
- 首批支持 Hermes 和 OpenClaw。
- Clawke Server 将 HTTP 请求转换成 gateway 任务命令，并通过现有 upstream WebSocket 连接发给对应 gateway。

## 目标

- 提供 Flutter 原生任务管理页面。
- 用一套 Server-facing Task API 同时支持 Hermes 和 OpenClaw。
- 保持任务执行和任务存储都在 agent/gateway 侧。
- 展示任务元数据、启用状态、调度规则、prompt、选中 skills、最近执行状态、执行历史和输出结果。
- 允许用户手动触发任务，但 Clawke 本身不执行 prompt。

## 非目标

- Clawke Server 不实现 cron scheduler。
- Clawke Server 不执行任务 prompt。
- Clawke Server 不在 SQLite 中维护可编辑的任务镜像。
- 初版不聚合所有离线 account 的任务。
- 初版不复制 Hermes WebUI 的视觉样式。

## 架构

### Flutter Client

新增独立的 `TasksManagementScreen`，结构参考 `SkillsManagementScreen`。这是一个独立管理页，因此应该使用类型化 HTTP API service，而不是通过聊天消息或 SDUI 页面消息完成主要工作流。

页面包含：

- 顶部统计区，展示任务数量、运行中/暂停/失败数量，并提供刷新和创建入口。
- 搜索和筛选，支持按状态、启用状态、agent/account、调度类型过滤。
- 任务列表卡片，优先保证信息密度和可扫描性。
- 创建/编辑弹窗，包含名称、调度规则、prompt、交付方式、skills、启用状态。
- 执行记录视图，展示最近 runs。
- 输出查看器，展示指定 run 的完整输出。

Client 状态使用 Riverpod controller 管理，并由 `TasksApiService` 驱动。HTTP 请求使用 Dio，并复用现有 `MediaResolver` 的 base URL 和 auth header 逻辑。

Client 到 Server 的传输选择：

- 独立管理页走 HTTP：Skills 管理页已经采用这个模式。
- 聊天和实时 agent stream 走 WebSocket。
- Server-driven UI card 走 CUP over WebSocket。
- 因此任务管理页从 Flutter 到 Clawke Server 应走 HTTP。

### Clawke Server

新增 `server/src/routes/tasks-routes.ts`，并在 `server/src/http-server.ts` 中注册。

HTTP 层负责输入校验、选择 account/gateway、通过现有 upstream WebSocket 转发命令、等待结构化响应、统一错误格式。它不把任务记录作为权威数据存储。

Server 到 Gateway 的传输选择：

- Gateway 已经通过持久 upstream WebSocket 连接到 Clawke Server。
- 现有 models/skills 等运行时查询已经使用 Server-to-Gateway WS request/response。
- 任务命令应复用这条 upstream WS 通道，不为每个 gateway 新增 HTTP server。

建议 HTTP endpoints：

- `GET /api/tasks?account_id=:accountId`
- `GET /api/tasks/:taskId?account_id=:accountId`
- `POST /api/tasks`
- `PUT /api/tasks/:taskId`
- `DELETE /api/tasks/:taskId?account_id=:accountId`
- `PUT /api/tasks/:taskId/enabled`
- `POST /api/tasks/:taskId/run`
- `GET /api/tasks/:taskId/runs?account_id=:accountId`
- `GET /api/tasks/:taskId/runs/:runId/output?account_id=:accountId`

修改任务或查看单个任务详情的请求必须包含 `account_id`，可以放在 query 或 body 中。如果省略 `account_id`，只有在当前恰好连接了一个 gateway account 时，Server 才可以使用这个唯一 account 作为默认值。

### Gateway Task Protocol

Server 到 Gateway 的命令：

- `task_list`
- `task_get`
- `task_create`
- `task_update`
- `task_delete`
- `task_set_enabled`
- `task_run`
- `task_runs`
- `task_output`

Gateway 到 Server 的响应：

- `task_list_response`
- `task_get_response`
- `task_mutation_response`
- `task_run_response`
- `task_runs_response`
- `task_output_response`

Gateway 到 Server 的异步事件：

- `task_event`，事件类型包括 `started`、`completed`、`failed`、`cancelled`

协议中必须包含 `request_id`，用于 Server 将 HTTP 请求和 gateway 响应精确关联。这个设计类似现有 models/skills 查询模式，但需要显式 request correlation，避免多个 HTTP 请求并发时串包。

## 数据模型

### Task

```ts
interface ManagedTask {
  id: string;
  account_id: string;
  agent: 'hermes' | 'openclaw' | string;
  name: string;
  schedule: string;
  schedule_text?: string;
  prompt: string;
  enabled: boolean;
  status: 'active' | 'paused' | 'disabled' | 'error';
  skills?: string[];
  deliver?: 'local' | 'discord' | 'telegram' | string;
  next_run_at?: string;
  last_run?: TaskRunSummary;
  created_at?: string;
  updated_at?: string;
}
```

### Task Draft

```ts
interface TaskDraft {
  account_id: string;
  name?: string;
  schedule: string;
  prompt: string;
  enabled?: boolean;
  skills?: string[];
  deliver?: string;
}
```

### Task Run

```ts
interface TaskRun {
  id: string;
  task_id: string;
  started_at: string;
  finished_at?: string;
  status: 'running' | 'success' | 'failed' | 'cancelled';
  output_preview?: string;
  error?: string;
}
```

## Hermes Adapter

Hermes gateway 将通用任务协议映射到 Hermes cron 能力：

- `task_list` 映射到 `cron.jobs.list_jobs`。
- `task_create` 映射到 `cron.jobs.create_job`。
- `task_update` 映射到 `cron.jobs.update_job`。
- `task_delete` 映射到 `cron.jobs.remove_job`。
- `task_set_enabled` 映射到 pause/resume 行为。
- `task_run` 映射到 Hermes 手动执行行为，并在 run 已开始后返回。
- `task_runs` 读取 Hermes 执行记录或输出元数据。
- `task_output` 读取指定 run 的输出。

Hermes 仍然负责调度和任务执行。

## OpenClaw Adapter

OpenClaw gateway 实现同一套任务协议。如果 OpenClaw 已经有原生 task/scheduler 机制，adapter 应该包装它；如果 OpenClaw 目前没有原生任务存储，那么可以在 OpenClaw gateway 侧提供一个轻量 agent-owned task adapter，但任务存储仍属于 OpenClaw/gateway 侧，而不是 Clawke Server。

OpenClaw 仍然负责调度和任务执行。

## UI 行为

任务页使用 Clawke 原生管理页风格：

- 卡片紧凑，信息密度高，适合快速扫描。
- 控件稳定，覆盖创建、编辑、删除、启用、暂停、恢复、立即运行、查看 runs、查看输出。
- 明确处理 empty、loading、error、disconnected 状态。
- Hermes 和 OpenClaw 同时连接时显示 account 选择器。
- Skill picker 根据当前选中的 account 获取 skills。
- Schedule 输入支持 cron expression，也支持所选 gateway 声明支持的自然 shorthand，例如 `every 1h`。

页面的主要工作流不依赖聊天消息或 SDUI message card。Flutter 结构应和 Skills 管理页一致：typed model、Dio API service、Riverpod controller、完整管理视图。

### 桌面端布局

桌面端采用方案 A：三栏 operations console。

- 最左侧是 Clawke 全局导航 rail，包含 Chat、Dashboard、Tasks、Skills、Settings，Tasks 处于选中状态。
- 中间是 gateway/account 列表栏，展示 Hermes、OpenClaw 等连接状态、任务数量、失败提示和最近同步时间。
- 右侧主区域是任务管理工作区，包含顶部统计、搜索筛选、新建任务入口和任务列表。
- 最右侧可打开任务详情/运行输出 drawer，用于查看选中任务的最近 runs、完整输出、错误信息和手动触发结果。
- 主区域保持管理台风格：高信息密度、明确状态、稳定操作按钮，不使用聊天气泡或营销化卡片。

### 移动端布局

移动端参考 Skills 管理页面的移动端方案。

- 使用单列信息流，顶部展示标题、当前 gateway 选择器、统计和新建任务按钮。
- Gateway/account 列表收进顶部选择器或底部 sheet，避免固定三栏压缩主内容。
- 搜索和筛选位于任务列表上方，必要时折叠为 filter sheet。
- 任务详情、编辑表单、运行记录和输出查看使用全屏 dialog 或 bottom sheet。
- 操作优先使用清晰的图标按钮和菜单，保证任务卡片在窄屏下仍可扫描。

## 错误处理

- 如果没有 gateway account 连接，页面展示 disconnected 状态，HTTP 返回 `503`。
- 如果 `account_id` 有歧义，HTTP 返回 `400` 和 `account_required`。
- 如果 gateway 不支持任务管理，HTTP 返回 `501` 和 `tasks_unsupported`。
- 如果 gateway 超时，HTTP 返回 `504` 和 `gateway_timeout`。
- 参数校验错误返回 `400`，尽量包含字段级错误。
- Gateway 错误统一归一化为 `{ error, message, details? }`。

## 测试

Server 测试：

- HTTP route 校验和鉴权。
- Account 选择逻辑。
- Gateway 超时行为。
- HTTP endpoint 到 gateway command 的映射。
- 错误响应归一化。

Gateway 测试：

- Hermes task command handling，mock `cron.jobs`。
- OpenClaw task command handling，mock adapter。
- `request_id` 响应关联。

Flutter 测试：

- Task API service 序列化。
- Task controller 的加载、创建、更新、删除、启用、运行、错误状态。
- Task management screen 的 loading、empty、populated、filter、edit dialog、delete confirmation、run history、output viewer 状态。

## 待确认问题

- OpenClaw 是否已经有可包装的原生 scheduled-task 存储。
- Hermes run history 是否暴露结构化元数据，还是主要依赖 output 文件。
- 任务完成事件是否在首版触发原生通知，还是放到后续迭代。
