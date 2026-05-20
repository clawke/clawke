import { createHash, randomUUID } from 'node:crypto';
import { promises as fs } from 'node:fs';
import { tmpdir } from 'node:os';
import { dirname, join, resolve, sep } from 'node:path';
import { inflateRaw } from 'node:zlib';
import { promisify } from 'node:util';
import { broadcastToClients } from '../downstream/client-server.js';
import type { GatewayInfo } from '../types/gateways.js';
import type { ManagedSkill, SkillHubInstallPackage } from '../types/skills.js';
import {
  downloadClawHubSkillArchive,
  fetchClawHubSkillDetail,
  resolveClawHubBaseUrl,
} from './clawhub-client.js';
import {
  isSkillHubSkillInstalled,
  recordSkillHubInstall,
  safeChildPath,
  SKILLHUB_SKILLS_DIR,
  skillHubSkillDir,
} from '../store/skillhub-install-store.js';

const inflateRawAsync = promisify(inflateRaw);
const VALID_SLUG_PATTERN = /^[a-z0-9](?:[a-z0-9-]*[a-z0-9])?$/i;
const ROOT_MARKERS = ['SKILL.md', 'skill.md', 'skills.md', 'SKILL.MD'];
const ZIP_EOCD_SIGNATURE = 0x06054b50;
const ZIP_CENTRAL_FILE_HEADER_SIGNATURE = 0x02014b50;
const ZIP_LOCAL_FILE_HEADER_SIGNATURE = 0x04034b50;
const ZIP_EOCD_MIN_BYTES = 22;
const ZIP_EOCD_MAX_COMMENT_BYTES = 0xffff;
const ZIP_UNIX_FILE_TYPE_MASK = 0o170000;
const ZIP_UNIX_SYMLINK_TYPE = 0o120000;

export interface ManagedSkillHubInstallResult {
  installed: boolean;
  status: string;
  message: string;
  skill?: ManagedSkill;
}

export class ManagedSkillHubInstallError extends Error {
  constructor(
    message: string,
    public code: string,
    public fallbackAllowed = true,
  ) {
    super(message);
    this.name = 'ManagedSkillHubInstallError';
  }
}

export function canUseManagedSkillHubInstall(input: {
  gateways: GatewayInfo[];
}): boolean {
  const gateways = input.gateways.filter((gateway) => gateway.status === 'online');
  if (gateways.length === 0) return true;
  const expected = normalizePath(SKILLHUB_SKILLS_DIR);
  return gateways.some((gateway) => {
    if (gateway.local_to_server === true) return true;
    return [gateway.shared_skill_root, gateway.managed_skills_root]
      .map((item) => normalizePath(item))
      .some((item) => item === expected);
  });
}

export async function startManagedSkillHubInstall(input: {
  installId: string;
  installMode: 'managed';
  installPackage: SkillHubInstallPackage;
  fallbackGatewayId?: string;
  refreshGateways?: (slug: string) => Promise<void>;
  fallbackToGateway?: (err: unknown) => Promise<void>;
}): Promise<ManagedSkillHubInstallResult> {
  const slug = validateSkillHubSlug(input.installPackage.slug);
  void runManagedSkillHubInstall({
    installId: input.installId,
    installPackage: { ...input.installPackage, slug },
    refreshGateways: input.refreshGateways,
  }).catch((err) => {
    const fallbackAllowed = !(err instanceof ManagedSkillHubInstallError) || err.fallbackAllowed;
    if (fallbackAllowed && input.fallbackToGateway) {
      emitStatus(input.installId, slug, 'fallback_pending', '正在切换到 Gateway 原生安装');
      void input.fallbackToGateway(err).catch((fallbackErr) => {
        emitStatus(input.installId, slug, 'failed', errorMessage(fallbackErr));
      });
      return;
    }
    emitStatus(input.installId, slug, 'failed', errorMessage(err));
  });
  return {
    installed: false,
    status: 'accepted',
    message: '安装任务已提交',
  };
}

async function runManagedSkillHubInstall(input: {
  installId: string;
  installPackage: SkillHubInstallPackage;
  refreshGateways?: (slug: string) => Promise<void>;
}): Promise<void> {
  const slug = input.installPackage.slug;
  if (await isSkillHubSkillInstalled(slug)) {
    emitStatus(input.installId, slug, 'installed', '已安装');
    return;
  }

  emitStatus(input.installId, slug, 'resolving', '正在解析');
  const detail = await fetchClawHubSkillDetail({ slug });
  if (!detail.skill) {
    throw new ManagedSkillHubInstallError(`Skill not found on ClawHub: ${slug}`, 'skill_not_found', false);
  }
  const version = detail.latestVersion?.version;
  if (!version) {
    throw new ManagedSkillHubInstallError(`Skill has no installable version: ${slug}`, 'missing_version', false);
  }

  emitStatus(input.installId, slug, 'downloading', '正在下载');
  const archive = await downloadClawHubSkillArchive({ slug, version });
  try {
    emitStatus(input.installId, slug, 'verifying', '正在校验安装包');
    await assertZipEntriesSafe(archive.archivePath);

    emitStatus(input.installId, slug, 'extracting', '正在解压安装包');
    const tempRoot = await fs.mkdtemp(join(tmpdir(), `clawke-skillhub-${slug}-`));
    try {
      await extractSkillHubArchive(archive.archivePath, tempRoot);
      const extractedRoot = await findSkillRoot(tempRoot);
      const targetDir = skillHubSkillDir(slug);
      await assertInside(SKILLHUB_SKILLS_DIR, targetDir);

      emitStatus(input.installId, slug, 'installing', '正在安装 Skill');
      await fs.mkdir(dirname(targetDir), { recursive: true });
      await fs.cp(extractedRoot, targetDir, { recursive: true, force: false, errorOnExist: true });

      emitStatus(input.installId, slug, 'recording', '正在记录安装信息');
      await recordSkillHubInstall({
        version: 1,
        source: 'clawhub',
        registry: resolveClawHubBaseUrl(),
        slug,
        installedVersion: version,
        archiveSha256: archive.sha256Hex,
        installedAt: Date.now(),
      });

      emitStatus(input.installId, slug, 'refreshing', '正在刷新Skill缓存');
      await input.refreshGateways?.(slug).catch(() => {
        // 刷新失败不回滚安装 — Refresh failure must not roll back install.
      });
      emitStatus(input.installId, slug, 'installed', '安装完成', {
        path: await findSkillMarkerPath(targetDir),
      });
    } finally {
      await fs.rm(tempRoot, { recursive: true, force: true });
    }
  } finally {
    await archive.cleanup().catch(() => undefined);
  }
}

export function validateSkillHubSlug(raw: string): string {
  const slug = raw.trim();
  if (!slug || slug.includes('/') || slug.includes('\\') || slug.includes('..') || !VALID_SLUG_PATTERN.test(slug)) {
    throw new ManagedSkillHubInstallError(`Invalid skill slug: ${raw}`, 'invalid_slug', false);
  }
  return slug;
}

function emitStatus(
  installId: string,
  slug: string,
  status: string,
  message: string,
  extra: Record<string, unknown> = {},
): void {
  broadcastToClients({
    payload_type: 'skillhub_install_status',
    installId,
    slug,
    installMode: 'managed',
    status,
    message,
    ...extra,
  });
}

async function assertZipEntriesSafe(archivePath: string): Promise<void> {
  const entries = await readZipEntries(archivePath);
  if (entries.length === 0) {
    throw new ManagedSkillHubInstallError('archive is empty', 'invalid_archive', false);
  }
  for (const entry of entries) {
    if (entry.path.startsWith('/') || entry.path.includes('\\') || entry.path.split('/').includes('..')) {
      throw new ManagedSkillHubInstallError(`unsafe archive entry: ${entry.path}`, 'unsafe_archive', false);
    }
  }
}

export async function extractSkillHubArchive(archivePath: string, targetDir: string): Promise<void> {
  try {
    const entries = await readZipEntries(archivePath);
    for (const entry of entries) {
      await extractZipEntry(entry, targetDir);
    }
  } catch (err) {
    throw new ManagedSkillHubInstallError(
      `解压安装包失败：${err instanceof Error ? err.message : String(err)}`,
      'extract_failed',
    );
  }
}

interface ZipEntry {
  path: string;
  dir: boolean;
  compressionMethod: number;
  compressedSize: number;
  uncompressedSize: number;
  localHeaderOffset: number;
  externalAttributes: number;
  archive: Buffer;
}

async function readZipEntries(archivePath: string): Promise<ZipEntry[]> {
  const archive = await fs.readFile(archivePath);
  const eocdOffset = findZipEndOfCentralDirectory(archive);
  if (eocdOffset < 0) throw new Error('invalid zip: missing end of central directory');
  const entryCount = archive.readUInt16LE(eocdOffset + 10);
  const centralDirectoryOffset = archive.readUInt32LE(eocdOffset + 16);
  const entries: ZipEntry[] = [];
  let offset = centralDirectoryOffset;
  for (let index = 0; index < entryCount; index += 1) {
    if (archive.readUInt32LE(offset) !== ZIP_CENTRAL_FILE_HEADER_SIGNATURE) {
      throw new Error('invalid zip: corrupt central directory');
    }
    const compressionMethod = archive.readUInt16LE(offset + 10);
    const compressedSize = archive.readUInt32LE(offset + 20);
    const uncompressedSize = archive.readUInt32LE(offset + 24);
    const nameLength = archive.readUInt16LE(offset + 28);
    const extraLength = archive.readUInt16LE(offset + 30);
    const commentLength = archive.readUInt16LE(offset + 32);
    const externalAttributes = archive.readUInt32LE(offset + 38);
    const localHeaderOffset = archive.readUInt32LE(offset + 42);
    const nameStart = offset + 46;
    const path = decodeZipName(archive.subarray(nameStart, nameStart + nameLength));
    entries.push({
      path,
      dir: path.endsWith('/'),
      compressionMethod,
      compressedSize,
      uncompressedSize,
      localHeaderOffset,
      externalAttributes,
      archive,
    });
    offset = nameStart + nameLength + extraLength + commentLength;
  }
  return entries;
}

function findZipEndOfCentralDirectory(buffer: Buffer): number {
  const minOffset = Math.max(0, buffer.length - ZIP_EOCD_MIN_BYTES - ZIP_EOCD_MAX_COMMENT_BYTES);
  for (let offset = buffer.length - ZIP_EOCD_MIN_BYTES; offset >= minOffset; offset -= 1) {
    if (buffer.readUInt32LE(offset) === ZIP_EOCD_SIGNATURE) return offset;
  }
  return -1;
}

function decodeZipName(bytes: Buffer): string {
  return new TextDecoder('utf-8', { fatal: false }).decode(bytes);
}

async function extractZipEntry(entry: ZipEntry, targetDir: string): Promise<void> {
  if (!entry.path || entry.path.startsWith('/') || entry.path.includes('\\') || entry.path.split('/').includes('..')) {
    throw new Error(`unsafe archive entry: ${entry.path}`);
  }
  if ((entry.externalAttributes >>> 16 & ZIP_UNIX_FILE_TYPE_MASK) === ZIP_UNIX_SYMLINK_TYPE) {
    throw new Error(`zip entry is a link: ${entry.path}`);
  }
  const targetPath = safeChildPath(targetDir, entry.path);
  if (entry.dir) {
    await fs.mkdir(targetPath, { recursive: true });
    return;
  }
  const content = await readZipEntryContent(entry);
  await fs.mkdir(dirname(targetPath), { recursive: true });
  await fs.writeFile(targetPath, content, { flag: 'wx' });
}

async function readZipEntryContent(entry: ZipEntry): Promise<Buffer> {
  const archive = entry.archive;
  if (archive.readUInt32LE(entry.localHeaderOffset) !== ZIP_LOCAL_FILE_HEADER_SIGNATURE) {
    throw new Error(`invalid zip local header: ${entry.path}`);
  }
  const localNameLength = archive.readUInt16LE(entry.localHeaderOffset + 26);
  const localExtraLength = archive.readUInt16LE(entry.localHeaderOffset + 28);
  const dataStart = entry.localHeaderOffset + 30 + localNameLength + localExtraLength;
  const dataEnd = dataStart + entry.compressedSize;
  if (dataEnd > archive.length) throw new Error(`invalid zip entry size: ${entry.path}`);
  const compressed = archive.subarray(dataStart, dataEnd);
  if (entry.compressionMethod === 0) return Buffer.from(compressed);
  if (entry.compressionMethod === 8) {
    const inflated = await inflateRawAsync(compressed);
    if (inflated.length !== entry.uncompressedSize) {
      throw new Error(`invalid zip entry inflated size: ${entry.path}`);
    }
    return inflated;
  }
  throw new Error(`unsupported zip compression method ${entry.compressionMethod}: ${entry.path}`);
}

async function findSkillRoot(tempRoot: string): Promise<string> {
  if (await hasRootMarker(tempRoot)) return tempRoot;
  const entries = await fs.readdir(tempRoot, { withFileTypes: true });
  const directories = entries.filter((entry) => entry.isDirectory());
  for (const directory of directories) {
    const candidate = join(tempRoot, directory.name);
    if (await hasRootMarker(candidate)) return candidate;
  }
  throw new ManagedSkillHubInstallError('archive is missing SKILL.md', 'missing_skill_marker', false);
}

async function hasRootMarker(root: string): Promise<boolean> {
  for (const marker of ROOT_MARKERS) {
    try {
      await fs.access(join(root, marker));
      return true;
    } catch {
      // 继续查找下一个入口标记 — Continue marker search.
    }
  }
  return false;
}

async function findSkillMarkerPath(root: string): Promise<string> {
  for (const marker of ROOT_MARKERS) {
    const candidate = join(root, marker);
    try {
      await fs.access(candidate);
      return candidate;
    } catch {
      // 继续查找实际入口文件 — Continue searching for the real entry file.
    }
  }
  return join(root, 'SKILL.md');
}

async function assertInside(baseDir: string, targetDir: string): Promise<void> {
  const base = resolve(baseDir);
  const target = resolve(targetDir);
  if (target === base || target.startsWith(`${base}${sep}`)) return;
  throw new ManagedSkillHubInstallError('invalid skill target path', 'invalid_target_path', false);
}

function normalizePath(value: string | null | undefined): string | null {
  if (!value) return null;
  try {
    return resolve(value);
  } catch {
    return null;
  }
}

function errorMessage(err: unknown): string {
  return err instanceof Error ? err.message : String(err);
}

export function createInstallId(): string {
  return `skillhub_${randomUUID()}`;
}

export async function sha256File(filePath: string): Promise<string> {
  const hash = createHash('sha256');
  hash.update(await fs.readFile(filePath));
  return hash.digest('hex');
}
