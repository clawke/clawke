/**
 * 会话配置 REST API
 *
 * - GET  /api/models?gateway_id=xxx         → 查询 Gateway 可用模型
 * - GET  /api/config/models?account_id=xxx  → 查询 Gateway 可用模型（兼容旧接口）
 * - GET  /api/config/skills?account_id=xxx  → 查询 Gateway 可用 Skills
 * - GET  /api/conv/:id/config → 读取会话配置
 * - PUT  /api/conv/:id/config → 保存会话配置
 */
import type { Request, Response } from 'express';
import type { ConversationConfigStore } from '../store/conversation-config-store.js';
import type { GatewayModelCacheStore } from '../store/gateway-model-cache-store.js';

// ─── 依赖注入 ───

let configStore: ConversationConfigStore | null = null;
let modelCacheStore: GatewayModelCacheStore | null = null;
let queryModelsFunc: ((gatewayId: string) => Promise<string[]>) | null = null;
let querySkillsFunc: ((accountId: string) => Promise<Array<{ name: string; description: string }>>) | null = null;

export function initConfigRoutes(deps: {
  configStore: ConversationConfigStore;
  modelCacheStore?: GatewayModelCacheStore;
  queryModels: (gatewayId: string) => Promise<string[]>;
  querySkills: (accountId: string) => Promise<Array<{ name: string; description: string }>>;
}): void {
  configStore = deps.configStore;
  modelCacheStore = deps.modelCacheStore ?? null;
  queryModelsFunc = deps.queryModels;
  querySkillsFunc = deps.querySkills;
  skillsCache.clear();
}

// ─── Models ───

export async function listModels(req: Request, res: Response): Promise<void> {
  await respondModels(req, res);
}

// 兼容旧版会话设置页的模型列表接口，新代码使用 /api/models。 — Compatibility endpoint for legacy conversation settings model list. New code should use /api/models.
export async function getModels(req: Request, res: Response): Promise<void> {
  await respondModels(req, res);
}

async function respondModels(req: Request, res: Response): Promise<void> {
  try {
    const gatewayId = resolveGatewayId(req);
    if (!gatewayId) {
      res.status(400).json({ error: 'gateway_id is required' });
      return;
    }

    const forceRefresh = req.query.refresh === '1' || req.query.refresh === 'true';
    const cachedModels = readCachedModels(gatewayId);
    if (!forceRefresh && cachedModels.length > 0) {
      res.json({ models: cachedModels });
      scheduleModelRefresh(gatewayId);
      return;
    }

    let models: string[] = [];
    try {
      models = await queryModelsFromGateway(gatewayId);
    } catch (err) {
      console.warn(`[ConfigAPI] model gateway query failed: ${err instanceof Error ? err.message : String(err)}`);
      res.json({ models: cachedModels });
      return;
    }
    if (models.length > 0) {
      writeCachedModels(gatewayId, models);
      res.json({ models });
      return;
    }

    res.json({ models: cachedModels });
  } catch (err: any) {
    console.error('[ConfigAPI] getModels error:', err.message);
    res.status(500).json({ error: err.message });
  }
}

async function queryModelsFromGateway(gatewayId: string): Promise<string[]> {
  if (!queryModelsFunc) return [];
  return queryModelsFunc(gatewayId);
}

function readCachedModels(gatewayId: string): string[] {
  if (!modelCacheStore) return [];
  try {
    return modelCacheStore.getGatewayModels(gatewayId);
  } catch (err) {
    console.warn(`[ConfigAPI] model cache read failed: ${err instanceof Error ? err.message : String(err)}`);
    return [];
  }
}

function writeCachedModels(gatewayId: string, models: string[]): void {
  if (!modelCacheStore || models.length === 0) return;
  try {
    modelCacheStore.replaceGatewayModels(gatewayId, models);
  } catch (err) {
    console.warn(`[ConfigAPI] model cache write failed: ${err instanceof Error ? err.message : String(err)}`);
  }
}

function scheduleModelRefresh(gatewayId: string): void {
  setTimeout(() => {
    void queryModelsFromGateway(gatewayId)
      .then((models) => {
        if (models.length > 0) writeCachedModels(gatewayId, models);
      })
      .catch((err) => {
        console.warn(`[ConfigAPI] model background refresh failed: ${err instanceof Error ? err.message : String(err)}`);
      });
  }, 0).unref?.();
}

function resolveGatewayId(req: Request): string {
  return (req.query.gateway_id as string) || (req.query.account_id as string) || '';
}

// ─── Skills ───

const skillsCache = new Map<string, { skills: Array<{ name: string; description: string }>; expiresAt: number }>();
const SKILLS_CACHE_TTL = 30 * 60 * 1000; // 30 分钟

// 兼容旧版会话设置页的 Skills 列表接口，新代码使用 /api/skills 并走客户端本地缓存。 — Compatibility endpoint for legacy conversation settings skills list. New code should use /api/skills with client-side cache.
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
      res.json({ skills: filterRuntimeSkills(cached.skills, accountId) });
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
    res.json({ skills: filterRuntimeSkills(skills, accountId) });
  } catch (err: any) {
    console.error('[ConfigAPI] getSkills error:', err.message);
    res.status(500).json({ error: err.message });
  }
}

function filterRuntimeSkills<T extends { name: string; description: string }>(skills: T[], accountId: string): T[] {
  void accountId;
  return skills;
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
