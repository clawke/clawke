/**
 * StatsCollector — 统计收集器
 *
 * 构造函数注入 dataDir，不在 import 时触发副作用。
 * 定时保存需手动启动/停止。
 */
import * as fs from 'fs';
import * as path from 'path';

export interface TokenStats {
  input: number;
  output: number;
  cache: number;
  cacheWrite: number;
  reasoning: number;
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
  cacheWrite: number;
  reasoning: number;
}

interface ModelTokenStats extends TokenStats {
  model: string;
  provider: string;
  calls: number;
}

interface UsageRecentRecord extends TokenStats {
  gateway_id: string;
  conversation_id: string;
  model: string;
  provider: string;
  created_at: number;
}

export interface RecordTokenOptions {
  gatewayId?: string;
  conversationId?: string;
  model?: string;
  provider?: string;
  cacheWrite?: number;
  reasoning?: number;
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

function _emptyStats(): TokenStats {
  return { input: 0, output: 0, cache: 0, cacheWrite: 0, reasoning: 0, total: 0 };
}

function _emptyDaily(date = _today()): DailyTokenStats {
  return { ..._emptyStats(), date };
}

function _normalizeStats(value: unknown): TokenStats {
  const data = (value && typeof value === 'object') ? value as Record<string, unknown> : {};
  const numberAt = (key: string) => typeof data[key] === 'number' ? data[key] as number : 0;
  const input = numberAt('input');
  const output = numberAt('output');
  return {
    input,
    output,
    cache: numberAt('cache'),
    cacheWrite: numberAt('cacheWrite'),
    reasoning: numberAt('reasoning'),
    total: numberAt('total') || input + output,
  };
}

export class StatsCollector {
  private startTime = new Date();
  private messagesToday = 0;
  private totalConversations = 0;
  private clawke: TokenStats = _emptyStats();
  private clawkeDaily: DailyTokenStats = _emptyDaily();
  private dailyHistory: DailyRecord[] = [];
  private hourlyTokens: HourlyBucket[] = [];
  private gatewayTotals: Record<string, TokenStats> = {};
  private gatewayDaily: Record<string, DailyTokenStats> = {};
  private gatewayDailyHistory: Record<string, DailyRecord[]> = {};
  private gatewayHourlyTokens: Record<string, HourlyBucket[]> = {};
  private gatewayModels: Record<string, Record<string, ModelTokenStats>> = {};
  private recentUsage: UsageRecentRecord[] = [];
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
        if (data.clawke) this.clawke = _normalizeStats(data.clawke);
        if (data.clawkeDaily) {
          this.clawkeDaily = { ..._normalizeStats(data.clawkeDaily), date: data.clawkeDaily.date || _today() };
          if (this.clawkeDaily.date !== _today()) {
            this.clawkeDaily = _emptyDaily();
          }
        }
        if (Array.isArray(data.hourlyTokens)) this.hourlyTokens = data.hourlyTokens;
        if (Array.isArray(data.dailyHistory)) {
          this.dailyHistory = data.dailyHistory.slice(-30).map((item: unknown) => ({
            date: (item as Record<string, unknown>)?.date as string || _today(),
            ..._normalizeStats(item),
          }));
        }
        if (data.gatewayTotals && typeof data.gatewayTotals === 'object') {
          this.gatewayTotals = Object.fromEntries(
            Object.entries(data.gatewayTotals).map(([id, stats]) => [id, _normalizeStats(stats)]),
          );
        }
        if (data.gatewayDaily && typeof data.gatewayDaily === 'object') {
          this.gatewayDaily = Object.fromEntries(
            Object.entries(data.gatewayDaily).map(([id, stats]) => {
              const raw = stats as Record<string, unknown>;
              return [id, { ..._normalizeStats(stats), date: raw.date as string || _today() }];
            }),
          );
        }
        if (data.gatewayDailyHistory && typeof data.gatewayDailyHistory === 'object') {
          this.gatewayDailyHistory = Object.fromEntries(
            Object.entries(data.gatewayDailyHistory).map(([id, records]) => [
              id,
              Array.isArray(records)
                ? records.slice(-30).map((item: unknown) => ({
                    date: (item as Record<string, unknown>)?.date as string || _today(),
                    ..._normalizeStats(item),
                  }))
                : [],
            ]),
          );
        }
        if (data.gatewayHourlyTokens && typeof data.gatewayHourlyTokens === 'object') {
          this.gatewayHourlyTokens = data.gatewayHourlyTokens as Record<string, HourlyBucket[]>;
        }
        if (data.gatewayModels && typeof data.gatewayModels === 'object') {
          this.gatewayModels = data.gatewayModels as Record<string, Record<string, ModelTokenStats>>;
        }
        if (Array.isArray(data.recentUsage)) this.recentUsage = data.recentUsage.slice(-50);
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
        gatewayTotals: this.gatewayTotals,
        gatewayDaily: this.gatewayDaily,
        gatewayDailyHistory: this.gatewayDailyHistory,
        gatewayHourlyTokens: this.gatewayHourlyTokens,
        gatewayModels: this.gatewayModels,
        recentUsage: this.recentUsage,
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

  recordTokens(input: number, output: number, cache: number = 0, options: RecordTokenOptions = {}): void {
    const cacheWrite = Math.max(0, Math.floor(options.cacheWrite || 0));
    const reasoning = Math.max(0, Math.floor(options.reasoning || 0));
    this.addStats(this.clawke, input, output, cache, cacheWrite, reasoning);
    this.addDaily(this.clawkeDaily, this.dailyHistory, input, output, cache, cacheWrite, reasoning);
    this.addHourly(this.hourlyTokens, input + output);

    const gatewayId = options.gatewayId?.trim();
    if (gatewayId) {
      this.recordGatewayTokens(gatewayId, input, output, cache, cacheWrite, reasoning, options);
    }
    // 注意：不再在 recordTokens 里即时写盘，改为定时保存 — Save on the periodic timer instead of every token update.
  }

  private recordGatewayTokens(
    gatewayId: string,
    input: number,
    output: number,
    cache: number,
    cacheWrite: number,
    reasoning: number,
    options: RecordTokenOptions,
  ): void {
    const total = this.gatewayTotals[gatewayId] || _emptyStats();
    this.gatewayTotals[gatewayId] = total;
    this.addStats(total, input, output, cache, cacheWrite, reasoning);

    const daily = this.gatewayDaily[gatewayId] || _emptyDaily();
    this.gatewayDaily[gatewayId] = daily;
    const history = this.gatewayDailyHistory[gatewayId] || [];
    this.gatewayDailyHistory[gatewayId] = history;
    this.addDaily(daily, history, input, output, cache, cacheWrite, reasoning);

    const hourly = this.gatewayHourlyTokens[gatewayId] || [];
    this.gatewayHourlyTokens[gatewayId] = hourly;
    this.addHourly(hourly, input + output);

    const model = options.model || '';
    const provider = options.provider || '';
    const modelKey = `${provider || 'unknown'}:${model || 'unknown'}`;
    const modelMap = this.gatewayModels[gatewayId] || {};
    this.gatewayModels[gatewayId] = modelMap;
    const modelStats = modelMap[modelKey] || { ..._emptyStats(), model, provider, calls: 0 };
    modelMap[modelKey] = modelStats;
    modelStats.calls += 1;
    this.addStats(modelStats, input, output, cache, cacheWrite, reasoning);

    this.recentUsage.push({
      ..._emptyStats(),
      gateway_id: gatewayId,
      conversation_id: options.conversationId || gatewayId,
      model,
      provider,
      created_at: Date.now(),
    });
    const recent = this.recentUsage[this.recentUsage.length - 1];
    this.addStats(recent, input, output, cache, cacheWrite, reasoning);
    if (this.recentUsage.length > 50) this.recentUsage = this.recentUsage.slice(-50);
  }

  private addStats(target: TokenStats, input: number, output: number, cache: number, cacheWrite: number, reasoning: number): void {
    target.input += Math.max(0, Math.floor(input || 0));
    target.output += Math.max(0, Math.floor(output || 0));
    target.cache += Math.max(0, Math.floor(cache || 0));
    target.cacheWrite += cacheWrite;
    target.reasoning += reasoning;
    target.total += Math.max(0, Math.floor(input || 0)) + Math.max(0, Math.floor(output || 0));
  }

  private addDaily(
    daily: DailyTokenStats,
    history: DailyRecord[],
    input: number,
    output: number,
    cache: number,
    cacheWrite: number,
    reasoning: number,
  ): void {
    const today = _today();
    if (daily.date !== today) {
      if (daily.date && (daily.input + daily.output + daily.cache + daily.cacheWrite + daily.reasoning) > 0) {
        history.push({
          date: daily.date,
          input: daily.input,
          output: daily.output,
          cache: daily.cache,
          cacheWrite: daily.cacheWrite,
          reasoning: daily.reasoning,
        });
        if (history.length > 30) history.splice(0, history.length - 30);
      }
      Object.assign(daily, _emptyDaily(today));
    }
    this.addStats(daily, input, output, cache, cacheWrite, reasoning);
  }

  private addHourly(hourlyTokens: HourlyBucket[], total: number): void {
    const hourKey = _currentHourKey();
    const lastBucket = hourlyTokens[hourlyTokens.length - 1];
    if (lastBucket && lastBucket.key === hourKey) {
      lastBucket.total += total;
    } else {
      hourlyTokens.push({ key: hourKey, total });
      if (hourlyTokens.length > 24) hourlyTokens.splice(0, hourlyTokens.length - 24);
    }
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
    return this.buildHourlyChartData(this.hourlyTokens);
  }

  private buildHourlyChartData(source: HourlyBucket[]): { hour: string; tokens: number }[] {
    const now = new Date();
    const points = [];
    for (let i = 23; i >= 0; i--) {
      const t = new Date(now.getTime() - i * 3600_000);
      const h = t.getHours().toString().padStart(2, '0');
      const key = `${t.toLocaleDateString('en-CA')}-${h}`;
      const bucket = source.find(b => b.key === key);
      points.push({ hour: `${h}:00`, tokens: bucket ? bucket.total : 0 });
    }
    return points;
  }

  private getDailyBarChartData(): DailyRecord[] {
    const allDays = [
      ...this.dailyHistory,
      {
        date: this.clawkeDaily.date,
        input: this.clawkeDaily.input,
        output: this.clawkeDaily.output,
        cache: this.clawkeDaily.cache,
        cacheWrite: this.clawkeDaily.cacheWrite,
        reasoning: this.clawkeDaily.reasoning,
      },
    ];
    return allDays.slice(-30).map(d => ({
      date: d.date,
      input: d.input || 0,
      output: d.output || 0,
      cache: d.cache || 0,
      cacheWrite: d.cacheWrite || 0,
      reasoning: d.reasoning || 0,
    }));
  }

  getUsageDashboard(gatewayId = ''): Record<string, unknown> {
    const id = gatewayId.trim();
    const summary = id ? (this.gatewayTotals[id] || _emptyStats()) : this.clawke;
    const today = id ? (this.gatewayDaily[id] || _emptyDaily()) : this.clawkeDaily;
    const hourly = id ? (this.gatewayHourlyTokens[id] || []) : this.hourlyTokens;
    const dailyHistory = id ? (this.gatewayDailyHistory[id] || []) : this.dailyHistory;
    const allDays = [
      ...dailyHistory,
      { date: today.date, input: today.input, output: today.output, cache: today.cache, cacheWrite: today.cacheWrite, reasoning: today.reasoning },
    ];
    const modelMap = id ? (this.gatewayModels[id] || {}) : {};
    const recent = this.recentUsage
      .filter(item => !id || item.gateway_id === id)
      .slice(-20)
      .reverse();

    return {
      gateway_id: id,
      summary: this.toUsagePayload(summary),
      today: this.toUsagePayload(today),
      todayMessages: this.messagesToday,
      totalConversations: this.totalConversations,
      hourly: this.buildHourlyChartData(hourly),
      daily: allDays.slice(-30).map(day => ({
        date: day.date,
        input: day.input || 0,
        output: day.output || 0,
        cacheRead: day.cache || 0,
        cacheWrite: day.cacheWrite || 0,
        reasoning: day.reasoning || 0,
        total: (day.input || 0) + (day.output || 0),
      })),
      models: Object.values(modelMap)
        .sort((a, b) => b.total - a.total)
        .map(model => ({ ...this.toUsagePayload(model), model: model.model, provider: model.provider, calls: model.calls })),
      recent: recent.map(item => ({
        gateway_id: item.gateway_id,
        conversation_id: item.conversation_id,
        model: item.model,
        provider: item.provider,
        created_at: item.created_at,
        ...this.toUsagePayload(item),
      })),
    };
  }

  private toUsagePayload(stats: TokenStats): Record<string, number> {
    return {
      input: stats.input || 0,
      output: stats.output || 0,
      cacheRead: stats.cache || 0,
      cacheWrite: stats.cacheWrite || 0,
      reasoning: stats.reasoning || 0,
      total: stats.total || 0,
    };
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
    this.clawke = { input: 18200, output: 52100, cache: 3800, cacheWrite: 0, reasoning: 0, total: 70300 };
    this.clawkeDaily = { input: 2100, output: 5400, cache: 300, cacheWrite: 0, reasoning: 0, total: 7500, date: _today() };
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
