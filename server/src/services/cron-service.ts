/**
 * 定时任务管理服务（SQLite 持久化）
 */
import { sendToClient } from '../downstream/client-server.js';
import type { WebSocket } from 'ws';
import type { Database } from '../store/database.js';

interface CronJob {
  id: string; name: string; schedule: string; schedule_text: string;
  message: string; enabled: boolean;
  last_run: { time: string; success: boolean } | null;
}

function toJob(row: any): CronJob | null {
  if (!row) return null;
  return {
    id: row.id, name: row.name, schedule: row.schedule,
    schedule_text: row.schedule_text, message: row.message,
    enabled: row.enabled === 1,
    last_run: row.last_run_time ? { time: row.last_run_time, success: row.last_run_success === 1 } : null,
  };
}

export class CronService {
  private listStmt: any;
  private findStmt: any;
  private toggleStmt: any;
  private updateLastRunStmt: any;

  constructor(private db: Database) {
    const raw = (db as any).db; // Access underlying better-sqlite3 instance
    this.listStmt = raw.prepare('SELECT * FROM cron_jobs ORDER BY id');
    this.findStmt = raw.prepare('SELECT * FROM cron_jobs WHERE id = ?');
    this.toggleStmt = raw.prepare('UPDATE cron_jobs SET enabled = ? WHERE id = ?');
    this.updateLastRunStmt = raw.prepare('UPDATE cron_jobs SET last_run_time = ?, last_run_success = ? WHERE id = ?');

    // Insert defaults if empty
    const count = raw.prepare('SELECT COUNT(*) AS c FROM cron_jobs').get().c;
    if (count === 0) {
      const insertStmt = raw.prepare(`
        INSERT INTO cron_jobs (id, name, schedule, schedule_text, message, enabled, last_run_time, last_run_success)
        VALUES (@id, @name, @schedule, @schedule_text, @message, @enabled, @last_run_time, @last_run_success)
      `);
      const defaults = [
        { id: 'job_news', name: '每日科技新闻', schedule: '0 8 * * *', schedule_text: '每天 08:00', message: '搜索今天科技前沿资讯并总结', enabled: 1, last_run_time: new Date().toISOString(), last_run_success: 1 },
        { id: 'job_report', name: '每周总结报告', schedule: '0 18 * * 5', schedule_text: '每周五 18:00', message: '分析本周频道活跃度', enabled: 0, last_run_time: new Date(Date.now() - 7 * 86400000).toISOString(), last_run_success: 1 },
      ];
      const insertAll = raw.transaction((jobs: any[]) => { for (const job of jobs) insertStmt.run(job); });
      insertAll(defaults);
      console.log('[CronService] Initialized default cron jobs in DB');
    }
  }

  getCronListViewJson(messageId = 'msg_sys'): Record<string, unknown> {
    const jobs = this.listStmt.all().map(toJob);
    const activeCount = jobs.filter((j: CronJob | null) => j?.enabled).length;
    return {
      payload_type: 'ui_component', message_id: messageId,
      component: {
        widget_name: 'CronListView',
        props: { stats: { total: jobs.length, active: activeCount, paused: jobs.length - activeCount, failed: 0 }, jobs },
      },
    };
  }

  handleCronAction(ws: WebSocket, payload: any): void {
    const { action_id, data } = payload.action;

    if (action_id === 'refresh_cron') {
      sendToClient(ws, this.getCronListViewJson(payload.message_id || payload.context?.client_msg_id));
    } else if (action_id === 'toggle_cron_job') {
      const job = this.findStmt.get(data.job_id);
      if (job) {
        this.toggleStmt.run(data.enabled ? 1 : 0, data.job_id);
        console.log(`[Clawke Cron] Job ${data.job_id} toggled to ${data.enabled}`);
        sendToClient(ws, this.getCronListViewJson(payload.message_id || payload.context?.client_msg_id));
      }
    } else if (action_id === 'trigger_cron_job') {
      const job = this.findStmt.get(data.job_id);
      if (job) {
        console.log(`[Clawke Cron] Job ${data.job_id} manually triggered!`);
        this.updateLastRunStmt.run(new Date().toISOString(), 1, data.job_id);
        sendToClient(ws, { payload_type: 'system_status', status: 'toast', message: `任务 [${job.name}] 已触发执行` });
        sendToClient(ws, this.getCronListViewJson(payload.message_id || payload.context?.client_msg_id));
      }
    }
  }
}
