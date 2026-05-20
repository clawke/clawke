#!/usr/bin/env node
import assert from 'node:assert/strict';
import { existsSync, readFileSync, rmSync } from 'node:fs';
import { homedir } from 'node:os';
import { dirname, join, resolve } from 'node:path';

const BASE_URL = process.env.CLAWKE_E2E_HTTP_URL || 'http://127.0.0.1:8780';
const REQUEST_TIMEOUT_MS = Number(process.env.CLAWKE_E2E_TIMEOUT_MS || 180000);
const GATEWAY_TYPE = process.env.CLAWKE_E2E_GATEWAY_TYPE || 'hermes';
const SKILL_QUERY = process.env.CLAWKE_E2E_SKILLHUB_QUERY || 'weather';
const SKILL_SLUG = process.env.CLAWKE_E2E_SKILLHUB_SLUG || 'weather';

let token = '';
try {
  const cfg = JSON.parse(
    readFileSync(join(homedir(), '.clawke', 'clawke.json'), 'utf-8'),
  );
  token = cfg.relay?.token || '';
} catch {}

let gatewayId = process.env.CLAWKE_E2E_GATEWAY_ID || '';
let installedSkill = null;

async function main() {
  console.log('Clawke SkillHub Hermes install E2E');
  console.log(`Base URL: ${BASE_URL}`);
  console.log(`Gateway type: ${GATEWAY_TYPE}`);
  console.log(`Skill slug: ${SKILL_SLUG}`);

  gatewayId = gatewayId || await resolveGatewayId();
  console.log(`Gateway: ${gatewayId}\n`);

  const before = await findInstalledSkill();
  if (before) {
    console.log(`SKIP: ${before.id} already exists on ${gatewayId}; not deleting user data.`);
    return;
  }

  try {
    const skillHubItem = await loadSkillHubItem();
    await installSkill(skillHubItem);
    installedSkill = await requireInstalledSkill();
    assert.equal(
      installedSkill.deletable,
      true,
      `Installed SkillHub skill must be deletable for cleanup: ${installedSkill.id}`,
    );
  } finally {
    if (installedSkill) {
      await cleanupInstalledSkill(installedSkill);
    }
  }

  const after = await findInstalledSkill();
  assert.equal(after, null, `Skill still exists after cleanup: ${SKILL_SLUG}`);
  console.log('\nPASS: SkillHub Hermes install e2e');
}

async function resolveGatewayId() {
  const response = await request('/api/gateways');
  assert.equal(response.status, 200, response.text);
  const gateways = response.json.gateways || [];
  const gateway = gateways.find(
    (item) =>
      item.status === 'online' &&
      item.gateway_type === GATEWAY_TYPE &&
      Array.isArray(item.capabilities) &&
      item.capabilities.includes('skills'),
  );
  assert.ok(
    gateway,
    `No online ${GATEWAY_TYPE} gateway with skills capability. Set CLAWKE_E2E_GATEWAY_ID to run against a specific gateway.`,
  );
  return gateway.gateway_id;
}

async function loadSkillHubItem() {
  const configResponse = await request('/api/skillhub/config');
  assert.equal(configResponse.status, 200, configResponse.text);
  const config = configResponse.json;
  const catalogUrl = new URL(config.skillsPath, config.apiBaseUrl);
  catalogUrl.searchParams.set('query', SKILL_QUERY);
  catalogUrl.searchParams.set('limit', '10');
  const catalog = await requestUrl(catalogUrl, { auth: true });
  assert.equal(catalog.status, 200, catalog.text);
  const items = valueMap(catalog.json).list || [];
  const item = items.find((candidate) => candidate.slug === SKILL_SLUG);
  assert.ok(item, `SkillHub item not found: ${SKILL_SLUG}`);
  return item;
}

async function installSkill(item) {
  const response = await request('/api/skillhub/install', {
    method: 'POST',
    body: {
      id: String(item.id),
      slug: item.slug,
      name: item.name,
      source: item.source,
      sourceOwner: item.sourceOwner,
      version: item.version,
      packageUrl: item.packageUrl,
      packageSha256: item.packageSha256,
      packageType: item.packageType,
      compatibleGateways: item.compatibleGateways || [],
      gateway_id: gatewayId,
      gatewayType: GATEWAY_TYPE,
    },
  });

  assert.ok(
    response.status === 200 || response.status === 202,
    `${response.text}\n${response.status} !== 200/202`,
  );
  const value = valueMap(response.json);
  if (response.status === 202 || value.status === 'accepted') {
    assert.equal(value.installed, false, response.text);
    assert.ok(value.installId, response.text);
    return;
  }
  assert.equal(value.installed, true, response.text);
  if (value.skill) installedSkill = value.skill;
}

async function requireInstalledSkill() {
  const deadline = Date.now() + REQUEST_TIMEOUT_MS;
  while (Date.now() < deadline) {
    const skill = await findInstalledSkill();
    if (skill) return skill;
    await sleep(1000);
  }
  assert.fail(`Installed skill not found in /api/skills: ${SKILL_SLUG}`);
}

async function findInstalledSkill() {
  const response = await request('/api/skills', {
    query: { gateway_id: gatewayId },
  });
  assert.equal(response.status, 200, response.text);
  const skills = response.json.skills || [];
  return skills.find(skillMatchesSlug) || null;
}

function sleep(ms) {
  return new Promise((resolve) => setTimeout(resolve, ms));
}

function skillMatchesSlug(skill) {
  const values = [skill.id, skill.name, skill.path, skill.absolutePath]
    .filter(Boolean)
    .map((value) => String(value).toLowerCase());
  return values.some(
    (value) => value === SKILL_SLUG || value.endsWith(`/${SKILL_SLUG}`),
  );
}

async function cleanupInstalledSkill(skill) {
  const [category, name] = String(skill.id).split('/');
  let deleteError = null;
  try {
    assert.ok(category && name, `Invalid skill id for delete: ${skill.id}`);
    const response = await request(
      `/api/skills/${encodeURIComponent(category)}/${encodeURIComponent(name)}`,
      {
        method: 'DELETE',
        query: { gateway_id: gatewayId },
      },
    );
    assert.equal(response.status, 200, response.text);
    assert.equal(response.json.ok, true, response.text);
  } catch (err) {
    deleteError = err;
  }

  if (deleteError) {
    cleanupFilesystemFallback(skill);
    throw deleteError;
  }
}

function cleanupFilesystemFallback(skill) {
  const absolutePath = String(skill.absolutePath || '');
  const root = String(skill.root || '');
  if (!absolutePath || !root) return;
  const skillDir = resolve(dirname(absolutePath));
  const safeRoot = resolve(root);
  if (!skillDir.startsWith(`${safeRoot}/`)) return;
  if (existsSync(skillDir)) {
    rmSync(skillDir, { recursive: true, force: true });
  }
}

function valueMap(json) {
  assert.equal(json.success, true, JSON.stringify(json));
  assert.ok(json.value && typeof json.value === 'object', JSON.stringify(json));
  return json.value;
}

async function request(path, { method = 'GET', query, body } = {}) {
  const url = new URL(path, BASE_URL);
  for (const [key, value] of Object.entries(query || {})) {
    if (value !== undefined && value !== null && value !== '') {
      url.searchParams.set(key, String(value));
    }
  }
  return requestUrl(url, { method, body, auth: true });
}

async function requestUrl(url, { method = 'GET', body, auth = false } = {}) {
  const controller = new AbortController();
  const timeout = setTimeout(() => controller.abort(), REQUEST_TIMEOUT_MS);
  try {
    const response = await fetch(url, {
      method,
      signal: controller.signal,
      headers: {
        ...(auth && token ? { Authorization: `Bearer ${token}` } : {}),
        ...(body === undefined ? {} : { 'Content-Type': 'application/json' }),
      },
      body: body === undefined ? undefined : JSON.stringify(body),
    });
    const text = await response.text();
    let json = null;
    try {
      json = text ? JSON.parse(text) : null;
    } catch {}
    return { status: response.status, json, text };
  } finally {
    clearTimeout(timeout);
  }
}

main().catch((err) => {
  console.error('\nFAIL:', err instanceof Error ? err.message : err);
  process.exit(1);
});
