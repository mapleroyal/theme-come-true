#!/usr/bin/env python3
"""Run the current Service with a fake helper and isolated paths, offscreen."""

import json
import os
from pathlib import Path
import shutil
import subprocess
import tempfile

ROOT = Path(__file__).resolve().parent.parent
OMARCHY = Path(os.environ.get("OMARCHY_PATH", "/usr/share/omarchy"))
if not shutil.which("quickshell") or not (OMARCHY / "shell/Commons").is_dir():
    raise SystemExit("The service lifecycle test requires Omarchy and QuickShell")

with tempfile.TemporaryDirectory(prefix="appearance-service-test-") as temporary:
    config = Path(temporary)
    fixture_home = config / "fixture-home"
    fixture_home.mkdir()
    (config / "Commons").symlink_to(OMARCHY / "shell/Commons", target_is_directory=True)
    (config / "Ui").symlink_to(OMARCHY / "shell/Ui", target_is_directory=True)
    for name in ("ScheduleModel.js", "NavigationModel.js"):
        (config / name).symlink_to(ROOT / name)
    # Only redirect Service filesystem paths. Its actual functions, QML
    # bindings, signals, timers and process stream parsers run unchanged.
    source = (ROOT / "Service.qml").read_text()
    original_home = 'readonly property string home: String(Quickshell.env("HOME") || "")'
    assert source.count(original_home) == 1, "Service path fixture needs updating"
    source = source.replace(original_home,
        'readonly property string home: String(Quickshell.env("APPEARANCE_TEST_HOME") || "")')
    (config / "TestService.qml").write_text(source)
    shutil.copyfile(ROOT / "tests/service-lifecycle.qml", config / "shell.qml")
    # Support the production relative helper path and the former installed path.
    for helper in (config / "appearance-helper", fixture_home / ".config/omarchy/plugins/io.github.mapleroyal.theme-come-true/appearance-helper"):
        helper.parent.mkdir(parents=True, exist_ok=True)
        shutil.copyfile(ROOT / "tests/fake-helper.py", helper)
        helper.chmod(0o755)
    inventory = {
        "version": 1,
        "current": {"theme": "a", "themeLabel": "A", "mode": "dark", "background": "/a.png",
                    "backgroundName": "a.png", "inThemePool": True, "inModePool": True},
        "themes": [{"slug": slug, "label": slug.upper(), "mode": "dark", "validPalette": True} for slug in "abc"],
        "pools": {"theme": 3, "mode": 3}, "palette": [],
    }
    (fixture_home / "state.json").write_text(json.dumps(inventory))
    environment = {**os.environ, "APPEARANCE_TEST_HOME": str(fixture_home),
                   "QT_QPA_PLATFORM": "offscreen", "QT_QPA_PLATFORMTHEME": "",
                   "QT_QUICK_CONTROLS_STYLE": "Basic"}
    environment.pop("WAYLAND_DISPLAY", None)
    environment.pop("DISPLAY", None)
    result = subprocess.run(["quickshell", "-p", str(config), "--no-color"], env=environment,
                            text=True, stdout=subprocess.PIPE, stderr=subprocess.STDOUT,
                            timeout=12, check=False)
    print(result.stdout, end="")
    if result.returncode != 0 or "appearance-service-lifecycle: PASS" not in result.stdout:
        raise SystemExit(1)
