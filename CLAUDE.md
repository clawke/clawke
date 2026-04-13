# Clawke - Claude 开发指南

## 项目简介

**⚠️ AI 沟通原则：说话必须极度精简，只讲重点，拒绝废话和过度解释，不要浪费时间。**

Clawke 是一款基于 **Edge-Cloud（边缘-云协同）** 架构的下一代多智能体（MAS）原生工作空间与富客户端 UI 渲染引擎。

核心创新是 **CUP (Clawke UI Protocol)**：Clawke Server 下发标准化 JSON，Native Client 作为无状态"渲染容器"，动态组装原生 UI 积木（Widgets）。

## 产品定位

Clawke 是**全平台产品**，目标覆盖 macOS、Windows、iOS、Android 四端。MVP 阶段优先 macOS Desktop 验证技术闭环，但架构设计和技术选型必须考虑多端兼容性。**严禁做出"仅桌面端"或"仅个人使用"的假设**——性能优化、数据库设计、状态管理等决策都必须兼顾移动端（CPU/内存受限）场景。

## 富客户端设计哲学

Clawke 不是普通的即时通讯应用（IM），而是**专为 OpenClaw 及其他 AI Agent 打造的富客户端工作空间**。如果只是文本对话，用户用任何 IM 都可以。Clawke 的核心价值在于：

- **所有 Agent 能力都必须有原生交互**：如 exec 审批、工具调用确认等，必须用原生按钮/卡片呈现，严禁降级为文本命令（如 `/approve xxx`）
- **全链路改造优先于局部补丁**：宁愿修改 Gateway → Server → Client 三层代码实现完整体验，也不做"发文本命令"的妥协方案
- **交互体验是差异化竞争力**：每个 Agent 交互场景（审批、文件操作、数据库查询等）都应设计专门的 SDUI 组件，让用户感受到与桌面端（ClawX）同等甚至更优的原生体验

> **决策原则**：当遇到"用文本命令快速实现" vs "用原生 UI 组件完整实现"的选择时，永远选择后者。

> **禁止临时兼容方案**：当某层（如 Gateway）的代码没有生效时，**禁止在其他层（如 Server）做 hack 绕过**。正确做法是找到根因（如编译缓存、进程未重启）并解决它。临时方案会变成屎山，且掩盖真正需要修复的问题。重编 + 重启永远优先于 workaround。

## 技术栈

| 层级               | 技术               | 说明                                                                          |
| ------------------ | ------------------ | ----------------------------------------------------------------------------- |
| Native Client      | Flutter            | 全平台（macOS/Windows/iOS/Android），MVP 优先 macOS Desktop，后续同时编译多端 |
| Mock Clawke Server | Node.js 或 Python  | 轻量 WebSocket 脚本，代码量 < 200 行                                          |
| 通信协议           | WebSocket (ws://)  | 全双工，流式文本 + SDUI JSON 广播                                             |
| 状态管理           | 内存级（MVP 阶段） | 无 SQLite，断连即清空                                                         |

## MVP 目标

验证完整技术闭环：

1. **全双工 WebSocket 通信**（Client ↔ Mock Server）
2. **CUP 协议解析**（服务端下发 JSON → 客户端动态渲染 Widget）
3. **纯原生组件渲染**（Flutter 原生绘制，零 WebView）
4. **交互事件回传**（用户点击 → 事件上报 → Server 打印日志）

## 项目结构

```
clawke/
├── CLAUDE.md              # 本文件
├── docs/                  # 📖 开源说明文档（对外公开，随代码提交）
│   ├── MRD.md             # 市场需求文档
│   ├── PRD.md             # 产品需求文档
│   ├── competitive-analysis/  # 竞品分析文档
│   ├── mvp/
│   │   └── MVP.md         # MVP 核心定义
│   └── plans/             # 实施计划（AI 生成）
├── internal-docs/         # 🔒 内部开发文档（.gitignore 排除，不对外公开）
├── client/                # Flutter 原生客户端
├── server/                # Clawke Server（Node.js，双模式：mock / openclaw）
├── gateways/
    └── openclaw/
        └── clawke/        # Clawke 渠道插件（连接 Clawke Server 的 Gateway）
            ├── index.ts
            ├── openclaw.plugin.json
            └── src/
                ├── channel.ts   # ChannelPlugin 定义 + outbound 适配器
                ├── config.ts    # 渠道配置（url / enabled / allowFrom）
                ├── gateway.ts   # WebSocket 连接 Clawke Server + 自动重连
                └── runtime.ts   # PluginRuntime 注入
```

### 文档分类规则

| 目录 | 性质 | Git 追踪 | 内容 |
|------|------|---------|------|
| `docs/` | **开源文档** | ✅ 提交到仓库 | 产品文档、架构说明、用户指南 — 面向开源社区和外部用户 |
| `internal-docs/` | **内部文档** | ❌ `.gitignore` 排除 | 开发笔记、分析报告、调试记录 — 仅供团队内部参考 |

**决策原则**：涉及内部实现细节、调试过程、竞品分析等敏感内容放 `internal-docs/`；产品架构、协议规范、使用说明等适合公开的放 `docs/`。

## 整体架构思路

遵循 **SDUI（Server-Driven UI）** 设计思路：服务端掌控 UI 逻辑，客户端仅负责渲染。具体通过 **CUP（Clawke UI Protocol）** 协议实现——Server 下发标准化 JSON 描述 UI 组件树，Client 解析后动态组装原生 Widget。这意味着：

- **新增 UI 能力不需要发版客户端**：Server 下发新的 `widget_name` + `props`，Client 侧只需注册对应 Builder
- **客户端零业务逻辑**：所有决策（该显示什么、何时显示）由 Server 决定
- **未知组件优雅降级**：遇到不认识的 `widget_name`，显示 `UpgradePromptWidget` 而非崩溃

### 瘦客户端原则

项目目标是多端支持（Mac → iOS → Android），为降低迁移成本，Client 端必须保持"瘦"：

1. **客户端只做渲染 + 交互反馈**，不做业务判断。按 CUP `payload_type` / `widget_name` 分发渲染即可
2. **新功能通过 CUP 组件下发**，不在客户端硬编码业务逻辑（协议级流式特性如 thinking 块除外）
3. **DB 只存消息和会话元数据**，不存业务状态
4. **平台差异用 `LayoutBuilder` / `MediaQuery` 适配**，避免 `if (Platform.isMacOS)` 式的硬分支
5. **共享代码放 `lib/core/`、`lib/models/`、`lib/providers/`**，平台特定 UI 放 `lib/screens/` 或 `lib/widgets/`
### Gateway 反腐败层（Anti-Corruption Layer）

Gateway 层是**唯一允许理解上游 Agent 私有协议的地方**。上游 Agent（如 OpenClaw）的格式变化、API 升级、协议变更，**必须全部在 Gateway 层吸收**，不得传导到 CS Server 或 Client：

```
Flutter Client ←CUP→ CS Server ←CUP→ Gateway A (OpenClaw)
                                 ←CUP→ Gateway B (Future Agent)
                                 ←CUP→ Gateway C (Future Agent)
```

**核心规则**：
1. **Gateway → CS Server 的输出必须是标准化 CUP 消息**，不含任何 Agent 特定的格式/术语
2. **CS Server 和 Client 永远不知道**后面接的是 OpenClaw 还是其他 Agent
3. **OpenClaw 升级时只改 Gateway 层**，CS Server 和 Client 代码零修改
4. **CUP 协议的交互能力（如审批、确认、工具调用）必须设计为通用机制**，不绑定特定 Agent 的概念（如不叫 `exec_approval`，而叫 `action_confirmation`）
5. **严禁在 Gateway 层解析非结构化文本**（如试图 regex 匹配 AI 回复中的命令），必须使用上游 Agent 提供的结构化 API/事件/Hook

> **决策原则**：新增功能时先问"这是 Agent 特定的还是通用的？"。Agent 特定逻辑放 Gateway，通用交互放 CUP 协议。

## 架构概览

```
Flutter Client ←ws:8765→ Clawke Server ←ws:8766→ OpenClaw Gateway（192.168.0.7）
```

- **Clawke Server**（`server/`）：双端口协议翻译网关，`MODE=mock` 用 Mock 数据，`MODE=openclaw` 接真实 AI
- **OpenClaw 实际部署**：运行在 **192.168.0.7** 服务器上，通过 Clawke 渠道插件主动 WebSocket 连接到本机 Clawke Server:8766，断线自动重连（指数退避 100ms→10s + 抖动）
- **`../clawke_extends/openclaw/`**：OpenClaw 源码副本（已移至项目外），方便开发时查阅接口定义和插件代码，**不用于实际运行**
- **Flutter Client**（`client/`）：连接 Clawke Server:8765，断线自动重连

## ⚠️ Clawke 插件架构规则（重要）

**Clawke 是 OpenClaw 的 Channel Plugin**，与飞书（Lark）、Telegram、Discord 等同级：

- 插件代码在 `gateways/openclaw/clawke/`，由 OpenClaw 加载并**运行在 OpenClaw 进程内（in-process）**
- `index.ts` 的 `register(api: OpenClawPluginApi)` 拿到完整的 Plugin API
- **可以使用 OpenClaw 的所有 Plugin Hook**，如 `api.on('llm_output', ...)` 获取真实 token 用量、`api.on('after_tool_call', ...)` 获取工具调用详情等
- 同时通过 WebSocket 与 Clawke Server 通信，将数据转发给 Flutter 客户端

**关键规则**：

1. **严禁修改 OpenClaw 核心代码**（`../clawke_extends/openclaw/src/` 下的文件）来实现 Clawke 功能。OpenClaw 是客户独立安装的，版本不可控
2. **优先使用 Plugin API**（hooks、registerTool、registerCommand 等）来扩展功能
3. 如果 Plugin API 不够用，在 `gateways/openclaw/clawke/` 内部解决（如解析已有的 reply 文本），而非改核心
4. 确有必要时，向 OpenClaw 上游提 PR，但 Clawke 功能不能依赖 PR 被合并

## 关键配置

| 配置项                  | 位置                                                  | 默认值                                                               |
| ----------------------- | ----------------------------------------------------- | -------------------------------------------------------------------- |
| Client → Server 地址    | `client/lib/core/ws_service.dart:9`                   | `ws://127.0.0.1:8765`                                                |
| Server 客户端端口       | `server/.env` `CLIENT_PORT`                           | `8765`                                                               |
| Server 上游端口         | `server/.env` `UPSTREAM_PORT`                         | `8766`                                                               |
| Server 运行模式         | `server/.env` `MODE`                                  | `openclaw`                                                           |
| OpenClaw → Server 地址  | `gateways/openclaw/clawke/src/config.ts:32` | `ws://127.0.0.1:8766`                                                |
| OpenClaw 渠道开关       | OpenClaw 配置文件 `channels.clawke.enabled`           | `false`                                                              |
| OpenClaw 生产部署服务器 | 局域网内独立服务器（**仅生产**）                      | `192.168.0.7`                                                        |
| Clawke 插件生产路径     | macMini 上 OpenClaw 加载的插件目录（**仅生产**）      | `samy@192.168.0.7:~/.openclaw/extensions/clawke/` |
| OpenClaw 启动命令       | 在 192.168.0.7 的 OpenClaw 项目目录下执行             | `pnpm dev gateway --force`                                           |
| OpenClaw 环境变量       | `~/.openclaw/gateway/.env`（192.168.0.7）             | `BRAVE_API_KEY`, `GOOGLE_API_KEY`                                    |

### ⚠️ 开发模式规则

**开发阶段，Server 和 Gateway（OpenClaw）都在本机运行，严禁部署到 192.168.0.7 远程服务器。**

- Server：`cd server && npm run dev`（本机 127.0.0.1:8780）
- OpenClaw Gateway：本机 OpenClaw 实例加载 `gateways/openclaw/clawke/` 插件
- 只有发布 / 部署生产环境时才 scp 到 192.168.0.7

### Clawke 插件部署规则（⚠️ 仅生产环境）

修改 `gateways/openclaw/clawke/` 下的文件后，**生产部署时**执行以下操作：

1. **运行时逻辑**（`index.ts`、`gateway.ts` 等）：scp 到 OpenClaw 服务器即可生效
   ```bash
   scp gateways/openclaw/clawke/src/*.ts samy@192.168.0.7:~/.openclaw/extensions/clawke/src/
   scp gateways/openclaw/clawke/index.ts samy@192.168.0.7:~/.openclaw/extensions/clawke/
   ```
2. **Channel 能力声明**（`channel.ts` 中的 `blockStreaming` 等静态配置）：编译进了 `dist/thinking-*.js`，需要额外 sed 替换
   ```bash
   ssh samy@192.168.0.7 "cd /Users/samy/MyProject/openclaw && sed -i 's/旧值/新值/g' dist/thinking-*.js"
   ```
3. 部署完成后提醒用户**重启 OpenClaw**

## 术语统一

- **Clawke Server**：本地服务端（原名 Mini Server，已统一改名）
- **OpenClaw**：AI Agent 框架，通过渠道插件连接 Clawke Server
- **CUP**：Clawke UI Protocol，Server ↔ Client 的通信协议
- 函数名：`sendToClawkeServer()`（原 `sendToMiniServer`，已统一改名）

## 日志规范

- **日志统一使用英文**，不做国际化（日志是给开发者看的，不是用户）
- 格式：`[Tag] emoji message`，如 `[Clawke] ✅ AI connected: AgentName`
- Client 端使用 `debugPrint()` 和 `logNotifier.addLog()`
- Server 端使用 `console.log()` / `console.error()` / `console.warn()`

## CUP 协议概要

### 服务端 → 客户端（下发 UI 组件）

```json
{
  "role": "agent",
  "agent_id": "coder_01",
  "payload_type": "ui_component",
  "component": {
    "widget_name": "CodeEditorView",
    "props": { "language": "dart", "filename": "main.dart", "content": "..." },
    "actions": [
      { "action_id": "cmd_copy_local", "label": "复制代码", "type": "local" },
      { "action_id": "cmd_apply_file", "label": "写入本地", "type": "remote" }
    ]
  }
}
```

### 客户端 → 服务端（上报用户事件）

```json
{
  "protocol": "clawke_event_v1",
  "event_type": "user_action",
  "context": { "session_id": "sess_102", "message_id": "msg_99x" },
  "action": {
    "action_id": "cmd_apply_file",
    "trigger": "button_click",
    "data": { "filename": "main.dart", "content": "..." }
  }
}
```

## MVP 核心 Widget（必须实现）

| Widget                | 功能                                     |
| --------------------- | ---------------------------------------- |
| `MarkdownWidget`      | 流式打字机文本渲染，支持加粗、列表       |
| `CodeEditorWidget`    | 多语言语法高亮 + 文件名 + Action 操作区  |
| `UpgradePromptWidget` | 未知 Widget 的优雅降级兜底，**严禁闪退** |

## MVP 明确不做（Out of Scope）

- 真实大模型 API 接入（全部用 Mock 数据）
- 多智能体路由与 @ 提及机制
- 本地 SQLite 持久化
- 公网穿透与用户登录鉴权

## 自动化测试准则 (Testing Requirements)

你是一个遵循 TDD（测试驱动开发）的架构师。在全自动执行任务时，必须遵守以下测试持久化规范：

**测试资产沉淀**：严禁编写阅后即焚的临时测试脚本。所有测试用例必须以文件形式持久化保存在项目的标准测试目录下。
**Node.js 规范**：使用原生 `node:test` 和 `assert`。测试文件必须放在 `server/test/` 目录下，以 `.test.js` 结尾。执行命令：`node --test`。
**Flutter 规范**：使用 `flutter_test`。测试文件必须放在 `client/test/` 目录下，并以 `_test.dart` 结尾。执行命令：`flutter test`。
**强硬验收红线**：修改核心逻辑（如 CupParser 解析、Model 转换、状态流转）后，必须运行对应的测试。如果测试失败，**严禁进入下一个 Task**，必须就地修复代码直到测试 100% 通过。

### 🔴 测试数据库隔离红线

**严禁测试代码操作生产数据库 `server/data/clawke.db`。** 测试必须使用独立的内存数据库（`:memory:`），由 `db.js` 中 `process.env.NODE_TEST` 环境变量自动切换。

此规则的背景教训：
- `message-store.js` 的 `reset()` 函数会执行 `DELETE FROM messages` 清空消息表
- 如果测试直接使用生产 DB，每次 `beforeEach → reset()` 都会**永久删除用户的真实聊天记录**
- `globalSeq` 是全局递增序列号，客户端持久化了 `last_seq`。一旦 `globalSeq` 被重置或回退，客户端 sync 时 `last_seq > currentSeq`，会永久丢失消息同步能力
- **绝对不能在 `reset()` 中重置 `globalSeq`**，详见 `message-store.js` 中的 ⚠️ 注释
- 测试中的 seq 断言必须使用**相对值**（如 `r2.seq === r1.seq + 1`），不能使用绝对值（如 `seq === 1`）

## MVP 验收标准

1. **零卡顿**：流式文本 + 大代码块插入时，Flutter UI 线程不掉帧
2. **协议健壮**：特殊字符/超长文本不崩溃；未知 Widget 类型触发优雅降级
3. **闭环延迟**：点击按钮到 Server 打印日志，局域网内 < 20ms

## 开发原则

- **交互语言**：所有交互对话必须使用**中文**。
- **代码注释双语**：代码中的注释必须同时使用**中文和英文**两种语言说明。格式：`// 中文说明 — English description`
- **Local-First**：Clawke Server 持有 API Key，客户端零业务逻辑
- **聊天渲染无 WebView**：聊天消息流、Markdown、代码高亮、Thinking Block 等核心聊天 UI 均为 Flutter 原生渲染，保证流式输出和高频滚动的性能。**例外：AI 生成的 VPP（虚拟应用）使用沙箱化 WebView 渲染**（AI 写标准 HTML/CSS/JS，在安全沙箱中运行）。详见 `docs/vpp/architecture.md`
- **安全沙箱**：Server 对客户端上报的文件路径严格校验，防止 `../../` 路径注入。vApp WebView 沙箱：CSP 策略限制外部请求、域名白名单、禁止本地文件访问、屏蔽危险 API
- **DRY / YAGNI**：不提前设计，最小可验证为准。先用最简方案跑通功能，遇到真实性能瓶颈再优化。例如：Drift `.watch()` 优先于手动 EventBus，移动端真正出现性能问题时再局部替换
- **公共方法提取（DRY 准则）**：在多个地方涉及相同的具体业务流（代码处理逻辑一样）时，**必须第一时间提取为公共辅助方法**，坚决避免复制粘贴式编程。这是为了防止在后续多次迭代、修改 Bug 时，因遗漏某个重复代码块而引发回归问题。
- **验证优先**：修改代码后，AI 必须先自行通过日志、源码审查或 Mock 测试确认功能正确，再交给用户验收。用户是最终验收者，不是测试员。严禁未经验证就让用户反复测试
- **文档同步**：执行有设计文档/计划文档的任务时，完成一个子任务后必须立即更新文档中该任务的状态（如 `[ ]` → `[x]`），不要等到全部完成才批量更新
- **🔴 线上环境红线**：**严禁直接 SSH 到线上生产环境（3.0.151.65 等远程服务器）执行任何操作**。必须将需要执行的命令和配置内容提供给用户，由用户确认后手动执行。SCP 上传文件可以执行，但 SSH 远程执行命令（创建文件、修改配置、重启服务等）必须经用户明确授权。此规则无例外。
- **🔴 生产数据红线**：**严禁测试代码操作 `server/data/clawke.db` 生产数据库**。测试必须通过 `:memory:` 内存数据库隔离。修改 `reset()` 等数据清理函数时，严禁重置 `globalSeq`（客户端依赖此值做增量同步）。详见「自动化测试准则」章节。

## 字体规范

- **基准字体：`bodyMedium` = 16sp**，所有其他文本样式基于此按比例放大/缩小
- **新代码禁止硬编码 `fontSize`**，必须通过 `Theme.of(context).textTheme.bodyMedium` 等 textTheme 引用
- 现有硬编码字号逐步迁移，修改前需用户审核
- 用户可通过设置调整 `fontScale`（70%–130%），所有 textTheme 字号自动乘以该系数
- 详细字号对照表见 `docs/font-spec.md`

## UI 调整工作流

使用 UI-UX-Pro-Max skill 进行 UI 调整时，必须遵循**预览优先**流程：

1. **先更新 `docs/ui-preview.html`**：用 HTML/CSS 模拟目标效果
2. **等待用户确认**：用户在浏览器中预览并确认效果
3. **再实施 Flutter 代码修改**：确认通过后才修改 `client/` 下的 Dart 代码

## 文档规范

- **图解优先 (Diagrams as Code)**：在编写架构设计、业务流程、类图或状态流转等文档时，**强烈建议使用 Mermaid**。这不仅能让文档更直观专业，而且与 Markdown 完美结合，易于追踪版本间的修改。
  - 支持的图表类型包括但不限于：流程图 (`graph/flowchart`)、时序图 (`sequenceDiagram`)、类图 (`classDiagram`)、状态图 (`stateDiagram`) 等。
  - 需要确保你的编辑器（如 VS Code）已安装 Mermaid 渲染插件，以便在预览中正确显示。

## IM 参考源码经验总结

`../clawke_extends/IM/` 目录下收录了多个开源 IM 的 Flutter 实现（已移至项目外），遇到疑难杂症时应优先参考这些源码。

### 关键参考项目

| 项目             | 路径                                    | 特点                                                         |
| ---------------- | --------------------------------------- | ------------------------------------------------------------ |
| Mixin Messenger  | `../clawke_extends/IM/mixin/`           | 最完整的 Flutter IM，消息处理、DB 设计、排序逻辑最具参考价值 |
| FluffyChat       | `../clawke_extends/IM/fluffychat/`      | Matrix 协议客户端，UI 组件和聊天交互参考                     |
| Wildfire Flutter | `../clawke_extends/IM/wildfire-flutter/` | 轻量 IM，架构简洁清晰                                        |

### 从 Mixin 学到的消息处理模式

1. **`insertOnConflictUpdate`**：消息写入 DB 用 upsert（主键冲突时更新），天然防重复。Clawke 已采用此模式
2. **排序兜底**：Mixin 用 `ORDER BY createdAt DESC, rowId DESC`。`rowId` 是 SQLite 自增的，作为同时间戳的确定性 tiebreaker。Clawke 用 `seq DESC` 作 tiebreaker
3. **DataBaseEventBus**：Mixin 用独立的事件总线通知 UI 消息变更，不依赖 Drift `.watch()` 的自动触发。Clawke 目前用 Drift watch，简单但可能有延迟
4. **消息 ID 一致性**：IM 的消息从发送到确认全程使用同一个 ID（UUID），不会中途换 ID。Clawke 的 abort 场景存在流式 ID（`msg_xxx`）与服务端 ID（`smsg_xxx`）不一致的问题，需统一

### 排查问题的最佳实践

- 遇到消息重复/丢失/乱序时，先 `grep` 参考 IM 源码中相同场景的实现
- 重点关注 `message_dao.dart`（DB 操作）、`database_event_bus.dart`（事件通知）、消息状态机（sending → sent → delivered → read）

## gstack

### 🔴 浏览器工具规则

**所有网页浏览操作必须使用 gstack 的 `/browse` 技能，永远不要使用 `mcp__claude-in-chrome__*` 工具。** 此规则无例外。

### 可用技能列表

| 技能 | 说明 |
| --- | --- |
| `/office-hours` | YC Office Hours — 创业模式或 Builder 模式的头脑风暴 |
| `/plan-ceo-review` | CEO/创始人视角的计划评审，挑战前提、扩展范围 |
| `/plan-eng-review` | 工程经理视角的计划评审，锁定架构和执行方案 |
| `/plan-design-review` | 设计师视角的计划评审，评估 UI/UX 维度 |
| `/design-consultation` | 设计咨询，创建完整设计系统和 DESIGN.md |
| `/design-shotgun` | 生成多个 AI 设计变体进行比较和迭代 |
| `/design-html` | 将设计稿转化为生产级 HTML/CSS |
| `/review` | PR 预着陆代码审查 |
| `/ship` | 完整发布流程：测试、版本号、CHANGELOG、PR |
| `/land-and-deploy` | 合并 PR、等待 CI、部署、验证生产健康 |
| `/canary` | 部署后金丝雀监控 |
| `/benchmark` | 性能基准检测和回归分析 |
| `/browse` | 快速无头浏览器，用于 QA 测试和网站验证 |
| `/connect-chrome` | 启动真实 Chrome 并通过 Side Panel 控制 |
| `/qa` | 系统化 QA 测试并修复发现的 Bug |
| `/qa-only` | 仅报告模式的 QA 测试，不修复 |
| `/design-review` | 设计师视角的视觉 QA 审查并修复问题 |
| `/setup-browser-cookies` | 导入浏览器 Cookie 用于认证测试 |
| `/setup-deploy` | 配置部署设置 |
| `/retro` | 每周工程回顾，分析提交历史和代码质量 |
| `/investigate` | 系统化调试，四阶段根因分析 |
| `/document-release` | 发布后文档更新和同步 |
| `/codex` | OpenAI Codex CLI 集成：审查、挑战、咨询 |
| `/cso` | 首席安全官模式，全方位安全审计 |
| `/autoplan` | 自动化全流程评审（CEO + 设计 + 工程） |
| `/careful` | 破坏性命令安全防护 |
| `/freeze` | 限制文件编辑范围到指定目录 |
| `/guard` | 完整安全模式：命令防护 + 目录锁定 |
| `/unfreeze` | 解除 freeze 限制 |
| `/gstack-upgrade` | 升级 gstack 到最新版本 |
| `/learn` | 管理项目学习记录 |

## Skill routing

When the user's request matches an available skill, ALWAYS invoke it using the Skill
tool as your FIRST action. Do NOT answer directly, do NOT use other tools first.
The skill has specialized workflows that produce better results than ad-hoc answers.

Key routing rules:
- Product ideas, "is this worth building", brainstorming → invoke office-hours
- Bugs, errors, "why is this broken", 500 errors → invoke investigate
- Ship, deploy, push, create PR → invoke ship
- QA, test the site, find bugs → invoke qa
- Code review, check my diff → invoke review
- Update docs after shipping → invoke document-release
- Weekly retro → invoke retro
- Design system, brand → invoke design-consultation
- Visual audit, design polish → invoke design-review
- Architecture review → invoke plan-eng-review
- Save progress, checkpoint, resume → invoke checkpoint
- Code quality, health check → invoke health
