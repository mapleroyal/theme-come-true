import QtQuick
import Quickshell
import qs.Commons
import "." as Fixture

ShellRoot {
  id: root
  property int step: 0
  property int ticks: 0
  property bool observedBusySnapshot: false
  property int renderingTicks: 0

  QtObject {
    id: fakeShell
    property var shellConfig: ({bar: {layout: {left: [], center: [], right: [
      {id: "io.github.mapleroyal.theme-come-true", darkTheme: "a", autoEnabled: false}
    ]}}})
    function updateEntryInline(id, entry) {
      var copy = JSON.parse(JSON.stringify(shellConfig))
      copy.bar.layout.right = [entry]
      shellConfig = copy
      return true
    }
  }

  Fixture.TestService {
    id: service
    shell: fakeShell
  }

  Connections {
    target: service
    function onSnapshotChanged() {
      if (service.snapshot.current && service.snapshot.current.background === "/b.png" && service.busy)
        root.observedBusySnapshot = true
    }
  }

  function assertEqual(actual, expected, label) {
    if (actual !== expected) throw new Error(label + ": expected " + expected + ", got " + actual)
  }
  function startMissingAction() {
    service.beginAction({kind: "wallpaper", navigationKind: "random", poolKey: "theme:b"},
      ["/appearance-test-missing-executable"], "Missing helper")
  }

  Timer {
    interval: 20
    running: true
    repeat: true
    onTriggered: {
      try {
        if (++root.ticks > 300) throw new Error("Lifecycle test stalled at step " + root.step + ": " + service.lastError)
        if (root.step === 0) {
          if (!service.ready) return
          root.assertEqual(service.currentBackground, "/a.png", "Initial inventory")
          root.assertEqual(service.randomWallpaper(), true, "Start first wallpaper")
          root.step = 1
        } else if (root.step === 1 && !service.busy) {
          root.assertEqual(service.currentBackground, "/b.png", "First result")
          root.assertEqual(root.observedBusySnapshot, true, "Snapshot commits before unlock")
          service.randomWallpaper()
          root.step = 2
        } else if (root.step === 2 && !service.busy) {
          root.assertEqual(service.currentBackground, "/c.png", "Second result")
          root.assertEqual(service.wallpaperRandomBackTarget("theme:a"), "/b.png", "Recent Previous target")
          service.previousWallpaper()
          root.step = 3
        } else if (root.step === 3 && !service.busy) {
          root.assertEqual(service.currentBackground, "/b.png", "Previous applied")
          root.assertEqual(service.chooseTheme("dark", "b", "random", ["c"]), true, "Theme action")
          root.step = 4
        } else if (root.step === 4) {
          if (service.busy) {
            if (service.operation.phase === "rendering") {
              root.assertEqual(service.currentTheme, "a", "Final result waits for native reveal")
              if (++root.renderingTicks === 5) Color.loadShell("")
            }
            return
          }
          root.assertEqual(root.renderingTicks, 5, "Unchanged colors still receive a shell reveal cue")
          root.assertEqual(service.currentTheme, "b", "Theme stdout before exit")
          root.assertEqual(service.settings.darkTheme, "b", "Pair persisted after verification")
          root.assertEqual(service.darkRandomBackHistory.join(","), "a", "Theme history committed")
          service.beginAction({kind: "theme", mode: "dark", theme: "c", pairMode: "dark", navigationKind: "random"},
            [service.helperPath, "fail"], "Failing fixture")
          root.step = 5
        } else if (root.step === 5 && !service.busy) {
          root.assertEqual(service.settings.darkTheme, "b", "Failure preserves pair")
          root.assertEqual(service.darkRandomBackHistory.join(","), "a", "Failure preserves history")
          root.assertEqual(service.lastError, "fixture failure", "Failure message")
          root.startMissingAction()
          root.step = 6
        } else if (root.step === 6 && !service.busy) {
          root.assertEqual(service.ready, true, "Missing executable recovers inventory")
          root.assertEqual(service.lastError, "Could not start appearance helper", "Missing executable message")
          service.browseWallpapers()
          root.step = 7
        } else if (root.step === 7 && !service.busy) {
          root.assertEqual(service.currentTheme, "b", "Picker cancellation preserves desktop")
          root.assertEqual(service.lastError, "", "Cancellation isn't failure")
          service.startWallpaperSelection("Missing picker", ["/appearance-test-missing-picker"], "file")
          root.step = 8
        } else if (root.step === 8 && !service.busy) {
          root.assertEqual(service.lastError, "Could not open the file chooser", "Missing picker recovers")
          service.beginAction({kind: "wallpaper", navigationKind: "random", poolKey: "theme:b"},
            [service.helperPath, "invalid-output"], "Invalid output")
          root.step = 9
        } else if (root.step === 9 && !service.busy) {
          root.assertEqual(service.ready, true, "Missing confirmation recovered inventory")
          root.assertEqual(service.currentTheme, "b", "Recovery state")
          if (service.lastError === "") throw new Error("Invalid action output must surface failure")
          console.log("appearance-service-lifecycle: PASS")
          Qt.quit()
        }
      } catch (error) {
        console.error("appearance-service-lifecycle: FAIL", error)
        Qt.quit()
      }
    }
  }
}
