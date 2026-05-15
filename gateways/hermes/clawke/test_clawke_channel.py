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
import os
import threading
import time
from dataclasses import dataclass
from typing import Any
from unittest.mock import AsyncMock, MagicMock, patch

import pytest

# ── Import the module under test ────────────────────────────────────────────
import clawke_channel
from clawke_channel import (
    ClawkeHermesGateway,
    GatewayConfig,
    GatewayMessageType,
    InboundMessageType,
    AgentStatusValue,
    _backoff_delay,
    _configured_default_model,
    _websocket_connect_kwargs,
    _sanitize_messages,
    _usage_from_result,
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


@pytest.mark.asyncio
async def test_send_gateway_alert_uses_gateway_id_without_account_id(gateway):
    sent = []
    gateway.config.gateway_id = "hermes"
    gateway._loop = asyncio.get_running_loop()
    gateway._ws = object()

    async def capture(data):
        sent.append(data)

    gateway._send = capture
    gateway._send_gateway_alert({
        "severity": "error",
        "source": "cron_delivery",
        "title": "Delivery failed",
        "message": "Attempt 1 / 3 failed.",
        "target_conversation_id": "conv_1",
        "dedupe_key": "alert_1",
    })
    await asyncio.sleep(0.01)

    assert sent == [{
        "type": "gateway_alert",
        "gateway_id": "hermes",
        "message_id": "alert_1",
        "severity": "error",
        "source": "cron_delivery",
        "title": "Delivery failed",
        "message": "Attempt 1 / 3 failed.",
        "target_conversation_id": "conv_1",
        "dedupe_key": "alert_1",
        "metadata": {},
    }]
    assert "account_id" not in sent[0]


@pytest.mark.asyncio
async def test_start_creates_one_cron_sync_task(config):
    gateway = ClawkeHermesGateway(config)

    class FakeSyncer:
        def __init__(self):
            self.started = 0
            self.running = True

        async def start(self):
            self.started += 1
            while self.running:
                await asyncio.sleep(0.01)

        async def stop(self):
            self.running = False

    fake_syncer = FakeSyncer()
    gateway._cron_syncer = fake_syncer

    async def fake_connect():
        gateway._running = False

    gateway._connect = fake_connect
    await gateway.start()
    await asyncio.sleep(0)
    assert fake_syncer.started == 1
    assert gateway._cron_sync_task is not None
    await gateway.stop()


@pytest.mark.asyncio
async def test_stop_stops_cron_sync_task(config):
    gateway = ClawkeHermesGateway(config)

    class FakeSyncer:
        def __init__(self):
            self.stopped = False

        async def stop(self):
            self.stopped = True

    fake_syncer = FakeSyncer()
    gateway._cron_syncer = fake_syncer
    gateway._cron_sync_task = asyncio.create_task(asyncio.sleep(10))

    await gateway.stop()

    assert fake_syncer.stopped is True
    assert gateway._cron_sync_task is None


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
        assert GatewayMessageType.GatewaySystemResponse == "gateway_system_response"

    def test_inbound_message_types(self):
        assert InboundMessageType.Chat == "chat"
        assert InboundMessageType.Abort == "abort"
        assert InboundMessageType.QueryModels == "query_models"
        assert InboundMessageType.QuerySkills == "query_skills"
        assert InboundMessageType.ApprovalResponse == "approval_response"
        assert InboundMessageType.ClarifyResponse == "clarify_response"
        assert InboundMessageType.GatewaySystemRequest == "gateway_system_request"


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


class TestUsageMapping:
    """验证 Hermes 结果 token usage 映射 — Verify Hermes result token usage mapping."""

    def test_usage_from_result_maps_hermes_fields(self):
        usage = _usage_from_result({
            "input_tokens": 10,
            "output_tokens": 5,
            "cache_read_tokens": 3,
            "cache_write_tokens": 2,
            "reasoning_tokens": 7,
            "total_tokens": 15,
        })

        assert usage == {
            "input": 10,
            "output": 5,
            "cacheRead": 3,
            "cacheWrite": 2,
            "reasoning": 7,
            "total": 15,
        }

    def test_usage_from_result_skips_empty_usage(self):
        assert _usage_from_result({"final_response": "ok"}) is None
        assert _usage_from_result(None) is None


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


class TestDefaultModelCache:
    def test_configured_default_model_caches_until_config_mtime_changes(self, tmp_path, monkeypatch):
        hermes_home = tmp_path / "hermes"
        hermes_home.mkdir()
        config_path = hermes_home / "config.yaml"
        config_path.write_text("model:\n  default: one\n", encoding="utf-8")
        monkeypatch.setenv("HERMES_HOME", str(hermes_home))
        monkeypatch.delenv("HERMES_INFERENCE_MODEL", raising=False)
        clawke_channel._DEFAULT_MODEL_CACHE.clear()
        calls = []

        config_module = MagicMock()

        def load_config():
            calls.append(1)
            return {"model": {"default": f"model-{len(calls)}"}}

        config_module.load_config = load_config
        with patch.dict("sys.modules", {
            "hermes_cli": MagicMock(),
            "hermes_cli.config": config_module,
        }):
            assert _configured_default_model() == "model-1"
            assert _configured_default_model() == "model-1"

            old_mtime = config_path.stat().st_mtime_ns
            os.utime(config_path, ns=(old_mtime + 1_000_000_000, old_mtime + 1_000_000_000))

            assert _configured_default_model() == "model-2"

        assert len(calls) == 2

    def test_configured_default_model_refreshes_when_env_changes(self, tmp_path, monkeypatch):
        hermes_home = tmp_path / "hermes"
        hermes_home.mkdir()
        (hermes_home / "config.yaml").write_text("model:\n  default: file-model\n", encoding="utf-8")
        monkeypatch.setenv("HERMES_HOME", str(hermes_home))
        clawke_channel._DEFAULT_MODEL_CACHE.clear()

        monkeypatch.setenv("HERMES_INFERENCE_MODEL", "env-one")
        assert _configured_default_model() == "env-one"

        monkeypatch.setenv("HERMES_INFERENCE_MODEL", "env-two")
        assert _configured_default_model() == "env-two"


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

    def test_loopback_connection_disables_proxy_when_supported(self, monkeypatch):
        def fake_connect(uri, *, ping_interval=30, ping_timeout=10, proxy=True):
            return None

        monkeypatch.setattr(clawke_channel.websockets, "connect", fake_connect)

        assert _websocket_connect_kwargs("ws://127.0.0.1:8766") == {
            "ping_interval": 30,
            "ping_timeout": 10,
            "proxy": None,
        }
        assert _websocket_connect_kwargs("ws://localhost:8766")["proxy"] is None
        assert "proxy" not in _websocket_connect_kwargs("ws://remote.example:8766")

    def test_loopback_connection_keeps_old_websockets_compatibility(self, monkeypatch):
        def fake_connect(uri, *, ping_interval=30, ping_timeout=10):
            return None

        monkeypatch.setattr(clawke_channel.websockets, "connect", fake_connect)

        assert _websocket_connect_kwargs("ws://127.0.0.1:8766") == {
            "ping_interval": 30,
            "ping_timeout": 10,
        }


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


class TestGatewaySystemRequest:
    """Test isolated Gateway system-session requests."""

    @pytest.mark.asyncio
    async def test_system_request_returns_response_without_user_message(self, gateway, sent_messages):
        async def fake_run(msg):
            assert msg["system_session_id"] == "__clawke_system__:Hermes"
            assert msg["prompt"] == "Return strict JSON."
            return '{"description":"中文描述"}'

        gateway._run_system_session = fake_run

        await gateway._handle_gateway_system_request({
            "type": InboundMessageType.GatewaySystemRequest,
            "request_id": "req_1",
            "gateway_id": "Hermes",
            "system_session_id": "__clawke_system__:Hermes",
            "purpose": "translation",
            "prompt": "Return strict JSON.",
        })

        assert sent_messages == [{
            "type": GatewayMessageType.GatewaySystemResponse,
            "request_id": "req_1",
            "ok": True,
            "json": {"description": "中文描述"},
        }]

    @pytest.mark.asyncio
    async def test_system_request_invalid_json_returns_safe_error(self, gateway, sent_messages):
        async def fake_run(_msg):
            return "not json"

        gateway._run_system_session = fake_run

        await gateway._handle_gateway_system_request({
            "type": InboundMessageType.GatewaySystemRequest,
            "request_id": "req_2",
            "gateway_id": "Hermes",
            "system_session_id": "__clawke_system__:Hermes",
            "purpose": "translation",
            "prompt": "Return strict JSON.",
        })

        assert sent_messages[0]["type"] == GatewayMessageType.GatewaySystemResponse
        assert sent_messages[0]["request_id"] == "req_2"
        assert sent_messages[0]["ok"] is False
        assert sent_messages[0]["error_code"] == "invalid_json"


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
        assert {
            "model_id": "anthropic/claude-3",
            "provider": "anthropic",
            "display_name": "claude-3",
        } in sent_messages[0]["models"]

    @pytest.mark.asyncio
    async def test_query_models_infers_minimax_cn_from_env_file(
        self,
        gateway,
        sent_messages,
        tmp_path,
        monkeypatch,
    ):
        hermes_home = tmp_path / "hermes"
        hermes_home.mkdir()
        (hermes_home / ".env").write_text("MINIMAX_CN_API_KEY=test-key\n", encoding="utf-8")
        monkeypatch.setenv("HERMES_HOME", str(hermes_home))
        for env_var in (
            "ANTHROPIC_API_KEY",
            "OPENROUTER_API_KEY",
            "OPENAI_API_KEY",
            "DEEPSEEK_API_KEY",
            "GOOGLE_API_KEY",
            "GEMINI_API_KEY",
            "DASHSCOPE_API_KEY",
            "GLM_API_KEY",
            "HF_TOKEN",
            "MINIMAX_API_KEY",
            "MINIMAX_CN_API_KEY",
        ):
            monkeypatch.delenv(env_var, raising=False)

        runtime_provider = MagicMock()
        runtime_provider.resolve_runtime_provider = (
            lambda: {"model": "", "provider": ""}
        )
        models_module = MagicMock()
        models_module.list_available_providers = lambda: []

        with patch.dict("sys.modules", {
            "hermes_cli": MagicMock(),
            "hermes_cli.runtime_provider": runtime_provider,
            "hermes_cli.models": models_module,
        }):
            await gateway._handle_query_models()

        assert {
            "model_id": "minimax-cn/MiniMax-M2.7",
            "provider": "minimax-cn",
            "display_name": "MiniMax-M2.7",
        } in sent_messages[0]["models"]

    @pytest.mark.asyncio
    async def test_query_models_preserves_same_display_from_runtime_and_config(
        self,
        gateway,
        sent_messages,
        tmp_path,
        monkeypatch,
    ):
        hermes_home = tmp_path / "hermes"
        hermes_home.mkdir()
        (hermes_home / "config.yaml").write_text(
            """
model:
  default: deepseek-v4-pro
  provider: deepseek-v4-pro
providers:
  deepseek-v4-pro:
    name: DeepSeek V4 Pro
    default_model: deepseek-v4-pro
""",
            encoding="utf-8",
        )
        monkeypatch.setenv("HERMES_HOME", str(hermes_home))
        for env_var in (
            "ANTHROPIC_API_KEY",
            "OPENROUTER_API_KEY",
            "OPENAI_API_KEY",
            "DEEPSEEK_API_KEY",
            "GOOGLE_API_KEY",
            "GEMINI_API_KEY",
            "DASHSCOPE_API_KEY",
            "GLM_API_KEY",
            "HF_TOKEN",
        ):
            monkeypatch.delenv(env_var, raising=False)

        runtime_provider = MagicMock()
        runtime_provider.resolve_runtime_provider = (
            lambda: {"model": "deepseek-v4-pro", "provider": "custom"}
        )
        models_module = MagicMock()
        models_module.list_available_providers = lambda: []

        with patch.dict("sys.modules", {
            "hermes_cli": MagicMock(),
            "hermes_cli.runtime_provider": runtime_provider,
            "hermes_cli.models": models_module,
        }):
            await gateway._handle_query_models()

        models = sent_messages[0]["models"]
        same_label = [
            model for model in models
            if model["display_name"] == "deepseek-v4-pro"
        ]
        assert same_label == [
            {
                "model_id": "custom/deepseek-v4-pro",
                "provider": "custom",
                "display_name": "deepseek-v4-pro",
            },
            {
                "model_id": "deepseek-v4-pro/deepseek-v4-pro",
                "provider": "deepseek-v4-pro",
                "display_name": "deepseek-v4-pro",
            },
        ]

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
    async def test_provider_override_strips_matching_model_prefix(self, gateway, sent_messages):
        """Hermes needs provider and raw model split before AIAgent construction."""
        captured_kwargs = {}

        class MockAIAgent:
            def __init__(self, **kwargs):
                captured_kwargs.update(kwargs)

            def run_conversation(self, **kwargs):
                return {"final_response": "ok"}

        def resolve_runtime_provider(requested=None, target_model=None):
            assert requested == "anthropic"
            assert target_model == "claude-sonnet-4"
            return {
                "api_key": "k",
                "provider": "anthropic",
                "model": "default-model",
                "base_url": "",
            }

        with patch("clawke_channel._get_ai_agent", return_value=MockAIAgent), \
             patch("clawke_channel._get_session_db", return_value=None), \
             patch.dict("sys.modules", {
                 "hermes_cli": MagicMock(),
                 "hermes_cli.runtime_provider": MagicMock(),
             }):
            import sys
            sys.modules["hermes_cli.runtime_provider"].resolve_runtime_provider = resolve_runtime_provider
            await gateway._handle_chat({
                "conversation_id": "conv_model",
                "text": "hello",
                "model_override": "anthropic/claude-sonnet-4",
                "provider_override": "anthropic",
            })

        assert captured_kwargs["provider"] == "anthropic"
        assert captured_kwargs["model"] == "claude-sonnet-4"

    @pytest.mark.asyncio
    async def test_openrouter_provider_override_keeps_nested_model_prefix(self, gateway, sent_messages):
        """Only the selected provider prefix is stripped."""
        captured_kwargs = {}

        class MockAIAgent:
            def __init__(self, **kwargs):
                captured_kwargs.update(kwargs)

            def run_conversation(self, **kwargs):
                return {"final_response": "ok"}

        with patch("clawke_channel._get_ai_agent", return_value=MockAIAgent), \
             patch("clawke_channel._get_session_db", return_value=None), \
             patch.dict("sys.modules", {
                 "hermes_cli": MagicMock(),
                 "hermes_cli.runtime_provider": MagicMock(),
             }):
            import sys
            sys.modules["hermes_cli.runtime_provider"].resolve_runtime_provider = (
                lambda requested=None, target_model=None: {
                    "api_key": "k",
                    "provider": requested,
                    "model": "default-model",
                    "base_url": "",
                }
            )
            await gateway._handle_chat({
                "conversation_id": "conv_openrouter",
                "text": "hello",
                "model_override": "openrouter/openai/gpt-4o",
                "provider_override": "openrouter",
            })

        assert captured_kwargs["provider"] == "openrouter"
        assert captured_kwargs["model"] == "openai/gpt-4o"

    @pytest.mark.asyncio
    async def test_default_chat_uses_hermes_config_model_when_runtime_has_no_model(self, sent_messages):
        captured_kwargs = {}

        class MockAIAgent:
            def __init__(self, **kwargs):
                captured_kwargs.update(kwargs)

            def run_conversation(self, **kwargs):
                return {"final_response": "ok"}

        gateway = ClawkeHermesGateway(GatewayConfig(
            ws_url="ws://127.0.0.1:8766",
            account_id="test_hermes",
            model="",
            provider="deepseek",
        ))
        gateway._ws = AsyncMock()
        gateway._loop = asyncio.get_event_loop()
        async def capture_send(data):
            sent_messages.append(data)
        gateway._send = capture_send
        gateway._send_sync = lambda data: sent_messages.append(data)

        with patch("clawke_channel._get_ai_agent", return_value=MockAIAgent), \
             patch("clawke_channel._get_session_db", return_value=None), \
             patch.dict("sys.modules", {
                 "hermes_cli": MagicMock(),
                 "hermes_cli.runtime_provider": MagicMock(),
                 "hermes_cli.config": MagicMock(),
             }):
            import sys
            sys.modules["hermes_cli.runtime_provider"].resolve_runtime_provider = (
                lambda requested=None, target_model=None: {
                    "api_key": "k",
                    "provider": "deepseek",
                    "model": None,
                    "base_url": "https://api.deepseek.com",
                }
            )
            sys.modules["hermes_cli.config"].load_config = lambda: {
                "model": {"default": "deepseek-v4-pro", "provider": "deepseek"}
            }
            await gateway._handle_chat({
                "conversation_id": "conv_default_model",
                "text": "hello",
            })

        assert captured_kwargs["provider"] == "deepseek"
        assert captured_kwargs["model"] == "deepseek-v4-pro"

    @pytest.mark.asyncio
    async def test_default_system_session_uses_hermes_config_model_when_runtime_has_no_model(self):
        captured_kwargs = {}

        class MockAIAgent:
            def __init__(self, **kwargs):
                captured_kwargs.update(kwargs)

            def run_conversation(self, **kwargs):
                return {"final_response": "ok"}

        gateway = ClawkeHermesGateway(GatewayConfig(
            ws_url="ws://127.0.0.1:8766",
            account_id="test_hermes",
            model="",
            provider="deepseek",
        ))

        with patch("clawke_channel._get_ai_agent", return_value=MockAIAgent), \
             patch.dict("sys.modules", {
                 "hermes_cli": MagicMock(),
                 "hermes_cli.runtime_provider": MagicMock(),
                 "hermes_cli.config": MagicMock(),
             }):
            import sys
            sys.modules["hermes_cli.runtime_provider"].resolve_runtime_provider = (
                lambda requested=None, target_model=None: {
                    "api_key": "k",
                    "provider": "deepseek",
                    "model": None,
                    "base_url": "https://api.deepseek.com",
                }
            )
            sys.modules["hermes_cli.config"].load_config = lambda: {
                "model": {"default": "deepseek-v4-pro", "provider": "deepseek"}
            }
            result = await gateway._run_system_session({
                "request_id": "req_default_model",
                "prompt": "translate",
            })

        assert result == "ok"
        assert captured_kwargs["provider"] == "deepseek"
        assert captured_kwargs["model"] == "deepseek-v4-pro"

    @pytest.mark.asyncio
    async def test_inbound_image_media_reaches_aiagent_as_native_content_parts(
        self,
        gateway,
        sent_messages,
        tmp_path,
    ):
        captured_run = {}
        image_path = tmp_path / "shot.png"
        image_path.write_bytes(b"fake-image")

        class MockAIAgent:
            def __init__(self, **kwargs):
                pass

            def run_conversation(self, **kwargs):
                captured_run.update(kwargs)
                return {"final_response": "ok"}

        runtime_provider = MagicMock()
        runtime_provider.resolve_runtime_provider = (
            lambda requested=None, target_model=None: {
                "api_key": "k",
                "provider": "vision-provider",
                "model": "vision-model",
                "base_url": "",
            }
        )
        config_module = MagicMock()
        config_module.load_config = lambda: {}
        image_routing = MagicMock()
        image_routing.decide_image_input_mode = lambda provider, model, cfg: "native"
        image_routing.build_native_content_parts = lambda text, paths: ([
            {"type": "text", "text": text},
            {"type": "image_url", "image_url": {"url": "data:image/png;base64,AAA"}},
        ], [])

        with patch("clawke_channel._get_ai_agent", return_value=MockAIAgent), \
             patch("clawke_channel._get_session_db", return_value=None), \
             patch.dict("sys.modules", {
                 "hermes_cli": MagicMock(),
                 "hermes_cli.runtime_provider": runtime_provider,
                 "hermes_cli.config": config_module,
                 "agent": MagicMock(),
                 "agent.image_routing": image_routing,
             }):
            await gateway._handle_chat({
                "conversation_id": "conv_image_native",
                "text": "这是什么",
                "media": {
                    "paths": [str(image_path)],
                    "types": ["image/png"],
                    "names": ["shot.png"],
                },
            })

        assert isinstance(captured_run["user_message"], list)
        assert captured_run["user_message"][1]["type"] == "image_url"
        assert "用户发送了 1 张图片" in captured_run["persist_user_message"]

    @pytest.mark.asyncio
    async def test_inbound_image_media_falls_back_to_vision_text_for_text_mode(
        self,
        gateway,
        sent_messages,
        tmp_path,
    ):
        captured_run = {}
        image_path = tmp_path / "shot.png"
        image_path.write_bytes(b"fake-image")

        class MockAIAgent:
            def __init__(self, **kwargs):
                pass

            def run_conversation(self, **kwargs):
                captured_run.update(kwargs)
                return {"final_response": "ok"}

        async def fake_vision_analyze_tool(image_url, user_prompt):
            return json.dumps({"success": True, "analysis": "a man in a city street"})

        runtime_provider = MagicMock()
        runtime_provider.resolve_runtime_provider = (
            lambda requested=None, target_model=None: {
                "api_key": "k",
                "provider": "text-provider",
                "model": "text-model",
                "base_url": "",
            }
        )
        config_module = MagicMock()
        config_module.load_config = lambda: {}
        image_routing = MagicMock()
        image_routing.decide_image_input_mode = lambda provider, model, cfg: "text"
        vision_tools = MagicMock()
        vision_tools.vision_analyze_tool = fake_vision_analyze_tool

        with patch("clawke_channel._get_ai_agent", return_value=MockAIAgent), \
             patch("clawke_channel._get_session_db", return_value=None), \
             patch.dict("sys.modules", {
                 "hermes_cli": MagicMock(),
                 "hermes_cli.runtime_provider": runtime_provider,
                 "hermes_cli.config": config_module,
                 "agent": MagicMock(),
                 "agent.image_routing": image_routing,
                 "tools": MagicMock(),
                 "tools.vision_tools": vision_tools,
             }):
            await gateway._handle_chat({
                "conversation_id": "conv_image_text",
                "text": "这是什么",
                "media": {
                    "paths": [str(image_path)],
                    "types": ["image/png"],
                    "names": ["shot.png"],
                },
            })

        assert isinstance(captured_run["user_message"], str)
        assert "a man in a city street" in captured_run["user_message"]
        assert "这是什么" in captured_run["user_message"]
        assert captured_run["persist_user_message"] == captured_run["user_message"]

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
                lambda requested=None, target_model=None: {"api_key": "k", "provider": "test", "model": "m", "base_url": ""}
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
        assert "usage" not in dones[0]

    @pytest.mark.asyncio
    async def test_stream_done_includes_usage_from_agent_result(self, gateway, sent_messages):
        """流式完成应包含映射后的 token usage — Streaming completion should include mapped token usage."""
        captured_callbacks = {}

        class MockAIAgent:
            def __init__(self, **kwargs):
                captured_callbacks["on_token"] = kwargs.get("stream_delta_callback")

            def run_conversation(self, **kwargs):
                captured_callbacks["on_token"]("Hello usage")
                return {
                    "final_response": "Hello usage",
                    "input_tokens": 42,
                    "output_tokens": 8,
                    "cache_read_tokens": 5,
                    "cache_write_tokens": 2,
                    "reasoning_tokens": 3,
                    "total_tokens": 50,
                }

        with patch("clawke_channel._get_ai_agent", return_value=MockAIAgent), \
             patch("clawke_channel._get_session_db", return_value=None), \
             patch.dict("sys.modules", {
                 "hermes_cli": MagicMock(),
                 "hermes_cli.runtime_provider": MagicMock(),
             }):
            import sys
            sys.modules["hermes_cli.runtime_provider"].resolve_runtime_provider = (
                lambda requested=None, target_model=None: {"api_key": "k", "provider": "test", "model": "m", "base_url": ""}
            )
            await gateway._handle_chat({
                "conversation_id": "conv_usage_stream",
                "text": "hello",
            })

        dones = [m for m in sent_messages if m["type"] == GatewayMessageType.AgentTextDone]
        assert len(dones) == 1
        assert dones[0]["usage"] == {
            "input": 42,
            "output": 8,
            "cacheRead": 5,
            "cacheWrite": 2,
            "reasoning": 3,
            "total": 50,
        }

    @pytest.mark.asyncio
    async def test_non_stream_text_includes_usage_from_agent_result(self, gateway, sent_messages):
        """非流式完成应包含映射后的 token usage — Non-streaming completion should include mapped token usage."""

        class MockAIAgent:
            def __init__(self, **kwargs):
                pass

            def run_conversation(self, **kwargs):
                return {
                    "final_response": "Full response",
                    "input_tokens": 9,
                    "output_tokens": 4,
                    "cache_read_tokens": 1,
                    "cache_write_tokens": 0,
                    "reasoning_tokens": 0,
                    "total_tokens": 13,
                }

        with patch("clawke_channel._get_ai_agent", return_value=MockAIAgent), \
             patch("clawke_channel._get_session_db", return_value=None), \
             patch.dict("sys.modules", {
                 "hermes_cli": MagicMock(),
                 "hermes_cli.runtime_provider": MagicMock(),
             }):
            import sys
            sys.modules["hermes_cli.runtime_provider"].resolve_runtime_provider = (
                lambda requested=None, target_model=None: {"api_key": "k", "provider": "test", "model": "m", "base_url": ""}
            )
            await gateway._handle_chat({
                "conversation_id": "conv_usage_full",
                "text": "hello",
            })

        texts = [m for m in sent_messages if m["type"] == GatewayMessageType.AgentText]
        assert len(texts) == 1
        assert texts[0]["usage"] == {
            "input": 9,
            "output": 4,
            "cacheRead": 1,
            "cacheWrite": 0,
            "reasoning": 0,
            "total": 13,
        }

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
                lambda requested=None, target_model=None: {"api_key": "k", "provider": "test", "model": "m", "base_url": ""}
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
                lambda requested=None, target_model=None: {"api_key": "k", "provider": "test", "model": "m", "base_url": ""}
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
                lambda requested=None, target_model=None: {"api_key": "k", "provider": "test", "model": "m", "base_url": ""}
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
                lambda requested=None, target_model=None: {"api_key": "k", "provider": "test", "model": "m", "base_url": ""}
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
                lambda requested=None, target_model=None: {"api_key": "k", "provider": "test", "model": "m", "base_url": ""}
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
