const test = require('node:test');
const assert = require('node:assert/strict');
const os = require('node:os');
const path = require('node:path');

test('fetchClawHubSkillDetail uses anonymous request when no token or config exists', async () => {
  const client = require('../dist/services/clawhub-client');
  const restore = withClawHubEnv({
    OPENCLAW_CLAWHUB_CONFIG_PATH: path.join(os.tmpdir(), `missing-clawhub-${Date.now()}.json`),
  });
  const seen = [];
  try {
    const detail = await client.fetchClawHubSkillDetail({
      slug: 'github',
      fetchImpl: async (_url, init) => {
        seen.push(init?.headers);
        return jsonResponse({
          skill: { slug: 'github', displayName: 'Github' },
          latestVersion: { version: '1.0.0' },
        });
      },
    });
    assert.equal(detail.skill.slug, 'github');
    assert.equal(seen[0], undefined);
  } finally {
    restore();
  }
});

test('fetchClawHubSkillDetail sends bearer token from generic CLAWHUB_TOKEN without OpenClaw installed', async () => {
  const client = require('../dist/services/clawhub-client');
  const restore = withClawHubEnv({ CLAWHUB_TOKEN: 'clawhub-test-token' });
  const seen = [];
  try {
    await client.fetchClawHubSkillDetail({
      slug: 'github',
      fetchImpl: async (_url, init) => {
        seen.push(init?.headers);
        return jsonResponse({
          skill: { slug: 'github', displayName: 'Github' },
          latestVersion: { version: '1.0.0' },
        });
      },
    });
    assert.deepEqual(seen[0], { Authorization: 'Bearer clawhub-test-token' });
  } finally {
    restore();
  }
});

test('fetchClawHubSkillDetail explains anonymous rate limit with token guidance', async () => {
  const client = require('../dist/services/clawhub-client');
  const restore = withClawHubEnv({
    OPENCLAW_CLAWHUB_CONFIG_PATH: path.join(os.tmpdir(), `missing-clawhub-${Date.now()}.json`),
  });
  try {
    await assert.rejects(
      () => client.fetchClawHubSkillDetail({
        slug: 'github',
        fetchImpl: async () => new Response('Too many requests', {
          status: 429,
          headers: { 'Retry-After': '30' },
        }),
      }),
      (err) => err.status === 429 && err.message.includes('CLAWHUB_TOKEN'),
    );
  } finally {
    restore();
  }
});

function jsonResponse(body) {
  return new Response(JSON.stringify(body), {
    status: 200,
    headers: { 'content-type': 'application/json' },
  });
}

function withClawHubEnv(next) {
  const keys = [
    'OPENCLAW_CLAWHUB_TOKEN',
    'CLAWHUB_TOKEN',
    'CLAWHUB_AUTH_TOKEN',
    'OPENCLAW_CLAWHUB_CONFIG_PATH',
    'CLAWHUB_CONFIG_PATH',
    'CLAWDHUB_CONFIG_PATH',
  ];
  const previous = Object.fromEntries(keys.map((key) => [key, process.env[key]]));
  for (const key of keys) delete process.env[key];
  Object.assign(process.env, next);
  return () => {
    for (const key of keys) {
      if (previous[key] === undefined) {
        delete process.env[key];
      } else {
        process.env[key] = previous[key];
      }
    }
  };
}
