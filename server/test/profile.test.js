const test = require('node:test');
const assert = require('node:assert/strict');
const os = require('node:os');
const path = require('node:path');

test('profile resolver keeps default commands on base clawke home', async () => {
  const { resolveProfileContext } = await import('../dist/profile.js');
  const homeDir = path.join(os.tmpdir(), 'clawke-home-default');

  const context = resolveProfileContext({ homeDir, env: {} });

  assert.equal(context.profile, undefined);
  assert.equal(context.isProfile, false);
  assert.equal(context.baseHome, path.join(homeDir, '.clawke'));
  assert.equal(context.runtimeHome, path.join(homeDir, '.clawke'));
  assert.equal(context.configPath, path.join(homeDir, '.clawke', 'clawke.json'));
});

test('profile resolver maps dev profile to isolated runtime home', async () => {
  const { resolveProfileContext } = await import('../dist/profile.js');
  const homeDir = path.join(os.tmpdir(), 'clawke-home-profile');

  const context = resolveProfileContext({ homeDir, profile: 'dev', env: {} });

  assert.equal(context.profile, 'dev');
  assert.equal(context.isProfile, true);
  assert.equal(context.baseHome, path.join(homeDir, '.clawke'));
  assert.equal(context.runtimeHome, path.join(homeDir, '.clawke', 'profiles', 'dev'));
  assert.equal(context.baseConfigPath, path.join(homeDir, '.clawke', 'clawke.json'));
  assert.equal(context.profileConfigPath, path.join(homeDir, '.clawke', 'profiles', 'dev', 'clawke.json'));
  assert.equal(context.configPath, path.join(homeDir, '.clawke', 'profiles', 'dev', 'clawke.json'));
});

test('profile argv parser removes profile args and lets CLI override env', async () => {
  const { parseProfileArgv } = await import('../dist/profile.js');

  const parsed = parseProfileArgv(['server', 'status', '--profile', 'dev'], {
    CLAWKE_PROFILE: 'prod',
  });

  assert.deepEqual(parsed.args, ['server', 'status']);
  assert.equal(parsed.profile, 'dev');

  const envOnly = parseProfileArgv(['doctor'], { CLAWKE_PROFILE: 'dev' });
  assert.deepEqual(envOnly.args, ['doctor']);
  assert.equal(envOnly.profile, 'dev');
});

test('profile argv parser rejects unsafe profile names', async () => {
  const { parseProfileArgv } = await import('../dist/profile.js');

  assert.throws(() => parseProfileArgv(['server', 'status', '--profile', '../prod']), /Invalid profile name/);
  assert.throws(() => parseProfileArgv(['server', 'status', '--profile=']), /Missing profile name/);
  assert.throws(() => parseProfileArgv(['server', 'status', '--profile', '.']), /Invalid profile name/);
});
