"""Clawke channel — connects Hermes AIAgent to Clawke Server as an AI gateway.

Protocol reference: docs/GATEWAY_INTEGRATION.md

This channel runs as a standalone Python process sharing the Hermes Python
environment, connecting to Clawke Server's upstream WebSocket port (default
8766). It directly instantiates Hermes AIAgent with five callbacks mapped
to the CUP protocol:

  stream_delta_callback  →  agent_text_delta
  reasoning_callback     →  agent_thinking_delta / agent_thinking_done
  tool_progress_callback →  agent_tool_call / agent_tool_result
  clarify_callback       →  clarify_request / clarify_response
  approval (notify)      →  approval_request / approval_response

Architecture reference:
  - nanobot gateway (gateways/nanobot/clawke/clawke.py) — WS client pattern
  - hermes-webui (api/streaming.py) — AIAgent instantiation + callbacks
  - OpenClaw gateway (gateways/openclaw/clawke/src/gateway.ts) — streaming + abort
"""

from __future__ import annotations

import asyncio
import json
import logging
import os
import random
import sys
import threading
import time
from dataclasses import dataclass, field
from pathlib import Path
from typing import Any, Optional

import websockets

logger = logging.getLogger("clawke.hermes")

# ─── CUP Protocol Message Types (mirror of protocol.ts) ─────────────────────

class GatewayMessageType:
    """Gateway → Clawke Server (downstream: AI output)."""
    Identify = "identify"
    ModelsResponse = "models_response"
    SkillsResponse = "skills_response"

    AgentTyping = "agent_typing"
    AgentTextDelta = "agent_text_delta"
    AgentTextDone = "agent_text_done"
    AgentText = "agent_text"

    AgentMedia = "agent_media"

    AgentToolCall = "agent_tool_call"
    AgentToolResult = "agent_tool_result"

    AgentThinkingDelta = "agent_thinking_delta"
    AgentThinkingDone = "agent_thinking_done"

    AgentStatus = "agent_status"
    AgentTurnStats = "agent_turn_stats"

    ApprovalRequest = "approval_request"
    ClarifyRequest = "clarify_request"


class InboundMessageType:
    """Clawke Server → Gateway (upstream: user input / control)."""
    Chat = "chat"
    Abort = "abort"
    QueryModels = "query_models"
    QuerySkills = "query_skills"
    ApprovalResponse = "approval_response"
    ClarifyResponse = "clarify_response"
    TaskList = "task_list"
    TaskGet = "task_get"
    TaskCreate = "task_create"
    TaskUpdate = "task_update"
    TaskDelete = "task_delete"
    TaskSetEnabled = "task_set_enabled"
    TaskRun = "task_run"
    TaskRuns = "task_runs"
    TaskOutput = "task_output"


class AgentStatusValue:
    """agent_status message status field values."""
    Compacting = "compacting"
    Thinking = "thinking"
    Queued = "queued"


# ─── Exponential Backoff ─────────────────────────────────────────────────────

BACKOFF_FIRST_S = 0.1
BACKOFF_MAX_S = 10.0
BACKOFF_BASE = 2


def _backoff_delay(attempt: int) -> float:
    """Calculate exponential backoff delay with ±25% jitter."""
    exp = BACKOFF_FIRST_S * (BACKOFF_BASE ** attempt)
    capped = min(exp, BACKOFF_MAX_S)
    return capped * (0.75 + random.random() * 0.5)


# ─── Error Classification ────────────────────────────────────────────────────
# ⚠️ 关键词表需与 OpenClaw Gateway (gateway.ts _classifyError) 保持同步

_AUTH_KEYWORDS = ("api key", "authentication", "unauthorized", "403", "invalid_api_key")
_NET_KEYWORDS = ("timeout", "connect", "connection refused", "dns", "econnrefused")
_RATE_KEYWORDS = ("rate limit", "429", "too many requests", "quota")
_MODEL_KEYWORDS = ("model not found", "model_not_found", "does not exist")


def _classify_error(e: Exception) -> dict[str, str]:
    """Classify an exception into a structured error code for client-side i18n."""
    err_str = str(e).lower()
    detail = str(e)[:100]

    if any(kw in err_str for kw in _AUTH_KEYWORDS):
        return {"error_code": "auth_failed", "error_detail": detail}
    if any(kw in err_str for kw in _NET_KEYWORDS):
        return {"error_code": "network_error", "error_detail": detail}
    if any(kw in err_str for kw in _RATE_KEYWORDS):
        return {"error_code": "rate_limited", "error_detail": detail}
    if any(kw in err_str for kw in _MODEL_KEYWORDS):
        return {"error_code": "model_unavailable", "error_detail": detail}
    return {"error_code": "agent_error", "error_detail": detail}


# ─── Lazy imports for Hermes components ──────────────────────────────────────

_AIAgent = None
_SessionDB = None


def _get_ai_agent():
    """Lazily import AIAgent from hermes-agent."""
    global _AIAgent
    if _AIAgent is None:
        try:
            from run_agent import AIAgent
            _AIAgent = AIAgent
        except ImportError:
            logger.error("Failed to import AIAgent from run_agent. "
                         "Ensure hermes-agent is on sys.path.")
    return _AIAgent


def _get_session_db():
    """Lazily create a SessionDB instance."""
    global _SessionDB
    if _SessionDB is None:
        try:
            from hermes_state import SessionDB
            _SessionDB = SessionDB()
        except Exception as e:
            logger.warning("SessionDB init failed (session_search unavailable): %s", e)
    return _SessionDB



# ─── Message Sanitization ────────────────────────────────────────────────────

# Fields safe to pass to the LLM API (everything else is UI metadata)
_API_SAFE_MSG_KEYS = frozenset({
    'role', 'content', 'name', 'tool_calls', 'tool_call_id',
    'function_call', 'refusal',
})


def _sanitize_messages(messages: list[dict]) -> list[dict]:
    """Strip non-API fields and orphaned tool results from conversation history.

    Providers like Z.AI/GLM reject unknown fields; strict providers reject
    tool results without matching assistant tool_calls.
    """
    # Collect all valid tool_call_ids from assistant messages
    valid_ids: set[str] = set()
    for msg in messages:
        if not isinstance(msg, dict):
            continue
        if msg.get('role') == 'assistant':
            for tc in msg.get('tool_calls') or []:
                if isinstance(tc, dict):
                    tid = tc.get('id') or tc.get('call_id') or ''
                    if tid:
                        valid_ids.add(tid)

    # Build sanitized list
    clean = []
    for msg in messages:
        if not isinstance(msg, dict):
            continue
        role = msg.get('role')
        # Drop orphaned tool results
        if role == 'tool':
            tid = msg.get('tool_call_id') or ''
            if not tid or tid not in valid_ids:
                continue
        sanitized = {k: v for k, v in msg.items() if k in _API_SAFE_MSG_KEYS}
        if sanitized.get('role'):
            clean.append(sanitized)
    return clean


# ─── Gateway ─────────────────────────────────────────────────────────────────

@dataclass
class GatewayConfig:
    """Configuration for the Hermes Clawke Gateway."""
    ws_url: str = "ws://127.0.0.1:8766"
    account_id: str = "hermes"
    model: str = ""
    provider: str = ""
    base_url: str = ""
    toolsets: list[str] = field(default_factory=list)


class ClawkeHermesGateway:
    """Clawke gateway channel — runs inside Hermes process.

    Connects to Clawke Server via WebSocket, receives user messages,
    runs them through Hermes AIAgent with streaming callbacks, and
    sends responses back using the CUP protocol.
    """

    def __init__(self, config: GatewayConfig):
        self.config = config
        self._ws: Any = None
        self._running = False
        self._reconnect_attempt = 0
        self._loop: asyncio.AbstractEventLoop | None = None

        # Per-session state
        self._cancel_events: dict[str, threading.Event] = {}
        self._agents: dict[str, Any] = {}
        self._session_locks: dict[str, asyncio.Lock] = {}
        self._active_dispatches: set[asyncio.Task] = set()

        # Streaming state per conversation
        self._partial_texts: dict[str, str] = {}

        # Approval/Clarify pending requests (session_id → {event, result})
        self._pending_approvals: dict[str, dict] = {}
        self._pending_clarifies: dict[str, dict] = {}
        self._task_adapter: Any = None

    # ── Public API ───────────────────────────────────────────────────────

    async def start(self) -> None:
        """Start the gateway: connect and listen with auto-reconnect."""
        self._running = True
        self._loop = asyncio.get_event_loop()
        logger.info("Clawke Hermes Gateway starting → %s", self.config.ws_url)

        while self._running:
            try:
                await self._connect()
            except asyncio.CancelledError:
                break
            except Exception as e:
                logger.error("Clawke connection error: %s", e)

            if not self._running:
                break

            delay = _backoff_delay(self._reconnect_attempt)
            self._reconnect_attempt += 1
            logger.info("Reconnecting in %.1fs (attempt %d)",
                        delay, self._reconnect_attempt)
            await asyncio.sleep(delay)

    async def stop(self) -> None:
        """Stop the gateway gracefully."""
        self._running = False

        # 1. Unblock approval/clarify threads to prevent deadlocks
        for pending in self._pending_approvals.values():
            pending["event"].set()
        self._pending_approvals.clear()
        for pending in self._pending_clarifies.values():
            pending["event"].set()
        self._pending_clarifies.clear()

        # 2. Signal all running agents to exit early
        for cancel_event in self._cancel_events.values():
            cancel_event.set()

        # 3. Cancel active tasks and wait for completion (up to 5 drain rounds)
        max_drain_rounds = 5
        for _ in range(max_drain_rounds):
            tasks = [t for t in self._active_dispatches
                     if not t.done()]
            if not tasks:
                break
            for t in tasks:
                t.cancel()
            await asyncio.gather(*tasks, return_exceptions=True)
        self._active_dispatches.clear()

        # 4. Close WS last
        if self._ws:
            await self._ws.close()
            self._ws = None

        logger.info("Clawke Hermes Gateway stopped")

    # ── Connection ───────────────────────────────────────────────────────

    async def _connect(self) -> None:
        """Establish WebSocket connection and handle messages."""
        async with websockets.connect(
            self.config.ws_url,
            ping_interval=30,
            ping_timeout=10,
        ) as ws:
            self._ws = ws
            self._reconnect_attempt = 0
            logger.info("Connected to Clawke Server")

            # Handshake: identify
            await ws.send(json.dumps({
                "type": GatewayMessageType.Identify,
                "accountId": self.config.account_id,
            }))
            logger.info("Identified as account=%s", self.config.account_id)

            # Listen for inbound messages
            async for raw in ws:
                try:
                    msg = json.loads(raw)
                except (json.JSONDecodeError, TypeError):
                    continue

                msg_type = msg.get("type")

                if isinstance(msg_type, str) and msg_type.startswith("task_"):
                    await self._handle_task_command(msg)

                elif msg_type == InboundMessageType.Chat:
                    # MUST NOT await — the WS loop must stay free to receive
                    # approval_response / abort while the agent is running.
                    task = asyncio.ensure_future(self._dispatch_chat(msg))
                    # 跟踪活跃 dispatch，stop() 时可 cancel — Track for stop() cancellation
                    self._active_dispatches.add(task)
                    task.add_done_callback(self._active_dispatches.discard)

                elif msg_type == InboundMessageType.Abort:
                    self._handle_abort(msg)

                elif msg_type == InboundMessageType.QueryModels:
                    await self._handle_query_models()

                elif msg_type == InboundMessageType.QuerySkills:
                    await self._handle_query_skills()

                elif msg_type == InboundMessageType.ApprovalResponse:
                    self._handle_approval_response(msg)

                elif msg_type == InboundMessageType.ClarifyResponse:
                    self._handle_clarify_response(msg)

        self._ws = None
        logger.info("Disconnected from Clawke Server")

    # ── Message Dispatch (serial per-session queue) ──────────────────────

    async def _dispatch_chat(self, msg: dict) -> None:
        """Dispatch chat message with per-session serial execution."""
        sender_id = msg.get("conversation_id", "clawke_user")

        # Get or create per-session lock
        if sender_id not in self._session_locks:
            self._session_locks[sender_id] = asyncio.Lock()
        lock = self._session_locks[sender_id]

        # If session is busy, notify client
        if lock.locked():
            logger.info("⏳ Session %s busy, queuing message", sender_id)
            await self._send({
                "type": GatewayMessageType.AgentStatus,
                "status": AgentStatusValue.Queued,
                "account_id": self.config.account_id,
                "conversation_id": sender_id,
            })

        async with lock:
            # Check if abort was requested while queued
            cancel = self._cancel_events.get(sender_id)
            if cancel and cancel.is_set():
                logger.info("🚫 Session %s aborted while queued, dropping", sender_id)
                self._cancel_events.pop(sender_id, None)
                return
            await self._handle_chat(msg)

    async def _handle_chat(self, msg: dict) -> None:
        """Core: instantiate AIAgent, register callbacks, run conversation."""
        text = msg.get("text", "")
        sender_id = msg.get("conversation_id", "clawke_user")
        client_msg_id = msg.get("client_msg_id", f"clawke_{int(time.time() * 1000)}")
        msg_id = f"reply_{int(time.time() * 1000)}"
        thinking_msg_id = f"think_{msg_id}"

        # ── Prompt injection: system_prompt + skills_hint ─────────────
        system_prompt = msg.get("system_prompt", "")

        skills_hint = msg.get("skills_hint") or []
        if skills_hint:
            skill_names = ", ".join(skills_hint)
            skill_mode = msg.get("skill_mode", "priority")
            if skill_mode == "exclusive":
                system_prompt += (
                    f"\n\n[IMPORTANT] You are a dedicated tool assistant. "
                    f"You MUST use one of the following skills to complete each task, "
                    f"do not answer directly.\nAvailable skills: {skill_names}\n"
                    f"If the user's question does not clearly match a skill, "
                    f"pick the closest one."
                )
            else:
                system_prompt += (
                    f"\n\n[Hint] Prefer using the following skills "
                    f"when answering: {skill_names}"
                )
            logger.info("[ConvConfig] skills=%s, mode=%s", skill_names, skill_mode)

        if system_prompt:
            text = f"{text}\n\n---\n{system_prompt}"

        logger.info("📥 Inbound: %s (conv=%s)", text[:80], sender_id)

        # Create cancel event for this dispatch
        cancel_event = threading.Event()
        self._cancel_events[sender_id] = cancel_event

        # Streaming state
        has_streamed_text = False
        has_streamed_thinking = False
        full_text = ""
        reasoning_text = ""
        tool_calls: list[dict] = []
        tool_call_counter = 0

        # ── Callbacks → CUP Protocol ────────────────────────────────────

        def on_token(text_chunk: str | None) -> None:
            """stream_delta_callback → agent_text_delta."""
            nonlocal has_streamed_text, full_text
            if text_chunk is None or cancel_event.is_set():
                return
            has_streamed_text = True
            full_text += text_chunk
            self._partial_texts[sender_id] = full_text
            self._send_sync({
                "type": GatewayMessageType.AgentTextDelta,
                "message_id": msg_id,
                "delta": text_chunk,
                "account_id": self.config.account_id,
                "conversation_id": sender_id,
            })

        def on_reasoning(text_chunk: str | None) -> None:
            """reasoning_callback → agent_thinking_delta."""
            nonlocal has_streamed_thinking, reasoning_text
            if text_chunk is None or cancel_event.is_set():
                return
            has_streamed_thinking = True
            reasoning_text += str(text_chunk)
            self._send_sync({
                "type": GatewayMessageType.AgentThinkingDelta,
                "message_id": thinking_msg_id,
                "delta": str(text_chunk),
                "account_id": self.config.account_id,
                "conversation_id": sender_id,
            })

        def on_tool(*cb_args, **cb_kwargs) -> None:
            """tool_progress_callback → agent_tool_call / agent_tool_result."""
            nonlocal tool_call_counter, has_streamed_thinking
            if cancel_event.is_set():
                return

            # Parse variable-length callback arguments (same as WebUI)
            event_type = None
            name = None
            preview = None
            args = None

            if len(cb_args) >= 4:
                event_type, name, preview, args = cb_args[:4]
            elif len(cb_args) == 3:
                name, preview, args = cb_args
                event_type = "tool.started"
            elif len(cb_args) == 2:
                event_type, name = cb_args
            elif len(cb_args) == 1:
                name = cb_args[0]
                event_type = "tool.started"

            # Handle reasoning emitted via tool callback
            if event_type in ("reasoning.available", "_thinking"):
                reason_text = preview if event_type == "reasoning.available" else name
                if reason_text:
                    on_reasoning(str(reason_text))
                return

            if event_type in (None, "tool.started"):
                # Finalize previous thinking stream before tool card
                if has_streamed_thinking:
                    self._send_sync({
                        "type": GatewayMessageType.AgentThinkingDone,
                        "message_id": thinking_msg_id,
                        "account_id": self.config.account_id,
                        "conversation_id": sender_id,
                    })
                    has_streamed_thinking = False

                tool_call_counter += 1
                tool_call_id = f"{msg_id}_tool_{tool_call_counter}"
                tool_calls.append({
                    "name": name or "tool",
                    "id": tool_call_id,
                    "start_time": time.time(),
                })
                # Build compact args snapshot
                args_snap = {}
                if isinstance(args, dict):
                    for k, v in list(args.items())[:4]:
                        s = str(v)
                        args_snap[k] = s[:120] + ("..." if len(s) > 120 else "")

                self._send_sync({
                    "type": GatewayMessageType.AgentToolCall,
                    "message_id": msg_id,
                    "toolCallId": tool_call_id,
                    "toolName": name or "tool",
                    "toolTitle": str(preview or "")[:60],
                    "account_id": self.config.account_id,
                    "conversation_id": sender_id,
                })
                logger.info("🔧 Tool started: %s", name)

            elif event_type == "tool.completed":
                # Find matching tool call
                duration_ms = None
                tool_id = ""
                for tc in reversed(tool_calls):
                    if not tc.get("done") and (not name or tc["name"] == name):
                        tc["done"] = True
                        duration_ms = int((time.time() - tc["start_time"]) * 1000)
                        tool_id = tc["id"]
                        break

                self._send_sync({
                    "type": GatewayMessageType.AgentToolResult,
                    "message_id": msg_id,
                    "toolCallId": tool_id,
                    "toolName": name or "tool",
                    "durationMs": duration_ms,
                    "account_id": self.config.account_id,
                    "conversation_id": sender_id,
                })
                logger.info("🔧 Tool completed: %s (%sms)", name, duration_ms)

        # ── Send typing indicator ───────────────────────────────────────

        await self._send({
            "type": GatewayMessageType.AgentTyping,
            "account_id": self.config.account_id,
            "conversation_id": sender_id,
        })

        # ── Instantiate AIAgent and run (in thread) ─────────────────────

        AIAgent = _get_ai_agent()
        if AIAgent is None:
            await self._send({
                "type": GatewayMessageType.AgentText,
                "message_id": msg_id,
                "text": "⚠️ Hermes AIAgent not available. Check hermes-agent installation.",
                "account_id": self.config.account_id,
                "conversation_id": sender_id,
            })
            return

        session_db = _get_session_db()

        # Resolve model/provider (priority: msg override > config > Hermes defaults)
        resolved_model = msg.get("model_override") or self.config.model
        resolved_provider = msg.get("provider_override") or self.config.provider
        resolved_base_url = self.config.base_url
        resolved_api_key = None

        try:
            from hermes_cli.runtime_provider import resolve_runtime_provider
            rt = resolve_runtime_provider(requested=resolved_provider or None)
            resolved_api_key = rt.get("api_key")
            if not resolved_provider:
                resolved_provider = rt.get("provider", "")
            if not resolved_model:
                resolved_model = rt.get("model", "")
            if not resolved_base_url:
                resolved_base_url = rt.get("base_url", "")
        except Exception as e:
            logger.warning("resolve_runtime_provider failed: %s", e)

        # Resolve toolsets (priority: msg override > config > Hermes defaults)
        toolsets = self.config.toolsets or None
        if not toolsets:
            try:
                from api.config import _resolve_cli_toolsets, get_config
                cfg = get_config()
                toolsets = _resolve_cli_toolsets(cfg)
            except Exception:
                toolsets = None

        # ── Clarify callback (blocking — waits for client response) ────

        def on_clarify(question, choices):
            """clarify_callback → clarify_request, blocks until response."""
            timeout = 120  # seconds
            choices_list = [str(c) for c in (choices or [])]

            # Push clarify_request to client
            self._send_sync({
                "type": GatewayMessageType.ClarifyRequest,
                "conversation_id": sender_id,
                "account_id": self.config.account_id,
                "question": str(question or ""),
                "choices": choices_list,
                "message_id": msg_id,
            })

            # Create pending entry with Event
            evt = threading.Event()
            self._pending_clarifies[sender_id] = {
                "event": evt, "result": None,
            }

            # Wait for response or timeout
            deadline = time.monotonic() + timeout
            while True:
                if cancel_event.is_set():
                    self._pending_clarifies.pop(sender_id, None)
                    return (
                        "The user did not provide a response within the time limit. "
                        "Use your best judgement to make the choice and proceed."
                    )
                remaining = deadline - time.monotonic()
                if remaining <= 0:
                    self._pending_clarifies.pop(sender_id, None)
                    return (
                        "The user did not provide a response within the time limit. "
                        "Use your best judgement to make the choice and proceed."
                    )
                if evt.wait(timeout=min(1.0, remaining)):
                    result = str(self._pending_clarifies.get(sender_id, {}).get("result", "")).strip()
                    self._pending_clarifies.pop(sender_id, None)
                    return (
                        result
                        or "The user did not provide a response within the time limit. "
                           "Use your best judgement to make the choice and proceed."
                    )

        def _run_agent():
            """Run AIAgent.run_conversation in a background thread."""
            nonlocal full_text

            # ── Set gateway environment so approval/terminal checks work ──
            # Without HERMES_GATEWAY_SESSION, approval.check_all_command_guards
            # returns approved=True unconditionally (line 714 in approval.py).
            os.environ["HERMES_GATEWAY_SESSION"] = "1"

            # Set session key via BOTH mechanisms so it's visible in all
            # threads (AIAgent spawns child threads for tool execution,
            # contextvars won't propagate there).
            _session_token = None
            _prev_session_key = os.environ.get("HERMES_SESSION_KEY")
            os.environ["HERMES_SESSION_KEY"] = sender_id
            try:
                from tools.approval import set_current_session_key
                _session_token = set_current_session_key(sender_id)
            except ImportError:
                pass

            # Register approval notify callback
            _unreg_approval = None
            try:
                from tools.approval import (
                    register_gateway_notify as _reg_approval,
                    unregister_gateway_notify as _unreg_approval_fn,
                )

                def _on_approval_notify(approval_data):
                    """Push approval request to client via WS."""
                    if cancel_event.is_set():
                        return
                    # Create pending entry
                    evt = threading.Event()
                    self._pending_approvals[sender_id] = {
                        "event": evt, "result": None,
                    }
                    self._send_sync({
                        "type": GatewayMessageType.ApprovalRequest,
                        "conversation_id": sender_id,
                        "account_id": self.config.account_id,
                        "message_id": msg_id,
                        "command": approval_data.get("command", ""),
                        "description": approval_data.get("description", ""),
                        "pattern_keys": approval_data.get("pattern_keys", []),
                    })

                _reg_approval(sender_id, _on_approval_notify)
                _unreg_approval = lambda: _unreg_approval_fn(sender_id)
            except ImportError:
                logger.debug("Approval module not available")

            try:
                agent = AIAgent(
                    model=resolved_model,
                    provider=resolved_provider,
                    base_url=resolved_base_url or None,
                    api_key=resolved_api_key,
                    platform="cli",
                    quiet_mode=True,
                    enabled_toolsets=toolsets,
                    session_id=sender_id,
                    session_db=session_db,
                    stream_delta_callback=on_token,
                    reasoning_callback=on_reasoning,
                    tool_progress_callback=on_tool,
                    clarify_callback=on_clarify,
                )

                # Store agent for abort access
                self._agents[sender_id] = agent

                # Check for pre-flight cancel
                if cancel_event.is_set():
                    return None

                # Load conversation history from SessionDB (Hermes auto-persists
                # messages after each turn via _flush_messages_to_session_db).
                # This is the canonical approach — same as WebUI's s.messages
                # but backed by SQLite instead of in-memory state.
                history = []
                if session_db:
                    try:
                        history = session_db.get_messages_as_conversation(sender_id)
                        logger.info("📚 Loaded %d history messages from SessionDB", len(history))
                    except Exception as e:
                        logger.warning("Failed to load history from SessionDB: %s", e)

                result = agent.run_conversation(
                    user_message=text,
                    conversation_history=_sanitize_messages(history),
                    task_id=sender_id,
                )

                return result

            except Exception as e:
                logger.error("AIAgent.run_conversation failed: %s", e, exc_info=True)
                classified = _classify_error(e)
                return {"error": classified["error_detail"],
                        "error_code": classified["error_code"],
                        "error_detail": classified["error_detail"]}
            finally:
                self._agents.pop(sender_id, None)
                self._pending_approvals.pop(sender_id, None)
                self._pending_clarifies.pop(sender_id, None)
                if _unreg_approval:
                    try:
                        _unreg_approval()
                    except Exception:
                        pass
                # Reset approval session key
                if _session_token is not None:
                    try:
                        from tools.approval import reset_current_session_key
                        reset_current_session_key(_session_token)
                    except Exception:
                        pass
                # Restore env-level session key
                if _prev_session_key is not None:
                    os.environ["HERMES_SESSION_KEY"] = _prev_session_key
                else:
                    os.environ.pop("HERMES_SESSION_KEY", None)

        # Run in thread pool to avoid blocking the event loop
        loop = asyncio.get_event_loop()
        try:
            result = await loop.run_in_executor(None, _run_agent)
        except Exception as e:
            logger.error("Agent execution failed: %s", e)
            result = {"error": str(e)}

        # Clean up cancel event
        self._cancel_events.pop(sender_id, None)
        self._partial_texts.pop(sender_id, None)

        # ── Check for cancel during execution ───────────────────────────

        if cancel_event.is_set():
            logger.info("🚫 Agent cancelled for %s", sender_id)
            return

        # ── Finalize thinking stream (if still open) ────────────────────

        if has_streamed_thinking:
            await self._send({
                "type": GatewayMessageType.AgentThinkingDone,
                "message_id": thinking_msg_id,
                "account_id": self.config.account_id,
                "conversation_id": sender_id,
            })

        # ── Send completion ─────────────────────────────────────────────

        final_text = full_text
        if result and isinstance(result, dict):
            # Prefer final_response from result if available
            final_text = result.get("final_response", full_text) or full_text

        error = result.get("error") if isinstance(result, dict) else None

        if has_streamed_text:
            # Send remaining delta (if any) + done signal
            await self._send({
                "type": GatewayMessageType.AgentTextDone,
                "message_id": msg_id,
                "fullText": final_text,
                "account_id": self.config.account_id,
                "conversation_id": sender_id,
                "model": resolved_model,
                "provider": resolved_provider,
            })
            logger.info("📤 Reply done (stream): %s", final_text[:80])

        elif final_text.strip():
            # Non-streaming fallback
            await self._send({
                "type": GatewayMessageType.AgentText,
                "message_id": msg_id,
                "text": final_text,
                "account_id": self.config.account_id,
                "conversation_id": sender_id,
                "model": resolved_model,
                "provider": resolved_provider,
            })
            logger.info("📤 Reply done (full): %s", final_text[:80])

        else:
            # No reply generated — send structured error for client i18n
            err_code = (result.get("error_code", "agent_error")
                        if isinstance(result, dict) else "no_reply")
            err_detail = (result.get("error_detail", "")
                          if isinstance(result, dict) else "")
            await self._send({
                "type": GatewayMessageType.AgentText,
                "message_id": msg_id,
                "text": err_detail or f"⚠️ [{err_code}]",
                "error_code": err_code,
                "error_detail": err_detail,
                "account_id": self.config.account_id,
                "conversation_id": sender_id,
            })
            logger.warning("📤 No reply, sent error_code=%s", err_code)

        # ── Tool stats ──────────────────────────────────────────────────

        if tool_calls:
            await self._send({
                "type": GatewayMessageType.AgentTurnStats,
                "message_id": msg_id,
                "toolCallCount": len(tool_calls),
                "tools": [tc["name"] for tc in tool_calls],
                "account_id": self.config.account_id,
                "conversation_id": sender_id,
            })

    # ── Abort ────────────────────────────────────────────────────────────

    def _handle_abort(self, msg: dict) -> None:
        """Handle abort request: cancel event + agent.interrupt()."""
        sender_id = msg.get("conversation_id", "clawke_user")
        logger.info("📥 Abort request: conversation=%s", sender_id)

        # Set cancel event
        cancel = self._cancel_events.get(sender_id)
        if cancel:
            cancel.set()

        # Interrupt agent if running
        agent = self._agents.get(sender_id)
        if agent:
            try:
                agent.interrupt("Cancelled by user")
                logger.info("📥 agent.interrupt() called for %s", sender_id)
            except Exception as e:
                logger.warning("agent.interrupt() failed: %s", e)

    def _handle_approval_response(self, msg: dict) -> None:
        """Route approval_response from client to waiting thread."""
        sender_id = msg.get("conversation_id", "")
        choice = msg.get("choice", "once")  # once|session|always|deny
        logger.info("📥 Approval response: %s → %s", sender_id, choice)

        # Route to Hermes approval system (unblocks the waiting agent thread)
        try:
            from tools.approval import resolve_gateway_approval
            resolved = resolve_gateway_approval(sender_id, choice)
            logger.info("📥 Resolved %d pending approval(s) for %s", resolved, sender_id)
        except Exception as e:
            logger.warning("resolve_gateway_approval failed: %s", e)

        # Also set the legacy pending event (for our own _pending_approvals)
        pending = self._pending_approvals.get(sender_id)
        if pending:
            pending["result"] = choice
            pending["event"].set()
        else:
            logger.warning("📥 Approval response for unknown session: %s", sender_id)

    def _handle_clarify_response(self, msg: dict) -> None:
        """Route clarify_response from client to waiting on_clarify thread."""
        sender_id = msg.get("conversation_id", "")
        response_text = msg.get("response", "")
        pending = self._pending_clarifies.get(sender_id)
        if pending:
            pending["result"] = response_text
            pending["event"].set()
            logger.info("📥 Clarify response: %s → %s", sender_id, response_text[:40])
        else:
            logger.warning("📥 Clarify response for unknown session: %s", sender_id)

    # ── Task Command Handler ────────────────────────────────────────────

    async def _handle_task_command(self, msg: dict) -> None:
        """Route Clawke task commands to Hermes cron through the adapter."""
        msg_type = str(msg.get("type") or "")
        request_id = msg.get("request_id", "")
        response: dict[str, Any] = {
            "type": f"{msg_type}_response",
            "request_id": request_id,
        }

        try:
            adapter = self._get_task_adapter()
            account_id = msg.get("account_id") or self.config.account_id
            task_id = msg.get("task_id", "")

            if msg_type == InboundMessageType.TaskList:
                response.update({"ok": True, "tasks": adapter.list_tasks(account_id)})
            elif msg_type == InboundMessageType.TaskGet:
                response.update({"ok": True, "task": adapter.get_task(account_id, task_id)})
            elif msg_type == InboundMessageType.TaskCreate:
                response.update({"ok": True, "task": adapter.create_task(account_id, msg.get("task") or {})})
            elif msg_type == InboundMessageType.TaskUpdate:
                response.update({"ok": True, "task": adapter.update_task(account_id, task_id, msg.get("patch") or {})})
            elif msg_type == InboundMessageType.TaskDelete:
                response.update({"ok": True, "deleted": adapter.delete_task(task_id)})
            elif msg_type == InboundMessageType.TaskSetEnabled:
                response.update({"ok": True, "task": adapter.set_enabled(account_id, task_id, bool(msg.get("enabled")))})
            elif msg_type == InboundMessageType.TaskRun:
                response.update({"ok": True, "run": adapter.run_task(task_id)})
            elif msg_type == InboundMessageType.TaskRuns:
                response.update({"ok": True, "runs": adapter.list_runs(task_id)})
            elif msg_type == InboundMessageType.TaskOutput:
                response.update({"ok": True, "output": adapter.get_output(task_id, msg.get("run_id", ""))})
            else:
                raise ValueError(f"Unsupported task command: {msg_type}")
        except Exception as e:
            logger.warning("Task command failed: type=%s error=%s", msg_type, e)
            response.update({
                "ok": False,
                "error": "task_error",
                "message": str(e),
            })

        await self._send(response)

    def _get_task_adapter(self):
        """Lazily instantiate the Hermes task adapter."""
        if self._task_adapter is None:
            from task_adapter import HermesTaskAdapter
            self._task_adapter = HermesTaskAdapter()
        return self._task_adapter

    # ── Query Handlers ───────────────────────────────────────────────────

    async def _handle_query_models(self) -> None:
        """Return available models from Hermes runtime + config.yaml + .env discovery.

        Strategy (mirrors hermes-webui's get_available_models):
        1. resolve_runtime_provider() → current active model
        2. hermes_cli.models.list_available_providers() → providers with valid credentials
        3. config.yaml → model.default + providers.<id>.models
        4. .env API Key scan → infer default models (fallback)
        """
        models: list[str] = []
        seen: set[str] = set()

        def _add(m: str) -> None:
            if m and m not in seen:
                seen.add(m)
                models.append(m)

        # 1. Current runtime model (the one Hermes is actually using)
        try:
            from hermes_cli.runtime_provider import resolve_runtime_provider
            rt = resolve_runtime_provider()
            _add(rt.get("model", ""))
        except Exception:
            pass

        # 2. list_available_providers() — Hermes native auth-aware provider detection
        #    This checks OAuth tokens, Copilot credentials, etc. that .env scan can't see
        try:
            from hermes_cli.models import list_available_providers
            available = list_available_providers()
            # available is typically a list of provider info dicts
            if isinstance(available, (list, tuple)):
                for prov in available:
                    if isinstance(prov, dict):
                        _add(prov.get("model", ""))
                        _add(prov.get("default_model", ""))
                    elif isinstance(prov, str):
                        _add(prov)
        except ImportError:
            logger.debug("hermes_cli.models.list_available_providers not available")
        except Exception as e:
            logger.debug("list_available_providers failed: %s", e)

        hermes_home = Path(os.environ.get("HERMES_HOME", "~/.hermes")).expanduser()

        # 3. config.yaml: model.default + providers section
        try:
            import yaml
            cfg_path = hermes_home / "config.yaml"
            if cfg_path.exists():
                with open(cfg_path) as f:
                    cfg = yaml.safe_load(f) or {}

                # model.default or model.model
                model_cfg = cfg.get("model") or {}
                _add(model_cfg.get("default", ""))
                _add(model_cfg.get("model", ""))

                # providers.<id>.models.<model> section
                providers = cfg.get("providers") or {}
                for _pid, pcfg in providers.items():
                    if isinstance(pcfg, dict):
                        pmodels = pcfg.get("models") or {}
                        if isinstance(pmodels, dict):
                            for mname in pmodels:
                                _add(f"{_pid}/{mname}" if "/" not in mname else mname)
                        elif isinstance(pmodels, list):
                            for mname in pmodels:
                                _add(str(mname))
        except Exception as e:
            logger.debug("config.yaml model scan failed: %s", e)

        # 4. .env: infer available providers from API keys (fallback)
        _PROVIDER_DEFAULTS = {
            "ANTHROPIC_API_KEY":    ("anthropic", "claude-sonnet-4"),
            "OPENROUTER_API_KEY":   ("openrouter", "anthropic/claude-sonnet-4"),
            "OPENAI_API_KEY":       ("openai", "gpt-4o"),
            "DEEPSEEK_API_KEY":     ("deepseek", "deepseek-chat"),
            "GOOGLE_API_KEY":       ("gemini", "gemini-2.5-pro"),
            "GEMINI_API_KEY":       ("gemini", "gemini-2.5-pro"),
            "DASHSCOPE_API_KEY":    ("alibaba", "qwen-max"),
            "GLM_API_KEY":          ("zai", "glm-4"),
            "HF_TOKEN":            ("huggingface", "meta-llama/Llama-3-70b"),
        }
        try:
            env_path = hermes_home / ".env"
            env_keys: set[str] = set()
            if env_path.exists():
                for line in env_path.read_text().splitlines():
                    line = line.strip()
                    if line and not line.startswith("#") and "=" in line:
                        env_keys.add(line.split("=", 1)[0].strip())

            for env_var, (_prov, default_model) in _PROVIDER_DEFAULTS.items():
                if env_var in env_keys or env_var in os.environ:
                    _add(default_model)
        except Exception as e:
            logger.debug(".env model scan failed: %s", e)

        await self._send({
            "type": GatewayMessageType.ModelsResponse,
            "models": models,
        })
        logger.info("📤 Models response: %d models", len(models))

    async def _handle_query_skills(self) -> None:
        """Return available Hermes skills.

        Strategy (mirrors hermes-webui):
        1. tools.skills_tool.skills_list() — native Hermes API (respects disabled skills)
        2. Manual scan ~/.hermes/skills/ — fallback if import fails
        """
        skills: list[dict] = []

        # 1. Try Hermes native skills_list() — same as hermes-webui uses
        try:
            from tools.skills_tool import skills_list as _skills_list
            import json as _json
            raw = _skills_list()
            data = _json.loads(raw) if isinstance(raw, str) else raw
            raw_skills = data.get("skills", []) if isinstance(data, dict) else data
            for s in raw_skills:
                if isinstance(s, dict):
                    skills.append({
                        "name": s.get("name", ""),
                        "description": s.get("description", s.get("name", "")),
                    })
            logger.info("skills_list() returned %d skills", len(skills))
        except ImportError:
            logger.warning("tools.skills_tool not importable, falling back to manual scan")
        except Exception as e:
            logger.warning("skills_list() failed: %s, falling back to manual scan", e)

        # 2. Fallback: recursive scan ~/.hermes/skills/
        #    Hermes skills 使用嵌套结构：category/skill/SKILL.md
        #    需要递归查找所有 SKILL.md 文件
        if not skills:
            try:
                import re
                hermes_home = Path(os.environ.get("HERMES_HOME", "~/.hermes")).expanduser()
                skills_dir = hermes_home / "skills"
                if skills_dir.is_dir():
                    # 递归查找所有 SKILL.md
                    for skill_md in skills_dir.rglob("SKILL.md"):
                        skill_dir = skill_md.parent
                        content = skill_md.read_text(errors="ignore")
                        name = skill_dir.name
                        desc = skill_dir.name
                        fm_match = re.search(r"^---\s*\n([\s\S]*?)\n---", content)
                        if fm_match:
                            name_match = re.search(r"name:\s*(.+)", fm_match.group(1), re.I)
                            if name_match:
                                name = name_match.group(1).strip()
                            desc_match = re.search(r"description:\s*(.+)", fm_match.group(1), re.I)
                            if desc_match:
                                desc = desc_match.group(1).strip()
                        skills.append({"name": name, "description": desc})
                    logger.info("Manual scan found %d skills in %s", len(skills), skills_dir)
            except Exception as e:
                logger.warning("Skills manual scan failed: %s", e)

        await self._send({
            "type": GatewayMessageType.SkillsResponse,
            "skills": skills,
        })
        logger.info("📤 Skills response: %d skills", len(skills))

    # ── WebSocket Send Helpers ───────────────────────────────────────────

    async def _send(self, data: dict, max_retries: int = 3) -> None:
        """Send JSON message to Clawke Server (async, with retry)."""
        if not self._ws:
            logger.warning("WS not connected, dropping: type=%s", data.get("type"))
            return
        for attempt in range(max_retries):
            try:
                await self._ws.send(json.dumps(data, ensure_ascii=False))
                return
            except websockets.ConnectionClosed:
                if attempt < max_retries - 1:
                    await asyncio.sleep(0.3 * (attempt + 1))
                    logger.debug("Send retry %d/%d: type=%s", attempt + 1, max_retries, data.get("type"))
                else:
                    logger.error("Send failed after %d retries: type=%s", max_retries, data.get("type"))
            except Exception as e:
                logger.error("Send failed: type=%s, error=%s", data.get("type"), e)
                return

    def _send_sync(self, data: dict) -> None:
        """Send JSON message from a synchronous callback (thread-safe).

        Called from AIAgent callbacks which run in a background thread.
        Uses run_coroutine_threadsafe to schedule the send on the event loop.
        """
        if not self._ws or not self._loop:
            return
        try:
            future = asyncio.run_coroutine_threadsafe(
                self._send(data), self._loop
            )
            # Don't block waiting — fire and forget
            future.add_done_callback(
                lambda f: f.exception() and logger.debug("send_sync error: %s", f.exception())
            )
        except Exception as e:
            logger.debug("_send_sync scheduling failed: %s", e)
