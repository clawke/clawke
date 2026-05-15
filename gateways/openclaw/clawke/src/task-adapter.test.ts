import test from "node:test";
import assert from "node:assert/strict";
import { mkdtempSync, rmSync, writeFileSync } from "node:fs";
import { tmpdir } from "node:os";
import { join } from "node:path";
import {
  createOpenClawGatewayRpc,
  type GatewayClientCtor,
  type GatewayClientLike,
  type GatewayClientOptions,
  OpenClawTaskAdapter,
  type OpenClawGatewayRpc,
  type StartGatewayClientWhenEventLoopReady,
} from "./task-adapter.ts";

type RpcCall = {
  method: string;
  params?: unknown;
};

function createAdapter(handler: OpenClawGatewayRpc) {
  const calls: RpcCall[] = [];
  const rpc: OpenClawGatewayRpc = async (method, params, options) => {
    calls.push({ method, params });
    return handler(method, params, options);
  };
  return { adapter: new OpenClawTaskAdapter({ rpc }), calls };
}

test("OpenClawTaskAdapter lists agent cron jobs through OpenClaw Gateway RPC", async () => {
  const { adapter, calls } = createAdapter(async (method, params) => {
    assert.equal(method, "cron.list");
    assert.deepEqual(params, { includeDisabled: true });
    return {
      jobs: [
        {
          id: "job_daily",
          name: "Daily report",
          enabled: true,
          createdAtMs: 1776395104970,
          updatedAtMs: 1777071981245,
          schedule: { kind: "cron", expr: "0 7 * * *", tz: "Asia/Shanghai" },
          payload: { kind: "agentTurn", message: "Create daily report" },
          delivery: { mode: "announce", channel: "clawke", to: "conv_1" },
          state: {
            nextRunAtMs: 1777158000000,
            lastRunAtMs: 1777071600006,
            lastRunStatus: "ok",
          },
        },
      ],
    };
  });

  const listed = await adapter.listTasks("OpenClaw");

  assert.equal(calls.length, 1);
  assert.equal(listed.length, 1);
  assert.equal(listed[0].id, "job_daily");
  assert.equal(listed[0].account_id, "OpenClaw");
  assert.equal(listed[0].name, "Daily report");
  assert.equal(listed[0].schedule, "0 7 * * *");
  assert.equal(listed[0].schedule_text, "每天 07:00 Asia/Shanghai");
  assert.equal(listed[0].prompt, "Create daily report");
  assert.equal(listed[0].enabled, true);
  assert.equal(listed[0].deliver, "conv_1");
  assert.equal(listed[0].next_run_at, "2026-04-25T23:00:00.000Z");
  assert.equal(listed[0].last_run?.status, "success");
});

test("OpenClawTaskAdapter writes task delivery as clawke channel target", async () => {
  const { adapter } = createAdapter(async (method, params) => {
    if (method === "cron.add") {
      assert.deepEqual(params, {
        name: "Return to conversation",
        schedule: { kind: "cron", expr: "0 7 * * *" },
        payload: { kind: "agentTurn", message: "Send summary" },
        enabled: true,
        wakeMode: "next-heartbeat",
        sessionTarget: "isolated",
        delivery: {
          mode: "announce",
          channel: "clawke",
          to: "conversation:be0b0ced-0036-4192-a62a-b313ac772f9a",
        },
      });
      return {
        id: "job_delivery",
        name: "Return to conversation",
        enabled: true,
        createdAtMs: 1776395104970,
        updatedAtMs: 1776395104970,
        schedule: { kind: "cron", expr: "0 7 * * *" },
        payload: { kind: "agentTurn", message: "Send summary" },
        delivery: {
          mode: "announce",
          channel: "clawke",
          to: "conversation:be0b0ced-0036-4192-a62a-b313ac772f9a",
        },
      };
    }
    throw new Error(`Unexpected method: ${method}`);
  });

  const created = await adapter.createTask("OpenClaw", {
    name: "Return to conversation",
    schedule: "0 7 * * *",
    prompt: "Send summary",
    enabled: true,
    deliver: "conversation:be0b0ced-0036-4192-a62a-b313ac772f9a",
  });

  assert.equal(
    created.deliver,
    "conversation:be0b0ced-0036-4192-a62a-b313ac772f9a",
  );
});

test("OpenClawTaskAdapter omits last_run when OpenClaw state has no real run time", async () => {
  const { adapter } = createAdapter(async (method, params) => {
    assert.equal(method, "cron.list");
    assert.deepEqual(params, { includeDisabled: true });
    return {
      jobs: [
        {
          id: "job_no_time",
          name: "No timestamp",
          enabled: true,
          createdAtMs: 1776395104970,
          updatedAtMs: 1776395104970,
          schedule: { kind: "cron", expr: "0 7 * * *" },
          payload: { kind: "agentTurn", message: "Create report" },
          state: {
            lastRunStatus: "ok",
          },
        },
      ],
    };
  });

  const listed = await adapter.listTasks("OpenClaw");

  assert.equal(listed.length, 1);
  assert.equal(listed[0].last_run, undefined);
});

test("OpenClawTaskAdapter mutates tasks through OpenClaw cron RPC methods", async () => {
  let job = {
    id: "job_new",
    name: "Morning check",
    enabled: true,
    createdAtMs: 1776395104970,
    updatedAtMs: 1776395104970,
    schedule: { kind: "cron", expr: "0 9 * * *" },
    payload: { kind: "agentTurn", message: "Summarize overnight changes" },
    delivery: { mode: "none" },
    state: {},
  };

  const { adapter, calls } = createAdapter(async (method, params) => {
    if (method === "cron.add") {
      assert.deepEqual(params, {
        name: "Morning check",
        schedule: { kind: "cron", expr: "0 9 * * *" },
        payload: { kind: "agentTurn", message: "Summarize overnight changes" },
        enabled: true,
        wakeMode: "next-heartbeat",
        sessionTarget: "isolated",
        delivery: { mode: "none" },
      });
      return job;
    }
    if (method === "cron.list") {
      return { jobs: [job] };
    }
    if (method === "cron.update") {
      const patch = (params as { patch: Record<string, unknown> }).patch;
      job = {
        ...job,
        ...patch,
        payload: (patch.payload as typeof job.payload | undefined) ?? job.payload,
        schedule: (patch.schedule as typeof job.schedule | undefined) ?? job.schedule,
        updatedAtMs: 1776395200000,
      };
      return job;
    }
    if (method === "cron.remove") {
      assert.deepEqual(params, { id: "job_new" });
      return { removed: true };
    }
    if (method === "cron.run") {
      assert.deepEqual(params, { id: "job_new", mode: "force" });
      return { runId: "run_1", queued: true };
    }
    if (method === "cron.runs") {
      assert.deepEqual(params, { id: "job_new", limit: 50 });
      return {
        entries: [
          {
            runId: "run_1",
            jobId: "job_new",
            status: "ok",
            startedAtMs: 1776395300000,
            completedAtMs: 1776395310000,
            summary: "done",
          },
        ],
      };
    }
    throw new Error(`Unexpected method: ${method}`);
  });

  const created = await adapter.createTask("acct_1", {
    name: "Morning check",
    schedule: "0 9 * * *",
    prompt: "Summarize overnight changes",
    enabled: true,
  });
  assert.equal(created.id, "job_new");
  assert.equal(created.status, "active");

  const fetched = await adapter.getTask("acct_1", "job_new");
  assert.equal(fetched?.id, "job_new");

  const updated = await adapter.updateTask("acct_1", "job_new", {
    name: "Updated check",
    schedule: "30 8 * * *",
    prompt: "Updated prompt",
    enabled: false,
  });
  assert.equal(updated?.name, "Updated check");
  assert.equal(updated?.schedule, "30 8 * * *");
  assert.equal(updated?.prompt, "Updated prompt");
  assert.equal(updated?.status, "paused");

  const enabled = await adapter.setEnabled("acct_1", "job_new", true);
  assert.equal(enabled?.enabled, true);

  const run = await adapter.runTask("acct_1", "job_new");
  assert.equal(run.id, "run_1");
  assert.equal(run.task_id, "job_new");
  assert.equal(run.status, "running");

  const runs = await adapter.listRuns("acct_1", "job_new");
  assert.equal(runs.length, 1);
  assert.equal(runs[0].id, "run_1");
  assert.equal(runs[0].status, "success");

  const output = await adapter.getOutput("acct_1", "job_new", "run_1");
  assert.equal(output, "done");

  await assert.rejects(
    () => adapter.getTask("acct_1", "../escape"),
    /Invalid taskId/,
  );
  await assert.rejects(
    () => adapter.getOutput("acct_1", "job_new", "../escape"),
    /Invalid runId/,
  );

  assert.equal(await adapter.deleteTask("acct_1", "job_new"), true);
  assert.equal(calls.some((call) => call.method === "cron.add"), true);
  assert.equal(calls.some((call) => call.method === "cron.update"), true);
  assert.equal(calls.some((call) => call.method === "cron.remove"), true);
  assert.equal(calls.some((call) => call.method === "cron.run"), true);
});

test("OpenClawTaskAdapter maps cron run log timestamps without epoch fallback", async () => {
  const logTimestamp = 1777071981245;
  const { adapter } = createAdapter(async (method) => {
    assert.equal(method, "cron.runs");
    return {
      entries: [
        {
          ts: logTimestamp,
          jobId: "job_new",
          action: "finished",
          status: "ok",
          summary: "done",
        },
      ],
    };
  });

  const runs = await adapter.listRuns("acct_1", "job_new");

  assert.equal(runs.length, 1);
  assert.equal(runs[0].started_at, new Date(logTimestamp).toISOString());
  assert.notEqual(runs[0].started_at, "1970-01-01T00:00:00.000Z");
});

type CapturedGatewayRequest = {
  method: string;
  params?: unknown;
  options?: { timeoutMs?: number | null; expectFinal?: boolean };
};

type CapturedStartCall = {
  client: GatewayClientLike;
  options?: { timeoutMs?: number; signal?: AbortSignal };
};

type GatewayClientHarnessOptions = {
  readiness?: "ready" | "not-ready" | "throw" | "pending";
  readinessError?: Error;
  autoHello?: boolean;
};

function createGatewayClientHarness(
  response: unknown = { jobs: [] },
  harnessOptions: GatewayClientHarnessOptions = {},
) {
  const startCalls: CapturedStartCall[] = [];
  let resolveReadiness:
    | ((readiness: { ready?: boolean; aborted?: boolean }) => void)
    | undefined;

  class FakeGatewayClient {
    readonly options: GatewayClientOptions;
    readonly requests: CapturedGatewayRequest[] = [];
    stopOptions?: { timeoutMs?: number };
    stopped = false;

    constructor(options: GatewayClientOptions) {
      this.options = options;
      instances.push(this);
    }

    start() {
      if (harnessOptions.autoHello === false) {
        return;
      }
      queueMicrotask(() => {
        void this.options.onHelloOk?.({
          type: "hello-ok",
          features: { methods: ["cron.list"], events: [] },
        });
      });
    }

    async request(
      method: string,
      params?: unknown,
      options?: { timeoutMs?: number | null; expectFinal?: boolean },
    ) {
      this.requests.push({ method, params, options });
      if (method === "cron.list") {
        return response;
      }
      throw new Error(`Unexpected method: ${method}`);
    }

    async stopAndWait(options?: { timeoutMs?: number }) {
      this.stopOptions = options;
      this.stopped = true;
    }
  }

  const instances: FakeGatewayClient[] = [];
  const startGatewayClientWhenEventLoopReady: StartGatewayClientWhenEventLoopReady = async (
    client,
    options,
  ) => {
    startCalls.push({ client, options });
    if (harnessOptions.readiness === "throw") {
      throw harnessOptions.readinessError ?? new Error("readiness failed");
    }
    if (harnessOptions.readiness === "not-ready") {
      return { ready: false, aborted: false };
    }
    client.start();
    if (harnessOptions.readiness === "pending") {
      return await new Promise((resolve) => {
        resolveReadiness = resolve;
      });
    }
    return { ready: true, aborted: false };
  };

  return {
    gatewayClientCtor: FakeGatewayClient as GatewayClientCtor,
    startGatewayClientWhenEventLoopReady,
    instances,
    startCalls,
    resolveReadiness: (readiness: { ready?: boolean; aborted?: boolean }) => {
      resolveReadiness?.(readiness);
    },
  };
}

test("OpenClawTaskAdapter default RPC uses OpenClaw GatewayClient with token auth", async () => {
  const originalPort = process.env.OPENCLAW_GATEWAY_PORT;
  const originalToken = process.env.OPENCLAW_GATEWAY_TOKEN;
  const originalPassword = process.env.OPENCLAW_GATEWAY_PASSWORD;
  const originalConfigPath = process.env.OPENCLAW_CONFIG_PATH;
  const tempDir = mkdtempSync(join(tmpdir(), "clawke-openclaw-config-"));
  const configPath = join(tempDir, "openclaw.json");
  const {
    gatewayClientCtor,
    startGatewayClientWhenEventLoopReady,
    instances,
    startCalls,
  } = createGatewayClientHarness();

  try {
    delete process.env.OPENCLAW_GATEWAY_PORT;
    delete process.env.OPENCLAW_GATEWAY_TOKEN;
    delete process.env.OPENCLAW_GATEWAY_PASSWORD;
    process.env.OPENCLAW_CONFIG_PATH = configPath;
    writeFileSync(
      configPath,
      `{
        // 本地配置允许注释 — Local config allows comments.
        "gateway": {
          "port": 18789,
          "auth": {
            "mode": "token",
            "token": "test-token", // token 可带尾注释 — Token may have trailing comments.
          },
        },
      }`,
      "utf8",
    );
    const tasks = await new OpenClawTaskAdapter({
      gatewayClientCtor,
      startGatewayClientWhenEventLoopReady,
    }).listTasks("OpenClaw");

    assert.deepEqual(tasks, []);
    assert.equal(instances.length, 1);
    assert.equal(instances[0].options.url, "ws://127.0.0.1:18789");
    assert.equal(instances[0].options.token, "test-token");
    assert.equal(instances[0].options.password, undefined);
    assert.equal(instances[0].options.clientName, "gateway-client");
    assert.equal(instances[0].options.clientDisplayName, "Clawke Plugin");
    assert.equal(instances[0].options.clientVersion, "1.0.2");
    assert.equal(instances[0].options.platform, undefined);
    assert.equal(instances[0].options.mode, "backend");
    assert.equal(instances[0].options.role, "operator");
    assert.deepEqual(instances[0].options.scopes, [
      "operator.read",
      "operator.write",
      "operator.admin",
      "operator.approvals",
    ]);
    assert.deepEqual(instances[0].options.caps, ["tool-events", "thinking-events"]);
    assert.deepEqual(instances[0].requests, [
      {
        method: "cron.list",
        params: { includeDisabled: true },
        options: { timeoutMs: 30_000 },
      },
    ]);
    assert.equal(startCalls.length, 1);
    assert.equal(startCalls[0].client, instances[0]);
    assert.equal(startCalls[0].options?.timeoutMs, 30_000);
    assert.equal(startCalls[0].options?.signal?.aborted, true);
    assert.equal(instances[0].stopped, true);
  } finally {
    if (originalPort === undefined) {
      delete process.env.OPENCLAW_GATEWAY_PORT;
    } else {
      process.env.OPENCLAW_GATEWAY_PORT = originalPort;
    }
    if (originalToken === undefined) {
      delete process.env.OPENCLAW_GATEWAY_TOKEN;
    } else {
      process.env.OPENCLAW_GATEWAY_TOKEN = originalToken;
    }
    if (originalPassword === undefined) {
      delete process.env.OPENCLAW_GATEWAY_PASSWORD;
    } else {
      process.env.OPENCLAW_GATEWAY_PASSWORD = originalPassword;
    }
    if (originalConfigPath === undefined) {
      delete process.env.OPENCLAW_CONFIG_PATH;
    } else {
      process.env.OPENCLAW_CONFIG_PATH = originalConfigPath;
    }
    rmSync(tempDir, { recursive: true, force: true });
  }
});

test("OpenClawTaskAdapter default RPC omits credentials when auth mode is none", async () => {
  const originalToken = process.env.OPENCLAW_GATEWAY_TOKEN;
  const originalPassword = process.env.OPENCLAW_GATEWAY_PASSWORD;
  const originalConfigPath = process.env.OPENCLAW_CONFIG_PATH;
  const tempDir = mkdtempSync(join(tmpdir(), "clawke-openclaw-config-none-"));
  const configPath = join(tempDir, "openclaw.json");
  const {
    gatewayClientCtor,
    startGatewayClientWhenEventLoopReady,
    instances,
    startCalls,
  } = createGatewayClientHarness();

  try {
    process.env.OPENCLAW_GATEWAY_TOKEN = "env-token-should-not-pass";
    process.env.OPENCLAW_GATEWAY_PASSWORD = "env-password-should-not-pass";
    process.env.OPENCLAW_CONFIG_PATH = configPath;
    writeFileSync(
      configPath,
      `{
        "gateway": {
          "port": 18789,
          "auth": {
            "mode": "none",
            "token": "config-token-should-not-pass",
            "password": "config-password-should-not-pass"
          }
        }
      }`,
      "utf8",
    );

    const tasks = await new OpenClawTaskAdapter({
      gatewayClientCtor,
      startGatewayClientWhenEventLoopReady,
    }).listTasks("OpenClaw");

    assert.deepEqual(tasks, []);
    assert.equal(instances.length, 1);
    assert.equal(instances[0].options.url, "ws://127.0.0.1:18789");
    assert.equal(instances[0].options.token, undefined);
    assert.equal(instances[0].options.password, undefined);
    assert.equal(instances[0].options.clientName, "gateway-client");
    assert.equal(instances[0].options.mode, "backend");
    assert.equal(instances[0].options.role, "operator");
    assert.equal(startCalls.length, 1);
    assert.equal(instances[0].stopped, true);
  } finally {
    if (originalToken === undefined) {
      delete process.env.OPENCLAW_GATEWAY_TOKEN;
    } else {
      process.env.OPENCLAW_GATEWAY_TOKEN = originalToken;
    }
    if (originalPassword === undefined) {
      delete process.env.OPENCLAW_GATEWAY_PASSWORD;
    } else {
      process.env.OPENCLAW_GATEWAY_PASSWORD = originalPassword;
    }
    if (originalConfigPath === undefined) {
      delete process.env.OPENCLAW_CONFIG_PATH;
    } else {
      process.env.OPENCLAW_CONFIG_PATH = originalConfigPath;
    }
    rmSync(tempDir, { recursive: true, force: true });
  }
});

test("OpenClawTaskAdapter default RPC cleans up when GatewayClient is not ready", async () => {
  const {
    gatewayClientCtor,
    startGatewayClientWhenEventLoopReady,
    instances,
    startCalls,
  } = createGatewayClientHarness({ jobs: [] }, {
    readiness: "not-ready",
    autoHello: false,
  });

  await assert.rejects(
    () =>
      new OpenClawTaskAdapter({
        gatewayClientCtor,
        startGatewayClientWhenEventLoopReady,
      }).listTasks("OpenClaw"),
    /OpenClaw Gateway RPC readiness timeout after 30000ms/,
  );

  assert.equal(instances.length, 1);
  assert.deepEqual(instances[0].requests, []);
  assert.equal(startCalls.length, 1);
  assert.equal(startCalls[0].options?.timeoutMs, 30_000);
  assert.equal(startCalls[0].options?.signal?.aborted, true);
  assert.equal(instances[0].stopped, true);
});

test("OpenClawTaskAdapter default RPC surfaces GatewayClient readiness failure", async () => {
  const {
    gatewayClientCtor,
    startGatewayClientWhenEventLoopReady,
    instances,
    startCalls,
  } = createGatewayClientHarness({ jobs: [] }, {
    readiness: "throw",
    readinessError: new Error("readiness boom"),
    autoHello: false,
  });

  await assert.rejects(
    () =>
      new OpenClawTaskAdapter({
        gatewayClientCtor,
        startGatewayClientWhenEventLoopReady,
      }).listTasks("OpenClaw"),
    /readiness boom/,
  );

  assert.equal(instances.length, 1);
  assert.deepEqual(instances[0].requests, []);
  assert.equal(startCalls.length, 1);
  assert.equal(startCalls[0].options?.signal?.aborted, true);
  assert.equal(instances[0].stopped, true);
});

test("createOpenClawGatewayRpc close stops active GatewayClient readiness client", async () => {
  const {
    gatewayClientCtor,
    startGatewayClientWhenEventLoopReady,
    instances,
    startCalls,
    resolveReadiness,
  } = createGatewayClientHarness({ jobs: [] }, {
    readiness: "pending",
    autoHello: false,
  });
  const rpc = createOpenClawGatewayRpc({
    gatewayUrl: "ws://127.0.0.1:18789",
    gatewayClientCtor,
    startGatewayClientWhenEventLoopReady,
  });
  const pending = rpc("cron.list", { includeDisabled: true });

  await new Promise<void>((resolve) => queueMicrotask(resolve));
  assert.equal(instances.length, 1);
  assert.equal(startCalls.length, 1);
  assert.equal(instances[0].stopped, false);

  rpc.close?.();

  assert.equal(instances[0].stopped, true);
  assert.equal(instances[0].stopOptions?.timeoutMs, 1_000);
  assert.equal(startCalls[0].options?.signal?.aborted, true);
  resolveReadiness({ ready: false, aborted: true });
  await assert.rejects(pending, /OpenClaw Gateway RPC client closed/);
});
