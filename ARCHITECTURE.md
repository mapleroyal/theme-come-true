# Theme Come True architecture

Theme Come True runs as one Omarchy session service with a view on each monitor.
`BarWidget.qml` renders native controls and forwards intent. `Service.qml`
owns scheduling, accepted preferences, navigation history and a single active
operation. `ScheduleModel.js` and `NavigationModel.js` contain deterministic
calculations with explicit inputs. The Python helper owns OS inventory and
every theme/wallpaper mutation; the service never invokes a second mutation
path behind the adapter.

## State and completion

An operation captures its original theme, mode and wallpaper once. Its lifecycle
is apply, verify, commit preferences/history, then release controls. Successful
command exit is insufficient: every mutation returns a versioned JSON result
with an authoritative inventory snapshot. The service applies the complete
snapshot synchronously before it accepts another action. This prevents fast
clicks from reusing an old wallpaper or history tip.

Ordinary inventory probes carry a local generation and cannot overwrite a
newer operation. Solar requests also carry a generation so changing the weather
location cannot accept a previous location's in-flight response. A prepared
visual snapshot can update the view early; it does
not commit preferences or history. Final verification remains authoritative,
including when native commands change state and subsequently fail in an app
hook. Such confirmed changes are reported with warnings. Rejected operations
do not consume a shuffle bag or save a new theme. Scheduled failures retry
after 30 seconds with exponential backoff capped at five minutes; a new schedule
boundary or changed settings can try immediately. Mode toggles preserve each
mode's navigation history.

Quickshell does not emit `exited` for every failed launch. Deferred stopped-
process guards handle those cases. The helper bounds noninteractive mutation
work to 60 seconds and terminates its owned child process group on timeout or
interruption. Service watchdogs provide a backstop, wait for the helper to stop,
then refresh actual state before releasing the operation. Interactive pickers
have no elapsed-time limit while waiting for a user. Cancellation is normal.
Command output is captured in temporary files so native delayed snapshot
cleanup does not hold an otherwise finished operation open through pipe EOF.

## Omarchy compatibility boundary

The adapter uses native theme/background commands, the native image picker,
and the native file chooser. It leaves packaged files under `/usr/share`
unchanged. A per-invocation inventory shares palette and wallpaper reads without
keeping stale filesystem data between operations. Active mode/palette come
from Omarchy's staged theme and canonical color resolver. Inactive theme
inventory implements the corresponding stock/user overlay rules, legacy
Alacritty palettes, and the difference between installed Git themes and links
to a user's working copy. Fixtures cover these compatibility assumptions.

Omarchy 4.0.2 does not expose a single command that accepts both a theme and a
remembered wallpaper. `ipc-bridge/omarchy-shell` is a scoped compatibility
adapter for that gap. Only the native theme subprocess receives its directory
on PATH. The bridge recognizes that operation's exact palette/transition IPC,
validates a private operation context, and delegates all other calls unchanged
to the native IPC client. Native staging, locking and application hooks remain
owned by `omarchy theme set`.

For a remembered wallpaper, the helper preserves any old image that lived in
the replaceable staged theme directory and asks the native command to skip its
default background handling. At the native palette commit, the bridge sends
the target wallpaper and colors together to `background themeTransition`.
The native renderer preloads the image and changes shell colors at its reveal.
The bridge commits the wallpaper link after IPC acceptance. For a default
wallpaper, it preserves the native command's snapshot paths and link ownership.
The service receives the prepared snapshot before the transition, preloads the
small GUI preview, and applies labels/counts/swatches when native colors match
and the shell reloads its surface values at reveal. This signal also fires for
unchanged palettes. A fast final result waits for the same cue, with a bounded
fallback if the shell cannot expose it. Omarchy itself retains its image-load
fallback and 420 ms wallpaper animation.

The native caller allows two seconds for its IPC. Optional inventory preparation
and GUI preparation are separately capped at 350 ms and 200 ms, leaving time
for the native transition. Preparation runs in an owned process group that can
be terminated without abandoning its read-only resolver subprocesses.

This is a compatibility bridge, not a replacement theme engine or a promise
that independent application windows render on the same frame. External apps
still follow Omarchy's normal hooks. If preparation or the coordinated IPC
fails, native palette handling remains available and the helper verifies/falls
back to a usable wallpaper. A future native theme-plus-wallpaper API should
replace this bridge. Tests cover its exact IPC contract, failures and ownership.

## Persistence and caches

The shell's inline-settings API persists themes, schedule choices, manual
override deadlines and remembered wallpaper paths. Random/back history and
shuffle bags are bounded session state and intentionally reset on reload.
Wallpaper scope affects browsing/cycling; mode changes restore the last mode
wallpaper, and same-mode theme changes restore that theme's selected wallpaper,
including personal images and selections browsed from another theme's pool.

Omarchy 4.0.3 exposes a scoped shell facade to custom plugins. Read the plugin's
inline bar entry from its reactive `barConfig` snapshot, with `shellConfig` as a
fallback for older hosts. Settings writes replace the entry, so merge patches
with that current entry to preserve unrelated preferences and remembered paths.
The host's synchronous `shellConfig` signal can publish the preceding derived
`barConfig` to its scoped facade. Later probes can arrive before it observes the
saved entry. Commit an operation's theme/schedule preferences and wallpaper
memory in one entry write. Keep successfully written fields as a pending overlay
until the facade observes them, so a later inventory probe or settings change
cannot merge the preceding theme back into storage. Unrelated external fields
remain live; acknowledged fields resume following the facade, and rejected
writes do not retain an optimistic preference.

The picker cache presents an exact merged pool to Omarchy's directory-based
image picker. It uses owned directories, a lock, atomic publication, source
signatures and selection validation. Personal imports preserve the original,
deduplicate identical files and publish without overwriting existing images.
Solar data has bounded network waits, location fingerprints and cached future
events for offline fallback. These caches are separate from user preferences.

## Verification

Run these commands from the plugin directory:

```bash
omarchy plugin validate .
python3 -B -m unittest discover -s tests -p 'test_*.py'
node --test tests/*.test.mjs
python3 -B tests/run-ui-test.py
python3 -B tests/run-service-test.py
python3 -B tests/run-settings-test.py
```

Python tests use temporary fixtures, and the QML tests run offscreen. Node.js
is needed only for development tests. The native transition adapter is tested
against Omarchy 4.0.2-1 and Quickshell 0.3.1-1.
The settings regression uses Omarchy 4.0.3's actual scoped facade, its exact
synchronous host notification order, delayed publication and a legacy shell
fixture to check follow-up probes before acknowledgement, saved scope,
rejected writes, reactive updates and preservation of
themes, schedules, remembered wallpapers and additional settings.

Model tests cover time/solar boundaries, manual
overrides, DST, ordered/random navigation, removed choices and bounded history.
Helper fixtures cover native theme compatibility, authoritative outcomes,
timeouts, imports, cache generations and solar expiry. Native QML contract tests
run offscreen and check service-backed dropdowns without changing the desktop.
Live verification should additionally exercise both remembered and default
theme transitions, fast wallpaper navigation, and popup routing on monitors.
