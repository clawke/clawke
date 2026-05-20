# Server 模块开发规则

适用于 `server/**` 下的 Clawke Server Node.js 代码。开始修改 `server/**` 前，先读取根目录 `CLAUDE.md`，再读取本文件。

## 本地开发

- 开发阶段只在本机运行 Server，严禁部署到 `192.168.0.7` 或其他远程生产环境
- 常用启动命令：`cd server && npm run dev`
- Server 端日志使用 `console.log()` / `console.error()` / `console.warn()`，日志内容统一英文

## 测试规范

- Node.js 测试使用原生 `node:test` 和 `assert`
- 测试文件必须放在 `server/test/` 目录下，以 `.test.js` 结尾
- 修改核心逻辑、协议转换、状态流转、数据库读写后必须运行对应测试；常用命令：`node --test`
- 严禁编写阅后即焚的临时测试脚本；测试用例必须持久化到标准测试目录

## 数据库红线

- 严禁测试代码操作生产数据库 `server/data/clawke.db`
- 测试必须通过 `process.env.NODE_TEST` 使用独立内存数据库 `:memory:`
- 修改 `reset()` 等清理逻辑时，严禁重置 `globalSeq`，客户端依赖该值做增量同步
- seq 断言必须使用相对值，例如 `r2.seq === r1.seq + 1`，不能断言绝对值如 `seq === 1`

## 协议边界

- Server 负责本地协议服务和 Gateway 管理边界，不吸收上游 Agent 私有协议
- Agent 特定逻辑必须放在 `gateways/**`，Server 和 Client 永远不要绑定 OpenClaw、Hermes 等特定 Agent 的内部格式
- 遇到 Gateway 代码没生效时，优先查根因、重编、重启，禁止在 Server 层写 hack 绕过
- Server 不负责 UI 国际化。新增面向客户端展示的状态必须优先发送稳定 `status` / `code` / 结构化字段，由 Client 映射 `AppLocalizations`
- 严禁新增中文硬编码作为 UI 展示文案；确需传递错误详情时，传技术错误或结构化错误码，Client 决定最终用户可见文案
