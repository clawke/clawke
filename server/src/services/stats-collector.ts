/**
 * StatsCollector — 统计收集器
 *
 * 构造函数注入 dataDir，不在 import 时触发副作用。
 * 定时保存需手动启动/停止。
 */
import * as fs from 'fs';
import * as path from 'path';

interface TokenStats {
  input: number;
  output: number;
  cache: number;
  total: number;
}

interface DailyTokenStats extends TokenStats {
  date: string;
}

interface ToolCallStats {
  count: number;
  totalDuration: number;
}

interface HourlyBucket {
  key: string;
  total: number;
}

interface DailyRecord {
  date: string;
  input: number;
  output: number;
  cache: number;
}

function _today(): string {
  return new Date().toLocaleDateString('en-CA');
}

function _currentHourKey(): string {
  const now = new Date();
  const h = now.getHours().toString().padStart(2, '0');
  return `${_today()}-${h}`;
}

function _fmtTokens(n: number): string {
  if (n >= 1000000) return (n / 1000000).toFixed(1) + 'M';
  if (n >= 1000) return (n / 1000).toFixed(1) + 'k';
  return n.toString();
}

export class StatsCollector {
  private startTime = new Date();
  private messagesToday = 0;
  private totalConversations = 0;
  private clawke: TokenStats = { input: 0, output: 0, cache: 0, total: 0 };
  private clawkeDaily: DailyTokenStats = { input: 0, output: 0, cache: 0, total: 0, date: _today() };
  private dailyHistory: DailyRecord[] = [];
  private hourlyTokens: HourlyBucket[] = [];
  private toolCalls: Record<string, ToolCallStats> = {};
  private saveTimer: ReturnType<typeof setInterval> | null = null;
  private statsFilePath: string;

  constructor(private dataDir: string) {
    this.statsFilePath = path.join(dataDir, 'clawke-stats.json');
    this.loadFromDisk();
  }

  // ── 持久化 ──────────────────────────────────────

  private loadFromDisk(): void {
    try {
      if (fs.existsSync(this.statsFilePath)) {
        const data = JSON.parse(fs.readFileSync(this.statsFilePath, 'utf-8'));
        if (data.clawke) this.clawke = data.clawke;
        if (data.clawkeDaily) {
          this.clawkeDaily = data.clawkeDaily;
          if (this.clawkeDaily.date !== _today()) {
            this.clawkeDaily = { input: 0, output: 0, cache: 0, total: 0, date: _today() };
          }
        }
        if (Array.isArray(data.hourlyTokens)) this.hourlyTokens = data.hourlyTokens;
        if (Array.isArray(data.dailyHistory)) this.dailyHistory = data.dailyHistory.slice(-30);
        if (data.messagesToday != null && this.clawkeDaily.date === data.clawkeDaily?.date) {
          this.messagesToday = data.messagesToday;
        }
        if (data.totalConversations != null) this.totalConversations = data.totalConversations;
        console.log('[Server] ✅ Stats restored from disk:', JSON.stringify(this.clawke));
      }
    } catch (err) {
      console.warn('[Server] Failed to load stats:', (err as Error).message);
    }
  }

  saveNow(): void {
    try {
      const dir = path.dirname(this.statsFilePath);
      if (!fs.existsSync(dir)) fs.mkdirSync(dir, { recursive: true });
      fs.writeFileSync(this.statsFilePath, JSON.stringify({
        clawke: this.clawke,
        clawkeDaily: this.clawkeDaily,
        dailyHistory: this.dailyHistory,
        hourlyTokens: this.hourlyTokens,
        messagesToday: this.messagesToday,
        totalConversations: this.totalConversations,
        savedAt: new Date().toISOString(),
      }, null, 2));
    } catch (err) {
      console.warn('[Server] Failed to save stats:', (err as Error).message);
    }
  }

  startPeriodicSave(intervalMs = 60_000): void {
    if (this.saveTimer) return;
    this.saveTimer = setInterval(() => this.saveNow(), intervalMs);
    if (this.saveTimer.unref) this.saveTimer.unref();
  }

  stopPeriodicSave(): void {
    if (this.saveTimer) {
      clearInterval(this.saveTimer);
      this.saveTimer = null;
    }
  }

  // ── 统计 API ──────────────────────────────────

  recordMessage(): void { this.messagesToday++; }
  recordConversation(): void { this.totalConversations++; }

  recordTokens(input: number, output: number, cache: number = 0): void {
    // 累计
    this.clawke.input += input;
    this.clawke.output += output;
    this.clawke.cache += cache;
    this.clawke.total += (input + output);

    // 每日（自动跨天重置）
    const today = _today();
    if (this.clawkeDaily.date !== today) {
      if (this.clawkeDaily.date && (this.clawkeDaily.input + this.clawkeDaily.output + this.clawkeDaily.cache) > 0) {
        this.dailyHistory.push({
          date: this.clawkeDaily.date,
          input: this.clawkeDaily.input,
          output: this.clawkeDaily.output,
          cache: this.clawkeDaily.cache,
        });
        if (this.dailyHistory.length > 30) this.dailyHistory = this.dailyHistory.slice(-30);
      }
      this.clawkeDaily = { input: 0, output: 0, cache: 0, total: 0, date: today };
    }
    this.clawkeDaily.input += input;
    this.clawkeDaily.output += output;
    this.clawkeDaily.cache += cache;
    this.clawkeDaily.total += (input + output);

    // 每小时统计
    const hourKey = _currentHourKey();
    const lastBucket = this.hourlyTokens[this.hourlyTokens.length - 1];
    if (lastBucket && lastBucket.key === hourKey) {
      lastBucket.total += (input + output);
    } else {
      this.hourlyTokens.push({ key: hourKey, total: input + output });
      if (this.hourlyTokens.length > 24) this.hourlyTokens = this.hourlyTokens.slice(-24);
    }
    // 注意：不再在 recordTokens 里即时写盘，改为定时保存
  }

  recordToolCall(toolName: string, durationMs: number): void {
    if (!this.toolCalls[toolName]) {
      this.toolCalls[toolName] = { count: 0, totalDuration: 0 };
    }
    this.toolCalls[toolName].count++;
    this.toolCalls[toolName].totalDuration += durationMs;
  }

  // ── Dashboard ──────────────────────────────────

  private getUptime(): string {
    const diffMs = Date.now() - this.startTime.getTime();
    const hours = Math.floor(diffMs / (1000 * 60 * 60));
    const mins = Math.floor((diffMs / (1000 * 60)) % 60);
    if (hours > 0) return `${hours}h ${mins}m`;
    return `${mins}m`;
  }

  private getHourlyChartData(): { hour: string; tokens: number }[] {
    const now = new Date();
    const points = [];
    for (let i = 23; i >= 0; i--) {
      const t = new Date(now.getTime() - i * 3600_000);
      const h = t.getHours().toString().padStart(2, '0');
      const key = `${t.toLocaleDateString('en-CA')}-${h}`;
      const bucket = this.hourlyTokens.find(b => b.key === key);
      points.push({ hour: `${h}:00`, tokens: bucket ? bucket.total : 0 });
    }
    return points;
  }

  private getDailyBarChartData(): DailyRecord[] {
    const allDays = [
      ...this.dailyHistory,
      { date: this.clawkeDaily.date, input: this.clawkeDaily.input, output: this.clawkeDaily.output, cache: this.clawkeDaily.cache },
    ];
    return allDays.slice(-30).map(d => ({
      date: d.date, input: d.input || 0, output: d.output || 0, cache: d.cache || 0,
    }));
  }

  getDashboardJson(connectedClientsCount = 0, isAiConnected = false, locale = 'zh'): Record<string, unknown> {
    const i18n: Record<string, Record<string, string>> = {
      zh: {
        gatewayStatus: '网关状态', tokenUsage: 'Token 用量',
        todayMessages: '今日消息', totalConversations: '总会话',
        hourlyTokenUsage: '每小时 Token 用量', dailyTokenUsage: '每日 Token 用量（30天）',
        recentToolCalls: '近期工具调用', toolName: '工具',
        toolCount: '次数', toolAvgDuration: '平均耗时', noToolCalls: '暂无调用',
      },
      en: {
        gatewayStatus: 'Gateway Status', tokenUsage: 'Token Usage',
        todayMessages: 'Today Messages', totalConversations: 'Total Conversations',
        hourlyTokenUsage: 'Hourly Token Usage', dailyTokenUsage: 'Daily Token Usage (30d)',
        recentToolCalls: 'Recent Tool Calls', toolName: 'Tool',
        toolCount: 'Count', toolAvgDuration: 'Avg Duration', noToolCalls: 'No calls yet',
      },
    };
    const t = i18n[locale] || i18n.zh;

    const recentToolsRow = Object.entries(this.toolCalls)
      .filter(([_, data]) => data.count > 0)
      .sort((a, b) => b[1].count - a[1].count)
      .map(([name, data]) => [name, data.count.toString(), (data.totalDuration / data.count / 1000).toFixed(1) + 's']);
    if (recentToolsRow.length === 0) recentToolsRow.push([t.noToolCalls, '-', '-']);

    return {
      widget_name: 'DashboardView',
      props: {
        sections: [
          {
            title: t.gatewayStatus, type: 'status_cards',
            items: [
              { label: 'OpenClaw Gateway', value: isAiConnected ? 'Connected' : 'Disconnected', status: isAiConnected ? 'ok' : 'error' },
              { label: 'Uptime', value: this.getUptime(), status: 'ok' },
              { label: 'Clients', value: `${connectedClientsCount} clients`, status: 'ok' },
            ],
          },
          {
            title: t.tokenUsage, type: 'stats_grid',
            items: [
              { label: t.todayMessages, value: this.messagesToday.toString() },
              { label: t.totalConversations, value: this.totalConversations.toString() },
              { label: 'Total Tokens', value: _fmtTokens(this.clawke.total), subtext: `${_fmtTokens(this.clawke.input)} in / ${_fmtTokens(this.clawke.output)} out · Cache: ${_fmtTokens(this.clawke.cache)}` },
              { label: 'Today Tokens', value: _fmtTokens(this.clawkeDaily.total), subtext: `${_fmtTokens(this.clawkeDaily.input)} in / ${_fmtTokens(this.clawkeDaily.output)} out · Cache: ${_fmtTokens(this.clawkeDaily.cache)}` },
            ],
          },
          { title: t.hourlyTokenUsage, type: 'line_chart', data: this.getHourlyChartData() },
          { title: t.dailyTokenUsage, type: 'bar_chart', data: this.getDailyBarChartData() },
          { title: t.recentToolCalls, type: 'table', columns: [t.toolName, t.toolCount, t.toolAvgDuration], rows: recentToolsRow },
        ],
      },
    };
  }

  // ── Mock 数据 ──────────────────────────────────

  populateMockData(): void {
    this.messagesToday = 42;
    this.totalConversations = 8;
    this.clawke = { input: 18200, output: 52100, cache: 3800, total: 70300 };
    this.clawkeDaily = { input: 2100, output: 5400, cache: 300, total: 7500, date: _today() };
    this.toolCalls['read_file'] = { count: 28, totalDuration: 2800 };
    this.toolCalls['web_fetch'] = { count: 12, totalDuration: 21600 };
    this.toolCalls['shell_exec'] = { count: 6, totalDuration: 19200 };
    this.startTime = new Date(Date.now() - 3 * 60 * 60 * 1000 - 25 * 60 * 1000);

    const now = new Date();
    this.hourlyTokens = [];
    for (let i = 23; i >= 0; i--) {
      const t = new Date(now.getTime() - i * 3600_000);
      const h = t.getHours().toString().padStart(2, '0');
      const key = `${t.toLocaleDateString('en-CA')}-${h}`;
      this.hourlyTokens.push({ key, total: Math.floor(Math.random() * 800) + 100 });
    }
  }
}
