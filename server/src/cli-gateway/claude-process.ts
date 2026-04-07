/**
 * Claude Code 子进程管理
 *
 * 关键发现（来自 Happy 源码 + 实测）：
 * 1. 必须加 `-p` (--print) 才能进入非交互模式，否则 Claude 进入 TUI/Ink 模式
 * 2. `-p` + `--input-format stream-json` 组合启用多轮持续对话
 * 3. 立即写入 stdin，不需要等 system init（Happy streamToStdin 也是立即写）
 *    否则会死锁：server 等 init → Claude 等 stdin input → forever
 * 4. 参考 Happy: packages/happy-cli/src/claude/sdk/query.ts L287-L362
 */
import { spawn, type ChildProcess } from 'child_process';
import { createInterface } from 'readline';
import { EventEmitter } from 'events';
import { homedir } from 'os';
import { existsSync } from 'fs';
import { join } from 'path';
import type { SdkMessage, SdkUserInput, SdkControlResponse } from './types.js';

export interface ClaudeProcessOptions {
  /** 工作目录 */
  cwd: string;
  /** 恢复已有会话 */
  sessionId?: string;
  /** 权限模式：default | plan | bypassPermissions */
  permissionMode?: string;
  /** claude 命令路径（默认自动检测） */
  claudePath?: string;
}

export class ClaudeProcess extends EventEmitter {
  private child: ChildProcess | null = null;
  private _sessionId: string | null = null;
  private _running = false;
  private _ready = false;  // system init 是否已收到

  get sessionId(): string | null { return this._sessionId; }
  get running(): boolean { return this._running; }
  get ready(): boolean { return this._ready; }

  /**
   * 自动检测 claude 命令路径
   * 参考 Happy: sdk/utils.ts getDefaultClaudeCodePath()
   */
  private resolveClaude(userPath?: string): string {
    if (userPath) return userPath;

    // 检查常见安装位置
    const candidates = [
      join(homedir(), '.local', 'bin', 'claude'),
      join(homedir(), '.claude', 'local', 'claude'),
      '/usr/local/bin/claude',
    ];
    for (const p of candidates) {
      if (existsSync(p)) return p;
    }

    // fallback: 依赖 PATH
    return 'claude';
  }

  /**
   * 构建 clean env（参考 Happy: sdk/utils.ts getCleanEnv()）
   * 移除 local node_modules/.bin 避免冲突
   */
  private getCleanEnv(): NodeJS.ProcessEnv {
    const env = { ...process.env };
    const cwd = process.cwd();
    const PATH = env.PATH || '';

    // 移除包含当前 cwd 的 node_modules/.bin 路径
    env.PATH = PATH.split(':')
      .filter(p => !p.includes(join(cwd, 'node_modules')))
      .join(':');

    return env;
  }

  /**
   * 启动 Claude Code 子进程
   */
  async start(opts: ClaudeProcessOptions): Promise<void> {
    if (this.child) {
      console.warn('[ClaudeProcess] Already running, stop first');
      return;
    }

    const claudeCmd = this.resolveClaude(opts.claudePath);

    // 参考 Happy query.ts L287-L321:
    // args 固定包含 --output-format stream-json --verbose
    // 加 -p (--print) 进入非交互模式
    // 加 --input-format stream-json 启用多轮 stdin 输入
    const args: string[] = [
      '-p',                           // 非交互模式（必须！）
      '--output-format', 'stream-json',
      '--input-format', 'stream-json',
      '--verbose',
    ];

    // 权限审批走 stdio 管道
    args.push('--permission-prompt-tool', 'stdio');

    if (opts.sessionId) {
      args.push('--resume', opts.sessionId);
    }
    if (opts.permissionMode) {
      args.push('--permission-mode', opts.permissionMode);
    }

    console.log(`[ClaudeProcess] Starting: ${claudeCmd} ${args.join(' ')}`);
    console.log(`[ClaudeProcess] cwd: ${opts.cwd}`);

    const env = this.getCleanEnv();

    this.child = spawn(claudeCmd, args, {
      cwd: opts.cwd,
      stdio: ['pipe', 'pipe', 'pipe'],
      env,
    });

    this._running = true;
    this._ready = false;

    // stdout — 逐行读取 JSON 消息
    const rl = createInterface({ input: this.child.stdout! });
    rl.on('line', (line: string) => {
      const trimmed = line.trim();
      if (!trimmed) return;
      try {
        const msg: SdkMessage = JSON.parse(trimmed);

        // 捕获 session_id
        if (msg.type === 'system' && msg.subtype === 'init') {
          this._sessionId = msg.session_id || null;
          this._ready = true;
          console.log(`[ClaudeProcess] ✅ Ready! Session: ${this._sessionId}`);
        }

        this.emit('message', msg);
      } catch {
        console.log(`[ClaudeProcess] Non-JSON stdout: ${trimmed.slice(0, 100)}`);
      }
    });

    // stderr — 日志
    this.child.stderr?.on('data', (data: Buffer) => {
      const text = data.toString().trim();
      if (text) {
        for (const line of text.split('\n')) {
          console.log(`[Claude stderr] ${line}`);
        }
      }
    });

    // 进程退出
    this.child.on('exit', (code: number | null, signal: string | null) => {
      console.log(`[ClaudeProcess] Exited: code=${code}, signal=${signal}`);
      this._running = false;
      this._ready = false;
      this.child = null;
      this.emit('exit', code, signal);
    });

    this.child.on('error', (err: Error) => {
      console.error(`[ClaudeProcess] Spawn error: ${err.message}`);
      this._running = false;
      this._ready = false;
      this.child = null;
      this.emit('error', err);
    });
  }

  /**
   * 发送用户消息（立即写入 stdin，OS pipe 缓冲区会暂存）
   * 参考 Happy: streamToStdin() 也是立即写，不等 init
   */
  sendMessage(text: string): void {
    if (!this.child?.stdin?.writable) {
      console.error('[ClaudeProcess] stdin not writable');
      return;
    }

    const msg: SdkUserInput = {
      type: 'user',
      message: { role: 'user', content: text },
    };
    this.child.stdin.write(JSON.stringify(msg) + '\n');
    console.log(`[ClaudeProcess] → User: ${text.slice(0, 80)}...`);
  }

  /**
   * 回复权限审批请求
   */
  sendPermissionResponse(requestId: string, allow: boolean): void {
    if (!this.child?.stdin?.writable) {
      console.error('[ClaudeProcess] stdin not writable');
      return;
    }
    const msg: SdkControlResponse = {
      type: 'control_response',
      response: {
        subtype: 'success',
        request_id: requestId,
        response: { behavior: allow ? 'allow' : 'deny' },
      },
    };
    this.child.stdin.write(JSON.stringify(msg) + '\n');
    console.log(`[ClaudeProcess] → Permission ${allow ? 'ALLOW' : 'DENY'}: ${requestId}`);
  }

  /** 中止当前执行 */
  abort(): void {
    if (this.child) {
      console.log('[ClaudeProcess] Aborting (SIGINT)...');
      this.child.kill('SIGINT');
    }
  }

  /** 停止子进程 */
  stop(): void {
    if (this.child) {
      console.log('[ClaudeProcess] Stopping...');
      this.child.kill('SIGTERM');
      const ref = this.child;
      setTimeout(() => {
        if (ref && !ref.killed) ref.kill('SIGKILL');
      }, 3000);
      this.child = null;
      this._running = false;
      this._ready = false;
    }
  }

}
