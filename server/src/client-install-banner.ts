import { cyanBold, shouldUseColor, yellowBold } from './terminal-style.js';

export const DOWNLOAD_URL = 'https://clawke.ai/#download';
export const RELEASES_URL = 'https://github.com/clawke/clawke/releases';
export const DEFAULT_LOCAL_SERVER_ADDRESS = 'http://127.0.0.1:8780';
export const DEFAULT_CONFIG_PATH = '~/.clawke/clawke.json';

const BOX_WIDTH = 52;

export interface ClientInstallBannerOptions {
  useColor?: boolean;
  serverAddress?: string;
  token?: string;
  configPath?: string;
  isTty?: boolean;
}

function boxRule(left: string, right: string, useColor: boolean): string {
  return cyanBold(`${left}${'═'.repeat(BOX_WIDTH)}${right}`, useColor);
}

function boxLine(text: string, useColor: boolean): string {
  return cyanBold(`║${`  ${text}`.padEnd(BOX_WIDTH, ' ')}║`, useColor);
}

function resolveBannerOptions(options: ClientInstallBannerOptions | boolean = {}): Required<ClientInstallBannerOptions> {
  const useColor = typeof options === 'boolean'
    ? options
    : options.useColor ?? shouldUseColor();
  return {
    useColor,
    serverAddress: typeof options === 'boolean'
      ? DEFAULT_LOCAL_SERVER_ADDRESS
      : options.serverAddress?.trim() || DEFAULT_LOCAL_SERVER_ADDRESS,
    token: typeof options === 'boolean' ? '' : options.token?.trim() || '',
    configPath: typeof options === 'boolean'
      ? DEFAULT_CONFIG_PATH
      : options.configPath?.trim() || DEFAULT_CONFIG_PATH,
    isTty: typeof options === 'boolean'
      ? Boolean(process.stdout.isTTY)
      : options.isTty ?? Boolean(process.stdout.isTTY),
  };
}

export function maskToken(token: string): string {
  const trimmed = token.trim();
  if (trimmed.length <= 8) return trimmed ? `${trimmed.slice(0, 2)}...${trimmed.slice(-2)}` : '';
  return `${trimmed.slice(0, 4)}...${trimmed.slice(-4)}`;
}

export function formatClientInstallBanner(options: ClientInstallBannerOptions | boolean = {}): string[] {
  const { useColor, serverAddress, token } = resolveBannerOptions(options);
  const tokenLine = token
    ? `   Token:           shown below in terminal only (${maskToken(token)})`
    : '   Token:           not required';

  return [
    '',
    boxRule('╔', '╗', useColor),
    boxLine('Clawke Server is ready', useColor),
    boxLine('Install Clawke Client to connect', useColor),
    boxRule('╚', '╝', useColor),
    '',
    '   Local connection:',
    `   Server address:  ${yellowBold(serverAddress, useColor)}`,
    tokenLine,
    '   Manual config:   Open Clawke Client > Configure Server Manually',
    '',
    '   iOS/iPadOS:      Open App Store on your device and search "Clawke"',
    `   Download:        ${yellowBold(DOWNLOAD_URL, useColor)}`,
    `   Other platforms: ${yellowBold(RELEASES_URL, useColor)}`,
    '',
  ];
}

export function formatTerminalTokenLines(options: ClientInstallBannerOptions = {}): string[] {
  const { token, configPath, isTty } = resolveBannerOptions(options);
  if (!token) return [];
  if (!isTty) {
    return [
      '   Token is required. Read relay.token from:',
      `   ${configPath}`,
      '',
    ];
  }
  return [
    '   Local connection token (terminal only):',
    `   ${token}`,
    '',
  ];
}

export function printClientInstallBanner(options: ClientInstallBannerOptions = {}): void {
  for (const line of formatClientInstallBanner(options)) {
    console.log(line);
  }
  for (const line of formatTerminalTokenLines(options)) {
    process.stdout.write(`${line}\n`);
  }
}
