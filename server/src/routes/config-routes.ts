/**
 * 会话配置 REST API
 *
 * - GET  /api/config/models?account_id=xxx  → 查询 Gateway 可用模型
 * - GET  /api/config/skills?account_id=xxx  → 查询 Gateway 可用 Skills
 * - GET  /api/conv/:id/config → 读取会话配置
 * - PUT  /api/conv/:id/config → 保存会话配置
 */
import type { Request, Response } from 'express';
import type { ConversationConfigStore } from '../store/conversation-config-store.js';

// ─── 依赖注入 ───

let configStore: ConversationConfigStore | null = null;
let queryModelsFunc: ((accountId: string) => Promise<string[]>) | null = null;
let querySkillsFunc: ((accountId: string) => Promise<Array<{ name: string; description: string }>>) | null = null;

export function initConfigRoutes(deps: {
  configStore: ConversationConfigStore;
  queryModels: (accountId: string) => Promise<string[]>;
  querySkills: (accountId: string) => Promise<Array<{ name: string; description: string }>>;
}): void {
  configStore = deps.configStore;
  queryModelsFunc = deps.queryModels;
  querySkillsFunc = deps.querySkills;
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

const skillsCache = new Map<string, { skills: Array<{ name: string; description: string }>; expiresAt: number }>();
const SKILLS_CACHE_TTL = 30 * 60 * 1000; // 30 分钟

export async function getSkills(req: Request, res: Response): Promise<void> {
  try {
    const accountId = (req.query.account_id as string) || '';
    if (!accountId) {
      res.status(400).json({ error: 'account_id is required' });
      return;
    }

    const forceRefresh = req.query.refresh === '1';
    const cached = skillsCache.get(accountId);
    if (!forceRefresh && cached && Date.now() < cached.expiresAt) {
      res.json({ skills: cached.skills });
      return;
    }

    let skills: Array<{ name: string; description: string }> = [];
    if (querySkillsFunc) {
      skills = await querySkillsFunc(accountId);
    }

    // 空结果不缓存
    if (skills.length > 0) {
      skillsCache.set(accountId, { skills, expiresAt: Date.now() + SKILLS_CACHE_TTL });
    }
    res.json({ skills });
  } catch (err: any) {
    console.error('[ConfigAPI] getSkills error:', err.message);
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
