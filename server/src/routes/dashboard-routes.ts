import type { Request, Response } from 'express';

interface DashboardUsageDeps {
  getUsageDashboard: (gatewayId?: string) => Record<string, unknown>;
}

let deps: DashboardUsageDeps | null = null;

export function initDashboardRoutes(nextDeps: DashboardUsageDeps): void {
  deps = nextDeps;
}

export function getDashboardUsage(req: Request, res: Response): void {
  if (!deps) {
    res.status(503).json({
      error: 'dashboard_unavailable',
      message: 'Dashboard usage service is not initialized.',
    });
    return;
  }

  const gatewayId = firstString(req.query.gateway_id) || firstString(req.query.account_id) || '';
  res.json(deps.getUsageDashboard(gatewayId));
}

function firstString(value: unknown): string | null {
  if (typeof value === 'string') return value;
  if (Array.isArray(value)) return firstString(value[0]);
  return null;
}
