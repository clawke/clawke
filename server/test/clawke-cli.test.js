const test = require('node:test');
const assert = require('node:assert/strict');
const fs = require('node:fs');
const os = require('node:os');
const path = require('node:path');
const { spawnSync } = require('node:child_process');

const serverRoot = path.resolve(__dirname, '..');
const projectRoot = path.resolve(serverRoot, '..');
const cliPath = path.join(serverRoot, 'dist', 'cli', 'clawke.js');
const packageJson = JSON.parse(
  fs.readFileSync(path.join(serverRoot, 'package.json'), 'utf-8'),
);

function makeFakeCommand(binDir, name, body) {
  const file = path.join(binDir, name);
  fs.writeFileSync(file, `#!/usr/bin/env node\n${body}`);
  fs.chmodSync(file, 0o755);
}

test('clawke --version prints package version and runtime info', () => {
  const dir = fs.mkdtempSync(path.join(os.tmpdir(), 'clawke-cli-'));
  const binDir = path.join(dir, 'bin');
  fs.mkdirSync(binDir);

  makeFakeCommand(binDir, 'git', `
const args = process.argv.slice(2);
const joined = args.join(' ');
if (joined === 'fetch origin --quiet') process.exit(0);
if (joined === 'rev-list --count HEAD..origin/main') {
  console.log('0');
  process.exit(0);
}
process.exit(1);
`);

  const result = spawnSync(process.execPath, [cliPath, '--version'], {
    cwd: serverRoot,
    env: {
      ...process.env,
      CLAWKE_DATA_DIR: path.join(dir, '.clawke'),
      PATH: `${binDir}${path.delimiter}${process.env.PATH || ''}`,
    },
    encoding: 'utf-8',
  });

  assert.equal(result.status, 0, result.stderr || result.stdout);
  assert.match(result.stdout, new RegExp(`Clawke v${packageJson.version}`));
  assert.match(result.stdout, new RegExp(`Project: ${projectRoot.replace(/[.*+?^${}()|[\]\\]/g, '\\$&')}`));
  assert.match(result.stdout, /^Node: v/m);
  assert.match(result.stdout, /Up to date/);
});

test('clawke update --check reports origin/main without installing', () => {
  const dir = fs.mkdtempSync(path.join(os.tmpdir(), 'clawke-cli-'));
  const binDir = path.join(dir, 'bin');
  fs.mkdirSync(binDir);
  const logPath = path.join(dir, 'commands.log');
  const quotedLogPath = JSON.stringify(logPath);

  makeFakeCommand(binDir, 'git', `
const fs = require('node:fs');
const args = process.argv.slice(2);
fs.appendFileSync(${quotedLogPath}, 'git ' + args.join(' ') + '\\n');
const joined = args.join(' ');
if (joined === 'fetch origin') {
  process.exit(0);
}
if (joined === 'rev-list HEAD..origin/main --count') {
  console.log('2');
  process.exit(0);
}
process.exit(1);
`);

  makeFakeCommand(binDir, 'npm', `
const fs = require('node:fs');
const args = process.argv.slice(2);
fs.appendFileSync(${quotedLogPath}, 'npm ' + args.join(' ') + '\\n');
process.exit(0);
`);

  const result = spawnSync(process.execPath, [cliPath, 'update', '--check'], {
    cwd: serverRoot,
    env: {
      ...process.env,
      CLAWKE_DATA_DIR: path.join(dir, '.clawke'),
      PATH: `${binDir}${path.delimiter}${process.env.PATH || ''}`,
    },
    encoding: 'utf-8',
  });

  assert.equal(result.status, 0, result.stderr || result.stdout);
  assert.match(result.stdout, /Update available: 2 commits behind origin\/main/);

  const commands = fs.readFileSync(logPath, 'utf-8').trim().split('\n');
  assert.deepEqual(commands, [
    'git fetch origin',
    'git rev-list HEAD..origin/main --count',
  ]);
});

test('clawke doctor prints a read-only setup report', () => {
  const dir = fs.mkdtempSync(path.join(os.tmpdir(), 'clawke-cli-'));
  const clawkeHome = path.join(dir, '.clawke');

  const result = spawnSync(process.execPath, [cliPath, 'doctor'], {
    cwd: serverRoot,
    env: {
      ...process.env,
      CLAWKE_DATA_DIR: clawkeHome,
      HOME: dir,
    },
    encoding: 'utf-8',
  });

  assert.equal(result.status, 0, result.stderr || result.stdout);
  assert.equal(fs.existsSync(path.join(clawkeHome, 'clawke.json')), false);
  assert.match(result.stdout, /Clawke Doctor/);
  assert.match(result.stdout, /clawke\.json is missing/);
});

test('clawke gateway install does not offer disabled nanobot gateway', () => {
  const dir = fs.mkdtempSync(path.join(os.tmpdir(), 'clawke-cli-'));

  const result = spawnSync(process.execPath, [cliPath, 'gateway', 'install'], {
    cwd: serverRoot,
    env: {
      ...process.env,
      HOME: dir,
    },
    input: '\n',
    encoding: 'utf-8',
  });

  assert.equal(result.status, 0, result.stderr || result.stdout);
  assert.match(result.stdout, /OpenClaw/);
  assert.match(result.stdout, /Hermes/);
  assert.match(result.stdout, /0\. Skip gateway installation/);
  assert.doesNotMatch(result.stdout, /nanobot/i);

  const openClawIndex = result.stdout.indexOf('OpenClaw');
  const hermesIndex = result.stdout.indexOf('Hermes');
  const skipIndex = result.stdout.indexOf('Skip gateway installation');
  assert.ok(openClawIndex >= 0);
  assert.ok(hermesIndex > openClawIndex);
  assert.ok(skipIndex > hermesIndex);
});

test('clawke gateway install exits without installing when skip is selected', () => {
  for (const input of ['0\n', 'q\n']) {
    const dir = fs.mkdtempSync(path.join(os.tmpdir(), 'clawke-cli-'));

    const result = spawnSync(process.execPath, [cliPath, 'gateway', 'install'], {
      cwd: serverRoot,
      env: {
        ...process.env,
        HOME: dir,
      },
      input,
      encoding: 'utf-8',
    });

    assert.equal(result.status, 0, result.stderr || result.stdout);
    assert.match(result.stdout, /Skip gateway installation/);
    assert.doesNotMatch(result.stderr, /Invalid selection/);
    assert.equal(fs.existsSync(path.join(dir, '.clawke', 'clawke.json')), false);
  }
});

test('clawke openclaw-gateway install explains local install when OpenClaw is missing', () => {
  const dir = fs.mkdtempSync(path.join(os.tmpdir(), 'clawke-cli-'));

  const result = spawnSync(process.execPath, [cliPath, 'openclaw-gateway', 'install'], {
    cwd: serverRoot,
    env: {
      ...process.env,
      HOME: dir,
    },
    encoding: 'utf-8',
  });

  assert.equal(result.status, 0, result.stderr || result.stdout);
  assert.match(result.stdout, /If OpenClaw is installed locally:/);
  assert.match(result.stdout, /Install OpenClaw first:/);
  assert.match(result.stdout, /clawke gateway install/);
  assert.match(result.stdout, /If OpenClaw is installed on a remote server/);
});

test('clawke update switches to main, autostashes local changes, and rebuilds server', () => {
  const dir = fs.mkdtempSync(path.join(os.tmpdir(), 'clawke-cli-'));
  const binDir = path.join(dir, 'bin');
  fs.mkdirSync(binDir);
  const logPath = path.join(dir, 'commands.log');
  const quotedLogPath = JSON.stringify(logPath);

  makeFakeCommand(binDir, 'git', `
const fs = require('node:fs');
const args = process.argv.slice(2);
fs.appendFileSync(${quotedLogPath}, 'git ' + args.join(' ') + '\\n');
const joined = args.join(' ');
if (joined === 'fetch origin') {
  process.exit(0);
}
if (joined === 'rev-parse --abbrev-ref HEAD') {
  console.log('feature/local');
  process.exit(0);
}
if (joined === 'status --porcelain') {
  console.log(' M server/src/cli/clawke.ts');
  process.exit(0);
}
if (joined === 'ls-files --unmerged') {
  process.exit(0);
}
if (joined.startsWith('stash push --include-untracked -m clawke-update-autostash-')) {
  process.exit(0);
}
if (joined === 'rev-parse --verify refs/stash') {
  console.log('stash-commit');
  process.exit(0);
}
if (joined === 'checkout main') {
  process.exit(0);
}
if (joined === 'rev-list HEAD..origin/main --count') {
  console.log('1');
  process.exit(0);
}
if (joined === 'pull --ff-only origin main') {
  console.log('pulled main');
  process.exit(0);
}
if (joined === 'stash apply stash-commit') {
  process.exit(0);
}
if (joined === 'diff --name-only --diff-filter=U') {
  process.exit(0);
}
if (joined === 'stash list --format=%gd %H') {
  console.log('stash@{0} stash-commit');
  process.exit(0);
}
if (joined === 'stash drop stash@{0}') {
  process.exit(0);
}
process.exit(1);
`);

  makeFakeCommand(binDir, 'npm', `
const fs = require('node:fs');
const args = process.argv.slice(2);
fs.appendFileSync(${quotedLogPath}, 'npm ' + args.join(' ') + '\\n');
process.exit(0);
`);

  const result = spawnSync(process.execPath, [cliPath, 'update'], {
    cwd: serverRoot,
    env: {
      ...process.env,
      CLAWKE_DATA_DIR: path.join(dir, '.clawke'),
      PATH: `${binDir}${path.delimiter}${process.env.PATH || ''}`,
    },
    encoding: 'utf-8',
  });

  assert.equal(result.status, 0, result.stderr || result.stdout);
  assert.match(result.stdout, /Updating Clawke/);
  assert.match(result.stdout, /Found 1 new commit/);
  assert.match(result.stdout, /Update complete/);

  const commands = fs.readFileSync(logPath, 'utf-8').trim().split('\n');
  assert.equal(commands[0], 'git fetch origin');
  assert.equal(commands[1], 'git rev-parse --abbrev-ref HEAD');
  assert.equal(commands[2], 'git status --porcelain');
  assert.equal(commands[3], 'git ls-files --unmerged');
  assert.match(commands[4], /^git stash push --include-untracked -m clawke-update-autostash-/);
  assert.deepEqual(commands.slice(5), [
    'git rev-parse --verify refs/stash',
    'git checkout main',
    'git rev-list HEAD..origin/main --count',
    'git pull --ff-only origin main',
    'git stash apply stash-commit',
    'git diff --name-only --diff-filter=U',
    'git stash list --format=%gd %H',
    'git stash drop stash@{0}',
    'npm ci --silent --no-fund --no-audit --progress=false',
    'npm run build',
  ]);
});

test('clawke update switches back to original branch when main is already current', () => {
  const dir = fs.mkdtempSync(path.join(os.tmpdir(), 'clawke-cli-'));
  const binDir = path.join(dir, 'bin');
  fs.mkdirSync(binDir);
  const logPath = path.join(dir, 'commands.log');
  const quotedLogPath = JSON.stringify(logPath);

  makeFakeCommand(binDir, 'git', `
const fs = require('node:fs');
const args = process.argv.slice(2);
fs.appendFileSync(${quotedLogPath}, 'git ' + args.join(' ') + '\\n');
const joined = args.join(' ');
if (joined === 'fetch origin') {
  process.exit(0);
}
if (joined === 'rev-parse --abbrev-ref HEAD') {
  console.log('feature/local');
  process.exit(0);
}
if (joined === 'status --porcelain') {
  process.exit(0);
}
if (joined === 'checkout main') {
  process.exit(0);
}
if (joined === 'rev-list HEAD..origin/main --count') {
  console.log('0');
  process.exit(0);
}
if (joined === 'checkout feature/local') {
  process.exit(0);
}
process.exit(1);
`);

  const result = spawnSync(process.execPath, [cliPath, 'update'], {
    cwd: serverRoot,
    env: {
      ...process.env,
      CLAWKE_DATA_DIR: path.join(dir, '.clawke'),
      PATH: `${binDir}${path.delimiter}${process.env.PATH || ''}`,
    },
    encoding: 'utf-8',
  });

  assert.equal(result.status, 0, result.stderr || result.stdout);
  assert.match(result.stdout, /Already up to date/);
  assert.match(result.stdout, /No configured gateways found/);

  const commands = fs.readFileSync(logPath, 'utf-8').trim().split('\n');
  assert.deepEqual(commands, [
    'git fetch origin',
    'git rev-parse --abbrev-ref HEAD',
    'git status --porcelain',
    'git checkout main',
    'git rev-list HEAD..origin/main --count',
    'git checkout feature/local',
  ]);
});

test('clawke update resets to origin main when fast-forward pull fails', () => {
  const dir = fs.mkdtempSync(path.join(os.tmpdir(), 'clawke-cli-'));
  const binDir = path.join(dir, 'bin');
  fs.mkdirSync(binDir);
  const logPath = path.join(dir, 'commands.log');
  const quotedLogPath = JSON.stringify(logPath);

  makeFakeCommand(binDir, 'git', `
const fs = require('node:fs');
const args = process.argv.slice(2);
fs.appendFileSync(${quotedLogPath}, 'git ' + args.join(' ') + '\\n');
const joined = args.join(' ');
if (joined === 'fetch origin') process.exit(0);
if (joined === 'rev-parse --abbrev-ref HEAD') {
  console.log('main');
  process.exit(0);
}
if (joined === 'status --porcelain') process.exit(0);
if (joined === 'rev-list HEAD..origin/main --count') {
  console.log('1');
  process.exit(0);
}
if (joined === 'pull --ff-only origin main') process.exit(1);
if (joined === 'reset --hard origin/main') process.exit(0);
process.exit(1);
`);

  makeFakeCommand(binDir, 'npm', `
const fs = require('node:fs');
const args = process.argv.slice(2);
fs.appendFileSync(${quotedLogPath}, 'npm ' + args.join(' ') + '\\n');
process.exit(0);
`);

  const result = spawnSync(process.execPath, [cliPath, 'update'], {
    cwd: serverRoot,
    env: {
      ...process.env,
      CLAWKE_DATA_DIR: path.join(dir, '.clawke'),
      PATH: `${binDir}${path.delimiter}${process.env.PATH || ''}`,
    },
    encoding: 'utf-8',
  });

  assert.equal(result.status, 0, result.stderr || result.stdout);
  assert.match(result.stdout, /Fast-forward not possible/);

  const commands = fs.readFileSync(logPath, 'utf-8').trim().split('\n');
  assert.deepEqual(commands, [
    'git fetch origin',
    'git rev-parse --abbrev-ref HEAD',
    'git status --porcelain',
    'git rev-list HEAD..origin/main --count',
    'git pull --ff-only origin main',
    'git reset --hard origin/main',
    'npm ci --silent --no-fund --no-audit --progress=false',
    'npm run build',
  ]);
});

test('clawke update preserves stash and cleans tree when restoring local changes conflicts', () => {
  const dir = fs.mkdtempSync(path.join(os.tmpdir(), 'clawke-cli-'));
  const binDir = path.join(dir, 'bin');
  fs.mkdirSync(binDir);
  const logPath = path.join(dir, 'commands.log');
  const quotedLogPath = JSON.stringify(logPath);

  makeFakeCommand(binDir, 'git', `
const fs = require('node:fs');
const args = process.argv.slice(2);
fs.appendFileSync(${quotedLogPath}, 'git ' + args.join(' ') + '\\n');
const joined = args.join(' ');
if (joined === 'fetch origin') process.exit(0);
if (joined === 'rev-parse --abbrev-ref HEAD') {
  console.log('main');
  process.exit(0);
}
if (joined === 'status --porcelain') {
  console.log(' M server/src/cli/clawke.ts');
  process.exit(0);
}
if (joined === 'ls-files --unmerged') process.exit(0);
if (joined.startsWith('stash push --include-untracked -m clawke-update-autostash-')) process.exit(0);
if (joined === 'rev-parse --verify refs/stash') {
  console.log('stash-commit');
  process.exit(0);
}
if (joined === 'rev-list HEAD..origin/main --count') {
  console.log('1');
  process.exit(0);
}
if (joined === 'pull --ff-only origin main') process.exit(0);
if (joined === 'stash apply stash-commit') process.exit(1);
if (joined === 'diff --name-only --diff-filter=U') {
  console.log('server/src/cli/clawke.ts');
  process.exit(0);
}
if (joined === 'reset --hard HEAD') process.exit(0);
process.exit(1);
`);

  makeFakeCommand(binDir, 'npm', `
const fs = require('node:fs');
const args = process.argv.slice(2);
fs.appendFileSync(${quotedLogPath}, 'npm ' + args.join(' ') + '\\n');
process.exit(0);
`);

  const result = spawnSync(process.execPath, [cliPath, 'update'], {
    cwd: serverRoot,
    env: {
      ...process.env,
      CLAWKE_DATA_DIR: path.join(dir, '.clawke'),
      PATH: `${binDir}${path.delimiter}${process.env.PATH || ''}`,
    },
    encoding: 'utf-8',
  });

  assert.equal(result.status, 0, result.stderr || result.stdout);
  assert.match(result.stdout, /Working tree reset to clean state/);
  assert.match(result.stdout, /Restore your changes later with: git stash apply stash-commit/);

  const commands = fs.readFileSync(logPath, 'utf-8').trim().split('\n');
  assert.equal(commands.includes('git reset --hard HEAD'), true);
  assert.equal(commands.includes('npm run build'), true);
});
