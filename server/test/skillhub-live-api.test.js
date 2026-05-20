const test = require('node:test');
const assert = require('node:assert/strict');
const { execFile } = require('node:child_process');
const { promisify } = require('node:util');

const execFileAsync = promisify(execFile);

const apiBaseUrl = (process.env.CLAWKE_SKILLHUB_LIVE_API_URL || '').replace(/\/$/, '');
const authToken = (
  process.env.CLAWKE_SKILLHUB_AUTH_TOKEN ||
  process.env.CLAWKE_RELAY_TOKEN ||
  ''
).trim();
const gatewayType = (process.env.CLAWKE_SKILLHUB_GATEWAY_TYPE || '').trim();
const tag = (process.env.CLAWKE_SKILLHUB_TAG || '').trim();
const expectData = process.env.CLAWKE_SKILLHUB_EXPECT_DATA === '1';

const skipReason = apiBaseUrl
  ? (authToken ? false : 'Set CLAWKE_SKILLHUB_AUTH_TOKEN to run live SkillHub API smoke tests.')
  : 'Set CLAWKE_SKILLHUB_LIVE_API_URL to run live SkillHub API smoke tests.';

test('live SkillHub catalog and detail API match the public contract', { skip: skipReason }, async () => {
  const catalog = await getJson('/api/skillhub/v1/skills.json', {
    limit: '10',
    ...(gatewayType ? { gatewayType } : {}),
    ...(tag ? { tag } : {}),
  });

  assert.equal(catalog.success, true);
  assert.equal(typeof catalog.value, 'object');
  assert.ok(Array.isArray(catalog.value.list));
  assert.equal(catalog.value.nextCursor === null || typeof catalog.value.nextCursor === 'string', true);
  assert.equal(typeof catalog.value.total, 'number');

  if (catalog.value.list.length === 0) {
    if (expectData) {
      assert.fail('Live SkillHub API returned no published skills.');
    }
    return;
  }

  const first = catalog.value.list[0];
  assert.ok(first.id !== undefined && first.id !== null);
  assert.equal(typeof first.name, 'string');
  assert.notEqual(first.name.trim(), '');
  assert.ok(Array.isArray(first.tags));
  assert.equal(typeof first.featured, 'boolean');
  assert.equal(typeof first.downloadCount, 'number');
  assert.equal(typeof first.packageUrl, 'string');
  assert.match(first.packageUrl, /^https?:\/\//);
  assert.equal(typeof first.packageSha256, 'string');
  assert.notEqual(first.packageSha256.trim(), '');
  assert.ok(Array.isArray(first.compatibleGateways));

  if (tag) {
    const normalizedTags = first.tags.map((value) => String(value).toLowerCase());
    assert.ok(
      normalizedTags.includes(tag.toLowerCase()),
      `Expected first item tags to include ${tag}, got ${JSON.stringify(first.tags)}`,
    );
  }

  const detail = await getJson('/api/skillhub/v1/skill.json', {
    id: String(first.id),
    ...(gatewayType ? { gatewayType } : {}),
  });

  assert.equal(detail.success, true);
  assert.equal(typeof detail.value, 'object');
  assert.equal(String(detail.value.id), String(first.id));
  assert.equal(typeof detail.value.name, 'string');
  assert.notEqual(detail.value.name.trim(), '');
  assert.ok(Array.isArray(detail.value.tags));
  assert.equal(typeof detail.value.downloadCount, 'number');
  assert.equal(typeof detail.value.packageUrl, 'string');
  assert.match(detail.value.packageUrl, /^https?:\/\//);
  assert.equal(typeof detail.value.originalSkillMd, 'string');
});

async function getJson(path, query) {
  const url = new URL(path, apiBaseUrl);
  for (const [key, value] of Object.entries(query)) {
    url.searchParams.set(key, value);
  }

  const { stdout } = await execFileAsync('curl', [
    '--noproxy',
    '*',
    '--fail-with-body',
    '--silent',
    '--show-error',
    '--max-time',
    '20',
    '--header',
    `Authorization: Bearer ${authToken}`,
    url.toString(),
  ]);
  const text = stdout.trim();
  try {
    return JSON.parse(text);
  } catch (error) {
    assert.fail(`${url} returned invalid JSON: ${text}`);
  }
}
