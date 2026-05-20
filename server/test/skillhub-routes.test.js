const test = require('node:test');
const assert = require('node:assert/strict');

test('getSkillHubConfig returns relay apiBaseUrl and fixed Nirvana paths', async () => {
  const routes = require('../dist/routes/skillhub-routes');
  routes.initSkillHubRoutes({
    loadConfig: () => ({
      relay: {
        apiBaseUrl: 'https://local.clawke.ai/',
      },
    }),
  });

  const res = fakeRes();
  await routes.getSkillHubConfig(fakeReq(), res);

  assert.equal(res.statusCode, 200);
  assert.deepEqual(res.body, {
    provider: 'nirvana',
    apiBaseUrl: 'https://local.clawke.ai',
    skillsPath: '/api/skillhub/v1/skills.json',
    skillPath: '/api/skillhub/v1/skill.json',
  });
});

test('installSkillHubSkill keeps gateway native install path when explicitly requested', async () => {
  const routes = require('../dist/routes/skillhub-routes');
  const calls = [];
  routes.initSkillHubRoutes({
    getConnectedAccountIds: () => ['openclaw-local'],
    sendSkillRequest: async (payload) => {
      calls.push(payload);
      return {
        type: 'skillhub_install_response',
        request_id: payload.request_id,
        ok: true,
        status: 'accepted',
        message: '安装任务已提交',
      };
    },
  });

  const res = fakeRes();
  await routes.installSkillHubSkill(fakeReq({
    body: {
      id: '204',
      slug: 'github-helper',
      name: 'GitHub Helper',
      source: 'clawhub',
      installMode: 'gateway_native',
      sourceOwner: 'garrytan',
      version: '1.2.1',
      packageUrl: 'https://local.clawke.ai/upload/package.zip',
      packageSha256: 'bed752338e7a19db1074e239075c4cd24fd5da73b0d40bfe040a496d73119371',
      packageType: 'bundle',
      gatewayType: 'openclaw',
    },
  }), res);

  assert.equal(res.statusCode, 202);
  assert.match(res.body.value.installId, /^skillhub_/);
  assert.deepEqual(calls, [{
    type: 'skillhub_install',
    request_id: res.body.value.installId,
    install_id: res.body.value.installId,
    account_id: 'openclaw-local',
    install_mode: 'gateway_native',
    package: {
      id: '204',
      slug: 'github-helper',
      name: 'GitHub Helper',
      source: 'clawhub',
      sourceOwner: 'garrytan',
      version: '1.2.1',
      packageUrl: 'https://local.clawke.ai/upload/package.zip',
      packageSha256: 'bed752338e7a19db1074e239075c4cd24fd5da73b0d40bfe040a496d73119371',
      packageType: 'bundle',
      gatewayType: 'openclaw',
    },
  }]);
  assert.deepEqual(res.body, {
    success: true,
    value: {
      installId: res.body.value.installId,
      installed: false,
      status: 'accepted',
      message: '安装任务已提交',
      accountId: 'openclaw-local',
      installMode: 'gateway_native',
      slug: 'github-helper',
    },
  });
});

test('installSkillHubSkill starts managed install with slug-only ClawHub request', async () => {
  const routes = require('../dist/routes/skillhub-routes');
  const managedCalls = [];
  const gatewayCalls = [];
  routes.initSkillHubRoutes({
    canUseManagedSkillHubInstall: () => true,
    getConnectedGateways: () => [{
      gateway_id: 'openclaw-local',
      display_name: 'OpenClaw',
      gateway_type: 'openclaw',
      status: 'online',
      capabilities: ['skills'],
      last_seen_at: Date.now(),
      last_connected_at: Date.now(),
    }],
    startManagedSkillHubInstall: async (payload) => {
      managedCalls.push(payload);
      await payload.refreshGateways?.(payload.installPackage.slug);
      return {
        installed: false,
        status: 'accepted',
        message: '安装任务已提交',
      };
    },
    sendSkillRequest: async (payload) => {
      gatewayCalls.push(payload);
      return {
        type: 'skill_list_response',
        request_id: payload.request_id || 'refresh',
        ok: true,
        skills: [],
      };
    },
  });

  const res = fakeRes();
  await routes.installSkillHubSkill(fakeReq({
    body: {
      slug: 'github',
      source: 'clawhub',
    },
  }), res);

  assert.equal(res.statusCode, 202);
  assert.equal(gatewayCalls.length, 1);
  assert.equal(gatewayCalls[0].type, 'skill_list');
  assert.equal(gatewayCalls[0].account_id, 'openclaw-local');
  assert.equal(managedCalls.length, 1);
  assert.equal(managedCalls[0].installPackage.slug, 'github');
  assert.equal(managedCalls[0].installMode, 'managed');
  assert.deepEqual(res.body, {
    success: true,
    value: {
      installId: res.body.value.installId,
      installed: false,
      status: 'accepted',
      message: '安装任务已提交',
      installMode: 'managed',
      slug: 'github',
    },
  });
});

test('installSkillHubSkill falls back to gateway native install when managed root is unavailable', async () => {
  const routes = require('../dist/routes/skillhub-routes');
  const gatewayCalls = [];
  routes.initSkillHubRoutes({
    canUseManagedSkillHubInstall: () => false,
    getConnectedAccountIds: () => ['hermes'],
    getConnectedGateways: () => [{
      gateway_id: 'hermes',
      display_name: 'Hermes',
      gateway_type: 'hermes',
      status: 'online',
      capabilities: ['skills'],
    }],
    sendSkillRequest: async (payload) => {
      gatewayCalls.push(payload);
      return {
        type: 'skillhub_install_response',
        request_id: payload.request_id,
        ok: true,
        status: 'accepted',
        installed: false,
        message: 'Gateway 原生安装已提交',
      };
    },
  });

  const res = fakeRes();
  await routes.installSkillHubSkill(fakeReq({
    body: {
      slug: 'weather',
      source: 'clawhub',
    },
  }), res);

  assert.equal(res.statusCode, 202);
  assert.equal(gatewayCalls.length, 1);
  assert.equal(gatewayCalls[0].account_id, 'hermes');
  assert.equal(gatewayCalls[0].package.slug, 'weather');
  assert.equal(gatewayCalls[0].package.source, 'clawhub');
  assert.equal(gatewayCalls[0].install_mode, 'gateway_native');
  assert.deepEqual(res.body, {
    success: true,
    value: {
      installId: res.body.value.installId,
      installed: false,
      status: 'accepted',
      message: 'Gateway 原生安装已提交',
      accountId: 'hermes',
      installMode: 'gateway_native',
      slug: 'weather',
    },
  });
});

test('installSkillHubSkill asks client to choose gateway when fallback has multiple candidates', async () => {
  const routes = require('../dist/routes/skillhub-routes');
  routes.initSkillHubRoutes({
    canUseManagedSkillHubInstall: () => false,
    getConnectedAccountIds: () => ['OpenClaw', 'hermes'],
    getConnectedGateways: () => [
      {
        gateway_id: 'OpenClaw',
        display_name: 'OpenClaw',
        gateway_type: 'openclaw',
        status: 'online',
        capabilities: ['skills'],
      },
      {
        gateway_id: 'hermes',
        display_name: 'Hermes',
        gateway_type: 'hermes',
        status: 'online',
        capabilities: ['skills'],
      },
    ],
    sendSkillRequest: async () => {
      throw new Error('gateway request should wait for user selection');
    },
  });

  const res = fakeRes();
  await routes.installSkillHubSkill(fakeReq({
    body: {
      slug: 'github',
      source: 'clawhub',
    },
  }), res);

  assert.equal(res.statusCode, 409);
  assert.deepEqual(res.body, {
    success: false,
    actionError: 'fallback_gateway_required',
    message: '请选择要安装到的 Gateway',
    details: {
      gateways: [
        { gatewayId: 'OpenClaw', label: 'OpenClaw', gatewayType: 'openclaw' },
        { gatewayId: 'hermes', label: 'Hermes', gatewayType: 'hermes' },
      ],
    },
  });
});

test('installSkillHubSkill resolves a single compatible gateway type when selection is all', async () => {
  const routes = require('../dist/routes/skillhub-routes');
  const calls = [];
  routes.initSkillHubRoutes({
    getConnectedAccountIds: () => ['hermes', 'OpenClaw'],
    getConnectedGateways: () => [
      {
        gateway_id: 'hermes',
        display_name: 'Hermes',
        gateway_type: 'hermes',
        status: 'online',
        capabilities: ['skills'],
      },
      {
        gateway_id: 'OpenClaw',
        display_name: 'OpenClaw',
        gateway_type: 'openclaw',
        status: 'online',
        capabilities: ['skills'],
      },
    ],
    sendSkillRequest: async (payload) => {
      calls.push(payload);
      return {
        type: 'skillhub_install_response',
        request_id: 'req-2',
        ok: true,
        installed: true,
        status: 'installed',
        message: '安装完成',
      };
    },
  });

  const res = fakeRes();
  await routes.installSkillHubSkill(fakeReq({
    body: {
      id: '605',
      slug: 'github',
      name: 'Github',
      source: 'clawhub',
      sourceOwner: 'steipete',
      packageType: 'single',
      compatibleGateways: ['openclaw'],
    },
  }), res);

  assert.equal(res.statusCode, 200);
  assert.equal(calls[0].account_id, 'OpenClaw');
  assert.deepEqual(calls[0].package, {
    id: '605',
    slug: 'github',
    name: 'Github',
    source: 'clawhub',
    sourceOwner: 'steipete',
    packageType: 'single',
    compatibleGateways: ['openclaw'],
  });
});

test('installSkillHubSkill rejects missing package archive fields for non-ClawHub packages', async () => {
  const routes = require('../dist/routes/skillhub-routes');
  routes.initSkillHubRoutes({
    getConnectedAccountIds: () => ['openclaw-local'],
    sendSkillRequest: async () => {
      throw new Error('sendSkillRequest should not be called');
    },
  });

  const res = fakeRes();
  await routes.installSkillHubSkill(fakeReq({
    body: {
      id: '204',
      slug: 'github-helper',
      name: 'GitHub Helper',
      source: 'upload',
      version: '1.2.1',
      packageUrl: 'https://local.clawke.ai/upload/package.zip',
      packageType: 'bundle',
    },
  }), res);

  assert.equal(res.statusCode, 400);
  assert.deepEqual(res.body, {
    success: false,
    actionError: 'validation_error',
    message: 'packageSha256 is required.',
  });
});

function fakeReq(overrides = {}) {
  return {
    params: {},
    body: {},
    query: {},
    ...overrides,
  };
}

function fakeRes() {
  return {
    statusCode: 200,
    body: undefined,
    status(code) {
      this.statusCode = code;
      return this;
    },
    json(body) {
      this.body = body;
      return this;
    },
  };
}
