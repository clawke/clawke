import { createHash } from 'node:crypto';
import { promises as fs } from 'node:fs';
import { homedir, tmpdir } from 'node:os';
import { join } from 'node:path';

const DEFAULT_CLAWHUB_URL = 'https://clawhub.ai';
const DEFAULT_TIMEOUT_MS = 30_000;

export type FetchLike = (input: string | URL, init?: RequestInit) => Promise<Response>;

export interface ClawHubSkillDetail {
  skill?: {
    slug: string;
    displayName?: string;
    summary?: string;
  } | null;
  latestVersion?: {
    version: string;
  } | null;
}

export interface ClawHubDownloadResult {
  archivePath: string;
  sha256Hex: string;
  integrity: string;
  cleanup: () => Promise<void>;
}

export class ClawHubRequestError extends Error {
  constructor(
    public status: number,
    public requestPath: string,
    message: string,
  ) {
    super(message);
    this.name = 'ClawHubRequestError';
  }
}

export function resolveClawHubBaseUrl(baseUrl?: string): string {
  const value = (baseUrl || process.env.OPENCLAW_CLAWHUB_URL || process.env.CLAWHUB_URL || DEFAULT_CLAWHUB_URL).trim();
  return (value || DEFAULT_CLAWHUB_URL).replace(/\/+$/, '');
}

export async function resolveClawHubAuthToken(): Promise<string | undefined> {
  const envToken = stringValue(process.env.OPENCLAW_CLAWHUB_TOKEN)
    || stringValue(process.env.CLAWHUB_TOKEN)
    || stringValue(process.env.CLAWHUB_AUTH_TOKEN);
  if (envToken) return envToken;

  for (const configPath of resolveClawHubConfigPaths()) {
    try {
      const raw = await fs.readFile(configPath, 'utf8');
      const token = extractTokenFromConfig(JSON.parse(raw));
      if (token) return token;
    } catch {
      // 尝试下一个配置路径 — Try next config path.
    }
  }
  return undefined;
}

export async function fetchClawHubSkillDetail(params: {
  slug: string;
  baseUrl?: string;
  token?: string;
  timeoutMs?: number;
  fetchImpl?: FetchLike;
}): Promise<ClawHubSkillDetail> {
  return fetchJson<ClawHubSkillDetail>({
    baseUrl: params.baseUrl,
    path: `/api/v1/skills/${encodeURIComponent(params.slug)}`,
    token: params.token,
    timeoutMs: params.timeoutMs,
    fetchImpl: params.fetchImpl,
  });
}

export async function downloadClawHubSkillArchive(params: {
  slug: string;
  version?: string;
  tag?: string;
  baseUrl?: string;
  token?: string;
  timeoutMs?: number;
  fetchImpl?: FetchLike;
}): Promise<ClawHubDownloadResult> {
  const { response, url, hasToken } = await clawhubRequest({
    baseUrl: params.baseUrl,
    path: '/api/v1/download',
    token: params.token,
    timeoutMs: params.timeoutMs,
    fetchImpl: params.fetchImpl,
    search: {
      slug: params.slug,
      version: params.version,
      tag: params.version ? undefined : params.tag,
    },
  });
  if (!response.ok) throw await buildClawHubError(response, url, hasToken);

  const bytes = new Uint8Array(await response.arrayBuffer());
  const sha256Hex = createHash('sha256').update(bytes).digest('hex');
  const integrity = `sha256-${createHash('sha256').update(bytes).digest('base64')}`;
  const archivePath = join(tmpdir(), `clawke-skillhub-${params.slug}-${Date.now()}-${Math.random().toString(16).slice(2)}.zip`);
  await fs.writeFile(archivePath, bytes);
  return {
    archivePath,
    sha256Hex,
    integrity,
    cleanup: async () => {
      await fs.rm(archivePath, { force: true });
    },
  };
}

interface ClawHubRequestParams {
  baseUrl?: string;
  path: string;
  token?: string;
  timeoutMs?: number;
  search?: Record<string, string | undefined>;
  fetchImpl?: FetchLike;
}

async function fetchJson<T>(params: ClawHubRequestParams): Promise<T> {
  const { response, url, hasToken } = await clawhubRequest(params);
  if (!response.ok) throw await buildClawHubError(response, url, hasToken);
  return await response.json() as T;
}

async function clawhubRequest(params: ClawHubRequestParams): Promise<{ response: Response; url: URL; hasToken: boolean }> {
  const url = buildUrl(params);
  const token = stringValue(params.token) || await resolveClawHubAuthToken();
  const controller = new AbortController();
  const timeout = setTimeout(() => {
    controller.abort(new Error(`ClawHub request timed out after ${params.timeoutMs ?? DEFAULT_TIMEOUT_MS}ms`));
  }, params.timeoutMs ?? DEFAULT_TIMEOUT_MS);
  try {
    const response = await (params.fetchImpl || fetch)(url, {
      headers: token ? { Authorization: `Bearer ${token}` } : undefined,
      signal: controller.signal,
    });
    return { response, url, hasToken: Boolean(token) };
  } finally {
    clearTimeout(timeout);
  }
}

function buildUrl(params: Pick<ClawHubRequestParams, 'baseUrl' | 'path' | 'search'>): URL {
  const url = new URL(params.path, `${resolveClawHubBaseUrl(params.baseUrl)}/`);
  for (const [key, value] of Object.entries(params.search || {})) {
    if (value) url.searchParams.set(key, value);
  }
  return url;
}

async function buildClawHubError(response: Response, url: URL, hasToken: boolean): Promise<ClawHubRequestError> {
  const body = await readErrorBody(response);
  const suffix = response.status === 429 ? rateLimitSuffix(response.headers, hasToken) : '';
  return new ClawHubRequestError(response.status, url.pathname, `${body}${suffix ? ` ${suffix}` : ''}`);
}

async function readErrorBody(response: Response): Promise<string> {
  try {
    const text = (await response.text()).trim();
    return text || response.statusText || `HTTP ${response.status}`;
  } catch {
    return response.statusText || `HTTP ${response.status}`;
  }
}

function rateLimitSuffix(headers: Headers, hasToken: boolean): string {
  const reset = stringValue(headers.get('RateLimit-Reset')) || stringValue(headers.get('Retry-After'));
  const parts: string[] = [];
  if (reset && Number.isFinite(Number(reset))) parts.push(`resets in ${reset}s`);
  if (!hasToken) parts.push('请登录 ClawHub 或配置 CLAWHUB_TOKEN 后重试');
  return parts.join('; ');
}

function resolveClawHubConfigPaths(): string[] {
  const explicit = stringValue(process.env.OPENCLAW_CLAWHUB_CONFIG_PATH)
    || stringValue(process.env.CLAWHUB_CONFIG_PATH)
    || stringValue(process.env.CLAWDHUB_CONFIG_PATH);
  if (explicit) return [explicit];

  const xdgHome = stringValue(process.env.XDG_CONFIG_HOME) || join(homedir(), '.config');
  const xdgPath = join(xdgHome, 'clawhub', 'config.json');
  if (process.platform === 'darwin') {
    return [join(homedir(), 'Library', 'Application Support', 'clawhub', 'config.json'), xdgPath];
  }
  return [xdgPath];
}

function extractTokenFromConfig(value: unknown): string | undefined {
  if (!value || typeof value !== 'object') return undefined;
  const record = value as Record<string, unknown>;
  return stringValue(record.accessToken)
    || stringValue(record.authToken)
    || stringValue(record.apiToken)
    || stringValue(record.token)
    || extractTokenFromConfig(record.auth)
    || extractTokenFromConfig(record.session)
    || extractTokenFromConfig(record.credentials)
    || extractTokenFromConfig(record.user);
}

function stringValue(value: unknown): string | undefined {
  return typeof value === 'string' && value.trim() ? value.trim() : undefined;
}
