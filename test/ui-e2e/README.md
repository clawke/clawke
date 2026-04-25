# Clawke UI E2E

这个目录管理 UI 层系统级集成测试。第一阶段只做手动触发，主力层是 Mock Gateway UI E2E。

## 测试边界

真实链路：

```text
Flutter UI -> Clawke Server -> WebSocket -> CUP -> Flutter 原生渲染
```

Mock 边界：

```text
Clawke Server -> Scripted Mock Gateway
```

不连接真实 Agent，不连接真实 LLM。测试系统只执行 UI、观察结果、输出报告，不负责修复。

## 一次性准备

```bash
cd server
npm install

cd ../client
dart run build_runner build --delete-conflicting-outputs
```

如果本地 Flutter/macOS 依赖已经生成过，第二条可以跳过。

## 手动运行

从仓库根目录执行：

```bash
./test/ui-e2e/tools/run.sh --case p0-send-message
```

通过时输出：

```text
PASS p0-send-message
Artifacts: test/ui-e2e/runs/<run-id>-p0-send-message
```

失败时输出 bug report 路径：

```text
FAIL p0-send-message
Bug report: test/ui-e2e/bug-reports/<run-id>-p0-send-message.md
```

## 目录

- `tools/`: runner、Mock Gateway、启动脚本。
- `test-cases/`: 持久化用例。
- `templates/`: bug report 模板。
- `docs/`: 设计和实施文档。
- `runs/`: 每次运行日志和结果，本地保留，不提交。
- `bug-reports/`: 失败报告，本地保留，不提交。

## 当前用例

- `p0-send-message`: 新建会话，发送消息，验证流式中间态和最终回复。
- `p0-openclaw-inline-approval`: OpenClaw markdown approval 代码块，点击原生审批按钮后以普通 chat 回复 `y`。
- `p0-openclaw-inline-choice`: OpenClaw markdown clarify 代码块，点击原生选项后以普通 chat 回复选项文本。
- `p0-hermes-approval`: Hermes 结构化 `approval_request`，点击原生审批按钮后透传 `approval_response`。
- `p0-hermes-choice`: Hermes 结构化 `clarify_request`，点击原生选项后透传 `clarify_response`。
