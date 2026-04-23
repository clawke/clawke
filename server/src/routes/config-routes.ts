/**
 * 会话配置 REST API
 *
 * - GET  /api/config/models?account_id=xxx  → 查询 Gateway 可用模型
 * - GET  /api/config/skills?account_id=xxx  → 查询 Gateway 可用 Skills
 * - GET  /api/config/skills/:dirName?account_id=xxx → 查询 Skill 详情
 * - POST /api/config/skills/:dirName → 保存/创建 Skill
 * - DELETE /api/config/skills/:dirName?account_id=xxx → 删除 Skill
 * - POST /api/config/skills/:dirName/toggle → 启用/禁用 Skill
 * - GET  /api/conv/:id/config → 读取会话配置
 * - PUT  /api/conv/:id/config → 保存会话配置
 */
import type { Request, Response } from 'express';
import type { ConversationConfigStore } from '../store/conversation-config-store.js';

// ─── 依赖注入 ───

let configStore: ConversationConfigStore | null = null;
let queryModelsFunc: ((accountId: string) => Promise<string[]>) | null = null;
type SkillInfo = {
  name: string;
  description: string;
  dir_name?: string;
  source?: string;
  disabled?: boolean;
};
type SkillDetailResult = {
  ok: boolean;
  dir_name: string;
  content?: string;
  name?: string;
  description?: string;
  source?: string;
  disabled?: boolean;
  error?: string;
};
type SkillMutationResult = {
  ok: boolean;
  error?: string;
};

let querySkillsFunc: ((accountId: string) => Promise<SkillInfo[]>) | null = null;
let querySkillDetailFunc: ((accountId: string, dirName: string) => Promise<SkillDetailResult>) | null = null;
let saveSkillFunc: ((accountId: string, dirName: string, content: string) => Promise<SkillMutationResult>) | null = null;
let deleteSkillFunc: ((accountId: string, dirName: string) => Promise<SkillMutationResult>) | null = null;
let toggleSkillFunc: ((accountId: string, dirName: string, disabled: boolean) => Promise<SkillMutationResult>) | null = null;

export function initConfigRoutes(deps: {
  configStore: ConversationConfigStore;
  queryModels: (accountId: string) => Promise<string[]>;
  querySkills: (accountId: string) => Promise<SkillInfo[]>;
  querySkillDetail: (accountId: string, dirName: string) => Promise<SkillDetailResult>;
  saveSkill: (accountId: string, dirName: string, content: string) => Promise<SkillMutationResult>;
  deleteSkill: (accountId: string, dirName: string) => Promise<SkillMutationResult>;
  toggleSkill: (accountId: string, dirName: string, disabled: boolean) => Promise<SkillMutationResult>;
}): void {
  configStore = deps.configStore;
  queryModelsFunc = deps.queryModels;
  querySkillsFunc = deps.querySkills;
  querySkillDetailFunc = deps.querySkillDetail;
  saveSkillFunc = deps.saveSkill;
  deleteSkillFunc = deps.deleteSkill;
  toggleSkillFunc = deps.toggleSkill;
}

// ─── Models ───

// 按 accountId 分 key 缓存
const modelCache = new Map<string, { models: string[]; expiresAt: number }>();
const MODEL_CACHE_TTL = 30 * 60 * 1000; // 30 分钟

export async function getModels(req: Request, res: Response): Promise<void> {
  try {
    const accountId = (req.query.account_id as string) || '';
    if (!accountId) {
      res.status(400).json({ error: 'account_id is required' });
      return;
    }

    const forceRefresh = req.query.refresh === '1';
    const cached = modelCache.get(accountId);
    if (!forceRefresh && cached && Date.now() < cached.expiresAt) {
      res.json({ models: cached.models });
      return;
    }

    let models: string[] = [];
    if (queryModelsFunc) {
      models = await queryModelsFunc(accountId);
    }

    // 空结果不缓存（gateway 可能还没连接）
    if (models.length > 0) {
      modelCache.set(accountId, { models, expiresAt: Date.now() + MODEL_CACHE_TTL });
    }
    res.json({ models });
  } catch (err: any) {
    console.error('[ConfigAPI] getModels error:', err.message);
    res.status(500).json({ error: err.message });
  }
}

// ─── Skills ───

const skillsCache = new Map<string, { skills: SkillInfo[]; expiresAt: number }>();
const SKILLS_CACHE_TTL = 30 * 60 * 1000; // 30 分钟
const SKILL_DIR_NAME_RE = /^[a-zA-Z0-9._-]+$/;

function isValidSkillDirName(dirName: string): boolean {
  return SKILL_DIR_NAME_RE.test(dirName);
}

function mapSkillErrorToStatus(error: string): number {
  if (error.includes('not found')) return 404;
  if (error.includes('read-only')) return 403;
  if (error.includes('invalid') || error.includes('empty')) return 400;
  return 500;
}

function invalidateSkillsCache(accountId: string): void {
  skillsCache.delete(accountId);
}

export async function getSkills(req: Request, res: Response): Promise<void> {
  try {
    const accountId = (req.query.account_id as string) || '';
    if (!accountId) {
      res.status(400).json({ error: 'account_id is required' });
      return;
    }

    const forceRefresh = req.query.refresh === '1';
    const includeDisabled = req.query.include_disabled === '1';
    const cached = skillsCache.get(accountId);
    if (!forceRefresh && cached && Date.now() < cached.expiresAt) {
      const output = includeDisabled
        ? cached.skills
        : cached.skills.filter((skill) => skill.disabled !== true);
      res.json({ skills: output });
      return;
    }

    let skills: SkillInfo[] = [];
    if (querySkillsFunc) {
      skills = await querySkillsFunc(accountId);
    }

    // 空结果不缓存
    if (skills.length > 0) {
      skillsCache.set(accountId, { skills, expiresAt: Date.now() + SKILLS_CACHE_TTL });
    }
    const output = includeDisabled
      ? skills
      : skills.filter((skill) => skill.disabled !== true);
    res.json({ skills: output });
  } catch (err: any) {
    console.error('[ConfigAPI] getSkills error:', err.message);
    res.status(500).json({ error: err.message });
  }
}

export async function getSkillDetail(req: Request, res: Response): Promise<void> {
  try {
    const accountId = (req.query.account_id as string) || '';
    if (!accountId) {
      res.status(400).json({ error: 'account_id is required' });
      return;
    }
    const dirName = (req.params.dirName as string) || '';
    if (!isValidSkillDirName(dirName)) {
      res.status(400).json({ error: 'invalid dir_name' });
      return;
    }

    if (!querySkillDetailFunc) {
      res.status(503).json({ error: 'Service not ready' });
      return;
    }

    const detail = await querySkillDetailFunc(accountId, dirName);
    if (!detail.ok) {
      res.status(mapSkillErrorToStatus(detail.error || '')).json({ error: detail.error || 'skill detail failed' });
      return;
    }

    res.json(detail);
  } catch (err: any) {
    console.error('[ConfigAPI] getSkillDetail error:', err.message);
    res.status(500).json({ error: err.message });
  }
}

export async function saveSkill(req: Request, res: Response): Promise<void> {
  try {
    const body = req.body || {};
    const accountId = String(body.account_id || '');
    const content = String(body.content || '');
    const dirName = (req.params.dirName as string) || '';
    if (!accountId) {
      res.status(400).json({ error: 'account_id is required' });
      return;
    }
    if (!isValidSkillDirName(dirName)) {
      res.status(400).json({ error: 'invalid dir_name' });
      return;
    }
    if (!content.trim()) {
      res.status(400).json({ error: 'content is required' });
      return;
    }
    if (!saveSkillFunc) {
      res.status(503).json({ error: 'Service not ready' });
      return;
    }

    const result = await saveSkillFunc(accountId, dirName, content);
    if (!result.ok) {
      res.status(mapSkillErrorToStatus(result.error || '')).json({ error: result.error || 'save skill failed' });
      return;
    }
    invalidateSkillsCache(accountId);
    res.json({ ok: true });
  } catch (err: any) {
    console.error('[ConfigAPI] saveSkill error:', err.message);
    res.status(500).json({ error: err.message });
  }
}

export async function deleteSkill(req: Request, res: Response): Promise<void> {
  try {
    const accountId = (req.query.account_id as string) || '';
    const dirName = (req.params.dirName as string) || '';
    if (!accountId) {
      res.status(400).json({ error: 'account_id is required' });
      return;
    }
    if (!isValidSkillDirName(dirName)) {
      res.status(400).json({ error: 'invalid dir_name' });
      return;
    }
    if (!deleteSkillFunc) {
      res.status(503).json({ error: 'Service not ready' });
      return;
    }

    const result = await deleteSkillFunc(accountId, dirName);
    if (!result.ok) {
      res.status(mapSkillErrorToStatus(result.error || '')).json({ error: result.error || 'delete skill failed' });
      return;
    }
    invalidateSkillsCache(accountId);
    res.json({ ok: true });
  } catch (err: any) {
    console.error('[ConfigAPI] deleteSkill error:', err.message);
    res.status(500).json({ error: err.message });
  }
}

export async function toggleSkill(req: Request, res: Response): Promise<void> {
  try {
    const body = req.body || {};
    const accountId = String(body.account_id || '');
    const disabled = body.disabled === true;
    const dirName = (req.params.dirName as string) || '';
    if (!accountId) {
      res.status(400).json({ error: 'account_id is required' });
      return;
    }
    if (!isValidSkillDirName(dirName)) {
      res.status(400).json({ error: 'invalid dir_name' });
      return;
    }
    if (body.disabled !== true && body.disabled !== false) {
      res.status(400).json({ error: 'disabled must be boolean' });
      return;
    }
    if (!toggleSkillFunc) {
      res.status(503).json({ error: 'Service not ready' });
      return;
    }

    const result = await toggleSkillFunc(accountId, dirName, disabled);
    if (!result.ok) {
      res.status(mapSkillErrorToStatus(result.error || '')).json({ error: result.error || 'toggle skill failed' });
      return;
    }
    invalidateSkillsCache(accountId);
    res.json({ ok: true });
  } catch (err: any) {
    console.error('[ConfigAPI] toggleSkill error:', err.message);
    res.status(500).json({ error: err.message });
  }
}

// ─── Conversation Config ───

export function getConvConfig(req: Request, res: Response): void {
  const convId = req.params.id as string;
  if (!configStore) {
    res.status(503).json({ error: 'Service not ready' });
    return;
  }
  const config = configStore.get(convId);
  if (!config) {
    res.json({ conv_id: convId, model_id: null, skills: null, skill_mode: null, system_prompt: null, work_dir: null });
    return;
  }
  res.json({
    conv_id: config.convId,
    account_id: config.accountId,
    model_id: config.modelId,
    skills: config.skills,
    skill_mode: config.skillMode,
    system_prompt: config.systemPrompt,
    work_dir: config.workDir,
  });
}

export function putConvConfig(req: Request, res: Response): void {
  const convId = req.params.id as string;
  if (!configStore) {
    res.status(503).json({ error: 'Service not ready' });
    return;
  }
  const body = req.body || {};
  const accountId = body.account_id;
  if (!accountId) {
    res.status(400).json({ error: 'account_id is required' });
    return;
  }
  configStore.set(convId, accountId, {
    modelId: body.model_id,
    skills: body.skills,
    skillMode: body.skill_mode,
    systemPrompt: body.system_prompt,
    workDir: body.work_dir,
  });
  console.log(`[ConfigAPI] Saved config for conv=${convId}: model=${body.model_id}, skills=${body.skills}, mode=${body.skill_mode}, workDir=${body.work_dir || 'default'}`);
  res.json({ ok: true });
}
