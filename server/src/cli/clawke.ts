#!/usr/bin/env node
/**
 * Clawke CLI 入口
 *
 * 用法：
 *   npx clawke gateway install   — 安装 Gateway 插件到本机 OpenClaw
 *   npx clawke server start      — 启动 Clawke Server
 *   npx clawke --help             — 显示帮助
 */

const args = process.argv.slice(2);
const command = args[0];
const subCommand = args[1];

async function main(): Promise<void> {
  if (command === 'gateway' && subCommand === 'install') {
    const { installGateway } = await import('./gateway-installer.js');
    await installGateway();

  } else if (command === 'server' && subCommand === 'start') {
    // 直接加载 server 入口
    await import('../index.js');

  } else {
    printHelp();
    process.exit(command === '--help' || command === '-h' ? 0 : 1);
  }
}

function printHelp(): void {
  console.log(`
  Clawke CLI

  Usage:
    npx clawke <command>

  Commands:
    gateway install    Install/update Clawke gateway plugin to local OpenClaw
    server start       Start Clawke Server

  Options:
    --help, -h         Show this help message

  Quick Start:
    cd server
    npm install
    npx clawke gateway install    # Install gateway + restart OpenClaw
    npx clawke server start       # Start CS Server
`);
}

main().catch((err) => {
  console.error('[clawke] Fatal error:', err.message);
  process.exit(1);
});
