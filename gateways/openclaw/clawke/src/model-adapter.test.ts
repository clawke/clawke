import test from "node:test";
import assert from "node:assert/strict";
import { OpenClawModelAdapter, modelCatalogEntryToKey } from "./model-adapter.ts";
import type { OpenClawGatewayRpc } from "./task-adapter.ts";

test("OpenClawModelAdapter lists models through OpenClaw Gateway RPC", async () => {
  const calls: Array<{ method: string; params?: unknown }> = [];
  const rpc: OpenClawGatewayRpc = async (method, params) => {
    calls.push({ method, params });
    return {
      models: [
        { provider: "anthropic", id: "claude-sonnet-4-6", name: "Claude Sonnet" },
        { provider: "openrouter", id: "openrouter/hunter-alpha", name: "Hunter" },
        { provider: "nvidia", id: "moonshotai/kimi-k2.5", name: "Kimi" },
        { provider: "anthropic", id: "claude-sonnet-4-6", name: "Duplicate" },
        { provider: "", id: "ignored" },
        { provider: "openai", id: "" },
      ],
    };
  };
  const adapter = new OpenClawModelAdapter({ rpc });

  const models = await adapter.listModels();

  assert.deepEqual(calls, [{ method: "models.list", params: {} }]);
  assert.deepEqual(models, [
    "anthropic/claude-sonnet-4-6",
    "openrouter/hunter-alpha",
    "nvidia/moonshotai/kimi-k2.5",
  ]);
});

test("OpenClawModelAdapter returns empty list and logs when models.list fails", async () => {
  const logs: string[] = [];
  const adapter = new OpenClawModelAdapter({
    rpc: async () => {
      throw new Error("gateway unavailable");
    },
  });

  const models = await adapter.listModels({
    log: { error: (message: string) => logs.push(message) },
  });

  assert.deepEqual(models, []);
  assert.equal(logs.length, 1);
  assert.match(logs[0], /models\.list failed: gateway unavailable/);
});

test("modelCatalogEntryToKey mirrors OpenClaw provider/model key semantics", () => {
  assert.equal(
    modelCatalogEntryToKey({ provider: "anthropic", id: "claude-opus-4-6" }),
    "anthropic/claude-opus-4-6",
  );
  assert.equal(
    modelCatalogEntryToKey({ provider: "openrouter", id: "openrouter/hunter-alpha" }),
    "openrouter/hunter-alpha",
  );
  assert.equal(modelCatalogEntryToKey({ provider: "nvidia", id: "moonshotai/kimi-k2.5" }), "nvidia/moonshotai/kimi-k2.5");
  assert.equal(modelCatalogEntryToKey({ provider: "", id: "gpt-5.4" }), undefined);
  assert.equal(modelCatalogEntryToKey({ provider: "openai", id: "" }), undefined);
});
