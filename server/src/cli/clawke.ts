#!/usr/bin/env node
/**
 * Clawke CLI 入口
 *
 * 用法：
 *   clawke gateway install                — 自动检测并安装 Gateway 插件
 *   clawke gateway update                 — 更新已配置 Gateway 插件代码 / Update configured Gateway plugin code
 *   clawke openclaw-gateway install       — 安装 Gateway 插件到本机 OpenClaw（别名）
 *   clawke server start                   — 启动 Clawke Server
 *   clawke doctor                         — 检查本机 Clawke 配置和运行状态
 *   clawke update                         — 更新 Clawke / Update Clawke
 *   clawke --version                      — 显示版本 / Show version
 *   clawke --help                         — 显示帮助
 */

import fs from 'fs';
import path from 'path';
import os from 'os';
import readline from 'readline';
import { spawn, execSync, type ChildProcess } from 'child_process';
import { resolveGatewayStartShell } from './gateway-start-config.js';
import { formatClawkeVersion, runClawkeUpdate } from './clawke-update.js';

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

  // 暂时禁用 nanobot 入口，下次需要时可恢复 — Temporarily disable the nanobot entry; restore when needed.
  // const nanobotConfig = path.join(os.homedir(), '.nanobot', 'config.json');
  // gateways.push({
  //   name: 'nanobot',
  //   displayName: 'nanobot',
  //   configPath: nanobotConfig,
  //   installFn: async () => {
  //     const { installNanobotGateway } = await import('./nanobot-gateway-installer.js');
  //     await installNanobotGateway();
  //   },
  // });

  return gateways;
}

/**
 * 交互式选择 Gateway — Interactive gateway selection
 */
async function promptGatewaySelection(gateways: GatewayInfo[]): Promise<number | null> {
  const rl = readline.createInterface({
    input: process.stdin,
    output: process.stdout,
  });

  return new Promise<number | null>((resolve) => {
    console.log('\n  Available gateways:\n');
    gateways.forEach((gw, i) => {
      const detected = fs.existsSync(gw.configPath) ? '(detected ✓)' : '(not detected)';
      console.log(`    ${i + 1}. ${gw.displayName}  ${detected}`);
    });
    console.log(`    0. Skip gateway installation`);
    console.log('');

    rl.question('  Select gateway to install [1, 0 to skip]: ', (answer) => {
      rl.close();
      const trimmed = answer.trim();
      if (trimmed === '') {
        resolve(0); // default: first
      } else if (trimmed === '0' || trimmed.toLowerCase() === 'q') {
        resolve(null);
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
    console.log(`[clawke] 🔍 Auto-detected: ${detected[0].displayName}`);
  } else if (detected.length > 1) {
    console.log(`[clawke] 🔍 Multiple agent platforms detected.`);
  } else {
    console.log(`[clawke] ⚠️  No agent platform detected locally.`);
    console.log(`[clawke] Select which gateway to install (you may need to install the agent platform first):`);
  }

  const idx = await promptGatewaySelection(gateways);
  if (idx === null) {
    console.log('[clawke] Gateway installation skipped.');
    return;
  }

  await gateways[idx].installFn();
}

// ────────────── PID 管理 ──────────────

const CLAWKE_HOME = path.join(os.homedir(), '.clawke');
const PID_FILE = path.join(CLAWKE_HOME, 'server.pid');
const FRPC_PID_FILE = path.join(CLAWKE_HOME, 'frpc.pid');

// ────────────── Gateway 进程管理 ──────────────

const gatewayChildren: ChildProcess[] = [];

interface GatewayInstance {
  id: string;
  start_shell?: string;
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

function terminateGatewayProcess(pid: number, signal: NodeJS.Signals = 'SIGTERM'): void {
  if (process.platform !== 'win32') {
    try {
      process.kill(-pid, signal);
      return;
    } catch {}
  }
  try { process.kill(pid, signal); } catch {}
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

function isFrpcProcess(pid: number): boolean {
  try {
    const cmd = execSync(`ps -p ${pid} -o command=`, { encoding: 'utf-8' }).trim();
    return cmd.includes('/frpc') || cmd.endsWith('frpc') || cmd.includes(' frpc ');
  } catch {
    return false;
  }
}

function stopFrpcFromPidFile(): void {
  try {
    const pid = parseInt(fs.readFileSync(FRPC_PID_FILE, 'utf-8').trim(), 10);
    if (!isNaN(pid) && isProcessAlive(pid) && isFrpcProcess(pid)) {
      try { process.kill(pid, 'SIGTERM'); } catch {}
    }
  } catch {}
  try { fs.unlinkSync(FRPC_PID_FILE); } catch {}
}

function getGatewayCommandNeedles(gw: GatewayInstance): string[] {
  const startShell = resolveGatewayStartShell(gw);
  if (!startShell) return [];
  const needles = new Set<string>([startShell]);
  for (const match of startShell.matchAll(/\/[^\s"'`]+\/run\.py/g)) {
    needles.add(match[0]);
  }
  return Array.from(needles).filter(needle => needle.length > 8);
}

function findGatewayProcessPids(gw: GatewayInstance): number[] {
  if (process.platform === 'win32') return [];
  const needles = getGatewayCommandNeedles(gw);
  if (needles.length === 0) return [];
  try {
    const output = execSync('ps -eo pid=,command=', { encoding: 'utf-8' });
    const pids: number[] = [];
    for (const line of output.split('\n')) {
      const trimmed = line.trim();
      const match = trimmed.match(/^(\d+)\s+(.+)$/);
      if (!match) continue;
      const pid = Number(match[1]);
      const commandLine = match[2];
      if (!Number.isFinite(pid) || pid === process.pid) continue;
      if (needles.some(needle => commandLine.includes(needle))) {
        pids.push(pid);
      }
    }
    return pids;
  } catch {
    return [];
  }
}

async function startGateways(): Promise<void> {
  const instances = loadGatewayInstances();
  if (instances.length === 0) return;

  console.log(`[clawke] 🔌 Starting ${instances.length} gateway(s)...`);

  for (const gw of instances) {
    const startShell = resolveGatewayStartShell(gw);
    if (!startShell) {
      // 外部接入型 Gateway 没有本地启动命令，只需等待它主动连接。 — Externally managed gateways have no local start command; wait for inbound connection.
      console.log(`[clawke] ℹ️  ${gw.id} gateway has no start_shell; waiting for external connection`);
      removeGatewayPid(gw.id);
      continue;
    }

    // Kill old process if running (code may have been updated)
    const oldPid = readGatewayPid(gw.id);
    if (oldPid && isProcessAlive(oldPid)) {
      if (!isGatewayProcess(oldPid, gw.id)) {
        console.warn(`[clawke] ⚠️ PID ${oldPid} alive but not ${gw.id} gateway, skipping kill`);
        removeGatewayPid(gw.id);
      } else {
        console.log(`[clawke] 🔄 Killing old ${gw.id} gateway (PID ${oldPid})...`);
        terminateGatewayProcess(oldPid);
        // Brief wait for graceful shutdown
        let waited = 0;
        while (isProcessAlive(oldPid) && waited < 3000) {
          await new Promise(r => setTimeout(r, 200));
          waited += 200;
        }
        if (isProcessAlive(oldPid)) {
          terminateGatewayProcess(oldPid, 'SIGKILL');
        }
        removeGatewayPid(gw.id);
      }
    }

    // 通过 shell 启动，正确处理含空格路径和引号参数 — Use shell to handle spaces/quotes in paths
    const child = spawn(startShell, [], {
      stdio: ['ignore', 'pipe', 'pipe'],
      detached: process.platform !== 'win32',
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
      console.error(`[clawke] ❌ Failed to start ${gw.id} gateway: ${startShell}`);
    }
  }
}

function stopAllGateways(): void {
  const stopped = new Set<number>();

  // Kill tracked child processes
  for (const child of gatewayChildren) {
    if (child.pid && isProcessAlive(child.pid) && !stopped.has(child.pid)) {
      terminateGatewayProcess(child.pid);
      stopped.add(child.pid);
    }
  }

  // Also kill by PID file (in case we didn't spawn them)
  const instances = loadGatewayInstances();
  for (const gw of instances) {
    const pid = readGatewayPid(gw.id);
    if (pid && isProcessAlive(pid) && !stopped.has(pid)) {
      terminateGatewayProcess(pid);
      stopped.add(pid);
    }
    for (const orphanPid of findGatewayProcessPids(gw)) {
      if (isProcessAlive(orphanPid) && !stopped.has(orphanPid)) {
        terminateGatewayProcess(orphanPid);
        stopped.add(orphanPid);
      }
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
  } catch (err: any) {
    // EPERM 说明进程存在但当前上下文无权发送信号 — EPERM means the process exists but cannot be signalled here.
    return err?.code === 'EPERM';
  }
}

function removePidFile(expectedPid?: number): void {
  if (expectedPid !== undefined) {
    const currentPid = readPid();
    if (currentPid !== expectedPid) return;
  }
  try { fs.unlinkSync(PID_FILE); } catch {}
}

// ────────────── Server 命令 ──────────────

async function serverStart(): Promise<void> {
  let serverStartupStarted = false;

  // 检查是否已有实例在运行 — Check if already running
  const existingPid = readPid();
  if (existingPid && isProcessAlive(existingPid)) {
    console.error(`[clawke] ⚠️  Server already running (PID ${existingPid})`);
    console.error('[clawke] Use "clawke server stop" to stop it first, or "clawke server restart".');
    process.exit(1);
  } else if (existingPid) {
    removePidFile(existingPid);
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
  const cleanup = () => { stopAllGateways(); stopFrpcFromPidFile(); removePidFile(process.pid); };
  process.on('exit', cleanup);
  process.on('SIGINT', () => { cleanup(); if (!serverStartupStarted) process.exit(0); });
  process.on('SIGTERM', () => { cleanup(); if (!serverStartupStarted) process.exit(0); });

  // 等待 server ready 后再启动 Gateway — Start gateways only after server is ready.
  serverStartupStarted = true;
  const { startClawkeServer } = await import('../index.js');
  await startClawkeServer();
  await startGateways();
}

function serverStop(): void {
  stopAllGateways();
  stopFrpcFromPidFile();

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
  stopAllGateways();
  stopFrpcFromPidFile();
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
  if (command === '--version' || command === '-V' || command === 'version') {
    console.log(formatClawkeVersion());

  } else if (command === 'update') {
    const code = runClawkeUpdate({ checkOnly: args.includes('--check') });
    if (code !== 0) process.exit(code);

  } else if (command === 'doctor') {
    const { runClawkeDoctor } = await import('./clawke-doctor.js');
    const result = runClawkeDoctor();
    if (result.errorCount > 0) process.exit(1);

  // 统一入口：clawke gateway install
  } else if (command === 'gateway' && subCommand === 'install') {
    await installGateway();

  } else if (command === 'gateway' && subCommand === 'update') {
    const { runGatewayUpdate } = await import('./gateway-updater.js');
    const result = runGatewayUpdate({ localOnly: args.includes('--local-only') });
    if (result !== 0) process.exit(result);

  // 旧命令别名兼容 — Legacy command aliases
  } else if (command === 'openclaw-gateway' && subCommand === 'install') {
    const { installOpenClawGateway } = await import('./openclaw-gateway-installer.js');
    await installOpenClawGateway();

  // 暂时禁用 nanobot 入口，下次需要时可恢复 — Temporarily disable the nanobot entry; restore when needed.
  // } else if (command === 'nanobot-gateway' && subCommand === 'install') {
  //   const { installNanobotGateway } = await import('./nanobot-gateway-installer.js');
  //   await installNanobotGateway();

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
    update                     Update Clawke to the latest version
    update --check             Check for updates without installing
    doctor                     Check local Clawke setup and runtime status
    server start               Start Clawke Server
    server stop                Stop Clawke Server
    server restart             Restart Clawke Server
    server status              Check if server is running
    gateway install            Auto-detect and install gateway plugin
    gateway update             Update configured gateway plugin code (no restart)

  Legacy Commands:
    openclaw-gateway install   Install OpenClaw gateway (same as gateway install)
    hermes-gateway install     Install Hermes gateway

  Options:
    --version, -V              Show version and exit
    --help, -h                 Show this help message

  Quick Start:
    clawke gateway install     # Connect to your AI agent
    clawke gateway update      # Update installed gateway code, no restart
    clawke server start        # Start the server
`);
}

main().catch((err) => {
  console.error('[clawke] Fatal error:', err.message);
  process.exit(1);
});
