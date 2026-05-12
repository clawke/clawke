import fs from 'node:fs';
import { loadConfig } from '../config.js';
import type { ConfiguredGateway } from '../types/gateways.js';

const DEFAULT_CAPABILITIES = ['chat', 'tasks', 'skills', 'models'];

export function listConfiguredGateways(
  configPath?: string,
): ConfiguredGateway[] {
  if (configPath && !fs.existsSync(configPath)) return [];
  const raw = configPath
    ? JSON.parse(fs.readFileSync(configPath, 'utf-8')) as Record<string, unknown>
    : loadConfig({ ensure: false }) as Record<string, unknown>;
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
