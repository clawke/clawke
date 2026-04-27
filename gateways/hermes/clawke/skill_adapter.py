"""Gateway-host skill adapter for Hermes Clawke integration."""

from __future__ import annotations

import json
import os
import re
import shutil
import time
from pathlib import Path
from typing import Any

import yaml


SAFE_SEGMENT = re.compile(r"^[A-Za-z0-9][A-Za-z0-9._-]*$")


class HermesSkillAdapter:
    """Manage Clawke-owned skills on the gateway host."""

    def __init__(
        self,
        clawke_home: str | Path | None = None,
        external_roots: list[str | Path] | None = None,
    ):
        self.clawke_home = Path(
            clawke_home or os.environ.get("CLAWKE_HOME", "~/.clawke")
        ).expanduser().resolve()
        self.managed_root = self.clawke_home / "skills"
        self.disabled_root = self.clawke_home / "disabled-skills"
        self.state_path = self.clawke_home / "skills-state.json"
        hermes_home = Path(os.environ.get("HERMES_HOME", "~/.hermes")).expanduser()
        default_home = Path(os.environ.get("CLAWKE_HOME", "~/.clawke")).expanduser().resolve()
        roots = (
            external_roots
            if external_roots is not None
            else ([hermes_home / "skills", Path("~/.agents/skills")] if self.clawke_home == default_home else [])
        )
        self.external_roots = [Path(root).expanduser().resolve() for root in roots]

    def list_skills(self) -> list[dict[str, Any]]:
        by_id: dict[str, dict[str, Any]] = {}
        for root in self.external_roots:
            for skill in self._scan_root(root, True, "external", "Hermes skills", False, False):
                by_id[skill["id"]] = skill
        for skill in self._scan_root(self.managed_root, True, "managed", "Clawke skills", True, True):
            by_id[skill["id"]] = skill
        for skill in self._scan_root(
            self.disabled_root,
            False,
            "managed",
            "Clawke disabled skills",
            True,
            True,
        ):
            by_id[skill["id"]] = skill
        return sorted(by_id.values(), key=lambda item: item["id"])

    def list_runtime_skills(self) -> list[dict[str, str]]:
        return [
            {"name": skill["name"], "description": skill["description"]}
            for skill in self.list_skills()
            if skill.get("enabled") is True
        ]

    def get_skill(self, skill_id: str) -> dict[str, Any] | None:
        self._require_skill_id(skill_id)
        for skill in self.list_skills():
            if skill["id"] == skill_id:
                return skill
        return None

    def create_skill(self, draft: dict[str, Any]) -> dict[str, Any]:
        normalized = self._normalize_draft(draft)
        skill_id = self._skill_id(normalized["category"], normalized["name"])
        skill_dir = self._safe_path(self.managed_root, normalized["name"])
        disabled_dir = self._safe_path(self.disabled_root, normalized["name"])
        if skill_dir.exists() or disabled_dir.exists():
            raise ValueError(f"Skill already exists: {skill_id}")
        skill_dir.mkdir(parents=True, exist_ok=True)
        (skill_dir / "SKILL.md").write_text(
            self._build_content(normalized),
            encoding="utf-8",
        )
        self._record_state(
            skill_id,
            normalized,
            enabled=True,
            path=skill_dir,
            original_path=skill_dir,
            disabled_path=disabled_dir,
        )
        return self._require_skill(skill_id)

    def update_skill(self, skill_id: str, draft: dict[str, Any]) -> dict[str, Any]:
        existing = self._require_skill(skill_id)
        if not existing.get("writable"):
            raise ValueError(f"Skill is not writable: {skill_id}")

        normalized = self._normalize_draft({
            "name": draft.get("name", existing["name"]),
            "category": draft.get("category", existing["category"]),
            "description": draft.get("description", existing["description"]),
            "trigger": draft.get("trigger", existing.get("trigger")),
            "body": draft.get("body", draft.get("content", existing.get("body", ""))),
        })
        next_id = self._skill_id(normalized["category"], normalized["name"])
        current_dir = Path(existing["absolutePath"]).parent
        target_root = self.managed_root if existing.get("enabled") else self.disabled_root
        next_dir = self._safe_path(target_root, normalized["name"])
        if current_dir.resolve() != next_dir.resolve():
            if next_dir.exists():
                raise ValueError(f"Skill already exists: {next_id}")
            next_dir.parent.mkdir(parents=True, exist_ok=True)
            current_dir.rename(next_dir)

        (next_dir / "SKILL.md").write_text(self._build_content(normalized), encoding="utf-8")
        state = self._read_state()
        if next_id != skill_id:
            state["skills"].pop(skill_id, None)
        state["skills"][next_id] = {
            "skillId": next_id,
            "source": "managed",
            "category": normalized["category"],
            "name": normalized["name"],
            "enabled": bool(existing.get("enabled")),
            "disableMethod": None if existing.get("enabled") else "move",
            "path": str(next_dir),
            "originalPath": str(self._safe_path(self.managed_root, normalized["name"])),
            "disabledPath": str(self._safe_path(self.disabled_root, normalized["name"])),
            "lastSyncedAt": self._timestamp(),
        }
        self._write_state(state)
        return self._require_skill(next_id)

    def delete_skill(self, skill_id: str) -> bool:
        existing = self._require_skill(skill_id)
        if not existing.get("deletable"):
            raise ValueError(f"Skill is not deletable: {skill_id}")
        shutil.rmtree(Path(existing["absolutePath"]).parent, ignore_errors=True)
        state = self._read_state()
        state["skills"].pop(skill_id, None)
        self._write_state(state)
        return True

    def set_enabled(self, skill_id: str, enabled: bool) -> dict[str, Any]:
        existing = self._require_skill(skill_id)
        if existing.get("source") != "managed":
            raise ValueError(f"Only Clawke-managed skills can be enabled or disabled: {skill_id}")
        if existing.get("enabled") is enabled:
            return existing

        name = existing["name"]
        original_dir = self._safe_path(self.managed_root, name)
        disabled_dir = self._safe_path(self.disabled_root, name)
        if enabled:
            if not disabled_dir.exists():
                raise ValueError(f"Disabled skill not found: {skill_id}")
            if original_dir.exists():
                raise ValueError(f"Skill target already exists: {skill_id}")
            self.managed_root.mkdir(parents=True, exist_ok=True)
            disabled_dir.rename(original_dir)
        else:
            if not original_dir.exists():
                raise ValueError(f"Skill not found in managed root: {skill_id}")
            if disabled_dir.exists():
                raise ValueError(f"Disabled skill already exists: {skill_id}")
            self.disabled_root.mkdir(parents=True, exist_ok=True)
            original_dir.rename(disabled_dir)

        state = self._read_state()
        state["skills"][skill_id] = {
            "skillId": skill_id,
            "source": "managed",
            "category": existing["category"],
            "name": name,
            "enabled": enabled,
            "disableMethod": None if enabled else "move",
            "path": str(original_dir if enabled else disabled_dir),
            "originalPath": str(original_dir),
            "disabledPath": str(disabled_dir),
            "disabledAt": None if enabled else self._timestamp(),
            "lastSyncedAt": self._timestamp(),
        }
        self._write_state(state)
        return self._require_skill(skill_id)

    def ensure_hermes_extra_dir(self) -> bool:
        """Best-effort config update so Hermes can load Clawke-managed skills."""
        hermes_home = Path(os.environ.get("HERMES_HOME", "~/.hermes")).expanduser()
        config_path = hermes_home / "config.yaml"
        try:
            config_path.parent.mkdir(parents=True, exist_ok=True)
            text = config_path.read_text(encoding="utf-8") if config_path.exists() else ""
            loaded = yaml.safe_load(text) if text.strip() else {}
            if loaded is None:
                loaded = {}
            if not isinstance(loaded, dict):
                return False

            changed = not text.strip()
            skills = loaded.get("skills")
            if not isinstance(skills, dict):
                skills = {}
                loaded["skills"] = skills
                changed = True

            external_dirs = skills.get("external_dirs")
            if external_dirs is None:
                external_dirs = []
                changed = True
            elif not isinstance(external_dirs, list):
                external_dirs = [external_dirs]
                changed = True

            managed_root = str(self.managed_root)
            if managed_root not in {str(root) for root in external_dirs}:
                external_dirs.append(managed_root)
                changed = True
            skills["external_dirs"] = external_dirs

            if changed:
                config_path.write_text(
                    yaml.safe_dump(loaded, sort_keys=False, allow_unicode=True),
                    encoding="utf-8",
                )
            return True
        except Exception:
            return False

    def _scan_root(
        self,
        root: Path,
        enabled: bool,
        source: str,
        source_label: str,
        writable: bool,
        deletable: bool,
    ) -> list[dict[str, Any]]:
        if not root.is_dir():
            return []
        return [
            self._read_skill(root, skill_md, enabled, source, source_label, writable, deletable)
            for skill_md in root.rglob("SKILL.md")
            if not any(part.startswith(".") for part in skill_md.relative_to(root).parts)
        ]

    def _read_skill(
        self,
        root: Path,
        skill_md: Path,
        enabled: bool,
        source: str,
        source_label: str,
        writable: bool,
        deletable: bool,
    ) -> dict[str, Any]:
        content = skill_md.read_text(encoding="utf-8", errors="replace")
        frontmatter, body = self._parse_content(content)
        rel_parts = skill_md.parent.relative_to(root).parts
        fallback_name = rel_parts[-1] if rel_parts else "skill"
        fallback_category = rel_parts[-2] if len(rel_parts) > 1 else "general"
        name = str(frontmatter.get("name") or fallback_name).strip()
        category = str(frontmatter.get("category") or fallback_category).strip()
        return {
            "id": self._skill_id(category, name),
            "name": name,
            "description": str(frontmatter.get("description") or name).strip(),
            "category": category,
            "trigger": frontmatter.get("trigger"),
            "enabled": enabled,
            "source": source,
            "sourceLabel": source_label,
            "writable": writable,
            "deletable": deletable,
            "path": str(skill_md.relative_to(root)),
            "absolutePath": str(skill_md.resolve()),
            "root": str(root.resolve()),
            "updatedAt": skill_md.stat().st_mtime * 1000,
            "hasConflict": False,
            "content": content,
            "body": body,
            "frontmatter": frontmatter,
        }

    @staticmethod
    def _parse_content(content: str) -> tuple[dict[str, str], str]:
        match = re.match(r"^---\s*\r?\n([\s\S]*?)\r?\n---\s*\r?\n?", content)
        if not match:
            return {}, content
        frontmatter: dict[str, str] = {}
        for line in match.group(1).splitlines():
            pair = re.match(r"^([A-Za-z0-9_-]+):\s*(.*)$", line)
            if pair:
                frontmatter[pair.group(1)] = pair.group(2).strip().strip("\"'")
        return frontmatter, content[match.end():]

    def _normalize_draft(self, draft: dict[str, Any]) -> dict[str, str]:
        name = str(draft.get("name") or "").strip()
        category = str(draft.get("category") or "general").strip()
        description = str(draft.get("description") or "").strip()
        self._require_safe_segment(name, "skill name")
        self._require_safe_segment(category, "skill category")
        if not description:
            raise ValueError("description is required")
        return {
            "name": name,
            "category": category,
            "description": description,
            "trigger": str(draft.get("trigger") or "").strip(),
            "body": str(draft.get("body", draft.get("content", ""))),
        }

    @staticmethod
    def _build_content(draft: dict[str, str]) -> str:
        lines = [
            "---",
            f"name: {draft['name']}",
            f"category: {draft['category']}",
            f"description: {draft['description']}",
        ]
        if draft.get("trigger"):
            lines.append(f"trigger: {draft['trigger']}")
        lines.extend(["---", ""])
        return "\n".join(lines) + draft.get("body", "")

    def _record_state(
        self,
        skill_id: str,
        draft: dict[str, str],
        *,
        enabled: bool,
        path: Path,
        original_path: Path,
        disabled_path: Path,
    ) -> None:
        state = self._read_state()
        state["skills"][skill_id] = {
            "skillId": skill_id,
            "source": "managed",
            "category": draft["category"],
            "name": draft["name"],
            "enabled": enabled,
            "path": str(path),
            "originalPath": str(original_path),
            "disabledPath": str(disabled_path),
            "lastSyncedAt": self._timestamp(),
        }
        self._write_state(state)

    def _read_state(self) -> dict[str, Any]:
        if not self.state_path.exists():
            return {"version": 1, "skills": {}}
        try:
            data = json.loads(self.state_path.read_text(encoding="utf-8"))
            if not isinstance(data, dict):
                return {"version": 1, "skills": {}}
            skills = data.get("skills")
            return {"version": 1, "skills": skills if isinstance(skills, dict) else {}}
        except Exception:
            return {"version": 1, "skills": {}}

    def _write_state(self, state: dict[str, Any]) -> None:
        self.state_path.parent.mkdir(parents=True, exist_ok=True)
        self.state_path.write_text(json.dumps(state, ensure_ascii=False, indent=2) + "\n", encoding="utf-8")

    def _require_skill(self, skill_id: str) -> dict[str, Any]:
        skill = self.get_skill(skill_id)
        if not skill:
            raise ValueError(f"Skill not found: {skill_id}")
        return skill

    def _skill_id(self, category: str, name: str) -> str:
        self._require_safe_segment(category, "skill category")
        self._require_safe_segment(name, "skill name")
        return f"{category}/{name}"

    def _require_skill_id(self, skill_id: str) -> None:
        parts = skill_id.split("/")
        if len(parts) != 2:
            raise ValueError(f"Invalid skill id: {skill_id}")
        self._require_safe_segment(parts[0], "skill category")
        self._require_safe_segment(parts[1], "skill name")

    def _safe_path(self, root: Path, segment: str) -> Path:
        self._require_safe_segment(segment, "skill name")
        target = (root / segment).resolve()
        root = root.resolve()
        if target != root and root not in target.parents:
            raise ValueError(f"Invalid path segment: {segment}")
        return target

    @staticmethod
    def _require_safe_segment(value: str, label: str) -> None:
        if not SAFE_SEGMENT.match(value) or value in {".", ".."}:
            raise ValueError(f"Invalid {label}: {value}")

    @staticmethod
    def _timestamp() -> str:
        return time.strftime("%Y-%m-%dT%H:%M:%SZ", time.gmtime())
