# CLI 与 Claude Code 双向通信机制

> 基于 Happy CLI 源码的深度分析
> 日期：2026-04-07

---

## 核心发现：两种截然不同的模式

Happy CLI 实现了 **两种运行模式**，使用完全不同的 I/O 机制：

| | Local 模式 | Remote 模式 |
|---|---|---|
| **输入** | `stdio: 'inherit'`（用户直接在终端打字） | `stdin.write(JSON)` (程序化写入 JSON) |
| **输出** | 读磁盘上的 JSONL 日志文件 | `stdout` 读取 JSON 消息流 |
| **场景** | 用户坐在电脑前 | 用户通过手机远程发消息 |
| **Claude 启动参数** | 无特殊 output format | `--output-format stream-json --input-format stream-json` |

---

## Local 模式 — 文件轮询

### 启动 Claude Code — `stdio: 'inherit'`

```typescript
// claudeLocal.ts
const child = spawn('node', [claudeCliPath, ...args], {
    stdio: ['inherit', 'inherit', 'inherit', 'pipe'],
    //       ↑ stdin    ↑ stdout   ↑ stderr   ↑ fd3 (自定义)
});
```

> `stdio: 'inherit'` 意味着 Claude Code 直接接管用户的终端。CLI 不拦截任何 I/O。

### 输出捕获 — 读 JSONL 日志文件

```typescript
// sessionScanner.ts
const sync = new InvalidateSync(async () => {
    const sessionMessages = await readSessionLog(projectDir, session);
    for (let file of sessionMessages) {
        let key = messageKey(file);
        if (processedMessageKeys.has(key)) continue;
        processedMessageKeys.add(key);
        opts.onMessage(file);  // 新消息 → 发送到服务器
    }
});

// 文件 watch + 3秒定时器兜底
watchers.set(p, startFileWatcher(join(projectDir, `${p}.jsonl`), () => sync.invalidate()));
const intervalId = setInterval(() => { sync.invalidate(); }, 3000);
```

### JSONL 文件路径

`~/.claude/projects/{projectHash}/{sessionId}.jsonl`

```jsonl
{"type":"user","uuid":"abc-123","message":{"role":"user","content":"fix the bug"}}
{"type":"assistant","uuid":"def-456","message":{"role":"assistant","content":[{"type":"text","text":"I'll fix..."}]}}
```

### fd3 — 思考状态追踪

```typescript
if (child.stdio[3]) {
    const rl = createInterface({ input: child.stdio[3] });
    rl.on('line', (line) => {
        const message = JSON.parse(line);
        if (message.type === 'fetch-start') updateThinking(true);
        if (message.type === 'fetch-end')   updateThinking(false);
    });
}
```

---

## Remote 模式 — SDK 管道通信

### 启动 Claude Code — `stdio: 'pipe'`

```typescript
// sdk/query.ts
const args = ['--output-format', 'stream-json', '--verbose'];
args.push('--input-format', 'stream-json');

const child = spawn(spawnCommand, spawnArgs, {
    stdio: ['pipe', 'pipe', 'pipe'],  // 全管道化
});
```

### 写入消息 — stdin.write(JSON)

```typescript
// sdk/utils.ts
export async function streamToStdin(stream, stdin, abort) {
    for await (const message of stream) {
        if (abort?.aborted) break;
        stdin.write(JSON.stringify(message) + '\n');
    }
    stdin.end();
}
```

### 读取输出 — stdout readline

```typescript
// sdk/query.ts
private async readMessages() {
    const rl = createInterface({ input: this.childStdout });
    for await (const line of rl) {
        if (!line.trim()) continue;
        const message = JSON.parse(line);
        if (message.type === 'control_request') {
            await this.handleControlRequest(message);
            continue;
        }
        this.inputStream.enqueue(message);
    }
}
```

### 权限审批 — 双向 JSON 管道

```
Claude stdout → CLI:
{"type":"control_request","request_id":"abc","request":{"subtype":"can_use_tool","tool_name":"Write","input":{"path":"main.ts"}}}

CLI → Claude stdin:
{"type":"control_response","response":{"subtype":"success","request_id":"abc","response":{"behavior":"allow"}}}
```

### 完整消息链路

```typescript
// claudeRemote.ts
let messages = new PushableAsyncIterable<SDKUserMessage>();
messages.push({ type: 'user', message: { role: 'user', content: initial.message } });

const response = query({ prompt: messages, options: sdkOptions });

for await (const message of response) {
    opts.onMessage(message);  // → 加密 → Server → 手机

    if (message.type === 'result') {
        opts.onReady();
        const next = await opts.nextMessage();
        if (!next) { messages.end(); return; }
        messages.push({ type: 'user', message: { role: 'user', content: next.message } });
    }
}
```

---

## 对比总结

| 维度 | Local 模式 | Remote 模式 |
|------|-----------|-------------|
| **Claude 启动参数** | 无特殊参数 | `--output-format stream-json --input-format stream-json` |
| **stdio 配置** | `['inherit', 'inherit', 'inherit', 'pipe']` | `['pipe', 'pipe', 'pipe']` |
| **输入方式** | 用户终端直接输入 | `stdin.write(JSON + '\n')` |
| **输出捕获** | JSONL 文件轮询 | `readline` 逐行读 stdout JSON |
| **延迟** | 文件 watch + 3s 兜底 | 实时（管道直连） |
| **额外管道** | fd3（thinking 状态） | control_request/response（权限审批） |

---

## Claude Code 关键参数

| 参数 | 作用 |
|------|------|
| `--output-format stream-json` | stdout 输出 JSON 消息流 |
| `--input-format stream-json` | stdin 接收 JSON 用户消息 |
| `--resume <sessionId>` | 恢复之前的会话上下文 |
| `--permission-prompt-tool stdio` | 权限审批走 stdio 管道 |
| `--permission-mode <mode>` | 权限模式（default/plan/bypassPermissions） |
| `--verbose` | 输出更详细的消息（包括 system init） |
| `--model <model>` | 指定模型 |
| `--append-system-prompt <text>` | 追加系统提示词 |
