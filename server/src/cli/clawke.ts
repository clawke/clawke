#!/usr/bin/env node
/**
 * Clawke CLI 入口
 *
 * 用法：
 *   clawke gateway install                — 自动检测并安装 Gateway 插件
 *   clawke openclaw-gateway install       — 安装 Gateway 插件到本机 OpenClaw（别名）
 *   clawke nanobot-gateway install        — 安装 Clawke channel 到本机 nanobot（别名）
 *   clawke server start                   — 启动 Clawke Server
 *   clawke --help                         — 显示帮助
 */

import fs from 'fs';
import path from 'path';
import os from 'os';
import readline from 'readline';
import { spawn, execSync, type ChildProcess } from 'child_process';

const args = process.argv.slice(2);
const command = args[0];
const subCommand = args[1];

// ────────────── Gateway 检测定义 ──────────────

interface GatewayInfo {
  name: string;
  displayName: string;
  configPath: string;
  installFn: () => Promise<void>;
}

/**
 * 扫描本机已安装的 Agent 平台，返回可用 gateway 列表
 * Scan locally installed agent platforms and return available gateways
 */
function detectAvailableGateways(): GatewayInfo[] {
  const gateways: GatewayInfo[] = [];

  // OpenClaw: 检查 ~/.openclaw/openclaw.json
  const openclawConfig = path.join(os.homedir(), '.openclaw', 'openclaw.json');
  gateways.push({
    name: 'openclaw',
    displayName: 'OpenClaw',
    configPath: openclawConfig,
    installFn: async () => {
      const { installOpenClawGateway } = await import('./openclaw-gateway-installer.js');
      await installOpenClawGateway();
    },
  });

  // nanobot: 检查 ~/.nanobot/config.json
  const nanobotConfig = path.join(os.homedir(), '.nanobot', 'config.json');
  gateways.push({
    name: 'nanobot',
    displayName: 'nanobot',
    configPath: nanobotConfig,
    installFn: async () => {
      const { installNanobotGateway } = await import('./nanobot-gateway-installer.js');
      await installNanobotGateway();
    },
  });

  // Hermes: 检查 ~/.hermes/
  const hermesHome = path.join(os.homedir(), '.hermes');
  gateways.push({
    name: 'hermes',
    displayName: 'Hermes',
    configPath: hermesHome,
    installFn: async () => {
      const { installHermesGateway } = await import('./hermes-gateway-installer.js');
      await installHermesGateway();
    },
  });

  return gateways;
}

/**
 * 交互式选择 Gateway — Interactive gateway selection
 */
async function promptGatewaySelection(gateways: GatewayInfo[]): Promise<number> {
  const rl = readline.createInterface({
    input: process.stdin,
    output: process.stdout,
  });

  return new Promise<number>((resolve) => {
    console.log('\n  Available gateways:\n');
    gateways.forEach((gw, i) => {
      const detected = fs.existsSync(gw.configPath) ? '(detected ✓)' : '(not detected)';
      console.log(`    ${i + 1}. ${gw.displayName}  ${detected}`);
    });
    console.log('');

    rl.question('  Select gateway to install [1]: ', (answer) => {
      rl.close();
      const trimmed = answer.trim();
      if (trimmed === '') {
        resolve(0); // default: first
      } else {
        const idx = parseInt(trimmed, 10) - 1;
        if (isNaN(idx) || idx < 0 || idx >= gateways.length) {
          console.error(`[clawke] ❌ Invalid selection: ${trimmed}`);
          process.exit(1);
        }
        resolve(idx);
      }
    });
  });
}

/**
 * 统一 gateway install 入口 — Unified gateway install entry
 */
async function installGateway(): Promise<void> {
  const gateways = detectAvailableGateways();

  // 检测哪些 agent 平台已安装 — Check which agent platforms are installed
  const detected = gateways.filter(gw => fs.existsSync(gw.configPath));

  if (detected.length === 1) {
    // 只有一个平台检测到，直接安装 — Only one platform detected, install directly
    console.log(`[clawke] 🔍 Auto-detected: ${detected[0].displayName}`);
    await detected[0].installFn();

  } else if (detected.length > 1) {
    // 多个平台检测到，让用户选择 — Multiple platforms detected, let user choose
    console.log(`[clawke] 🔍 Multiple agent platforms detected.`);
    const idx = await promptGatewaySelection(detected);
    await detected[idx].installFn();

  } else {
    // 没有检测到任何平台，展示所有选项让用户选 — None detected, show all options
    console.log(`[clawke] ⚠️  No agent platform detected locally.`);
    console.log(`[clawke] Select which gateway to install (you may need to install the agent platform first):`);
    const idx = await promptGatewaySelection(gateways);
    await gateways[idx].installFn();
  }
}

// ────────────── PID 管理 ──────────────

const CLAWKE_HOME = path.join(os.homedir(), '.clawke');
const PID_FILE = path.join(CLAWKE_HOME, 'server.pid');

// ────────────── Gateway 进程管理 ──────────────

const gatewayChildren: ChildProcess[] = [];

interface GatewayInstance {
  id: string;
  start_shell: string;
  hermes_home?: string;
}

function loadGatewayInstances(): GatewayInstance[] {
  const configPath = path.join(CLAWKE_HOME, 'clawke.json');
  if (!fs.existsSync(configPath)) return [];
  try {
    const config = JSON.parse(fs.readFileSync(configPath, 'utf-8'));
    if (!config.gateways) return [];
    const instances: GatewayInstance[] = [];
    for (const [, list] of Object.entries(config.gateways)) {
      if (Array.isArray(list)) {
        instances.push(...(list as GatewayInstance[]));
      }
    }
    return instances;
  } catch {
    return [];
  }
}

function readGatewayPid(id: string): number | null {
  try {
    const pidFile = path.join(CLAWKE_HOME, `${id}-gateway.pid`);
    const pid = parseInt(fs.readFileSync(pidFile, 'utf-8').trim(), 10);
    return isNaN(pid) ? null : pid;
  } catch {
    return null;
  }
}

function writeGatewayPid(id: string, pid: number): void {
  fs.writeFileSync(path.join(CLAWKE_HOME, `${id}-gateway.pid`), String(pid));
}

function removeGatewayPid(id: string): void {
  try { fs.unlinkSync(path.join(CLAWKE_HOME, `${id}-gateway.pid`)); } catch {}
}

// 验证 PID 是否属于目标 gateway 进程，防止误杀 — Verify PID belongs to gateway before kill
function isGatewayProcess(pid: number, gwId: string): boolean {
  try {
    const cmd = execSync(`ps -p ${pid} -o command=`, { encoding: 'utf-8' }).trim();
    return cmd.includes(gwId) || cmd.includes('gateway') || cmd.includes('run.py') || cmd.includes('clawke');
  } catch {
    return false; // 进程已退出 — Process already exited
  }
}

async function startGateways(): Promise<void> {
  const instances = loadGatewayInstances();
  if (instances.length === 0) return;

  console.log(`[clawke] 🔌 Starting ${instances.length} gateway(s)...`);

  for (const gw of instances) {
    // Kill old process if running (code may have been updated)
    const oldPid = readGatewayPid(gw.id);
    if (oldPid && isProcessAlive(oldPid)) {
      if (!isGatewayProcess(oldPid, gw.id)) {
        console.warn(`[clawke] ⚠️ PID ${oldPid} alive but not ${gw.id} gateway, skipping kill`);
        removeGatewayPid(gw.id);
      } else {
        console.log(`[clawke] 🔄 Killing old ${gw.id} gateway (PID ${oldPid})...`);
        try { process.kill(oldPid, 'SIGTERM'); } catch {}
        // Brief wait for graceful shutdown
        let waited = 0;
        while (isProcessAlive(oldPid) && waited < 3000) {
          await new Promise(r => setTimeout(r, 200));
          waited += 200;
        }
        if (isProcessAlive(oldPid)) {
          try { process.kill(oldPid, 'SIGKILL'); } catch {}
        }
        removeGatewayPid(gw.id);
      }
    }

    // 通过 shell 启动，正确处理含空格路径和引号参数 — Use shell to handle spaces/quotes in paths
    const child = spawn(gw.start_shell, [], {
      stdio: ['ignore', 'pipe', 'pipe'],
      detached: false,
      shell: true,
    });

    if (child.pid) {
      writeGatewayPid(gw.id, child.pid);
      gatewayChildren.push(child);
      console.log(`[clawke] ✅ ${gw.id} gateway started (PID ${child.pid})`);

      // Pipe gateway output to server console
      child.stdout?.on('data', (data: Buffer) => {
        process.stdout.write(`[${gw.id}] ${data}`);
      });
      child.stderr?.on('data', (data: Buffer) => {
        process.stderr.write(`[${gw.id}] ${data}`);
      });

      child.on('exit', (code) => {
        console.log(`[clawke] ⚠️  ${gw.id} gateway exited (code ${code})`);
        removeGatewayPid(gw.id);
      });

      // 兜底：命令不存在等场景的 spawn 错误 — Catch spawn errors (e.g. command not found)
      child.on('error', (err) => {
        console.error(`[clawke] ❌ ${gw.id} gateway spawn error: ${err.message}`);
        removeGatewayPid(gw.id);
      });
    } else {
      console.error(`[clawke] ❌ Failed to start ${gw.id} gateway: ${gw.start_shell}`);
    }
  }
}

function stopAllGateways(): void {
  // Kill tracked child processes
  for (const child of gatewayChildren) {
    if (child.pid && isProcessAlive(child.pid)) {
      try { child.kill('SIGTERM'); } catch {}
    }
  }

  // Also kill by PID file (in case we didn't spawn them)
  const instances = loadGatewayInstances();
  for (const gw of instances) {
    const pid = readGatewayPid(gw.id);
    if (pid && isProcessAlive(pid)) {
      try { process.kill(pid, 'SIGTERM'); } catch {}
    }
    removeGatewayPid(gw.id);
  }
}

function writePid(): void {
  fs.mkdirSync(CLAWKE_HOME, { recursive: true });
  fs.writeFileSync(PID_FILE, String(process.pid));
}

function readPid(): number | null {
  try {
    const pid = parseInt(fs.readFileSync(PID_FILE, 'utf-8').trim(), 10);
    return isNaN(pid) ? null : pid;
  } catch {
    return null;
  }
}

function isProcessAlive(pid: number): boolean {
  try {
    process.kill(pid, 0); // signal 0 = check existence
    return true;
  } catch {
    return false;
  }
}

function removePidFile(): void {
  try { fs.unlinkSync(PID_FILE); } catch {}
}

// ────────────── Server 命令 ──────────────

async function serverStart(): Promise<void> {
  // 检查是否已有实例在运行 — Check if already running
  const existingPid = readPid();
  if (existingPid && isProcessAlive(existingPid)) {
    console.error(`[clawke] ⚠️  Server already running (PID ${existingPid})`);
    console.error('[clawke] Use "clawke server stop" to stop it first, or "clawke server restart".');
    process.exit(1);
  }

  // 自动编译 TypeScript（增量模式，没改动时秒完成）— Auto-build before start
  const serverDir = path.join(__dirname, '..', '..');
  const tsconfigPath = path.join(serverDir, 'tsconfig.json');
  if (fs.existsSync(tsconfigPath)) {
    const { execSync } = await import('child_process');
    try {
      execSync('npx tsc', { cwd: serverDir, stdio: 'inherit' });
    } catch {
      console.error('[clawke] ⚠️  TypeScript build failed, starting with existing dist...');
    }
  }

  // 写入 PID 文件 — Write PID file
  writePid();

  // 进程退出时清理 PID 文件 + Gateway 子进程 — Cleanup on exit
  const cleanup = () => { stopAllGateways(); removePidFile(); };
  process.on('exit', cleanup);
  process.on('SIGINT', () => { cleanup(); process.exit(0); });
  process.on('SIGTERM', () => { cleanup(); process.exit(0); });

  // 加载 server 入口 — Load server entry
  await import('../index.js');

  // Server 启动后启动 Gateway — Start gateways after server is ready
  // 延迟 1s 确保 WS 端口就绪
  setTimeout(async () => {
    await startGateways();
  }, 1000);
}

function serverStop(): void {
  const pid = readPid();
  if (!pid) {
    console.log('[clawke] No PID file found. Server may not be running.');
    return;
  }

  if (!isProcessAlive(pid)) {
    console.log(`[clawke] Process ${pid} not found (stale PID file). Cleaning up.`);
    removePidFile();
    return;
  }

  // 先停 Gateway
  stopAllGateways();

  console.log(`[clawke] Stopping server (PID ${pid})...`);
  try {
    process.kill(pid, 'SIGTERM');
  } catch (err: any) {
    console.error(`[clawke] ❌ Failed to stop: ${err.message}`);
    process.exit(1);
  }

  // 等待进程退出（最多 5 秒）— Wait up to 5s for graceful shutdown
  let waited = 0;
  const interval = 200;
  const maxWait = 5000;
  const check = setInterval(() => {
    waited += interval;
    if (!isProcessAlive(pid)) {
      clearInterval(check);
      removePidFile();
      console.log('[clawke] ✅ Server stopped.');
    } else if (waited >= maxWait) {
      clearInterval(check);
      console.log(`[clawke] ⚠️  Process ${pid} didn't exit gracefully, sending SIGKILL...`);
      try { process.kill(pid, 'SIGKILL'); } catch {}
      removePidFile();
      console.log('[clawke] ✅ Server killed.');
    }
  }, interval);
}

function serverStatus(): void {
  const pid = readPid();
  if (!pid) {
    console.log('[clawke] Server is not running (no PID file).');
    return;
  }

  if (isProcessAlive(pid)) {
    console.log(`[clawke] ✅ Server is running (PID ${pid}).`);
  } else {
    console.log(`[clawke] Server is not running (stale PID ${pid}). Cleaning up.`);
    removePidFile();
  }
}

async function serverRestart(): Promise<void> {
  const pid = readPid();
  if (pid && isProcessAlive(pid)) {
    console.log(`[clawke] Stopping server (PID ${pid})...`);
    process.kill(pid, 'SIGTERM');

    // 等待旧进程退出 — Wait for old process to exit
    let waited = 0;
    while (isProcessAlive(pid) && waited < 5000) {
      await new Promise(r => setTimeout(r, 200));
      waited += 200;
    }
    if (isProcessAlive(pid)) {
      try { process.kill(pid, 'SIGKILL'); } catch {}
    }
    removePidFile();
    console.log('[clawke] ✅ Old server stopped.');
  }

  console.log('[clawke] Starting server...');
  await serverStart();
}

// ────────────── Main ──────────────

async function main(): Promise<void> {
  // 统一入口：clawke gateway install
  if (command === 'gateway' && subCommand === 'install') {
    await installGateway();

  // 旧命令别名兼容 — Legacy command aliases
  } else if (command === 'openclaw-gateway' && subCommand === 'install') {
    const { installOpenClawGateway } = await import('./openclaw-gateway-installer.js');
    await installOpenClawGateway();

  } else if (command === 'nanobot-gateway' && subCommand === 'install') {
    const { installNanobotGateway } = await import('./nanobot-gateway-installer.js');
    await installNanobotGateway();

  } else if (command === 'hermes-gateway' && subCommand === 'install') {
    const { installHermesGateway } = await import('./hermes-gateway-installer.js');
    await installHermesGateway();

  } else if (command === 'server') {
    switch (subCommand) {
      case 'start':   await serverStart(); break;
      case 'stop':    serverStop(); break;
      case 'restart': await serverRestart(); break;
      case 'status':  serverStatus(); break;
      default:
        console.error(`[clawke] Unknown server command: ${subCommand}`);
        console.error('  Available: start, stop, restart, status');
        process.exit(1);
    }

  } else {
    printHelp();
    process.exit(command === '--help' || command === '-h' ? 0 : 1);
  }
}

function printHelp(): void {
  console.log(`
  Clawke CLI

  Usage:
    clawke <command>

  Commands:
    server start               Start Clawke Server
    server stop                Stop Clawke Server
    server restart             Restart Clawke Server
    server status              Check if server is running
    gateway install            Auto-detect and install gateway plugin

  Legacy Commands:
    openclaw-gateway install   Install OpenClaw gateway (same as gateway install)
    nanobot-gateway install    Install nanobot gateway (same as gateway install)
    hermes-gateway install     Install Hermes gateway

  Options:
    --help, -h                 Show this help message

  Quick Start:
    clawke gateway install     # Connect to your AI agent
    clawke server start        # Start the server
`);
}

main().catch((err) => {
  console.error('[clawke] Fatal error:', err.message);
  process.exit(1);
});

