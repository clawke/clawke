"""Hermes task protocol adapter for Clawke task commands."""

from __future__ import annotations

import importlib
import time
from pathlib import Path
from typing import Any


class HermesTaskAdapter:
    """Map Clawke task commands to Hermes cron APIs."""

    agent = "hermes"

    def list_tasks(self, account_id: str) -> list[dict[str, Any]]:
        jobs_api = self._jobs()
        try:
            jobs = jobs_api.list_jobs(include_disabled=True)
        except TypeError:
            jobs = jobs_api.list_jobs()
        return [self._normalize_task(account_id, job) for job in jobs]

    def get_task(self, account_id: str, task_id: str) -> dict[str, Any] | None:
        for task in self.list_tasks(account_id):
            if task["id"] == task_id:
                return task
        return None

    def create_task(self, account_id: str, draft: dict[str, Any]) -> dict[str, Any]:
        jobs = self._jobs()
        job = jobs.create_job(
            prompt=draft.get("prompt", ""),
            schedule=draft.get("schedule", ""),
            name=draft.get("name") or None,
            deliver=draft.get("deliver"),
            skills=draft.get("skills") or draft.get("skill_ids") or [],
        )
        return self._normalize_task(account_id, job)

    def update_task(
        self,
        account_id: str,
        task_id: str,
        patch: dict[str, Any],
    ) -> dict[str, Any] | None:
        supported: dict[str, Any] = {}
        for field in ("name", "schedule", "prompt", "deliver"):
            if field in patch:
                supported[field] = patch[field]
        if "skills" in patch:
            supported["skills"] = patch["skills"]
        elif "skill_ids" in patch:
            supported["skills"] = patch["skill_ids"]

        job = self._jobs().update_job(task_id, supported)
        if job is None:
            return None
        return self._normalize_task(account_id, job)

    def delete_task(self, task_id: str) -> bool:
        return bool(self._jobs().remove_job(task_id))

    def set_enabled(
        self,
        account_id: str,
        task_id: str,
        enabled: bool,
    ) -> dict[str, Any]:
        jobs = self._jobs()
        job = jobs.resume_job(task_id) if enabled else jobs.pause_job(task_id)
        return self._normalize_task(account_id, job)

    def list_runs(self, task_id: str) -> list[dict[str, Any]]:
        task_dir = self._output_dir() / task_id
        if not task_dir.is_dir():
            return []

        paths = list(task_dir.glob("*.md")) + list(task_dir.glob("*.txt"))
        runs = [self._run_summary(task_id, path) for path in paths]
        runs.sort(
            key=lambda run: (run.get("_mtime", 0.0), run.get("id", "")),
            reverse=True,
        )
        for run in runs:
            run.pop("_mtime", None)
        return runs

    def get_output(self, task_id: str, run_id: str) -> str:
        task_dir = self._output_dir() / task_id
        for suffix in (".md", ".txt"):
            path = task_dir / f"{run_id}{suffix}"
            if path.is_file():
                return path.read_text(encoding="utf-8", errors="replace")
        return ""

    def run_task(self, task_id: str) -> dict[str, Any]:
        job = self._jobs().get_job(task_id)
        if not job:
            raise ValueError(f"Task not found: {task_id}")
        self._scheduler().run_job(job)
        now = self._timestamp()
        return {
            "id": f"manual_{int(time.time() * 1000)}",
            "task_id": task_id,
            "started_at": now,
            "status": "running",
        }

    def _normalize_task(self, account_id: str, job: Any) -> dict[str, Any]:
        raw = self._as_dict(job)
        schedule = raw.get("schedule") or raw.get("cron") or ""
        enabled = bool(raw.get("enabled", True))
        return {
            "id": str(raw.get("id") or raw.get("job_id") or raw.get("name") or ""),
            "account_id": account_id,
            "agent": self.agent,
            "name": str(raw.get("name") or ""),
            "schedule": str(schedule),
            "schedule_text": str(raw.get("schedule_text") or schedule),
            "prompt": str(raw.get("prompt") or ""),
            "enabled": enabled,
            "status": "active" if enabled else "paused",
            "skills": list(raw.get("skills") or raw.get("skill_ids") or []),
            "deliver": raw.get("deliver"),
            "created_at": raw.get("created_at"),
            "updated_at": raw.get("updated_at"),
        }

    def _run_summary(self, task_id: str, path: Path) -> dict[str, Any]:
        stat = path.stat()
        text = path.read_text(encoding="utf-8", errors="replace")
        return {
            "id": path.stem,
            "task_id": task_id,
            "started_at": self._timestamp(stat.st_mtime),
            "finished_at": self._timestamp(stat.st_mtime),
            "status": "success",
            "output_preview": text[:200],
            "_mtime": stat.st_mtime,
        }

    def _output_dir(self) -> Path:
        return Path(self._jobs().OUTPUT_DIR)

    @staticmethod
    def _jobs():
        return importlib.import_module("cron.jobs")

    @staticmethod
    def _scheduler():
        return importlib.import_module("cron.scheduler")

    @staticmethod
    def _as_dict(value: Any) -> dict[str, Any]:
        if isinstance(value, dict):
            return dict(value)
        if hasattr(value, "__dict__"):
            return dict(vars(value))
        return {}

    @staticmethod
    def _timestamp(seconds: float | None = None) -> str:
        return time.strftime("%Y-%m-%dT%H:%M:%SZ", time.gmtime(seconds or time.time()))
