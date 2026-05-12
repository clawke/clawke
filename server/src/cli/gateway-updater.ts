import fs from 'node:fs';
import os from 'node:os';
import path from 'node:path';
import { spawn, spawnSync } from 'node:child_process';
import { mergeOpenClawConfigFile } from './openclaw-gateway-installer.js';

const DEFAULT_PROJECT_ROOT = path.resolve(__dirname, '..', '..', '..');
const DEFAULT_CLAWKE_HOME = process.env.CLAWKE_DATA_DIR || path.join(os.homedir(), '.clawke');
const DEFAULT_CLAWKE_CONFIG = path.join(DEFAULT_CLAWKE_HOME, 'clawke.json');
const DEFAULT_OPENCLAW_HOME = path.join(os.homedir(), '.openclaw');

interface WritableLike {
  write(chunk: string): unknown;
}

interface GatewayUpdateOptions {
  projectRoot?: string;
  clawkeHome?: string;
  clawkeConfigPath?: string;
  openclawHome?: string;
  localOnly?: boolean;
  restartUpdatedGateways?: boolean;
  spawnProcess?: typeof spawn;
  spawnSyncProcess?: typeof spawnSync;
  stdout?: WritableLike;
  stderr?: WritableLike;
}

interface GatewayEntry {
  id?: unknown;
  start_shell?: unknown;
  [key: string]: unknown;
}

interface ConfiguredGateway {
  type: string;
  entry: GatewayEntry;
}

interface GatewayUpdateResult {
  ok: boolean;
  updated: boolean;
}

interface ClawkeConfig {
  gateways?: Record<string, unknown>;
  [key: string]: unknown;
}

interface RestartContext {
  projectRoot: string;
  clawkeHome: string;
  restartUpdatedGateways: boolean;
  spawnProcess: typeof spawn;
  spawnSyncProcess: typeof spawnSync;
  stdout: WritableLike;
  stderr: WritableLike;
}

function readConfig(configPath: string, stderr: WritableLike): ClawkeConfig | null {
  if (!fs.existsSync(configPath)) return null;
  try {
    return JSON.parse(fs.readFileSync(configPath, 'utf-8')) as ClawkeConfig;
  } catch (err: any) {
    stderr.write(`[clawke] ❌ Could not parse ${configPath}: ${err.message}\n`);
    return null;
  }
}

function writeConfig(configPath: string, config: ClawkeConfig): void {
  try {
    fs.copyFileSync(configPath, `${configPath}.bak`);
  } catch {}
  fs.writeFileSync(configPath, JSON.stringify(config, null, 2) + '\n');
}

function collectConfiguredGateways(config: ClawkeConfig | null): ConfiguredGateway[] {
  const gateways = config?.gateways;
  if (!gateways || typeof gateways !== 'object') return [];

  const result: ConfiguredGateway[] = [];
  for (const [type, value] of Object.entries(gateways)) {
    if (!Array.isArray(value)) continue;
    for (const entry of value) {
      if (entry && typeof entry === 'object' && !Array.isArray(entry)) {
        result.push({ type, entry: entry as GatewayEntry });
      }
    }
  }
  return result;
}

function replaceRunScript(startShell: string, runScript: string): string | null {
  const match = startShell.match(/^(.*\s)\/[^\s"'`]*run\.py\s*$/);
  if (!match) return null;
  return `${match[1]}${runScript}`;
}

function readPidFile(pidPath: string): number | null {
  try {
    const pid = Number.parseInt(fs.readFileSync(pidPath, 'utf-8').trim(), 10);
    return Number.isFinite(pid) ? pid : null;
  } catch {
    return null;
  }
}

function isProcessAlive(pid: number): boolean {
  try {
    process.kill(pid, 0);
    return true;
  } catch {
    return false;
  }
}

function printHermesRestartHint(stdout: WritableLike): void {
  stdout.write('[clawke] ℹ️ Hermes gateway updated. Next `clawke server start` will load it.\n');
}

function printOpenClawRestartHint(stdout: WritableLike): void {
  stdout.write('[clawke] ℹ️ OpenClaw gateway updated. Restart OpenClaw to load it: openclaw gateway restart\n');
}

function restartHermesGateway(context: RestartContext): void {
  if (!context.restartUpdatedGateways) {
    printHermesRestartHint(context.stdout);
    return;
  }

  const pid = readPidFile(path.join(context.clawkeHome, 'server.pid'));
  if (!pid || !isProcessAlive(pid)) {
    printHermesRestartHint(context.stdout);
    return;
  }

  const cliPath = path.join(context.projectRoot, 'server', 'dist', 'cli', 'clawke.js');
  if (!fs.existsSync(cliPath)) {
    context.stderr.write('[clawke] ⚠️ Could not restart Clawke Server automatically. Restart manually: clawke server restart\n');
    return;
  }

  try {
    const child = context.spawnProcess(process.execPath, [cliPath, 'server', 'restart'], {
      cwd: path.join(context.projectRoot, 'server'),
      detached: true,
      stdio: 'ignore',
    });
    child.unref();
    context.stdout.write('[clawke] 🔄 Restarting Clawke Server to reload the updated Hermes gateway...\n');
  } catch {
    context.stderr.write('[clawke] ⚠️ Could not restart Clawke Server automatically. Restart manually: clawke server restart\n');
  }
}

function restartOpenClawGateway(context: RestartContext): void {
  if (!context.restartUpdatedGateways) {
    printOpenClawRestartHint(context.stdout);
    return;
  }

  const which = context.spawnSyncProcess('which openclaw', { shell: true, stdio: 'ignore' });
  if (which.status !== 0) {
    printOpenClawRestartHint(context.stdout);
    return;
  }

  context.stdout.write('[clawke] 🔄 Restarting OpenClaw gateway...\n');
  try {
    const result = context.spawnSyncProcess('openclaw gateway restart', {
      shell: true,
      stdio: 'inherit',
    });
    if (result.status !== 0) {
      throw new Error(`exit code ${result.status}`);
    }
    context.stdout.write('[clawke] ✓ OpenClaw gateway restarted\n');
  } catch {
    context.stderr.write('[clawke] ⚠️ Could not restart OpenClaw automatically. Restart manually: openclaw gateway restart\n');
  }
}

function updateHermesGateway(
  projectRoot: string,
  entry: GatewayEntry,
  stdout: WritableLike,
  stderr: WritableLike,
): GatewayUpdateResult {
  const runScript = path.join(projectRoot, 'gateways', 'hermes', 'clawke', 'run.py');
  if (!fs.existsSync(runScript)) {
    stderr.write(`[clawke] ❌ Hermes gateway source not found: ${runScript}\n`);
    return { ok: false, updated: false };
  }

  if (typeof entry.start_shell === 'string') {
    const nextStartShell = replaceRunScript(entry.start_shell, runScript);
    if (nextStartShell) {
      entry.start_shell = nextStartShell;
    }
  }

  stdout.write('[clawke] ✓ hermes gateway uses in-place source; start command refreshed\n');
  return { ok: true, updated: true };
}

function updateOpenClawGateway(
  projectRoot: string,
  openclawHome: string,
  localOnly: boolean,
  spawnSyncProcess: typeof spawnSync,
  stdout: WritableLike,
  stderr: WritableLike,
): GatewayUpdateResult {
  const sourceDir = path.join(projectRoot, 'gateways', 'openclaw', 'clawke');
  const openclawConfig = path.join(openclawHome, 'openclaw.json');
  const targetDir = path.join(openclawHome, 'extensions', 'clawke');

  if (!fs.existsSync(sourceDir)) {
    stderr.write(`[clawke] ❌ OpenClaw gateway source not found: ${sourceDir}\n`);
    return { ok: false, updated: false };
  }

  if (!fs.existsSync(openclawConfig)) {
    if (localOnly) {
      stdout.write('[clawke] ⚠️ Skipping OpenClaw gateway sync: local OpenClaw install was not found.\n');
      return { ok: true, updated: false };
    }
    stderr.write('[clawke] ⚠️ OpenClaw is configured, but local OpenClaw install was not found.\n');
    stderr.write('[clawke] Remote gateway cannot be updated automatically.\n');
    stderr.write(`  scp -r ${sourceDir}/ user@<REMOTE>:~/.openclaw/extensions/clawke/\n`);
    return { ok: false, updated: false };
  }

  fs.rmSync(targetDir, { recursive: true, force: true });
  fs.mkdirSync(path.dirname(targetDir), { recursive: true });
  fs.cpSync(sourceDir, targetDir, { recursive: true });
  stdout.write(`[clawke] ✓ OpenClaw gateway synced to ${targetDir}\n`);

  if (fs.existsSync(path.join(targetDir, 'package.json'))) {
    stdout.write('[clawke] Installing OpenClaw gateway dependencies...\n');
    const result = spawnSyncProcess('npm', ['install', '--production'], {
      cwd: targetDir,
      stdio: 'inherit',
      shell: process.platform === 'win32',
    });
    if (result.status !== 0) {
      stderr.write(`[clawke] ❌ Failed to install OpenClaw gateway dependencies in ${targetDir}\n`);
      return { ok: false, updated: false };
    }
  }

  mergeOpenClawConfigFile(openclawConfig, {
    info(message) {
      stdout.write(`${message}\n`);
    },
    warn(message) {
      stderr.write(`${message}\n`);
    },
  });

  return { ok: true, updated: true };
}

export function runGatewayUpdate(options: GatewayUpdateOptions = {}): number {
  const projectRoot = options.projectRoot || DEFAULT_PROJECT_ROOT;
  const clawkeHome = options.clawkeHome || DEFAULT_CLAWKE_HOME;
  const configPath = options.clawkeConfigPath || DEFAULT_CLAWKE_CONFIG;
  const openclawHome = options.openclawHome || DEFAULT_OPENCLAW_HOME;
  const localOnly = options.localOnly === true;
  const restartUpdatedGateways = options.restartUpdatedGateways ?? !localOnly;
  const spawnProcess = options.spawnProcess || spawn;
  const spawnSyncProcess = options.spawnSyncProcess || spawnSync;
  const stdout = options.stdout || process.stdout;
  const stderr = options.stderr || process.stderr;
  const config = readConfig(configPath, stderr);
  const gateways = collectConfiguredGateways(config);

  if (!config || gateways.length === 0) {
    stdout.write('[clawke] No configured gateways found. Run `clawke gateway install` first.\n');
    return 0;
  }

  stdout.write('[clawke] Updating configured gateways...\n');

  let failed = 0;
  let changedConfig = false;
  const updatedGatewayTypes = new Set<string>();
  for (const gateway of gateways) {
    const before = JSON.stringify(gateway.entry);
    let result: GatewayUpdateResult = { ok: true, updated: false };

    if (gateway.type === 'hermes') {
      result = updateHermesGateway(projectRoot, gateway.entry, stdout, stderr);
    } else if (gateway.type === 'openclaw') {
      result = updateOpenClawGateway(projectRoot, openclawHome, localOnly, spawnSyncProcess, stdout, stderr);
    } else {
      stdout.write(`[clawke] ⚠️ Skipping unknown gateway type: ${gateway.type}\n`);
    }

    if (!result.ok) failed += 1;
    if (result.updated) updatedGatewayTypes.add(gateway.type);
    if (JSON.stringify(gateway.entry) !== before) changedConfig = true;
  }

  if (changedConfig) {
    writeConfig(configPath, config);
    stdout.write(`[clawke] ✓ Gateway config updated: ${configPath}\n`);
  }

  if (failed > 0) {
    stderr.write(`[clawke] ❌ Gateway update failed for ${failed} configured gateway(s).\n`);
    return 1;
  }

  const restartContext: RestartContext = {
    projectRoot,
    clawkeHome,
    restartUpdatedGateways,
    spawnProcess,
    spawnSyncProcess,
    stdout,
    stderr,
  };
  if (updatedGatewayTypes.has('hermes')) {
    restartHermesGateway(restartContext);
  }
  if (updatedGatewayTypes.has('openclaw')) {
    restartOpenClawGateway(restartContext);
  }

  stdout.write('[clawke] ✓ Gateway update complete\n');
  return 0;
}
