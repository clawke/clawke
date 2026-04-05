import type { OpenClawPluginApi } from "openclaw/plugin-sdk";
import { emptyPluginConfigSchema } from "openclaw/plugin-sdk";
import { clawkePlugin } from "./src/channel.js";
import { setClawkeRuntime } from "./src/runtime.js";
import { addPendingUsage } from "./src/gateway.js";

const plugin = {
  id: "clawke",
  name: "Clawke",
  description: "Clawke rich client channel – SDUI-powered native workspace",
  configSchema: emptyPluginConfigSchema(),
  register(api: OpenClawPluginApi) {
    setClawkeRuntime(api.runtime);
    api.registerChannel({ plugin: clawkePlugin });

    // 注册 llm_output hook，累加 usage 数据
    // deliver 回调会将累加的 usage 合并到 agent_text_done 中一起发送
    api.on("llm_output", (event, ctx) => {
      // 只处理 Clawke channel 的 usage，忽略飞书/Teams 等其他 channel
      if (ctx.messageProvider !== "clawke") return;

      if (!event.usage) {
        // 兜底：至少传递 model 和 provider
        addPendingUsage(null, event.model, event.provider);
        return;
      }
      addPendingUsage({
        input: event.usage?.input ?? 0,
        output: event.usage?.output ?? 0,
        cacheRead: event.usage?.cacheRead ?? 0,
        cacheWrite: event.usage?.cacheWrite ?? 0,
        total: event.usage?.total ?? 0,
      }, event.model, event.provider);
    });
  },
};

export default plugin;
