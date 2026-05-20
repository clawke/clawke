import test from 'node:test';
import assert from 'node:assert/strict';
import { createServer } from 'node:http';
import { existsSync, mkdtempSync, readFileSync, rmSync, writeFileSync } from 'node:fs';
import { mkdir, rm } from 'node:fs/promises';
import { tmpdir } from 'node:os';
import { join } from 'node:path';
import { execFileSync } from 'node:child_process';

test('managed SkillHub install downloads ClawHub zip into isolated CLAWKE_DATA_DIR', async () => {
  const runtimeDir = mkdtempSync(join(tmpdir(), 'clawke-skillhub-e2e-runtime-'));
  const packageDir = mkdtempSync(join(tmpdir(), 'clawke-skillhub-e2e-package-'));
  const archivePath = join(packageDir, 'weather.zip');
  const skillRoot = join(packageDir, 'weather');
  await mkdir(skillRoot, { recursive: true });
  writeFileSync(join(skillRoot, 'SKILL.md'), '# Weather\n\nUse for weather lookup.\n', 'utf8');
  execFileSync('zip', ['-qr', archivePath, 'weather'], { cwd: packageDir });
  const archiveBytes = readFileSync(archivePath);

  const server = createServer((req, res) => {
    const url = new URL(req.url || '/', 'http://127.0.0.1');
    if (url.pathname === '/api/v1/skills/weather') {
      res.setHeader('Content-Type', 'application/json');
      res.end(JSON.stringify({
        skill: { slug: 'weather', displayName: 'Weather' },
        latestVersion: { version: '1.0.0' },
      }));
      return;
    }
    if (url.pathname === '/api/v1/download' && url.searchParams.get('slug') === 'weather') {
      res.setHeader('Content-Type', 'application/zip');
      res.end(archiveBytes);
      return;
    }
    res.statusCode = 404;
    res.end('not found');
  });
  await new Promise((resolve) => server.listen(0, '127.0.0.1', resolve));
  const address = server.address();
  assert.ok(address && typeof address === 'object');

  const previousDataDir = process.env.CLAWKE_DATA_DIR;
  const previousClawHubUrl = process.env.OPENCLAW_CLAWHUB_URL;
  process.env.CLAWKE_DATA_DIR = runtimeDir;
  process.env.OPENCLAW_CLAWHUB_URL = `http://127.0.0.1:${address.port}`;

  try {
    const runner = await import(`../dist/services/skillhub-install-runner.js?case=${Date.now()}`);
    const result = await runner.startManagedSkillHubInstall({
      installId: 'skillhub_test_weather',
      installMode: 'managed',
      installPackage: { slug: 'weather', source: 'clawhub' },
    });
    assert.equal(result.status, 'accepted');

    await waitFor(() => existsSync(join(runtimeDir, 'skills', 'weather', 'SKILL.md')));
    assert.equal(
      readFileSync(join(runtimeDir, 'skills', 'weather', 'SKILL.md'), 'utf8'),
      '# Weather\n\nUse for weather lookup.\n',
    );
    const lock = JSON.parse(readFileSync(join(runtimeDir, 'skills', '.skillhub', 'lock.json'), 'utf8'));
    assert.equal(lock.skills.weather.version, '1.0.0');
    assert.equal(typeof lock.skills.weather.archiveSha256, 'string');
    assert.ok(existsSync(join(runtimeDir, 'skills', 'weather', '.skillhub', 'origin.json')));
    assert.ok(existsSync(join(runtimeDir, 'skills', 'weather', '.clawhub', 'origin.json')));
  } finally {
    if (previousDataDir === undefined) {
      delete process.env.CLAWKE_DATA_DIR;
    } else {
      process.env.CLAWKE_DATA_DIR = previousDataDir;
    }
    if (previousClawHubUrl === undefined) {
      delete process.env.OPENCLAW_CLAWHUB_URL;
    } else {
      process.env.OPENCLAW_CLAWHUB_URL = previousClawHubUrl;
    }
    await new Promise((resolve) => server.close(resolve));
    rmSync(runtimeDir, { recursive: true, force: true });
    await rm(packageDir, { recursive: true, force: true });
  }
});

async function waitFor(predicate) {
  const deadline = Date.now() + 5000;
  while (Date.now() < deadline) {
    if (predicate()) return;
    await new Promise((resolve) => setTimeout(resolve, 50));
  }
  assert.fail('timed out waiting for managed SkillHub install');
}
