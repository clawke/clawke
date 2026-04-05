#!/usr/bin/env node
/**
 * 回归测试运行器
 *
 * 按层级依次运行：
 *   1. 单元测试（media-resolution）
 *   2. 集成测试（media-upload）
 *   3. 端到端测试（media-e2e）— 可选，需要 OpenClaw
 *
 * 运行：node test/regression/run-all.js [--skip-e2e]
 */

const { execSync, spawnSync } = require('child_process');
const path = require('path');

const REGRESSION_DIR = __dirname;
const SERVER_DIR = path.join(REGRESSION_DIR, '..', '..');
const skipE2E = process.argv.includes('--skip-e2e');

const tests = [
  { name: '单元测试：媒体解析', file: 'media-resolution.test.js', runner: 'node --test' },
  { name: '集成测试：媒体上传', file: 'media-upload.test.js', runner: 'node' },
];

if (!skipE2E) {
  tests.push({ name: '端到端：CS → OpenClaw → AI', file: 'media-e2e.test.js', runner: 'node' });
}

console.log('╔══════════════════════════════════════╗');
console.log('║       Clawke 回归测试                 ║');
console.log('╚══════════════════════════════════════╝\n');

if (skipE2E) {
  console.log('⏭️  跳过端到端测试（--skip-e2e）\n');
}

let allPassed = true;

for (const test of tests) {
  console.log(`\n━━━ ${test.name} ━━━`);
  const filePath = path.join(REGRESSION_DIR, test.file);
  const result = spawnSync(test.runner.split(' ')[0], [...test.runner.split(' ').slice(1), filePath], {
    cwd: SERVER_DIR,
    stdio: 'inherit',
    timeout: 300000, // 5 min
  });

  if (result.status !== 0) {
    console.error(`\n❌ ${test.name} 失败！`);
    allPassed = false;
    if (!process.argv.includes('--continue-on-failure')) {
      console.error('中止后续测试。使用 --continue-on-failure 继续。');
      process.exit(1);
    }
  } else {
    console.log(`✅ ${test.name} 通过`);
  }
}

console.log('\n' + '═'.repeat(40));
if (allPassed) {
  console.log('🎉 全部回归测试通过！可以发布。');
} else {
  console.log('❌ 部分回归测试失败，请修复后重试。');
}
console.log('═'.repeat(40));

process.exit(allPassed ? 0 : 1);
