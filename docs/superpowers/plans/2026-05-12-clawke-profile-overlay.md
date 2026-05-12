# Clawke Profile Overlay Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Add `--profile <name>` support so dev profiles can overlay base config while keeping runtime files isolated.

**Architecture:** Introduce a shared profile resolver used by config loading, CLI server commands, gateway update, and doctor. Default commands keep using `~/.clawke`; profile commands read `~/.clawke/clawke.json` plus `~/.clawke/profiles/<profile>/clawke.json` and write runtime state under the profile directory.

**Tech Stack:** TypeScript, Node.js CLI, native `node:test`, existing Clawke Server config/runtime modules.

---

### Task 1: Profile Resolver

**Files:**
- Create: `server/src/cli/profile.ts`
- Test: `server/test/profile.test.js`

- [x] Write tests for default profile behavior, CLI/env precedence, profile path calculation, and invalid profile names.
- [x] Implement `resolveProfileContext()` and `parseProfileArgv()`.
- [x] Run `npm run build` and `node --test test/profile.test.js`.

### Task 2: Config Overlay

**Files:**
- Modify: `server/src/config.ts`
- Test: `server/test/config-profile.test.js`

- [x] Write tests for default config compatibility and profile overlay deep merge.
- [x] Implement overlay loading with array replacement.
- [x] Preserve current no-profile behavior and `MODE` env override.
- [x] Run `npm run build` and config tests.

### Task 3: Runtime Home and CLI Server Commands

**Files:**
- Modify: `server/src/store/clawke-home.ts`
- Modify: `server/src/cli/clawke.ts`
- Test: `server/test/clawke-cli-profile.test.js`

- [x] Write tests proving default commands still use `~/.clawke`.
- [x] Write tests proving `server status --profile dev` uses `~/.clawke/profiles/dev/server.pid`.
- [x] Replace hardcoded CLI runtime paths with profile context.
- [x] Run CLI profile tests.

### Task 4: Gateway Update and Doctor

**Files:**
- Modify: `server/src/cli/gateway-updater.ts`
- Modify: `server/src/cli/clawke-doctor.ts`
- Test: extend existing `gateway-updater.test.js` and doctor tests if present.

- [x] Write tests for `gateway update --profile dev --local-only` writing profile config.
- [x] Add profile path output to `doctor --profile dev`.
- [x] Run targeted tests.

### Task 5: Verification

**Files:**
- Modify docs/skill only if command usage changes.

- [x] Run `npm run build`.
- [x] Run relevant server tests.
- [x] Run `git diff --check`.
- [x] Summarize changed behavior and compatibility.
