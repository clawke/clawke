# 回归测试

发布前必须运行回归测试，确保核心功能正常。

## 测试层级

| 文件 | 类型 | 依赖 | 说明 |
|------|------|------|------|
| `media-resolution.test.js` | 单元测试 | 仅 CS HTTP | 验证媒体解析逻辑：本地读取 + HTTP 下载两条分支 |
| `media-upload.test.js` | 集成测试 | CS 运行 | 验证 HTTP 上传 + 文件保存 + 类型处理（PNG/JPEG/PDF/TXT） |
| `media-e2e.test.js` | 端到端测试 | CS + OpenClaw | 验证完整链路：上传 → CS → GW → AI 回复 |

## 运行

```bash
# 仅单元测试（无需启动服务）
npm test -- --test-path-pattern regression/media-resolution

# 集成测试（需要 CS 运行在本地）
node test/regression/media-upload.test.js

# 端到端测试（需要 CS + OpenClaw + SSH 隧道）
node test/regression/media-e2e.test.js

# 运行全部回归测试
node test/regression/run-all.js
```

## 前置条件

### 单元 + 集成测试
- CS 运行：`node index.js`

### 端到端测试
- CS 运行：`node index.js`（本地 Mac）
- SSH 隧道：`ssh -vNR 8766:127.0.0.1:8766 user@<REMOTE_HOST>`
- OpenClaw：`pnpm dev gateway --force`（远程 Mac）
