/**
 * Gateway 自动安装器
 *
 * 检测本机 OpenClaw → 版本比较 → 拷贝插件 → 合并配置 → 重启
 */
import fs from 'fs';
import path from 'path';
import os from 'os';
import { execSync, spawnSync } from 'child_process';
import { registerGatewayInClawkeConfig } from './clawke-config-writer.js';

const OPENCLAW_HOME = path.join(os.homedir(), '.openclaw');
const OPENCLAW_CONFIG = path.join(OPENCLAW_HOME, 'openclaw.json');
const EXTENSIONS_DIR = path.join(OPENCLAW_HOME, 'extensions');
const TARGET_DIR = path.join(EXTENSIONS_DIR, 'clawke');

interface OpenClawConfigMergeLogger {
  info(message: string): void;
  warn(message: string): void;
}

interface OpenClawConfigMergeResult {
  addedChannelConfig: boolean;
  addedConversationHookAccess: boolean;
  enabledControlUiInsecureAuth: boolean;
  updatedSessionDmScope: boolean;
  preservedSessionDmScope?: string;
}

/** 获取项目内 gateway 插件源路径 */
function getSourceDir(): string {
  // dist/cli/gateway-installer.js → server/ → ../gateways/openclaw/clawke/
  return path.join(__dirname, '..', '..', '..', 'gateways', 'openclaw', 'clawke');
}


export async function installOpenClawGateway(): Promise<void> {
  console.log('[clawke] 🔍 Detecting OpenClaw installation...');

  // Step 1: 检测 OpenClaw
  if (!fs.existsSync(OPENCLAW_CONFIG)) {
    printRemoteGuide();
    return;
  }

  console.log(`[clawke] ✅ OpenClaw detected: ${OPENCLAW_CONFIG}`);

  const sourceDir = getSourceDir();
  if (!fs.existsSync(sourceDir)) {
    console.error(`[clawke] ❌ Gateway source not found: ${sourceDir}`);
    console.error('[clawke] Please run this command from the Clawke project root.');
    process.exit(1);
  }

  console.log(`[clawke] 📦 Installing gateway plugin...`);

  // Step 3: 拷贝插件文件
  fs.mkdirSync(TARGET_DIR, { recursive: true });
  fs.cpSync(sourceDir, TARGET_DIR, { recursive: true });
  console.log(`[clawke] ✅ Plugin copied: ${sourceDir} → ${TARGET_DIR}`);

  // Step 3.5: 安装插件依赖（ws 等）
  if (fs.existsSync(path.join(TARGET_DIR, 'package.json'))) {
    console.log('[clawke] 📦 Installing plugin dependencies...');
    try {
      execSync('npm install --production', { cwd: TARGET_DIR, stdio: 'inherit', timeout: 60000 });
      console.log('[clawke] ✅ Dependencies installed');
    } catch {
      console.error('[clawke] ⚠️  npm install failed. Please run manually:');
      console.error(`  cd ${TARGET_DIR} && npm install`);
    }
  }

  // Step 4: 合并 OpenClaw 配置
  mergeOpenClawConfig();
  mergeClawkeConfig();

  // Step 5: 重启 OpenClaw
  restartOpenClaw();
}

function mergeOpenClawConfig(): void {
  mergeOpenClawConfigFile(OPENCLAW_CONFIG, {
    info: (message) => console.log(message),
    warn: (message) => console.error(message),
  });
}

export function mergeOpenClawConfigFile(
  configPath: string,
  logger: OpenClawConfigMergeLogger,
): void {
  let config: Record<string, any> = {};
  try {
    config = JSON.parse(fs.readFileSync(configPath, 'utf-8'));
  } catch (err: any) {
    logger.warn(`[clawke] ⚠️  Could not parse ${configPath}: ${err.message}`);
    logger.warn('[clawke] Creating backup and writing fresh config...');
  }

  // 备份
  try {
    fs.copyFileSync(configPath, configPath + '.bak');
    logger.info(`[clawke] 📋 Config backed up: ${configPath}.bak`);
  } catch {}

  const result = mergeOpenClawConfigForClawke(config);
  logOpenClawConfigMergeResult(result, logger);

  fs.writeFileSync(configPath, JSON.stringify(config, null, 2) + '\n');
  logger.info(`[clawke] ✅ OpenClaw config updated: ${configPath}`);
}

export function mergeOpenClawConfigForClawke(config: Record<string, any>): OpenClawConfigMergeResult {
  const result: OpenClawConfigMergeResult = {
    addedChannelConfig: false,
    addedConversationHookAccess: false,
    enabledControlUiInsecureAuth: false,
    updatedSessionDmScope: false,
  };

  // 合并 channels.clawke
  if (!config.channels) config.channels = {};
  if (!config.channels.clawke) {
    config.channels.clawke = {
      enabled: true,
      url: 'ws://127.0.0.1:8766',
    };
    result.addedChannelConfig = true;
  } else {
    // 不覆盖已有的 url，只确保 enabled
    config.channels.clawke.enabled = true;
  }

  // 合并 plugins.entries.clawke
  result.addedConversationHookAccess = enableClawkePluginEntryForClawke(config);

  result.enabledControlUiInsecureAuth = enableControlUiInsecureAuthForClawke(config);

  // 合并 session.dmScope — 多会话隔离需要 per-account-channel-peer
  if (!config.session) config.session = {};
  const currentScope = config.session.dmScope;
  if (!currentScope || currentScope === 'main') {
    config.session.dmScope = 'per-account-channel-peer';
    result.updatedSessionDmScope = true;
  } else if (currentScope !== 'per-account-channel-peer') {
    result.preservedSessionDmScope = String(currentScope);
  }

  return result;
}

function logOpenClawConfigMergeResult(
  result: OpenClawConfigMergeResult,
  logger: OpenClawConfigMergeLogger,
): void {
  if (result.addedChannelConfig) {
    logger.info('[clawke] ✅ Added channels.clawke config (url: ws://127.0.0.1:8766)');
  } else {
    logger.info('[clawke] ✅ Enabled channels.clawke (existing url preserved)');
  }

  if (result.addedConversationHookAccess) {
    logger.info('[clawke] ✅ Enabled plugins.entries.clawke with hooks.allowConversationAccess = true');
  } else {
    logger.info('[clawke] ✅ Enabled plugins.entries.clawke (existing hook config preserved)');
  }

  if (result.enabledControlUiInsecureAuth) {
    logger.info('[clawke] ✅ Set gateway.controlUi.allowInsecureAuth = true');
  } else {
    logger.info('[clawke] ✅ gateway.controlUi.allowInsecureAuth already enabled');
  }

  if (result.updatedSessionDmScope) {
    logger.info('[clawke] ✅ Set session.dmScope = "per-account-channel-peer" (multi-session isolation)');
  } else if (result.preservedSessionDmScope) {
    logger.info(`[clawke] ℹ️  session.dmScope already set to "${result.preservedSessionDmScope}" — keeping user config`);
  }
}

function mergeClawkeConfig(): void {
  registerGatewayInClawkeConfig({
    gatewayType: 'openclaw',
    gatewayId: 'OpenClaw',
  });
  console.log('[clawke] ✅ Registered OpenClaw gateway in ~/.clawke/clawke.json');
}

function restartOpenClaw(): void {
  // 检测 openclaw 命令是否存在（远程部署场景下本机无此命令）
  const which = spawnSync('which openclaw', { shell: true });
  if (which.status !== 0) {
    console.log('[clawke] ℹ️  openclaw not found locally (remote server scenario).');
    console.log('  Please restart OpenClaw on the remote server:');
    console.log('    openclaw gateway restart');
    return;
  }

  console.log('[clawke] 🔄 Restarting OpenClaw...');
  try {
    const result = spawnSync('openclaw gateway restart', {
      shell: true,
      stdio: 'inherit',
    });
    if (result.status !== 0) {
      throw new Error(`exit code ${result.status}`);
    }
    console.log('[clawke] ✅ Gateway installed and OpenClaw restarted');
  } catch {
    console.log('');
    console.log('[clawke] ⚠️  Could not restart OpenClaw automatically.');
    console.log('  Please restart manually:');
    console.log('    openclaw gateway restart');
  }
}

function printRemoteGuide(): void {
  console.log(`[clawke] OpenClaw not detected on this machine.

If OpenClaw is installed locally:

  1. Install OpenClaw first:
     npm install -g openclaw@latest
     openclaw onboard --install-daemon

  2. Re-run:
     clawke gateway install

If OpenClaw is installed on a remote server, install the gateway manually:

  1. Copy the plugin:
     scp -r gateways/openclaw/clawke/ user@<REMOTE>:~/.openclaw/extensions/

  2. Configure OpenClaw (edit ~/.openclaw/openclaw.json on the remote server):
     {
       "gateway": {
         "controlUi": {
           "allowInsecureAuth": true
         }
       },
       "session": {
         "dmScope": "per-account-channel-peer"
       },
       "channels": {
         "clawke": {
           "enabled": true,
           "url": "ws://<THIS_MACHINE_IP>:8766"
         }
       },
       "plugins": {
         "entries": {
           "clawke": {
             "enabled": true,
             "hooks": {
               "allowConversationAccess": true
             }
           }
         }
       }
     }

  3. Restart OpenClaw on the remote server:
     npx openclaw gateway restart`);
}

export function enableControlUiInsecureAuthForClawke(config: Record<string, any>): boolean {
  if (!config.gateway || typeof config.gateway !== 'object' || Array.isArray(config.gateway)) {
    config.gateway = {};
  }
  if (
    !config.gateway.controlUi ||
    typeof config.gateway.controlUi !== 'object' ||
    Array.isArray(config.gateway.controlUi)
  ) {
    config.gateway.controlUi = {};
  }

  const changed = config.gateway.controlUi.allowInsecureAuth !== true;
  config.gateway.controlUi.allowInsecureAuth = true;
  return changed;
}

export function enableClawkePluginEntryForClawke(config: Record<string, any>): boolean {
  if (!config.plugins || typeof config.plugins !== 'object' || Array.isArray(config.plugins)) {
    config.plugins = {};
  }
  if (!config.plugins.entries || typeof config.plugins.entries !== 'object' || Array.isArray(config.plugins.entries)) {
    config.plugins.entries = {};
  }

  const existingEntry = config.plugins.entries.clawke;
  const entry =
    existingEntry && typeof existingEntry === 'object' && !Array.isArray(existingEntry)
      ? existingEntry
      : {};
  config.plugins.entries.clawke = entry;
  entry.enabled = true;

  if (!entry.hooks || typeof entry.hooks !== 'object' || Array.isArray(entry.hooks)) {
    entry.hooks = {};
  }

  if (!Object.prototype.hasOwnProperty.call(entry.hooks, 'allowConversationAccess')) {
    entry.hooks.allowConversationAccess = true;
    return true;
  }

  return false;
}
