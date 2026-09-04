#!/usr/bin/env python3
"""Local-only process fixture; never invokes Omarchy or changes the desktop."""

import json
import os
from pathlib import Path
import sys

state_file = Path(os.environ["APPEARANCE_TEST_HOME"]) / "state.json"
state = json.loads(state_file.read_text())
arguments = sys.argv[1:]
command = arguments[0]
request_id = arguments[arguments.index("--request-id") + 1] if "--request-id" in arguments else ""


def emit(value):
    print(json.dumps(value), flush=True)


if command == "status":
    emit(state)
elif command == "browse":
    emit({"version": 1, "selected": False})
elif command == "invalid-output":
    print("not a confirmed JSON result", flush=True)
elif command == "fail":
    emit({"version": 1, "requestId": request_id, "ok": False, "error": "fixture failure", "status": state})
    raise SystemExit(1)
else:
    current = state["current"]
    if command == "cycle":
        current["background"] = {"/a.png": "/b.png", "/b.png": "/c.png"}.get(current["background"], "/a.png")
    elif command == "set-wallpaper":
        current["background"] = arguments[1]
    elif command == "switch-theme":
        current["theme"] = arguments[arguments.index("--theme") + 1]
        current["themeLabel"] = current["theme"].upper()
        current["background"] = "/" + current["theme"] + "-theme.png"
    else:
        raise SystemExit("Unexpected fixture command: " + command)
    current["backgroundName"] = current["background"]
    state_file.write_text(json.dumps(state))
    emit({"version": 1, "requestId": request_id, "event": "applied", "status": state})
    emit({"version": 1, "requestId": request_id, "ok": True, "status": state})
