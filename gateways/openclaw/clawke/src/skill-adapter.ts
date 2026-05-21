import {
  existsSync,
  mkdirSync,
  readdirSync,
  readFileSync,
  renameSync,
  rmSync,
  statSync,
  writeFileSync,
  type Dirent,
} from "node:fs";
import { createHash } from "node:crypto";
import { dirname, join, relative, resolve, sep } from "node:path";
import { homedir } from "node:os";
import {
  createOpenClawGatewayRpc,
  type OpenClawGatewayRpc,
  type OpenClawGatewayRpcOptions,
} from "./task-adapter.ts";

export interface OpenClawSkillDraft {
  name?: string;
  category?: string;
  description?: string;
  trigger?: string;
  body?: string;
  content?: string;
}

export interface OpenClawSkillHubInstallPackage {
  id?: string;
  slug: string;
  name?: string;
  source?: string;
  sourceOwner?: string;
  version?: string;
  packageUrl?: string;
  packageSha256?: string;
  packageType?: string;
  gatewayType?: string;
}

export interface OpenClawManagedSkill {
  id: string;
  name: string;
  description: string;
  category: string;
  trigger?: string;
  enabled: boolean;
  source: "managed" | "external" | "readonly";
  sourceLabel: string;
  writable: boolean;
  deletable: boolean;
  path: string;
  absolutePath: string;
  root: string;
  updatedAt: number;
  hasConflict: boolean;
  content?: string;
  body?: string;
  frontmatter?: Record<string, unknown>;
}

interface SkillState {
  version: 1;
  skills: Record<string, {
    skillId: string;
    source: "managed" | "external" | "readonly";
    category: string;
    name: string;
    enabled: boolean;
    disableMethod?: "move" | "state" | "config";
    path: string;
    originalPath?: string;
    disabledPath?: string;
    disabledAt?: string;
    lastSyncedAt?: string;
  }>;
}

type SkillRoot = {
  root: string;
  enabled: boolean;
  source: "managed" | "external" | "readonly";
  sourceLabel: string;
  writable: boolean;
  deletable: boolean;
};

type RpcSkillStatus = {
  id?: string;
  skillKey?: string;
  name?: string;
  description?: string;
  source?: string;
  bundled?: boolean;
  filePath?: string;
  baseDir?: string;
  disabled?: boolean;
  eligible?: boolean;
  always?: boolean;
  emoji?: string;
  homepage?: string;
  triggers?: string[];
  missing?: unknown;
  requirements?: unknown;
  install?: unknown;
  updatedAt?: number;
  updatedAtMs?: number;
};

export interface OpenClawSkillAdapterOptions extends OpenClawGatewayRpcOptions {
  rpc?: OpenClawGatewayRpc;
}

const SAFE_SEGMENT = /^[A-Za-z0-9][A-Za-z0-9._-]*$/;
const SKILLHUB_UPLOAD_CHUNK_BYTES = 256 * 1024;

export class OpenClawSkillAdapter {
  private readonly rpc: OpenClawGatewayRpc;
  private readonly legacyLocal: LegacyLocalOpenClawSkillAdapter;
  private readonly localOverrides = new Map<string, OpenClawManagedSkill>();
  private readonly hiddenLocalIds = new Set<string>();

  constructor(
    _clawkeHome = join(homedir(), ".clawke"),
    options: OpenClawSkillAdapterOptions = {},
  ) {
    this.legacyLocal = new LegacyLocalOpenClawSkillAdapter(_clawkeHome);
    this.rpc = options.rpc ?? createOpenClawGatewayRpc(options);
  }

  async listSkills(): Promise<OpenClawManagedSkill[]> {
    let result: unknown;
    try {
      result = await this.rpc("skills.status");
    } catch (err) {
      if (!this.isSkillMetadataError(err)) throw err;
      return this.legacyLocal.listSkills().sort((a, b) => a.name.localeCompare(b.name));
    }
    const byId = new Map<string, OpenClawManagedSkill>();
    for (const skill of this.extractSkills(result).map((item) => this.withLocalContent(this.toManagedSkill(item)))) {
      if (!this.hiddenLocalIds.has(skill.id)) byId.set(skill.id, skill);
    }
    this.addShadowedClawkeManagedSkills(byId);
    for (const [id, skill] of this.localOverrides) {
      if (skill.absolutePath && existsSync(skill.absolutePath)) {
        byId.set(id, this.withLocalContent(skill));
      } else {
        this.localOverrides.delete(id);
      }
    }
    return [...byId.values()].sort((a, b) => a.name.localeCompare(b.name));
  }

  async listRuntimeSkills(): Promise<Array<{ name: string; description: string }>> {
    return (await this.listSkills())
      .filter((skill) => skill.enabled)
      .map((skill) => ({ name: skill.name, description: skill.description }));
  }

  async getSkill(id: string): Promise<OpenClawManagedSkill | null> {
    const skillKey = this.skillKeyFromId(id);
    const skills = await this.listSkills();
    const skill = skills.find((item) => item.id === id)
      ?? skills.find((item) => this.skillKeyFromId(item.id) === skillKey)
      ?? null;
    return skill ? this.withLocalContent(skill) : null;
  }

  async createSkill(draft: OpenClawSkillDraft): Promise<OpenClawManagedSkill> {
    const legacyCreated = this.legacyLocal.createSkill(draft);
    const id = this.skillId("openclaw-extra", legacyCreated.name);
    const skillDir = dirname(legacyCreated.absolutePath);
    const created = this.withLocalContent({
      ...legacyCreated,
      id,
      category: "openclaw-extra",
      enabled: true,
      source: "external",
      sourceLabel: "OpenClaw openclaw-extra",
      writable: true,
      deletable: true,
      path: legacyCreated.absolutePath,
      root: skillDir,
      frontmatter: {
        ...legacyCreated.frontmatter,
        skillKey: legacyCreated.name,
        source: "openclaw-extra",
        bundled: false,
        always: false,
      },
    });
    this.localOverrides.set(id, created);
    return created;
  }

  async updateSkill(id: string, draft: OpenClawSkillDraft): Promise<OpenClawManagedSkill> {
    const existing = await this.requireSkill(id);
    if (!existing.writable) throw new Error(`Skill is not writable: ${id}`);

    const normalized = this.normalizeDraft({
      name: draft.name ?? existing.name,
      category: draft.category ?? existing.category,
      description: draft.description ?? existing.description,
      trigger: draft.trigger ?? existing.trigger,
      body: draft.body ?? draft.content ?? existing.body ?? "",
    });
    const nextId = this.skillId(normalized.category, normalized.name);
    const currentDir = dirname(existing.absolutePath);
    const nextDir = this.safePath(dirname(currentDir), normalized.name);
    if (resolve(currentDir) !== resolve(nextDir)) {
      if (existsSync(nextDir)) throw new Error(`Skill already exists: ${nextId}`);
      mkdirSync(dirname(nextDir), { recursive: true });
      renameSync(currentDir, nextDir);
    }
    const nextPath = join(nextDir, "SKILL.md");
    writeFileSync(nextPath, this.buildContent(normalized), "utf-8");

    if (nextId !== id) {
      this.localOverrides.delete(id);
      this.hiddenLocalIds.add(id);
    }
    this.hiddenLocalIds.delete(nextId);
    const updated = this.withLocalContent({
      ...existing,
      id: nextId,
      name: normalized.name,
      category: normalized.category,
      description: normalized.description,
      trigger: normalized.trigger,
      path: nextPath,
      absolutePath: nextPath,
      root: nextDir,
      updatedAt: statSync(nextPath).mtimeMs,
    });
    this.localOverrides.set(nextId, updated);
    return updated;
  }

  async deleteSkill(id: string): Promise<boolean> {
    const existing = await this.requireSkill(id);
    if (!existing.deletable) throw new Error(`Skill is not deletable: ${id}`);
    rmSync(dirname(existing.absolutePath), { recursive: true, force: true });
    this.localOverrides.delete(id);
    this.hiddenLocalIds.add(id);
    return true;
  }

  async setEnabled(id: string, enabled: boolean): Promise<OpenClawManagedSkill> {
    if (this.isClawkeManagedLocalSkill(id)) {
      throw new Error(`Skill is shadowed and cannot be toggled: ${id}`);
    }
    const skillKey = this.skillKeyFromId(id);
    await this.rpc("skills.update", { skillKey, enabled });
    return (await this.getSkill(id)) ?? this.placeholderSkill(id, skillKey, enabled);
  }

  async installSkillHubPackage(installPackage: OpenClawSkillHubInstallPackage): Promise<OpenClawManagedSkill | null> {
    const normalized = this.normalizeSkillHubPackage(installPackage);
    if (normalized.source?.toLowerCase() === "clawhub") {
      return this.installClawHubSkillHubPackage(normalized);
    }

    const packageUrl = normalized.packageUrl;
    const packageSha256 = normalized.packageSha256;
    if (!packageUrl || !packageSha256) throw new Error("SkillHub package archive metadata is required");

    const archive = await this.downloadSkillHubArchive(packageUrl);
    const digest = createHash("sha256").update(archive).digest("hex");
    if (digest.toLowerCase() !== packageSha256.toLowerCase()) {
      throw new Error("SkillHub package sha256 mismatch");
    }

    const begin = await this.rpc("skills.upload.begin", {
      kind: "skill-archive",
      slug: normalized.slug,
      sizeBytes: archive.byteLength,
      sha256: digest,
    }, { timeoutMs: 30_000 });
    const uploadId = this.requireUploadId(begin);

    for (let offset = 0; offset < archive.byteLength; offset += SKILLHUB_UPLOAD_CHUNK_BYTES) {
      const chunk = archive.subarray(offset, Math.min(offset + SKILLHUB_UPLOAD_CHUNK_BYTES, archive.byteLength));
      await this.rpc("skills.upload.chunk", {
        uploadId,
        offset,
        dataBase64: Buffer.from(chunk).toString("base64"),
      }, { timeoutMs: 30_000 });
    }

    this.requirePayloadOk(await this.rpc("skills.upload.commit", {
      uploadId,
      sha256: digest,
    }, { timeoutMs: 30_000 }));

    this.requirePayloadOk(await this.rpc("skills.install", {
      source: "upload",
      uploadId,
      slug: normalized.slug,
      sha256: digest,
    }, { timeoutMs: 90_000 }));

    const skills = await this.listSkills();
    return skills.find((skill) => this.skillKeyFromId(skill.id) === normalized.slug) ?? null;
  }

  private async installClawHubSkillHubPackage(installPackage: OpenClawSkillHubInstallPackage): Promise<OpenClawManagedSkill | null> {
    this.requirePayloadOk(await this.rpc("skills.install", {
      source: "clawhub",
      slug: installPackage.slug,
      ...(installPackage.version ? { version: installPackage.version } : {}),
    }, { timeoutMs: 90_000 }));

    const skills = await this.listSkills();
    return skills.find((skill) => this.skillKeyFromId(skill.id) === installPackage.slug) ?? null;
  }

  ensureOpenClawExtraDir(): boolean {
    // 旧的本地 extraDirs 注入已停用，skills 现在以 OpenClaw RPC 为准 — Legacy local extraDirs injection is disabled; skills now come from OpenClaw RPC.
    return true;
  }

  private extractSkills(value: unknown): RpcSkillStatus[] {
    if (Array.isArray(value)) return value.filter((item): item is RpcSkillStatus => this.isRecord(item));
    if (!this.isRecord(value)) return [];
    const candidates = [value.skills, value.items, value.list];
    for (const candidate of candidates) {
      if (Array.isArray(candidate)) return candidate.filter((item): item is RpcSkillStatus => this.isRecord(item));
    }
    return [];
  }

  private toManagedSkill(skill: RpcSkillStatus): OpenClawManagedSkill {
    const skillKey = this.normalizeSegment(skill.skillKey ?? skill.id ?? skill.name ?? "skill");
    const category = this.categoryFor(skill);
    const enabled = skill.disabled !== true;
    const source = skill.bundled === true || skill.always === true ? "readonly" : "external";
    const filePath = String(skill.filePath ?? "");
    const baseDir = String(skill.baseDir ?? "");
    const canEditLocalFile = source !== "readonly" && this.isSkillFile(filePath) && existsSync(filePath);
    return {
      id: `${category}/${skillKey}`,
      name: String(skill.name ?? skillKey),
      description: String(skill.description ?? ""),
      category,
      trigger: Array.isArray(skill.triggers) ? skill.triggers.join(", ") : undefined,
      enabled,
      source,
      sourceLabel: this.sourceLabelFor(skill),
      writable: canEditLocalFile,
      deletable: canEditLocalFile,
      path: filePath,
      absolutePath: filePath,
      root: baseDir,
      updatedAt: Number(skill.updatedAtMs ?? skill.updatedAt ?? 0),
      hasConflict: false,
      frontmatter: {
        skillKey,
        source: skill.source,
        bundled: skill.bundled,
        eligible: skill.eligible,
        always: skill.always,
        missing: skill.missing,
        requirements: skill.requirements,
        install: skill.install,
        emoji: skill.emoji,
        homepage: skill.homepage,
      },
    };
  }

  private addShadowedClawkeManagedSkills(byId: Map<string, OpenClawManagedSkill>): void {
    const returnedPaths = new Set(
      [...byId.values()]
        .map((skill) => skill.absolutePath ? resolve(skill.absolutePath) : "")
        .filter(Boolean),
    );
    const returnedKeys = new Set([...byId.values()].map((skill) => this.skillKeyFromId(skill.id)));
    for (const skill of this.legacyLocal.listSkills()) {
      if (skill.sourceLabel !== "Clawke skills") continue;
      if (byId.has(skill.id)) continue;
      if (skill.absolutePath && returnedPaths.has(resolve(skill.absolutePath))) continue;
      if (!returnedKeys.has(this.skillKeyFromId(skill.id))) continue;
      byId.set(skill.id, this.withLocalContent({
        ...skill,
        enabled: false,
        sourceLabel: "Clawke skills (shadowed)",
        writable: false,
        deletable: true,
        hasConflict: true,
        frontmatter: {
          ...skill.frontmatter,
          shadowed: true,
        },
      }));
    }
  }

  private isClawkeManagedLocalSkill(id: string): boolean {
    return this.legacyLocal.listSkills().some((skill) => skill.id === id && skill.sourceLabel === "Clawke skills");
  }

  private placeholderSkill(id: string, skillKey: string, enabled: boolean): OpenClawManagedSkill {
    const category = this.categoryFromId(id);
    return {
      id,
      name: skillKey,
      description: "",
      category,
      enabled,
      source: "external",
      sourceLabel: "OpenClaw skills",
      writable: false,
      deletable: false,
      path: "",
      absolutePath: "",
      root: "",
      updatedAt: 0,
      hasConflict: false,
      frontmatter: { skillKey },
    };
  }

  private categoryFor(skill: RpcSkillStatus): string {
    if (skill.bundled === true) return "openclaw-bundled";
    const source = String(skill.source ?? "").trim();
    return this.normalizeSegment(source || "openclaw");
  }

  private sourceLabelFor(skill: RpcSkillStatus): string {
    if (skill.bundled === true) return "OpenClaw built-in skills";
    const source = String(skill.source ?? "").trim();
    return source ? `OpenClaw ${source}` : "OpenClaw skills";
  }

  private withLocalContent(skill: OpenClawManagedSkill): OpenClawManagedSkill {
    if (!skill.absolutePath || !existsSync(skill.absolutePath)) return skill;
    const content = readFileSync(skill.absolutePath, "utf-8");
    const parsed = this.parseContent(content);
    return {
      ...skill,
      description: String(parsed.frontmatter.description || skill.description).trim(),
      trigger: parsed.frontmatter.trigger ? String(parsed.frontmatter.trigger) : skill.trigger,
      content,
      body: parsed.body,
      frontmatter: {
        ...skill.frontmatter,
        ...parsed.frontmatter,
      },
      updatedAt: statSync(skill.absolutePath).mtimeMs,
    };
  }

  private skillKeyFromId(id: string): string {
    const parts = id.split("/");
    const skillKey = parts.length === 2 ? parts[1] : id;
    this.requireSafeSegment(skillKey, "skill key");
    return skillKey;
  }

  private categoryFromId(id: string): string {
    const parts = id.split("/");
    return parts.length === 2 ? parts[0] : "openclaw";
  }

  private async requireSkill(id: string): Promise<OpenClawManagedSkill> {
    const skill = await this.getSkill(id);
    if (!skill) throw new Error(`Skill not found: ${id}`);
    return skill;
  }

  private skillId(category: string, name: string): string {
    this.requireSafeSegment(category, "skill category");
    this.requireSafeSegment(name, "skill name");
    return `${category}/${name}`;
  }

  private normalizeDraft(draft: OpenClawSkillDraft): Required<Pick<OpenClawSkillDraft, "name" | "category" | "description" | "body">> & { trigger?: string } {
    const name = (draft.name || "").trim();
    const category = (draft.category || "general").trim();
    const description = (draft.description || "").trim();
    this.requireSafeSegment(name, "skill name");
    this.requireSafeSegment(category, "skill category");
    if (!description) throw new Error("description is required");
    return {
      name,
      category,
      description,
      trigger: draft.trigger?.trim() || undefined,
      body: draft.body ?? draft.content ?? "",
    };
  }

  private normalizeSkillHubPackage(installPackage: OpenClawSkillHubInstallPackage): OpenClawSkillHubInstallPackage {
    const slug = this.normalizeSegment(installPackage.slug);
    const normalized = {
      ...installPackage,
      id: installPackage.id?.trim() || "",
      slug,
      name: installPackage.name?.trim() || slug,
      source: installPackage.source?.trim() || undefined,
      sourceOwner: installPackage.sourceOwner?.trim() || undefined,
      version: installPackage.version?.trim() || undefined,
      packageUrl: installPackage.packageUrl?.trim() || undefined,
      packageSha256: installPackage.packageSha256?.trim() || undefined,
      packageType: installPackage.packageType?.trim() || undefined,
      gatewayType: installPackage.gatewayType?.trim() || undefined,
    };
    this.requireSafeSegment(normalized.slug, "SkillHub package slug");
    if (normalized.source?.toLowerCase() === "clawhub") return normalized;
    if (!normalized.id) throw new Error("SkillHub package id is required");
    if (!normalized.name) throw new Error("SkillHub package name is required");
    if (!normalized.version) throw new Error("SkillHub package version is required");
    if (!normalized.packageUrl) throw new Error("SkillHub packageUrl is required");
    if (!normalized.packageSha256 || !/^[a-fA-F0-9]{64}$/.test(normalized.packageSha256)) {
      throw new Error("SkillHub packageSha256 must be a 64-character hex digest");
    }
    return normalized;
  }

  private async downloadSkillHubArchive(packageUrl: string): Promise<Uint8Array> {
    if (typeof fetch !== "function") throw new Error("fetch is not available in this runtime");
    const response = await fetch(packageUrl);
    if (!response.ok) {
      throw new Error(`Failed to download SkillHub package: HTTP ${response.status}`);
    }
    return new Uint8Array(await response.arrayBuffer());
  }

  private requireUploadId(value: unknown): string {
    if (this.isRecord(value) && typeof value.uploadId === "string" && value.uploadId.trim()) {
      return value.uploadId;
    }
    throw new Error("OpenClaw skills.upload.begin did not return uploadId");
  }

  private requirePayloadOk(value: unknown): void {
    if (this.isRecord(value) && value.ok === false) {
      const message = this.isRecord(value.error) && typeof value.error.message === "string"
        ? value.error.message
        : "OpenClaw SkillHub install failed";
      throw new Error(message);
    }
  }

  private buildContent(draft: Required<Pick<OpenClawSkillDraft, "name" | "category" | "description" | "body">> & { trigger?: string }): string {
    const frontmatter = [
      "---",
      `name: ${this.yamlValue(draft.name)}`,
      `category: ${this.yamlValue(draft.category)}`,
      `description: ${this.yamlValue(draft.description)}`,
      ...(draft.trigger ? [`trigger: ${this.yamlValue(draft.trigger)}`] : []),
      "---",
      "",
    ].join("\n");
    return `${frontmatter}${draft.body || ""}`;
  }

  private parseContent(content: string): { frontmatter: Record<string, string>; body: string } {
    const match = content.match(/^---\s*\r?\n([\s\S]*?)\r?\n---\s*\r?\n?/);
    if (!match) return { frontmatter: {}, body: content };
    const frontmatter: Record<string, string> = {};
    for (const line of match[1].split(/\r?\n/)) {
      const pair = line.match(/^([A-Za-z0-9_-]+):\s*(.*)$/);
      if (!pair) continue;
      frontmatter[pair[1]] = this.unquote(pair[2].trim());
    }
    return { frontmatter, body: content.slice(match[0].length) };
  }

  private safePath(root: string, segment: string): string {
    this.requireSafeSegment(segment, "skill name");
    const resolvedRoot = resolve(root);
    const target = resolve(resolvedRoot, segment);
    if (target !== resolvedRoot && !target.startsWith(`${resolvedRoot}${sep}`)) {
      throw new Error(`Invalid path segment: ${segment}`);
    }
    return target;
  }

  private normalizeSegment(value: string): string {
    const normalized = value.trim().replace(/[^A-Za-z0-9._-]+/g, "-").replace(/^-+|-+$/g, "");
    return normalized || "skill";
  }

  private isSkillFile(path: string): boolean {
    return path.replace(/\\/g, "/").endsWith("/SKILL.md");
  }

  private isRecord(value: unknown): value is Record<string, unknown> {
    return Boolean(value && typeof value === "object");
  }

  private isSkillMetadataError(err: unknown): boolean {
    const message = err instanceof Error ? err.message : String(err);
    return /\bInvalid skill (?:name|category|id|key)\b/.test(message);
  }

  private requireSafeSegment(value: string, label: string): void {
    if (!SAFE_SEGMENT.test(value) || value === "." || value === "..") {
      throw new Error(`Invalid ${label}: ${value}`);
    }
  }

  private yamlValue(value: string): string {
    return value.replace(/\r?\n/g, " ").trim();
  }

  private unquote(value: string): string {
    if ((value.startsWith('"') && value.endsWith('"')) || (value.startsWith("'") && value.endsWith("'"))) {
      return value.slice(1, -1);
    }
    return value;
  }
}

// 旧的 openclaw.json/extraDirs 管理实现仅保留为 legacy；主路径列表和启停走 OpenClaw RPC，本地 file-backed SKILL.md 仍可直接编辑/删除。
// Legacy openclaw.json/extraDirs management is kept for reference; the main path lists and toggles through OpenClaw RPC while local file-backed SKILL.md files can still be edited/deleted directly.
export class LegacyLocalOpenClawSkillAdapter {
  private readonly clawkeHome: string;
  private readonly managedRoot: string;
  private readonly disabledRoot: string;
  private readonly statePath: string;
  private readonly openClawConfigPath: string;
  private readonly externalRoots: string[];

  constructor(
    clawkeHome = join(homedir(), ".clawke"),
    options: { externalRoots?: string[]; statePath?: string; openClawConfigPath?: string } = {},
  ) {
    this.clawkeHome = clawkeHome;
    this.managedRoot = resolve(clawkeHome, "skills");
    this.disabledRoot = resolve(clawkeHome, "disabled-skills");
    this.statePath = resolve(options.statePath ?? join(clawkeHome, "skills-state.json"));
    this.openClawConfigPath = resolve(
      options.openClawConfigPath ?? join(homedir(), ".openclaw", "openclaw.json"),
    );
    const defaultHome = resolve(join(homedir(), ".clawke"));
    this.externalRoots = options.externalRoots ?? (
      resolve(clawkeHome) === defaultHome
        ? [
            join(homedir(), ".openclaw", "skills"),
            join(homedir(), ".agents", "skills"),
          ]
        : []
    );
  }

  listSkills(): OpenClawManagedSkill[] {
    const byId = new Map<string, OpenClawManagedSkill>();
    const state = this.readState();
    const config = this.readOpenClawConfig();
    for (const root of this.externalRoots) {
      for (const skill of this.scanRoot({
        root,
        enabled: true,
        source: "external",
        sourceLabel: "OpenClaw skills",
        writable: true,
        deletable: true,
      })) {
        byId.set(skill.id, this.applyStateAndConfig(skill, state, config));
      }
    }
    for (const skill of this.scanRoot({
      root: this.managedRoot,
      enabled: true,
      source: "managed",
      sourceLabel: "Clawke skills",
      writable: true,
      deletable: true,
    })) {
      byId.set(skill.id, this.applyStateAndConfig(skill, state, config));
    }
    for (const skill of this.scanRoot({
      root: this.disabledRoot,
      enabled: false,
      source: "managed",
      sourceLabel: "Clawke disabled skills",
      writable: true,
      deletable: true,
    })) {
      byId.set(skill.id, this.applyStateAndConfig(skill, state, config));
    }
    return [...byId.values()].sort((a, b) => a.id.localeCompare(b.id));
  }

  listRuntimeSkills(): Array<{ name: string; description: string }> {
    return this.listSkills()
      .filter((skill) => skill.enabled)
      .map((skill) => ({ name: skill.name, description: skill.description }));
  }

  getSkill(id: string): OpenClawManagedSkill | null {
    this.requireSkillId(id);
    return this.listSkills().find((skill) => skill.id === id) ?? null;
  }

  createSkill(draft: OpenClawSkillDraft): OpenClawManagedSkill {
    const normalized = this.normalizeDraft(draft);
    const id = this.skillId(normalized.category, normalized.name);
    const skillDir = this.safePath(this.managedRoot, normalized.name);
    const disabledDir = this.safePath(this.disabledRoot, normalized.name);
    if (existsSync(skillDir) || existsSync(disabledDir)) {
      throw new Error(`Skill already exists: ${id}`);
    }
    mkdirSync(skillDir, { recursive: true });
    writeFileSync(join(skillDir, "SKILL.md"), this.buildContent(normalized), "utf-8");
    this.recordState(id, normalized, {
      enabled: true,
      path: skillDir,
      originalPath: skillDir,
      disabledPath: disabledDir,
    });
    return this.requireSkill(id);
  }

  updateSkill(id: string, draft: OpenClawSkillDraft): OpenClawManagedSkill {
    const existing = this.requireSkill(id);
    if (!existing.writable) throw new Error(`Skill is not writable: ${id}`);

    const normalized = this.normalizeDraft({
      name: draft.name ?? existing.name,
      category: draft.category ?? existing.category,
      description: draft.description ?? existing.description,
      trigger: draft.trigger ?? existing.trigger,
      body: draft.body ?? draft.content ?? existing.body ?? "",
    });
    const nextId = this.skillId(normalized.category, normalized.name);
    const currentDir = dirname(existing.absolutePath);
    const state = this.readState();
    const saved = state.skills[id];
    const isMoved = saved?.disableMethod === "move" || resolve(existing.root) === this.disabledRoot;
    const targetRoot = isMoved ? this.disabledRoot : this.originalRoot(existing, saved);
    const nextDir = this.safePath(targetRoot, normalized.name);
    if (resolve(currentDir) !== resolve(nextDir)) {
      if (existsSync(nextDir)) throw new Error(`Skill already exists: ${nextId}`);
      mkdirSync(dirname(nextDir), { recursive: true });
      renameSync(currentDir, nextDir);
    }
    writeFileSync(join(nextDir, "SKILL.md"), this.buildContent(normalized), "utf-8");

    if (nextId !== id) delete state.skills[id];
    if (!existing.enabled && !isMoved) {
      this.setOpenClawSkillEnabled(normalized.name, false);
    }
    state.skills[nextId] = {
      skillId: nextId,
      source: existing.source,
      category: normalized.category,
      name: normalized.name,
      enabled: existing.enabled,
      disableMethod: existing.enabled ? undefined : isMoved ? "move" : "config",
      path: nextDir,
      originalPath: this.safePath(this.originalRoot(existing, saved), normalized.name),
      disabledPath: this.safePath(this.disabledRoot, normalized.name),
      disabledAt: existing.enabled ? undefined : state.skills[id]?.disabledAt,
      lastSyncedAt: new Date().toISOString(),
    };
    this.writeState(state);
    return this.requireSkill(nextId);
  }

  deleteSkill(id: string): boolean {
    const existing = this.requireSkill(id);
    if (!existing.deletable) throw new Error(`Skill is not deletable: ${id}`);
    rmSync(dirname(existing.absolutePath), { recursive: true, force: true });
    const state = this.readState();
    delete state.skills[id];
    this.writeState(state);
    return true;
  }

  setEnabled(id: string, enabled: boolean): OpenClawManagedSkill {
    const existing = this.requireSkill(id);
    const state = this.readState();
    const saved = state.skills[id];
    const isMoved = saved?.disableMethod === "move" || resolve(existing.root) === this.disabledRoot;
    const needsConfigSync = saved?.disableMethod === "state";
    if (existing.enabled === enabled && !isMoved && !needsConfigSync) return existing;

    const name = existing.name;
    const originalDir = saved?.originalPath
      ? resolve(saved.originalPath)
      : this.safePath(this.originalRoot(existing, saved), name);
    const disabledDir = saved?.disabledPath
      ? resolve(saved.disabledPath)
      : this.safePath(this.disabledRoot, name);
    if (enabled && isMoved) {
      if (!existsSync(disabledDir)) throw new Error(`Disabled skill not found: ${id}`);
      if (existsSync(originalDir)) throw new Error(`Skill target already exists: ${id}`);
      mkdirSync(dirname(originalDir), { recursive: true });
      renameSync(disabledDir, originalDir);
    }

    this.setOpenClawSkillEnabled(this.openClawSkillKey(existing), enabled);

    state.skills[id] = {
      skillId: id,
      source: existing.source,
      category: existing.category,
      name,
      enabled,
      disableMethod: "config",
      path: enabled && isMoved ? originalDir : dirname(existing.absolutePath),
      originalPath: originalDir,
      disabledPath: disabledDir,
      disabledAt: enabled ? undefined : new Date().toISOString(),
      lastSyncedAt: new Date().toISOString(),
    };
    this.writeState(state);
    return this.requireSkill(id);
  }

  ensureOpenClawExtraDir(): boolean {
    try {
      const config = this.readOpenClawConfig();
      config.skills ??= {};
      config.skills.load ??= {};
      const extraDirs = Array.isArray(config.skills.load.extraDirs)
        ? config.skills.load.extraDirs
        : [];
      if (!extraDirs.includes(this.managedRoot)) {
        extraDirs.push(this.managedRoot);
      }
      config.skills.load.extraDirs = extraDirs;
      config.skills.load.watch ??= true;
      this.writeOpenClawConfig(config);
      return true;
    } catch {
      return false;
    }
  }

  private scanRoot(root: SkillRoot): OpenClawManagedSkill[] {
    const rootPath = resolve(root.root);
    if (!existsSync(rootPath)) return [];
    const skills: OpenClawManagedSkill[] = [];
    for (const file of this.findSkillFiles(rootPath)) {
      try {
        skills.push(this.readSkill(root, file));
      } catch {
        // 跳过单个坏 Skill，避免拖垮整个列表 — Skip one malformed skill instead of failing the whole list.
      }
    }
    return skills;
  }

  private applyStateAndConfig(
    skill: OpenClawManagedSkill,
    state: SkillState,
    config: Record<string, any>,
  ): OpenClawManagedSkill {
    const saved = state.skills[skill.id];
    const configured = config.skills?.entries?.[this.openClawSkillKey(skill)]?.enabled;
    return {
      ...skill,
      enabled: configured === false ? false : configured === true ? true : (saved?.enabled ?? skill.enabled),
      source: saved?.source ?? skill.source,
      sourceLabel: saved?.source === "external" ? "OpenClaw skills" : skill.sourceLabel,
    };
  }

  private originalRoot(skill: OpenClawManagedSkill, saved?: SkillState["skills"][string]): string {
    if (saved?.originalPath) return dirname(resolve(saved.originalPath));
    if (skill.source === "managed") return this.managedRoot;
    if (skill.enabled) return resolve(skill.root);
    return this.managedRoot;
  }

  private openClawSkillKey(skill: OpenClawManagedSkill): string {
    const explicit = skill.frontmatter?.skillKey ?? skill.frontmatter?.["skill-key"];
    return typeof explicit === "string" && explicit.trim() ? explicit.trim() : skill.name;
  }

  private setOpenClawSkillEnabled(skillKey: string, enabled: boolean): void {
    const config = this.readOpenClawConfig();
    config.skills ??= {};
    config.skills.entries ??= {};
    config.skills.entries[skillKey] ??= {};
    config.skills.entries[skillKey].enabled = enabled;
    this.writeOpenClawConfig(config);
  }

  private readOpenClawConfig(): Record<string, any> {
    if (!existsSync(this.openClawConfigPath)) return {};
    try {
      return JSON.parse(readFileSync(this.openClawConfigPath, "utf-8"));
    } catch {
      return {};
    }
  }

  private writeOpenClawConfig(config: Record<string, any>): void {
    mkdirSync(dirname(this.openClawConfigPath), { recursive: true });
    writeFileSync(this.openClawConfigPath, `${JSON.stringify(config, null, 2)}\n`, "utf-8");
  }

  private findSkillFiles(root: string, depth = 0): string[] {
    if (depth > 4) return [];
    let entries: Dirent[];
    try {
      entries = readdirSync(root, { withFileTypes: true }) as Dirent[];
    } catch {
      return [];
    }
    const files: string[] = [];
    for (const entry of entries) {
      if (entry.name.startsWith(".")) continue;
      const next = join(root, entry.name);
      if (entry.isFile() && entry.name === "SKILL.md") {
        files.push(next);
      } else if (entry.isDirectory()) {
        files.push(...this.findSkillFiles(next, depth + 1));
      }
    }
    return files;
  }

  private readSkill(root: SkillRoot, skillMd: string): OpenClawManagedSkill {
    const absolutePath = resolve(skillMd);
    const content = readFileSync(absolutePath, "utf-8");
    const parsed = this.parseContent(content);
    const relDir = relative(resolve(root.root), dirname(absolutePath));
    const parts = relDir.split(sep).filter(Boolean);
    const fallbackName = parts[parts.length - 1] || "skill";
    const fallbackCategory = parts.length > 1 ? parts[parts.length - 2] : "general";
    const name = String(parsed.frontmatter.name || fallbackName).trim();
    const category = String(parsed.frontmatter.category || fallbackCategory).trim();
    return {
      id: this.skillId(category, name),
      name,
      description: String(parsed.frontmatter.description || name).trim(),
      category,
      trigger: parsed.frontmatter.trigger ? String(parsed.frontmatter.trigger) : undefined,
      enabled: root.enabled,
      source: root.source,
      sourceLabel: root.sourceLabel,
      writable: root.writable,
      deletable: root.deletable,
      path: relative(resolve(root.root), absolutePath),
      absolutePath,
      root: resolve(root.root),
      updatedAt: statSync(absolutePath).mtimeMs,
      hasConflict: false,
      content,
      body: parsed.body,
      frontmatter: parsed.frontmatter,
    };
  }

  private parseContent(content: string): { frontmatter: Record<string, string>; body: string } {
    const match = content.match(/^---\s*\r?\n([\s\S]*?)\r?\n---\s*\r?\n?/);
    if (!match) return { frontmatter: {}, body: content };
    const frontmatter: Record<string, string> = {};
    for (const line of match[1].split(/\r?\n/)) {
      const pair = line.match(/^([A-Za-z0-9_-]+):\s*(.*)$/);
      if (!pair) continue;
      frontmatter[pair[1]] = this.unquote(pair[2].trim());
    }
    return { frontmatter, body: content.slice(match[0].length) };
  }

  private normalizeDraft(draft: OpenClawSkillDraft): Required<Pick<OpenClawSkillDraft, "name" | "category" | "description" | "body">> & { trigger?: string } {
    const name = (draft.name || "").trim();
    const category = (draft.category || "general").trim();
    const description = (draft.description || "").trim();
    this.requireSafeSegment(name, "skill name");
    this.requireSafeSegment(category, "skill category");
    if (!description) throw new Error("description is required");
    return {
      name,
      category,
      description,
      trigger: draft.trigger?.trim() || undefined,
      body: draft.body ?? draft.content ?? "",
    };
  }

  private buildContent(draft: Required<Pick<OpenClawSkillDraft, "name" | "category" | "description" | "body">> & { trigger?: string }): string {
    const frontmatter = [
      "---",
      `name: ${this.yamlValue(draft.name)}`,
      `category: ${this.yamlValue(draft.category)}`,
      `description: ${this.yamlValue(draft.description)}`,
      ...(draft.trigger ? [`trigger: ${this.yamlValue(draft.trigger)}`] : []),
      "---",
      "",
    ].join("\n");
    return `${frontmatter}${draft.body || ""}`;
  }

  private recordState(id: string, draft: { name: string; category: string }, fields: {
    enabled: boolean;
    path: string;
    originalPath: string;
    disabledPath: string;
  }): void {
    const state = this.readState();
    state.skills[id] = {
      skillId: id,
      source: "managed",
      category: draft.category,
      name: draft.name,
      enabled: fields.enabled,
      path: fields.path,
      originalPath: fields.originalPath,
      disabledPath: fields.disabledPath,
      lastSyncedAt: new Date().toISOString(),
    };
    this.writeState(state);
  }

  private readState(): SkillState {
    if (!existsSync(this.statePath)) return { version: 1, skills: {} };
    try {
      const parsed = JSON.parse(readFileSync(this.statePath, "utf-8")) as Partial<SkillState>;
      return {
        version: 1,
        skills: parsed.skills && typeof parsed.skills === "object" ? parsed.skills : {},
      };
    } catch {
      return { version: 1, skills: {} };
    }
  }

  private writeState(state: SkillState): void {
    mkdirSync(dirname(this.statePath), { recursive: true });
    writeFileSync(this.statePath, `${JSON.stringify(state, null, 2)}\n`, "utf-8");
  }

  private requireSkill(id: string): OpenClawManagedSkill {
    const skill = this.getSkill(id);
    if (!skill) throw new Error(`Skill not found: ${id}`);
    return skill;
  }

  private skillId(category: string, name: string): string {
    this.requireSafeSegment(category, "skill category");
    this.requireSafeSegment(name, "skill name");
    return `${category}/${name}`;
  }

  private requireSkillId(id: string): void {
    const parts = id.split("/");
    if (parts.length !== 2) throw new Error(`Invalid skill id: ${id}`);
    this.requireSafeSegment(parts[0], "skill category");
    this.requireSafeSegment(parts[1], "skill name");
  }

  private safePath(root: string, segment: string): string {
    this.requireSafeSegment(segment, "skill name");
    const resolvedRoot = resolve(root);
    const target = resolve(resolvedRoot, segment);
    if (target !== resolvedRoot && !target.startsWith(`${resolvedRoot}${sep}`)) {
      throw new Error(`Invalid path segment: ${segment}`);
    }
    return target;
  }

  private requireSafeSegment(value: string, label: string): void {
    if (!SAFE_SEGMENT.test(value) || value === "." || value === "..") {
      throw new Error(`Invalid ${label}: ${value}`);
    }
  }

  private yamlValue(value: string): string {
    return value.replace(/\r?\n/g, " ").trim();
  }

  private unquote(value: string): string {
    if ((value.startsWith('"') && value.endsWith('"')) || (value.startsWith("'") && value.endsWith("'"))) {
      return value.slice(1, -1);
    }
    return value;
  }
}
