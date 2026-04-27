"""Automated tests for ClawkeHermesGateway.

Tests CUP protocol message generation, callback → message mapping,
abort logic, serial queue, and approval/clarify bridging.

Run:
    cd gateways/hermes/clawke
    python3 -m pytest test_clawke_channel.py -v
"""

from __future__ import annotations

import asyncio
import json
import threading
import time
from dataclasses import dataclass
from typing import Any
from unittest.mock import AsyncMock, MagicMock, patch

import pytest

# ── Import the module under test ────────────────────────────────────────────
from clawke_channel import (
    ClawkeHermesGateway,
    GatewayConfig,
    GatewayMessageType,
    InboundMessageType,
    AgentStatusValue,
    _backoff_delay,
    _sanitize_messages,
)


# ── Fixtures ────────────────────────────────────────────────────────────────

@pytest.fixture
def config():
    """Default gateway config for tests."""
    return GatewayConfig(
        ws_url="ws://127.0.0.1:8766",
        account_id="test_hermes",
        model="test-model",
        provider="test-provider",
    )


@pytest.fixture
def gateway(config):
    """Fresh gateway instance with mocked WS."""
    gw = ClawkeHermesGateway(config)
    gw._ws = AsyncMock()
    gw._loop = asyncio.get_event_loop()
    return gw


@pytest.fixture
def sent_messages(gateway):
    """Capture all messages sent through gateway._send."""
    messages = []
    original_send = gateway._send

    async def capture_send(data):
        messages.append(data)
        # Don't actually send
    gateway._send = capture_send

    # Also override _send_sync for sync callbacks
    def capture_send_sync(data):
        messages.append(data)
    gateway._send_sync = capture_send_sync

    return messages


# ── Protocol Message Type Tests ─────────────────────────────────────────────

class TestProtocolTypes:
    """Verify CUP protocol message type constants."""

    def test_gateway_message_types(self):
        assert GatewayMessageType.Identify == "identify"
        assert GatewayMessageType.AgentTextDelta == "agent_text_delta"
        assert GatewayMessageType.AgentTextDone == "agent_text_done"
        assert GatewayMessageType.AgentThinkingDelta == "agent_thinking_delta"
        assert GatewayMessageType.AgentThinkingDone == "agent_thinking_done"
        assert GatewayMessageType.AgentToolCall == "agent_tool_call"
        assert GatewayMessageType.AgentToolResult == "agent_tool_result"
        assert GatewayMessageType.ApprovalRequest == "approval_request"
        assert GatewayMessageType.ClarifyRequest == "clarify_request"

    def test_inbound_message_types(self):
        assert InboundMessageType.Chat == "chat"
        assert InboundMessageType.Abort == "abort"
        assert InboundMessageType.QueryModels == "query_models"
        assert InboundMessageType.QuerySkills == "query_skills"
        assert InboundMessageType.ApprovalResponse == "approval_response"
        assert InboundMessageType.ClarifyResponse == "clarify_response"


# ── Backoff Tests ───────────────────────────────────────────────────────────

class TestBackoff:
    """Test exponential backoff with jitter."""

    def test_first_attempt_is_small(self):
        delay = _backoff_delay(0)
        assert 0.05 <= delay <= 0.15  # 0.1 ± 25%

    def test_increases_exponentially(self):
        d0 = _backoff_delay(0)
        d1 = _backoff_delay(1)
        d2 = _backoff_delay(2)
        # Median should roughly double each time
        assert d1 > d0 * 0.5
        assert d2 > d1 * 0.5

    def test_caps_at_max(self):
        delay = _backoff_delay(100)
        assert delay <= 10.0 * 1.5  # max with jitter

    def test_jitter_varies(self):
        """Multiple calls produce different values (non-deterministic)."""
        delays = {_backoff_delay(3) for _ in range(20)}
        assert len(delays) > 1, "Jitter should produce varying delays"


class TestMessageSanitization:
    """Test conversation history cleanup before Hermes agent replay."""

    def test_preserves_reasoning_fields_for_deepseek_v4_replay(self):
        history = [
            {"role": "user", "content": "hello", "ui_only": True},
            {
                "role": "assistant",
                "content": "answer",
                "reasoning": "thinking trace",
                "reasoning_details": [{"type": "reasoning", "text": "thinking trace"}],
                "codex_reasoning_items": [{"id": "r1"}],
                "ui_message_id": "msg_1",
            },
        ]

        sanitized = _sanitize_messages(history)

        assert sanitized == [
            {"role": "user", "content": "hello"},
            {
                "role": "assistant",
                "content": "answer",
                "reasoning": "thinking trace",
                "reasoning_details": [{"type": "reasoning", "text": "thinking trace"}],
                "codex_reasoning_items": [{"id": "r1"}],
            },
        ]


# ── Gateway Init Tests ──────────────────────────────────────────────────────

class TestGatewayInit:
    """Test gateway initialization."""

    def test_default_config(self):
        cfg = GatewayConfig()
        assert cfg.ws_url == "ws://127.0.0.1:8766"
        assert cfg.account_id == "hermes"
        assert cfg.model == ""
        assert cfg.provider == ""
        assert cfg.toolsets == []

    def test_custom_config(self, config):
        assert config.account_id == "test_hermes"
        assert config.model == "test-model"

    def test_gateway_initial_state(self, gateway):
        assert gateway._running is False
        assert len(gateway._cancel_events) == 0
        assert len(gateway._agents) == 0
        assert len(gateway._session_locks) == 0
        assert len(gateway._pending_approvals) == 0
        assert len(gateway._pending_clarifies) == 0


# ── Send Tests ──────────────────────────────────────────────────────────────

class TestSend:
    """Test WebSocket send mechanics."""

    @pytest.mark.asyncio
    async def test_send_serializes_json(self, gateway):
        gateway._ws = AsyncMock()
        await gateway._send({"type": "test", "data": "hello"})
        gateway._ws.send.assert_called_once()
        sent = json.loads(gateway._ws.send.call_args[0][0])
        assert sent["type"] == "test"
        assert sent["data"] == "hello"

    @pytest.mark.asyncio
    async def test_send_handles_no_ws(self, gateway):
        gateway._ws = None
        # Should not raise
        await gateway._send({"type": "test"})

    @pytest.mark.asyncio
    async def test_send_ensures_ascii_false(self, gateway):
        gateway._ws = AsyncMock()
        await gateway._send({"text": "中文测试"})
        sent_raw = gateway._ws.send.call_args[0][0]
        assert "中文测试" in sent_raw  # Not escaped


# ── Abort Tests ─────────────────────────────────────────────────────────────

class TestAbort:
    """Test abort/cancel mechanism."""

    def test_abort_sets_cancel_event(self, gateway):
        evt = threading.Event()
        gateway._cancel_events["conv1"] = evt
        gateway._handle_abort({"conversation_id": "conv1"})
        assert evt.is_set()

    def test_abort_calls_agent_interrupt(self, gateway):
        mock_agent = MagicMock()
        gateway._agents["conv1"] = mock_agent
        evt = threading.Event()
        gateway._cancel_events["conv1"] = evt

        gateway._handle_abort({"conversation_id": "conv1"})

        mock_agent.interrupt.assert_called_once_with("Cancelled by user")
        assert evt.is_set()

    def test_abort_handles_missing_session(self, gateway):
        # Should not raise
        gateway._handle_abort({"conversation_id": "nonexistent"})

    def test_abort_handles_interrupt_failure(self, gateway):
        mock_agent = MagicMock()
        mock_agent.interrupt.side_effect = RuntimeError("oops")
        gateway._agents["conv1"] = mock_agent
        gateway._cancel_events["conv1"] = threading.Event()

        # Should not raise
        gateway._handle_abort({"conversation_id": "conv1"})


# ── Approval/Clarify Response Routing Tests ─────────────────────────────────

class TestApprovalClarifyRouting:
    """Test approval_response and clarify_response routing."""

    def test_clarify_response_wakes_pending(self, gateway):
        evt = threading.Event()
        gateway._pending_clarifies["conv1"] = {"event": evt, "result": None}

        gateway._handle_clarify_response({
            "conversation_id": "conv1",
            "response": "Option A",
        })

        assert evt.is_set()
        # pending should have result set before pop
        # (it's popped by the on_clarify loop after reading)

    def test_clarify_response_unknown_session(self, gateway):
        # Should not raise
        gateway._handle_clarify_response({
            "conversation_id": "unknown",
            "response": "test",
        })

    def test_approval_response_wakes_pending(self, gateway):
        evt = threading.Event()
        gateway._pending_approvals["conv1"] = {"event": evt, "result": None}

        with patch.dict("sys.modules", {"tools": MagicMock(), "tools.approval": MagicMock()}):
            gateway._handle_approval_response({
                "conversation_id": "conv1",
                "choice": "once",
            })

        assert evt.is_set()

    def test_approval_response_unknown_session(self, gateway):
        # Should not raise
        gateway._handle_approval_response({
            "conversation_id": "unknown",
            "choice": "deny",
        })


# ── Dispatch Queue Tests ────────────────────────────────────────────────────

class TestDispatchQueue:
    """Test per-session serial execution queue."""

    @pytest.mark.asyncio
    async def test_creates_session_lock(self, gateway, sent_messages):
        """First message to a session creates a lock."""
        # Mock _handle_chat to avoid actually running agent
        gateway._handle_chat = AsyncMock()
        await gateway._dispatch_chat({"conversation_id": "conv1", "text": "hi"})
        assert "conv1" in gateway._session_locks

    @pytest.mark.asyncio
    async def test_aborted_while_queued_is_dropped(self, gateway, sent_messages):
        """Message aborted while queued should be dropped."""
        gateway._handle_chat = AsyncMock()

        # Pre-set cancel event
        evt = threading.Event()
        evt.set()
        gateway._cancel_events["conv2"] = evt

        await gateway._dispatch_chat({"conversation_id": "conv2", "text": "drop me"})
        gateway._handle_chat.assert_not_called()


# ── Query Handlers Tests ────────────────────────────────────────────────────

class TestQueryHandlers:
    """Test query_models and query_skills responses."""

    @pytest.mark.asyncio
    async def test_query_models_response(self, gateway, sent_messages):
        with patch.dict("sys.modules", {
            "hermes_cli": MagicMock(),
            "hermes_cli.runtime_provider": MagicMock(),
        }):
            # Mock resolve_runtime_provider to return a model
            import sys
            sys.modules["hermes_cli.runtime_provider"].resolve_runtime_provider = (
                lambda: {"model": "claude-3", "provider": "anthropic"}
            )
            await gateway._handle_query_models()

        assert len(sent_messages) == 1
        assert sent_messages[0]["type"] == GatewayMessageType.ModelsResponse
        assert "models" in sent_messages[0]

    @pytest.mark.asyncio
    async def test_query_skills_response(self, gateway, sent_messages):
        await gateway._handle_query_skills()
        assert len(sent_messages) == 1
        assert sent_messages[0]["type"] == GatewayMessageType.SkillsResponse
        assert "skills" in sent_messages[0]


# ── Callback → CUP Protocol Mapping Tests (Integration) ────────────────────

class TestCallbackMapping:
    """Test AIAgent callback → CUP protocol message mapping.

    These tests exercise the callback closures defined inside _handle_chat
    by calling _handle_chat with a mocked AIAgent.
    """

    @pytest.mark.asyncio
    async def test_stream_token_generates_text_delta(self, gateway, sent_messages):
        """stream_delta_callback should produce agent_text_delta messages."""
        captured_callbacks = {}

        class MockAIAgent:
            def __init__(self, **kwargs):
                captured_callbacks["on_token"] = kwargs.get("stream_delta_callback")
                captured_callbacks["on_reasoning"] = kwargs.get("reasoning_callback")
                captured_callbacks["on_tool"] = kwargs.get("tool_progress_callback")
                captured_callbacks["on_clarify"] = kwargs.get("clarify_callback")

            def run_conversation(self, **kwargs):
                # Simulate streaming
                on_token = captured_callbacks["on_token"]
                on_token("Hello ")
                on_token("world!")
                return {"final_response": "Hello world!"}

        with patch("clawke_channel._get_ai_agent", return_value=MockAIAgent), \
             patch("clawke_channel._get_session_db", return_value=None), \
             patch.dict("sys.modules", {
                 "hermes_cli": MagicMock(),
                 "hermes_cli.runtime_provider": MagicMock(),
             }):
            import sys
            sys.modules["hermes_cli.runtime_provider"].resolve_runtime_provider = (
                lambda requested=None: {"api_key": "k", "provider": "test", "model": "m", "base_url": ""}
            )
            await gateway._handle_chat({
                "conversation_id": "conv_test",
                "text": "hello",
            })

        # Find text delta messages
        deltas = [m for m in sent_messages if m["type"] == GatewayMessageType.AgentTextDelta]
        assert len(deltas) == 2
        assert deltas[0]["delta"] == "Hello "
        assert deltas[1]["delta"] == "world!"
        assert deltas[0]["conversation_id"] == "conv_test"

        # Find text done message
        dones = [m for m in sent_messages if m["type"] == GatewayMessageType.AgentTextDone]
        assert len(dones) == 1
        assert dones[0]["fullText"] == "Hello world!"

    @pytest.mark.asyncio
    async def test_reasoning_generates_thinking_delta(self, gateway, sent_messages):
        """reasoning_callback should produce agent_thinking_delta messages."""
        captured_callbacks = {}

        class MockAIAgent:
            def __init__(self, **kwargs):
                captured_callbacks["on_reasoning"] = kwargs.get("reasoning_callback")
                captured_callbacks["on_token"] = kwargs.get("stream_delta_callback")

            def run_conversation(self, **kwargs):
                on_reasoning = captured_callbacks["on_reasoning"]
                on_token = captured_callbacks["on_token"]
                on_reasoning("Let me think...")
                on_token("The answer is 42.")
                return {"final_response": "The answer is 42."}

        with patch("clawke_channel._get_ai_agent", return_value=MockAIAgent), \
             patch("clawke_channel._get_session_db", return_value=None), \
             patch.dict("sys.modules", {
                 "hermes_cli": MagicMock(),
                 "hermes_cli.runtime_provider": MagicMock(),
             }):
            import sys
            sys.modules["hermes_cli.runtime_provider"].resolve_runtime_provider = (
                lambda requested=None: {"api_key": "k", "provider": "test", "model": "m", "base_url": ""}
            )
            await gateway._handle_chat({
                "conversation_id": "conv_reason",
                "text": "think",
            })

        thinking_deltas = [m for m in sent_messages if m["type"] == GatewayMessageType.AgentThinkingDelta]
        assert len(thinking_deltas) >= 1
        assert thinking_deltas[0]["delta"] == "Let me think..."

        thinking_dones = [m for m in sent_messages if m["type"] == GatewayMessageType.AgentThinkingDone]
        assert len(thinking_dones) >= 1

    @pytest.mark.asyncio
    async def test_tool_call_generates_tool_messages(self, gateway, sent_messages):
        """tool_progress_callback should produce agent_tool_call/result messages."""
        captured_callbacks = {}

        class MockAIAgent:
            def __init__(self, **kwargs):
                captured_callbacks["on_tool"] = kwargs.get("tool_progress_callback")
                captured_callbacks["on_token"] = kwargs.get("stream_delta_callback")

            def run_conversation(self, **kwargs):
                on_tool = captured_callbacks["on_tool"]
                on_token = captured_callbacks["on_token"]
                on_tool("tool.started", "web_search", "Searching...", {"query": "test"})
                time.sleep(0.01)
                on_tool("tool.completed", "web_search", None, None)
                on_token("Found results.")
                return {"final_response": "Found results."}

        with patch("clawke_channel._get_ai_agent", return_value=MockAIAgent), \
             patch("clawke_channel._get_session_db", return_value=None), \
             patch.dict("sys.modules", {
                 "hermes_cli": MagicMock(),
                 "hermes_cli.runtime_provider": MagicMock(),
             }):
            import sys
            sys.modules["hermes_cli.runtime_provider"].resolve_runtime_provider = (
                lambda requested=None: {"api_key": "k", "provider": "test", "model": "m", "base_url": ""}
            )
            await gateway._handle_chat({
                "conversation_id": "conv_tool",
                "text": "search",
            })

        tool_calls = [m for m in sent_messages if m["type"] == GatewayMessageType.AgentToolCall]
        assert len(tool_calls) == 1
        assert tool_calls[0]["toolName"] == "web_search"

        tool_results = [m for m in sent_messages if m["type"] == GatewayMessageType.AgentToolResult]
        assert len(tool_results) == 1
        assert tool_results[0]["durationMs"] is not None

        # Should have turn stats
        stats = [m for m in sent_messages if m["type"] == GatewayMessageType.AgentTurnStats]
        assert len(stats) == 1
        assert stats[0]["toolCallCount"] == 1

    @pytest.mark.asyncio
    async def test_abort_during_stream_cancels(self, gateway, sent_messages):
        """Abort during streaming should stop further messages."""
        captured_callbacks = {}

        class MockAIAgent:
            def __init__(self, **kwargs):
                captured_callbacks["on_token"] = kwargs.get("stream_delta_callback")

            def interrupt(self, reason):
                pass

            def run_conversation(self, **kwargs):
                on_token = captured_callbacks["on_token"]
                on_token("Part 1 ")
                # Simulate abort mid-stream
                gateway._handle_abort({"conversation_id": "conv_abort"})
                on_token("Part 2 (should be dropped)")
                return {"final_response": "Part 1 Part 2"}

        with patch("clawke_channel._get_ai_agent", return_value=MockAIAgent), \
             patch("clawke_channel._get_session_db", return_value=None), \
             patch.dict("sys.modules", {
                 "hermes_cli": MagicMock(),
                 "hermes_cli.runtime_provider": MagicMock(),
             }):
            import sys
            sys.modules["hermes_cli.runtime_provider"].resolve_runtime_provider = (
                lambda requested=None: {"api_key": "k", "provider": "test", "model": "m", "base_url": ""}
            )
            await gateway._handle_chat({
                "conversation_id": "conv_abort",
                "text": "abort me",
            })

        deltas = [m for m in sent_messages if m["type"] == GatewayMessageType.AgentTextDelta]
        assert len(deltas) == 1  # Only Part 1, Part 2 was dropped
        assert deltas[0]["delta"] == "Part 1 "

        # No done message because cancelled
        dones = [m for m in sent_messages if m["type"] == GatewayMessageType.AgentTextDone]
        assert len(dones) == 0

    @pytest.mark.asyncio
    async def test_empty_response_sends_error_fallback(self, gateway, sent_messages):
        """No reply from agent should trigger error fallback."""

        class MockAIAgent:
            def __init__(self, **kwargs):
                pass

            def run_conversation(self, **kwargs):
                return {"final_response": ""}

        with patch("clawke_channel._get_ai_agent", return_value=MockAIAgent), \
             patch("clawke_channel._get_session_db", return_value=None), \
             patch.dict("sys.modules", {
                 "hermes_cli": MagicMock(),
                 "hermes_cli.runtime_provider": MagicMock(),
             }):
            import sys
            sys.modules["hermes_cli.runtime_provider"].resolve_runtime_provider = (
                lambda requested=None: {"api_key": "k", "provider": "test", "model": "m", "base_url": ""}
            )
            await gateway._handle_chat({
                "conversation_id": "conv_empty",
                "text": "hello",
            })

        texts = [m for m in sent_messages if m["type"] == GatewayMessageType.AgentText]
        assert len(texts) == 1
        assert "⚠️" in texts[0]["text"]

    @pytest.mark.asyncio
    async def test_agent_error_sends_error_message(self, gateway, sent_messages):
        """Agent exception should produce user-visible error."""

        class MockAIAgent:
            def __init__(self, **kwargs):
                pass

            def run_conversation(self, **kwargs):
                raise RuntimeError("LLM connection failed")

        with patch("clawke_channel._get_ai_agent", return_value=MockAIAgent), \
             patch("clawke_channel._get_session_db", return_value=None), \
             patch.dict("sys.modules", {
                 "hermes_cli": MagicMock(),
                 "hermes_cli.runtime_provider": MagicMock(),
             }):
            import sys
            sys.modules["hermes_cli.runtime_provider"].resolve_runtime_provider = (
                lambda requested=None: {"api_key": "k", "provider": "test", "model": "m", "base_url": ""}
            )
            await gateway._handle_chat({
                "conversation_id": "conv_err",
                "text": "fail",
            })

        texts = [m for m in sent_messages if m["type"] == GatewayMessageType.AgentText]
        assert len(texts) == 1
        assert "LLM connection failed" in texts[0]["text"]

    @pytest.mark.asyncio
    async def test_no_aiagent_sends_unavailable(self, gateway, sent_messages):
        """When AIAgent is not importable, send unavailable message."""
        with patch("clawke_channel._get_ai_agent", return_value=None):
            await gateway._handle_chat({
                "conversation_id": "conv_noagent",
                "text": "hello",
            })

        texts = [m for m in sent_messages if m["type"] == GatewayMessageType.AgentText]
        assert len(texts) == 1
        assert "not available" in texts[0]["text"].lower()


# ── Config Tests ────────────────────────────────────────────────────────────

class TestConfig:
    """Test configuration loading."""

    def test_config_from_env(self, tmp_path, monkeypatch):
        monkeypatch.setenv("CLAWKE_WS_URL", "ws://remote:9999")
        monkeypatch.setenv("CLAWKE_ACCOUNT_ID", "my_hermes")
        monkeypatch.setenv("CLAWKE_MODEL", "gpt-4")

        from config import load_config
        cfg = load_config()
        assert cfg.ws_url == "ws://remote:9999"
        assert cfg.account_id == "my_hermes"
        assert cfg.model == "gpt-4"


if __name__ == "__main__":
    pytest.main([__file__, "-v"])
