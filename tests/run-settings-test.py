#!/usr/bin/env python3
"""Run production QML with the packaged scoped API and the legacy shell API.

All service filesystem paths and helper processes are isolated. This never
invokes Omarchy commands or modifies the live desktop/configuration.
"""
import json
import os
from pathlib import Path
import shutil
import subprocess
import tempfile

ROOT = Path(__file__).resolve().parent.parent
PACKAGED = Path(os.environ.get("OMARCHY_PATH", "/usr/share/omarchy")) / "shell"
FACADE = PACKAGED / "services/PluginShellApi.qml"
if not shutil.which("quickshell") or not FACADE.is_file():
    raise SystemExit("The settings test requires QuickShell and Omarchy's scoped plugin API")

for api_mode in ("scoped", "legacy"):
    with tempfile.TemporaryDirectory(prefix="appearance-settings-test-") as temporary:
        config = Path(temporary)
        fixture_home = config / "fixture-home"
        fixture_home.mkdir()
        (config / "Commons").symlink_to(PACKAGED / "Commons", target_is_directory=True)
        for name in ("ScheduleModel.js", "NavigationModel.js"):
            (config / name).symlink_to(ROOT / name)
        # Redirect paths only; execute the actual functions, QML bindings,
        # timers and process handlers against isolated fixtures.
        source = (ROOT / "Service.qml").read_text()
        original = 'readonly property string home: String(Quickshell.env("HOME") || "")'
        assert source.count(original) == 1, "Service path fixture needs updating"
        source = source.replace(original,
            'readonly property string home: String(Quickshell.env("APPEARANCE_TEST_HOME") || "")')
        (config / "TestService.qml").write_text(source)
        shutil.copyfile(FACADE, config / "HostShellApi.qml")
        shutil.copyfile(ROOT / "tests/settings-contract.qml", config / "shell.qml")
        helper = config / "appearance-helper"
        shutil.copyfile(ROOT / "tests/fake-helper.py", helper)
        helper.chmod(0o755)
        inventory = {
            "version": 1,
            "current": {"theme": "a", "themeLabel": "A", "mode": "dark", "background": "/a.png",
                        "backgroundName": "a.png", "inThemePool": True, "inModePool": True},
            "themes": [{"slug": slug, "label": slug.upper(),
                        "mode": "light" if slug == "l" else "dark", "validPalette": True}
                       for slug in "abl"],
            "pools": {"theme": 3, "mode": 12}, "palette": [],
        }
        (fixture_home / "state.json").write_text(json.dumps(inventory))
        environment = {**os.environ, "APPEARANCE_TEST_HOME": str(fixture_home),
                       "APPEARANCE_API_MODE": api_mode,
                       "QT_QPA_PLATFORM": "offscreen", "QT_QPA_PLATFORMTHEME": "",
                       "QT_QUICK_CONTROLS_STYLE": "Basic"}
        environment.pop("WAYLAND_DISPLAY", None)
        environment.pop("DISPLAY", None)
        result = subprocess.run(["quickshell", "-p", str(config), "--no-color"], env=environment,
                                text=True, stdout=subprocess.PIPE, stderr=subprocess.STDOUT,
                                timeout=10, check=False)
        expected = f"settings-regression: PASS {api_mode}"
        if result.returncode != 0 or expected not in result.stdout:
            print(result.stdout, end="")
            raise SystemExit(1)
        for line in result.stdout.splitlines():
            if "settings-regression:" in line:
                print(line)
