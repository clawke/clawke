/**
 * Gateway 自动安装器
 *
 * 检测本机 OpenClaw → 版本比较 → 拷贝插件 → 合并配置 → 重启
 */
import fs from 'fs';
import path from 'path';
import os from 'os';
import { execSync } from 'child_process';

const OPENCLAW_HOME = path.join(os.homedir(), '.openclaw');
const OPENCLAW_CONFIG = path.join(OPENCLAW_HOME, 'openclaw.json');
const EXTENSIONS_DIR = path.join(OPENCLAW_HOME, 'extensions');
const TARGET_DIR = path.join(EXTENSIONS_DIR, 'clawke');

/** 获取项目内 gateway 插件源路径 */
function getSourceDir(): string {
  // dist/cli/gateway-installer.js → server/ → ../gateways/openclaw/clawke/
  return path.join(__dirname, '..', '..', '..', 'gateways', 'openclaw', 'clawke');
}


export async function installGateway(): Promise<void> {
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

  // Step 5: 重启 OpenClaw
  restartOpenClaw();
}

function mergeOpenClawConfig(): void {
  let config: Record<string, any> = {};
  try {
    config = JSON.parse(fs.readFileSync(OPENCLAW_CONFIG, 'utf-8'));
  } catch (err: any) {
    console.error(`[clawke] ⚠️  Could not parse ${OPENCLAW_CONFIG}: ${err.message}`);
    console.error('[clawke] Creating backup and writing fresh config...');
  }

  // 备份
  try {
    fs.copyFileSync(OPENCLAW_CONFIG, OPENCLAW_CONFIG + '.bak');
    console.log(`[clawke] 📋 Config backed up: ${OPENCLAW_CONFIG}.bak`);
  } catch {}

  // 合并 channels.clawke
  if (!config.channels) config.channels = {};
  if (!config.channels.clawke) {
    config.channels.clawke = {
      enabled: true,
      url: 'ws://127.0.0.1:8766',
    };
    console.log('[clawke] ✅ Added channels.clawke config (url: ws://127.0.0.1:8766)');
  } else {
    // 不覆盖已有的 url，只确保 enabled
    config.channels.clawke.enabled = true;
    console.log('[clawke] ✅ Enabled channels.clawke (existing url preserved)');
  }

  // 合并 plugins.entries.clawke
  if (!config.plugins) config.plugins = {};
  if (!config.plugins.entries) config.plugins.entries = {};
  config.plugins.entries.clawke = { enabled: true };
  console.log('[clawke] ✅ Enabled plugins.entries.clawke');

  fs.writeFileSync(OPENCLAW_CONFIG, JSON.stringify(config, null, 2) + '\n');
  console.log(`[clawke] ✅ Config updated: ${OPENCLAW_CONFIG}`);
}

function restartOpenClaw(): void {
  console.log('[clawke] 🔄 Restarting OpenClaw...');
  try {
    execSync('npx openclaw gateway restart', {
      stdio: 'inherit',
      timeout: 30000,
    });
    console.log('[clawke] ✅ Gateway installed and OpenClaw restarted');
  } catch {
    console.log('');
    console.log('[clawke] ⚠️  Could not restart OpenClaw automatically.');
    console.log('  Please restart manually:');
    console.log('    npx openclaw gateway restart');
  }
}

function printRemoteGuide(): void {
  console.log(`[clawke] OpenClaw not detected on this machine.
  
If OpenClaw is installed on a remote server, install the gateway manually:

  1. Copy the plugin:
     scp -r gateways/openclaw/clawke/ user@<REMOTE>:~/.openclaw/extensions/

  2. Configure OpenClaw (edit ~/.openclaw/openclaw.json on the remote server):
     {
       "channels": {
         "clawke": {
           "enabled": true,
           "url": "ws://<THIS_MACHINE_IP>:8766"
         }
       },
       "plugins": {
         "entries": {
           "clawke": { "enabled": true }
         }
       }
     }

  3. Restart OpenClaw on the remote server:
     npx openclaw gateway restart`);
}
