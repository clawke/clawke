import fs from 'node:fs';
import os from 'node:os';
import path from 'node:path';
import type { ConfiguredGateway } from '../types/gateways.js';

const DEFAULT_CAPABILITIES = ['chat', 'tasks', 'skills', 'models'];

function defaultConfigPath(): string {
  const clawkeHome = process.env.CLAWKE_DATA_DIR || path.join(os.homedir(), '.clawke');
  return path.join(clawkeHome, 'clawke.json');
}

export function listConfiguredGateways(
  configPath = defaultConfigPath(),
): ConfiguredGateway[] {
  if (!fs.existsSync(configPath)) return [];
  const raw = JSON.parse(fs.readFileSync(configPath, 'utf-8')) as Record<string, unknown>;
  const gateways = raw.gateways as Record<string, unknown> | undefined;
  if (!gateways) return [];

  const result: ConfiguredGateway[] = [];
  for (const [gatewayType, list] of Object.entries(gateways)) {
    if (!Array.isArray(list)) continue;
    for (const item of list as Array<Record<string, unknown>>) {
      const id = typeof item.id === 'string' && item.id.trim() ? item.id.trim() : '';
      if (!id) continue;
      result.push({
        gateway_id: id,
        gateway_type: gatewayType,
        display_name: displayNameFor(gatewayType, id),
        capabilities: DEFAULT_CAPABILITIES,
      });
    }
  }
  return result;
}

function displayNameFor(gatewayType: string, id: string): string {
  if (gatewayType === 'hermes') return 'Hermes';
  if (gatewayType === 'openclaw') return 'OpenClaw';
  if (gatewayType === 'nanobot') return 'nanobot';
  return id;
}
