[English](README.md)

# Clawke

安全的边缘-云端协作 AI 工作空间。Clawke 通过 CUP 协议（Clawke Unified Protocol）连接本地服务器与 AI 提供商，并通过 SDUI（Server-Driven UI）提供丰富的原生客户端体验。

## 架构

```
┌─────────────┐        CUP/WS        ┌──────────────┐       WS        ┌──────────────┐
│ Flutter App  │ ◄──────────────────► │ Clawke Server│ ◄─────────────► │   OpenClaw    │
│  (iOS/Mac)   │    下行链路           │   (Node.js)  │    上行链路     │   Gateway     │
└─────────────┘                       └──────────────┘                 └──────┬───────┘
                                                                              │
                                                                       ┌──────▼───────┐
                                                                       │  AI 提供商    │
                                                                       │ (Claude 等)   │
                                                                       └──────────────┘
```

## 功能特性

- **CUP 协议** — AI 流式响应，支持思考块、工具调用和用量统计
- **SDUI** — 服务端驱动 UI：仪表盘、表单、对话框由服务端指令渲染
- **多模型** — 通过 OpenClaw 网关支持任意 AI 提供商
- **媒体** — 图片/PDF/文本文件上传与内联渲染
- **Relay** — 内置隧道，无需端口转发即可远程访问

## 快速开始

### 前置条件

- [Node.js](https://nodejs.org/) >= 18
- [Flutter](https://flutter.dev/) >= 3.x（客户端）

### 启动服务端

```bash
cd server
npm install              # 安装依赖 + 编译 TypeScript
npx clawke gateway install   # 安装 Gateway 插件到 OpenClaw
npx clawke server start      # 启动 Clawke 服务
```

服务端会：
1. 首次运行时将配置模板拷贝到 `~/.clawke/clawke.json`
2. 在 `~/.clawke/data/clawke.db` 初始化 SQLite 数据库
3. 启动 WebSocket 服务（8765 端口：客户端，8766 端口：上行）
4. 启动 HTTP/媒体服务（8781 端口）

### 启动客户端

```bash
cd client
flutter pub get
flutter run              # iOS 模拟器 / macOS / Android
```

## 项目结构

```
clawke/
├── client/              # Flutter 客户端（iOS、macOS、Android）
├── server/              # Clawke 服务端（TypeScript/Node.js）
│   ├── src/             # 源码
│   ├── config/          # 配置模板
│   └── test/            # 测试（42 个用例）
├── gateways/            # OpenClaw Gateway 插件
│   └── openclaw/clawke/
└── relay-server/        # Relay 服务配置
```

## 贡献

1. Fork 本仓库
2. 创建特性分支 (`git checkout -b feature/amazing-feature`)
3. 提交更改 (`git commit -m 'Add amazing feature'`)
4. 推送分支 (`git push origin feature/amazing-feature`)
5. 创建 Pull Request

## 许可证

[MIT](LICENSE)
