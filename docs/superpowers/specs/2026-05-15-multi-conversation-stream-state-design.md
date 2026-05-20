# 多会话流式运行态隔离设计

## 一句话结论

右侧聊天区保持一个 `ChatScreen` viewport。接收层支持多个会话同时流式接收，每个会话的流式正文、Thinking、等待状态、工具状态和缓冲区都按 `conversationId` 隔离。当前 viewport 只订阅当前会话的运行态。

## 背景问题

当前客户端把流式消息放在全局单槽状态里。两个会话同时接收时，后到的 delta 会覆盖前一个会话的 streaming state，并可能触发旧流 finalize。即使 UI 按 `conversationId` 过滤，当前 `ChatScreen` 仍会因为全局 provider 变化而重建，表现为聊天区闪烁。

## 硬约束

1. `text_delta` 和 `thinking_delta` 永远不写数据库。
2. 永远不做“每个会话一个常驻 ChatScreen”。
3. 左侧会话列表的 preview 和 time 只在 `text_done` 后一次性更新。
4. 后台会话接收流式内容时，不能触发当前会话聊天区闪烁。
5. 切换到后台会话时，应展示该会话已累计到的位置，并继续追加后续 delta。

## 架构原则

```text
一个 ChatScreen viewport
+
按 conversationId 隔离的轻量运行态
```

展示层只有一个聊天 viewport。数据和运行态按会话隔离。切换会话时，viewport 绑定到另一个 `conversationId` 的状态，而不是创建或保留多个隐藏 `ChatScreen`。

## 运行态模型

新增按会话隔离的运行态容器：

```text
Map<String, ConversationRuntimeState>
```

每个 `ConversationRuntimeState` 至少包含：

```text
conversationId
streamingTextMessage
streamingThinkingMessage
waitingForReply
activeTool
textBuffer
thinkingBuffer
textFlushTimer
thinkingFlushTimer
```

其中 buffer 和 timer 必须属于单个会话，不能再使用全局 `_textBuffer`、`_thinkingBuffer`、`_streamingConversationId` 作为跨会话共享状态。

## 接收流程

### text_delta

```text
读取 conversationId
找到 runtimeState[conversationId]
append 到该会话 textBuffer
刷新该会话 streamingTextMessage
不写 DB
不更新左侧会话列表 preview/time
只通知该 conversationId 的订阅者
```

### thinking_delta

```text
读取 conversationId
找到 runtimeState[conversationId]
append 到该会话 thinkingBuffer
刷新该会话 streamingThinkingMessage
不写 DB
不更新左侧会话列表 preview/time
只通知该 conversationId 的订阅者
```

### text_done

```text
读取 conversationId
读取 runtimeState[conversationId]
将最终 text/thinking 写入消息 DB
更新 conversation.lastMessageAt / lastMessagePreview
清理该会话运行态
不影响其他会话运行态
```

## 展示流程

`ChatScreen` 仍然只有一个。它只订阅当前 `selectedConversationId` 对应的运行态：

```text
selectedConversationId -> ConversationRuntimeState?
```

结果：

- 当前会话流式时，正常展示正文、Thinking、等待状态、工具状态和停止按钮。
- 后台会话流式时，只更新后台会话自己的内存运行态，不触发当前聊天区刷新。
- 用户切到后台会话时，立即看到已累计内容，后续 delta 继续追加。
- 用户切回原会话时，原会话运行态仍在，不会被后台会话清掉。

## 不采用的方案

### 不把 delta 写 DB

流式 token 到达频率高。如果每个 delta 都写 DB，会造成大量 IO、Drift watch 重算、消息列表刷新和移动端性能压力。最终 `text_done` 已经能完成持久化，所以 delta 只能进入内存运行态。

### 不保留每个会话一个 ChatScreen

多个隐藏 `ChatScreen` 会让内存、ScrollController、TextEditingController、ListView、Markdown/代码块渲染对象和 DB watcher 随会话数线性增长。隐藏页面也可能继续 rebuild，移动端风险更高。需要保留的是会话状态，不是整棵 Widget 树。

## 第一阶段范围

1. 将 `streamingMessageProvider` 从单值改成按会话隔离。
2. 将 `streamingThinkingProvider` 从单值改成按会话隔离。
3. 将 `waitingForReplyProvider` 改成按会话隔离。
4. 将 `activeToolProvider` 改成按会话隔离。
5. 将 `_streamingConversationId`、文本 buffer、Thinking buffer、flush timer 改成每会话独立。
6. 修改 `ChatScreen`，只订阅当前会话的运行态。
7. 补测试覆盖两个会话交错 delta、切换会话继续显示累计内容、`text_done` 后才写 DB。

## TDD 与 E2E 策略

这次必须先复现 bug，再改代码。实现前先写失败用例，确认当前代码会失败，并且失败原因就是多会话流式状态串扰，而不是测试脚本错误。

### RED：先复现

第一层用 Flutter provider/widget 测试精确复现：

```text
会话 A 收到 text_delta: "A1"
会话 B 收到 text_delta: "B1"
会话 A 再收到 text_delta: "A2"
断言 A 的流式内容应为 "A1A2"
断言 B 的流式内容应为 "B1"
断言 A/B 没有互相 finalize 或清空
```

当前代码预期会失败，因为全局单槽 `streamingMessageProvider` 会被 B 覆盖，A 再来 delta 时状态已经不是 A。

第二层用 UI E2E 复现用户路径：

```text
创建会话 A
让 Mock Gateway 开始慢速流式回复 A
切到/创建会话 B
让 Mock Gateway 开始慢速流式回复 B
在 A/B 之间切换
断言切到任一会话时，都能看到该会话已累计的部分回复
断言另一会话后台流式时，当前聊天区不出现对方内容、不清空、不跳 stop 状态
断言 text_done 前左侧 preview/time 不跟随 delta 跳动
```

UI E2E 需要新增或扩展 Mock Gateway 能力，让它能对两个 `conversation_id` 交错发送 delta。这个用例应该放在 `test/ui-e2e/test-cases/`，作为 P0 聊天回归。

### GREEN：最小修复

只有 RED 用例按预期失败后，才改生产代码。修复只围绕运行态按会话隔离，不引入 delta 写 DB，也不引入多个常驻 `ChatScreen`。

### 验证顺序

1. 运行新的 provider/widget 失败用例，确认 RED。
2. 运行新的 UI E2E 失败用例，确认能复现用户可见问题。
3. 实现按会话隔离运行态。
4. 重新运行 provider/widget 测试，确认 GREEN。
5. 重新运行 UI E2E，确认用户路径修复。
6. 运行相关既有聊天/流式测试，防止断连恢复、Thinking、停止按钮回归。

## 暂不做

- 不做每个会话独立 `ChatScreen` 常驻。
- 不做 delta 写 DB。
- 不扩大到草稿和滚动位置持久化。
- 不改服务端重试机制和 Gateway 协议。

## 验收标准

1. 两个会话同时接收流式内容时，当前聊天区不闪烁。
2. A 会话流式中切到 B，会显示 B 已累计的流式内容。
3. B 后台继续流式时，不影响 A 的右侧聊天区。
4. `text_done` 前左侧会话 preview/time 不跳动。
5. `text_done` 后消息写入 DB，左侧会话列表一次性更新。
6. Flutter 单元测试覆盖多会话交错流式场景。
7. UI E2E 覆盖两个会话交错流式、切换会话、后台流式不污染当前会话。
