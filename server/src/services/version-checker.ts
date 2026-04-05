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

  constructor(configDir?: string, checkIntervalMs = 30 * 60 * 1000) {
    this.owner = process.env.GITHUB_OWNER || 'user';
    this.repo = process.env.GITHUB_REPO || 'clawke';
    this.checkIntervalMs = checkIntervalMs;

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
    try {
      const url = `https://api.github.com/repos/${this.owner}/${this.repo}/releases/latest`;
      const resp = await fetch(url, { headers: { Accept: 'application/vnd.github+json' } });
      if (!resp.ok) {
        console.warn(`[VersionChecker] GitHub API returned ${resp.status}`);
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
      console.error(`[VersionChecker] Failed to fetch: ${(err as Error).message}`);
      return null;
    }
  }

  /** 检查版本 */
  checkVersion(clientVersion: string, platform?: string, arch?: string): Record<string, unknown> | null {
    if (!this.cachedRelease || !clientVersion) return null;
    const latest = this.cachedRelease.version;
    if (VersionChecker.compareVersions(clientVersion, latest) >= 0) return null;

    let upgradeLevel = 1;
    if (VersionChecker.compareVersions(clientVersion, this.forceUpgradeConfig.force_upgrade_below) < 0) {
      upgradeLevel = 2;
    }
    const downloadUrl = VersionChecker.matchDownloadUrl(this.cachedRelease.assets, platform, arch)
      || this.cachedRelease.html_url;

    return {
      payload_type: 'system_status',
      status: 'update_available',
      upgrade: upgradeLevel,
      update_info: {
        version: latest,
        changelog: this.cachedRelease.changelog,
        release_date: this.cachedRelease.release_date,
        download_url: downloadUrl,
      },
    };
  }

  /** 启动定时轮询 */
  startPeriodicCheck(): void {
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
