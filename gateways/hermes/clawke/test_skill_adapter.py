from __future__ import annotations

from pathlib import Path

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
