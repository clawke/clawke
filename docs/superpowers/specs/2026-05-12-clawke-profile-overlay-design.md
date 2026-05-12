# Clawke Profile Overlay 设计计划

## 背景

当前 Clawke Server 默认使用 `~/.clawke/clawke.json`，开发环境和正式环境会共享同一份配置、PID、DB、日志和 gateway 配置。开发时切换 `apiBaseUrl`、relay、gateway 路径或端口，可能污染正式环境。

目标是保留老命令兼容性，同时允许通过 `--profile dev` 启动隔离的开发环境。

## 目标

- 老命令完全兼容：
  - `clawke server start`
  - `clawke server restart`
  - `clawke gateway update`
  - `clawke doctor`
- 不传 `--profile` 时，行为保持现在一样，继续使用 `~/.clawke/`。
- 传 `--profile <name>` 时：
  - 配置采用 overlay：默认值 + `~/.clawke/clawke.json` + profile 覆盖。
  - runtime 状态独立：PID、DB、logs、uploads、gateway pid 不 fallback 到正式目录。
- 支持多个 worktree 并行启动，只要 profile 端口不冲突。

## 非目标

- 不迁移用户现有正式配置。
- 不改变 release / TestFlight / Android 发布流程。
- 不让 profile 自动推断 worktree 名称，除非后续另行设计。
- 不在本设计中实现 UI 管理页面。

## 目录结构

默认正式环境保持不变：

```text
~/.clawke/
  clawke.json
  server.pid
  frpc.pid
  data/clawke.db
  logs/
  uploads/
```

profile 目录：

```text
~/.clawke/profiles/
  dev/
    clawke.json
    server.pid
    frpc.pid
    data/clawke.db
    logs/
    uploads/
    hermes-gateway.pid
    OpenClaw-gateway.pid
```

## 命令语义

不传 profile：

```bash
clawke server start
```

等价于当前行为：

```text
CLAWKE_HOME=~/.clawke
config=~/.clawke/clawke.json
```

传 profile：

```bash
clawke server start --profile dev
clawke server restart --profile dev
clawke gateway update --profile dev --local-only
clawke doctor --profile dev
```

等价于：

```text
base config     = ~/.clawke/clawke.json
profile config  = ~/.clawke/profiles/dev/clawke.json
runtime home    = ~/.clawke/profiles/dev
```

建议同时支持：

```bash
clawke --profile dev server start
CLAWKE_PROFILE=dev clawke server start
```

优先级：

```text
CLI --profile > CLAWKE_PROFILE > 默认无 profile
```

## Profile 名称规则

允许：

```text
a-z A-Z 0-9 _ -
```

禁止：

```text
路径分隔符、..、空字符串、绝对路径
```

非法 profile 直接报错，不做路径容错。

## 配置 Overlay 规则

最终配置合并顺序：

```text
内置 DEFAULTS
  <- ~/.clawke/clawke.json
  <- ~/.clawke/profiles/<profile>/clawke.json
  <- 环境变量 / CLI 显式覆盖
```

合并规则：

- object 深度合并。
- scalar 后者覆盖前者。
- array 整体替换，不做逐项合并。
- `gateways` 属于 object，但 gateway list 是 array；profile 中写某个 gateway list 时整体替换该 list。

示例 dev profile：

```json
{
  "server": {
    "httpPort": 8782,
    "upstreamPort": 8768,
    "mediaPort": 8783
  },
  "openclaw": {
    "mediaBaseUrl": "http://127.0.0.1:8783"
  },
  "relay": {
    "enable": false,
    "apiBaseUrl": "https://local.clawke.ai"
  }
}
```

如果 `dev` 没写 `relay.token`，会继承 base config。这样本地 client 仍可使用同一个本地 server token。是否为某个 profile 单独覆盖 token，由用户决定。

## Runtime 隔离规则

配置可以 fallback，runtime 不能 fallback。

当 `--profile dev` 时，下面内容必须只写入：

```text
~/.clawke/profiles/dev/
```

包括：

- `server.pid`
- `frpc.pid`
- `<gateway-id>-gateway.pid`
- `data/clawke.db`
- `logs/`
- `uploads/`
- `bin/`
- `frpc.toml`

原因：如果 runtime fallback 到 `~/.clawke/`，dev 仍会污染正式 DB、PID、日志和隧道状态。

## 写入规则

不传 profile：

- 所有配置写入 `~/.clawke/clawke.json`。
- 行为保持现在不变。

传 profile：

- 配置写入 `~/.clawke/profiles/<profile>/clawke.json`。
- 即使字段来自 base config，修改时也写入 profile override，不回写 base。
- `gateway install --profile dev` 只改 dev profile 的 gateway 配置。
- Device Auth 如果在 profile 下触发，只写 dev profile 的 relay 配置。

## 组件改造范围

### 1. Profile 解析

新增统一解析模块，例如：

```text
server/src/cli/profile.ts
```

职责：

- 从 argv 解析 `--profile`。
- 读取 `CLAWKE_PROFILE`。
- 校验 profile 名。
- 计算：
  - `baseHome`
  - `profileHome`
  - `configPath`
  - `baseConfigPath`
  - `effectiveRuntimeHome`

所有 CLI 命令共用该模块。

### 2. Config 加载

调整 `server/src/config.ts`：

- 支持 `loadConfig({ profile })` 或 `loadConfig({ configPath, baseConfigPath })`。
- 默认无 profile 时保持旧逻辑。
- 有 profile 时执行 overlay merge。
- `getConfigPath()` 返回当前写入目标：无 profile 是 base，有 profile 是 profile config。

### 3. Runtime Home

调整 `server/src/store/clawke-home.ts`：

- 统一从 profile 解析结果或 `CLAWKE_DATA_DIR` 得到 runtime home。
- 无 profile：`~/.clawke`
- 有 profile：`~/.clawke/profiles/<profile>`

### 4. CLI Server 命令

调整 `server/src/cli/clawke.ts`：

- PID 文件不能硬编码 `~/.clawke/server.pid`。
- gateway pid 不能硬编码 `~/.clawke/<id>-gateway.pid`。
- `loadGatewayInstances()` 必须读取 effective config。
- `server start/restart/stop/status` 都使用 effective runtime home。

### 5. Gateway Update

调整 `server/src/cli/gateway-updater.ts`：

- 支持 `--profile`。
- 读取 effective config。
- 写回 profile config。
- restart 时使用 profile runtime home 的 `server.pid`。

### 6. Doctor

调整 `server/src/cli/clawke-doctor.ts`：

`doctor --profile dev` 需要输出：

- profile 名称。
- base config path。
- profile config path。
- runtime home。
- effective ports。
- 当前 PID 是否属于该 profile。
- 端口是否冲突。

## 多 Worktree 并行

可以多个 profile 同时运行，例如：

```bash
clawke server start --profile dev-a
clawke server start --profile dev-b
```

前提是端口不同：

```json
{
  "server": {
    "httpPort": 8782,
    "upstreamPort": 8768,
    "mediaPort": 8783
  },
  "openclaw": {
    "mediaBaseUrl": "http://127.0.0.1:8783"
  }
}
```

Client 也必须指向对应 profile：

```bash
flutter run -d macos \
  --dart-define=CLAWKE_FORCE_HTTP_URL=http://127.0.0.1:8782 \
  --dart-define=CLAWKE_FORCE_WS_URL=ws://127.0.0.1:8782/ws \
  --dart-define=CLAWKE_FORCE_TOKEN=<profile-token>
```

Gateway 也必须连对应 `upstreamPort`：

```text
ws://127.0.0.1:<upstreamPort>
```

## 错误处理

- profile 名非法：直接失败，提示允许字符。
- profile config JSON 无效：失败，显示路径。
- base config 缺失：按现有逻辑初始化 `~/.clawke/clawke.json`。
- profile config 缺失：视为空 override，启动时创建 profile runtime 目录；只有发生写入时创建 `clawke.json`。
- 端口冲突：server start 失败前输出冲突端口和占用 PID。
- profile pid 指向不存在进程：清理 stale pid。
- profile pid 指向其他 profile 或主目录命令：不自动 kill，提示用户。

## 测试计划

### 单元测试

- `loadConfig()` 无 profile 时保持旧行为。
- `loadConfig()` 有 profile 时按 DEFAULTS -> base -> profile 合并。
- object 深度合并。
- array 整体替换。
- profile 名校验。
- profile config 写入只写 override 文件。

### CLI 测试

- `clawke server status` 默认读取 `~/.clawke/server.pid`。
- `clawke server status --profile dev` 读取 `~/.clawke/profiles/dev/server.pid`。
- `clawke gateway update --profile dev --local-only` 写 profile config，不改 base config。
- `clawke doctor --profile dev` 输出 profile paths 和 effective ports。

### 集成验证

- 不传 profile 启动，确认旧 `~/.clawke` 行为不变。
- `--profile dev` 启动，确认：
  - server.pid 在 profile 目录。
  - DB 在 profile 目录。
  - logs 在 profile 目录。
  - health 端口按 profile 生效。
- 同时启动两个 profile，端口不同，互不影响。

## 实施顺序

1. 新增 profile 解析模块和测试。
2. 改造 config overlay 加载和测试。
3. 改造 runtime home 解析。
4. 改造 server CLI 的 PID/gateway pid/config 读取。
5. 改造 gateway update。
6. 改造 doctor。
7. 更新 `clawke-dev-ops` skill，把 `--profile dev` 纳入重启/部署默认流程。
8. 手工验证默认模式和 dev profile 模式。

## 验收标准

- 老命令不传 `--profile` 时行为不变。
- `--profile dev` 不会写 `~/.clawke/server.pid`、`~/.clawke/data`、`~/.clawke/logs`。
- `--profile dev` 只把配置变更写到 `~/.clawke/profiles/dev/clawke.json`。
- `doctor --profile dev` 能准确显示 profile runtime 和 effective config。
- 两个不同 profile 可以在端口不冲突时同时运行。
