import test from "node:test";
import assert from "node:assert/strict";
import { existsSync, readFileSync } from "node:fs";
import { homedir } from "node:os";
import { join } from "node:path";

type ModelCatalogEntry = {
  id: unknown;
  name?: unknown;
  provider?: unknown;
  alias?: unknown;
  contextWindow?: unknown;
};

const liveTestEnabled = process.env.OPENCLAW_MODEL_RPC_LIVE === "1";

test(
  "live OpenClaw Gateway models.list returns model catalog",
  {
    skip: liveTestEnabled ? false : "Set OPENCLAW_MODEL_RPC_LIVE=1 to query the local OpenClaw Gateway",
    timeout: 15_000,
  },
  async () => {
    const payload = await queryLiveModelsList();

    assert.ok(isRecord(payload), `Expected object payload, got: ${JSON.stringify(payload)}`);
    assert.ok(Array.isArray(payload.models), `Expected payload.models array, got: ${JSON.stringify(payload)}`);
    assert.ok(payload.models.length > 0, `Expected at least one model, got: ${JSON.stringify(payload)}`);

    const models = payload.models as ModelCatalogEntry[];
    for (const model of models) {
      assert.equal(typeof model.id, "string", `Expected model.id string, got: ${JSON.stringify(model)}`);
      if (model.name !== undefined) {
        assert.equal(typeof model.name, "string", `Expected model.name string, got: ${JSON.stringify(model)}`);
      }
      if (model.provider !== undefined) {
        assert.equal(typeof model.provider, "string", `Expected model.provider string, got: ${JSON.stringify(model)}`);
      }
    }

    const sample = models
      .slice(0, 10)
      .map((model) => [model.provider, model.id].filter(Boolean).join("/"))
      .join(", ");
    console.log(`[OpenClaw models.list] count=${models.length}; sample=${sample}`);
  },
);

function isRecord(value: unknown): value is Record<string, unknown> {
  return Boolean(value && typeof value === "object");
}

type GatewayOptions = {
  url: string;
  token?: string;
  password?: string;
};

function loadGatewayOptions(): GatewayOptions {
  const config = safeLoadOpenClawConfig();
  const gateway = isRecord(config.gateway) ? config.gateway : {};
  const auth = isRecord(gateway.auth) ? gateway.auth : {};
  const tls = isRecord(gateway.tls) && gateway.tls.enabled === true;
  const port = Number(process.env.OPENCLAW_GATEWAY_PORT ?? gateway.port ?? 18789);
  const mode =
    typeof auth.mode === "string"
      ? auth.mode
      : typeof auth.password === "string" && auth.password.trim()
        ? "password"
        : typeof auth.token === "string" && auth.token.trim()
          ? "token"
          : "none";
  const token =
    process.env.OPENCLAW_GATEWAY_TOKEN ??
    (typeof auth.token === "string" && auth.token.trim() ? auth.token.trim() : undefined);
  const password =
    process.env.OPENCLAW_GATEWAY_PASSWORD ??
    (typeof auth.password === "string" && auth.password.trim() ? auth.password.trim() : undefined);
  return {
    url: `${tls ? "wss" : "ws"}://127.0.0.1:${port}`,
    token: mode === "token" ? token : undefined,
    password: mode === "password" ? password : undefined,
  };
}

function safeLoadOpenClawConfig(): Record<string, unknown> {
  try {
    const stateDir = process.env.OPENCLAW_STATE_DIR || join(homedir(), ".openclaw");
    const configPath = process.env.OPENCLAW_CONFIG_PATH || join(stateDir, "openclaw.json");
    if (!existsSync(configPath)) return {};
    const loaded = JSON.parse(readFileSync(configPath, "utf8"));
    return isRecord(loaded) ? loaded : {};
  } catch {
    return {};
  }
}

function queryLiveModelsList(): Promise<unknown> {
  const options = loadGatewayOptions();
  const WebSocketCtor = globalThis.WebSocket;
  assert.equal(typeof WebSocketCtor, "function", "Global WebSocket is unavailable");

  return new Promise((resolve, reject) => {
    const ws = new WebSocketCtor(options.url);
    let requestId = 0;
    let settled = false;
    const timer = setTimeout(() => {
      finish(reject, new Error("Timed out waiting for OpenClaw models.list response"));
    }, 10_000);

    const finish = (done: (value: unknown) => void, value: unknown) => {
      if (settled) return;
      settled = true;
      clearTimeout(timer);
      try {
        ws.close();
      } catch {
        // 测试清理失败可忽略 — Ignore best-effort test cleanup failure.
      }
      done(value);
    };

    const sendRequest = (method: string, params: unknown) => {
      ws.send(JSON.stringify({ type: "req", id: String(++requestId), method, params }));
    };

    ws.addEventListener("message", (event) => {
      const frame = parseFrame(String(event.data ?? ""));
      if (!isRecord(frame)) return;

      if (frame.type === "event" && frame.event === "connect.challenge") {
        sendRequest("connect", {
          minProtocol: 3,
          maxProtocol: 3,
          role: "operator",
          scopes: ["operator.read", "operator.write", "operator.admin", "operator.approvals"],
          client: {
            id: "openclaw-tui",
            displayName: "Clawke Plugin",
            version: "1.0.2",
            platform: "openclaw-plugin",
            mode: "ui",
          },
          caps: ["tool-events", "thinking-events"],
          auth: options.token
            ? { token: options.token }
            : options.password
              ? { password: options.password }
              : undefined,
        });
        return;
      }

      if (frame.type !== "res") return;
      if (frame.ok !== true) {
        finish(reject, new Error(`OpenClaw RPC failed: ${JSON.stringify(frame.error ?? frame)}`));
        return;
      }
      if (isRecord(frame.payload) && frame.payload.type === "hello-ok") {
        sendRequest("models.list", {});
        return;
      }
      if (frame.id === String(requestId)) {
        finish(resolve, frame.payload);
      }
    });

    ws.addEventListener("error", (event) => {
      finish(reject, new Error(`OpenClaw WebSocket error: ${String(event)}`));
    });

    ws.addEventListener("close", () => {
      if (!settled) {
        finish(reject, new Error("OpenClaw WebSocket closed before models.list response"));
      }
    });
  });
}

function parseFrame(data: string): unknown {
  try {
    return JSON.parse(data);
  } catch {
    return undefined;
  }
}
