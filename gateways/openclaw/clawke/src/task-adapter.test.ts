import test from "node:test";
import assert from "node:assert/strict";
import { mkdtemp, rm } from "node:fs/promises";
import { join } from "node:path";
import { tmpdir } from "node:os";
import { OpenClawTaskAdapter } from "./task-adapter.js";

test("OpenClawTaskAdapter manages tasks and run output in gateway storage", async () => {
  const root = await mkdtemp(join(tmpdir(), "openclaw-task-adapter-"));
  try {
    const adapter = new OpenClawTaskAdapter(root);

    const created = await adapter.createTask("acct_1", {
      name: "Morning check",
      schedule: "0 9 * * *",
      prompt: "Summarize overnight changes",
      enabled: true,
      skills: ["summarizer"],
      deliver: "clawke",
    });

    assert.equal(created.account_id, "acct_1");
    assert.equal(created.agent, "openclaw");
    assert.equal(created.status, "active");
    assert.equal(created.name, "Morning check");
    assert.equal(created.schedule, "0 9 * * *");
    assert.equal(created.prompt, "Summarize overnight changes");
    assert.deepEqual(created.skills, ["summarizer"]);
    assert.equal(created.deliver, "clawke");
    assert.match(created.id, /^[a-zA-Z0-9_-]+$/);

    const listed = await adapter.listTasks("acct_1");
    assert.equal(listed.length, 1);
    assert.equal(listed[0].id, created.id);

    const fetched = await adapter.getTask("acct_1", created.id);
    assert.equal(fetched.id, created.id);

    const updated = await adapter.updateTask("acct_1", created.id, {
      name: "Updated check",
      enabled: false,
    });
    assert.equal(updated.name, "Updated check");
    assert.equal(updated.enabled, false);
    assert.equal(updated.status, "paused");
    assert.notEqual(updated.updated_at, created.updated_at);

    const enabled = await adapter.setEnabled("acct_1", created.id, true);
    assert.equal(enabled.enabled, true);
    assert.equal(enabled.status, "active");

    const run = await adapter.runTask("acct_1", created.id);
    assert.equal(run.task_id, created.id);
    assert.equal(run.status, "running");
    assert.match(run.output_preview ?? "", /triggered from Clawke/);

    const runs = await adapter.listRuns(created.id);
    assert.equal(runs.length, 1);
    assert.equal(runs[0].id, run.id);

    const output = await adapter.getOutput(created.id, run.id);
    assert.equal(output.task_id, created.id);
    assert.equal(output.run_id, run.id);
    assert.match(output.text, /Task was triggered from Clawke/);
    assert.doesNotMatch(output.text, /executed the prompt/i);

    await assert.rejects(
      () => adapter.getTask("acct_1", "../escape"),
      /Invalid task id/,
    );
    await assert.rejects(
      () => adapter.getOutput(created.id, "../escape"),
      /Invalid run id/,
    );

    assert.equal(await adapter.deleteTask("acct_1", created.id), true);
    assert.equal(await adapter.getTask("acct_1", created.id), null);
    assert.deepEqual(await adapter.listTasks("acct_1"), []);
  } finally {
    await rm(root, { recursive: true, force: true });
  }
});
