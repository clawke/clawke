import type { SkillLocalizationPayload } from './skill-translation.js';

export interface SkillScope {
  id: string;
  type: 'gateway';
  label: string;
  description: string;
  readonly: boolean;
  gatewayId: string;
}

export interface ManagedSkill {
  id: string;
  name: string;
  description: string;
  category: string;
  trigger?: string;
  enabled: boolean;
  source: 'managed' | 'external' | 'readonly';
  sourceLabel: string;
  writable: boolean;
  deletable: boolean;
  path: string;
  absolutePath?: string;
  root: string;
  updatedAt: number;
  hasConflict: boolean;
  content?: string;
  body?: string;
  frontmatter?: Record<string, unknown>;
  sourceHash?: string;
  localization?: SkillLocalizationPayload;
}

export interface SkillDraft {
  name: string;
  category?: string;
  description: string;
  trigger?: string;
  body?: string;
  content?: string;
}

export interface SkillHubInstallPackage {
  id?: string;
  slug: string;
  name?: string;
  source?: string;
  sourceOwner?: string;
  version?: string;
  packageUrl?: string;
  packageSha256?: string;
  packageType?: string;
  gatewayType?: string;
  compatibleGateways?: string[];
}

export type SkillGatewayRequest =
  | { type: 'skill_list'; request_id?: string; account_id: string }
  | { type: 'skill_get'; request_id?: string; account_id: string; skill_id: string }
  | { type: 'skill_create'; request_id?: string; account_id: string; skill: SkillDraft }
  | { type: 'skill_update'; request_id?: string; account_id: string; skill_id: string; skill: SkillDraft }
  | { type: 'skill_delete'; request_id?: string; account_id: string; skill_id: string }
  | { type: 'skill_set_enabled'; request_id?: string; account_id: string; skill_id: string; enabled: boolean }
  | { type: 'skillhub_install'; request_id?: string; install_id?: string; account_id: string; install_mode?: 'gateway_native' | 'managed' | 'auto'; package: SkillHubInstallPackage };

export interface SkillGatewayResponse {
  type: 'skill_list_response' | 'skill_get_response' | 'skill_mutation_response' | 'skillhub_install_response';
  request_id: string;
  ok?: boolean;
  error?: string;
  message?: string;
  status?: string;
  details?: unknown;
  skills?: ManagedSkill[];
  skill?: ManagedSkill;
  deleted?: boolean;
  installed?: boolean;
}
