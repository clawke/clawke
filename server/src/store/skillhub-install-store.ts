import { promises as fs } from 'node:fs';
import { dirname, join, resolve, sep } from 'node:path';
import { CLAWKE_HOME } from './clawke-home.js';

export const SKILLHUB_SKILLS_DIR = join(CLAWKE_HOME, 'skills');
const SKILLHUB_DOT_DIR = '.skillhub';
const CLAWHUB_DOT_DIR = '.clawhub';

export interface SkillHubInstallOrigin {
  version: 1;
  source: 'clawhub';
  registry: string;
  slug: string;
  installedVersion: string;
  archiveSha256: string;
  installedAt: number;
}

export interface SkillHubInstallLock {
  version: 1;
  skills: Record<string, {
    version: string;
    installedAt: number;
    archiveSha256?: string;
  }>;
}

export function skillHubSkillDir(slug: string): string {
  return safeChildPath(SKILLHUB_SKILLS_DIR, slug);
}

export async function isSkillHubSkillInstalled(slug: string): Promise<boolean> {
  try {
    await fs.access(join(skillHubSkillDir(slug), 'SKILL.md'));
    return true;
  } catch {
    return false;
  }
}

export async function readSkillHubInstallLock(): Promise<SkillHubInstallLock> {
  try {
    const raw = await fs.readFile(lockPath(), 'utf8');
    const parsed = JSON.parse(raw) as Partial<SkillHubInstallLock>;
    if (parsed.version === 1 && parsed.skills && typeof parsed.skills === 'object') {
      return { version: 1, skills: parsed.skills };
    }
  } catch {
    // 忽略缺失或格式错误的 lock — Ignore missing or malformed lock.
  }
  return { version: 1, skills: {} };
}

export async function recordSkillHubInstall(origin: SkillHubInstallOrigin): Promise<void> {
  const skillDir = skillHubSkillDir(origin.slug);
  await writeJson(join(skillDir, SKILLHUB_DOT_DIR, 'origin.json'), origin);
  await writeJson(join(skillDir, CLAWHUB_DOT_DIR, 'origin.json'), {
    version: 1,
    registry: origin.registry,
    slug: origin.slug,
    installedVersion: origin.installedVersion,
    installedAt: origin.installedAt,
  });
  const lock = await readSkillHubInstallLock();
  lock.skills[origin.slug] = {
    version: origin.installedVersion,
    installedAt: origin.installedAt,
    archiveSha256: origin.archiveSha256,
  };
  await writeJson(lockPath(), lock);
}

export function safeChildPath(baseDir: string, childName: string): string {
  const base = resolve(baseDir);
  const target = resolve(base, childName);
  if (target !== base && target.startsWith(`${base}${sep}`)) return target;
  throw new Error('invalid skill target path');
}

function lockPath(): string {
  return join(SKILLHUB_SKILLS_DIR, SKILLHUB_DOT_DIR, 'lock.json');
}

async function writeJson(filePath: string, value: unknown): Promise<void> {
  await fs.mkdir(dirname(filePath), { recursive: true });
  await fs.writeFile(filePath, `${JSON.stringify(value, null, 2)}\n`, 'utf8');
}
