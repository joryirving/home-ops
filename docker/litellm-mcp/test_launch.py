from __future__ import annotations

import contextlib
import errno
import io
import os
import tempfile
import unittest
from pathlib import Path
from unittest import mock

import launch


class LauncherTests(unittest.TestCase):
    def setUp(self) -> None:
        self.tempdir = tempfile.TemporaryDirectory()
        self.secret_root = Path(self.tempdir.name)

    def tearDown(self) -> None:
        self.tempdir.cleanup()

    def write_secrets(self, server_name: str) -> None:
        for key in launch.SERVERS[server_name].secrets:
            path = self.secret_root / server_name / key
            path.parent.mkdir(parents=True, exist_ok=True)
            path.write_text(f"secret-for-{key}\n", encoding="utf-8")

    def test_only_fixed_allowlist_and_selected_secret_are_passed(self) -> None:
        self.write_secrets("github")
        with mock.patch.dict(
            os.environ,
            {
                "LITELLM_MASTER_KEY": "proxy-admin-secret",
                "OPENAI_API_KEY": "provider-secret",
                "GITHUB_PERSONAL_ACCESS_TOKEN": "wrong-inherited-token",
                "KUBERNETES_SERVICE_HOST": "cluster-api",
                "TALOSCONFIG": "talos-secret",
            },
        ):
            env = launch.build_environment("github", self.secret_root)

        self.assertEqual(env["GITHUB_PERSONAL_ACCESS_TOKEN"], "secret-for-token")
        self.assertEqual(env["GITHUB_API_URL"], "https://api.github.com")
        for name in (
            "LITELLM_MASTER_KEY",
            "OPENAI_API_KEY",
            "KUBERNETES_SERVICE_HOST",
            "TALOSCONFIG",
        ):
            self.assertNotIn(name, env)
        self.assertEqual(set(env), set(launch.SERVERS["github"].env) | {"GITHUB_PERSONAL_ACCESS_TOKEN"})

    def test_each_server_receives_only_its_mapped_secret_keys(self) -> None:
        expected = {
            "arr": {"SONARR_API_KEY", "RADARR_API_KEY", "PROWLARR_API_KEY"},
            "seerr": {"SEERR_API_KEY"},
            "github": {"GITHUB_PERSONAL_ACCESS_TOKEN"},
            "dispatch": {"DISPATCH_AGENT_TOKEN"},
        }
        for server_name, child_keys in expected.items():
            with self.subTest(server=server_name):
                self.write_secrets(server_name)
                env = launch.build_environment(server_name, self.secret_root)
                actual = set(env) - set(launch.SERVERS[server_name].env)
                self.assertEqual(actual, child_keys)

    def test_missing_secret_fails_without_disclosing_content(self) -> None:
        with self.assertRaisesRegex(launch.LaunchError, "cannot read required secret file") as caught:
            launch.build_environment("dispatch", self.secret_root)
        self.assertNotIn("token-value", str(caught.exception))

    def test_empty_secret_is_rejected(self) -> None:
        path = self.secret_root / "seerr" / "SEERR_API_KEY"
        path.parent.mkdir(parents=True)
        path.write_text("\n", encoding="utf-8")
        with self.assertRaisesRegex(launch.LaunchError, "empty or invalid"):
            launch.build_environment("seerr", self.secret_root)

    def test_server_name_is_allowlisted(self) -> None:
        with self.assertRaisesRegex(launch.LaunchError, "unknown MCP server"):
            launch.build_environment("kubectl", self.secret_root)

    def test_main_execs_known_binary_and_preserves_child_arguments(self) -> None:
        self.write_secrets("seerr")
        with mock.patch.object(launch, "SECRET_ROOT", self.secret_root), mock.patch.object(
            launch.os, "execvpe", side_effect=OSError("not found")
        ) as execvpe:
            self.assertEqual(launch.main(["seerr"]), 127)

        command, argv, env = execvpe.call_args.args
        self.assertEqual(command, launch.NODE)
        self.assertEqual(argv, [launch.NODE, *launch.SERVERS["seerr"].args])
        self.assertNotIn("OPENAI_API_KEY", env)
        self.assertEqual(env["SEERR_API_KEY"], "secret-for-SEERR_API_KEY")

    def test_exec_failure_is_reported_without_python_traceback(self) -> None:
        self.write_secrets("github")
        stderr = io.StringIO()
        with (
            mock.patch.object(launch, "SECRET_ROOT", self.secret_root),
            mock.patch.object(launch.os, "execvpe", side_effect=FileNotFoundError(errno.ENOENT, "missing executable")),
            contextlib.redirect_stderr(stderr),
        ):
            self.assertEqual(launch.main(["github"]), 127)
        self.assertIn("cannot execute github MCP server", stderr.getvalue())
        self.assertNotIn("Traceback", stderr.getvalue())

    def test_invalid_cli_does_not_execute(self) -> None:
        with mock.patch.object(launch.os, "execvpe") as execvpe:
            self.assertEqual(launch.main([]), 2)
            self.assertEqual(launch.main(["github", "--help"]), 2)
        execvpe.assert_not_called()


if __name__ == "__main__":
    unittest.main()
