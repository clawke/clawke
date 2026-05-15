const test = require('node:test');
const assert = require('node:assert/strict');

test('enableControlUiInsecureAuthForClawke creates gateway control UI config', async () => {
  const { enableControlUiInsecureAuthForClawke } = await import(
    '../dist/cli/openclaw-gateway-installer.js'
  );
  const config = {};

  const changed = enableControlUiInsecureAuthForClawke(config);

  assert.equal(changed, true);
  assert.deepEqual(config, {
    gateway: {
      controlUi: {
        allowInsecureAuth: true,
      },
    },
  });
});

test('enableControlUiInsecureAuthForClawke preserves existing control UI config', async () => {
  const { enableControlUiInsecureAuthForClawke } = await import(
    '../dist/cli/openclaw-gateway-installer.js'
  );
  const config = {
    gateway: {
      controlUi: {
        basePath: '/openclaw',
        allowInsecureAuth: false,
      },
    },
  };

  const changed = enableControlUiInsecureAuthForClawke(config);

  assert.equal(changed, true);
  assert.deepEqual(config.gateway.controlUi, {
    basePath: '/openclaw',
    allowInsecureAuth: true,
  });
});

test('enableControlUiInsecureAuthForClawke reports unchanged when already enabled', async () => {
  const { enableControlUiInsecureAuthForClawke } = await import(
    '../dist/cli/openclaw-gateway-installer.js'
  );
  const config = {
    gateway: {
      controlUi: {
        allowInsecureAuth: true,
      },
    },
  };

  const changed = enableControlUiInsecureAuthForClawke(config);

  assert.equal(changed, false);
  assert.equal(config.gateway.controlUi.allowInsecureAuth, true);
});

test('enableClawkePluginEntryForClawke creates enabled entry with conversation access hook', async () => {
  const { enableClawkePluginEntryForClawke } = await import(
    '../dist/cli/openclaw-gateway-installer.js'
  );
  const config = {};

  const changed = enableClawkePluginEntryForClawke(config);

  assert.equal(changed, true);
  assert.deepEqual(config, {
    plugins: {
      entries: {
        clawke: {
          enabled: true,
          hooks: {
            allowConversationAccess: true,
          },
        },
      },
    },
  });
});

test('enableClawkePluginEntryForClawke preserves explicit conversation access hook', async () => {
  const { enableClawkePluginEntryForClawke } = await import(
    '../dist/cli/openclaw-gateway-installer.js'
  );
  const config = {
    plugins: {
      entries: {
        clawke: {
          enabled: false,
          customSetting: 'keep-me',
          hooks: {
            allowConversationAccess: false,
            timeoutMs: 30000,
          },
        },
      },
    },
  };

  const changed = enableClawkePluginEntryForClawke(config);

  assert.equal(changed, false);
  assert.deepEqual(config.plugins.entries.clawke, {
    enabled: true,
    customSetting: 'keep-me',
    hooks: {
      allowConversationAccess: false,
      timeoutMs: 30000,
    },
  });
});

test('enableClawkePluginEntryForClawke preserves other hook fields while adding default access', async () => {
  const { enableClawkePluginEntryForClawke } = await import(
    '../dist/cli/openclaw-gateway-installer.js'
  );
  const config = {
    plugins: {
      entries: {
        clawke: {
          enabled: false,
          hooks: {
            timeoutMs: 30000,
          },
        },
      },
    },
  };

  const changed = enableClawkePluginEntryForClawke(config);

  assert.equal(changed, true);
  assert.deepEqual(config.plugins.entries.clawke, {
    enabled: true,
    hooks: {
      timeoutMs: 30000,
      allowConversationAccess: true,
    },
  });
});
