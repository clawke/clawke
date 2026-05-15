# Changelog

> Full version history of the Clawke project. The README shows only the latest month.

<!-- CHANGELOG_START -->

## v1.1.31 (2026-05-12)

**[New Feature]** Gateway usage visibility and update automation.
- Added a gateway usage dashboard so connected gateway activity is easier to inspect.
- Added automatic restart handling for updated gateways and clearer local server connection hints.

**[Bug Fix]** OpenClaw gateway configuration and runtime guidance.
- Fixed OpenClaw gateway update configuration merging.
- Improved GatewayClient error guidance and server PID lifecycle safeguards.
- Made release version checks configurable and improved install script TTY handling.

## v1.1.30 (2026-05-11)

**[Bug Fix]** OpenClaw gateway and UI regression stability.
- Stabilized the OpenClaw gateway integration path so prepared gateway changes are reflected reliably in release validation.
- Hardened the UI E2E regression suite to reduce flaky release checks before publishing.

**[Enhancement]** Linux desktop setup and packaging polish.
- Added Linux desktop registration and shell-friendly setup support for packaged desktop installs.
- Repaired Linux icon and font fallback behavior, and polished desktop app icon/title metadata.
- Improved the gateway install flow so post-install next steps are clearer.

## v1.1.29 (2026-05-10)

**[Bug Fix]** macOS App Store login and review readiness.
- Disabled in-app update checks and update prompts for Mac App Store builds so updates stay under App Store control.
- Fixed macOS App Store signing and entitlement validation for Apple Sign-In, production APNs, and Google Sign-In keychain access.
- Added safeguards for Mac App Store package signing so quarantine attributes and disallowed entitlements are caught before upload.

**[Enhancement]** Release polish and runtime path safety.
- Refined the welcome screen layout for a cleaner first-run experience.
- Ignored debug runtime directory overrides on mobile platforms and when the repo root cannot be resolved.

## v1.1.27 (2026-05-09)

**[Bug Fix]** macOS release sign-in and desktop OAuth packaging.
- Keeps macOS release Google sign-in on the native GoogleSignIn flow and validates the required keychain access groups.
- Keeps macOS release Apple sign-in hidden unless the provisioning profile enables the Sign in with Apple entitlement, avoiding a broken login button.

**[Enhancement]** Desktop release coverage and assets.
- Polished the desktop OAuth callback flow and refreshed Windows/Linux desktop icons.
- Updated GitHub Actions to the current Node runtime and added internal desktop build coverage for release workflows.

## v1.1.26 (2026-05-09)

**[Bug Fix]** macOS release signing and Windows desktop Google login.
- Reworked macOS release signing to sign nested frameworks explicitly before signing the app bundle, matching current Apple signing guidance and macOS 26 validation.
- Switched macOS release build and post-publish verification to macOS 26 runners so published DMGs are validated on the same OS family users reported failures on.
- Added Windows/Linux desktop Google OAuth through system browser loopback flow with PKCE, gated by `GOOGLE_DESKTOP_CLIENT_ID`.
- Updated Windows release builds to enable desktop Google OAuth when `GOOGLE_DESKTOP_CLIENT_ID` is configured, while keeping release validation runnable when the secret is absent.

## v1.1.23 (2026-05-09)

**[Bug Fix]** Windows release startup and desktop login behavior.
- Bundled the Visual C++ runtime DLLs into the Windows release zip so Clawke can start even when the system runtime is missing or corrupted.
- Added release workflow validation to ensure Windows packages include `msvcp140.dll`, `vcruntime140.dll`, and `vcruntime140_1.dll`.
- Hid Google sign-in on Windows and Linux desktop builds where the native plugin is unavailable, avoiding the desktop `MissingPluginException` path.

## v1.1.22 (2026-05-09)

**[Bug Fix]** Android release signing and Google login.
- Restored fixed Android release signing in the GitHub release workflow so official APKs use the expected release certificate.
- Added certificate fingerprint checks and published APK verification to prevent debug-signed Android release artifacts.

## v1.1.21 (2026-05-03)

**[Enhancement]** Release and runtime path stability.
- Stabilized runtime path handling used by local app runs and task UI E2E coverage.
- Hardened task E2E setup so release validation can run with fewer environment-specific path failures.

**[Architecture]** Gateway listener naming and public docs cleanup.
- Renamed the upstream listener concept to gateway listener across the runtime boundary.
- Moved private planning documents out of public docs and kept public documentation focused on product and integration material.

## v1.1.20 (2026-05-02)

**[New Feature]** Hermes cron result sync and task delivery tracking.
- Added Hermes cron output sync so scheduled job results can be delivered back into the target Clawke conversation.
- Added persistent delivery state, retry handling, and validation around task delivery targets.
- Added client-side task delivery validation and expanded task management tests.

**[Enhancement]** Task management and gateway diagnostics.
- Improved the task management page with richer delivery status handling and validation feedback.
- Added gateway alert support for surfacing delivery problems to connected clients.
- Added runtime-directory diagnostics to make local client logging and database path issues easier to inspect.

**[Enhancement]** Hermes media routing and workspace isolation.
- Updated Hermes image routing so image inputs can use native multimodal support or vision enrichment depending on provider/model capability.
- Added per-session working directory handling for Hermes without mutating global process state.
- Added regression tests for Hermes channel routing, workdir isolation, cron sync, and task adapter behavior.

## v1.1.17 (2026-04-29)

**[New Feature]** Clawke Doctor command.
- Added `clawke doctor` to inspect project files, runtime status, local configuration, and configured gateway instances.
- Added clearer gateway diagnostics for OpenClaw-managed and Clawke-managed gateway modes.

**[Enhancement]** Multi-agent positioning and mobile management messaging.
- Updated README messaging to emphasize online management for OpenClaw, Hermes, Nanobot, and other agents.
- Clarified that Clawke can manage multiple agents from desktop and mobile clients.

**[Bug Fix]** Disconnect recovery for streamed chat replies.
- Fixed a state recovery bug where the UI could keep showing `Thinking`, a running tool, and the stop button after reconnecting.
- Sync now acts as a completion recovery path when the client missed `text_done` or `tool_call_done` during a WebSocket disconnect.
- Added persistent provider and UI E2E regression coverage for this failure mode.

## v1.1.15 (2026-04-29)

**[New Feature]** Hermes gateway support.
- Added Hermes gateway integration so Clawke can connect to Hermes-backed agent sessions.
- Added Hermes model and skill discovery through the gateway layer.

**[New Feature]** Native management pages for skills and tasks.
- Added Skills Center support for listing, searching, creating, editing, disabling, and deleting managed skills.
- Added task management UI and APIs for viewing, triggering, and managing agent-side tasks without moving execution into Clawke.

**[Enhancement]** Gateway-backed resource discovery and translation.
- Moved model and skill metadata reads to gateway-backed APIs.
- Added gateway system sessions for background translation and refresh flows.
- Added batch translation, cache reuse, and detailed logs to make production diagnosis easier.

**[Bug Fix]** OpenClaw model routing and startup configuration.
- Fixed OpenClaw model switching to align with the dispatcher API.
- Fixed gateway model metadata fallback and channel configuration writing during install.
- Hardened startup behavior for gateways that do not provide a runnable start command.

**[Architecture]** Broader gateway test and release coverage.
- Added regression tests for OpenClaw, Hermes, nanobot, skill management, task management, and gateway system requests.
- Added UI E2E harness and high-priority cases for conversation settings, skills, tasks, approvals, choices, and streaming replies.

## v1.1.5 (2026-04-18)

**[New Feature]** One-click installation and unified CLI commands.
- Introduced `curl` based one-click install script for easy setup.
- Added `npx clawke server <start|stop|restart|status>` commands for better server management.
- Enabled password manager auto-fill hints for login and signup inputs on mobile.

**[New Feature]** AI typing status indicators.
- Added smooth spinner and status text to indicate when the AI is processing or typing.
- Built-in bilingual changelog generation workflow.

**[Enhancement]** Gateway pipeline optimizations.
- Upgraded gateway protocol handling with detailed delivery tracking and message compaction.
- Centralized logger and comprehensive state documentation for gateways.

**[Bug Fix]** Comprehensive abort (stop generation) pipeline overhaul.
- Fixed 3-layer abort synchronization across client, server, and gateway.
- Cancel queued messages immediately upon abort to prevent them from executing later.
- Fixed issue where AI would incorrectly "remember" and refer to the user's aborted requests.
- Corrected account ID forwarding during abort operations.

**[Bug Fix]** Fixed concurrent message and delivery state issues.
- Fixed an issue where the LLM becomes unresponsive when multiple tasks are sent concurrently.
- Fixed duplicate messages bug by implementing `disableBlockStreaming` constraints.
- Resolved a sequence boundary error where the client would miss messages if `client_last_seq > server_currentSeq`.

## v1.1.3 (2026-04-15)

**[New Feature]** Multi-session support with per-conversation AI configuration.
- Each conversation can now be configured with its own AI gateway, model, system prompt, and temperature
- New conversation settings panel accessible from the chat screen
- Server-side conversation config storage with REST API (`/api/conversations/:id/config`)
- Gateway-authoritative model and skill queries — available models are fetched directly from the connected AI backend

**[New Feature]** Gateway selector for new conversations.
- Card-style UI with guided text for choosing which AI backend to use
- Displays connected account IDs with visual indicators

**[Enhancement]** Complete internationalization (i18n) for all screens.
- Full English/Chinese localization for settings, password change, and edge-case pages
- Global AppBar title centering and consistent font sizing (18sp)

**[Enhancement]** Desktop UI polish.
- Conversation list header alignment and spacing adjustments
- Unified AppBar actions padding across all screens
- Conversation settings sheet with full-screen system prompt editor

**[Bug Fix]** Fix cross-conversation message leakage — thinking blocks and messages now correctly route by `conversation_id`.

**[Bug Fix]** Fix port conflict detection on startup to prevent multiple frpc instances from spawning.

**[Bug Fix]** Fix Android 11+ unable to open privacy policy and terms of service links.

**[Architecture]** Server-side conversation auto-creation — conversations are now created server-side when a new `account_id` is first seen, removing client-side race conditions.

<!-- CHANGELOG_END -->
