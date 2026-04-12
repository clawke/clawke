/**
 * 会话配置 REST API
 *
 * - GET  /api/config/models  → 查询可用模型（通过 WS 查 Gateway）
 * - GET  /api/config/skills  → 扫描 skills 目录
 * - GET  /api/conv/:id/config → 读取会话配置
 * - PUT  /api/conv/:id/config → 保存会话配置
 */
import type { Request, Response } from 'express';
import * as fs from 'fs';
import * as path from 'path';
import type { ConversationConfigStore } from '../store/conversation-config-store.js';

// ─── 依赖注入 ───

let configStore: ConversationConfigStore | null = null;
let queryModelsFunc: (() => Promise<string[]>) | null = null;
let skillsDirs: string[] = [];

export function initConfigRoutes(deps: {
  configStore: ConversationConfigStore;
  queryModels: () => Promise<string[]>;
  skillsDirs: string[];
}): void {
  configStore = deps.configStore;
  queryModelsFunc = deps.queryModels;
  skillsDirs = deps.skillsDirs;
}

// ─── Models ───

let modelCache: { models: string[]; expiresAt: number } | null = null;
const MODEL_CACHE_TTL = 30 * 60 * 1000; // 30 分钟

/** 从 OpenClaw models.json 文件直接读取可用模型 */
function readModelsFromFile(): string[] {
  try {
    const os = require('os');
    const modelsPath = path.join(os.homedir(), '.openclaw', 'agents', 'main', 'agent', 'models.json');
    if (!fs.existsSync(modelsPath)) return [];
    const data = JSON.parse(fs.readFileSync(modelsPath, 'utf-8'));
    const models: string[] = [];
    if (data.providers && typeof data.providers === 'object') {
      for (const [providerName, provider] of Object.entries(data.providers)) {
        const p = provider as any;
        if (Array.isArray(p.models)) {
          for (const m of p.models) {
            if (m.id) models.push(`${providerName}/${m.id}`);
          }
        }
      }
    }
    return models;
  } catch {
    return [];
  }
}

export async function getModels(req: Request, res: Response): Promise<void> {
  try {
    const forceRefresh = req.query.refresh === '1';
    if (!forceRefresh && modelCache && Date.now() < modelCache.expiresAt) {
      res.json({ models: modelCache.models });
      return;
    }
    // 策略 1：直接读 OpenClaw models.json（零延迟）
    let models = readModelsFromFile();
    // 策略 2：WS 查询 Gateway（fallback）
    if (models.length === 0 && queryModelsFunc) {
      models = await queryModelsFunc();
    }
    modelCache = { models, expiresAt: Date.now() + MODEL_CACHE_TTL };
    res.json({ models });
  } catch (err: any) {
    console.error('[ConfigAPI] getModels error:', err.message);
    res.status(500).json({ error: err.message });
  }
}

// ─── Skills ───

let skillsCache: { skills: Array<{ name: string; description: string }>; expiresAt: number } | null = null;
const SKILLS_CACHE_TTL = 30 * 60 * 1000; // 30 分钟

export function getSkills(req: Request, res: Response): void {
  try {
    const forceRefresh = req.query.refresh === '1';
    if (!forceRefresh && skillsCache && Date.now() < skillsCache.expiresAt) {
      res.json({ skills: skillsCache.skills });
      return;
    }
    const seen = new Set<string>();
    const skills: Array<{ name: string; description: string }> = [];
    for (const dir of skillsDirs) {
      if (!dir || !fs.existsSync(dir)) continue;
      const entries = fs.readdirSync(dir, { withFileTypes: true });
      for (const entry of entries) {
        if (!entry.isDirectory() || seen.has(entry.name)) continue;
        const skillMd = path.join(dir, entry.name, 'SKILL.md');
        if (!fs.existsSync(skillMd)) continue;
        const content = fs.readFileSync(skillMd, 'utf-8');
        const desc = extractSkillDescription(content, entry.name);
        skills.push({ name: entry.name, description: desc });
        seen.add(entry.name);
      }
    }
    skillsCache = { skills, expiresAt: Date.now() + SKILLS_CACHE_TTL };
    res.json({ skills });
  } catch (err: any) {
    console.error('[ConfigAPI] getSkills error:', err.message);
    res.status(500).json({ error: err.message });
  }
}

function extractSkillDescription(content: string, fallbackName: string): string {
  // 先尝试 YAML frontmatter
  const fmMatch = content.match(/^---\s*\n([\s\S]*?)\n---/);
  if (fmMatch) {
    const descMatch = fmMatch[1].match(/description:\s*(.+)/i);
    if (descMatch) return descMatch[1].trim();
  }
  // 退而求其次：取第一个非空行
  const firstLine = content.split('\n').find(l => l.trim() && !l.startsWith('#') && !l.startsWith('---'));
  return firstLine?.trim().slice(0, 120) || fallbackName;
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
