import type { ChannelConfigAdapter, OpenClawConfig } from "openclaw/plugin-sdk";

export type ClawkeChannelConfig = {
  enabled?: boolean;
  accountId?: string; // 唯一标识，用于 Clawke Server 路由和 Flutter 会话匹配
  url?: string; // ws://127.0.0.1:8766
  httpUrl?: string; // http://127.0.0.1:8780 — CS HTTP 服务地址，用于下载媒体文件
  allowFrom?: string[];
  defaultTo?: string;
};

export const DEFAULT_ACCOUNT_ID = "OpenClaw";

export type ResolvedClawkeAccount = {
  accountId: string;
  url: string;
  httpUrl: string;
  enabled: boolean;
  config: ClawkeChannelConfig;
};

function getClawkeConfig(cfg: OpenClawConfig): ClawkeChannelConfig | undefined {
  return (cfg.channels as Record<string, unknown> | undefined)?.clawke as
    | ClawkeChannelConfig
    | undefined;
}

export const clawkeConfig: ChannelConfigAdapter<ResolvedClawkeAccount> = {
  listAccountIds: (cfg) => {
    const clawkeCfg = getClawkeConfig(cfg);
    const id = clawkeCfg?.accountId ?? DEFAULT_ACCOUNT_ID;
    return [id];
  },

  resolveAccount: (cfg, accountId) => {
    const clawkeCfg = getClawkeConfig(cfg);
    const wsUrl = clawkeCfg?.url ?? "ws://127.0.0.1:8766";
    // httpUrl 默认从 WS URL 推导：ws://host:8766 → http://host:8780
    const defaultHttpUrl = wsUrl.replace(/^wss?:\/\//, "http://").replace(/:8766\b/, ":8780");
    return {
      accountId: accountId ?? DEFAULT_ACCOUNT_ID,
      url: wsUrl,
      httpUrl: clawkeCfg?.httpUrl ?? defaultHttpUrl,
      enabled: clawkeCfg?.enabled ?? false,
      config: clawkeCfg ?? {},
    };
  },

  isEnabled: (account) => account.enabled,

  isConfigured: (account) => !!account.url,

  resolveAllowFrom: ({ cfg }) => {
    const clawkeCfg = getClawkeConfig(cfg);
    return clawkeCfg?.allowFrom;
  },

  resolveDefaultTo: ({ cfg }) => {
    const clawkeCfg = getClawkeConfig(cfg);
    return clawkeCfg?.defaultTo;
  },

  describeAccount: (account) => ({
    accountId: account.accountId,
    enabled: account.enabled,
    configured: !!account.url,
  }),
};
