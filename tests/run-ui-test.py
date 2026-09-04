#!/usr/bin/env python3
"""Exercise native Omarchy controls offscreen, without loading a desktop service."""

import os
from pathlib import Path
import shutil
import subprocess
import tempfile


ROOT = Path(__file__).resolve().parent.parent
OMARCHY = Path(os.environ.get("OMARCHY_PATH", "/usr/share/omarchy"))
if not shutil.which("quickshell") or not (OMARCHY / "shell/Ui").is_dir():
    raise SystemExit("The UI contract test requires Omarchy and QuickShell")

with tempfile.TemporaryDirectory(prefix="appearance-ui-test-") as temporary:
    config = Path(temporary)
    (config / "Commons").symlink_to(OMARCHY / "shell/Commons", target_is_directory=True)
    (config / "Ui").symlink_to(OMARCHY / "shell/Ui", target_is_directory=True)
    for name in ("BoundDropdown.qml", "ScheduleModel.js", "NavigationModel.js"):
        (config / name).symlink_to(ROOT / name)
    shutil.copyfile(ROOT / "tests/ui.qml", config / "shell.qml")
    environment = {
        **os.environ, "QT_QPA_PLATFORM": "offscreen", "QT_QPA_PLATFORMTHEME": "",
        "QT_QUICK_CONTROLS_STYLE": "Basic", "TZ": "America/Chicago",
    }
    environment.pop("WAYLAND_DISPLAY", None)
    environment.pop("DISPLAY", None)
    result = subprocess.run(
        ["quickshell", "-p", str(config), "--no-color"],
        env=environment, text=True, stdout=subprocess.PIPE, stderr=subprocess.STDOUT,
        timeout=15, check=False,
    )
    print(result.stdout, end="")
    if result.returncode != 0 or "appearance-ui-tests: PASS" not in result.stdout:
        raise SystemExit(1)
