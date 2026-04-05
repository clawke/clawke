[English](README.md)
[中文文档](README_zh.md)

# Clawke

A secure, edge-cloud collaborative AI workspace. Clawke connects your local server to AI providers through the CUP (Clawke Unified Protocol) and delivers a rich native client experience via SDUI (Server-Driven UI).

## Architecture

```
┌─────────────┐        CUP/WS        ┌──────────────┐       WS        ┌──────────────┐
│ Flutter App  │ ◄──────────────────► │ Clawke Server│ ◄─────────────► │   OpenClaw    │
│  (iOS/Mac)   │    Downstream        │   (Node.js)  │    Upstream     │   Gateway     │
└─────────────┘                       └──────┬───────┘                 └──────┬───────┘
                                              │                               │
                                              │        WS              ┌──────▼───────┐
                                              └──────────────────────► │  AI Provider  │
                                                                       │ (Claude, etc) │
                                              ┌──────────────┐         └──────▲───────┘
                                              │   nanobot     │               │
                                              │   Gateway     │ ──────────────┘
                                              └──────────────┘
```

## Features

- **CUP Protocol** — Streaming AI responses with thinking blocks, tool calls, and usage tracking
- **SDUI** — Server-driven UI: dashboards, forms, dialogs rendered from server instructions
- **Multi-gateway** — Pluggable AI backends: [OpenClaw](https://github.com/nicepkg/openclaw) and [nanobot](https://github.com/swuecho/nanobot) supported
- **Media** — Image/PDF/text file upload and inline rendering
- **Relay** — Built-in tunnel for remote access without port forwarding

## Quick Start

### Prerequisites

- [Node.js](https://nodejs.org/) >= 18
- [Flutter](https://flutter.dev/) >= 3.x (for client)

### Start Server

```bash
cd server
npm install                           # Installs dependencies + compiles TypeScript
npx clawke openclaw-gateway install    # Install OpenClaw gateway plugin
# or: npx clawke nanobot-gateway install  # Install nanobot gateway
npx clawke server start                # Start Clawke Server
```

The server will:

1. Copy config template to `~/.clawke/clawke.json` (first run)
2. Initialize SQLite database at `~/.clawke/data/clawke.db`
3. Start WebSocket server on port 8765 (client) and 8766 (upstream)
4. Start HTTP/media server on port 8781

### Start Client

```bash
cd client
flutter pub get
flutter run              # iOS Simulator / macOS / Android
```

## Project Structure

```
clawke/
├── client/              # Flutter app (iOS, macOS, Android)
├── server/              # Clawke Server (TypeScript/Node.js)
│   ├── src/             # Source code
│   ├── config/          # Config templates
│   └── test/            # Tests (42 cases)
├── gateways/            # Gateway plugins
│   ├── openclaw/clawke/ # OpenClaw gateway
│   └── nanobot/clawke/  # nanobot gateway
└── relay-server/        # Relay server config
```

> 📖 For advanced configuration, see [CONFIGURATION.md](docs/CONFIGURATION.md).  
> 🔌 To build your own gateway, see [GATEWAY_INTEGRATION.md](docs/GATEWAY_INTEGRATION.md).

## Contributing

1. Fork this repository
2. Create your feature branch (`git checkout -b feature/amazing-feature`)
3. Commit changes (`git commit -m 'Add amazing feature'`)
4. Push to branch (`git push origin feature/amazing-feature`)
5. Open a Pull Request

## License

[MIT](LICENSE)
