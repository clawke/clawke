# 版本演进 (Changelog)

> Clawke 项目的完整版本演进历史。README 仅展示最近一个月的更新。

<!-- CHANGELOG_START -->

## v1.1.31 (2026-05-12)

**[新功能]** Gateway 使用情况可视化与更新自动化。
- 新增 Gateway 使用情况面板，便于查看已连接 Gateway 的活动状态。
- 新增 Gateway 更新后的自动重启处理，并补充本地 Server 连接提示。

**[问题修复]** OpenClaw Gateway 配置与运行指引。
- 修复 OpenClaw Gateway 更新配置合并问题。
- 优化 GatewayClient 错误指引和 Server PID 生命周期保护。
- 让发布版本校验可配置，并改进安装脚本的 TTY 处理。

## v1.1.30 (2026-05-11)

**[问题修复]** OpenClaw Gateway 与 UI 回归稳定性。
- 稳定 OpenClaw Gateway 集成路径，确保已准备的 Gateway 修改能可靠进入发布验证。
- 加固 UI E2E 回归套件，减少发布前校验中的不稳定失败。

**[功能优化]** Linux 桌面端安装与打包体验。
- 新增 Linux 桌面端注册，并支持通过 `sh` 执行桌面安装脚本。
- 修复 Linux 图标和字体 fallback 行为，并优化桌面端应用图标与标题元数据。
- 改进 Gateway 安装流程，让安装后的下一步更清晰。

## v1.1.29 (2026-05-10)

**[问题修复]** macOS App Store 登录与审核准备。
- App Store 版禁用应用内更新检查和更新弹窗，确保更新完全由 Mac App Store 管理。
- 修复 macOS App Store 签名和 entitlement 校验，覆盖 Apple 登录、production APNs 和 Google 登录 Keychain 访问。
- 加固 Mac App Store 包签名流程，上传前拦截 quarantine 扩展属性和审核不允许的 entitlements。

**[功能优化]** 发布体验与运行路径安全。
- 优化欢迎页布局，提升首次启动体验。
- 移动端和无法定位仓库根目录时忽略 debug runtime directory 覆盖，避免错误路径影响运行。

## v1.1.27 (2026-05-09)

**[问题修复]** macOS release 登录与桌面端 OAuth 打包。
- macOS release 版保持原生 GoogleSignIn 流程，并校验必需的 Keychain access groups。
- macOS release 版默认隐藏 Apple 登录，直到 provisioning profile 真正启用 Sign in with Apple entitlement，避免显示不可用按钮。

**[功能优化]** 桌面端发布覆盖与图标资源。
- 优化桌面端 OAuth 回调流程，并刷新 Windows/Linux 桌面端图标。
- 将 GitHub Actions 更新到当前 Node runtime，并新增内部桌面端发布构建覆盖。

## v1.1.26 (2026-05-09)

**[问题修复]** macOS release 签名与 Windows 桌面端 Google 登录。
- macOS release 签名改为先显式签名嵌套 framework，再签名 app bundle，符合当前 Apple 签名建议和 macOS 26 验证规则。
- macOS release 构建和发布后回验切换到 macOS 26 runner，确保发布 DMG 在用户报错的同一系统大版本上验证。
- Windows/Linux 桌面端新增系统浏览器 loopback + PKCE 的 Google OAuth 流程，通过 `GOOGLE_DESKTOP_CLIENT_ID` 控制开启。
- Windows release 构建在配置 `GOOGLE_DESKTOP_CLIENT_ID` 时启用桌面端 Google OAuth；未配置时仍可完成发布验证，登录入口保持禁用。

## v1.1.23 (2026-05-09)

**[问题修复]** Windows 发布包启动与桌面端登录体验。
- Windows release zip 现在会随包携带 Visual C++ runtime DLL，即使系统 runtime 缺失或损坏也能启动 Clawke。
- 新增发布流程校验，确保 Windows 包包含 `msvcp140.dll`、`vcruntime140.dll` 和 `vcruntime140_1.dll`。
- Windows 和 Linux 桌面端会隐藏暂不支持的 Google 登录入口，避免触发桌面端 `MissingPluginException`。

## v1.1.22 (2026-05-09)

**[问题修复]** Android 发布签名与 Google 登录。
- 恢复 GitHub 发布流程中的固定 Android release 签名，确保官方 APK 使用预期的 release 证书。
- 新增证书指纹校验和已发布 APK 回验，防止再次发布 debug 签名的 Android release 包。

## v1.1.21 (2026-05-03)

**[功能优化]** 发布与运行路径稳定性增强。
- 稳定本地 App 运行和任务 UI E2E 使用的运行路径处理。
- 加固任务 E2E 初始化流程，减少发布验证中的环境路径差异问题。

**[架构调整]** Gateway listener 命名统一与公开文档清理。
- 将 runtime 边界里的 upstream listener 概念统一改名为 gateway listener。
- 将内部规划文档移出公开文档目录，让公开文档聚焦产品和接入资料。

## v1.1.20 (2026-05-02)

**[新功能]** Hermes 定时任务结果同步与任务投递追踪。
- 新增 Hermes cron 输出同步，定时任务结果可以投递回目标 Clawke 会话。
- 新增持久化投递状态、重试处理和任务投递目标校验。
- 新增客户端任务投递校验，并扩展任务管理相关测试。

**[功能优化]** 任务管理和 Gateway 诊断增强。
- 优化任务管理页面的投递状态展示和校验反馈。
- 新增 Gateway 告警能力，用于向客户端暴露任务投递问题。
- 新增运行目录诊断，方便排查本地客户端日志和数据库路径问题。

**[功能优化]** Hermes 媒体路由与工作目录隔离。
- 优化 Hermes 图片路由，可根据 provider/model 能力选择原生多模态或视觉增强。
- 新增 Hermes 会话级工作目录处理，避免修改全局进程状态。
- 新增 Hermes channel 路由、工作目录隔离、cron sync 和 task adapter 回归测试。

## v1.1.17 (2026-04-29)

**[新功能]** 新增 Clawke Doctor 命令。
- 新增 `clawke doctor`，用于检查项目文件、运行状态、本地配置和已配置的 Gateway 实例。
- 优化 Gateway 诊断文案，区分 OpenClaw 内嵌管理和 Clawke 本地管理两种模式。

**[功能优化]** 强化多 Agent 在线管理定位。
- README 重点说明 Clawke 支持 OpenClaw、Hermes、Nanobot 等多 Agent 在线管理。
- 明确桌面端和移动端都可以随时管理 Agent。

**[问题修复]** 修复流式回复断线后的界面卡住问题。
- 修复客户端重连后可能残留 `Thinking`、工具执行中状态和停止按钮的问题。
- 当客户端断线漏收 `text_done` 或 `tool_call_done` 时，`sync_response` 现在会补齐完成事件的清理效果。
- 新增 provider 单测和 UI E2E 持久化用例，覆盖该断线恢复场景。

## v1.1.15 (2026-04-29)

**[新功能]** 新增 Hermes 网关支持。
- Clawke 现在可以通过 Hermes Gateway 连接 Hermes 后端会话。
- 支持通过网关发现 Hermes 的模型和技能。

**[新功能]** 原生技能中心与任务管理页面。
- 技能中心支持托管技能的列表、搜索、新建、编辑、禁用和删除。
- 任务管理支持查看、触发和管理 Agent 侧任务，Clawke 仍保持控制平面定位，不接管任务执行。

**[功能优化]** 基于网关的资源发现与翻译刷新。
- 模型和技能元数据改为通过 Gateway API 获取。
- 新增 Gateway System Session，用于后台翻译和刷新流程，避免污染用户会话。
- 增加批量翻译、缓存复用和关键日志，方便线上问题一次性定位。

**[问题修复]** OpenClaw 模型路由与启动配置修复。
- 修复 OpenClaw 模型切换逻辑，使其与 dispatcher API 对齐。
- 修复网关模型元数据 fallback 和安装时的 channel 配置写入。
- 加固没有启动命令的外部网关处理，避免启动流程异常。

**[架构调整]** 扩展网关测试与发布覆盖。
- 新增 OpenClaw、Hermes、nanobot、技能管理、任务管理和 Gateway System Request 回归测试。
- 新增 UI E2E 测试框架，覆盖会话设置、技能、任务、审批、选择和流式回复等主路径。

## v1.1.5 (2026-04-18)

**[新功能]** 一键安装脚本与统一的 CLI 管理命令。
- 发布了一键安装脚本（通过 `curl` 即可快速部署服务端）。
- 新增 `npx clawke server <start|stop|restart|status>` 等服务控制台命令，方便管理后台进程。
- 移动端登录/注册页面现已支持密码管理器自动填充（Auto-fill）。
- 新增中英文双语 Changelog 自动生成系统。

**[新功能]** AI 「正在输入」状态指示器。
- 对话界面新增精细的 AI 回复状态展示（正在思考或接收请求时显示带有文字的动画指示器）。

**[功能优化]** 网关底层通讯管道优化。
- 升级了网关协议层，提供完整的下发链路追踪与消息流（Compaction）压缩机制。
- 统一网关日志规范，并对网关层全局状态管理进行了全量文档化。
- TypeScript 编码规范增强与 ESM 导入支持。

**[问题修复]** 中止生成（Abort）全链路彻底修复。
- 全面重构了中止功能，保证客户端、服务端和网关三层精准打断生成。
- 修复了因为中止生成导致 AI 在后续对话中出现“重复回答被中止的问题”的幻觉 Bug。
- 在用户触发中止时会一并清除队列中排队的消息，防止后续被错误自动执行。
- 修复了 Abort 转发时携带的 Account ID 验证错误。

**[问题修复]** 并发消息与底层稳定性修复。
- 解决了在消息并发请求时，偶发的导致大模型“无响应”或任务堵塞的问题。
- 修复了连续生成中的“消息重复” Bug（通过引入 `disableBlockStreaming` 等底座管控能力）。
- 修复了在历史消息增量同步（Sync）过程中请求了越界序列号导致失败的同步错误。

## v1.1.3 (2026-04-15)

**[新功能]** 多会话管理：支持为每个会话独立配置 AI 网关和模型参数。
- 每个会话可独立设置 AI Gateway、模型、系统提示词和温度参数
- 新增会话设置面板，从聊天界面即可进入
- 服务端新增会话配置存储和 REST API（`/api/conversations/:id/config`）
- Gateway 权威查询：可用模型列表直接从对接的 AI 后端实时获取

**[新功能]** 新建会话时的 Gateway 选择器。
- 卡片式 UI 设计，引导用户选择 AI 后端
- 显示已连接的 Account ID 及视觉指示器

**[功能优化]** 全面国际化（i18n）覆盖所有页面。
- 设置、修改密码、边缘页面完整中英文本地化
- 全局 AppBar 标题居中对齐，统一字号（18sp）

**[功能优化]** 桌面端 UI 打磨。
- 会话列表头部对齐与间距调整
- 全局统一 AppBar 操作按钮边距
- 会话设置底部面板，支持全屏系统提示词编辑

**[问题修复]** 修复跨会话消息泄漏 — Thinking 块和消息现在正确按 `conversation_id` 路由。

**[问题修复]** 修复启动时端口冲突检测，防止多个 frpc 实例循环重启。

**[问题修复]** 修复 Android 11+ 无法打开隐私政策和用户协议链接的问题。

**[架构调整]** 会话自动创建移至服务端 — 首次收到新 `account_id` 时由服务端自动创建会话，消除客户端竞态条件。

<!-- CHANGELOG_END -->
