from __future__ import annotations

from pathlib import Path
from types import SimpleNamespace
import os
import tempfile
import unittest
from unittest.mock import patch

from skill_adapter import HermesSkillAdapter


class NativeSkillHubInstallTest(unittest.TestCase):
    def test_native_installer_uses_valid_python_code_string(self):
        adapter = HermesSkillAdapter(clawke_home=Path("/tmp/clawke"))

        with patch("skill_adapter.subprocess.run") as run:
            run.return_value = SimpleNamespace(returncode=0, stdout="", stderr="")

            adapter._run_native_skillhub_install(
                "clawhub/weather",
                Path("/tmp/hermes"),
                True,
            )

        command = run.call_args.args[0]
        code = command[2]
        self.assertIn("import sys\nfrom hermes_cli.skills_hub", code)
        self.assertNotIn("\\n", code)

    def test_hermes_native_skills_are_deletable_for_cleanup(self):
        with tempfile.TemporaryDirectory() as tmp:
            root = Path(tmp)
            hermes_home = root / "hermes"
            skill_dir = hermes_home / "skills" / "weather"
            skill_dir.mkdir(parents=True)
            (skill_dir / "SKILL.md").write_text(
                "---\nname: weather\ndescription: Weather\n---\n",
                encoding="utf-8",
            )

            with patch.dict(os.environ, {"HERMES_HOME": str(hermes_home)}):
                adapter = HermesSkillAdapter(
                    clawke_home=root / "clawke",
                    external_roots=[hermes_home / "skills"],
                )

                skill = adapter.get_skill("general/weather")
                self.assertTrue(skill["deletable"])
                self.assertTrue(adapter.delete_skill("general/weather"))
                self.assertFalse(skill_dir.exists())


if __name__ == "__main__":
    unittest.main()
