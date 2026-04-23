/**
 * Hermes Gateway 安装器
 *
 * 检测本机 Hermes → 检测 Python 环境 → 注册 gateway 到 clawke.json
 * 不拷贝文件，就地运行（start_shell 指向仓库中的 run.py）
 */
import fs from 'fs';
import path from 'path';
import os from 'os';
import { execSync } from 'child_process';

const CLAWKE_HOME = path.join(os.homedir(), '.clawke');
const CLAWKE_CONFIG = path.join(CLAWKE_HOME, 'clawke.json');
const HERMES_HOME = path.join(os.homedir(), '.hermes');

/** 获取仓库中 Gateway 源路径 */
function getGatewayDir(): string {
  // dist/cli/hermes-gateway-installer.js → server/ → ../gateways/hermes/clawke/
  return path.join(__dirname, '..', '..', '..', 'gateways', 'hermes', 'clawke');
}

/** 检测 Hermes 安装 */
function detectHermes(): boolean {
  // 方式 1：~/.hermes/ 目录存在
  if (fs.existsSync(HERMES_HOME)) {
    return true;
  }
  // 方式 2：which hermes
  try {
    execSync('which hermes', { stdio: 'ignore' });
    return true;
  } catch {
    return false;
  }
}

/**
 * 搜索 hermes-agent 目录（参考 webui/bootstrap.py 的 discover_agent_dir）
 */
function discoverAgentDir(): string | null {
  const candidates = [
    process.env.HERMES_WEBUI_AGENT_DIR,
    path.join(HERMES_HOME, 'hermes-agent'),
    path.join(getGatewayDir(), '..', '..', '..', '..', 'hermes-agent'),  // 兄弟目录
    path.join(os.homedir(), 'hermes-agent'),
  ];

  for (const raw of candidates) {
    if (!raw) continue;
    const candidate = path.resolve(raw);
    if (fs.existsSync(candidate) && fs.existsSync(path.join(candidate, 'run_agent.py'))) {
      return candidate;
    }
  }
  return null;
}

/**
 * 搜索 Python 解释器（参考 webui/bootstrap.py 的 discover_launcher_python）
 */
function discoverPython(agentDir: string | null): string | null {
  // 优先级 1：环境变量
  if (process.env.HERMES_WEBUI_PYTHON) {
    return process.env.HERMES_WEBUI_PYTHON;
  }

  // 优先级 2：agent 目录下的 venv
  if (agentDir) {
    const venvPython = path.join(agentDir, 'venv', 'bin', 'python');
    if (fs.existsSync(venvPython)) {
      return venvPython;
    }
    const venvPython3 = path.join(agentDir, 'venv', 'bin', 'python3');
    if (fs.existsSync(venvPython3)) {
      return venvPython3;
    }
  }

  // 优先级 3：系统 python3
  try {
    execSync('which python3', { stdio: 'ignore' });
    return 'python3';
  } catch {
    return null;
  }
}

/** 检查 Python 环境中是否有 websockets */
function checkWebsockets(pythonExe: string): boolean {
  try {
    execSync(`${pythonExe} -c "import websockets"`, { stdio: 'ignore' });
    return true;
  } catch {
    return false;
  }
}

/** 检查 Python 环境中是否能导入 AIAgent */
function checkAIAgent(pythonExe: string): boolean {
  try {
    execSync(`${pythonExe} -c "from run_agent import AIAgent"`, {
      stdio: 'ignore',
      env: { ...process.env },
    });
    return true;
  } catch {
    return false;
  }
}

/** 合并 gateway 配置到 clawke.json */
function mergeGatewayConfig(startShell: string): void {
  let config: Record<string, any> = {};

  // 读取现有配置
  if (fs.existsSync(CLAWKE_CONFIG)) {
    try {
      config = JSON.parse(fs.readFileSync(CLAWKE_CONFIG, 'utf-8'));
    } catch (err: any) {
      console.error(`[clawke] ⚠️  Could not parse ${CLAWKE_CONFIG}: ${err.message}`);
    }

    // 备份
    try {
      fs.copyFileSync(CLAWKE_CONFIG, CLAWKE_CONFIG + '.bak');
      console.log(`[clawke] 📋 Config backed up: ${CLAWKE_CONFIG}.bak`);
    } catch {}
  }

  // 确保 gateways 结构存在
  if (!config.gateways) {
    config.gateways = {};
  }
  if (!config.gateways.hermes) {
    config.gateways.hermes = [];
  }

  // 检查是否已注册
  const existing = config.gateways.hermes.find((gw: any) => gw.id === 'hermes');
  if (existing) {
    // 更新 start_shell（路径可能变了）
    existing.start_shell = startShell;
    console.log('[clawke] 🔄 Updated existing hermes gateway config');
  } else {
    config.gateways.hermes.push({
      id: 'hermes',
      start_shell: startShell,
      hermes_home: HERMES_HOME,
    });
    console.log('[clawke] ✅ Registered hermes gateway');
  }

  // 写回
  fs.mkdirSync(CLAWKE_HOME, { recursive: true });
  fs.writeFileSync(CLAWKE_CONFIG, JSON.stringify(config, null, 2) + '\n');
  console.log(`[clawke] ✅ Config written: ${CLAWKE_CONFIG}`);
}


export async function installHermesGateway(): Promise<void> {
  console.log('[clawke] 🔍 Detecting Hermes installation...');

  // Step 1: 检测 Hermes
  if (!detectHermes()) {
    console.error('[clawke] ❌ Hermes not found.');
    console.error('  Install Hermes first:');
    console.error('    curl -fsSL https://raw.githubusercontent.com/NousResearch/hermes-agent/main/scripts/install.sh | bash');
    console.error('  Or ensure ~/.hermes/ exists.');
    process.exit(1);
  }
  console.log(`[clawke] ✅ Hermes detected: ${HERMES_HOME}`);

  // Step 2: 检测 Gateway 源文件
  const gatewayDir = getGatewayDir();
  if (!fs.existsSync(path.join(gatewayDir, 'run.py'))) {
    console.error(`[clawke] ❌ Gateway source not found: ${gatewayDir}`);
    console.error('[clawke] Please run this command from the Clawke project root.');
    process.exit(1);
  }
  console.log(`[clawke] ✅ Gateway source: ${gatewayDir}`);

  // Step 3: 检测 Python 环境
  const agentDir = discoverAgentDir();
  if (agentDir) {
    console.log(`[clawke] ✅ hermes-agent found: ${agentDir}`);
  } else {
    console.log('[clawke] ⚠️  hermes-agent directory not found (will rely on PYTHONPATH)');
  }

  const pythonExe = discoverPython(agentDir);
  if (!pythonExe) {
    console.error('[clawke] ❌ Python not found. Install Python 3.10+ first.');
    process.exit(1);
  }
  console.log(`[clawke] ✅ Python: ${pythonExe}`);

  // Step 4: 检查 websockets 依赖
  if (!checkWebsockets(pythonExe)) {
    console.log('[clawke] 📦 Installing websockets...');
    try {
      execSync(`${pythonExe} -m pip install websockets>=12.0`, { stdio: 'inherit' });
    } catch {
      console.error('[clawke] ⚠️  Could not install websockets. Please run manually:');
      console.error(`  ${pythonExe} -m pip install websockets>=12.0`);
    }
  }

  // Step 5: 注册 gateway（就地运行，不拷贝文件）
  const runScript = path.join(gatewayDir, 'run.py');
  const startShell = `${pythonExe} ${runScript}`;
  mergeGatewayConfig(startShell);

  console.log('');
  console.log('[clawke] ✅ Hermes Gateway installed successfully!');
  console.log('');
  console.log('  Start everything:');
  console.log('    npx clawke server start');
  console.log('');
  console.log('  Or start gateway manually:');
  console.log(`    ${startShell}`);
  console.log('');
}
