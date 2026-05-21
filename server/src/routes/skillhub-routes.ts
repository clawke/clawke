import type { Request, Response } from 'express';
import { randomUUID } from 'node:crypto';
import type { GatewayInfo } from '../types/gateways.js';
import type { SkillGatewayRequest, SkillGatewayResponse, SkillHubInstallPackage } from '../types/skills.js';
import { loadConfig } from '../config.js';
import { sendSkillGatewayRequest, SkillGatewayError } from '../upstream/skill-gateway-client.js';
import {
  startManagedSkillHubInstall,
  type ManagedSkillHubInstallResult,
} from '../services/skillhub-install-runner.js';

const DEFAULT_SKILLHUB_API_BASE_URL = 'https://api.clawke.ai';
const SKILLHUB_SKILLS_PATH = '/api/skillhub/v1/skills.json';
const SKILLHUB_SKILL_PATH = '/api/skillhub/v1/skill.json';

interface SkillHubRoutesDeps {
  loadConfig?: typeof loadConfig;
  getConnectedAccountIds?: () => string[];
  getConnectedGateways?: () => GatewayInfo[];
  sendSkillRequest?: (payload: SkillGatewayRequest) => Promise<SkillGatewayResponse>;
  startManagedSkillHubInstall?: (input: ManagedInstallStartInput) => Promise<ManagedSkillHubInstallResult> | ManagedSkillHubInstallResult;
}

type SkillHubInstallMode = 'auto' | 'managed' | 'gateway_native';

interface ManagedInstallStartInput {
  installId: string;
  installMode: 'managed';
  installPackage: SkillHubInstallPackage;
  refreshGateways?: (slug: string) => Promise<void>;
}

let deps: SkillHubRoutesDeps = {};

export function initSkillHubRoutes(nextDeps: SkillHubRoutesDeps = {}): void {
  deps = nextDeps;
}

export async function getSkillHubConfig(_req: Request, res: Response): Promise<void> {
  const config = (deps.loadConfig || loadConfig)();
  res.json({
    provider: 'nirvana',
    apiBaseUrl: normalizeBaseUrl(config.relay?.apiBaseUrl),
    skillsPath: SKILLHUB_SKILLS_PATH,
    skillPath: SKILLHUB_SKILL_PATH,
  });
}

export async function installSkillHubSkill(req: Request, res: Response): Promise<void> {
  const installPackage = packageFromBody(req.body);
  const validation = validatePackage(installPackage);
  if (validation) {
    sendJsonResultError(res, 400, 'validation_error', validation);
    return;
  }

  const installId = `skillhub_${randomUUID()}`;
  const installMode = installModeFromBody(req.body);

  if (installMode !== 'gateway_native') {
    try {
      const starter = deps.startManagedSkillHubInstall || startManagedSkillHubInstall;
      const response = await starter({
        installId,
        installMode: 'managed',
        installPackage,
        refreshGateways: async () => {
          await refreshConnectedSkillGateways();
        },
      });
      sendInstallAccepted(res, response, {
        installId,
        installMode: 'managed',
        slug: installPackage.slug,
      });
      return;
    } catch (err) {
      const message = err instanceof Error ? err.message : String(err);
      sendJsonResultError(res, 500, 'managed_install_failed', message);
      return;
    }
  }

  await installSkillHubSkillViaGateway(req, res, installPackage, installId);
}

async function installSkillHubSkillViaGateway(
  req: Request,
  res: Response,
  installPackage: SkillHubInstallPackage,
  installId: string,
): Promise<void> {
  const accountId = resolveFallbackAccountId(req, res, installPackage);
  if (!accountId) return;

  try {
    const sender = deps.sendSkillRequest || sendSkillGatewayRequest;
    const response = await sender({
      type: 'skillhub_install',
      request_id: installId,
      install_id: installId,
      account_id: accountId,
      install_mode: 'gateway_native',
      package: installPackage,
    });
    if (response.ok === false || response.error) {
      sendJsonResultError(
        res,
        responseStatus(response),
        response.error || 'gateway_error',
        response.message || response.error || 'Gateway SkillHub install failed.',
        response.details,
      );
      return;
    }
    const accepted = response.status === 'accepted' || response.installed === false;
    res.status(accepted ? 202 : 200).json({
      success: true,
      value: {
        installId,
        installed: accepted ? false : response.installed !== false,
        status: response.status || (accepted ? 'accepted' : 'installed'),
        message: response.message || (accepted ? '安装任务已提交' : '安装完成'),
        accountId,
        installMode: 'gateway_native',
        slug: installPackage.slug,
        ...(response.skill === undefined ? {} : { skill: response.skill }),
      },
    });
  } catch (err) {
    if (err instanceof SkillGatewayError) {
      sendJsonResultError(res, err.status, err.code, err.message, err.details);
      return;
    }
    const message = err instanceof Error ? err.message : String(err);
    sendJsonResultError(res, 500, 'internal_error', message);
  }
}

function sendInstallAccepted(
  res: Response,
  response: ManagedSkillHubInstallResult,
  context: { installId: string; installMode: 'managed'; slug: string },
): void {
  const accepted = response.status === 'accepted' || response.installed === false;
  res.status(accepted ? 202 : 200).json({
    success: true,
    value: {
      installId: context.installId,
      installed: accepted ? false : response.installed !== false,
      status: response.status || (accepted ? 'accepted' : 'installed'),
      message: response.message || (accepted ? '安装任务已提交' : '安装完成'),
      installMode: context.installMode,
      slug: context.slug,
      ...(response.skill === undefined ? {} : { skill: response.skill }),
    },
  });
}

function normalizeBaseUrl(baseUrl: string | undefined): string {
  const value = (baseUrl || DEFAULT_SKILLHUB_API_BASE_URL).trim();
  return value.endsWith('/') ? value.slice(0, -1) : value;
}

function resolveAccountId(req: Request, res: Response, installPackage: SkillHubInstallPackage): string | null {
  const explicit = stringValue(req.body?.gateway_id)
    || stringValue(req.body?.account_id)
    || singleQueryValue(req.query.gateway_id)
    || singleQueryValue(req.query.account_id);
  if (explicit) return explicit;

  const requestedGatewayType = stringValue(req.body?.gatewayType) || inferredGatewayType(installPackage);
  const byGatewayType = resolveAccountIdByGatewayType(requestedGatewayType);
  if (byGatewayType) return byGatewayType;

  const connected = deps.getConnectedAccountIds?.() || [];
  if (connected.length === 1) return connected[0];

  sendJsonResultError(res, 400, 'account_required', 'gateway_id is required when gateway selection is ambiguous.');
  return null;
}

function resolveFallbackAccountId(req: Request, res: Response, installPackage: SkillHubInstallPackage): string | null {
  const explicit = explicitAccountId(req);
  if (explicit) return explicit;

  const requestedGatewayType = stringValue(req.body?.gatewayType) || inferredGatewayType(installPackage);
  const byGatewayType = resolveAccountIdByGatewayType(requestedGatewayType);
  if (byGatewayType) return byGatewayType;

  const connectedGateways = deps.getConnectedGateways?.() || [];
  const skillGateways = connectedGateways.filter((gateway) =>
    gateway.status === 'online' && gateway.capabilities.includes('skills'));
  if (skillGateways.length === 1) return skillGateways[0].gateway_id;
  if (skillGateways.length > 1) {
    sendJsonResultError(res, 409, 'fallback_gateway_required', '请选择要安装到的 Gateway', {
      gateways: skillGateways.map((gateway) => ({
        gatewayId: gateway.gateway_id,
        label: gateway.display_name || gateway.gateway_id,
        gatewayType: gateway.gateway_type,
      })),
    });
    return null;
  }

  const connected = deps.getConnectedAccountIds?.() || [];
  if (connected.length === 1) return connected[0];

  sendJsonResultError(res, 400, 'account_required', 'gateway_id is required when gateway native install is needed.');
  return null;
}

async function refreshConnectedSkillGateways(): Promise<void> {
  const sender = deps.sendSkillRequest || sendSkillGatewayRequest;
  const skillGateways = (deps.getConnectedGateways?.() || [])
    .filter((gateway) => gateway.status === 'online' && gateway.capabilities.includes('skills'));
  await Promise.allSettled(
    skillGateways.map((gateway) => sender({
      type: 'skill_list',
      account_id: gateway.gateway_id,
    })),
  );
}

function explicitAccountId(req: Request): string | undefined {
  return stringValue(req.body?.gateway_id)
    || stringValue(req.body?.account_id)
    || singleQueryValue(req.query.gateway_id)
    || singleQueryValue(req.query.account_id);
}

function packageFromBody(body: Record<string, unknown> | undefined): SkillHubInstallPackage {
  return {
    ...(stringValue(body?.id) ? { id: stringValue(body?.id) } : {}),
    slug: stringValue(body?.slug) || '',
    ...(stringValue(body?.name) ? { name: stringValue(body?.name) } : {}),
    ...(stringValue(body?.source) ? { source: stringValue(body?.source) } : {}),
    ...(stringValue(body?.sourceOwner) ? { sourceOwner: stringValue(body?.sourceOwner) } : {}),
    ...(stringValue(body?.version) ? { version: stringValue(body?.version) } : {}),
    ...(stringValue(body?.packageUrl) ? { packageUrl: stringValue(body?.packageUrl) } : {}),
    ...(stringValue(body?.packageSha256) ? { packageSha256: stringValue(body?.packageSha256) } : {}),
    ...(stringValue(body?.packageType) ? { packageType: stringValue(body?.packageType) } : {}),
    ...(stringValue(body?.gatewayType) ? { gatewayType: stringValue(body?.gatewayType) } : {}),
    ...(stringListValue(body?.compatibleGateways).length
      ? { compatibleGateways: stringListValue(body?.compatibleGateways) }
      : {}),
  };
}

function installModeFromBody(body: Record<string, unknown> | undefined): SkillHubInstallMode {
  const value = stringValue(body?.installMode) || stringValue(body?.install_mode) || 'auto';
  return value === 'managed' || value === 'gateway_native' ? value : 'auto';
}

function inferredGatewayType(installPackage: SkillHubInstallPackage): string | undefined {
  const types = new Set((installPackage.compatibleGateways || [])
    .map((item) => item.trim().toLowerCase())
    .filter(Boolean));
  return types.size === 1 ? [...types][0] : undefined;
}

function resolveAccountIdByGatewayType(gatewayType: string | undefined): string | null {
  if (!gatewayType) return null;
  const expected = gatewayType.trim().toLowerCase();
  const matches = (deps.getConnectedGateways?.() || [])
    .filter((item) => item.gateway_type.trim().toLowerCase() === expected);
  if (matches.length === 1) return matches[0].gateway_id;
  return null;
}

function validatePackage(installPackage: SkillHubInstallPackage): string | null {
  if (!installPackage.slug) return 'slug is required.';
  const source = installPackage.source?.trim().toLowerCase();
  if (!source || source === 'clawhub') return null;
  for (const key of ['id', 'name', 'version', 'packageUrl', 'packageSha256', 'packageType'] as const) {
    if (!installPackage[key]) return `${key} is required.`;
  }
  return null;
}

function responseStatus(response: SkillGatewayResponse): number {
  const maybeStatus = (response as SkillGatewayResponse & { status?: unknown }).status;
  if (typeof maybeStatus === 'number') return maybeStatus;
  return 502;
}

function singleQueryValue(value: unknown): string | undefined {
  if (Array.isArray(value)) {
    return typeof value[0] === 'string' && value[0].trim() ? value[0] : undefined;
  }
  return typeof value === 'string' && value.trim() ? value : undefined;
}

function stringValue(value: unknown): string | undefined {
  return typeof value === 'string' && value.trim() ? value.trim() : undefined;
}

function stringListValue(value: unknown): string[] {
  if (!Array.isArray(value)) return [];
  return value
    .map((item) => stringValue(item))
    .filter((item): item is string => Boolean(item));
}

function sendJsonResultError(res: Response, status: number, actionError: string, message: string, details?: unknown): void {
  res.status(status).json({
    success: false,
    actionError,
    message,
    ...(details === undefined ? {} : { details }),
  });
}
