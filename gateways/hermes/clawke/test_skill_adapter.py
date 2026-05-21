from __future__ import annotations

import asyncio
from pathlib import Path

import pytest
import yaml

from skill_adapter import HermesSkillAdapter


def test_hermes_skill_adapter_manages_gateway_host_clawke_skills(tmp_path: Path):
    adapter = HermesSkillAdapter(clawke_home=tmp_path)

    created = adapter.create_skill({
        "name": "apple-notes",
        "category": "apple",
        "description": "Manage Apple Notes",
        "trigger": "Use for notes",
        "body": "# Apple Notes\n",
    })

    assert created["id"] == "apple/apple-notes"
    assert created["source"] == "managed"
    assert created["enabled"] is True
    assert (tmp_path / "skills" / "apple-notes" / "SKILL.md").exists()

    listed = adapter.list_skills()
    assert [skill["id"] for skill in listed] == ["apple/apple-notes"]

    disabled = adapter.set_enabled("apple/apple-notes", False)
    assert disabled["enabled"] is False
    assert not (tmp_path / "skills" / "apple-notes" / "SKILL.md").exists()
    assert (tmp_path / "disabled-skills" / "apple-notes" / "SKILL.md").exists()

    restored = adapter.set_enabled("apple/apple-notes", True)
    assert restored["enabled"] is True
    assert (tmp_path / "skills" / "apple-notes" / "SKILL.md").exists()


def test_list_skills_skips_invalid_skill_names(tmp_path: Path):
    managed = tmp_path / "skills"
    valid_dir = managed / "weather"
    invalid_dir = managed / "word-docx"
    valid_dir.mkdir(parents=True)
    invalid_dir.mkdir(parents=True)
    (valid_dir / "SKILL.md").write_text(
        "---\nname: weather\ndescription: Weather lookup\n---\n",
        encoding="utf-8",
    )
    (invalid_dir / "SKILL.md").write_text(
        "---\nname: Word / DOCX\ndescription: Word documents\n---\n",
        encoding="utf-8",
    )
    adapter = HermesSkillAdapter(clawke_home=tmp_path)

    skills = adapter.list_skills()

    assert [skill["id"] for skill in skills] == ["general/weather"]


def test_ensure_hermes_extra_dir_keeps_managed_root_under_skills_block(
    tmp_path: Path,
    monkeypatch,
):
    hermes_home = tmp_path / "hermes"
    hermes_home.mkdir()
    config_path = hermes_home / "config.yaml"
    config_path.write_text(
        "\n".join([
            "model:",
            "  default: deepseek-v4-pro",
            "skills:",
            "  external_dirs:",
            "    - /existing/skills",
            "platforms:",
            "  api_server:",
            "    enabled: true",
            "    cors_origins: '*'",
            "",
        ]),
        encoding="utf-8",
    )
    monkeypatch.setenv("HERMES_HOME", str(hermes_home))

    adapter = HermesSkillAdapter(clawke_home=tmp_path / "clawke")

    assert adapter.ensure_hermes_extra_dir() is True
    assert adapter.ensure_hermes_extra_dir() is True

    config = yaml.safe_load(config_path.read_text(encoding="utf-8"))
    managed_root = str(adapter.managed_root)
    assert config["skills"]["external_dirs"] == ["/existing/skills", managed_root]
    assert config["platforms"]["api_server"]["cors_origins"] == "*"


def test_install_skillhub_package_uses_hermes_default_home(tmp_path: Path, monkeypatch):
    hermes_home = tmp_path / "hermes"
    clawke_home = tmp_path / "clawke"
    monkeypatch.setenv("HERMES_HOME", str(hermes_home))
    calls = []

    def fake_installer(identifier: str, hermes_home: Path, force: bool) -> None:
        calls.append((identifier, hermes_home, force))
        skill_dir = hermes_home / "skills" / "github-helper"
        skill_dir.mkdir(parents=True)
        (skill_dir / "SKILL.md").write_text(
            "---\nname: github-helper\ndescription: GitHub helper\n---\n",
            encoding="utf-8",
        )

    adapter = HermesSkillAdapter(
        clawke_home=clawke_home,
        external_roots=[hermes_home / "skills"],
        skillhub_installer=fake_installer,
    )

    installed = adapter.install_skillhub_package({
        "id": "204",
        "slug": "github-helper",
        "name": "GitHub Helper",
        "source": "clawhub",
        "packageType": "bundle",
    })

    assert calls == [("clawhub/github-helper", hermes_home.resolve(), True)]
    assert installed["id"] == "general/github-helper"
    assert installed["source"] == "external"
    assert installed["root"] == str((hermes_home / "skills").resolve())


@pytest.mark.asyncio
async def test_channel_skillhub_install_sends_accepted_then_async_status():
    from clawke_channel import ClawkeHermesGateway, GatewayConfig

    completed = asyncio.Event()

    class FakeAdapter:
        def install_skillhub_package(self, package):
            assert package["slug"] == "weather"
            return {"id": "general/weather", "name": "weather"}

    sent = []
    gateway = ClawkeHermesGateway(GatewayConfig(account_id="hermes"))
    gateway._skill_adapter = FakeAdapter()

    async def capture(data):
        sent.append(data)
        if data.get("type") == "skillhub_install_status" and data.get("status") == "installed":
            completed.set()

    gateway._send = capture

    await gateway._handle_skill_command({
        "type": "skillhub_install",
        "request_id": "skillhub_1",
        "install_id": "skillhub_1",
        "package": {
            "id": "404",
            "slug": "weather",
            "name": "Weather",
            "source": "clawhub",
        },
    })

    assert sent[0] == {
        "type": "skillhub_install_response",
        "request_id": "skillhub_1",
        "install_id": "skillhub_1",
        "ok": True,
        "installed": False,
        "status": "accepted",
        "message": "安装任务已提交",
    }
    await asyncio.wait_for(completed.wait(), timeout=1)
    statuses = [
        item for item in sent
        if item.get("type") == "skillhub_install_status"
    ]
    assert [item["status"] for item in statuses] == ["installing", "installed"]
    assert statuses[-1]["install_id"] == "skillhub_1"
    assert statuses[-1]["skill"]["id"] == "general/weather"
