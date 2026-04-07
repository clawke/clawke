/**
 * CLI Gateway — Claude Code ↔ Clawke Server 桥接模块
 *
 * 核心职责：
 * 1. 管理 Claude Code 子进程（spawn + stdio pipe）
 * 2. 将 SDK 消息转译为 CUP 协议并广播给客户端
 * 3. 将客户端的用户消息/权限审批转发给 Claude Code
 */
import { ClaudeProcess, type ClaudeProcessOptions } from './claude-process.js';
import { translateSdkToCup } from './sdk-to-cup.js';
import type { SdkMessage } from './types.js';

export interface CliGatewayDeps {
  /** 广播 CUP 消息给所有客户端 */
  broadcast: (msg: Record<string, unknown>) => void;
}

export class CliGateway {
  private claude: ClaudeProcess;
  private broadcast: (msg: Record<string, unknown>) => void;
  private accountId = 'cli';

  constructor(deps: CliGatewayDeps) {
    this.broadcast = deps.broadcast;
    this.claude = new ClaudeProcess();

    // Claude 输出 → CUP 转译 → 广播
    this.claude.on('message', (sdkMsg: SdkMessage) => {
      const cupMessages = translateSdkToCup(sdkMsg, this.accountId);
      for (const cup of cupMessages) {
        if (!cup.created_at) cup.created_at = Date.now();
        this.broadcast(cup as Record<string, unknown>);
      }
    });

    // Claude 退出 → 通知客户端
    this.claude.on('exit', (code: number | null) => {
      this.broadcast({
        payload_type: 'system_status',
        status: 'ai_disconnected',
        agent_name: 'Claude Code',
        account_id: this.accountId,
        exit_code: code,
        created_at: Date.now(),
      });
    });

    // Claude 启动失败 → 通知客户端
    this.claude.on('error', (err: Error) => {
      this.broadcast({
        payload_type: 'system_status',
        status: 'ai_error',
        agent_name: 'Claude Code',
        account_id: this.accountId,
        error: err.message,
        created_at: Date.now(),
      });
    });
  }

  /**
   * 启动 Claude Code 子进程
   */
  async start(opts: ClaudeProcessOptions): Promise<void> {
    await this.claude.start(opts);
  }

  /**
   * 处理客户端发来的用户消息
   */
  handleUserMessage(text: string): void {
    if (!this.claude.running) {
      console.warn('[CliGateway] Claude Code not running, cannot send message');
      this.broadcast({
        payload_type: 'system_status',
        status: 'ai_error',
        agent_name: 'Claude Code',
        account_id: this.accountId,
        error: 'Claude Code is not running',
        created_at: Date.now(),
      });
      return;
    }
    this.claude.sendMessage(text);
  }

  /**
   * 处理客户端的权限审批
   */
  handleToolApproval(requestId: string, approved: boolean): void {
    this.claude.sendPermissionResponse(requestId, approved);
  }

  /**
   * 中止当前任务
   */
  handleAbort(): void {
    this.claude.abort();
    this.broadcast({
      payload_type: 'system_status',
      status: 'stream_interrupted',
      account_id: this.accountId,
      message: 'User aborted',
      created_at: Date.now(),
    });
  }

  /**
   * 停止 Gateway
   */
  stop(): void {
    this.claude.stop();
  }

  get running(): boolean {
    return this.claude.running;
  }

  get sessionId(): string | null {
    return this.claude.sessionId;
  }
}
