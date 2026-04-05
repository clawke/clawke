# Gateway Integration Guide

This document describes how to build a **Gateway Plugin** that connects Clawke Server to any AI backend. The reference implementation is the OpenClaw gateway in `gateways/openclaw/clawke/`.

## Architecture Overview

```
┌──────────┐   CUP/WS (8765)   ┌──────────────┐   WS (8766)   ┌────────────────┐
│  Client  │ ◄───────────────► │ Clawke Server │ ◄────────────► │ Gateway Plugin │
│ (Flutter) │   downstream      │   (Node.js)   │   upstream     │  (your code)   │
└──────────┘                    └──────────────┘                 └───────┬────────┘
                                                                         │
                                                                  ┌──────▼──────┐
                                                                  │ AI Provider │
                                                                  │ (LLM API)   │
                                                                  └─────────────┘
```

The Gateway Plugin connects to Clawke Server's **upstream WebSocket port** (default 8766) and acts as a bidirectional bridge:
- **Inbound**: Receives user messages from Clawke Server, forwards them to the AI provider
- **Outbound**: Streams AI responses back to Clawke Server using the standard message protocol

## Connection Lifecycle

### 1. Establish WebSocket Connection

Connect to `ws://127.0.0.1:8766` (configurable via `server.upstreamPort` in `~/.clawke/clawke.json`).

### 2. Handshake (identify)

Immediately after connection, send an `identify` message:

```json
{
  "type": "identify",
  "accountId": "your-account-id"
}
```

The `accountId` is used by Clawke Server to route messages. Each account gets its own WebSocket slot; reconnecting with the same `accountId` replaces the previous connection.

### 3. Receive User Messages

Clawke Server sends user messages as JSON:

```json
{
  "type": "chat",
  "text": "Hello, explain quantum computing",
  "conversation_id": "conv_abc123",
  "client_msg_id": "msg_1234567890",
  "content_type": "text",
  "media": {
    "paths": ["/absolute/path/to/file.jpg"],
    "relativeUrls": ["/api/media/1234_abcd.jpg"],
    "httpBase": "http://127.0.0.1:8781",
    "types": ["image/jpeg"],
    "names": ["photo.jpg"]
  }
}
```

| Field | Type | Required | Description |
|-------|------|----------|-------------|
| `type` | string | ✅ | Always `"chat"` |
| `text` | string | ✅ | User message text |
| `conversation_id` | string | ❌ | Conversation identifier |
| `client_msg_id` | string | ❌ | Unique message ID from the client |
| `content_type` | string | ❌ | `"text"` or `"media"` |
| `media.paths` | string[] | ❌ | Absolute file paths (when server and gateway share filesystem) |
| `media.relativeUrls` | string[] | ❌ | Relative URLs for HTTP download fallback |
| `media.httpBase` | string | ❌ | Base URL for constructing full media download URLs |
| `media.types` | string[] | ❌ | MIME types of attached files |
| `media.names` | string[] | ❌ | Original filenames |

**Media Resolution Strategy:**
1. Try reading from `media.paths` directly (works when gateway and server are on the same machine)
2. If local files not found, download via HTTP: `${media.httpBase}${media.relativeUrls[i]}`

### 4. Abort Requests

Clawke Server may send abort requests when the user cancels:

```json
{
  "type": "abort",
  "conversation_id": "conv_abc123"
}
```

Your gateway should stop generating and clean up any in-progress AI calls.

## Response Protocol

Send AI responses back as JSON messages over the same WebSocket. All messages must include `account_id`.

### Text Streaming (Preferred)

Stream text responses in real-time for the best user experience.

#### `agent_text_delta` — Incremental text chunk

```json
{
  "type": "agent_text_delta",
  "message_id": "reply_1234567890",
  "delta": "Quantum computing is",
  "account_id": "your-account-id"
}
```

#### `agent_text_done` — End of text stream

```json
{
  "type": "agent_text_done",
  "message_id": "reply_1234567890",
  "fullText": "Quantum computing is a type of computation...",
  "account_id": "your-account-id",
  "model": "claude-sonnet-4-20250514",
  "provider": "anthropic",
  "usage": {
    "input": 150,
    "output": 320,
    "cacheRead": 0,
    "cacheWrite": 0,
    "total": 470
  }
}
```

### Non-Streaming Text (Fallback)

If your AI provider doesn't support streaming, send the complete response at once:

#### `agent_text` — Complete text response

```json
{
  "type": "agent_text",
  "message_id": "reply_1234567890",
  "text": "Quantum computing is a type of computation...",
  "account_id": "your-account-id",
  "model": "gpt-4",
  "provider": "openai",
  "usage": { "input": 150, "output": 320, "total": 470 }
}
```

### Thinking / Reasoning Blocks

If your AI provider supports extended thinking (e.g., Claude's thinking blocks):

#### `agent_thinking_delta` — Thinking stream chunk

```json
{
  "type": "agent_thinking_delta",
  "message_id": "think_1234567890",
  "delta": "Let me analyze this step by step...",
  "account_id": "your-account-id"
}
```

#### `agent_thinking_done` — End of thinking stream

```json
{
  "type": "agent_thinking_done",
  "message_id": "think_1234567890",
  "account_id": "your-account-id"
}
```

> **Note:** Thinking deltas should be sent **before** text deltas. The sequence is: `agent_thinking_delta` → `agent_thinking_done` → `agent_text_delta` → `agent_text_done`.

### Tool Calls

Report when the AI invokes tools:

#### `agent_tool_call` — Tool invocation started

```json
{
  "type": "agent_tool_call",
  "message_id": "reply_1234567890",
  "toolCallId": "reply_1234567890_tool_1",
  "toolName": "web_search",
  "account_id": "your-account-id"
}
```

#### `agent_tool_result` — Tool execution completed

```json
{
  "type": "agent_tool_result",
  "message_id": "reply_1234567890",
  "toolCallId": "reply_1234567890_tool_1",
  "toolName": "web_search",
  "durationMs": 1200,
  "account_id": "your-account-id"
}
```

### Media Responses

When the AI generates images or files:

#### `agent_media` — Media attachment

```json
{
  "type": "agent_media",
  "message_id": "reply_1234567890",
  "mediaUrl": "https://example.com/generated-image.png",
  "account_id": "your-account-id"
}
```

### Usage Statistics (Optional)

Report token usage per turn for dashboard display:

#### `agent_turn_stats` — Turn-level summary

```json
{
  "type": "agent_turn_stats",
  "message_id": "reply_1234567890",
  "toolCallCount": 2,
  "tools": ["web_search", "calculator"],
  "account_id": "your-account-id"
}
```

## Complete Message Flow Example

```
Gateway                          Clawke Server                    Client
   │                                  │                              │
   │── identify ─────────────────────>│                              │
   │                                  │<──── user sends message ─────│
   │<──── { type: "chat", text } ─────│                              │
   │                                  │                              │
   │   (AI processes...)              │                              │
   │                                  │                              │
   │── agent_thinking_delta ─────────>│── thinking_delta ───────────>│
   │── agent_thinking_delta ─────────>│── thinking_delta ───────────>│
   │── agent_thinking_done ──────────>│── thinking_done ────────────>│
   │── agent_tool_call ──────────────>│── tool_call_start ──────────>│
   │── agent_tool_result ────────────>│── tool_call_done ───────────>│
   │── agent_text_delta ─────────────>│── text_delta ───────────────>│
   │── agent_text_delta ─────────────>│── text_delta ───────────────>│
   │── agent_text_done ──────────────>│── text_done + usage_report ─>│
   │                                  │                              │
```

## Reconnection

Your gateway should implement automatic reconnection with exponential backoff:

```
Attempt 1: 100ms
Attempt 2: 200ms
Attempt 3: 400ms
...
Max delay: 10,000ms (10s)
Add ±25% jitter to prevent thundering herd
```

On reconnect, send `identify` again. Clawke Server will replace the old connection.

## CUP Protocol Translation Reference

Clawke Server automatically translates your gateway messages into the CUP (Clawke Unified Protocol) for the Flutter client:

| Gateway Message | → CUP Message | Notes |
|-----------------|----------------|-------|
| `agent_text_delta` | `text_delta` | Streamed to client in real-time |
| `agent_text_done` | `text_done` + `usage_report` | Persisted to database |
| `agent_text` | `text_delta` + `text_done` | Non-streaming fallback |
| `agent_thinking_delta` | `thinking_delta` | Client renders in collapsible block |
| `agent_thinking_done` | `thinking_done` | |
| `agent_tool_call` | `tool_call_start` | Client shows tool indicator |
| `agent_tool_result` | `tool_call_done` | Client shows duration |
| `agent_media` | `ui_component` (ImageView) | Rendered inline in chat |
| `agent_turn_stats` | *(not forwarded)* | Stats only, used for dashboard |

## Minimal Example (Node.js)

```typescript
import WebSocket from "ws";

const ws = new WebSocket("ws://127.0.0.1:8766");

ws.on("open", () => {
  // Step 1: Identify
  ws.send(JSON.stringify({
    type: "identify",
    accountId: "my-agent",
  }));
});

ws.on("message", (raw) => {
  const msg = JSON.parse(raw.toString());

  if (msg.type === "chat") {
    const replyId = `reply_${Date.now()}`;

    // Step 2: Call your AI provider
    // ... yourAiProvider.stream(msg.text) ...

    // Step 3: Stream response back
    ws.send(JSON.stringify({
      type: "agent_text_delta",
      message_id: replyId,
      delta: "Hello! ",
      account_id: "my-agent",
    }));

    ws.send(JSON.stringify({
      type: "agent_text_done",
      message_id: replyId,
      fullText: "Hello! I'm your AI assistant.",
      account_id: "my-agent",
      model: "my-model",
      provider: "my-provider",
    }));
  }
});

// Step 4: Reconnect on disconnect
ws.on("close", () => {
  setTimeout(() => { /* reconnect logic */ }, 1000);
});
```

## File Structure Reference

```
gateways/
└── openclaw/
    └── clawke/
        ├── index.ts              # Plugin entry point
        ├── package.json          # Dependencies (ws)
        ├── openclaw.plugin.json  # Plugin metadata
        └── src/
            ├── channel.ts        # Channel capabilities & outbound adapter
            ├── config.ts         # Account config schema
            ├── gateway.ts        # WebSocket client & message handling
            └── runtime.ts        # Runtime API bridge
```
