import fs from 'node:fs';
import os from 'node:os';
import path from 'node:path';
import { spawnSync } from 'node:child_process';

const DEFAULT_SERVER_ROOT = path.resolve(__dirname, '..', '..');
const MAIN_BRANCH = 'main';

type CommandResult = ReturnType<typeof spawnSync>;

interface UpdateOptions {
  serverRoot?: string;
  stdout?: NodeJS.WriteStream;
  stderr?: NodeJS.WriteStream;
  checkOnly?: boolean;
}

class CommandFailure extends Error {
  result?: CommandResult;

  constructor(message: string, result?: CommandResult) {
    super(message);
    this.result = result;
  }
}

function runArgv(argv: string[], cwd: string, inherit = false): CommandResult {
  const [command, ...args] = argv;
  return spawnSync(command, args, {
    cwd,
    encoding: 'utf-8',
    stdio: inherit ? 'inherit' : 'pipe',
  });
}

function runGit(gitCmd: string[], args: string[], cwd: string): CommandResult {
  return runArgv([...gitCmd, ...args], cwd);
}

function ensureOk(result: CommandResult, message: string): void {
  if (result.status !== 0) throw new CommandFailure(message, result);
}

function firstLine(value: string | Buffer | null | undefined): string {
  return String(value ?? '').trim().split(/\r?\n/)[0] ?? '';
}

function fail(
  stderr: NodeJS.WriteStream,
  message: string,
  result?: CommandResult,
): number {
  stderr.write(`[clawke] ❌ ${message}\n`);
  const detail = firstLine(result?.stderr || result?.error?.message);
  if (detail) stderr.write(`[clawke] ${detail}\n`);
  return 1;
}

function gitCommand(): string[] {
  return process.platform === 'win32'
    ? ['git', '-c', 'windows.appendAtomically=false']
    : ['git'];
}

function requireGitCheckout(projectRoot: string, stderr: NodeJS.WriteStream): boolean {
  if (fs.existsSync(path.join(projectRoot, '.git'))) return true;
  stderr.write('[clawke] ❌ Not a git repository. Reinstall Clawke from source.\n');
  return false;
}

function updateTimestamp(): string {
  return new Date()
    .toISOString()
    .replace(/[-:]/g, '')
    .replace(/\.\d{3}Z$/, 'Z')
    .replace('T', '-');
}

function stashLocalChangesIfNeeded(
  gitCmd: string[],
  projectRoot: string,
  stdout: NodeJS.WriteStream,
): string | null {
  const status = runGit(gitCmd, ['status', '--porcelain'], projectRoot);
  ensureOk(status, 'Failed to inspect local changes.');
  if (!String(status.stdout || '').trim()) return null;

  const unmerged = runGit(gitCmd, ['ls-files', '--unmerged'], projectRoot);
  if (String(unmerged.stdout || '').trim()) {
    stdout.write('[clawke] Clearing unmerged index entries from a previous conflict...\n');
    runGit(gitCmd, ['reset'], projectRoot);
  }

  const stashName = `clawke-update-autostash-${updateTimestamp()}`;
  stdout.write('[clawke] Local changes detected; stashing before update...\n');
  const stash = runGit(
    gitCmd,
    ['stash', 'push', '--include-untracked', '-m', stashName],
    projectRoot,
  );
  ensureOk(stash, 'Failed to stash local changes.');

  const ref = runGit(gitCmd, ['rev-parse', '--verify', 'refs/stash'], projectRoot);
  ensureOk(ref, 'Failed to resolve stash ref.');
  return firstLine(ref.stdout);
}

function resolveStashSelector(
  gitCmd: string[],
  projectRoot: string,
  stashRef: string,
): string | null {
  const list = runGit(gitCmd, ['stash', 'list', '--format=%gd %H'], projectRoot);
  if (list.status !== 0) return null;
  for (const line of String(list.stdout || '').split(/\r?\n/)) {
    const [selector, commit] = line.split(' ');
    if (commit === stashRef) return selector || null;
  }
  return null;
}

function restoreStashedChanges(
  gitCmd: string[],
  projectRoot: string,
  stashRef: string,
  stdout: NodeJS.WriteStream,
  stderr: NodeJS.WriteStream,
): boolean {
  stdout.write('[clawke] Restoring local changes...\n');
  const restore = runGit(gitCmd, ['stash', 'apply', stashRef], projectRoot);
  const unmerged = runGit(gitCmd, ['diff', '--name-only', '--diff-filter=U'], projectRoot);
  const conflicted = String(unmerged.stdout || '').trim();

  if (restore.status !== 0 || conflicted) {
    stdout.write('[clawke] ✗ Update pulled new code, but restoring local changes hit conflicts.\n');
    if (conflicted) stdout.write(`\n[clawke] Conflicted files:\n${conflicted}\n`);
    stdout.write('\n[clawke] Your stashed changes are preserved; nothing is lost.\n');
    stdout.write(`[clawke] Stash ref: ${stashRef}\n`);
    runGit(gitCmd, ['reset', '--hard', 'HEAD'], projectRoot);
    stdout.write('[clawke] Working tree reset to clean state.\n');
    stdout.write(`[clawke] Restore your changes later with: git stash apply ${stashRef}\n`);
    return false;
  }

  const selector = resolveStashSelector(gitCmd, projectRoot, stashRef);
  if (!selector) {
    stderr.write('[clawke] ⚠️ Local changes restored, but stash entry was left in place.\n');
    return true;
  }

  const drop = runGit(gitCmd, ['stash', 'drop', selector], projectRoot);
  if (drop.status !== 0) {
    stderr.write('[clawke] ⚠️ Local changes restored, but dropping the stash entry failed.\n');
  }
  return true;
}

function runUpdateCheck(
  gitCmd: string[],
  projectRoot: string,
  stdout: NodeJS.WriteStream,
  stderr: NodeJS.WriteStream,
): number {
  if (!requireGitCheckout(projectRoot, stderr)) return 1;

  stdout.write('[clawke] Fetching origin...\n');
  let result = runGit(gitCmd, ['fetch', 'origin'], projectRoot);
  if (result.status !== 0) return fail(stderr, 'Failed to fetch from origin.', result);

  result = runGit(gitCmd, ['rev-list', `HEAD..origin/${MAIN_BRANCH}`, '--count'], projectRoot);
  if (result.status !== 0) return fail(stderr, `Failed to compare with origin/${MAIN_BRANCH}.`, result);

  const behind = Number.parseInt(firstLine(result.stdout), 10);
  if (!Number.isFinite(behind)) {
    stderr.write(`[clawke] ❌ Could not parse update count for origin/${MAIN_BRANCH}.\n`);
    return 1;
  }

  if (behind === 0) {
    stdout.write('[clawke] Already up to date.\n');
  } else {
    const word = behind === 1 ? 'commit' : 'commits';
    stdout.write(`[clawke] Update available: ${behind} ${word} behind origin/${MAIN_BRANCH}.\n`);
    stdout.write('[clawke] Run `clawke update` to install.\n');
  }
  return 0;
}

function runNpmInstallDeterministic(
  serverRoot: string,
  stderr: NodeJS.WriteStream,
): number {
  const extraArgs = ['--silent', '--no-fund', '--no-audit', '--progress=false'];
  const lockfile = path.join(serverRoot, 'package-lock.json');

  if (fs.existsSync(lockfile)) {
    const ci = runArgv(['npm', 'ci', ...extraArgs], serverRoot);
    if (ci.status === 0) return 0;
  }

  const install = runArgv(['npm', 'install', ...extraArgs], serverRoot);
  if (install.status !== 0) return fail(stderr, 'Failed to install server dependencies.', install);
  return 0;
}

function runGatewayUpdateAfterBuild(
  projectRoot: string,
  stdout: NodeJS.WriteStream,
  stderr: NodeJS.WriteStream,
): number {
  delete require.cache[require.resolve('./gateway-updater.js')];
  const { runGatewayUpdate } = require('./gateway-updater.js') as typeof import('./gateway-updater.js');
  return runGatewayUpdate({ projectRoot, stdout, stderr });
}

export function getClawkeServerRoot(): string {
  return DEFAULT_SERVER_ROOT;
}

export function getClawkeProjectRoot(serverRoot = DEFAULT_SERVER_ROOT): string {
  return path.resolve(serverRoot, '..');
}

export function readClawkeVersion(serverRoot = DEFAULT_SERVER_ROOT): string {
  const packagePath = path.join(serverRoot, 'package.json');
  const packageJson = JSON.parse(fs.readFileSync(packagePath, 'utf-8'));
  return String(packageJson.version || '0.0.0');
}

export function formatClawkeVersion(serverRoot = DEFAULT_SERVER_ROOT): string {
  const lines = [
    `Clawke v${readClawkeVersion(serverRoot)}`,
    `Project: ${getClawkeProjectRoot(serverRoot)}`,
    `Node: ${process.version}`,
  ];
  const behind = checkForUpdates(getClawkeProjectRoot(serverRoot));
  if (behind && behind > 0) {
    const word = behind === 1 ? 'commit' : 'commits';
    lines.push(`Update available: ${behind} ${word} behind; run 'clawke update'`);
  } else if (behind === 0) {
    lines.push('Up to date');
  }
  return lines.join('\n');
}

function checkForUpdates(projectRoot: string): number | null {
  if (!fs.existsSync(path.join(projectRoot, '.git'))) return null;
  try {
    spawnSync(gitCommand()[0], [...gitCommand().slice(1), 'fetch', 'origin', '--quiet'], {
      cwd: projectRoot,
      encoding: 'utf-8',
      stdio: 'pipe',
      timeout: 10_000,
    });
  } catch {
    return null;
  }
  const gitCmd = gitCommand();
  const result = spawnSync(gitCmd[0], [...gitCmd.slice(1), 'rev-list', '--count', `HEAD..origin/${MAIN_BRANCH}`], {
    cwd: projectRoot,
    encoding: 'utf-8',
    stdio: 'pipe',
    timeout: 5_000,
  });
  if (result.status !== 0) return null;
  const behind = Number.parseInt(firstLine(result.stdout), 10);
  return Number.isFinite(behind) ? behind : null;
}

export function runClawkeUpdate(options: UpdateOptions = {}): number {
  const serverRoot = options.serverRoot || DEFAULT_SERVER_ROOT;
  const projectRoot = getClawkeProjectRoot(serverRoot);
  const stdout = options.stdout || process.stdout;
  const stderr = options.stderr || process.stderr;
  const gitCmd = gitCommand();

  if (options.checkOnly) return runUpdateCheck(gitCmd, projectRoot, stdout, stderr);
  if (!requireGitCheckout(projectRoot, stderr)) return 1;

  try {
    if (process.platform === 'win32') {
      runGit(['git'], ['config', 'windows.appendAtomically', 'false'], projectRoot);
    }

    stdout.write('⚕ Updating Clawke...\n\n');
    stdout.write('[clawke] Fetching updates...\n');
    let result = runGit(gitCmd, ['fetch', 'origin'], projectRoot);
    if (result.status !== 0) return fail(stderr, 'Failed to fetch updates from origin.', result);

    result = runGit(gitCmd, ['rev-parse', '--abbrev-ref', 'HEAD'], projectRoot);
    ensureOk(result, 'Failed to detect current branch.');
    const currentBranch = firstLine(result.stdout);

    let autoStashRef: string | null = null;
    if (currentBranch !== MAIN_BRANCH) {
      const label = currentBranch === 'HEAD' ? 'detached HEAD' : `branch '${currentBranch}'`;
      stdout.write(`[clawke] Currently on ${label}; switching to ${MAIN_BRANCH} for update...\n`);
      autoStashRef = stashLocalChangesIfNeeded(gitCmd, projectRoot, stdout);
      result = runGit(gitCmd, ['checkout', MAIN_BRANCH], projectRoot);
      ensureOk(result, `Failed to checkout ${MAIN_BRANCH}.`);
    } else {
      autoStashRef = stashLocalChangesIfNeeded(gitCmd, projectRoot, stdout);
    }

    result = runGit(gitCmd, ['rev-list', `HEAD..origin/${MAIN_BRANCH}`, '--count'], projectRoot);
    ensureOk(result, `Failed to compare with origin/${MAIN_BRANCH}.`);
    const commitCount = Number.parseInt(firstLine(result.stdout), 10);
    if (!Number.isFinite(commitCount)) {
      stderr.write(`[clawke] ❌ Could not parse update count for origin/${MAIN_BRANCH}.\n`);
      return 1;
    }

    if (commitCount === 0) {
      if (autoStashRef) restoreStashedChanges(gitCmd, projectRoot, autoStashRef, stdout, stderr);
      if (currentBranch !== MAIN_BRANCH && currentBranch !== 'HEAD') {
        runGit(gitCmd, ['checkout', currentBranch], projectRoot);
      }
      stdout.write('[clawke] ✓ Already up to date!\n');
      return runGatewayUpdateAfterBuild(projectRoot, stdout, stderr);
    }

    stdout.write(`[clawke] Found ${commitCount} new commit(s)\n`);
    stdout.write('[clawke] Pulling updates...\n');
    result = runGit(gitCmd, ['pull', '--ff-only', 'origin', MAIN_BRANCH], projectRoot);
    if (result.status !== 0) {
      stdout.write('[clawke] Fast-forward not possible; resetting to match remote...\n');
      const reset = runGit(gitCmd, ['reset', '--hard', `origin/${MAIN_BRANCH}`], projectRoot);
      if (reset.status !== 0) {
        if (autoStashRef) stderr.write(`[clawke] Local changes preserved in stash: ${autoStashRef}\n`);
        return fail(stderr, `Failed to reset to origin/${MAIN_BRANCH}.`, reset);
      }
    }

    if (autoStashRef) {
      restoreStashedChanges(gitCmd, projectRoot, autoStashRef, stdout, stderr);
    }

    stdout.write('[clawke] Updating Node.js dependencies...\n');
    const installCode = runNpmInstallDeterministic(serverRoot, stderr);
    if (installCode !== 0) return installCode;

    stdout.write('[clawke] Rebuilding server...\n');
    result = runArgv(['npm', 'run', 'build'], serverRoot, true);
    if (result.status !== 0) return fail(stderr, 'Failed to rebuild server.', result);

    const gatewayUpdateCode = runGatewayUpdateAfterBuild(projectRoot, stdout, stderr);
    if (gatewayUpdateCode !== 0) return gatewayUpdateCode;

    stdout.write('\n[clawke] ✓ Update complete!\n');
    return 0;
  } catch (err) {
    if (err instanceof CommandFailure) return fail(stderr, err.message, err.result);
    throw err;
  }
}
