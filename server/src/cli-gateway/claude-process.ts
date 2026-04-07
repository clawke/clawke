/**
 * Claude Code 子进程管理
 *
 * spawn claude CLI with --input-format stream-json --output-format stream-json
 * 通过 stdin/stdout JSON 管道实现双向通信
 */
import { spawn, type ChildProcess } from 'child_process';
import { createInterface } from 'readline';
import { EventEmitter } from 'events';
import type { SdkMessage, SdkUserInput, SdkControlResponse } from './types.js';

export interface ClaudeProcessOptions {
  /** 工作目录 */
  cwd: string;
  /** 恢复已有会话 */
  sessionId?: string;
  /** 权限模式：default | plan | bypassPermissions */
  permissionMode?: string;
  /** claude 命令路径（默认 'claude'） */
  claudePath?: string;
}

export class ClaudeProcess extends EventEmitter {
  private child: ChildProcess | null = null;
  private _sessionId: string | null = null;
  private _running = false;

  get sessionId(): string | null { return this._sessionId; }
  get running(): boolean { return this._running; }

  /**
   * 启动 Claude Code 子进程
   */
  async start(opts: ClaudeProcessOptions): Promise<void> {
    if (this.child) {
      console.warn('[ClaudeProcess] Already running, stop first');
      return;
    }

    const claudeCmd = opts.claudePath || 'claude';
    const args: string[] = [
      '--output-format', 'stream-json',
      '--input-format', 'stream-json',
      '--verbose',
    ];

    // 权限审批走 stdio 管道（不依赖终端弹窗）
    args.push('--permission-prompt-tool', 'stdio');

    if (opts.sessionId) {
      args.push('--resume', opts.sessionId);
    }
    if (opts.permissionMode) {
      args.push('--permission-mode', opts.permissionMode);
    }

    console.log(`[ClaudeProcess] Starting: ${claudeCmd} ${args.join(' ')}`);
    console.log(`[ClaudeProcess] cwd: ${opts.cwd}`);

    this.child = spawn(claudeCmd, args, {
      cwd: opts.cwd,
      stdio: ['pipe', 'pipe', 'pipe'],
      env: { ...process.env },
    });

    this._running = true;

    // stdout — 逐行读取 JSON 消息
    const rl = createInterface({ input: this.child.stdout! });
    rl.on('line', (line: string) => {
      const trimmed = line.trim();
      if (!trimmed) return;
      try {
        const msg: SdkMessage = JSON.parse(trimmed);

        // 捕获 session_id
        if (msg.type === 'system' && msg.subtype === 'init' && msg.session_id) {
          this._sessionId = msg.session_id;
          console.log(`[ClaudeProcess] Session: ${this._sessionId}`);
        }

        this.emit('message', msg);
      } catch {
        // 非 JSON 行，忽略
        console.log(`[ClaudeProcess] Non-JSON stdout: ${trimmed.slice(0, 100)}`);
      }
    });

    // stderr — 日志输出
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
      this.child = null;
      this.emit('exit', code, signal);
    });

    this.child.on('error', (err: Error) => {
      console.error(`[ClaudeProcess] Spawn error: ${err.message}`);
      this._running = false;
      this.child = null;
      this.emit('error', err);
    });
  }

  /**
   * 发送用户消息
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
    console.log(`[ClaudeProcess] → User message: ${text.slice(0, 80)}...`);
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

  /**
   * 中止当前执行
   */
  abort(): void {
    if (this.child) {
      console.log('[ClaudeProcess] Aborting...');
      this.child.kill('SIGINT');  // SIGINT 让 Claude Code 优雅停止当前任务
    }
  }

  /**
   * 停止子进程
   */
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
    }
  }
}
