/**
 * sync handler
 */
import type { HandlerContext } from '../event-registry.js';
import type { CupV2Handler } from '../protocol/cup-v2-handler.js';

interface VersionCheckerLike {
  checkVersion(appVersion: string, platform?: string, arch?: string): Record<string, unknown> | null;
}

export function createSyncHandler(
  cupHandler: CupV2Handler,
  versionChecker: VersionCheckerLike,
) {
  return (ctx: HandlerContext) => {
    const syncResp = cupHandler.handleSync(ctx.payload);
    ctx.respond(syncResp);

    // 版本检查
    const data = ctx.payload.data as Record<string, unknown> | undefined;
    const appVersion = data?.app_version as string | undefined;
    if (appVersion) {
      const upgradeMsg = versionChecker.checkVersion(
        appVersion,
        data?.platform as string | undefined,
        data?.arch as string | undefined,
      );
      if (upgradeMsg) {
        ctx.respond(upgradeMsg);
        console.log(`[Server] Upgrade available for client v${appVersion}`);
      }
    }
  };
}
