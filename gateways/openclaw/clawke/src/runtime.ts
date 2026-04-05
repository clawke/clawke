import type { PluginRuntime } from "openclaw/plugin-sdk";

let runtime: PluginRuntime | null = null;

export function setClawkeRuntime(next: PluginRuntime) {
  runtime = next;
}

export function getClawkeRuntime(): PluginRuntime {
  if (!runtime) {
    throw new Error("Clawke runtime not initialized");
  }
  return runtime;
}
