import * as fs from 'fs';
import * as path from 'path';
import * as os from 'os';

// ────────────── 类型定义 ──────────────

export interface ServerConfig {
  mode: 'mock' | 'openclaw' | 'cli';
  clientPort: number;
  httpPort: number;
  upstreamPort: number;
  mediaPort: number;
  fastMode: boolean;
  logLevel: string;
}

export interface OpenClawConfig {
  sharedFs: boolean;
  mediaBaseUrl: string;
}

export interface RelayConfig {
  enable: boolean;
  token: string;
  relayUrl: string;
  serverAddr: string;
  serverPort: number;
}

export interface ClawkeConfig {
  server: ServerConfig;
  openclaw: OpenClawConfig;
  relay: RelayConfig;
}

// ────────────── 默认值 ──────────────

const DEFAULTS: ClawkeConfig = {
  server: {
    mode: 'openclaw',
    clientPort: 8765,
    httpPort: 8780,
    upstreamPort: 8766,
    mediaPort: 8781,
    fastMode: false,
    logLevel: 'info',
  },
  openclaw: {
    sharedFs: false,
    mediaBaseUrl: 'http://127.0.0.1:8781',
  },
  relay: {
    enable: false,
    token: '',
    relayUrl: '',
    serverAddr: '',
    serverPort: 7000,
  },
};

// ────────────── 路径解析 ──────────────

const CLAWKE_HOME = process.env.CLAWKE_DATA_DIR
  || path.join(os.homedir(), '.clawke');

/** 配置文件路径：~/.clawke/clawke.json */
const USER_CONFIG_PATH = path.join(CLAWKE_HOME, 'clawke.json');

/** 项目内模板路径：server/config/clawke.json */
const TEMPLATE_CONFIG_PATH = path.join(__dirname, '..', 'config', 'clawke.json');

/**
 * 获取配置文件的绝对路径
 * 外部模块需要写入配置时使用（如 Device Auth 写入 relay 凭证）
 */
export function getConfigPath(): string {
  return USER_CONFIG_PATH;
}

// ────────────── 加载逻辑 ──────────────

/**
 * 确保 ~/.clawke/clawke.json 存在。
 * 不存在时从项目模板 server/config/clawke.json 拷贝；
 * 模板也不存在则使用内置默认值创建。
 */
function ensureConfigFile(): void {
  if (fs.existsSync(USER_CONFIG_PATH)) return;

  fs.mkdirSync(path.dirname(USER_CONFIG_PATH), { recursive: true });

  if (fs.existsSync(TEMPLATE_CONFIG_PATH)) {
    fs.copyFileSync(TEMPLATE_CONFIG_PATH, USER_CONFIG_PATH);
    console.log(`[Config] Initialized config from template: ${TEMPLATE_CONFIG_PATH} → ${USER_CONFIG_PATH}`);
  } else {
    fs.writeFileSync(USER_CONFIG_PATH, JSON.stringify(DEFAULTS, null, 2) + '\n');
    console.log(`[Config] Created default config: ${USER_CONFIG_PATH}`);
  }
}

/**
 * 加载 Clawke 配置。
 *
 * 优先级：
 *   1. configPath 参数（测试用）
 *   2. ~/.clawke/clawke.json（用户配置）
 *   3. 内置默认值
 *
 * 首次启动时自动从 server/config/clawke.json 模板拷贝到 ~/.clawke/。
 */
export function loadConfig(configPath?: string): ClawkeConfig {
  const filePath = configPath || USER_CONFIG_PATH;

  // 仅在使用默认路径时自动初始化
  if (!configPath) {
    ensureConfigFile();
  }

  let fileConfig: Record<string, any> = {};
  try {
    const raw = fs.readFileSync(filePath, 'utf-8');
    fileConfig = JSON.parse(raw);
  } catch {
    console.warn(`[Config] Config file not found: ${filePath}, using defaults`);
  }

  return {
    server: {
      ...DEFAULTS.server,
      ...(fileConfig.server || {}),
      // 环境变量覆盖 mode（兼容 MODE=mock node dist/index.js）
      ...(process.env.MODE ? { mode: process.env.MODE as 'mock' | 'openclaw' | 'cli' } : {}),
    },
    openclaw: {
      ...DEFAULTS.openclaw,
      ...(fileConfig.openclaw || {}),
    },
    relay: {
      ...DEFAULTS.relay,
      ...(fileConfig.relay || {}),
    },
  };
}

/**
 * 重新加载配置（Device Auth 写入后调用）
 */
export function reloadConfig(configPath?: string): ClawkeConfig {
  return loadConfig(configPath);
}

