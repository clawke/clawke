import fs from 'node:fs';
import os from 'node:os';
import path from 'node:path';
import { loadConfig } from '../config.js';
import { resolveProfileContext, type ProfileContext } from '../profile.js';
import { resolveGatewayStartShell } from './gateway-start-config.js';

type DoctorStatus = 'ok' | 'warn' | 'error' | 'info';

interface DoctorCheck {
  section: string;
  status: DoctorStatus;
  message: string;
  detail?: string;
}

interface GatewayInstance {
  id?: unknown;
  type?: string;
  start_shell?: unknown;
}

interface DoctorOptions {
  clawkeHome?: string;
  profile?: string;
  homeDir?: string;
  projectRoot?: string;
  serverDir?: string;
  stdout?: NodeJS.WritableStream;
  env?: NodeJS.ProcessEnv;
}

export interface DoctorResult {
  ok: boolean;
  warningCount: number;
  errorCount: number;
  checks: DoctorCheck[];
}

const DEFAULT_SERVER_DIR = path.resolve(__dirname, '..', '..');
const DEFAULT_PROJECT_ROOT = path.resolve(DEFAULT_SERVER_DIR, '..');

function resolveDoctorProfileContext(options: DoctorOptions): ProfileContext {
  if (options.clawkeHome && !options.profile) {
    const baseConfigPath = path.join(options.clawkeHome, 'clawke.json');
    return {
      profile: undefined,
      isProfile: false,
      baseHome: options.clawkeHome,
      runtimeHome: options.clawkeHome,
      baseConfigPath,
      configPath: baseConfigPath,
    };
  }
  const env = options.env || process.env;
  return resolveProfileContext({
    profile: options.profile,
    baseHome: options.clawkeHome,
    homeDir: options.homeDir,
    env,
  });
}

function addCheck(
  checks: DoctorCheck[],
  section: string,
  status: DoctorStatus,
  message: string,
  detail?: string,
): void {
  checks.push({ section, status, message, detail });
}

function readJson(filePath: string): { value?: any; error?: string } {
  try {
    return { value: JSON.parse(fs.readFileSync(filePath, 'utf-8')) };
  } catch (err: any) {
    return { error: err?.message || String(err) };
  }
}

function isProcessAlive(pid: number): boolean {
  try {
    process.kill(pid, 0);
    return true;
  } catch (err: any) {
    return err?.code === 'EPERM';
  }
}

function readPidFile(pidPath: string): number | null {
  try {
    const pid = Number.parseInt(fs.readFileSync(pidPath, 'utf-8').trim(), 10);
    return Number.isFinite(pid) ? pid : null;
  } catch {
    return null;
  }
}

function collectGatewayInstances(config: any): GatewayInstance[] {
  if (!config || typeof config !== 'object' || !config.gateways || typeof config.gateways !== 'object') {
    return [];
  }

  const instances: GatewayInstance[] = [];
  for (const [type, value] of Object.entries(config.gateways)) {
    if (Array.isArray(value)) {
      instances.push(...value.map((item) => ({ ...(item as GatewayInstance), type })));
    }
  }
  return instances;
}

function formatGatewayName(gateway: GatewayInstance, id: string): string {
  const type = gateway.type;
  if (type === 'hermes') return id === 'hermes' ? 'Clawke Hermes Gateway' : `Clawke Hermes Gateway (${id})`;
  if (type === 'openclaw') return id === 'OpenClaw' ? 'Clawke OpenClaw Gateway' : `Clawke OpenClaw Gateway (${id})`;
  if (type === 'nanobot') return id === 'nanobot' ? 'Clawke nanobot Gateway' : `Clawke nanobot Gateway (${id})`;
  return `Clawke Gateway (${id})`;
}

function formatGatewayOwner(gateway: GatewayInstance): string {
  if (gateway.type === 'openclaw') return 'OpenClaw';
  if (gateway.type === 'nanobot') return 'nanobot';
  return 'external agent process';
}

function shouldCheckLocalStartShell(gateway: GatewayInstance): boolean {
  return gateway.type === 'hermes';
}

function validatePort(checks: DoctorCheck[], config: any, key: string): void {
  const value = config?.server?.[key];
  if (value === undefined) return;
  const valid = Number.isInteger(value) && value > 0 && value <= 65535;
  addCheck(
    checks,
    'Configuration',
    valid ? 'ok' : 'error',
    `${key}: ${value}`,
    valid ? undefined : 'Expected an integer between 1 and 65535.',
  );
}

function inspectProjectFiles(checks: DoctorCheck[], projectRoot: string, serverDir: string): void {
  const files = [
    [path.join(serverDir, 'package.json'), 'server/package.json'],
    [path.join(serverDir, 'tsconfig.json'), 'server/tsconfig.json'],
    [path.join(serverDir, 'dist', 'index.js'), 'server/dist/index.js'],
    [path.join(serverDir, 'dist', 'cli', 'clawke.js'), 'server/dist/cli/clawke.js'],
  ] as const;

  for (const [filePath, label] of files) {
    addCheck(
      checks,
      'Project',
      fs.existsSync(filePath) ? 'ok' : 'warn',
      label,
      fs.existsSync(filePath) ? undefined : 'Missing; run `cd server && npm run build`.',
    );
  }

  const clientPubspec = path.join(projectRoot, 'client', 'pubspec.yaml');
  addCheck(
    checks,
    'Project',
    fs.existsSync(clientPubspec) ? 'ok' : 'info',
    'client/pubspec.yaml',
    fs.existsSync(clientPubspec) ? undefined : 'Flutter client not found in this checkout.',
  );
}

function inspectAgentPlatforms(checks: DoctorCheck[], homeDir: string): void {
  const platforms = [
    ['OpenClaw', path.join(homeDir, '.openclaw', 'openclaw.json')],
    ['Hermes', path.join(homeDir, '.hermes')],
    ['nanobot', path.join(homeDir, '.nanobot', 'config.json')],
  ] as const;

  for (const [name, configPath] of platforms) {
    const detected = fs.existsSync(configPath);
    addCheck(
      checks,
      'Agent Platforms',
      detected ? 'ok' : 'info',
      `${name}: ${detected ? 'detected' : 'not detected'}`,
      configPath,
    );
  }
}

function inspectServerPid(checks: DoctorCheck[], clawkeHome: string): void {
  const pidPath = path.join(clawkeHome, 'server.pid');
  const pid = readPidFile(pidPath);
  if (!fs.existsSync(pidPath)) {
    addCheck(checks, 'Runtime', 'info', 'Clawke Server is not running', 'No server.pid file.');
    return;
  }
  if (!pid) {
    addCheck(checks, 'Runtime', 'warn', 'server.pid is invalid', pidPath);
    return;
  }

  addCheck(
    checks,
    'Runtime',
    isProcessAlive(pid) ? 'ok' : 'warn',
    isProcessAlive(pid) ? `Clawke Server is running (PID ${pid})` : `Clawke Server PID is stale (${pid})`,
    pidPath,
  );
}

function inspectGatewayPids(checks: DoctorCheck[], clawkeHome: string, gateways: GatewayInstance[]): void {
  for (const gateway of gateways) {
    const id = typeof gateway.id === 'string' ? gateway.id : '';
    if (!id) {
      addCheck(checks, 'Gateways', 'error', 'Gateway entry is missing id');
      continue;
    }

    const name = formatGatewayName(gateway, id);
    if (!shouldCheckLocalStartShell(gateway)) {
      const owner = formatGatewayOwner(gateway);
      addCheck(
        checks,
        'Gateways',
        'ok',
        `${name} is registered`,
        `startup: embedded in ${owner}`,
      );
      continue;
    }

    const startShell = resolveGatewayStartShell(gateway);
    if (!startShell) {
      addCheck(
        checks,
        'Gateways',
        'warn',
        `${name} is missing start_shell`,
        'Run `clawke gateway install` to register the local Hermes gateway launcher.',
      );
      continue;
    }

    addCheck(
      checks,
      'Gateways',
      'ok',
      `${name} has local start command`,
      startShell,
    );

    const pidPath = path.join(clawkeHome, `${id}-gateway.pid`);
    if (!fs.existsSync(pidPath)) {
      addCheck(checks, 'Gateways', 'info', `${name} is not running`, 'No gateway PID file.');
      continue;
    }

    const pid = readPidFile(pidPath);
    if (!pid) {
      addCheck(checks, 'Gateways', 'warn', `${name} PID file is invalid`, pidPath);
      continue;
    }

    addCheck(
      checks,
      'Gateways',
      isProcessAlive(pid) ? 'ok' : 'warn',
      isProcessAlive(pid) ? `${name} is running (PID ${pid})` : `${name} PID is stale (${pid})`,
      pidPath,
    );
  }
}

function statusIcon(status: DoctorStatus): string {
  switch (status) {
    case 'ok': return '✅';
    case 'warn': return '⚠️';
    case 'error': return '❌';
    case 'info': return 'ℹ️';
  }
}

function renderChecks(checks: DoctorCheck[], stdout: NodeJS.WritableStream): void {
  stdout.write('\nClawke Doctor\n\n');

  let currentSection = '';
  for (const check of checks) {
    if (check.section !== currentSection) {
      currentSection = check.section;
      stdout.write(`◆ ${currentSection}\n`);
    }
    stdout.write(`  ${statusIcon(check.status)} ${check.message}`);
    if (check.detail) stdout.write(` (${check.detail})`);
    stdout.write('\n');
  }
}

function inspectProfile(checks: DoctorCheck[], context: ProfileContext): void {
  if (!context.isProfile || !context.profile) return;

  addCheck(checks, 'Profile', 'info', `Profile: ${context.profile}`, context.runtimeHome);
  addCheck(checks, 'Profile', fs.existsSync(context.baseConfigPath) ? 'ok' : 'warn', 'Base config', context.baseConfigPath);
  addCheck(
    checks,
    'Profile',
    context.profileConfigPath && fs.existsSync(context.profileConfigPath) ? 'ok' : 'info',
    'Profile config',
    context.profileConfigPath,
  );
}

export function runClawkeDoctor(options: DoctorOptions = {}): DoctorResult {
  const stdout = options.stdout || process.stdout;
  const profileContext = resolveDoctorProfileContext(options);
  const clawkeHome = profileContext.runtimeHome;
  const homeDir = options.homeDir || os.homedir();
  const projectRoot = options.projectRoot || DEFAULT_PROJECT_ROOT;
  const serverDir = options.serverDir || DEFAULT_SERVER_DIR;
  const checks: DoctorCheck[] = [];

  inspectProjectFiles(checks, projectRoot, serverDir);
  inspectAgentPlatforms(checks, homeDir);
  inspectProfile(checks, profileContext);
  inspectServerPid(checks, clawkeHome);

  const configPath = profileContext.configPath;
  let config: any = null;
  if (profileContext.isProfile) {
    try {
      config = loadConfig({
        profile: profileContext.profile,
        baseHome: profileContext.baseHome,
        ensure: false,
        env: options.env,
      });
      addCheck(checks, 'Configuration', 'ok', 'clawke.json overlay parsed', configPath);
      validatePort(checks, config, 'clientPort');
      validatePort(checks, config, 'httpPort');
      validatePort(checks, config, 'upstreamPort');
      validatePort(checks, config, 'mediaPort');
    } catch (err: any) {
      addCheck(checks, 'Configuration', 'error', 'clawke.json overlay is not valid', err?.message || String(err));
    }
  } else if (!fs.existsSync(configPath)) {
    addCheck(
      checks,
      'Configuration',
      'warn',
      'clawke.json is missing',
      `${configPath}; run \`clawke gateway install\` or \`clawke server start\`.`,
    );
  } else {
    const parsed = readJson(configPath);
    if (parsed.error) {
      addCheck(checks, 'Configuration', 'error', 'clawke.json is not valid JSON', parsed.error);
    } else {
      config = parsed.value;
      addCheck(checks, 'Configuration', 'ok', 'clawke.json parsed', configPath);
      validatePort(checks, config, 'clientPort');
      validatePort(checks, config, 'httpPort');
      validatePort(checks, config, 'upstreamPort');
      validatePort(checks, config, 'mediaPort');
    }
  }

  const gateways = collectGatewayInstances(config);
  if (config) {
    const suffix = gateways.length === 1 ? '' : 's';
    addCheck(checks, 'Gateways', gateways.length > 0 ? 'ok' : 'warn', `${gateways.length} gateway instance${suffix} configured`);
  }
  inspectGatewayPids(checks, clawkeHome, gateways);

  renderChecks(checks, stdout);

  const warningCount = checks.filter((check) => check.status === 'warn').length;
  const errorCount = checks.filter((check) => check.status === 'error').length;
  stdout.write(`\nSummary: ${errorCount} error(s), ${warningCount} warning(s).\n`);

  return {
    ok: errorCount === 0,
    warningCount,
    errorCount,
    checks,
  };
}
