import { mkdir, readFile, readdir, rename, rm, writeFile } from "node:fs/promises";
import { existsSync } from "node:fs";
import { randomUUID } from "node:crypto";
import { join, resolve } from "node:path";
import { homedir } from "node:os";

export type OpenClawTaskStatus = "active" | "paused";
export type OpenClawRunStatus = "running" | "success" | "failed" | "cancelled";

export interface OpenClawTaskDraft {
  name?: string;
  schedule: string;
  prompt: string;
  enabled?: boolean;
  skills?: string[];
  deliver?: string;
}

export interface OpenClawTaskPatch {
  name?: string;
  schedule?: string;
  prompt?: string;
  enabled?: boolean;
  skills?: string[];
  deliver?: string;
}

export interface OpenClawManagedTask {
  id: string;
  account_id: string;
  agent: "openclaw";
  name: string;
  schedule: string;
  prompt: string;
  enabled: boolean;
  status: OpenClawTaskStatus;
  skills: string[];
  deliver?: string;
  created_at: string;
  updated_at: string;
}

export interface OpenClawTaskRun {
  id: string;
  task_id: string;
  started_at: string;
  status: OpenClawRunStatus;
  output_preview?: string;
}

export interface OpenClawTaskOutput {
  task_id: string;
  run_id: string;
  created_at: string;
  text: string;
}

const DEFAULT_ROOT = join(homedir(), ".openclaw", "clawke-tasks");
const SAFE_SEGMENT = /^[A-Za-z0-9_-]+$/;

export class OpenClawTaskAdapter {
  private lastTimestamp = 0;

  constructor(private readonly root = DEFAULT_ROOT) {}

  async listTasks(accountId: string): Promise<OpenClawManagedTask[]> {
    const dir = this.accountDir(accountId);
    if (!existsSync(dir)) return [];

    const entries = await readdir(dir, { withFileTypes: true });
    const tasks = await Promise.all(
      entries
        .filter((entry) => entry.isDirectory())
        .map((entry) => this.readTaskFile(join(dir, entry.name, "task.json"))),
    );
    return tasks.filter((task): task is OpenClawManagedTask => task !== null)
      .sort((a, b) => a.created_at.localeCompare(b.created_at));
  }

  async getTask(accountId: string, taskId: string): Promise<OpenClawManagedTask | null> {
    return this.readTaskFile(this.taskFile(accountId, taskId));
  }

  async createTask(accountId: string, draft: OpenClawTaskDraft): Promise<OpenClawManagedTask> {
    this.requireSafeSegment(accountId, "account id");
    const id = this.newId("task");
    const now = this.now();
    const enabled = draft.enabled ?? true;
    const task: OpenClawManagedTask = {
      id,
      account_id: accountId,
      agent: "openclaw",
      name: draft.name?.trim() || "Untitled task",
      schedule: draft.schedule,
      prompt: draft.prompt,
      enabled,
      status: enabled ? "active" : "paused",
      skills: draft.skills ?? [],
      deliver: draft.deliver,
      created_at: now,
      updated_at: now,
    };
    await this.writeJson(this.taskFile(accountId, id), task);
    return task;
  }

  async updateTask(accountId: string, taskId: string, patch: OpenClawTaskPatch): Promise<OpenClawManagedTask> {
    const existing = await this.requireTask(accountId, taskId);
    const enabled = patch.enabled ?? existing.enabled;
    const updated: OpenClawManagedTask = {
      ...existing,
      ...this.cleanPatch(patch),
      enabled,
      status: enabled ? "active" : "paused",
      updated_at: this.now(),
    };
    await this.writeJson(this.taskFile(accountId, taskId), updated);
    return updated;
  }

  async deleteTask(accountId: string, taskId: string): Promise<boolean> {
    const file = this.taskFile(accountId, taskId);
    if (!existsSync(file)) return false;
    await rm(this.taskDir(accountId, taskId), { recursive: true, force: true });
    await rm(this.runDir(taskId), { recursive: true, force: true });
    return true;
  }

  async setEnabled(accountId: string, taskId: string, enabled: boolean): Promise<OpenClawManagedTask> {
    return this.updateTask(accountId, taskId, { enabled });
  }

  async runTask(accountId: string, taskId: string): Promise<OpenClawTaskRun> {
    const task = await this.requireTask(accountId, taskId);
    const runId = this.newId("run");
    const now = this.now();
    const text = [
      `Task was triggered from Clawke at ${now}.`,
      `Task: ${task.name}`,
      "OpenClaw gateway recorded this trigger; Clawke Server did not execute the prompt.",
    ].join("\n");
    const run: OpenClawTaskRun = {
      id: runId,
      task_id: taskId,
      started_at: now,
      status: "running",
      output_preview: "Task was triggered from Clawke.",
    };
    await this.writeJson(this.runFile(taskId, runId), run);
    await this.writeJson(this.outputFile(taskId, runId), {
      task_id: taskId,
      run_id: runId,
      created_at: now,
      text,
    } satisfies OpenClawTaskOutput);
    return run;
  }

  async listRuns(taskId: string): Promise<OpenClawTaskRun[]> {
    const dir = this.runDir(taskId);
    if (!existsSync(dir)) return [];

    const entries = await readdir(dir, { withFileTypes: true });
    const runs = await Promise.all(
      entries
        .filter((entry) => entry.isDirectory())
        .map((entry) => this.readRunFile(join(dir, entry.name, "run.json"))),
    );
    return runs.filter((run): run is OpenClawTaskRun => run !== null)
      .sort((a, b) => b.started_at.localeCompare(a.started_at));
  }

  async getOutput(taskId: string, runId: string): Promise<string | null> {
    const output = await this.readOutputFile(this.outputFile(taskId, runId));
    return output?.text ?? null;
  }

  private async requireTask(accountId: string, taskId: string): Promise<OpenClawManagedTask> {
    const task = await this.getTask(accountId, taskId);
    if (!task) throw new Error(`Task not found: ${taskId}`);
    return task;
  }

  private cleanPatch(patch: OpenClawTaskPatch): OpenClawTaskPatch {
    const cleaned: OpenClawTaskPatch = {};
    if (patch.name !== undefined) cleaned.name = patch.name.trim() || "Untitled task";
    if (patch.schedule !== undefined) cleaned.schedule = patch.schedule;
    if (patch.prompt !== undefined) cleaned.prompt = patch.prompt;
    if (patch.skills !== undefined) cleaned.skills = patch.skills;
    if (patch.deliver !== undefined) cleaned.deliver = patch.deliver;
    return cleaned;
  }

  private async readTaskFile(file: string): Promise<OpenClawManagedTask | null> {
    return this.readJson<OpenClawManagedTask>(file);
  }

  private async readRunFile(file: string): Promise<OpenClawTaskRun | null> {
    return this.readJson<OpenClawTaskRun>(file);
  }

  private async readOutputFile(file: string): Promise<OpenClawTaskOutput | null> {
    return this.readJson<OpenClawTaskOutput>(file);
  }

  private async readJson<T>(file: string): Promise<T | null> {
    if (!existsSync(file)) return null;
    try {
      return JSON.parse(await readFile(file, "utf-8")) as T;
    } catch {
      return null;
    }
  }

  private async writeJson(file: string, value: unknown): Promise<void> {
    const dir = resolve(file, "..");
    await mkdir(dir, { recursive: true });
    const tempFile = join(dir, `.${this.newId("tmp")}.json`);
    await writeFile(tempFile, `${JSON.stringify(value, null, 2)}\n`, "utf-8");
    await rename(tempFile, file);
  }

  private accountDir(accountId: string): string {
    return this.safePath("account id", accountId, "accounts", accountId);
  }

  private taskDir(accountId: string, taskId: string): string {
    return this.safePath("task id", taskId, "accounts", accountId, taskId);
  }

  private taskFile(accountId: string, taskId: string): string {
    return join(this.taskDir(accountId, taskId), "task.json");
  }

  private runDir(taskId: string): string {
    return this.safePath("task id", taskId, "runs", taskId);
  }

  private runFile(taskId: string, runId: string): string {
    return join(this.safePath("run id", runId, "runs", taskId, runId), "run.json");
  }

  private outputFile(taskId: string, runId: string): string {
    return join(this.safePath("run id", runId, "runs", taskId, runId), "output.json");
  }

  private safePath(label: string, segmentToCheck: string, ...segments: string[]): string {
    this.requireSafeSegment(segmentToCheck, label);
    for (const segment of segments) {
      this.requireSafeSegment(segment, segment === segmentToCheck ? label : "path segment");
    }
    const root = resolve(this.root);
    const target = resolve(root, ...segments);
    if (target !== root && !target.startsWith(`${root}/`)) {
      throw new Error(`Invalid ${label}: ${segmentToCheck}`);
    }
    return target;
  }

  private requireSafeSegment(value: string, label: string): void {
    if (!SAFE_SEGMENT.test(value)) {
      throw new Error(`Invalid ${label}: ${value}`);
    }
  }

  private newId(prefix: string): string {
    return `${prefix}_${randomUUID().replace(/-/g, "")}`;
  }

  private now(): string {
    const current = Date.now();
    const next = current <= this.lastTimestamp ? this.lastTimestamp + 1 : current;
    this.lastTimestamp = next;
    return new Date(next).toISOString();
  }
}
