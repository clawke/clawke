import test from "node:test";
import assert from "node:assert/strict";
import { createHash } from "node:crypto";
import { mkdtemp, rm } from "node:fs/promises";
import { existsSync, mkdirSync, readFileSync, writeFileSync } from "node:fs";
import { join } from "node:path";
import { tmpdir } from "node:os";
import { OpenClawSkillAdapter, LegacyLocalOpenClawSkillAdapter } from "./skill-adapter.ts";

test("OpenClawSkillAdapter lists and toggles skills through OpenClaw Gateway RPC", async () => {
  const calls: Array<{ method: string; params?: unknown }> = [];
  const root = await mkdtemp(join(tmpdir(), "openclaw-rpc-skill-list-"));
  try {
    const adapter = new OpenClawSkillAdapter(root, {
      rpc: async (method, params) => {
        calls.push({ method, params });
        if (method === "skills.status") {
          return {
            skills: [
              {
                skillKey: "web-search",
                name: "web-search",
                description: "Search the web",
                source: "openclaw-bundled",
                bundled: true,
                filePath: "/opt/openclaw/skills/web-search/SKILL.md",
                baseDir: "/opt/openclaw/skills/web-search",
                disabled: false,
                eligible: true,
                always: false,
                missing: {},
              },
            ],
          };
        }
        if (method === "skills.update") {
          assert.deepEqual(params, { skillKey: "web-search", enabled: false });
          return { ok: true, skillKey: "web-search" };
        }
        throw new Error(`Unexpected method: ${method}`);
      },
    });

    const listed = await adapter.listSkills();

    assert.equal(listed.length, 1);
    assert.equal(listed[0].id, "openclaw-bundled/web-search");
    assert.equal(listed[0].enabled, true);
    assert.equal(listed[0].writable, false);
    assert.equal(listed[0].deletable, false);
    assert.equal(listed[0].path, "/opt/openclaw/skills/web-search/SKILL.md");

    const disabled = await adapter.setEnabled("openclaw-bundled/web-search", false);

    assert.equal(disabled.id, "openclaw-bundled/web-search");
    assert.equal(calls[0].method, "skills.status");
    assert.deepEqual(calls[1], {
      method: "skills.update",
      params: { skillKey: "web-search", enabled: false },
    });
  } finally {
    await rm(root, { recursive: true, force: true });
  }
});

test("OpenClawSkillAdapter gets duplicate skill names by full source id", async () => {
  const adapter = new OpenClawSkillAdapter(undefined, {
    rpc: async (method) => {
      assert.equal(method, "skills.status");
      return {
        skills: [
          {
            skillKey: "duplicate",
            name: "duplicate",
            description: "Built-in duplicate",
            source: "openclaw-bundled",
            bundled: true,
            disabled: false,
          },
          {
            skillKey: "duplicate",
            name: "duplicate",
            description: "Personal duplicate",
            source: "agents-skills-personal",
            bundled: false,
            disabled: false,
          },
        ],
      };
    },
  });

  const personal = await adapter.getSkill("agents-skills-personal/duplicate");
  const bundled = await adapter.getSkill("openclaw-bundled/duplicate");

  assert.equal(personal?.id, "agents-skills-personal/duplicate");
  assert.equal(personal?.description, "Personal duplicate");
  assert.equal(bundled?.id, "openclaw-bundled/duplicate");
  assert.equal(bundled?.description, "Built-in duplicate");
});

test("OpenClawSkillAdapter falls back to local Clawke skills when RPC skill status fails", async () => {
  const root = await mkdtemp(join(tmpdir(), "openclaw-rpc-local-fallback-"));
  try {
    writeSkill(join(root, "skills"), "weather", "weather", "Weather lookup");
    writeSkill(join(root, "skills"), "word-docx", "Word / DOCX", "Word documents");
    const adapter = new OpenClawSkillAdapter(root, {
      rpc: async (method) => {
        assert.equal(method, "skills.status");
        throw new Error("Invalid skill name: Word / DOCX");
      },
    });

    const listed = await adapter.listSkills();

    assert.deepEqual(listed.map((skill) => skill.id), ["general/weather"]);
  } finally {
    await rm(root, { recursive: true, force: true });
  }
});

test("OpenClawSkillAdapter shows shadowed Clawke managed skills", async () => {
  const root = await mkdtemp(join(tmpdir(), "openclaw-rpc-shadowed-skill-"));
  try {
    writeSkill(join(root, "skills"), "openclaw-github-assistant", "github", "Clawke GitHub helper");
    const adapter = new OpenClawSkillAdapter(root, {
      rpc: async (method) => {
        assert.equal(method, "skills.status");
        return {
          skills: [
            {
              skillKey: "github",
              name: "github",
              description: "Built-in GitHub helper",
              source: "openclaw-bundled",
              bundled: true,
              disabled: false,
            },
          ],
        };
      },
    });

    const listed = await adapter.listSkills();

    assert.deepEqual(listed.map((skill) => skill.id), [
      "openclaw-bundled/github",
      "general/github",
    ]);
    const shadowed = listed.find((skill) => skill.id === "general/github");
    assert.equal(shadowed?.sourceLabel, "Clawke skills (shadowed)");
    assert.equal(shadowed?.hasConflict, true);
    assert.equal(shadowed?.enabled, false);
    assert.equal(shadowed?.writable, false);
    assert.equal(shadowed?.deletable, true);
    assert.equal(shadowed?.path, "openclaw-github-assistant/SKILL.md");
    await assert.rejects(
      () => adapter.setEnabled("general/github", true),
      /shadowed/,
    );
  } finally {
    await rm(root, { recursive: true, force: true });
  }
});

test("OpenClawSkillAdapter edits and deletes file-backed non-bundled skills locally", async () => {
  const root = await mkdtemp(join(tmpdir(), "openclaw-rpc-skill-file-"));
  try {
    writeSkill(root, "editable-skill", "editable-skill", "Editable skill");
    const skillPath = join(root, "editable-skill", "SKILL.md");
    const adapter = new OpenClawSkillAdapter(undefined, {
      rpc: async (method) => {
        assert.equal(method, "skills.status");
        return {
          skills: [
            {
              skillKey: "editable-skill",
              name: "editable-skill",
              description: "Editable skill",
              source: "agents-skills-personal",
              bundled: false,
              filePath: skillPath,
              baseDir: join(root, "editable-skill"),
              disabled: false,
              always: false,
            },
          ],
        };
      },
    });

    const listed = await adapter.listSkills();

    assert.equal(listed[0].writable, true);
    assert.equal(listed[0].deletable, true);
    assert.equal(listed[0].body, "# editable-skill\n");
    assert.match(listed[0].content ?? "", /description: Editable skill/);

    const updated = await adapter.updateSkill("agents-skills-personal/editable-skill", {
      name: "edited-skill",
      category: "agents-skills-personal",
      description: "Edited description",
      body: "# Edited body\n",
    });

    assert.equal(updated.id, "agents-skills-personal/edited-skill");
    assert.equal(updated.description, "Edited description");
    assert.equal(updated.absolutePath, join(root, "edited-skill", "SKILL.md"));
    assert.equal(existsSync(join(root, "editable-skill", "SKILL.md")), false);
    assert.match(readFileSync(updated.absolutePath, "utf-8"), /Edited description/);
    assert.match(readFileSync(updated.absolutePath, "utf-8"), /Edited body/);

    assert.equal(await adapter.deleteSkill("agents-skills-personal/edited-skill"), true);
    assert.equal(existsSync(join(root, "edited-skill", "SKILL.md")), false);
  } finally {
    await rm(root, { recursive: true, force: true });
  }
});

test("OpenClawSkillAdapter creates Clawke local skills in the configured skills root", async () => {
  const root = await mkdtemp(join(tmpdir(), "openclaw-rpc-skill-create-"));
  try {
    const adapter = new OpenClawSkillAdapter(root, {
      rpc: async (method) => {
        assert.equal(method, "skills.status");
        return { skills: [] };
      },
    });

    const created = await adapter.createSkill({
      name: "abc",
      category: "general",
      description: "ABC helper",
      body: "# ABC\n",
    });

    const skillPath = join(root, "skills", "abc", "SKILL.md");
    assert.equal(created.id, "openclaw-extra/abc");
    assert.equal(created.absolutePath, skillPath);
    assert.equal(existsSync(skillPath), true);
    assert.match(readFileSync(skillPath, "utf-8"), /name: abc/);
    assert.match(readFileSync(skillPath, "utf-8"), /description: ABC helper/);
    assert.match(readFileSync(skillPath, "utf-8"), /# ABC/);

    const listed = await adapter.listSkills();
    assert.deepEqual(listed.map((skill) => skill.id), ["openclaw-extra/abc"]);
  } finally {
    await rm(root, { recursive: true, force: true });
  }
});

test("OpenClawSkillAdapter installs SkillHub package through OpenClaw upload RPC", async () => {
  const archive = Buffer.from("fake zip bytes");
  const digest = createHash("sha256").update(archive).digest("hex");
  const calls: Array<{ method: string; params?: any }> = [];
  const adapter = new OpenClawSkillAdapter(undefined, {
    rpc: async (method, params) => {
      calls.push({ method, params });
      if (method === "skills.upload.begin") {
        return { uploadId: "upload-1" };
      }
      if (method === "skills.upload.chunk") {
        return { ok: true };
      }
      if (method === "skills.upload.commit") {
        return { ok: true, sha256: digest };
      }
      if (method === "skills.install") {
        return { ok: true, slug: "github-helper", sha256: digest };
      }
      if (method === "skills.status") {
        return {
          skills: [{
            skillKey: "github-helper",
            name: "GitHub Helper",
            description: "GitHub helper",
            source: "openclaw-workspace",
            bundled: false,
            disabled: false,
          }],
        };
      }
      throw new Error(`Unexpected method: ${method}`);
    },
  });

  const installed = await adapter.installSkillHubPackage({
    id: "204",
    slug: "github-helper",
    name: "GitHub Helper",
    version: "1.2.1",
    packageUrl: `data:application/zip;base64,${archive.toString("base64")}`,
    packageSha256: digest,
    packageType: "bundle",
  });

  assert.equal(installed?.id, "openclaw-workspace/github-helper");
  assert.deepEqual(calls.map((call) => call.method), [
    "skills.upload.begin",
    "skills.upload.chunk",
    "skills.upload.commit",
    "skills.install",
    "skills.status",
  ]);
  assert.deepEqual(calls[0].params, {
    kind: "skill-archive",
    slug: "github-helper",
    sizeBytes: archive.length,
    sha256: digest,
  });
  assert.deepEqual(calls[1].params, {
    uploadId: "upload-1",
    offset: 0,
    dataBase64: archive.toString("base64"),
  });
  assert.deepEqual(calls[3].params, {
    source: "upload",
    uploadId: "upload-1",
    slug: "github-helper",
    sha256: digest,
  });
});

test("OpenClawSkillAdapter installs ClawHub-backed SkillHub package through native ClawHub RPC", async () => {
  const calls: Array<{ method: string; params?: any }> = [];
  const adapter = new OpenClawSkillAdapter(undefined, {
    rpc: async (method, params) => {
      calls.push({ method, params });
      if (method === "skills.install") {
        return { ok: true, slug: "github-helper", version: "1.2.1" };
      }
      if (method === "skills.status") {
        return {
          skills: [{
            skillKey: "github-helper",
            name: "GitHub Helper",
            description: "GitHub helper",
            source: "openclaw-workspace",
            bundled: false,
            disabled: false,
          }],
        };
      }
      throw new Error(`Unexpected method: ${method}`);
    },
  });

  const installed = await adapter.installSkillHubPackage({
    slug: "github-helper",
    source: "clawhub",
  });

  assert.equal(installed?.id, "openclaw-workspace/github-helper");
  assert.deepEqual(calls, [
    {
      method: "skills.install",
      params: {
        source: "clawhub",
        slug: "github-helper",
      },
    },
    { method: "skills.status", params: undefined },
  ]);
});

test("OpenClawSkillAdapter manages gateway-host Clawke skills", async () => {
  const root = await mkdtemp(join(tmpdir(), "openclaw-skill-adapter-"));
  try {
    const openClawConfigPath = join(root, "openclaw.json");
    const adapter = new LegacyLocalOpenClawSkillAdapter(root, { openClawConfigPath });

    const created = adapter.createSkill({
      name: "apple-notes",
      category: "apple",
      description: "Manage Apple Notes",
      trigger: "Use for notes",
      body: "# Apple Notes\n",
    });

    assert.equal(created.id, "apple/apple-notes");
    assert.equal(created.source, "managed");
    assert.equal(created.enabled, true);
    assert.equal(existsSync(join(root, "skills", "apple-notes", "SKILL.md")), true);

    const listed = adapter.listSkills();
    assert.deepEqual(listed.map((skill) => skill.id), ["apple/apple-notes"]);

    const disabled = adapter.setEnabled("apple/apple-notes", false);
    assert.equal(disabled.enabled, false);
    assert.equal(existsSync(join(root, "skills", "apple-notes", "SKILL.md")), true);
    assert.equal(existsSync(join(root, "disabled-skills", "apple-notes", "SKILL.md")), false);
    assert.equal(readConfig(openClawConfigPath).skills.entries["apple-notes"].enabled, false);
    assert.deepEqual(adapter.listRuntimeSkills(), []);

    const restored = adapter.setEnabled("apple/apple-notes", true);
    assert.equal(restored.enabled, true);
    assert.equal(existsSync(join(root, "skills", "apple-notes", "SKILL.md")), true);
    assert.equal(readConfig(openClawConfigPath).skills.entries["apple-notes"].enabled, true);
  } finally {
    await rm(root, { recursive: true, force: true });
  }
});

test("LegacyLocalOpenClawSkillAdapter skips invalid skill names while listing", async () => {
  const root = await mkdtemp(join(tmpdir(), "openclaw-skill-adapter-invalid-"));
  try {
    writeSkill(join(root, "skills"), "weather", "weather", "Weather lookup");
    writeSkill(join(root, "skills"), "word-docx", "Word / DOCX", "Word documents");
    const adapter = new LegacyLocalOpenClawSkillAdapter(root, {
      openClawConfigPath: join(root, "openclaw.json"),
    });

    const listed = adapter.listSkills();

    assert.deepEqual(listed.map((skill) => skill.id), ["general/weather"]);
  } finally {
    await rm(root, { recursive: true, force: true });
  }
});

test("OpenClawSkillAdapter marks external skills editable and supports edit/delete", async () => {
  const root = await mkdtemp(join(tmpdir(), "openclaw-skill-adapter-"));
  const externalRoot = await mkdtemp(join(tmpdir(), "openclaw-external-skills-"));
  try {
    writeSkill(externalRoot, "external-edit", "external-edit", "External skill");
    writeSkill(externalRoot, "external-delete", "external-delete", "External delete");
    const adapter = new LegacyLocalOpenClawSkillAdapter(root, {
      externalRoots: [externalRoot],
      openClawConfigPath: join(root, "openclaw.json"),
    });

    const listed = adapter.listSkills();
    const editable = listed.find((skill) => skill.id === "general/external-edit");
    const deletable = listed.find((skill) => skill.id === "general/external-delete");
    assert.equal(editable?.writable, true);
    assert.equal(editable?.deletable, true);
    assert.equal(deletable?.writable, true);
    assert.equal(deletable?.deletable, true);

    const updated = adapter.updateSkill("general/external-edit", {
      name: "external-edit-renamed",
      category: "general",
      description: "Edited external skill",
      body: "# Edited\n",
    });
    assert.equal(updated.id, "general/external-edit-renamed");
    assert.equal(updated.source, "external");
    assert.equal(updated.description, "Edited external skill");
    assert.equal(updated.absolutePath, join(externalRoot, "external-edit-renamed", "SKILL.md"));
    assert.equal(existsSync(join(root, "skills", "external-edit-renamed", "SKILL.md")), false);
    assert.match(readFileSync(updated.absolutePath, "utf-8"), /Edited external skill/);

    assert.equal(adapter.deleteSkill("general/external-delete"), true);
    assert.equal(existsSync(join(externalRoot, "external-delete", "SKILL.md")), false);
  } finally {
    await rm(root, { recursive: true, force: true });
    await rm(externalRoot, { recursive: true, force: true });
  }
});

test("OpenClawSkillAdapter disables external skills through OpenClaw config", async () => {
  const root = await mkdtemp(join(tmpdir(), "openclaw-skill-adapter-"));
  const externalRoot = await mkdtemp(join(tmpdir(), "openclaw-external-skills-"));
  try {
    const openClawConfigPath = join(root, "openclaw.json");
    writeSkill(externalRoot, "external-toggle", "external-toggle", "External toggle");
    const adapter = new LegacyLocalOpenClawSkillAdapter(root, { externalRoots: [externalRoot], openClawConfigPath });

    const disabled = adapter.setEnabled("general/external-toggle", false);

    assert.equal(disabled.enabled, false);
    assert.equal(disabled.source, "external");
    assert.equal(existsSync(join(externalRoot, "external-toggle", "SKILL.md")), true);
    assert.equal(existsSync(join(root, "disabled-skills", "external-toggle", "SKILL.md")), false);
    assert.equal(readConfig(openClawConfigPath).skills.entries["external-toggle"].enabled, false);
    assert.deepEqual(adapter.listRuntimeSkills(), []);

    const updatedWhileDisabled = adapter.updateSkill("general/external-toggle", {
      name: "external-toggle-renamed",
      category: "general",
      description: "External toggle renamed",
      body: "# Renamed\n",
    });
    assert.equal(updatedWhileDisabled.enabled, false);
    assert.equal(existsSync(join(externalRoot, "external-toggle-renamed", "SKILL.md")), true);
    assert.equal(existsSync(join(root, "disabled-skills", "external-toggle-renamed", "SKILL.md")), false);
    assert.equal(readConfig(openClawConfigPath).skills.entries["external-toggle-renamed"].enabled, false);
    assert.deepEqual(adapter.listRuntimeSkills(), []);

    const restored = adapter.setEnabled("general/external-toggle-renamed", true);

    assert.equal(restored.enabled, true);
    assert.equal(existsSync(join(externalRoot, "external-toggle-renamed", "SKILL.md")), true);
    assert.equal(existsSync(join(root, "disabled-skills", "external-toggle-renamed", "SKILL.md")), false);
    assert.equal(readConfig(openClawConfigPath).skills.entries["external-toggle-renamed"].enabled, true);
    assert.deepEqual(adapter.listRuntimeSkills(), [
      { name: "external-toggle-renamed", description: "External toggle renamed" },
    ]);
  } finally {
    await rm(root, { recursive: true, force: true });
    await rm(externalRoot, { recursive: true, force: true });
  }
});

test("OpenClawSkillAdapter migrates old state-only external disables into OpenClaw config", async () => {
  const root = await mkdtemp(join(tmpdir(), "openclaw-skill-adapter-"));
  const externalRoot = await mkdtemp(join(tmpdir(), "openclaw-external-skills-"));
  try {
    const openClawConfigPath = join(root, "openclaw.json");
    writeSkill(externalRoot, "external-toggle", "external-toggle", "External toggle");
    writeFileSync(
      join(root, "skills-state.json"),
      JSON.stringify({
        version: 1,
        skills: {
          "general/external-toggle": {
            skillId: "general/external-toggle",
            source: "external",
            category: "general",
            name: "external-toggle",
            enabled: false,
            disableMethod: "state",
            path: join(externalRoot, "external-toggle"),
            originalPath: join(externalRoot, "external-toggle"),
          },
        },
      }),
      "utf-8",
    );
    const adapter = new LegacyLocalOpenClawSkillAdapter(root, { externalRoots: [externalRoot], openClawConfigPath });

    const disabled = adapter.setEnabled("general/external-toggle", false);

    assert.equal(disabled.enabled, false);
    assert.equal(existsSync(join(externalRoot, "external-toggle", "SKILL.md")), true);
    assert.equal(existsSync(join(root, "disabled-skills", "external-toggle", "SKILL.md")), false);
    assert.equal(readConfig(openClawConfigPath).skills.entries["external-toggle"].enabled, false);
  } finally {
    await rm(root, { recursive: true, force: true });
    await rm(externalRoot, { recursive: true, force: true });
  }
});

test("OpenClawSkillAdapter restores legacy moved external skills before enabling config", async () => {
  const root = await mkdtemp(join(tmpdir(), "openclaw-skill-adapter-"));
  const externalRoot = await mkdtemp(join(tmpdir(), "openclaw-external-skills-"));
  try {
    const openClawConfigPath = join(root, "openclaw.json");
    writeSkill(join(root, "disabled-skills"), "external-toggle", "external-toggle", "External toggle");
    writeFileSync(
      join(root, "skills-state.json"),
      JSON.stringify({
        version: 1,
        skills: {
          "general/external-toggle": {
            skillId: "general/external-toggle",
            source: "external",
            category: "general",
            name: "external-toggle",
            enabled: false,
            disableMethod: "move",
            path: join(root, "disabled-skills", "external-toggle"),
            originalPath: join(externalRoot, "external-toggle"),
            disabledPath: join(root, "disabled-skills", "external-toggle"),
          },
        },
      }),
      "utf-8",
    );
    const adapter = new LegacyLocalOpenClawSkillAdapter(root, { externalRoots: [externalRoot], openClawConfigPath });

    const restored = adapter.setEnabled("general/external-toggle", true);

    assert.equal(restored.enabled, true);
    assert.equal(existsSync(join(externalRoot, "external-toggle", "SKILL.md")), true);
    assert.equal(existsSync(join(root, "disabled-skills", "external-toggle", "SKILL.md")), false);
    assert.equal(readConfig(openClawConfigPath).skills.entries["external-toggle"].enabled, true);
  } finally {
    await rm(root, { recursive: true, force: true });
    await rm(externalRoot, { recursive: true, force: true });
  }
});

function writeSkill(root: string, dir: string, name: string, description: string): void {
  const skillDir = join(root, dir);
  mkdirSync(skillDir, { recursive: true });
  writeFileSync(
    join(skillDir, "SKILL.md"),
    `---\nname: ${name}\ndescription: ${description}\n---\n\n# ${name}\n`,
    "utf-8",
  );
}

function readConfig(configPath: string): any {
  return JSON.parse(readFileSync(configPath, "utf-8"));
}
