"""Fixture tests for the plugin's native-command and filesystem boundary."""

from __future__ import annotations

import contextlib
import importlib.machinery
import importlib.util
import io
import json
import os
from pathlib import Path
import signal
import subprocess
import sys
import tempfile
import time
import unittest
from unittest.mock import patch

sys.dont_write_bytecode = True
HELPER_PATH = Path(__file__).resolve().parents[1] / "appearance-helper"


def load_helper():
    loader = importlib.machinery.SourceFileLoader("appearance_helper_tests", str(HELPER_PATH))
    spec = importlib.util.spec_from_loader(loader.name, loader)
    module = importlib.util.module_from_spec(spec)
    loader.exec_module(module)
    return module


class HelperTests(unittest.TestCase):
    def setUp(self):
        self.temporary = tempfile.TemporaryDirectory(prefix="appearance-test-")
        self.addCleanup(self.temporary.cleanup)
        self.root = Path(self.temporary.name)
        self.helper = load_helper()
        self.helper.HOME = self.root
        self.helper.OMARCHY_PATH = self.root / "omarchy"
        self.helper.STOCK_THEMES = self.root / "omarchy/themes"
        self.helper.USER_THEMES = self.root / "themes"
        self.helper.USER_BACKGROUNDS = self.root / "backgrounds"
        self.helper.CURRENT_STATE = self.root / "current"
        self.helper.BACKGROUND_PIN_CACHE = self.root / "pins"
        self.helper.BACKGROUND_PICKER_CACHE = self.root / "picker"
        for directory in (self.helper.STOCK_THEMES, self.helper.USER_THEMES,
                          self.helper.USER_BACKGROUNDS, self.helper.CURRENT_STATE):
            directory.mkdir(parents=True)

    def write(self, path, contents="image"):
        path.parent.mkdir(parents=True, exist_ok=True)
        path.write_text(contents, encoding="utf-8")
        return path

    def theme(self, slug, mode="dark", user=False):
        root = self.helper.USER_THEMES if user else self.helper.STOCK_THEMES
        directory = root / slug
        self.write(directory / "colors.toml", f'mode = "{mode}"\nbackground = "#101010"\n')
        self.write(directory / "backgrounds/wallpaper.png")
        return directory

    def activate(self, slug, background):
        self.write(self.helper.CURRENT_STATE / "theme.name", slug)
        self.helper.replace_background_link(background)

    def legacy(self, slug="legacy-light"):
        path = self.helper.USER_THEMES / slug / "alacritty.toml"
        return self.write(path, '''[colors.primary]
background = "#ffffff"
foreground = "#111111"
[colors.normal]
black = "#111111"
red = "#aa0000"
green = "#00aa00"
yellow = "#aaaa00"
blue = "#0000aa"
magenta = "#aa00aa"
cyan = "#00aaaa"
white = "#eeeeee"
''')

    def invoke_main(self, *arguments):
        stdout = io.StringIO()
        stderr = io.StringIO()
        with patch.object(sys, "argv", [str(HELPER_PATH), *arguments]), \
             contextlib.redirect_stdout(stdout), contextlib.redirect_stderr(stderr):
            exit_code = self.helper.main()
        payloads = [json.loads(line) for line in stdout.getvalue().splitlines()]
        return exit_code, payloads, stderr.getvalue()

    def test_legacy_light_palette_remains_selectable(self):
        self.legacy()
        self.assertEqual(self.helper.theme_mode("legacy-light"), ("light", True))
        status = self.helper.build_status()
        self.assertEqual(status["themes"][0]["mode"], "light")
        self.assertTrue(status["themes"][0]["validPalette"])
        self.assertFalse((self.helper.USER_THEMES / "legacy-light/colors.toml").exists())

    def test_incomplete_legacy_palette_is_not_accepted(self):
        self.write(self.helper.USER_THEMES / "broken/alacritty.toml", '[colors.normal]\nblack = "#101010"\n')
        self.assertEqual(self.helper.theme_mode("broken"), ("dark", False))

    def test_colors_overlay_takes_precedence_over_legacy_palette(self):
        self.theme("legacy-light", "dark")
        self.legacy()
        self.assertEqual(self.helper.theme_mode("legacy-light"), ("dark", True))

    def test_symlinked_git_working_copy_keeps_wallpaper_symlinks(self):
        checkout = self.root / "checkout"
        (checkout / ".git").mkdir(parents=True)
        image = self.write(self.root / "image.png")
        (checkout / "backgrounds").mkdir()
        (checkout / "backgrounds/wallpaper.png").symlink_to(image)
        (self.helper.USER_THEMES / "linked").symlink_to(checkout, target_is_directory=True)
        self.assertEqual([entry["path"] for entry in self.helper.effective_theme_wallpapers("linked")], [str(image)])

    def test_installed_git_theme_rejects_symlinked_wallpaper_directory(self):
        theme = self.helper.USER_THEMES / "installed"
        (theme / ".git").mkdir(parents=True)
        images = self.root / "images"
        self.write(images / "image.png")
        (theme / "backgrounds").symlink_to(images, target_is_directory=True)
        self.assertEqual(self.helper.effective_theme_wallpapers("installed"), [])

    def test_installed_git_palette_symlink_does_not_override_stock(self):
        self.theme("same", "dark")
        user = self.helper.USER_THEMES / "same"
        (user / ".git").mkdir(parents=True)
        palette = self.write(self.root / "light.toml", 'mode = "light"\n')
        (user / "colors.toml").symlink_to(palette)
        self.assertEqual(self.helper.theme_mode("same"), ("dark", True))

    def test_status_enumerates_each_theme_once(self):
        self.theme("first", "light")
        self.theme("second", "dark")
        self.activate("second", self.helper.STOCK_THEMES / "second/backgrounds/wallpaper.png")
        with patch.object(self.helper, "theme_slugs", wraps=self.helper.theme_slugs) as slugs, \
             patch.object(self.helper, "read_palette", wraps=self.helper.read_palette) as palettes, \
             patch.object(self.helper, "effective_theme_wallpapers", wraps=self.helper.effective_theme_wallpapers) as backgrounds:
            self.helper.build_status()
        self.assertEqual(slugs.call_count, 1)
        self.assertEqual(palettes.call_count, 2)
        self.assertEqual(backgrounds.call_count, 2)

    def test_staged_mode_drives_current_and_mode_pool(self):
        theme = self.theme("edited", "dark")
        self.activate("edited", theme / "backgrounds/wallpaper.png")
        self.write(self.helper.CURRENT_STATE / "theme/colors.toml", 'mode = "light"\n')
        self.write(self.helper.OMARCHY_PATH / "bin/omarchy-theme-color")
        resolved = subprocess.CompletedProcess([], 0, "mode\tlight\naccent\t#ffffff\n", "")
        with patch.object(self.helper, "run_bounded", return_value=resolved):
            status = self.helper.build_status()
        self.assertEqual(status["current"]["mode"], "light")
        self.assertTrue(status["current"]["inModePool"])
        self.assertEqual(status["themes"][0]["mode"], "light")

    def test_preparation_resolver_stays_in_the_bridge_owned_group(self):
        self.write(self.helper.CURRENT_STATE / "theme/colors.toml", 'mode = "dark"\n')
        resolver = self.write(self.helper.OMARCHY_PATH / "bin/omarchy-theme-color",
                              '#!/usr/bin/env python3\nimport os\nprint("mode\\tdark")\nprint(f"group\\t{os.getpgrp()}")\n')
        resolver.chmod(0o700)
        results = []
        original = self.helper.run_bounded

        def capture(*args, **kwargs):
            result = original(*args, **kwargs)
            results.append(result)
            return result

        with patch.dict(os.environ, {"OMARCHY_APPEARANCE_PREPARE": "1"}), \
             patch.object(self.helper, "run_bounded", side_effect=capture):
            self.helper.active_theme_appearance()
        self.assertIn(f"group\t{os.getpgrp()}\n", results[0].stdout)

    def test_visual_override_is_durable_and_does_not_change_active_link(self):
        theme = self.theme("sample")
        source = theme / "backgrounds/wallpaper.png"
        shortcut = self.helper.USER_BACKGROUNDS / "sample/shortcut.png"
        shortcut.parent.mkdir()
        shortcut.symlink_to(source)
        staged = self.write(self.helper.CURRENT_STATE / "theme/backgrounds/wallpaper.png")
        old = self.write(self.root / "old.png")
        self.activate("sample", old)
        status = self.helper.build_status(background_override=staged)
        self.assertEqual(status["current"]["background"], str(source))
        self.assertTrue(status["current"]["inThemePool"])
        self.assertEqual(self.helper.actual_current_background(), old)

    def test_status_cli_background_override_is_read_only_and_uses_durable_path(self):
        theme = self.theme("sample")
        staged = self.write(self.helper.CURRENT_STATE / "theme/backgrounds/wallpaper.png")
        old = self.write(self.root / "old.png")
        self.activate("sample", old)
        code, payloads, errors = self.invoke_main("status", "--background-override", str(staged))
        self.assertEqual(code, 0, errors)
        self.assertEqual(len(payloads), 1)
        self.assertEqual(payloads[0]["current"]["background"], str(theme / "backgrounds/wallpaper.png"))
        self.assertTrue(payloads[0]["current"]["inThemePool"])
        self.assertEqual(self.helper.actual_current_background(), old)
        self.assertNotIn("ok", payloads[0], "status retains its non-mutation protocol")

    def test_status_cli_rejects_an_unavailable_override_without_changing_state(self):
        old = self.write(self.root / "old.png")
        self.activate("sample", old)
        code, payloads, errors = self.invoke_main("status", "--background-override", str(self.root / "missing.png"))
        self.assertEqual(code, 2)
        self.assertEqual(payloads, [])
        self.assertIn("readable", errors)
        self.assertEqual(self.helper.actual_current_background(), old)

    def test_failed_native_command_is_reconciled_when_background_changed(self):
        target = self.write(self.root / "chosen.png")

        def applied_then_failed(arguments, **_kwargs):
            self.helper.replace_background_link(Path(arguments[-1]))
            raise self.helper.AppearanceError("renderer unavailable")

        with patch.object(self.helper, "run_omarchy", side_effect=applied_then_failed):
            warning = self.helper.apply_background(target)
        self.assertEqual(warning, "renderer unavailable")
        self.assertEqual(self.helper.actual_current_background(), target)

    def test_success_exit_without_background_change_is_an_error(self):
        target = self.write(self.root / "chosen.png")
        old = self.write(self.root / "old.png")
        self.helper.replace_background_link(old)
        with patch.object(self.helper, "run_omarchy"):
            with self.assertRaisesRegex(self.helper.AppearanceError, "did not activate"):
                self.helper.apply_background(target)

    def test_cycle_uses_the_same_authoritative_verification(self):
        theme = self.theme("sample")
        old = self.write(self.root / "old.png")
        self.activate("sample", old)
        with patch.object(self.helper, "run_omarchy"):
            with self.assertRaisesRegex(self.helper.AppearanceError, "did not activate"):
                self.helper.cycle_wallpaper("theme", "next", False)
        self.assertEqual(self.helper.actual_current_background(), old)

    def test_mutation_cli_returns_final_state_and_request_id(self):
        theme = self.theme("sample")
        target = theme / "backgrounds/wallpaper.png"
        self.activate("sample", self.write(self.root / "old.png"))
        with patch.object(self.helper, "run_omarchy", side_effect=lambda arguments, **kwargs: self.helper.replace_background_link(Path(arguments[-1]))):
            code, payloads, errors = self.invoke_main("set-wallpaper", str(target), "--request-id", "42")
        self.assertEqual(code, 0, errors)
        self.assertTrue(payloads[-1]["ok"])
        self.assertEqual(payloads[-1]["requestId"], "42")
        self.assertEqual(payloads[-1]["status"]["current"]["background"], str(target))

    def test_mutation_cli_failure_still_reports_authoritative_state(self):
        self.theme("sample")
        old = self.write(self.root / "old.png")
        self.activate("sample", old)
        code, payloads, errors = self.invoke_main("set-wallpaper", str(self.root / "missing.png"))
        self.assertEqual(code, 2)
        self.assertFalse(payloads[-1]["ok"])
        self.assertEqual(payloads[-1]["status"]["current"]["background"], str(old))
        self.assertIn("readable", errors)

    def test_default_theme_switch_keeps_native_background_handling(self):
        theme = self.theme("next")
        captured = []

        def set_theme(arguments, env=None, **_kwargs):
            captured.append((arguments, env))
            self.activate("next", theme / "backgrounds/wallpaper.png")

        with patch.object(self.helper, "run_omarchy", side_effect=set_theme):
            code, payloads, errors = self.invoke_main("switch-theme", "--theme", "next")
        self.assertEqual(code, 0, errors)
        self.assertEqual(len(captured), 1)
        self.assertNotIn("OMARCHY_THEME_SKIP_BACKGROUND", captured[0][1])
        self.assertTrue(payloads[-1]["ok"])
        self.assertEqual(payloads[-1]["status"]["current"]["theme"], "next")

    def test_bridge_progress_is_emitted_before_final_result(self):
        self.theme("next")
        previous = self.write(self.root / "old.png")
        target = self.write(self.root / "target.png")
        self.activate("old", previous)
        self.write(self.helper.OMARCHY_PATH / "bin/omarchy-shell")
        inherited_path = os.environ.get("PATH")

        def native_set(arguments, env=None, on_poll=None):
            self.assertEqual(arguments, ["theme", "set", "next"])
            context = Path(env["OMARCHY_APPEARANCE_CONTEXT"])
            self.assertEqual(context.stat().st_mode & 0o777, 0o600)
            self.assertEqual(context.parent.stat().st_mode & 0o777, 0o700)
            self.assertEqual(json.loads(context.read_text())["requestId"], "9")
            self.activate("next", target)
            (context.parent / "applied.json").write_text(json.dumps({
                "version": 1, "ok": True, "status": self.helper.build_status(),
            }))
            on_poll()

        with patch.object(self.helper, "run_omarchy", side_effect=native_set):
            code, payloads, errors = self.invoke_main("switch-theme", "--theme", "next", "--background", str(target), "--request-id", "9")
        self.assertEqual(code, 0, errors)
        self.assertEqual([payload.get("event", "final") for payload in payloads], ["applied", "final"])
        self.assertEqual(os.environ.get("PATH"), inherited_path)
        self.assertTrue(payloads[-1]["restored"])

    def test_bounded_command_terminates_descendant_on_timeout(self):
        pid_path = self.root / "child.pid"
        program = (
            "import subprocess,time,pathlib; "
            "p=subprocess.Popen(['sleep','30']); "
            f"pathlib.Path({str(pid_path)!r}).write_text(str(p.pid)); "
            "time.sleep(30)"
        )
        started = time.monotonic()
        with self.assertRaisesRegex(self.helper.AppearanceError, "timed out"):
            self.helper.run_bounded([sys.executable, "-B", "-c", program], timeout=0.2)
        self.assertLess(time.monotonic() - started, 5)
        self.assertTrue(pid_path.exists())
        child = int(pid_path.read_text())
        status = Path(f"/proc/{child}/stat")
        if status.exists():
            self.assertEqual(status.read_text().split()[2], "Z", "child must have exited, even if init has not reaped it")

    def test_background_cleanup_inheriting_output_does_not_delay_completion(self):
        cleanup_done = self.root / "cleanup-done"
        cleanup = f"import pathlib,time; time.sleep(0.6); pathlib.Path({str(cleanup_done)!r}).touch()"
        parent = f"import subprocess,sys; subprocess.Popen([sys.executable,'-B','-c',{cleanup!r}]); print('foreground done',flush=True); print('diagnostic',file=sys.stderr,flush=True)"
        started = time.monotonic()
        result = self.helper.run_bounded([sys.executable, "-B", "-c", parent], timeout=0.3)
        self.assertLess(time.monotonic() - started, 0.5)
        self.assertEqual(result.returncode, 0)
        self.assertEqual(result.stdout, "foreground done\n")
        self.assertEqual(result.stderr, "diagnostic\n")
        deadline = time.monotonic() + 2
        while not cleanup_done.exists() and time.monotonic() < deadline:
            time.sleep(0.01)
        self.assertTrue(cleanup_done.exists(), "successful commands leave native cleanup running")

    def test_interruption_is_not_treated_as_success_after_state_change(self):
        target = self.write(self.root / "chosen.png")

        def interrupted(arguments, **kwargs):
            self.helper.replace_background_link(target)
            raise self.helper.CommandInterrupted("cancelled")

        with patch.object(self.helper, "run_omarchy", side_effect=interrupted):
            with self.assertRaises(self.helper.CommandInterrupted):
                self.helper.apply_background(target)

    def test_expired_mutation_budget_does_not_start_another_command(self):
        self.helper.MUTATION_DEADLINE = time.monotonic() - 1
        with patch.object(self.helper.subprocess, "Popen") as start:
            with self.assertRaisesRegex(self.helper.AppearanceError, "timed out"):
                self.helper.run_bounded(["must-not-start"])
        start.assert_not_called()

    def test_sigterm_cleans_up_the_owned_command_group(self):
        pid_path = self.root / "owned.pid"
        program = f'''import importlib.machinery, importlib.util, sys
sys.dont_write_bytecode = True
loader = importlib.machinery.SourceFileLoader("signal_fixture", {str(HELPER_PATH)!r})
spec = importlib.util.spec_from_loader(loader.name, loader)
helper = importlib.util.module_from_spec(spec)
loader.exec_module(helper)
try:
    helper.run_bounded([sys.executable, "-B", "-c", "import os,pathlib,time; pathlib.Path({str(pid_path)!r}).write_text(str(os.getpid())); time.sleep(30)"])
except helper.CommandInterrupted:
    sys.exit(2)
'''
        parent = subprocess.Popen([sys.executable, "-B", "-c", program])
        try:
            deadline = time.monotonic() + 3
            while not pid_path.exists() and time.monotonic() < deadline:
                time.sleep(0.01)
            self.assertTrue(pid_path.exists())
            child = int(pid_path.read_text())
            parent.send_signal(signal.SIGTERM)
            self.assertEqual(parent.wait(timeout=5), 2)
            self.assertFalse(Path(f"/proc/{child}").exists())
        finally:
            if parent.poll() is None:
                parent.kill()
                parent.wait()


if __name__ == "__main__":
    unittest.main()
