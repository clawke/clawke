const assert = require('node:assert/strict');
const fs = require('node:fs');
const path = require('node:path');
const test = require('node:test');

const repoRoot = path.resolve(__dirname, '..', '..');

test('clawke server start waits for server ready before starting gateways', () => {
  const cliSource = fs.readFileSync(path.join(repoRoot, 'server', 'src', 'cli', 'clawke.ts'), 'utf8');
  const serverStartBody = cliSource.match(/async function serverStart\(\): Promise<void> \{([\s\S]*?)\n\}/);

  assert.ok(serverStartBody, 'serverStart() not found');
  assert.match(serverStartBody[1], /const \{ startClawkeServer \} = await import\('\.\.\/index\.js'\)/);
  assert.match(serverStartBody[1], /await startClawkeServer\(\)/);
  assert.match(serverStartBody[1], /await startGateways\(\)/);
  assert.doesNotMatch(serverStartBody[1], /setTimeout/);
});

test('server index exports explicit startup function and keeps standalone startup guarded', () => {
  const indexSource = fs.readFileSync(path.join(repoRoot, 'server', 'src', 'index.ts'), 'utf8');

  assert.match(indexSource, /export async function startClawkeServer\(\)/);
  assert.match(indexSource, /import \{ printClientInstallBanner \} from '\.\/client-install-banner\.js'/);
  assert.match(indexSource, /function printReadyBanner\(httpPort: number\): void/);
  assert.match(indexSource, /const freshConfig = loadConfig\(\)/);
  assert.match(indexSource, /serverAddress: `http:\/\/127\.0\.0\.1:\$\{httpPort\}`/);
  assert.match(indexSource, /token: freshConfig\.relay\?\.token \|\| ''/);
  assert.equal((indexSource.match(/printReadyBanner\(HTTP_PORT\)/g) || []).length, 2);
  assert.match(indexSource, /await Promise\.all\(\[unifiedReady, mediaReady, upstreamReady\]\);\n\s+console\.log\('\[Server\] ✅ Ready'\);\n\s+printReadyBanner\(HTTP_PORT\);/);
  assert.match(indexSource, /await Promise\.all\(\[unifiedReady, mediaReady\]\);\n\s+console\.log\('\[Server\] ✅ Ready'\);\n\s+printReadyBanner\(HTTP_PORT\);/);
  assert.match(indexSource, /function isDirectRun\(entryPath: string \| undefined\): boolean/);
  assert.match(indexSource, /if \(isDirectRun\(process\.argv\[1\]\)\)/);
  assert.doesNotMatch(indexSource, /^main\(\)\.catch/m);
});

test('gateway children are started in a killable process group', () => {
  const cliSource = fs.readFileSync(path.join(repoRoot, 'server', 'src', 'cli', 'clawke.ts'), 'utf8');

  assert.match(cliSource, /function terminateGatewayProcess\(pid: number, signal: NodeJS\.Signals = 'SIGTERM'\): void/);
  assert.match(cliSource, /process\.kill\(-pid, signal\)/);
  assert.match(cliSource, /detached: process\.platform !== 'win32'/);
  assert.match(cliSource, /terminateGatewayProcess\(oldPid\)/);
  assert.match(cliSource, /terminateGatewayProcess\(child\.pid\)/);
});

test('server stop cleans gateways even when the server pid is missing or stale', () => {
  const cliSource = fs.readFileSync(path.join(repoRoot, 'server', 'src', 'cli', 'clawke.ts'), 'utf8');
  const serverStopBody = cliSource.match(/function serverStop\(\): void \{([\s\S]*?)\n\}/);

  assert.ok(serverStopBody, 'serverStop() not found');
  assert.match(serverStopBody[1], /stopAllGateways\(\)/);
  assert.match(serverStopBody[1], /stopFrpcFromPidFile\(\)/);
  assert.match(serverStopBody[1], /No PID file found/);
  assert.match(serverStopBody[1], /stale PID file/);
  assert.match(serverStopBody[1], /return/);
});

test('server lifecycle treats EPERM as an existing process and protects pid cleanup', () => {
  const cliSource = fs.readFileSync(path.join(repoRoot, 'server', 'src', 'cli', 'clawke.ts'), 'utf8');

  assert.match(cliSource, /return err\?\.code === 'EPERM'/);
  assert.match(cliSource, /function removePidFile\(expectedPid\?: number\): void/);
  assert.match(cliSource, /removePidFile\(process\.pid\)/);
});
