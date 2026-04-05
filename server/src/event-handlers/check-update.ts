/**
 * check-update handler
 */
import type { HandlerContext } from '../event-registry.js';

interface VersionCheckerLike {
  checkVersion(appVersion: string, platform?: string, arch?: string): Record<string, unknown> | null;
}

export function createCheckUpdateHandler(versionChecker: VersionCheckerLike) {
  return (ctx: HandlerContext) => {
    const data = ctx.payload.data as Record<string, unknown> | undefined;
    const ver = data?.app_version as string | undefined;
    const plat = data?.platform as string | undefined;
    const ar = data?.arch as string | undefined;

    const result = versionChecker.checkVersion(ver || '', plat, ar);
    ctx.respond(result || {
      payload_type: 'system_status',
      status: 'up_to_date',
      upgrade: 0,
    });
  };
}
