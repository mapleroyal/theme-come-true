"""Exercise the IPC boundary without connecting to a live desktop."""

import json
import os
from pathlib import Path
import shutil
import subprocess
import tempfile
import time
import unittest


BRIDGE = Path(__file__).resolve().parents[1] / "ipc-bridge/omarchy-shell"


class IpcBridgeTests(unittest.TestCase):
    def setUp(self):
        self.temporary = tempfile.TemporaryDirectory(
            prefix="appearance-bridge-", dir=os.environ.get("APPEARANCE_TEST_TMPDIR")
        )
        self.addCleanup(self.temporary.cleanup)
        self.root = Path(self.temporary.name)
        self.home = self.root / "home"
        self.state = self.home / ".local/state/omarchy/current"
        self.state.mkdir(parents=True)
        (self.state / "theme.name").write_text("test-theme\n")
        self.old = self.root / "old.png"
        self.old.write_bytes(b"old")
        self.target = self.root / "new 雪 wallpaper.png"
        self.target.write_bytes(b"new")
        (self.state / "background").symlink_to(self.old)
        self.omarchy = self.root / "omarchy"
        (self.omarchy / "bin").mkdir(parents=True)
        self.native = self.omarchy / "bin/omarchy-shell"
        self.native.write_text(
            "#!/usr/bin/env python3\n"
            "import json, os, sys, time\n"
            "with open(os.environ['BRIDGE_TEST_LOG'], 'a') as output:\n"
            "    output.write(json.dumps(sys.argv[1:]) + '\\n')\n"
            "if sys.argv[1:3] == ['appearance', 'prepareVisual'] and os.environ.get('SLOW_VISUAL_PREPARE'):\n"
            "    time.sleep(5)\n"
            "if sys.argv[1:3] == ['background', 'themeTransition'] and os.environ.get('FAIL_TRANSITION'):\n"
            "    print('native transition unavailable', file=sys.stderr)\n"
            "    raise SystemExit(1)\n"
        )
        self.native.chmod(0o755)
        self.plugin = self.root / "plugin"
        (self.plugin / "ipc-bridge").mkdir(parents=True)
        self.bridge = self.plugin / "ipc-bridge/omarchy-shell"
        shutil.copy2(BRIDGE, self.bridge)
        (self.plugin / "appearance-helper").write_text(
            "#!/usr/bin/env python3\n"
            "import json, os, pathlib, subprocess, sys, time\n"
            "assert sys.argv[1:3] == ['status', '--background-override']\n"
            "assert os.environ.get('OMARCHY_APPEARANCE_PREPARE') == '1'\n"
            "if os.environ.get('SLOW_INVENTORY'):\n"
            "    child = subprocess.Popen([sys.executable, '-c', 'import time; time.sleep(30)'])\n"
            "    pathlib.Path(os.environ['PREPARE_CHILD_PID']).write_text(str(child.pid))\n"
            "    time.sleep(5)\n"
            "print(json.dumps({'version': 1, 'current': {'theme': 'test-theme', "
            "'background': sys.argv[3]}, 'themes': [], 'palette': []}))\n"
        )
        (self.plugin / "appearance-helper").chmod(0o755)
        self.log = self.root / "calls.jsonl"
        self.context_dir = self.root / "context"
        self.context_dir.mkdir(mode=0o700)
        self.context_file = self.context_dir / "context.json"
        self.context = {
            "version": 1,
            "theme": "test-theme",
            "background": str(self.target),
            "previousBackground": str(self.old),
            "nativeShell": str(self.native),
            "requestId": "42",
        }
        self.write_context()
        self.env = {
            **os.environ,
            "HOME": str(self.home),
            "OMARCHY_PATH": str(self.omarchy),
            "BRIDGE_TEST_LOG": str(self.log),
            "OMARCHY_APPEARANCE_CONTEXT": str(self.context_file),
        }
        self.palette_call = ["shell", "applyTheme", "Y29sb3Jz", "c2hlbGw="]

    def write_context(self):
        self.context_file.write_text(json.dumps(self.context))
        self.context_file.chmod(0o600)

    def run_bridge(self, arguments, *, failure=False, expected_code=0, native_deadline=False):
        self.log.write_text("")
        environment = {**self.env, "FAIL_TRANSITION": "1" if failure else ""}
        command = [str(self.bridge), *arguments]
        if native_deadline:
            command = ["timeout", "2", *command]
        result = subprocess.run(
            command, env=environment,
            capture_output=True, text=True, timeout=5,
        )
        self.assertEqual(result.returncode, expected_code, result.stderr)
        return [json.loads(line) for line in self.log.read_text().splitlines()]

    def event(self):
        return json.loads((self.context_dir / "applied.json").read_text())

    def test_unmatched_call_preserves_arguments(self):
        arguments = ["background", "set", "literal $() quoted space"]
        self.assertEqual(self.run_bridge(arguments), [arguments])
        self.assertFalse((self.context_dir / "applied.json").exists())

    def test_remembered_wallpaper_prepares_visual_before_native_reveal(self):
        calls = self.run_bridge(self.palette_call)
        self.assertEqual([call[:2] for call in calls], [
            ["appearance", "prepareVisual"], ["background", "themeTransition"],
        ])
        self.assertEqual(calls[1][2:], [
            str(self.old), str(self.target), str(self.target), *self.palette_call[2:],
        ])
        self.assertEqual(json.loads(calls[0][3]), self.event()["status"])
        self.assertEqual(self.event()["status"]["current"]["background"], str(self.target))
        self.assertTrue(self.event()["ok"])
        self.assertEqual((self.state / "background").resolve(), self.target)
        self.assertFalse(list(self.plugin.rglob("__pycache__")))

    def test_native_default_keeps_os_snapshot_and_link_ownership(self):
        self.context["background"] = ""
        self.write_context()
        arguments = [
            "background", "themeTransition", str(self.old), "native snapshot.png",
            str(self.target), *self.palette_call[2:],
        ]
        calls = self.run_bridge(arguments)
        self.assertEqual(calls[-1], arguments)
        self.assertEqual(calls[0][:2], ["appearance", "prepareVisual"])
        self.assertTrue(self.event()["ok"])
        self.assertEqual((self.state / "background").resolve(), self.old)

    def test_operation_intercepts_only_once(self):
        self.run_bridge(self.palette_call)
        self.assertEqual(self.run_bridge(self.palette_call), [self.palette_call])

    def test_failed_remembered_reveal_preserves_link_and_falls_back(self):
        calls = self.run_bridge(self.palette_call, failure=True)
        self.assertEqual(calls[-1], self.palette_call)
        self.assertFalse(self.event()["ok"])
        self.assertIn("native transition unavailable", self.event()["error"])
        self.assertEqual((self.state / "background").resolve(), self.old)

    def test_failed_native_default_defers_fallback_to_os(self):
        arguments = [
            "background", "themeTransition", str(self.old), str(self.target),
            str(self.target), *self.palette_call[2:],
        ]
        calls = self.run_bridge(arguments, failure=True, expected_code=1)
        self.assertEqual([call[:2] for call in calls], [
            ["appearance", "prepareVisual"], ["background", "themeTransition"],
        ])
        self.assertFalse(self.event()["ok"])

    def test_missing_image_reports_error_before_native_palette_fallback(self):
        self.target.unlink()
        self.assertEqual(self.run_bridge(self.palette_call), [self.palette_call])
        self.assertFalse(self.event()["ok"])

    def test_non_private_context_does_not_intercept(self):
        self.context_file.chmod(0o644)
        self.assertEqual(self.run_bridge(self.palette_call), [self.palette_call])
        self.assertFalse((self.context_dir / "applied.json").exists())

    def test_stale_theme_does_not_commit_requested_wallpaper(self):
        (self.state / "theme.name").write_text("another-theme\n")
        self.assertEqual(self.run_bridge(self.palette_call), [self.palette_call])
        self.assertIn("staged theme changed", self.event()["error"])
        self.assertEqual((self.state / "background").resolve(), self.old)

    def test_slow_inventory_cannot_use_up_native_transition_deadline(self):
        pid_file = self.root / "preparation-child.pid"
        self.env.update({"SLOW_INVENTORY": "1", "PREPARE_CHILD_PID": str(pid_file)})
        started = time.monotonic()
        calls = self.run_bridge(self.palette_call, native_deadline=True)
        self.assertLess(time.monotonic() - started, 1.5)
        self.assertEqual([call[:2] for call in calls], [["background", "themeTransition"]])
        self.assertTrue(self.event()["ok"])
        self.assertFalse(self.event()["visualPrepared"])
        self.assertEqual((self.state / "background").resolve(), self.target)
        child_status = Path(f"/proc/{pid_file.read_text().strip()}/stat")
        # An adopted child can briefly remain a zombie, but cannot keep running.
        if child_status.exists():
            self.assertEqual(child_status.read_text().split()[2], "Z")

    def test_slow_preview_ipc_is_optional_within_native_deadline(self):
        self.env["SLOW_VISUAL_PREPARE"] = "1"
        started = time.monotonic()
        calls = self.run_bridge(self.palette_call, native_deadline=True)
        self.assertLess(time.monotonic() - started, 1.5)
        self.assertEqual([call[:2] for call in calls], [
            ["appearance", "prepareVisual"], ["background", "themeTransition"],
        ])
        self.assertTrue(self.event()["ok"])
        self.assertFalse(self.event()["visualPrepared"])
        self.assertEqual((self.state / "background").resolve(), self.target)

    def test_slow_default_preparation_still_forwards_native_snapshot_paths(self):
        self.context["background"] = ""
        self.write_context()
        pid_file = self.root / "preparation-child.pid"
        self.env.update({"SLOW_INVENTORY": "1", "PREPARE_CHILD_PID": str(pid_file)})
        arguments = ["background", "themeTransition", str(self.old), "native snapshot.png",
                     str(self.target), *self.palette_call[2:]]
        self.assertEqual(self.run_bridge(arguments, native_deadline=True), [arguments])
        self.assertTrue(self.event()["ok"])
        self.assertEqual((self.state / "background").resolve(), self.old)


if __name__ == "__main__":
    unittest.main()
