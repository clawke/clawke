/**
 * frpc 子进程管理（Managed Relay 隧道客户端）
 *
 * 功能：自动下载 frpc、生成配置、运行子进程、异常重连、PID 管理
 */
import { spawn, execSync, type ChildProcess } from 'child_process';
import fs from 'fs';
import path from 'path';
import https from 'https';
import http from 'http';
import { CLAWKE_HOME, BIN_DIR } from '../store/clawke-home.js';

const PLATFORM_MAP: Record<string, string> = {
  linux: 'linux',
  darwin: 'darwin',
  win32: 'windows',
};
const ARCH_MAP: Record<string, string> = {
  x64: 'amd64',
  arm64: 'arm64',
};

const FRP_VERSION = '0.61.1';
const RECONNECT_DELAY = 10000;

export interface FrpcConfig {
  relayToken: string;
  relaySubdomain: string;
  httpPort?: number;
  relayServer?: string;
  relayPort?: number;
  transport?: string;
}

export class FrpcManager {
  private token: string;
  private subdomain: string;
  private localPort: number;
  private relayServer: string;
  private relayPort: number;
  private transport: string;
  private proc: ChildProcess | null = null;
  private _stopping = false;
  private pidFile: string;
  private configPath: string;
  private binDir: string;

  constructor(config: FrpcConfig) {
    this.token = config.relayToken;
    this.subdomain = config.relaySubdomain;
    this.localPort = config.httpPort || 8780;
    this.relayServer = config.relayServer || 'relay.clawke.ai';
    this.relayPort = config.relayPort || 7000;
    this.transport = config.transport || '';
    this.pidFile = path.join(CLAWKE_HOME, 'frpc.pid');
    this.configPath = path.join(CLAWKE_HOME, 'frpc.toml');
    this.binDir = BIN_DIR;
  }

  async start(): Promise<void> {
    if (!this.token || !this.subdomain) {
      console.log('[frpc] Relay token or subdomain not configured, skipping');
      return;
    }

    this._stopping = false;
    this._killStale();

    const frpcPath = await this._ensureFrpc();
    if (!frpcPath) {
      console.error('[frpc] Failed to ensure frpc binary, aborting');
      return;
    }

    this._writeConfig();

    console.log(`[frpc] Starting: ${frpcPath} -c ${this.configPath}`);
    this.proc = spawn(frpcPath, ['-c', this.configPath], {
      stdio: ['pipe', 'pipe', 'pipe'],
      windowsHide: true,
    });

    fs.mkdirSync(path.dirname(this.pidFile), { recursive: true });
    fs.writeFileSync(this.pidFile, String(this.proc.pid));

    this.proc.stdout?.on('data', (data: Buffer) => {
      for (const line of data.toString().trim().split('\n')) {
        console.log(`[frpc] ${line}`);
      }
    });

    this.proc.stderr?.on('data', (data: Buffer) => {
      for (const line of data.toString().trim().split('\n')) {
        console.error(`[frpc] ${line}`);
      }
    });

    this.proc.on('exit', (code, signal) => {
      console.log(`[frpc] Exited: code=${code}, signal=${signal}`);
      this.proc = null;
      this._cleanPid();
      if (!this._stopping) {
        console.log(`[frpc] Reconnecting in ${RECONNECT_DELAY / 1000}s...`);
        setTimeout(() => this.start(), RECONNECT_DELAY);
      }
    });

    console.log(`[Clawke] 🌐 Relay: https://${this.subdomain}.${this.relayServer}`);
  }

  stop(): void {
    this._stopping = true;
    if (this.proc) {
      console.log('[frpc] Stopping...');
      this.proc.kill('SIGTERM');
      const ref = this.proc;
      setTimeout(() => {
        if (ref && !ref.killed) ref.kill('SIGKILL');
      }, 2000);
      this.proc = null;
    }
    this._cleanPid();
  }

  private _killStale(): void {
    if (!fs.existsSync(this.pidFile)) return;
    try {
      const oldPid = parseInt(fs.readFileSync(this.pidFile, 'utf8'));
      if (!isNaN(oldPid)) {
        process.kill(oldPid, 'SIGTERM');
        console.log(`[frpc] Cleaned up stale process PID=${oldPid}`);
        try { execSync(`kill -0 ${oldPid} 2>/dev/null && sleep 1`, { timeout: 2000 }); } catch {}
      }
    } catch {
      // Process doesn't exist
    }
    this._cleanPid();
  }

  private _cleanPid(): void {
    try { fs.unlinkSync(this.pidFile); } catch {}
  }

  private async _ensureFrpc(): Promise<string | null> {
    const isWin = process.platform === 'win32';
    const frpcPath = path.join(this.binDir, isWin ? 'frpc.exe' : 'frpc');

    if (fs.existsSync(frpcPath)) return frpcPath;

    const platform = PLATFORM_MAP[process.platform];
    const arch = ARCH_MAP[process.arch];
    if (!platform || !arch) {
      console.error(`[frpc] Unsupported platform: ${process.platform}-${process.arch}`);
      return null;
    }

    const ext = isWin ? '.zip' : '.tar.gz';
    const archiveName = `frp_${FRP_VERSION}_${platform}_${arch}`;
    const url = `https://github.com/fatedier/frp/releases/download/v${FRP_VERSION}/${archiveName}${ext}`;

    console.log(`[frpc] First run — downloading frpc (${platform}/${arch})...`);
    console.log(`[frpc] URL: ${url}`);

    try {
      fs.mkdirSync(this.binDir, { recursive: true });
      const archivePath = path.join(this.binDir, `frpc-download${ext}`);
      await this._download(url, archivePath);

      if (isWin) {
        execSync(`powershell -command "Expand-Archive -Path '${archivePath}' -DestinationPath '${this.binDir}' -Force"`);
        fs.renameSync(path.join(this.binDir, archiveName, 'frpc.exe'), frpcPath);
      } else {
        execSync(`tar -xzf "${archivePath}" -C "${this.binDir}"`);
        fs.renameSync(path.join(this.binDir, archiveName, 'frpc'), frpcPath);
        fs.chmodSync(frpcPath, 0o755);
      }

      try { fs.unlinkSync(archivePath); } catch {}
      try { fs.rmSync(path.join(this.binDir, archiveName), { recursive: true }); } catch {}

      console.log(`[frpc] Download complete: ${frpcPath}`);
      return frpcPath;
    } catch (err: any) {
      console.error(`[frpc] Download failed: ${err.message}`);
      return null;
    }
  }

  private _download(url: string, destPath: string): Promise<void> {
    return new Promise((resolve, reject) => {
      const get = url.startsWith('https') ? https.get : http.get;
      get(url, { headers: { 'User-Agent': 'Clawke-CS' } }, (res: any) => {
        if (res.statusCode === 301 || res.statusCode === 302) {
          return this._download(res.headers.location!, destPath).then(resolve).catch(reject);
        }
        if (res.statusCode !== 200) {
          return reject(new Error(`HTTP ${res.statusCode}`));
        }
        const file = fs.createWriteStream(destPath);
        res.pipe(file);
        file.on('finish', () => { file.close(); resolve(); });
        file.on('error', reject);
      }).on('error', reject);
    });
  }

  private _writeConfig(): void {
    const transport = this.transport || '';
    const transportLine = transport ? `transport.protocol = "${transport}"\n` : '';

    const config = `# Auto-generated by Clawke CS — do not edit manually
serverAddr = "${this.relayServer}"
serverPort = ${this.relayPort}
${transportLine}
[metadatas]
token = "${this.token}"

[[proxies]]
name = "cs-${this.subdomain}"
type = "http"
localPort = ${this.localPort}
subdomain = "${this.subdomain}"
`;

    fs.mkdirSync(path.dirname(this.configPath), { recursive: true });
    fs.writeFileSync(this.configPath, config);
    console.log(`[frpc] Config written: ${this.configPath}`);
  }
}
