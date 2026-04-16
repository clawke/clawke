/**
 * Server 日志持久化模块
 *
 * 调用 initLogger() 后，所有 console.log / console.error / console.warn
 * 都会同时写入日志文件（按天轮转）。
 *
 * 日志路径：~/.clawke/logs/server-YYYY-MM-DD.log
 * 格式：[ISO时间] [LEVEL] 原始内容
 */
import { appendFileSync, mkdirSync, existsSync } from 'fs';
import { join } from 'path';
import { homedir } from 'os';

const LOG_DIR = join(homedir(), '.clawke', 'logs');
let logDate = '';
let logPath = '';

// 保存原始 console 方法
const originalLog = console.log.bind(console);
const originalError = console.error.bind(console);
const originalWarn = console.warn.bind(console);

function ensureLogFile(): string {
  const now = new Date();
  const today = now.toISOString().slice(0, 10);
  if (today !== logDate) {
    logDate = today;
    if (!existsSync(LOG_DIR)) mkdirSync(LOG_DIR, { recursive: true });
    logPath = join(LOG_DIR, `server-${today}.log`);
  }
  return logPath;
}

function writeToFile(level: string, args: unknown[]): void {
  try {
    const path = ensureLogFile();
    const ts = new Date().toISOString();
    const msg = args.map(a =>
      typeof a === 'string' ? a : JSON.stringify(a)
    ).join(' ');
    appendFileSync(path, `[${ts}] [${level}] ${msg}\n`);
  } catch {
    // 日志写入失败不影响主流程
  }
}

/**
 * 初始化日志持久化，hook console.log/error/warn
 * 调用一次即可，通常在 server 启动入口调用。
 */
export function initLogger(): void {
  console.log = (...args: unknown[]) => {
    originalLog(...args);
    writeToFile('INFO', args);
  };

  console.error = (...args: unknown[]) => {
    originalError(...args);
    writeToFile('ERROR', args);
  };

  console.warn = (...args: unknown[]) => {
    originalWarn(...args);
    writeToFile('WARN', args);
  };

  console.log(`[Logger] File logging enabled: ${LOG_DIR}/server-YYYY-MM-DD.log`);
}
