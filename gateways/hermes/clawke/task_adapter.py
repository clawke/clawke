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
        jobs = self._jobs().list_jobs()
        return [self._normalize_task(account_id, job) for job in jobs]

    def get_task(self, account_id: str, task_id: str) -> dict[str, Any] | None:
        for task in self.list_tasks(account_id):
            if task["id"] == task_id:
                return task
        return None

    def create_task(self, account_id: str, draft: dict[str, Any]) -> dict[str, Any]:
        jobs = self._jobs()
        job = jobs.create_job(
            draft.get("name") or draft.get("prompt", "Task"),
            draft.get("schedule", ""),
            draft.get("prompt", ""),
            draft.get("deliver"),
            draft.get("skills") or draft.get("skill_ids") or [],
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
            supported["skill_ids"] = patch["skills"]
        elif "skill_ids" in patch:
            supported["skill_ids"] = patch["skill_ids"]

        job = self._jobs().update_job(task_id, **supported)
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

        runs = [self._run_summary(task_id, path) for path in task_dir.glob("*.txt")]
        runs.sort(key=lambda run: run.get("started_at", ""), reverse=True)
        return runs

    def get_output(self, task_id: str, run_id: str) -> str:
        path = self._output_dir() / task_id / f"{run_id}.txt"
        if not path.is_file():
            return ""
        return path.read_text(encoding="utf-8", errors="replace")

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
