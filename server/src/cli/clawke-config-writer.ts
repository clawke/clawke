import fs from 'node:fs';
import path from 'node:path';
import { getConfigPath } from '../config.js';

interface RegisterGatewayOptions {
  configPath?: string;
  gatewayType: string;
  gatewayId: string;
  values?: Record<string, unknown>;
}

export function registerGatewayInClawkeConfig(options: RegisterGatewayOptions): void {
  const configPath = options.configPath || getConfigPath();
  let config: Record<string, any> = {};

  if (fs.existsSync(configPath)) {
    try {
      config = JSON.parse(fs.readFileSync(configPath, 'utf-8'));
    } catch (err: any) {
      console.error(`[clawke] ⚠️  Could not parse ${configPath}: ${err.message}`);
    }

    try {
      fs.copyFileSync(configPath, `${configPath}.bak`);
    } catch {}
  }

  if (!config.gateways || typeof config.gateways !== 'object') {
    config.gateways = {};
  }
  if (!Array.isArray(config.gateways[options.gatewayType])) {
    config.gateways[options.gatewayType] = [];
  }

  const gateways = config.gateways[options.gatewayType] as Array<Record<string, unknown>>;
  const existing = gateways.find((item) => item.id === options.gatewayId);
  const next = {
    ...(options.values || {}),
    id: options.gatewayId,
  };

  if (existing) {
    Object.assign(existing, next);
  } else {
    gateways.push(next);
  }

  fs.mkdirSync(path.dirname(configPath), { recursive: true });
  fs.writeFileSync(configPath, JSON.stringify(config, null, 2) + '\n');
}
