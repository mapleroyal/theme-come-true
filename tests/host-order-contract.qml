import QtQuick
import Quickshell
import "." as Fixture

ShellRoot {
  id: host
  readonly property string pluginId: "io.github.mapleroyal.theme-come-true"
  property bool observe: false
  property int step: 0
  property int ticks: 0
  property int failures: 0
  property var shellConfig: ({bar: {layout: {right: [{
    id: pluginId, darkTheme: "a", lightTheme: "l", autoEnabled: false,
    rememberedWallpapers: {"mode:dark": "/a.png", "theme:a": "/a.png"},
    customFutureSetting: "preserved"
  }]}}})
  // Match the actual host declaration/notification order. The scoped facade
  // copies the preceding derived barConfig during shellConfig's signal.
  onShellConfigChanged: if (observe) registry.pluginsChanged()
  readonly property var barConfig: shellConfig.bar

  QtObject { id: registry; signal pluginsChanged() }
  Connections {
    target: registry
    function onPluginsChanged() { facade.barConfig = host.publicBarConfig() }
  }

  function publicBarConfig() { return JSON.parse(JSON.stringify(host.barConfig)) }
  function check(actual, expected, label) {
    if (JSON.stringify(actual) === JSON.stringify(expected)) return
    host.failures++
    console.error("CHECK FAIL:", label, JSON.stringify(actual), "expected", JSON.stringify(expected))
  }

  Fixture.HostShellApi {
    id: facade
    pluginId: host.pluginId
    _updateSettings: function(id, entry) {
      if (id !== host.pluginId) throw new Error("Unexpected plugin settings write")
      var next = JSON.parse(JSON.stringify(host.shellConfig))
      next.bar.layout.right = [entry]
      host.shellConfig = next
      return true
    }
  }
  Fixture.TestService { id: service; shell: facade }

  Component.onCompleted: {
    // Production creates the facade with an imperative snapshot, not a binding.
    facade.barConfig = host.publicBarConfig()
    host.observe = true
  }

  Timer {
    interval: 30
    running: true
    repeat: true
    onTriggered: {
      if (++host.ticks > 100) {
        console.error("settings-regression: STALLED host-order")
        Qt.quit()
        return
      }
      if (host.step === 0) {
        // Let both startup refresh requests drain before injecting the
        // verified outcome; the fake helper deliberately stays at theme A.
        if (!service.ready || !service.statusFinished || host.ticks < 5) return
        var next = JSON.parse(JSON.stringify(service.snapshot))
        next.current.theme = "b"
        next.current.background = "/chosen-b.png"
        service.operation = {kind: "theme", theme: "b", mode: "dark", pairMode: "dark"}
        service.applySnapshot(next)
        service.finishAction(true)
        // A filesystem-triggered probe can finish before the host publishes
        // our saved entry. It must not merge the preceding scoped theme back.
        service.statusGeneration = service.stateGeneration
        service.consumeStatus(JSON.stringify(next))
        host.check(service.pendingSettings.darkTheme, "b", "selection retained until acknowledgement")
        host.check(host.shellConfig.bar.layout.right[0].darkTheme, "b", "theme survives completion writes")
        host.check(host.shellConfig.bar.layout.right[0].rememberedWallpapers["theme:b"],
                   "/chosen-b.png", "wallpaper saved with theme")
        host.check(host.shellConfig.bar.layout.right[0].customFutureSetting, "preserved", "unrelated preference")
        // Model FileView's subsequent reload of the saved payload. This is
        // separate from the synchronous writes that previously lost the theme.
        host.shellConfig = JSON.parse(JSON.stringify(host.shellConfig))
      } else {
        host.check(service.darkTheme, "b", "dropdown model after host reload")
        host.check(Object.keys(service.pendingSettings).length, 0, "acknowledged overlay is released")
        host.check(service.rememberedThemeWallpaper("a"), "/a.png", "previous wallpaper retained")
        console.log("settings-regression:", host.failures ? "FAIL" : "PASS", "host-order", host.failures + " failures")
        Qt.quit()
      }
      host.step++
    }
  }
}
