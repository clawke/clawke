/**
 * VersionChecker — 版本检查服务
 *
 * 定期查询 GitHub Releases API，缓存最新版本。
 */
import * as path from 'path';
import * as fs from 'fs';

interface ReleaseAsset {
  name: string;
  browser_download_url: string;
  size: number;
}

interface CachedRelease {
  version: string;
  changelog: string;
  release_date: string;
  html_url: string;
  assets: ReleaseAsset[];
}

interface ForceUpgradeConfig {
  min_supported_version: string;
  force_upgrade_below: string;
}

export class VersionChecker {
  private cachedRelease: CachedRelease | null = null;
  private forceUpgradeConfig: ForceUpgradeConfig = {
    min_supported_version: '0.0.0',
    force_upgrade_below: '0.0.0',
  };
  private checkTimer: ReturnType<typeof setInterval> | null = null;
  private owner: string;
  private repo: string;
  private checkIntervalMs: number;
  private serverVersion: string;

  constructor(configDir?: string, checkIntervalMs = 30 * 60 * 1000, serverVersion?: string) {
    this.owner = process.env.GITHUB_OWNER || 'clawke';
    this.repo = process.env.GITHUB_REPO || 'clawke';
    this.checkIntervalMs = checkIntervalMs;
    this.serverVersion = VersionChecker.normalizeSemanticVersion(
      serverVersion || VersionChecker.readServerVersion(),
    );

    // 加载 force-upgrade.json
    if (configDir) {
      try {
        const raw = fs.readFileSync(path.join(configDir, 'force-upgrade.json'), 'utf-8');
        this.forceUpgradeConfig = JSON.parse(raw);
      } catch {
        console.warn('[VersionChecker] force-upgrade.json not found, using defaults');
      }
    }
  }

  /** 读取服务端版本 — Read the server package version. */
  private static readServerVersion(): string {
    try {
      const raw = fs.readFileSync(path.join(__dirname, '..', '..', 'package.json'), 'utf-8');
      const packageJson = JSON.parse(raw) as { version?: string };
      return packageJson.version || '0.0.0';
    } catch {
      return '0.0.0';
    }
  }

  /** 规范化语义版本，忽略 build number — Normalize semver and ignore build metadata. */
  static normalizeSemanticVersion(version: string): string {
    const raw = String(version || '').trim().replace(/^v/, '').split('+')[0];
    const match = raw.match(/^(\d+)\.(\d+)\.(\d+)$/);
    if (!match) return '';
    return `${Number(match[1])}.${Number(match[2])}.${Number(match[3])}`;
  }

  /** 语义化版本比较 */
  static compareVersions(a: string, b: string): number {
    const pa = a.replace(/^v/, '').split('.').map(Number);
    const pb = b.replace(/^v/, '').split('.').map(Number);
    for (let i = 0; i < 3; i++) {
      const na = pa[i] || 0;
      const nb = pb[i] || 0;
      if (na < nb) return -1;
      if (na > nb) return 1;
    }
    return 0;
  }

  /** 兼容线使用 major.minor，patch 差异只提示 — Compatibility line is major.minor; patch differences only warn. */
  static getCompatibilityLine(version: string): string {
    const normalized = VersionChecker.normalizeSemanticVersion(version);
    if (!normalized) return '';
    const parts = normalized.split('.');
    return `${parts[0]}.${parts[1]}`;
  }

  /** 匹配平台下载链接 */
  static matchDownloadUrl(assets: ReleaseAsset[], platform?: string, arch?: string): string | null {
    if (!assets || assets.length === 0) return null;
    const patterns: Record<string, string[]> = {
      macos_arm64: ['macos-arm64', 'darwin-arm64'],
      macos_x64: ['macos-x64', 'darwin-x64', 'macos-x86_64'],
      windows_x64: ['win-x64', 'windows-x64'],
      windows_arm64: ['win-arm64', 'windows-arm64'],
      linux_x64: ['linux-x64', 'linux-amd64', 'linux-x86_64'],
      linux_arm64: ['linux-arm64', 'linux-aarch64'],
    };
    const key = `${platform}_${arch}`;
    const keywords = patterns[key] || [];
    for (const keyword of keywords) {
      const match = assets.find(a => a.name.toLowerCase().includes(keyword.toLowerCase()));
      if (match) return match.browser_download_url;
    }
    return null;
  }

  /** 从 GitHub 获取最新 release */
  async fetchLatestRelease(): Promise<CachedRelease | null> {
    const url = `https://api.github.com/repos/${this.owner}/${this.repo}/releases/latest`;
    try {
      const resp = await fetch(url, { headers: { Accept: 'application/vnd.github+json' } });
      if (!resp.ok) {
        console.warn(`[VersionChecker] GitHub API returned ${resp.status} for ${url}`);
        return null;
      }
      const data = await resp.json() as Record<string, unknown>;
      this.cachedRelease = {
        version: ((data.tag_name as string) || '').replace(/^v/, '') || '0.0.0',
        changelog: (data.body as string) || '',
        release_date: ((data.published_at as string) || '').split('T')[0] || '',
        html_url: (data.html_url as string) || '',
        assets: ((data.assets as Record<string, unknown>[]) || []).map(a => ({
          name: a.name as string,
          browser_download_url: a.browser_download_url as string,
          size: a.size as number,
        })),
      };
      console.log(`[VersionChecker] Latest release: v${this.cachedRelease.version}`);
      return this.cachedRelease;
    } catch (err) {
      console.error(`[VersionChecker] Failed to fetch ${url}: ${(err as Error).message}`);
      return null;
    }
  }

  /** 检查客户端与当前服务端是否兼容 — Check client compatibility with the current server. */
  private checkServerCompatibility(clientVersion: string): Record<string, unknown> | null {
    const client = VersionChecker.normalizeSemanticVersion(clientVersion);
    const server = this.serverVersion;
    if (!client || !server) return null;
    if (client === server) return null;

    const clientIsOlder = VersionChecker.compareVersions(client, server) < 0;
    const sameCompatibilityLine = VersionChecker.getCompatibilityLine(client)
      === VersionChecker.getCompatibilityLine(server);
    const isForced = !sameCompatibilityLine;
    const actionPrefix = isForced ? 'required' : 'recommended';
    const action = clientIsOlder ? `${actionPrefix}_client_update` : `${actionPrefix}_server_update`;
    const title = clientIsOlder
      ? (isForced ? '需要升级客户端' : '建议升级客户端')
      : (isForced ? '需要升级服务端' : '建议升级服务端');
    const message = this.buildCompatibilityMessage({
      client,
      server,
      clientIsOlder,
      isForced,
    });
    const downloadUrl = clientIsOlder
      ? `https://github.com/${this.owner}/${this.repo}/releases/tag/v${server}`
      : '';

    return {
      payload_type: 'system_status',
      status: 'update_available',
      upgrade: isForced ? 2 : 1,
      update_info: {
        version: clientIsOlder ? server : client,
        changelog: message,
        release_date: '',
        download_url: downloadUrl,
        title,
        message,
        action,
        client_version: client,
        server_version: server,
      },
    };
  }

  /** 构建兼容提示文案 — Build compatibility warning text. */
  private buildCompatibilityMessage({
    client,
    server,
    clientIsOlder,
    isForced,
  }: {
    client: string;
    server: string;
    clientIsOlder: boolean;
    isForced: boolean;
  }): string {
    if (clientIsOlder) {
      if (isForced) {
        return `当前服务端版本为 ${server}，客户端版本为 ${client}。请升级客户端到 ${server} 后继续使用。`;
      }
      return `当前服务端版本为 ${server}，客户端版本为 ${client}。版本不完全一致，可能不兼容或出现异常；建议升级客户端到 ${server}。`;
    }

    if (isForced) {
      return `当前服务端版本为 ${server}，客户端版本为 ${client}。请先运行 clawke update 升级服务端后继续使用。`;
    }
    return `当前服务端版本为 ${server}，客户端版本为 ${client}。版本不完全一致，可能不兼容或出现异常；建议先运行 clawke update 升级服务端。`;
  }

  /** 检查版本 — Check version status. */
  checkVersion(clientVersion: string, _platform?: string, _arch?: string): Record<string, unknown> | null {
    const compatibilityMsg = this.checkServerCompatibility(clientVersion);
    if (compatibilityMsg) return compatibilityMsg;

    // 第一阶段只做本地 Client/Server 兼容比较，不做 GitHub latest 比较。
    // Phase one only checks local Client/Server compatibility; GitHub latest comparison is deferred.
    return null;
  }

  /** 启动定时轮询 */
  startPeriodicCheck(): void {
    if (process.env.DISABLE_AUTO_UPDATE === 'true') {
      console.log('[VersionChecker] Auto update check disabled');
      return;
    }

    this.fetchLatestRelease();
    this.checkTimer = setInterval(() => this.fetchLatestRelease(), this.checkIntervalMs);
    if (this.checkTimer.unref) this.checkTimer.unref();
    console.log(`[VersionChecker] Periodic check started (interval: ${this.checkIntervalMs / 60000}m)`);
  }

  stopPeriodicCheck(): void {
    if (this.checkTimer) {
      clearInterval(this.checkTimer);
      this.checkTimer = null;
    }
  }
}
