import type { OpenClawSkillHubInstallPackage } from "./skill-adapter.ts";

export type SkillHubInstallMessage = {
  type: string;
  request_id?: string;
  install_id?: string;
  account_id?: string;
  package?: OpenClawSkillHubInstallPackage;
};

export type SkillHubInstallAdapter = {
  installSkillHubPackage(installPackage: OpenClawSkillHubInstallPackage): Promise<unknown>;
};

type SkillHubInstallStatusSender = (payload: Record<string, unknown>) => void;

function installIdFor(msg: SkillHubInstallMessage): string {
  return msg.install_id || msg.request_id || "";
}

export function skillHubInstallAcceptedResponse(msg: SkillHubInstallMessage): Record<string, unknown> {
  const installId = installIdFor(msg);
  return {
    type: "skillhub_install_response",
    request_id: msg.request_id,
    install_id: installId,
    ok: true,
    installed: false,
    status: "accepted",
    message: "安装任务已提交",
  };
}

export async function runSkillHubInstallJob(
  adapter: SkillHubInstallAdapter,
  msg: SkillHubInstallMessage,
  accountId: string,
  send: SkillHubInstallStatusSender,
): Promise<void> {
  const installId = installIdFor(msg);
  const base = {
    type: "skillhub_install_status",
    request_id: msg.request_id,
    install_id: installId,
    account_id: accountId,
  };

  try {
    const installPackage = requireSkillHubPackage(msg);
    const installBase = {
      ...base,
      slug: installPackage.slug,
    };
    send({
      ...installBase,
      status: "installing",
      message: "正在安装",
    });

    const skill = await adapter.installSkillHubPackage(installPackage);
    send({
      ...installBase,
      status: "installed",
      message: "安装完成",
      skill,
    });
  } catch (err: any) {
    send({
      ...base,
      slug: msg.package?.slug,
      status: "failed",
      error: "skill_error",
      message: err?.message || String(err),
    });
  }
}

function requireSkillHubPackage(msg: SkillHubInstallMessage): OpenClawSkillHubInstallPackage {
  if (!msg.package) throw new Error("SkillHub package is required");
  return msg.package;
}
