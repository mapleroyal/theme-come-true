import QtQuick
import Quickshell
import "." as Fixture

ShellRoot {
  id: root
  readonly property string pluginId: "io.github.mapleroyal.theme-come-true"
  readonly property string apiMode: Quickshell.env("APPEARANCE_API_MODE")
  property int step: 0
  property int ticks: 0
  property int failures: 0
  property int checks: 0
  property var initialEntry: ({
    id: pluginId, wallpaperScope: "mode", darkTheme: "b", lightTheme: "l",
    autoEnabled: false, lightStart: "08:15", darkStart: "20:45",
    importPersonalWallpaper: false,
    rememberedWallpapers: {"mode:dark": "/a.png", "theme:a": "/a.png",
                          "theme:b": "/remembered-b.png", "mode:light": "/remembered-l.png"},
    customFutureSetting: {enabled: true, value: 17}
  })
  property var config: ({bar: {layout: {left: [], center: [], right: [initialEntry]}}})
  property var publishedConfig: ({bar: {layout: {left: [], center: [], right: [initialEntry]}}})

  function persist(id, entry) {
    if (id !== root.pluginId) throw new Error("Attempt to update another plugin")
    var copy = JSON.parse(JSON.stringify(root.config))
    copy.bar.layout.right = [entry]
    root.config = copy
    if (root.apiMode === "scoped-delayed") publication.restart()
    return true
  }

  Timer {
    id: publication
    interval: 5
    onTriggered: root.publishedConfig = JSON.parse(JSON.stringify(root.config))
  }

  Fixture.HostShellApi {
    id: scopedApi
    pluginId: root.pluginId
    barConfig: root.apiMode === "scoped-delayed" ? root.publishedConfig.bar : root.config.bar
    _updateSettings: function(id, entry) { return root.persist(id, entry) }
  }

  QtObject {
    id: legacyApi
    property var shellConfig: root.config
    function updateEntryInline(id, entry) { return root.persist(id, entry) }
  }

  Fixture.TestService {
    id: service
    shell: root.apiMode === "legacy" ? legacyApi : scopedApi
  }

  function equal(actual, expected, label) {
    root.checks++
    if (JSON.stringify(actual) === JSON.stringify(expected)) return
    root.failures++
    console.error("CHECK FAIL:", label, "expected", JSON.stringify(expected), "got", JSON.stringify(actual))
  }

  function preserved(label) {
    var entry = root.config.bar.layout.right[0]
    for (var key in root.initialEntry) {
      if (key !== "wallpaperScope") root.equal(entry[key], root.initialEntry[key], label + " preserves " + key)
    }
    root.equal(service.settings.rememberedWallpapers, root.initialEntry.rememberedWallpapers,
               label + " remembered wallpapers readable")
  }

  Timer {
    interval: 30
    running: true
    repeat: true
    onTriggered: {
      if (++root.ticks > 150) {
        console.error("settings-regression: STALLED", service.lastError)
        Qt.quit()
        return
      }
      if (root.step === 0) {
        if (!service.ready) return
        root.equal(service.wallpaperScope, "mode", "saved scope read on startup")
        root.equal(service.configuredDarkTheme, "b", "saved theme read on startup")
        root.equal(service.importPersonalWallpaper, false, "saved boolean read on startup")
        root.preserved("startup")
        service.setWallpaperScope("theme")
      } else if (root.step === 1) {
        root.equal(service.wallpaperScope, "theme", "toggle off updates reactive scope")
        root.equal(root.config.bar.layout.right[0].wallpaperScope, "theme", "toggle off persists")
        root.preserved("toggle off")
        service.setWallpaperScope("mode")
      } else if (root.step === 2) {
        root.equal(service.wallpaperScope, "mode", "toggle on updates reactive scope")
        root.equal(root.config.bar.layout.right[0].wallpaperScope, "mode", "toggle on persists")
        root.preserved("toggle on")
        var copy = JSON.parse(JSON.stringify(root.config))
        copy.bar.layout.right[0].wallpaperScope = "theme"
        root.config = copy
      } else if (root.step === 3) {
        if (root.apiMode === "scoped-delayed") root.publishedConfig = root.config
        root.equal(service.wallpaperScope, "theme", "external settings refresh is reactive")
        root.preserved("external refresh")
        service.updateSettings({darkTheme: "a"})
      } else if (root.step === 4) {
        var next = JSON.parse(JSON.stringify(service.snapshot))
        next.current.theme = "b"
        next.current.background = "/other-theme/chosen.png"
        next.current.inThemePool = false
        service.operation = {kind: "theme", mode: "dark", theme: "b", pairMode: "dark"}
        service.applySnapshot(next)
        service.finishAction(true)
      } else if (root.step === 5) {
        root.equal(service.configuredDarkTheme, "b", "completion keeps accepted dropdown selection")
        root.equal(root.config.bar.layout.right[0].darkTheme, "b", "completion persists accepted theme")
        root.equal(service.rememberedThemeWallpaper("b"), "/other-theme/chosen.png",
                   "completion remembers image from another theme")
        root.equal(service.settings.customFutureSetting, root.initialEntry.customFutureSetting,
                   "completion preserves unrelated preferences")
        console.log("settings-regression:", root.failures === 0 ? "PASS" : "FAIL",
                    root.apiMode, root.checks + " checks", root.failures + " failures")
        Qt.quit()
      }
      root.step++
    }
  }
}
