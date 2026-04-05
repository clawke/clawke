/**
 * 设备授权流程
 *
 * 首次启动无 relay 凭证时，向 clawke.ai 发起设备授权：
 *   1. POST /api/clawke/device-auth/request.json → 获取 authKey + authUrl
 *   2. 自动打开浏览器 / 终端显示授权链接
 *   3. 轮询 /api/clawke/device-auth/status.json 等待用户审批
 *   4. 审批通过 → 返回 { token, subdomain, relayUrl, serverAddr, serverPort }
 */
import https from 'https';
import http from 'http';
import { exec } from 'child_process';
import os from 'os';

const POLL_INTERVAL = 3000;
const MAX_POLL_TIME = 600000;

export interface AuthResult {
  token: string;
  subdomain: string;
  relayUrl: string;
  serverAddr: string;
  serverPort: number;
}

export class DeviceAuth {
  private apiBaseUrl: string;
  private _cancelled = false;

  constructor(apiBaseUrl: string) {
    this.apiBaseUrl = apiBaseUrl.replace(/\/$/, '');
  }

  async authorize(): Promise<AuthResult> {
    const deviceInfo = {
      hostname: os.hostname(),
      os: process.platform,
      arch: process.arch,
      csVersion: require('../../package.json').version,
    };

    const resp = await this._post('/api/clawke/device-auth/request.json', deviceInfo);
    if (!resp.success) {
      throw new Error(resp.actionError || 'Failed to request authorization');
    }
    const { authKey, authUrl, expiresIn } = resp.value;

    this._tryOpenBrowser(authUrl);
    this._printAuthBanner(authUrl, expiresIn);

    return this._pollStatus(authKey);
  }

  private async _pollStatus(authKey: string): Promise<AuthResult> {
    const startTime = Date.now();

    while (!this._cancelled) {
      const elapsed = Date.now() - startTime;
      if (elapsed > MAX_POLL_TIME) {
        throw new Error('Authorization timed out');
      }

      await this._sleep(POLL_INTERVAL);
      const resp = await this._get(`/api/clawke/device-auth/status.json?key=${authKey}`);

      if (!resp.success) {
        throw new Error(resp.actionError || 'Authorization expired');
      }

      const result = resp.value;
      switch (result.status) {
        case 'approved':
          console.log('');
          return {
            token: result.token,
            subdomain: result.subdomain,
            relayUrl: result.relayUrl,
            serverAddr: result.serverAddr,
            serverPort: result.serverPort,
          };
        case 'init': {
          const remaining = Math.ceil(result.expiresIn);
          process.stdout.write(`\r  ⏳ Waiting for authorization... (${remaining}s remaining)  `);
          break;
        }
      }
    }

    throw new Error('Authorization cancelled');
  }

  cancel(): void {
    this._cancelled = true;
  }

  private _printAuthBanner(authUrl: string, expiresIn: number): void {
    const minutes = Math.ceil(expiresIn / 60);
    console.log('');
    console.log('╔══════════════════════════════════════════╗');
    console.log('║                                          ║');
    console.log('║   🔗 To authorize this server, visit:    ║');
    console.log('║                                          ║');
    console.log('╚══════════════════════════════════════════╝');
    console.log('');
    console.log(`  ${authUrl}`);
    console.log('');
    console.log("  If the browser didn't open automatically,");
    console.log('  please copy the link above and open it manually.');
    console.log('');
    console.log(`  ⏳ Waiting for authorization... (expires in ${minutes}:00)`);
    console.log('');
  }

  private _tryOpenBrowser(url: string): void {
    const cmd = process.platform === 'darwin'
      ? `open "${url}"`
      : process.platform === 'win32'
        ? `start "${url}"`
        : `xdg-open "${url}"`;

    exec(cmd, (err) => {
      if (err) {
        console.log('[Clawke] 🌐 Could not open browser automatically.');
      } else {
        console.log('[Clawke] 🌐 Opening browser for authorization...');
      }
    });
  }

  private _post(urlPath: string, body: Record<string, unknown>): Promise<any> {
    return this._request('POST', urlPath, body);
  }

  private _get(urlPath: string): Promise<any> {
    return this._request('GET', urlPath);
  }

  private _request(method: string, urlPath: string, body?: Record<string, unknown>): Promise<any> {
    return new Promise((resolve, reject) => {
      const fullUrl = `${this.apiBaseUrl}${urlPath}`;
      const parsed = new URL(fullUrl);
      const isHttps = parsed.protocol === 'https:';
      const transport = isHttps ? https : http;

      const options = {
        hostname: parsed.hostname,
        port: parsed.port || (isHttps ? 443 : 80),
        path: parsed.pathname + parsed.search,
        method,
        headers: {
          'User-Agent': 'Clawke-CS',
          'Content-Type': 'application/json',
        },
      };

      const req = transport.request(options, (res: any) => {
        let data = '';
        res.on('data', (chunk: string) => { data += chunk; });
        res.on('end', () => {
          try {
            resolve(JSON.parse(data));
          } catch {
            reject(new Error(`Invalid JSON response: ${data.slice(0, 200)}`));
          }
        });
      });

      req.on('error', reject);
      req.setTimeout(10000, () => {
        req.destroy(new Error('Request timeout'));
      });

      if (body) {
        req.write(JSON.stringify(body));
      }
      req.end();
    });
  }

  private _sleep(ms: number): Promise<void> {
    return new Promise((resolve) => setTimeout(resolve, ms));
  }
}
