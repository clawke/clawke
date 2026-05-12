import * as fs from 'fs';
import * as path from 'path';
import { resolveProfileContext, type ResolveProfileOptions } from './profile.js';

// ────────────── 类型定义 ──────────────

export interface ServerConfig {
  mode: 'mock' | 'openclaw';
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
  apiBaseUrl: string;
  relayUrl: string;
  serverAddr: string;
  serverPort: number;
}

export interface ClawkeConfig {
  server: ServerConfig;
  openclaw: OpenClawConfig;
  relay: RelayConfig;
  gateways?: Record<string, unknown>;
  [key: string]: unknown;
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
    apiBaseUrl: 'https://api.clawke.ai',
    relayUrl: '',
    serverAddr: '',
    serverPort: 7000,
  },
};

/** 项目内模板路径：server/config/clawke.json */
const TEMPLATE_CONFIG_PATH = path.join(__dirname, '..', 'config', 'clawke.json');

export interface LoadConfigOptions extends ResolveProfileOptions {
  configPath?: string;
  baseConfigPath?: string;
  profileConfigPath?: string;
  ensure?: boolean;
}

/**
 * 获取配置文件的绝对路径
 * 外部模块需要写入配置时使用（如 Device Auth 写入 relay 凭证）
 */
export function getConfigPath(options: ResolveProfileOptions = {}): string {
  return resolveProfileContext(options).configPath;
}

// ────────────── 加载逻辑 ──────────────

/**
 * 确保 ~/.clawke/clawke.json 存在。
 * 不存在时从项目模板 server/config/clawke.json 拷贝；
 * 模板也不存在则使用内置默认值创建。
 */
function ensureConfigFile(configPath: string): void {
  if (fs.existsSync(configPath)) return;

  fs.mkdirSync(path.dirname(configPath), { recursive: true });

  if (fs.existsSync(TEMPLATE_CONFIG_PATH)) {
    fs.copyFileSync(TEMPLATE_CONFIG_PATH, configPath);
    console.log(`[Config] Initialized config from template: ${TEMPLATE_CONFIG_PATH} → ${configPath}`);
  } else {
    fs.writeFileSync(configPath, JSON.stringify(DEFAULTS, null, 2) + '\n');
    console.log(`[Config] Created default config: ${configPath}`);
  }
}

function readConfigFile(filePath: string, warnOnMissing: boolean): Record<string, any> {
  try {
    const raw = fs.readFileSync(filePath, 'utf-8');
    return JSON.parse(raw);
  } catch {
    if (warnOnMissing) {
      console.warn(`[Config] Config file not found: ${filePath}, using defaults`);
    }
    return {};
  }
}

function isPlainObject(value: unknown): value is Record<string, any> {
  return Boolean(value) && typeof value === 'object' && !Array.isArray(value);
}

function deepMergeConfig(base: Record<string, any>, overlay: Record<string, any>): Record<string, any> {
  const result: Record<string, any> = { ...base };
  for (const [key, value] of Object.entries(overlay)) {
    if (Array.isArray(value)) {
      result[key] = value.slice();
    } else if (isPlainObject(value) && isPlainObject(result[key])) {
      result[key] = deepMergeConfig(result[key], value);
    } else if (isPlainObject(value)) {
      result[key] = deepMergeConfig({}, value);
    } else {
      result[key] = value;
    }
  }
  return result;
}

function normalizeConfig(fileConfig: Record<string, any>, env: NodeJS.ProcessEnv | Record<string, string | undefined>): ClawkeConfig {
  return {
    ...fileConfig,
    server: {
      ...DEFAULTS.server,
      ...(fileConfig.server || {}),
      // 环境变量覆盖 mode（兼容 MODE=mock node dist/index.js） — MODE env overrides config for legacy launchers.
      ...(env.MODE ? { mode: env.MODE as 'mock' | 'openclaw' } : {}),
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
 * 加载 Clawke 配置。
 *
 * 优先级：
 *   1. configPath 参数（测试用）
 *   2. ~/.clawke/clawke.json（用户配置）
 *   3. 内置默认值
 *
 * 首次启动时自动从 server/config/clawke.json 模板拷贝到 ~/.clawke/。
 */
export function loadConfig(input?: string | LoadConfigOptions): ClawkeConfig {
  if (typeof input === 'string') {
    return normalizeConfig(readConfigFile(input, true), process.env);
  }

  const options = input || {};
  const env = options.env ?? process.env;
  const context = resolveProfileContext(options);
  const ensure = options.ensure ?? true;
  const baseConfigPath = options.baseConfigPath || context.baseConfigPath;
  const profileConfigPath = options.profileConfigPath || context.profileConfigPath;

  if (options.configPath && !context.isProfile) {
    return normalizeConfig(readConfigFile(options.configPath, true), env);
  }

  if (ensure) {
    ensureConfigFile(baseConfigPath);
  }

  const baseConfig = readConfigFile(baseConfigPath, false);
  if (!context.isProfile) {
    return normalizeConfig(baseConfig, env);
  }

  const profileConfig = profileConfigPath ? readConfigFile(profileConfigPath, false) : {};
  return normalizeConfig(deepMergeConfig(baseConfig, profileConfig), env);
}

/**
 * 重新加载配置（Device Auth 写入后调用）
 */
export function reloadConfig(input?: string | LoadConfigOptions): ClawkeConfig {
  return loadConfig(input);
}
