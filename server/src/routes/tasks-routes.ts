import type { Request, Response } from 'express';
import type { TaskDraft, TaskGatewayRequest, TaskGatewayResponse } from '../types/tasks.js';
import { sendTaskGatewayRequest, TaskGatewayError } from '../upstream/task-gateway-client.js';

interface TasksRouteDeps {
  getConnectedAccountIds: () => string[];
  sendTaskRequest?: (payload: TaskGatewayRequest) => Promise<TaskGatewayResponse>;
}

let deps: TasksRouteDeps | null = null;

export function initTasksRoutes(nextDeps: TasksRouteDeps): void {
  deps = nextDeps;
}

export async function listTasks(req: Request, res: Response): Promise<void> {
  const accountId = resolveAccountId(req, res);
  if (!accountId) return;
  await respond(res, { type: 'task_list', account_id: accountId }, (response) => ({
    tasks: response.tasks || [],
  }));
}

export async function getTask(req: Request, res: Response): Promise<void> {
  const accountId = resolveAccountId(req, res);
  if (!accountId) return;
  await respond(res, { type: 'task_get', account_id: accountId, task_id: firstString(req.params.taskId) }, (response) => ({
    task: response.task,
  }));
}

export async function createTask(req: Request, res: Response): Promise<void> {
  const draft = req.body as TaskDraft;
  const validation = validateDraft(draft);
  if (validation) {
    sendHttpError(res, 400, 'validation_error', validation);
    return;
  }

  await respond(res, { type: 'task_create', account_id: draft.account_id, task: draft }, (response) => ({
    task: response.task,
  }), 201);
}

export async function updateTask(req: Request, res: Response): Promise<void> {
  const accountId = resolveAccountId(req, res);
  if (!accountId) return;
  await respond(res, {
    type: 'task_update',
    account_id: accountId,
    task_id: firstString(req.params.taskId),
    patch: req.body || {},
  }, (response) => ({
    task: response.task,
  }));
}

export async function deleteTask(req: Request, res: Response): Promise<void> {
  const accountId = resolveAccountId(req, res);
  if (!accountId) return;
  await respond(res, { type: 'task_delete', account_id: accountId, task_id: firstString(req.params.taskId) }, () => ({
    ok: true,
  }));
}

export async function setTaskEnabled(req: Request, res: Response): Promise<void> {
  const accountId = resolveAccountId(req, res);
  if (!accountId) return;
  const validation = validateEnabled(req.body?.enabled);
  if (validation) {
    sendHttpError(res, 400, 'validation_error', validation);
    return;
  }
  await respond(res, {
    type: 'task_set_enabled',
    account_id: accountId,
    task_id: firstString(req.params.taskId),
    enabled: req.body.enabled,
  }, (response) => ({
    ok: true,
    task: response.task,
  }));
}

export async function runTask(req: Request, res: Response): Promise<void> {
  const accountId = resolveAccountId(req, res);
  if (!accountId) return;
  await respond(res, { type: 'task_run', account_id: accountId, task_id: firstString(req.params.taskId) }, (response) => ({
    ok: true,
    run: response.runs?.[0] || null,
  }));
}

export async function listTaskRuns(req: Request, res: Response): Promise<void> {
  const accountId = resolveAccountId(req, res);
  if (!accountId) return;
  await respond(res, { type: 'task_runs', account_id: accountId, task_id: firstString(req.params.taskId) }, (response) => ({
    runs: response.runs || [],
  }));
}

export async function getTaskRunOutput(req: Request, res: Response): Promise<void> {
  const accountId = resolveAccountId(req, res);
  if (!accountId) return;
  await respond(res, {
    type: 'task_output',
    account_id: accountId,
    task_id: firstString(req.params.taskId),
    run_id: firstString(req.params.runId),
  }, (response) => ({
    output: response.output || '',
  }));
}

function resolveAccountId(req: Request, res: Response): string | null {
  const explicit = firstString(req.query.account_id) || firstString(req.body?.account_id);
  if (explicit) return explicit;

  const connected = deps?.getConnectedAccountIds() || [];
  if (connected.length === 1) return connected[0];

  sendHttpError(res, 400, 'account_required', 'account_id is required when account selection is ambiguous.');
  return null;
}

function validateDraft(draft: TaskDraft | undefined): string | null {
  if (!draft?.account_id) return 'account_id is required.';
  if (typeof draft.schedule !== 'string' || !draft.schedule.trim()) return 'schedule is required.';
  if (typeof draft.prompt !== 'string' || !draft.prompt.trim()) return 'prompt is required.';
  return null;
}

function validateEnabled(enabled: unknown): string | null {
  if (typeof enabled !== 'boolean') return 'enabled must be a boolean.';
  return null;
}

async function respond(
  res: Response,
  request: TaskGatewayRequest,
  map: (response: TaskGatewayResponse) => Record<string, unknown>,
  status = 200,
): Promise<void> {
  try {
    const sender = deps?.sendTaskRequest || sendTaskGatewayRequest;
    const response = await sender(request);
    if (response.ok === false || response.error) {
      sendGatewayResponseError(res, response);
      return;
    }
    res.status(status).json(map(response));
  } catch (err) {
    sendError(res, err);
  }
}

function sendGatewayResponseError(res: Response, response: TaskGatewayResponse): void {
  const error = response.error || 'gateway_error';
  const status = responseStatus(response, error);
  res.status(status).json({
    error,
    message: response.message || error,
    details: response.details,
  });
}

function responseStatus(response: TaskGatewayResponse, error: string): number {
  const maybeStatus = (response as TaskGatewayResponse & { status?: unknown }).status;
  if (typeof maybeStatus === 'number') return maybeStatus;
  if (error === 'tasks_unsupported') return 501;
  return 502;
}

function sendError(res: Response, err: unknown): void {
  if (err instanceof TaskGatewayError) {
    res.status(err.status).json({
      error: err.code,
      message: err.message,
      details: err.details,
    });
    return;
  }

  const message = err instanceof Error ? err.message : String(err);
  res.status(500).json({ error: 'internal_error', message });
}

function sendHttpError(res: Response, status: number, error: string, message: string): void {
  res.status(status).json({ error, message });
}

function firstString(value: unknown): string {
  if (typeof value === 'string') return value;
  if (Array.isArray(value) && typeof value[0] === 'string') return value[0];
  return '';
}
