import os from 'node:os';
import path from 'node:path';

export interface ProfileContext {
  profile?: string;
  isProfile: boolean;
  baseHome: string;
  runtimeHome: string;
  baseConfigPath: string;
  profileConfigPath?: string;
  configPath: string;
}

export interface ResolveProfileOptions {
  profile?: string;
  baseHome?: string;
  homeDir?: string;
  env?: NodeJS.ProcessEnv | Record<string, string | undefined>;
}

export interface ParsedProfileArgv {
  args: string[];
  profile?: string;
}

function validateProfileName(profile: string): string {
  const trimmed = profile.trim();
  if (!trimmed) {
    throw new Error('Missing profile name after --profile');
  }
  if (trimmed === '.' || trimmed === '..' || !/^[A-Za-z0-9_-]+$/.test(trimmed)) {
    throw new Error(`Invalid profile name: ${profile}`);
  }
  return trimmed;
}

function normalizeProfile(profile?: string): string | undefined {
  if (profile === undefined) return undefined;
  return validateProfileName(profile);
}

export function parseProfileArgv(
  argv: string[],
  env: NodeJS.ProcessEnv | Record<string, string | undefined> = process.env,
): ParsedProfileArgv {
  const args: string[] = [];
  let profileFromArg: string | undefined;

  for (let i = 0; i < argv.length; i += 1) {
    const arg = argv[i];
    if (arg === '--profile') {
      const next = argv[i + 1];
      if (next === undefined || next === '') {
        throw new Error('Missing profile name after --profile');
      }
      profileFromArg = validateProfileName(next);
      i += 1;
      continue;
    }
    if (arg.startsWith('--profile=')) {
      profileFromArg = validateProfileName(arg.slice('--profile='.length));
      continue;
    }
    args.push(arg);
  }

  const profile = profileFromArg ?? normalizeProfile(env.CLAWKE_PROFILE);
  return { args, profile };
}

export function resolveProfileContext(options: ResolveProfileOptions = {}): ProfileContext {
  const env = options.env ?? process.env;
  const homeDir = options.homeDir || os.homedir();
  const baseHome = options.baseHome || env.CLAWKE_DATA_DIR || path.join(homeDir, '.clawke');
  const profile = normalizeProfile(options.profile ?? env.CLAWKE_PROFILE);
  const baseConfigPath = path.join(baseHome, 'clawke.json');

  if (!profile) {
    return {
      profile: undefined,
      isProfile: false,
      baseHome,
      runtimeHome: baseHome,
      baseConfigPath,
      configPath: baseConfigPath,
    };
  }

  const runtimeHome = path.join(baseHome, 'profiles', profile);
  const profileConfigPath = path.join(runtimeHome, 'clawke.json');
  return {
    profile,
    isProfile: true,
    baseHome,
    runtimeHome,
    baseConfigPath,
    profileConfigPath,
    configPath: profileConfigPath,
  };
}
