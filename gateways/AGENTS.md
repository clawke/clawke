# Gateways 模块开发规则

适用于 `gateways/**` 下的 Agent Gateway / Channel Plugin 代码。开始修改 `gateways/**` 前，先读取根目录 `CLAUDE.md`，再读取本文件。

## 架构边界

- Gateway 层是唯一允许理解上游 Agent 私有协议的地方
- Gateway 输出给 Clawke Server 的内容必须标准化为 CUP / Clawke 协议消息，不得把 Agent 私有格式传导到 Server 或 Client
- 新增能力先判断“Agent 特定”还是“通用交互”：Agent 特定逻辑放 Gateway，通用交互抽到 CUP 协议
- 严禁在 Gateway 层解析非结构化文本来驱动关键行为，必须优先使用上游 Agent 提供的结构化 API、事件或 Hook
- Gateway 不负责 UI 国际化。面向 Client 的用户可见状态必须发送稳定 `status` / `code` / 结构化字段，由 Client 映射本地化文案
- 严禁新增中文硬编码作为最终 UI 展示文案；错误详情可以传原始技术信息，但不要把中文 `message` 当作客户端 UI 文案契约

## OpenClaw 插件规则

- Clawke 是 OpenClaw 的 Channel Plugin，代码在 `gateways/openclaw/clawke/`
- 严禁修改 `../clawke_extends/openclaw/src/` 核心代码来实现 Clawke 功能
- 优先使用 OpenClaw Plugin API，例如 hooks、registerTool、registerCommand
- 插件运行在 OpenClaw 进程内，`index.ts` 的 `register(api)` 可以使用完整 Plugin API

## 开发与部署

- 开发阶段 Gateway 必须本机运行，严禁部署到 `192.168.0.7`
- `../clawke_extends/openclaw/` 只是本地源码副本，方便查接口，不用于实际运行
- 只有发布 / 生产部署时才 scp 到 `192.168.0.7`
- 生产部署后只提醒用户重启 OpenClaw；不要未经授权 SSH 执行修改、配置变更或重启

## TypeScript 编码规范

适用于 `gateways/openclaw/clawke/src/**`。

- 使用 ESM `import`，禁止 `require()`
- Node.js 内置模块使用 `node:` 前缀，例如 `node:fs`、`node:path`、`node:os`
- 日志统一使用 `ctx.log?.info/error/warn`，禁止 `console.log/error`
- `catch` 中必须记录日志，禁止空 `catch {}`
- 模块级变量仅用于生命周期级状态；每次请求入口处必须重置请求级状态

## 测试规范

- Gateway 测试必须持久化到对应 gateway 的测试目录或同目录 `.test.ts` / `.test.py`
- 修改协议转换、安装流程、技能适配、连接状态处理后必须运行对应测试
- OpenClaw Gateway TypeScript 测试优先使用仓库既有 `node --test` 流程
