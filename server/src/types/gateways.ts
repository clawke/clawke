export type GatewayStatus = 'online' | 'disconnected' | 'error';

export interface GatewayInfo {
  gateway_id: string;
  display_name: string;
  gateway_type: string;
  status: GatewayStatus;
  capabilities: string[];
  clawke_home?: string | null;
  managed_skills_root?: string | null;
  shared_skill_root?: string | null;
  local_to_server?: boolean | null;
  last_error_code?: string | null;
  last_error_message?: string | null;
  last_connected_at?: number | null;
  last_seen_at?: number | null;
}

export interface GatewayMetadataPatch {
  display_name?: string;
}

export interface ConfiguredGateway {
  gateway_id: string;
  gateway_type: string;
  display_name: string;
  capabilities: string[];
}
