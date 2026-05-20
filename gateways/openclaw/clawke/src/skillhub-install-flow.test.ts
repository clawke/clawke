import test from "node:test";
import assert from "node:assert/strict";
import {
  runSkillHubInstallJob,
  skillHubInstallAcceptedResponse,
  type SkillHubInstallMessage,
} from "./skillhub-install-flow.ts";

test("OpenClaw gateway accepts SkillHub install before native install completes", async () => {
  const msg: SkillHubInstallMessage = {
    type: "skillhub_install",
    request_id: "skillhub_1",
    install_id: "skillhub_1",
    package: {
      id: "404",
      slug: "weather",
      name: "Weather",
      source: "clawhub",
      version: "1.0.0",
      packageUrl: "https://local.clawke.ai/weather.zip",
      packageSha256: "b6d96df2ad9b4670293987afad32cabcc4db5f30842e471615bf348e6b2b0aac",
      packageType: "single",
    },
  };

  assert.deepEqual(skillHubInstallAcceptedResponse(msg), {
    type: "skillhub_install_response",
    request_id: "skillhub_1",
    install_id: "skillhub_1",
    ok: true,
    installed: false,
    status: "accepted",
    message: "安装任务已提交",
  });
});

test("OpenClaw gateway sends async SkillHub install status messages", async () => {
  const sent: Record<string, unknown>[] = [];
  const adapter = {
    async installSkillHubPackage() {
      return { id: "openclaw/weather", name: "weather" };
    },
  };

  await runSkillHubInstallJob(
    adapter,
    {
      type: "skillhub_install",
      request_id: "skillhub_1",
      install_id: "skillhub_1",
      package: {
        id: "404",
        slug: "weather",
        name: "Weather",
        source: "clawhub",
        version: "1.0.0",
        packageUrl: "https://local.clawke.ai/weather.zip",
        packageSha256: "b6d96df2ad9b4670293987afad32cabcc4db5f30842e471615bf348e6b2b0aac",
        packageType: "single",
      },
    },
    "OpenClaw",
    (payload) => sent.push(payload),
  );

  assert.deepEqual(sent.map((item) => item.status), ["installing", "installed"]);
  assert.equal(sent[0].type, "skillhub_install_status");
  assert.equal(sent[0].install_id, "skillhub_1");
  assert.equal(sent[0].account_id, "OpenClaw");
  assert.equal(sent[0].slug, "weather");
  assert.deepEqual(sent[1].skill, { id: "openclaw/weather", name: "weather" });
});

test("OpenClaw gateway reports failed SkillHub install status", async () => {
  const sent: Record<string, unknown>[] = [];
  const adapter = {
    async installSkillHubPackage() {
      throw new Error("native install failed");
    },
  };

  await runSkillHubInstallJob(
    adapter,
    {
      type: "skillhub_install",
      request_id: "skillhub_1",
      install_id: "skillhub_1",
      package: {
        id: "404",
        slug: "weather",
        name: "Weather",
        source: "clawhub",
        version: "1.0.0",
        packageUrl: "https://local.clawke.ai/weather.zip",
        packageSha256: "b6d96df2ad9b4670293987afad32cabcc4db5f30842e471615bf348e6b2b0aac",
        packageType: "single",
      },
    },
    "OpenClaw",
    (payload) => sent.push(payload),
  );

  assert.deepEqual(sent.map((item) => item.status), ["installing", "failed"]);
  assert.equal(sent[1].error, "skill_error");
  assert.equal(sent[1].message, "native install failed");
});

test("OpenClaw gateway reports failed status when SkillHub package is missing", async () => {
  const sent: Record<string, unknown>[] = [];

  await runSkillHubInstallJob(
    {
      async installSkillHubPackage() {
        throw new Error("should not be called");
      },
    },
    {
      type: "skillhub_install",
      request_id: "skillhub_1",
      install_id: "skillhub_1",
    },
    "OpenClaw",
    (payload) => sent.push(payload),
  );

  assert.equal(sent.length, 1);
  assert.equal(sent[0].status, "failed");
  assert.equal(sent[0].message, "SkillHub package is required");
});
