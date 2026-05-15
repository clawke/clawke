const assert = require('node:assert/strict');
const { execFileSync } = require('node:child_process');
const fs = require('node:fs');
const os = require('node:os');
const path = require('node:path');
const test = require('node:test');

const repoRoot = path.resolve(__dirname, '..', '..');
const installScriptPath = path.join(repoRoot, 'scripts', 'install.sh');

function stripAnsi(value) {
  return value.replace(/\x1b\[[0-9;]*m/g, '');
}

test('install.sh is valid bash syntax', () => {
  execFileSync('bash', ['-n', installScriptPath], { stdio: 'pipe' });
});

test('install.sh offers guided post-install actions', () => {
  const script = fs.readFileSync(installScriptPath, 'utf8');

  assert.match(script, /run_post_install_setup\(\)/);
  assert.match(script, /Install an AI gateway now\?/);
  assert.match(script, /Install another AI gateway\?/);
  assert.match(script, /Start Clawke Server now\?/);
  assert.match(script, /run_clawke_command\(\)/);
});

test('install.sh requires an explicit answer before leaving gateway loop', () => {
  const script = fs.readFileSync(installScriptPath, 'utf8');

  assert.match(script, /prompt_yes_no_required\(\)/);
  assert.match(script, /prompt_yes_no_required "Install another AI gateway\?"/);
});

test('install.sh exits gateway loop immediately when CLI skip is selected', () => {
  const script = fs.readFileSync(installScriptPath, 'utf8');

  assert.match(script, /run_clawke_command_record\(\)/);
  assert.match(script, /Gateway installation skipped\./);
  assert.match(script, /Gateway installation skipped\.[\s\S]*break[\s\S]*prompt_yes_no_required "Install another AI gateway\?"/);
});

test('install.sh auto-updates configured local gateways before success output', () => {
  const script = fs.readFileSync(installScriptPath, 'utf8');

  assert.match(script, /sync_configured_local_gateways\(\)/);
  assert.match(script, /run_clawke_command gateway update --local-only/);
  assert.match(script, /install_builtin_skills[\s\S]*sync_configured_local_gateways[\s\S]*print_success/);
  assert.match(script, /gateway update --local-only[\s\S]*Configured local gateway update did not complete/);
});

test('guided post-install commands use available tty for child stdin', () => {
  const script = fs.readFileSync(installScriptPath, 'utf8');

  assert.match(script, /can_use_tty\(\) \{[\s\S]*\[ -r \/dev\/tty \][\s\S]*\[ -w \/dev\/tty \][\s\S]*: < \/dev\/tty > \/dev\/tty/);
  assert.match(script, /prompt_yes_no\(\)[\s\S]*elif can_use_tty; then[\s\S]*IFS= read -r answer < \/dev\/tty/);
  assert.match(script, /prompt_yes_no_required\(\)[\s\S]*elif can_use_tty; then[\s\S]*IFS= read -r answer < \/dev\/tty/);
  assert.match(script, /run_clawke_command\(\)[\s\S]*if \[ "\$IS_INTERACTIVE" = true \]; then[\s\S]*elif can_use_tty; then[\s\S]*"\$clawke_cmd" "\$@" < \/dev\/tty/);
  assert.doesNotMatch(script, /if \[ "\$IS_INTERACTIVE" = true \] && \[ -r \/dev\/tty \] && \[ -w \/dev\/tty \]/);
  assert.match(script, /printf '\\n'/);
  assert.match(script, /clawke_cmd="\$\(get_command_link_dir\)\/clawke"/);
});

test('install.sh uses printf for status logs', () => {
  const script = fs.readFileSync(installScriptPath, 'utf8');

  assert.match(script, /log_success\(\) \{\s*printf/s);
  assert.doesNotMatch(script, /log_success\(\) \{\s*echo -e/s);
});

test('install.sh forbids rsync delete during local install updates', () => {
  const script = fs.readFileSync(installScriptPath, 'utf8');

  assert.doesNotMatch(script, /rsync[\s\S]{0,80}--delete/);
  assert.match(script, /禁止添加 --delete/);
});

test('install.sh refuses local sync into an external git worktree', () => {
  const tmpDir = fs.mkdtempSync(path.join(os.tmpdir(), 'clawke-install-test-'));
  const homeDir = path.join(tmpDir, 'home');
  const sourceDir = path.join(tmpDir, 'source');
  const installDir = path.join(tmpDir, 'worktree-target');
  const sentinel = path.join(installDir, 'keep.txt');

  fs.mkdirSync(path.join(sourceDir, 'server'), { recursive: true });
  fs.mkdirSync(path.join(sourceDir, 'gateways'), { recursive: true });
  fs.mkdirSync(installDir, { recursive: true });
  fs.writeFileSync(path.join(sourceDir, 'server', 'package.json'), '{"scripts":{}}\n');
  fs.writeFileSync(path.join(installDir, '.git'), 'gitdir: /tmp/main/.git/worktrees/worktree-target\n');
  fs.writeFileSync(sentinel, 'keep\n');

  let error;
  try {
    execFileSync(
      'bash',
      [
        installScriptPath,
        '--local',
        sourceDir,
        '--dir',
        installDir,
        '--clawke-home',
        path.join(homeDir, '.clawke'),
        '--no-post-install',
      ],
      {
        cwd: repoRoot,
        encoding: 'utf8',
        env: {
          ...process.env,
          HOME: homeDir,
          SHELL: '/bin/bash',
        },
      },
    );
  } catch (err) {
    error = err;
  }

  assert.ok(error);
  assert.match(stripAnsi(`${error.stdout || ''}${error.stderr || ''}`), /Refusing to sync local install into a linked Git worktree/);
  assert.equal(fs.readFileSync(sentinel, 'utf8'), 'keep\n');
});

test('install.sh supports local non-interactive install without post-install prompts', () => {
  const tmpDir = fs.mkdtempSync(path.join(os.tmpdir(), 'clawke-install-test-'));
  const homeDir = path.join(tmpDir, 'home');
  const sourceDir = path.join(tmpDir, 'source');
  const installDir = path.join(tmpDir, 'install');
  const fakeBinDir = path.join(tmpDir, 'bin');
  const fakeCliLog = path.join(tmpDir, 'fake-clawke.log');

  fs.mkdirSync(path.join(sourceDir, 'server', 'dist', 'cli'), { recursive: true });
  fs.mkdirSync(path.join(sourceDir, 'server', 'config'), { recursive: true });
  fs.mkdirSync(path.join(sourceDir, 'gateways'), { recursive: true });
  fs.mkdirSync(fakeBinDir, { recursive: true });

  fs.writeFileSync(
    path.join(sourceDir, 'server', 'fake-clawke.js'),
    [
      'const fs = require("node:fs");',
      'const log = process.env.CLAWKE_FAKE_CLI_LOG;',
      'if (log) fs.appendFileSync(log, `${process.argv.slice(2).join(" ")}\\n`);',
      'console.log("fake clawke");',
    ].join('\n'),
  );
  fs.writeFileSync(path.join(sourceDir, 'server', 'package.json'), '{"scripts":{}}\n');
  fs.writeFileSync(path.join(sourceDir, 'server', 'config', 'clawke.json'), '{"server":{"mode":"mock"}}\n');
  fs.writeFileSync(
    path.join(fakeBinDir, 'npm'),
    '#!/bin/sh\nif [ "$1" = "run" ] && [ "$2" = "build" ]; then mkdir -p dist/cli && cp fake-clawke.js dist/cli/clawke.js; fi\nexit 0\n',
    { mode: 0o755 },
  );

  const output = stripAnsi(execFileSync(
    'bash',
    [
      installScriptPath,
      '--local',
      sourceDir,
      '--dir',
      installDir,
      '--clawke-home',
      path.join(homeDir, '.clawke'),
      '--no-post-install',
    ],
    {
      cwd: repoRoot,
      encoding: 'utf8',
      env: {
        ...process.env,
        HOME: homeDir,
        CLAWKE_FAKE_CLI_LOG: fakeCliLog,
        PATH: `${fakeBinDir}:${path.join(homeDir, '.local', 'bin')}:${process.env.PATH}`,
        SHELL: '/bin/bash',
      },
    },
  ));

  assert.match(output, /Installation Complete/);
  assert.match(output, /Updating configured local gateways/);
  assert.match(output, /clawke doctor\s+Check local setup/);
  assert.doesNotMatch(output, /Continue setup now/);
  assert.match(output, /If 'clawke' is not found in this terminal/);
  assert.doesNotMatch(output, /Reload shell \(above\)/);
  assert.match(output, /1\. clawke gateway install/);
  assert.match(output, /2\. clawke server start/);
  assert.match(fs.readFileSync(fakeCliLog, 'utf8'), /^gateway update --local-only$/m);
  assert.ok(fs.existsSync(path.join(homeDir, '.local', 'bin', 'clawke')));
  assert.ok(fs.existsSync(path.join(homeDir, '.clawke', 'clawke.json')));
});

test('install.sh warns but completes when automatic local gateway update fails', () => {
  const tmpDir = fs.mkdtempSync(path.join(os.tmpdir(), 'clawke-install-test-'));
  const homeDir = path.join(tmpDir, 'home');
  const sourceDir = path.join(tmpDir, 'source');
  const installDir = path.join(tmpDir, 'install');
  const fakeBinDir = path.join(tmpDir, 'bin');
  const fakeCliLog = path.join(tmpDir, 'fake-clawke.log');

  fs.mkdirSync(path.join(sourceDir, 'server', 'dist', 'cli'), { recursive: true });
  fs.mkdirSync(path.join(sourceDir, 'server', 'config'), { recursive: true });
  fs.mkdirSync(path.join(sourceDir, 'gateways'), { recursive: true });
  fs.mkdirSync(fakeBinDir, { recursive: true });

  fs.writeFileSync(
    path.join(sourceDir, 'server', 'fake-clawke.js'),
    [
      'const fs = require("node:fs");',
      'const args = process.argv.slice(2).join(" ");',
      'const log = process.env.CLAWKE_FAKE_CLI_LOG;',
      'if (log) fs.appendFileSync(log, `${args}\\n`);',
      'if (args === "gateway update --local-only") process.exit(7);',
      'console.log("fake clawke");',
    ].join('\n'),
  );
  fs.writeFileSync(path.join(sourceDir, 'server', 'package.json'), '{"scripts":{}}\n');
  fs.writeFileSync(path.join(sourceDir, 'server', 'config', 'clawke.json'), '{"server":{"mode":"mock"}}\n');
  fs.writeFileSync(
    path.join(fakeBinDir, 'npm'),
    '#!/bin/sh\nif [ "$1" = "run" ] && [ "$2" = "build" ]; then mkdir -p dist/cli && cp fake-clawke.js dist/cli/clawke.js; fi\nexit 0\n',
    { mode: 0o755 },
  );

  const output = stripAnsi(execFileSync(
    'bash',
    [
      installScriptPath,
      '--local',
      sourceDir,
      '--dir',
      installDir,
      '--clawke-home',
      path.join(homeDir, '.clawke'),
      '--no-post-install',
    ],
    {
      cwd: repoRoot,
      encoding: 'utf8',
      env: {
        ...process.env,
        HOME: homeDir,
        CLAWKE_FAKE_CLI_LOG: fakeCliLog,
        PATH: `${fakeBinDir}:${path.join(homeDir, '.local', 'bin')}:${process.env.PATH}`,
        SHELL: '/bin/bash',
      },
    },
  ));

  assert.match(output, /Configured local gateway update did not complete/);
  assert.match(output, /Installation Complete/);
  assert.match(fs.readFileSync(fakeCliLog, 'utf8'), /^gateway update --local-only$/m);
});
