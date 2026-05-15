"""Verify Hermes task-level cwd overrides are session-scoped.

Run:
    python3 -m unittest discover -s gateways/hermes/clawke -p 'test_workdir_isolation.py' -v
"""

from __future__ import annotations

import ast
import asyncio
import importlib
import os
import sys
import tempfile
import types
import unittest
from pathlib import Path
from typing import Any, Dict
from unittest.mock import AsyncMock, patch


def _hermes_terminal_tool_path() -> Path:
    """定位官方 Hermes 源码 — Locate the official Hermes source checkout."""
    override = os.getenv("HERMES_AGENT_SOURCE")
    if override:
        candidate = Path(override).expanduser()
        if candidate.name == "terminal_tool.py":
            return candidate
        return candidate / "tools" / "terminal_tool.py"

    candidates = [
        Path.home() / ".hermes" / "hermes-agent" / "tools" / "terminal_tool.py",
    ]
    for candidate in candidates:
        if candidate.exists():
            return candidate

    checked = ", ".join(str(candidate) for candidate in candidates)
    raise FileNotFoundError(f"Hermes terminal_tool.py not found. Checked: {checked}")


def _load_official_task_override_primitives():
    """加载官方 cwd override 原语 — Load official cwd override primitives only."""
    terminal_tool = _hermes_terminal_tool_path()
    source = terminal_tool.read_text(encoding="utf-8")
    tree = ast.parse(source, filename=str(terminal_tool))

    wanted = {
        "_task_env_overrides",
        "register_task_env_overrides",
        "clear_task_env_overrides",
    }
    selected: list[ast.stmt] = []
    for node in tree.body:
        if isinstance(node, ast.AnnAssign):
            target = node.target
            if isinstance(target, ast.Name) and target.id in wanted:
                selected.append(node)
        elif isinstance(node, ast.Assign):
            if any(isinstance(t, ast.Name) and t.id in wanted for t in node.targets):
                selected.append(node)
        elif isinstance(node, ast.FunctionDef) and node.name in wanted:
            selected.append(node)

    module = ast.Module(body=selected, type_ignores=[])
    ast.fix_missing_locations(module)
    namespace: dict[str, Any] = {"Dict": Dict, "Any": Any}
    exec(compile(module, str(terminal_tool), "exec"), namespace)
    return types.SimpleNamespace(
        _task_env_overrides=namespace["_task_env_overrides"],
        register_task_env_overrides=namespace["register_task_env_overrides"],
        clear_task_env_overrides=namespace["clear_task_env_overrides"],
        source=source,
    )


class HermesTaskWorkdirIsolationTest(unittest.TestCase):
    def test_terminal_tool_path_does_not_fallback_to_clawke_extends(self):
        with tempfile.TemporaryDirectory() as tmp:
            with patch.dict(os.environ, {}, clear=True), \
                 patch.object(Path, "home", return_value=Path(tmp)):
                with self.assertRaises(FileNotFoundError) as context:
                    _hermes_terminal_tool_path()

        self.assertNotIn("clawke_extends", str(context.exception))

    def test_task_cwd_overrides_are_per_session_and_do_not_mutate_terminal_cwd(self):
        primitives = _load_official_task_override_primitives()
        old_terminal_cwd = os.environ.get("TERMINAL_CWD")
        os.environ["TERMINAL_CWD"] = "/global/default"
        try:
            primitives.register_task_env_overrides(
                "conv_a",
                {"cwd": "/tmp/hermes-workdir-a"},
            )
            primitives.register_task_env_overrides(
                "conv_b",
                {"cwd": "/tmp/hermes-workdir-b"},
            )

            self.assertEqual(
                primitives._task_env_overrides["conv_a"]["cwd"],
                "/tmp/hermes-workdir-a",
            )
            self.assertEqual(
                primitives._task_env_overrides["conv_b"]["cwd"],
                "/tmp/hermes-workdir-b",
            )
            self.assertEqual(os.environ["TERMINAL_CWD"], "/global/default")

            primitives.clear_task_env_overrides("conv_a")

            self.assertNotIn("conv_a", primitives._task_env_overrides)
            self.assertEqual(
                primitives._task_env_overrides["conv_b"]["cwd"],
                "/tmp/hermes-workdir-b",
            )
            self.assertEqual(os.environ["TERMINAL_CWD"], "/global/default")
        finally:
            if old_terminal_cwd is None:
                os.environ.pop("TERMINAL_CWD", None)
            else:
                os.environ["TERMINAL_CWD"] = old_terminal_cwd

    def test_terminal_tool_prefers_task_cwd_override_before_global_config_cwd(self):
        primitives = _load_official_task_override_primitives()

        self.assertIn(
            'cwd = overrides.get("cwd") or config["cwd"]',
            primitives.source,
        )


class ClawkeHermesGatewayWorkdirTest(unittest.IsolatedAsyncioTestCase):
    async def test_gateway_registers_work_dir_by_conversation_without_mutating_global_cwd(self):
        sys.path.insert(0, str(Path(__file__).resolve().parent))
        sys.modules.pop("clawke_channel", None)
        with patch.dict(sys.modules, {"websockets": types.ModuleType("websockets")}):
            clawke_channel = importlib.import_module("clawke_channel")

        captured_agent_kwargs: dict[str, Any] = {}
        captured_run_kwargs: dict[str, Any] = {}
        registered: list[tuple[str, dict[str, Any]]] = []
        cleared: list[str] = []

        class MockAIAgent:
            def __init__(self, **kwargs):
                captured_agent_kwargs.update(kwargs)

            def run_conversation(self, **kwargs):
                captured_run_kwargs.update(kwargs)
                return {"final_response": "ok"}

        tools_module = types.ModuleType("tools")
        terminal_tool_module = types.ModuleType("tools.terminal_tool")
        terminal_tool_module.register_task_env_overrides = (
            lambda task_id, overrides: registered.append((task_id, dict(overrides)))
        )
        terminal_tool_module.clear_task_env_overrides = lambda task_id: cleared.append(task_id)

        hermes_cli_module = types.ModuleType("hermes_cli")
        runtime_provider_module = types.ModuleType("hermes_cli.runtime_provider")
        runtime_provider_module.resolve_runtime_provider = (
            lambda requested=None, target_model=None: {
                "api_key": "k",
                "provider": requested or "test-provider",
                "model": target_model or "test-model",
                "base_url": "",
            }
        )

        agent_module = types.ModuleType("agent")
        prompt_builder_module = types.ModuleType("agent.prompt_builder")
        prompt_builder_module.build_context_files_prompt = (
            lambda cwd, skip_soul=False: f"CTX:{cwd}"
        )

        gateway = clawke_channel.ClawkeHermesGateway(clawke_channel.GatewayConfig(
            ws_url="ws://127.0.0.1:8766",
            account_id="test_hermes",
            model="test-model",
            provider="test-provider",
        ))
        gateway._ws = AsyncMock()
        gateway._loop = asyncio.get_event_loop()
        gateway._send = AsyncMock()
        gateway._send_sync = lambda _data: None

        old_terminal_cwd = os.environ.get("TERMINAL_CWD")
        os.environ["TERMINAL_CWD"] = "/global/default"
        expected_work_dir = str(Path("/tmp").resolve())
        try:
            with patch.object(clawke_channel, "_get_ai_agent", return_value=MockAIAgent), \
                 patch.object(clawke_channel, "_get_session_db", return_value=None), \
                 patch.dict(sys.modules, {
                     "tools": tools_module,
                     "tools.terminal_tool": terminal_tool_module,
                     "hermes_cli": hermes_cli_module,
                     "hermes_cli.runtime_provider": runtime_provider_module,
                     "agent": agent_module,
                     "agent.prompt_builder": prompt_builder_module,
                 }):
                await gateway._handle_chat({
                    "conversation_id": "conv_workdir",
                    "text": "pwd",
                    "work_dir": expected_work_dir,
                })
        finally:
            if old_terminal_cwd is None:
                os.environ.pop("TERMINAL_CWD", None)
            else:
                os.environ["TERMINAL_CWD"] = old_terminal_cwd

        self.assertIn("conv_workdir", cleared)
        self.assertIn(("conv_workdir", {"cwd": expected_work_dir}), registered)
        self.assertEqual(os.environ.get("TERMINAL_CWD"), old_terminal_cwd)
        self.assertTrue(captured_agent_kwargs["skip_context_files"])
        prompt = captured_agent_kwargs["ephemeral_system_prompt"]
        self.assertIn(f"Current session working directory: {expected_work_dir}", prompt)
        self.assertIn('Do not change to "/" unless explicitly requested.', prompt)
        self.assertIn(f"CTX:{expected_work_dir}", prompt)
        self.assertEqual(captured_run_kwargs["task_id"], "conv_workdir")

    async def test_gateway_without_work_dir_does_not_register_or_prompt(self):
        sys.path.insert(0, str(Path(__file__).resolve().parent))
        sys.modules.pop("clawke_channel", None)
        with patch.dict(sys.modules, {"websockets": types.ModuleType("websockets")}):
            clawke_channel = importlib.import_module("clawke_channel")

        captured_agent_kwargs: dict[str, Any] = {}
        registered: list[tuple[str, dict[str, Any]]] = []

        class MockAIAgent:
            def __init__(self, **kwargs):
                captured_agent_kwargs.update(kwargs)

            def run_conversation(self, **kwargs):
                return {"final_response": "ok"}

        tools_module = types.ModuleType("tools")
        terminal_tool_module = types.ModuleType("tools.terminal_tool")
        terminal_tool_module.register_task_env_overrides = (
            lambda task_id, overrides: registered.append((task_id, dict(overrides)))
        )
        terminal_tool_module.clear_task_env_overrides = lambda task_id: None

        hermes_cli_module = types.ModuleType("hermes_cli")
        runtime_provider_module = types.ModuleType("hermes_cli.runtime_provider")
        runtime_provider_module.resolve_runtime_provider = (
            lambda requested=None, target_model=None: {
                "api_key": "k",
                "provider": requested or "test-provider",
                "model": target_model or "test-model",
                "base_url": "",
            }
        )

        gateway = clawke_channel.ClawkeHermesGateway(clawke_channel.GatewayConfig(
            ws_url="ws://127.0.0.1:8766",
            account_id="test_hermes",
            model="test-model",
            provider="test-provider",
        ))
        gateway._ws = AsyncMock()
        gateway._loop = asyncio.get_event_loop()
        gateway._send = AsyncMock()
        gateway._send_sync = lambda _data: None

        with patch.object(clawke_channel, "_get_ai_agent", return_value=MockAIAgent), \
             patch.object(clawke_channel, "_get_session_db", return_value=None), \
             patch.dict(sys.modules, {
                 "tools": tools_module,
                 "tools.terminal_tool": terminal_tool_module,
                 "hermes_cli": hermes_cli_module,
                 "hermes_cli.runtime_provider": runtime_provider_module,
             }):
            await gateway._handle_chat({
                "conversation_id": "conv_no_workdir",
                "text": "hello",
            })

        self.assertEqual(registered, [])
        self.assertIsNone(captured_agent_kwargs["ephemeral_system_prompt"])
        self.assertFalse(captured_agent_kwargs["skip_context_files"])


if __name__ == "__main__":
    unittest.main()
