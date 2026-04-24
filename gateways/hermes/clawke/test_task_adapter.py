"""Tests for Hermes task adapter."""

from __future__ import annotations

import sys
import threading
import time
import types
from pathlib import Path

import pytest


@pytest.fixture
def cron_jobs(monkeypatch, tmp_path):
    cron_mod = types.ModuleType("cron")
    jobs_mod = types.ModuleType("cron.jobs")
    jobs_mod.OUTPUT_DIR = tmp_path
    jobs_mod.calls = []
    jobs_mod.jobs = [
        {
            "id": "job_1",
            "name": "Daily brief",
            "schedule": "0 9 * * *",
            "prompt": "Summarize the day",
            "enabled": True,
            "skill_ids": ["news", "calendar"],
            "deliver": "notification",
            "created_at": "2026-04-24T01:00:00Z",
            "updated_at": "2026-04-24T02:00:00Z",
        },
        {
            "id": "job_2",
            "name": "Paused task",
            "cron": "0 17 * * 5",
            "prompt": "Weekly wrap",
            "enabled": False,
            "skills": ["writing"],
        },
        {
            "id": "job_3",
            "name": "Structured schedule",
            "schedule": {"type": "daily", "hour": 9},
            "schedule_display": "Every day at 9:00 AM",
            "prompt": "Structured prompt",
            "enabled": True,
        },
    ]

    def list_jobs(include_disabled=False):
        jobs_mod.calls.append(("list_jobs", include_disabled))
        return [
            job for job in jobs_mod.jobs
            if include_disabled or job.get("enabled", True)
        ]

    def create_job(*, prompt, schedule, name=None, deliver=None, skills=None, skill=None, **kwargs):
        jobs_mod.calls.append(("create_job", {
            "prompt": prompt,
            "schedule": schedule,
            "name": name,
            "deliver": deliver,
            "skills": skills,
            "skill": skill,
            "extra": kwargs,
        }))
        job = {
            "id": "job_new",
            "name": name,
            "schedule": schedule,
            "prompt": prompt,
            "enabled": True,
            "deliver": deliver,
            "skills": skills or ([skill] if skill else []),
        }
        jobs_mod.jobs.append(job)
        return job

    def update_job(task_id, updates):
        jobs_mod.calls.append(("update_job", task_id, updates))
        for job in jobs_mod.jobs:
            if job["id"] == task_id:
                job.update(updates)
                return job
        return None

    def remove_job(task_id):
        jobs_mod.calls.append(("remove_job", task_id))
        return True

    def pause_job(task_id):
        jobs_mod.calls.append(("pause_job", task_id))
        return {"id": task_id, "enabled": False}

    def resume_job(task_id):
        jobs_mod.calls.append(("resume_job", task_id))
        return {"id": task_id, "enabled": True}

    def get_job(task_id):
        jobs_mod.calls.append(("get_job", task_id))
        for job in jobs_mod.jobs:
            if job["id"] == task_id:
                return dict(job)
        return None

    jobs_mod.list_jobs = list_jobs
    jobs_mod.create_job = create_job
    jobs_mod.update_job = update_job
    jobs_mod.remove_job = remove_job
    jobs_mod.pause_job = pause_job
    jobs_mod.resume_job = resume_job
    jobs_mod.get_job = get_job
    cron_mod.jobs = jobs_mod
    monkeypatch.setitem(sys.modules, "cron", cron_mod)
    monkeypatch.setitem(sys.modules, "cron.jobs", jobs_mod)
    return jobs_mod


@pytest.fixture
def adapter(cron_jobs):
    from task_adapter import HermesTaskAdapter

    return HermesTaskAdapter()


def test_list_tasks_maps_cron_jobs_to_normalized_tasks(adapter, cron_jobs):
    tasks = adapter.list_tasks("acct_1")

    assert [task["id"] for task in tasks] == ["job_1", "job_2", "job_3"]
    assert tasks[0] == {
        "id": "job_1",
        "account_id": "acct_1",
        "agent": "hermes",
        "name": "Daily brief",
        "schedule": "0 9 * * *",
        "schedule_text": "0 9 * * *",
        "prompt": "Summarize the day",
        "enabled": True,
        "status": "active",
        "skills": ["news", "calendar"],
        "deliver": "notification",
        "created_at": "2026-04-24T01:00:00Z",
        "updated_at": "2026-04-24T02:00:00Z",
    }
    assert tasks[1]["schedule"] == "0 17 * * 5"
    assert tasks[1]["status"] == "paused"
    assert tasks[2]["schedule"] == "Every day at 9:00 AM"
    assert tasks[2]["schedule_text"] == "Every day at 9:00 AM"
    assert cron_jobs.calls[0] == ("list_jobs", True)


def test_get_task_returns_matching_task_or_none(adapter):
    assert adapter.get_task("acct_1", "job_2")["id"] == "job_2"
    assert adapter.get_task("acct_1", "missing") is None


def test_create_update_delete_call_cron_jobs(adapter, cron_jobs):
    created = adapter.create_task(
        "acct_1",
        {
            "name": "New task",
            "schedule": "*/30 * * * *",
            "prompt": "Check status",
            "deliver": "chat",
            "skills": ["ops"],
        },
    )

    assert created["id"] == "job_new"
    assert created["account_id"] == "acct_1"
    assert ("create_job", {
        "prompt": "Check status",
        "schedule": "*/30 * * * *",
        "name": "New task",
        "deliver": "chat",
        "skills": ["ops"],
        "skill": None,
        "extra": {},
    }) in cron_jobs.calls

    updated = adapter.update_task(
        "acct_1",
        "job_new",
        {
            "name": "Renamed",
            "schedule": "0 * * * *",
            "prompt": "Do it",
            "deliver": "notification",
            "skills": ["ops", "audit"],
            "skill_ids": ["legacy"],
            "unsupported": "ignored",
        },
    )

    assert updated["name"] == "Renamed"
    update_call = next(call for call in cron_jobs.calls if call[0] == "update_job")
    assert update_call == (
        "update_job",
        "job_new",
        {
            "name": "Renamed",
            "schedule": "0 * * * *",
            "prompt": "Do it",
            "deliver": "notification",
            "skills": ["ops", "audit"],
        },
    )

    cron_jobs.calls.clear()
    adapter.update_task("acct_1", "job_new", {"skill_ids": ["legacy"]})
    assert cron_jobs.calls == [(
        "update_job",
        "job_new",
        {"skills": ["legacy"]},
    )]

    assert adapter.delete_task("job_new") is True
    assert ("remove_job", "job_new") in cron_jobs.calls


def test_set_enabled_pauses_and_resumes(adapter, cron_jobs):
    paused = adapter.set_enabled("acct_1", "job_1", False)
    resumed = adapter.set_enabled("acct_1", "job_1", True)

    assert paused["enabled"] is False
    assert paused["status"] == "paused"
    assert resumed["enabled"] is True
    assert resumed["status"] == "active"
    assert ("pause_job", "job_1") in cron_jobs.calls
    assert ("resume_job", "job_1") in cron_jobs.calls


def test_list_runs_and_get_output_read_output_files(adapter, cron_jobs):
    task_dir = Path(cron_jobs.OUTPUT_DIR) / "job_1"
    task_dir.mkdir()
    (task_dir / "run_a.txt").write_text("First run output", encoding="utf-8")
    (task_dir / "run_b.md").write_text("Second run output is longer", encoding="utf-8")

    runs = adapter.list_runs("job_1")

    assert [run["id"] for run in runs] == ["run_b", "run_a"]
    assert runs[0]["task_id"] == "job_1"
    assert runs[0]["status"] == "success"
    assert runs[0]["output_preview"] == "Second run output is longer"
    assert adapter.get_output("job_1", "run_a") == "First run output"
    assert adapter.get_output("job_1", "run_b") == "Second run output is longer"
    assert adapter.get_output("job_1", "missing") == ""


def test_output_reads_reject_path_traversal(adapter):
    outside_dir = adapter._output_dir().parent
    (outside_dir / "outside.txt").write_text("outside", encoding="utf-8")

    assert adapter.list_runs("../job_1") == []
    assert adapter.list_runs("nested/job_1") == []
    assert adapter.get_output("../job_1", "run_a") == ""
    assert adapter.get_output("job_1", "../run_a") == ""
    assert adapter.get_output("job_1", "nested/run_a") == ""
    assert adapter.get_output("..", "outside") == ""


@pytest.mark.asyncio
async def test_run_task_invokes_scheduler_and_returns_running_summary(adapter, cron_jobs, monkeypatch):
    scheduler_mod = types.ModuleType("cron.scheduler")
    scheduler_mod.calls = []

    def run_job(job):
        scheduler_mod.calls.append(("run_job", job["id"]))

    scheduler_mod.run_job = run_job
    monkeypatch.setitem(sys.modules, "cron.scheduler", scheduler_mod)

    run = adapter.run_task("job_1")

    assert run["task_id"] == "job_1"
    assert run["status"] == "running"
    assert run["id"].startswith("manual_")
    assert ("get_job", "job_1") in cron_jobs.calls
    assert scheduler_mod.calls == [("run_job", "job_1")]


def test_run_task_starts_scheduler_in_background(adapter, cron_jobs, monkeypatch):
    scheduler_mod = types.ModuleType("cron.scheduler")
    started = threading.Event()
    release = threading.Event()

    def run_job(job):
        started.set()
        release.wait(timeout=1)

    scheduler_mod.run_job = run_job
    monkeypatch.setitem(sys.modules, "cron.scheduler", scheduler_mod)

    start = time.monotonic()
    run = adapter.run_task("job_1")
    elapsed = time.monotonic() - start

    try:
        assert run["status"] == "running"
        assert elapsed < 0.2
        assert started.wait(timeout=0.2)
    finally:
        release.set()


def test_channel_declares_task_inbound_message_types():
    from clawke_channel import InboundMessageType

    assert InboundMessageType.TaskList == "task_list"
    assert InboundMessageType.TaskGet == "task_get"
    assert InboundMessageType.TaskCreate == "task_create"
    assert InboundMessageType.TaskUpdate == "task_update"
    assert InboundMessageType.TaskDelete == "task_delete"
    assert InboundMessageType.TaskSetEnabled == "task_set_enabled"
    assert InboundMessageType.TaskRun == "task_run"
    assert InboundMessageType.TaskRuns == "task_runs"
    assert InboundMessageType.TaskOutput == "task_output"


@pytest.mark.asyncio
async def test_channel_task_command_sends_response(monkeypatch):
    from clawke_channel import ClawkeHermesGateway, GatewayConfig

    class FakeAdapter:
        def list_tasks(self, account_id):
            return [{"id": "job_1", "account_id": account_id}]

    sent = []
    gateway = ClawkeHermesGateway(GatewayConfig(account_id="acct_1"))
    gateway._task_adapter = FakeAdapter()

    async def capture(data):
        sent.append(data)

    gateway._send = capture

    await gateway._handle_task_command({
        "type": "task_list",
        "request_id": "req_1",
        "account_id": "acct_1",
    })

    assert sent == [{
        "type": "task_list_response",
        "request_id": "req_1",
        "ok": True,
        "tasks": [{"id": "job_1", "account_id": "acct_1"}],
    }]


@pytest.mark.asyncio
@pytest.mark.parametrize(("msg", "expected"), [
    ({"type": "task_create", "task": {"name": "New"}}, {"type": "task_mutation_response", "task": {"id": "created"}}),
    ({"type": "task_update", "task_id": "job_1", "patch": {"name": "Renamed"}}, {"type": "task_mutation_response", "task": {"id": "updated"}}),
    ({"type": "task_delete", "task_id": "job_1"}, {"type": "task_mutation_response", "deleted": True}),
    ({"type": "task_set_enabled", "task_id": "job_1", "enabled": False}, {"type": "task_mutation_response", "task": {"id": "enabled"}}),
    ({"type": "task_run", "task_id": "job_1"}, {"type": "task_run_response", "runs": [{"id": "run_1"}]}),
])
async def test_channel_task_command_response_contract(msg, expected):
    from clawke_channel import ClawkeHermesGateway, GatewayConfig

    class FakeAdapter:
        def create_task(self, account_id, task):
            return {"id": "created"}

        def update_task(self, account_id, task_id, patch):
            return {"id": "updated"}

        def delete_task(self, task_id):
            return True

        def set_enabled(self, account_id, task_id, enabled):
            return {"id": "enabled"}

        def run_task(self, task_id):
            return {"id": "run_1"}

    sent = []
    gateway = ClawkeHermesGateway(GatewayConfig(account_id="acct_1"))
    gateway._task_adapter = FakeAdapter()

    async def capture(data):
        sent.append(data)

    gateway._send = capture
    outbound = {"request_id": "req_contract", "account_id": "acct_1", **msg}

    await gateway._handle_task_command(outbound)

    assert sent[0]["request_id"] == "req_contract"
    assert sent[0]["ok"] is True
    for key, value in expected.items():
        assert sent[0][key] == value


@pytest.mark.asyncio
async def test_channel_task_command_errors_are_structured():
    from clawke_channel import ClawkeHermesGateway, GatewayConfig

    class FakeAdapter:
        def get_task(self, account_id, task_id):
            raise RuntimeError("boom")

    sent = []
    gateway = ClawkeHermesGateway(GatewayConfig(account_id="acct_1"))
    gateway._task_adapter = FakeAdapter()

    async def capture(data):
        sent.append(data)

    gateway._send = capture

    await gateway._handle_task_command({
        "type": "task_get",
        "request_id": "req_2",
        "account_id": "acct_1",
        "task_id": "job_1",
    })

    assert sent == [{
        "type": "task_get_response",
        "request_id": "req_2",
        "ok": False,
        "error": "task_error",
        "message": "boom",
    }]
