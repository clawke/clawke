import { createOpenClawGatewayRpc, type OpenClawGatewayRpc, type OpenClawGatewayRpcOptions } from "./task-adapter.ts";

export type OpenClawModelAdapterContext = {
  log?: {
    error?: (message: string) => void;
  };
};

export interface OpenClawModelAdapterOptions extends OpenClawGatewayRpcOptions {
  rpc?: OpenClawGatewayRpc;
}

export class OpenClawModelAdapter {
  private readonly rpc: OpenClawGatewayRpc;

  constructor(options: OpenClawModelAdapterOptions = {}) {
    this.rpc = options.rpc ?? createOpenClawGatewayRpc(options);
  }

  async listModels(ctx?: OpenClawModelAdapterContext): Promise<string[]> {
    try {
      const payload = await this.rpc("models.list", {}, { timeoutMs: 10_000 });
      return modelCatalogPayloadToKeys(payload);
    } catch (error) {
      ctx?.log?.error?.(`models.list failed: ${error instanceof Error ? error.message : String(error)}`);
      return [];
    }
  }
}

export function modelCatalogPayloadToKeys(payload: unknown): string[] {
  if (!isRecord(payload) || !Array.isArray(payload.models)) {
    return [];
  }
  const seen = new Set<string>();
  const keys: string[] = [];
  for (const entry of payload.models) {
    const key = modelCatalogEntryToKey(entry);
    if (!key || seen.has(key)) continue;
    seen.add(key);
    keys.push(key);
  }
  return keys;
}

export function modelCatalogEntryToKey(entry: unknown): string | undefined {
  if (!isRecord(entry)) return undefined;
  const provider = normalizeNonEmptyString(entry.provider);
  const model = normalizeNonEmptyString(entry.id) ?? normalizeNonEmptyString(entry.name);
  if (!provider || !model) return undefined;
  return modelStartsWithProvider(model, provider) ? model : `${provider}/${model}`;
}

function modelStartsWithProvider(model: string, provider: string): boolean {
  return model.toLowerCase().startsWith(`${provider.toLowerCase()}/`);
}

function normalizeNonEmptyString(value: unknown): string | undefined {
  if (typeof value !== "string") return undefined;
  const trimmed = value.trim();
  return trimmed ? trimmed : undefined;
}

function isRecord(value: unknown): value is Record<string, unknown> {
  return Boolean(value && typeof value === "object");
}
