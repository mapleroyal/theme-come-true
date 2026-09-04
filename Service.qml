import QtQuick
import Quickshell
import Quickshell.Io
import qs.Commons
import "ScheduleModel.js" as ScheduleModel
import "NavigationModel.js" as NavigationModel

Item {
  id: root

  // Injected by omarchy-shell for service plugins.
  property var shell: null
  property var manifest: null

  readonly property string pluginId: "io.github.mapleroyal.theme-come-true"
  readonly property string home: String(Quickshell.env("HOME") || "")
  readonly property string helperPath: decodeURIComponent(String(Qt.resolvedUrl("appearance-helper")).replace(/^file:\/\//, ""))
  readonly property string statePath: home + "/.local/state/omarchy/current"
  readonly property string weatherLocationPath: home + "/.local/state/omarchy/settings/weather.json"
  readonly property string userThemesPath: home + "/.config/omarchy/themes"
  readonly property string userBackgroundsPath: home + "/.config/omarchy/backgrounds"

  property bool ready: false
  // One operation owns apply -> verify -> remember -> release. A returned
  // process exit alone never makes stale desktop state available to actions.
  property var operation: null
  readonly property bool busy: operation !== null
  property int requestSequence: 0
  property int stateGeneration: 0
  property int statusGeneration: -1
  property string actionStatus: ""
  property string lastError: ""
  property var snapshot: ({})
  readonly property var current: snapshot.current || ({})
  readonly property string currentTheme: String(current.theme || "")
  readonly property string currentThemeLabel: String(current.themeLabel || "Unknown")
  readonly property string currentMode: current.mode === "light" ? "light" : "dark"
  readonly property string currentBackground: String(current.background || "")
  readonly property string currentBackgroundName: String(current.backgroundName || "No wallpaper")
  readonly property bool currentInThemePool: current.inThemePool === true
  readonly property bool currentInModePool: current.inModePool === true
  readonly property int themeWallpaperCount: Number(snapshot.pools && snapshot.pools.theme || 0)
  readonly property int modeWallpaperCount: Number(snapshot.pools && snapshot.pools.mode || 0)
  readonly property var themes: snapshot.themes || []
  property alias themePaletteModel: themePaletteModel
  readonly property int themePaletteCount: themePaletteModel.count
  ListModel { id: themePaletteModel }

  property var preparedSnapshot: null
  property var pendingCompletion: null
  property int themeRenderSerial: 0
  readonly property string previewBackground: preparedSnapshot && preparedSnapshot.current
    ? String(preparedSnapshot.current.background || "") : ""
  readonly property string displayLightTheme: operation && operation.visualCommitted
    && operation.pairMode === "light" ? operation.theme : lightTheme
  readonly property string displayDarkTheme: operation && operation.visualCommitted
    && operation.pairMode === "dark" ? operation.theme : darkTheme
  property bool refreshQueued: false
  property bool statusReceived: false
  property bool statusFinished: true
  property string statusError: ""
  property string actionError: ""
  property var actionResult: null
  property bool actionFinished: true
  property bool actionStarted: false
  property string selectionOutput: ""
  property string selectionError: ""
  property bool selectionFinished: true
  property bool selectionStarted: false
  property bool solarFinished: true
  property var lightRandomBackHistory: []
  property var darkRandomBackHistory: []
  property string lightRandomHistoryTip: ""
  property string darkRandomHistoryTip: ""
  property var lightRandomBag: []
  property var darkRandomBag: []
  property var wallpaperRandomHistories: ({})
  property var wallpaperRandomTips: ({})
  property string lastScheduleToken: ""
  property string scheduleFailureToken: ""
  property int scheduleFailureCount: 0
  property double scheduleRetryAt: 0
  property double clockNow: Date.now()

  property bool solarReady: false
  property int solarGeneration: 0
  property int solarRequestGeneration: -1
  property bool solarLoading: false
  property bool solarReceived: false
  property bool solarRefreshQueued: false
  property string solarError: ""
  property string solarProcessError: ""
  property string solarLocation: ""
  property string solarLocationSource: ""
  property string solarTimezone: ""
  property double solarTodaySunrise: 0
  property double solarTodaySunset: 0
  property double solarLoadedAt: 0
  property double solarLastAttemptAt: 0
  property var solarEvents: []

  function settingsFromShell() {
    var config = root.shell ? root.shell.shellConfig : null
    if (!config) return ({})

    var layout = config.bar && config.bar.layout ? config.bar.layout : null
    var sections = ["left", "center", "right"]
    if (layout) {
      for (var s = 0; s < sections.length; s++) {
        var entries = layout[sections[s]] || []
        for (var i = 0; i < entries.length; i++) {
          if (entries[i] && String(entries[i].id || "") === root.pluginId)
            return entries[i]
        }
      }
    }

    var plugins = config.plugins || []
    for (var p = 0; p < plugins.length; p++) {
      if (plugins[p] && String(plugins[p].id || "") === root.pluginId)
        return plugins[p]
    }
    return ({})
  }

  readonly property var settings: root.settingsFromShell()
  readonly property string configuredLightTheme: String(settings.lightTheme || "catppuccin-latte")
  readonly property string configuredDarkTheme: String(settings.darkTheme || "catppuccin")
  readonly property string wallpaperScope: String(settings.wallpaperScope || "theme") === "mode" ? "mode" : "theme"
  readonly property bool importPersonalWallpaper: root.booleanValue(settings.importPersonalWallpaper, true)
  readonly property bool autoEnabled: root.booleanValue(settings.autoEnabled, false)
  readonly property string lightStart: root.normalizedBoundary("light", String(settings.lightStart || "07:00"))
  readonly property string darkStart: root.normalizedBoundary("dark", String(settings.darkStart || "19:00"))
  readonly property bool usesSolarSchedule: lightStart === "sunrise" || darkStart === "sunset"
  readonly property string manualOverrideMode: String(settings.manualOverrideMode || "")
  readonly property double manualOverrideUntil: Number(settings.manualOverrideUntil || 0)
  readonly property var rememberedWallpapers: root.plainObject(settings.rememberedWallpapers) ? settings.rememberedWallpapers : ({})

  readonly property var lightThemeOptions: root.optionsForMode("light")
  readonly property var darkThemeOptions: root.optionsForMode("dark")
  readonly property int currentModeThemeCount: currentMode === "light"
    ? lightThemeOptions.length : darkThemeOptions.length
  readonly property int currentWallpaperPoolCount: wallpaperScope === "mode"
    ? modeWallpaperCount : themeWallpaperCount
  readonly property bool currentInWallpaperPool: wallpaperScope === "mode"
    ? currentInModePool : currentInThemePool
  readonly property bool canRandomizeWallpaper: currentWallpaperPoolCount > 1
    || (currentWallpaperPoolCount === 1 && !currentInWallpaperPool)
  readonly property bool themeNavigationBusy: busy
  readonly property string lightTheme: root.resolvedTheme("light", configuredLightTheme)
  readonly property string darkTheme: root.resolvedTheme("dark", configuredDarkTheme)
  readonly property var timeOptions: root.buildTimeOptions()
  readonly property var lightStartOptions: root.buildBoundaryOptions("light")
  readonly property var darkStartOptions: root.buildBoundaryOptions("dark")
  readonly property string scheduleSignature: JSON.stringify({
    enabled: autoEnabled,
    lightTheme: lightTheme,
    darkTheme: darkTheme,
    lightStart: lightStart,
    darkStart: darkStart,
    overrideMode: manualOverrideMode,
    overrideUntil: manualOverrideUntil
  })

  onScheduleSignatureChanged: {
    root.lastScheduleToken = ""
    root.resetScheduleRetry()
    if (root.usesSolarSchedule) solarRequestDebounce.restart()
    scheduleDebounce.restart()
  }

  onSolarEventsChanged: {
    root.lastScheduleToken = ""
    scheduleDebounce.restart()
  }

  onUsesSolarScheduleChanged: {
    if (root.usesSolarSchedule) solarRequestDebounce.restart()
  }

  function plainObject(value) {
    return value !== null && typeof value === "object" && !Array.isArray(value)
  }

  function booleanValue(value, fallback) {
    if (value === true || value === false) return value
    if (value === undefined || value === null || value === "") return fallback
    var normalized = String(value).toLowerCase()
    return normalized === "true" || normalized === "yes" || normalized === "1" || normalized === "on"
  }

  function validTime(value) { return ScheduleModel.validTime(value) }

  function normalizedBoundary(kind, value) {
    return ScheduleModel.normalizedBoundary(kind, value)
  }

  function parseMinutes(value) { return ScheduleModel.parseMinutes(value) }

  function formatTime(value) {
    var minutes = root.parseMinutes(value)
    var hour = Math.floor(minutes / 60)
    var minute = minutes % 60
    var suffix = hour >= 12 ? "PM" : "AM"
    var displayHour = hour % 12
    if (displayHour === 0) displayHour = 12
    return displayHour + ":" + String(minute).padStart(2, "0") + " " + suffix
  }

  function buildTimeOptions() {
    var result = []
    for (var hour = 0; hour < 24; hour++) {
      for (var minute = 0; minute < 60; minute += 30) {
        var value = String(hour).padStart(2, "0") + ":" + String(minute).padStart(2, "0")
        result.push({ value: value, label: root.formatTime(value) })
      }
    }
    return result
  }

  function formatEpoch(epochSeconds) {
    var value = Number(epochSeconds || 0)
    if (value <= 0) return "—"
    return new Date(value * 1000).toLocaleTimeString(Qt.locale(), "h:mm AP")
  }

  function nextSolarEpoch(kind, nowMs) {
    var nowSeconds = Number(nowMs === undefined ? root.clockNow : nowMs) / 1000
    var next = 0
    for (var i = 0; i < root.solarEvents.length; i++) {
      var event = root.solarEvents[i]
      var epoch = Number(event && event.epoch || 0)
      if (event && event.event === kind && epoch > nowSeconds && (next === 0 || epoch < next))
        next = epoch
    }
    return next
  }

  function buildBoundaryOptions(kind) {
    var result = []
    if (kind === "light") {
      result.push({
        value: "sunrise",
        label: root.solarReady && root.nextSolarEpoch("sunrise") > 0
          ? "Sunrise · " + root.formatEpoch(root.nextSolarEpoch("sunrise")) : "Sunrise"
      })
    } else {
      result.push({
        value: "sunset",
        label: root.solarReady && root.nextSolarEpoch("sunset") > 0
          ? "Sunset · " + root.formatEpoch(root.nextSolarEpoch("sunset")) : "Sunset"
      })
    }
    for (var i = 0; i < root.timeOptions.length; i++) result.push(root.timeOptions[i])
    return result
  }

  function optionsForMode(mode) {
    var result = []
    for (var i = 0; i < root.themes.length; i++) {
      var theme = root.themes[i]
      if (!theme || theme.mode !== mode || theme.validPalette !== true) continue
      result.push({
        value: String(theme.slug),
        label: String(theme.label),
        description: Number(theme.wallpaperCount || 0) + " wallpapers"
      })
    }
    return result
  }

  function optionContains(options, value) {
    for (var i = 0; i < options.length; i++)
      if (String(options[i].value) === String(value)) return true
    return false
  }

  function resolvedTheme(mode, preferred) {
    var options = mode === "light" ? root.lightThemeOptions : root.darkThemeOptions
    // Before inventory arrives, retain the configured default so startup
    // automation has a stable target once ready flips true.
    if (options.length === 0) return root.ready ? "" : String(preferred || "")
    if (root.optionContains(options, preferred)) return String(preferred)
    return String(options[0].value)
  }

  function themeForMode(mode) {
    return mode === "light" ? root.lightTheme : root.darkTheme
  }

  function updateSettings(patch) {
    if (!root.shell || typeof root.shell.updateEntryInline !== "function") return false
    var next = { id: root.pluginId }
    for (var key in root.settings) if (key !== "id") next[key] = root.settings[key]
    for (var changed in patch) next[changed] = patch[changed]
    return root.shell.updateEntryInline(root.pluginId, next)
  }

  function randomHistoryForMode(mode) {
    var history = mode === "light" ? root.lightRandomBackHistory : root.darkRandomBackHistory
    return Array.isArray(history) ? history : []
  }

  function randomHistoryTipForMode(mode) {
    return mode === "light" ? root.lightRandomHistoryTip : root.darkRandomHistoryTip
  }

  function setRandomHistory(mode, history, tip) {
    var next = Array.isArray(history) ? history.slice() : []
    if (mode === "light") {
      root.lightRandomBackHistory = next
      root.lightRandomHistoryTip = String(tip || "")
    } else {
      root.darkRandomBackHistory = next
      root.darkRandomHistoryTip = String(tip || "")
    }
  }

  function clearRandomHistory(mode) {
    root.setRandomHistory(mode, [], "")
  }

  function randomBagForMode(mode) {
    var bag = mode === "light" ? root.lightRandomBag : root.darkRandomBag
    return Array.isArray(bag) ? bag : []
  }

  function setRandomBag(mode, bag) {
    var next = Array.isArray(bag) ? bag.slice() : []
    if (mode === "light") root.lightRandomBag = next
    else root.darkRandomBag = next
  }

  function clearRandomBag(mode) {
    root.setRandomBag(mode, [])
  }

  function clearRandomNavigation(mode) {
    root.clearRandomHistory(mode)
    root.clearRandomBag(mode)
  }

  function randomHistoryBackTarget(mode) {
    var options = mode === "light" ? root.lightThemeOptions : root.darkThemeOptions
    var result = NavigationModel.backTarget(root.randomHistoryForMode(mode),
      root.randomHistoryTipForMode(mode), root.currentTheme,
      options.map(function(option) { return String(option.value) }))
    root.setRandomHistory(mode, result.history, result.tip)
    if (result.invalidated) root.clearRandomBag(mode)
    return result.target
  }

  function commitPendingNavigation() {
    var op = root.operation
    if (!op || op.kind !== "theme" || !op.navigationKind) return
    var result = NavigationModel.commitHistory(root.randomHistoryForMode(op.mode),
      root.randomHistoryTipForMode(op.mode), op.navigationKind, op.fromTheme, op.theme, 32)
    root.setRandomHistory(op.mode, result.history, result.tip)
    if (op.navigationKind === "random") root.setRandomBag(op.mode, op.randomBag)
    else if (op.navigationKind !== "history-back") root.clearRandomBag(op.mode)
  }

  function chooseTheme(mode, slug, navigationKind, randomBag) {
    if (!root.ready || root.busy || (mode !== "light" && mode !== "dark")) return false
    var options = mode === "light" ? root.lightThemeOptions : root.darkThemeOptions
    if (!root.optionContains(options, slug)) return false
    var patch = mode === "light" ? { lightTheme: slug } : { darkTheme: slug }
    if (root.currentMode !== mode || root.currentTheme === slug) {
      root.clearRandomNavigation(mode)
      root.updateSettings(patch)
      return true
    }
    return root.startTheme(mode, slug, false, {
      pairMode: mode, navigationKind: String(navigationKind || "direct"), randomBag: randomBag || []
    })
  }

  function cycleTheme(direction) {
    if (root.busy || !root.ready || (direction !== "previous" && direction !== "next")) return false
    var mode = root.currentMode
    var options = mode === "light" ? root.lightThemeOptions : root.darkThemeOptions
    var target = NavigationModel.nextValue(options, root.currentTheme, direction)
    if (!target) { root.lastError = "No " + mode + " themes are available"; return false }
    return root.chooseTheme(mode, target, "sorted")
  }

  function previousTheme() {
    if (root.themeNavigationBusy || !root.ready) return false
    var mode = root.currentMode
    var target = root.randomHistoryBackTarget(mode)
    if (target !== "") return root.chooseTheme(mode, target, "history-back")
    return root.cycleTheme("previous")
  }

  function randomTheme() {
    if (root.busy || !root.ready) return false
    var mode = root.currentMode
    var options = mode === "light" ? root.lightThemeOptions : root.darkThemeOptions
    var tip = root.randomHistoryTipForMode(mode)
    if (tip !== "" && tip !== root.currentTheme) root.clearRandomNavigation(mode)
    var choice = NavigationModel.chooseRandom(options, root.currentTheme,
      root.randomBagForMode(mode), root.randomHistoryForMode(mode), Math.random())
    if (!choice.target) { root.lastError = "No " + mode + " themes are available"; return false }
    return root.chooseTheme(mode, choice.target, "random", choice.bag)
  }

  function wallpaperPoolKey() {
    return root.wallpaperScope === "mode"
      ? "mode:" + root.currentMode
      : "theme:" + root.currentTheme
  }

  function wallpaperRandomHistory(key) {
    var history = root.wallpaperRandomHistories[String(key || "")]
    return Array.isArray(history) ? history : []
  }

  function wallpaperRandomTip(key) {
    return String(root.wallpaperRandomTips[String(key || "")] || "")
  }

  function setWallpaperRandomHistory(key, history, tip) {
    var normalizedKey = String(key || "")
    if (normalizedKey === "") return

    var histories = ({})
    var tips = ({})
    for (var historyKey in root.wallpaperRandomHistories) {
      if (historyKey !== normalizedKey)
        histories[historyKey] = root.wallpaperRandomHistories[historyKey]
    }
    for (var tipKey in root.wallpaperRandomTips) {
      if (tipKey !== normalizedKey) tips[tipKey] = root.wallpaperRandomTips[tipKey]
    }

    var next = Array.isArray(history) ? history.slice() : []
    if (next.length > 0) {
      histories[normalizedKey] = next
      tips[normalizedKey] = String(tip || "")
    }
    root.wallpaperRandomHistories = histories
    root.wallpaperRandomTips = tips
  }

  function clearWallpaperRandomHistory(key) {
    root.setWallpaperRandomHistory(key, [], "")
  }

  function wallpaperRandomBackTarget(key) {
    var result = NavigationModel.backTarget(root.wallpaperRandomHistory(key),
      root.wallpaperRandomTip(key), root.currentBackground)
    root.setWallpaperRandomHistory(key, result.history, result.tip)
    return result.target
  }

  function commitPendingWallpaperNavigation() {
    var op = root.operation
    if (!op || op.kind !== "wallpaper") return
    // An external theme change must not attach wallpaper history to the old pool.
    if (root.currentTheme !== op.fromTheme || root.currentMode !== op.fromMode) {
      root.clearWallpaperRandomHistory(op.poolKey)
      return
    }
    var result = NavigationModel.commitHistory(root.wallpaperRandomHistory(op.poolKey),
      root.wallpaperRandomTip(op.poolKey), op.navigationKind,
      op.fromBackground, root.currentBackground, 32)
    root.setWallpaperRandomHistory(op.poolKey, result.history, result.tip)
  }

  function setWallpaperScope(scope) {
    root.updateSettings({ wallpaperScope: scope === "mode" ? "mode" : "theme" })
  }

  function setImportPersonalWallpaper(enabled) {
    root.updateSettings({ importPersonalWallpaper: enabled === true })
  }

  function setAutomatic(enabled) {
    root.updateSettings({
      autoEnabled: enabled === true,
      manualOverrideMode: "",
      manualOverrideUntil: 0
    })
    if (enabled === true) scheduleDebounce.restart()
  }

  function setScheduleTime(kind, value) {
    var boundary = root.normalizedBoundary(kind, String(value || ""))
    if (boundary !== value) return
    var patch = {
      manualOverrideMode: "",
      manualOverrideUntil: 0
    }
    if (kind === "light") patch.lightStart = boundary
    else patch.darkStart = boundary
    root.updateSettings(patch)
  }

  function fixedBoundaryEvents(mode, value, nowMs) {
    return ScheduleModel.fixedBoundaryEvents(mode, value, nowMs === undefined ? Date.now() : nowMs)
  }

  function boundaryEvents(nowMs) {
    return ScheduleModel.boundaryEvents(root.lightStart, root.darkStart, root.solarEvents,
      nowMs === undefined ? Date.now() : nowMs)
  }

  function nextBoundaryEpoch(nowMs) {
    var state = root.scheduleState(nowMs)
    return state.valid ? state.nextEpoch : 0
  }

  function scheduleState(nowMs) {
    return ScheduleModel.scheduleState({
      lightStart: root.lightStart, darkStart: root.darkStart,
      solarReady: root.solarReady, solarEvents: root.solarEvents,
      currentMode: root.currentMode, manualOverrideMode: root.manualOverrideMode,
      manualOverrideUntil: root.manualOverrideUntil
    }, nowMs === undefined ? Date.now() : nowMs)
  }

  function scheduleSummary() {
    var now = root.clockNow
    if (!root.autoEnabled) return "Automatic switching is off"
    if (root.manualOverrideUntil * 1000 > now) {
      var overrideState = root.scheduleState(now)
      return "Manual " + overrideState.mode + " until "
        + new Date(overrideState.nextEpoch).toLocaleTimeString(Qt.locale(), "h:mm AP")
    }
    if (root.usesSolarSchedule && !root.solarReady) {
      if (root.solarLoading) return "Finding sunrise and sunset…"
      if (root.solarError !== "") return "Solar schedule unavailable"
      return "Waiting for sunrise and sunset"
    }
    var state = root.scheduleState(now)
    if (!state.valid) return "Waiting for the next schedule boundary"
    var next = new Date(state.nextEpoch)
    var label = next.toLocaleTimeString(Qt.locale(), "h:mm AP")
    var nextLabel = state.nextMode === "light" ? "Light" : "Dark"
    return "Next: " + nextLabel + " at " + label
  }

  function solarLocationSummary() {
    if (!root.solarReady) return root.solarLoading ? "Detecting location…" : "Location unavailable"
    var suffix = root.solarLocationSource === "ip" ? " · auto-detected" : " · Weather location"
    return root.solarLocation + suffix
  }

  function solarTimesSummary() {
    var now = root.clockNow
    if (root.solarLoading && !root.solarReady) return "Loading solar times…"
    if (!root.solarReady) return root.solarError || "Could not load sunrise and sunset"
    return "Next · Sunrise " + root.formatEpoch(root.nextSolarEpoch("sunrise", now))
      + " · Sunset " + root.formatEpoch(root.nextSolarEpoch("sunset", now))
  }

  function solarNeedsRefresh(nowMs) {
    if (!root.usesSolarSchedule || root.solarLoading) return false
    var nowValue = nowMs === undefined ? Date.now() : nowMs
    if (!root.solarReady) return nowValue - root.solarLastAttemptAt >= 60000
    if (nowValue - root.solarLoadedAt >= 6 * 60 * 60 * 1000) return true
    for (var i = 0; i < root.solarEvents.length; i++)
      if (Number(root.solarEvents[i].epoch || 0) * 1000 > nowValue) return false
    return true
  }

  function requestSolarRefresh(force) {
    if (!root.usesSolarSchedule) return
    if (solarProcess.running) {
      root.solarRefreshQueued = true
      return
    }
    root.solarRefreshQueued = false
    root.solarReceived = false
    root.solarProcessError = ""
    root.solarError = ""
    root.solarLoading = true
    root.solarRequestGeneration = root.solarGeneration
    root.solarLastAttemptAt = Date.now()
    solarProcess.command = force === true
      ? [root.helperPath, "solar", "--refresh"]
      : [root.helperPath, "solar"]
    root.solarFinished = false
    solarWatchdog.restart()
    solarProcess.running = true
  }

  function invalidateSolar() {
    root.solarGeneration += 1
    root.solarReady = false
    root.solarEvents = []
    root.solarTodaySunrise = 0
    root.solarTodaySunset = 0
    root.lastScheduleToken = ""
    if (root.manualOverrideMode !== "")
      root.updateSettings({ manualOverrideMode: "", manualOverrideUntil: 0 })
    if (root.usesSolarSchedule) solarRequestDebounce.restart()
  }

  function consumeSolar(raw) {
    if (root.solarRequestGeneration !== root.solarGeneration) return
    try {
      var payload = JSON.parse(String(raw || ""))
      if (Number(payload.version) !== 1 || !Array.isArray(payload.events) || !payload.location)
        throw new Error("Unsupported solar response")
      var normalized = []
      for (var i = 0; i < payload.events.length; i++) {
        var event = payload.events[i]
        var epoch = Number(event && event.epoch || 0)
        var kind = String(event && event.event || "")
        if (epoch <= 0 || (kind !== "sunrise" && kind !== "sunset")) continue
        normalized.push({ event: kind, mode: kind === "sunrise" ? "light" : "dark", epoch: epoch })
      }
      if (normalized.length === 0) throw new Error("No solar boundaries")
      root.solarEvents = normalized
      root.solarLocation = String(payload.location.name || "Detected location")
      root.solarLocationSource = String(payload.location.source || "")
      root.solarTimezone = String(payload.timezone || "")
      root.solarTodaySunrise = Number(payload.today && payload.today.sunrise || 0)
      root.solarTodaySunset = Number(payload.today && payload.today.sunset || 0)
      root.solarLoadedAt = Date.now()
      root.solarReady = true
      root.solarReceived = true
      root.solarError = ""
      scheduleDebounce.restart()
    } catch (error) {
      root.solarProcessError = "Could not read sunrise and sunset data"
      console.warn("appearance: invalid solar response:", error)
    }
  }

  function openWeatherLocation() {
    if (weatherPanelProcess.running) return
    weatherPanelProcess.running = true
  }

  function rememberedModeWallpaper(mode) {
    return String(root.rememberedWallpapers["mode:" + mode] || "")
  }

  function rememberedThemeWallpaper(theme) {
    return String(root.rememberedWallpapers["theme:" + theme] || "")
  }

  function rememberCurrentWallpaper() {
    if (!root.ready || root.busy || root.currentBackground === "") return
    var next = {}
    for (var key in root.rememberedWallpapers) next[key] = root.rememberedWallpapers[key]
    var changed = false
    var modeKey = "mode:" + root.currentMode
    if (next[modeKey] !== root.currentBackground) {
      next[modeKey] = root.currentBackground
      changed = true
    }
    if (root.currentInThemePool && root.currentTheme !== "") {
      var themeKey = "theme:" + root.currentTheme
      if (next[themeKey] !== root.currentBackground) {
        next[themeKey] = root.currentBackground
        changed = true
      }
    }
    if (changed) root.updateSettings({ rememberedWallpapers: next })
  }

  function requestMode(mode, manual) {
    if (root.busy || !root.ready || (mode !== "light" && mode !== "dark")) return false
    var override = null
    if (manual === true && root.autoEnabled) {
      var boundary = root.nextBoundaryEpoch(Date.now())
      if (boundary <= Date.now()) boundary = Date.now() + 24 * 60 * 60 * 1000
      override = { manualOverrideMode: mode, manualOverrideUntil: Math.floor(boundary / 1000) }
    }
    return root.startTheme(mode, root.themeForMode(mode), false, { settingsPatch: override })
  }

  function toggleMode() {
    root.requestMode(root.currentMode === "light" ? "dark" : "light", true)
  }

  function startTheme(mode, explicitTheme, scheduled, options) {
    if (root.busy || !root.ready) return false
    var theme = String(explicitTheme || root.themeForMode(mode) || "")
    if (!theme) { root.lastError = "No " + mode + " theme is available"; return false }
    var extra = options || ({})
    if (root.currentMode === mode && root.currentTheme === theme) {
      if (extra.settingsPatch) root.updateSettings(extra.settingsPatch)
      root.lastError = ""
      return true
    }
    root.rememberCurrentWallpaper()
    var restore = root.currentMode === mode
      ? root.rememberedThemeWallpaper(theme) : root.rememberedModeWallpaper(mode)
    var command = [root.helperPath, "switch-theme", "--theme", theme]
    if (restore) command.push("--background", restore)
    return root.beginAction({
      kind: "theme", mode: mode, theme: theme, scheduled: scheduled === true,
      pairMode: extra.pairMode || "", navigationKind: extra.navigationKind || "",
      scheduleToken: scheduled === true ? root.lastScheduleToken : "",
      randomBag: extra.randomBag || [], settingsPatch: extra.settingsPatch || null
    }, command, "Switching to " + mode + "…")
  }

  function startWallpaperAction(status, command, navigationKind, target) {
    if (root.busy || !root.ready) return false
    return root.beginAction({kind: "wallpaper", navigationKind: navigationKind,
      poolKey: root.wallpaperPoolKey(), target: String(target || "")}, command, status)
  }

  function beginAction(details, command, status) {
    if (root.busy || actionProcess.running) return false
    var op = Object.assign({}, details, {
      id: String(Date.now()) + "-" + (++root.requestSequence), phase: "applying",
      fromTheme: root.currentTheme, fromMode: root.currentMode,
      fromBackground: root.currentBackground, visualCommitted: false,
      renderSerial: root.themeRenderSerial
    })
    root.stateGeneration += 1
    root.operation = op
    root.preparedSnapshot = null
    root.pendingCompletion = null
    root.actionStatus = status
    root.lastError = ""
    root.actionError = ""
    root.actionResult = null
    root.actionStarted = false
    root.actionFinished = false
    actionProcess.command = command.concat(["--request-id", op.id])
    actionWatchdog.restart()
    actionProcess.running = true
    return true
  }

  function previousWallpaper() {
    if (root.busy || !root.ready) return false
    var target = root.wallpaperRandomBackTarget(root.wallpaperPoolKey())
    if (target !== "") {
      return root.startWallpaperAction("Returning to previous wallpaper…",
        [root.helperPath, "set-wallpaper", target], "history-back", target)
    }
    return root.startWallpaperAction("Finding previous wallpaper…",
      [root.helperPath, "cycle", "--scope", root.wallpaperScope, "--direction", "previous"],
      "ordered", "")
  }

  function randomWallpaper() {
    if (root.busy || !root.ready) return false
    return root.startWallpaperAction("Choosing a random wallpaper…",
      [root.helperPath, "cycle", "--scope", root.wallpaperScope, "--direction", "random"],
      "random", "")
  }

  function cycleWallpaper(direction) {
    if (direction === "previous") return root.previousWallpaper()
    if (direction === "random") return root.randomWallpaper()
    return root.startWallpaperAction("Finding next wallpaper…",
      [root.helperPath, "cycle", "--scope", root.wallpaperScope, "--direction", "next"],
      "ordered", "")
  }

  function startWallpaperSelection(status, command, kind) {
    if (root.busy || !root.ready || selectionProcess.running || actionProcess.running) return false
    root.operation = {kind: "picker", selectionKind: kind, phase: "selecting"}
    root.actionStatus = status
    root.lastError = ""
    root.selectionOutput = ""
    root.selectionError = ""
    root.selectionFinished = false
    root.selectionStarted = false
    selectionProcess.command = command
    selectionProcess.running = true
    return true
  }

  function browseWallpapers() {
    return root.startWallpaperSelection("Opening wallpaper browser…",
      [root.helperPath, "browse", "--scope", root.wallpaperScope], "browse")
  }

  function choosePersonalWallpaper(importFile) {
    if (!root.ready || root.currentTheme === "") return false
    var shouldImport = importFile === undefined
      ? root.importPersonalWallpaper : importFile === true
    var command = [root.helperPath, "pick-file", "--theme", root.currentTheme]
    if (shouldImport) command.push("--import")
    return root.startWallpaperSelection(shouldImport
        ? "Choosing a wallpaper to add…" : "Choosing a wallpaper…",
      command, "file")
  }

  function finishWallpaperSelection(exitCode) {
    if (root.selectionFinished) return
    root.selectionFinished = true
    var kind = root.operation ? root.operation.selectionKind : "file"
    var raw = root.selectionOutput
    root.operation = null
    root.actionStatus = ""
    try {
      if (exitCode !== 0) throw new Error(root.selectionError ||
        (kind === "browse" ? "Wallpaper browser failed" : "Could not open the file chooser"))
      var payload = JSON.parse(raw)
      if (Number(payload.version) !== 1 || typeof payload.selected !== "boolean")
        throw new Error("Could not read wallpaper selection")
      if (payload.selected) {
        var path = String(payload.path || "")
        if (!path) throw new Error("Wallpaper selection did not include a path")
        if (!root.startWallpaperAction("Setting wallpaper…", [root.helperPath, "set-wallpaper", path], "select", path))
          throw new Error("Appearance state is unavailable; please try again")
        return
      }
    } catch (error) { root.lastError = String(error.message || error) }
    if (root.refreshQueued) root.refresh()
    scheduleDebounce.restart()
  }

  function finishAction(success) {
    var op = root.operation
    if (!op) return
    if (op.scheduled) {
      if (success) root.resetScheduleRetry()
      else {
        root.lastScheduleToken = ""
        root.scheduleFailureCount = root.scheduleFailureToken === op.scheduleToken
          ? root.scheduleFailureCount + 1 : 1
        root.scheduleFailureToken = op.scheduleToken
        root.scheduleRetryAt = Date.now() + Math.min(300000,
          30000 * Math.pow(2, Math.min(root.scheduleFailureCount - 1, 4)))
      }
    }
    if (success) {
      var patch = Object.assign({}, op.settingsPatch || ({}))
      if (op.kind === "theme") {
        root.commitPendingNavigation()
        if (op.pairMode === "light") patch.lightTheme = op.theme
        if (op.pairMode === "dark") patch.darkTheme = op.theme
      } else if (op.kind === "wallpaper") root.commitPendingWallpaperNavigation()
      if (Object.keys(patch).length) root.updateSettings(patch)
    } else if (op.kind === "wallpaper" && op.navigationKind === "history-back") {
      root.clearWallpaperRandomHistory(op.poolKey)
    }
    actionWatchdog.stop()
    visualFallback.stop()
    root.preparedSnapshot = null
    root.pendingCompletion = null
    root.operation = null
    root.actionStatus = ""
    root.stateGeneration += 1
    root.rememberCurrentWallpaper()
    // The adapter's final snapshot already includes its own filesystem events.
    // A fresh background probe is reserved for an explicitly queued refresh.
    root.refreshQueued = false
    scheduleDebounce.restart()
  }

  function receiveActionLine(line) {
    if (!root.operation || root.operation.phase !== "applying") return
    try {
      var payload = JSON.parse(String(line || ""))
      if (Number(payload.version) !== 1) throw new Error("Unsupported action response")
      if (payload.requestId && String(payload.requestId) !== root.operation.id) return
      if (payload.event === "applied") {
        if (payload.status) {
          root.prepareVisual(root.operation.id, JSON.stringify(payload.status))
          Qt.callLater(root.commitPreparedVisual)
        }
      } else root.actionResult = payload
    } catch (error) { root.actionError = "Could not read appearance change result" }
  }

  function actionExited(exitCode) {
    if (root.actionFinished) return
    root.actionFinished = true
    actionWatchdog.stop()
    var result = root.actionResult
    if (!result || !root.validSnapshot(result.status)) {
      root.recoverAction(root.actionError || "Appearance change did not return a confirmed state")
      return
    }
    var success = exitCode === 0 && result.ok === true
    if (success && root.operation.kind === "theme")
      success = result.status.current.theme === root.operation.theme
        && result.status.current.mode === root.operation.mode
    root.lastError = success ? (Array.isArray(result.warnings) ? result.warnings.join("\n") : String(result.warning || ""))
      : String(result.error || root.actionError || "Appearance change failed")
    if (success && root.operation.kind === "theme") {
      // Native IPC acceptance and helper completion can precede image decode.
      // Keep the verified result locked until the shell starts its reveal.
      root.operation = Object.assign({}, root.operation, {phase: "rendering"})
      root.pendingCompletion = {success: true}
      root.preparedSnapshot = result.status
      visualFallback.restart()
      root.commitPreparedVisual()
      return
    }
    root.applySnapshot(result.status)
    root.finishAction(success)
  }

  function recoverAction(message) {
    if (!root.operation) return
    root.lastError = String(message || "Appearance change failed")
    root.operation = Object.assign({}, root.operation, {phase: actionProcess.running ? "stopping" : "verifying"})
    root.actionStatus = "Checking appearance…"
    root.preparedSnapshot = null
    root.pendingCompletion = null
    visualFallback.stop()
    if (actionProcess.running) { recoveryWatchdog.restart(); return }
    recoveryWatchdog.stop()
    root.refresh(true)
  }

  function prepareVisual(requestId, raw) {
    if (!root.operation || root.operation.kind === "picker"
        || String(root.operation.id) !== String(requestId)) return "ignored"
    try {
      var candidate = JSON.parse(String(raw || ""))
      if (!root.validSnapshot(candidate)) return "invalid"
      root.preparedSnapshot = candidate
      visualFallback.restart()
      return "ready"
    } catch (error) { return "invalid" }
  }

  function commitPreparedVisual(force) {
    if (!root.preparedSnapshot || !root.operation) return
    var palette = root.preparedSnapshot.palette || []
    if (root.operation.kind === "theme" && force !== true) {
      if (root.themeRenderSerial <= root.operation.renderSerial) return
      for (var i = 0; i < palette.length; i++) {
        var entry = palette[i]
        if (entry.role === "foreground" && !Qt.colorEqual(entry.color, Color.foreground)) return
        if (entry.role === "background" && !Qt.colorEqual(entry.color, Color.background)) return
        if (entry.role === "accent" && !Qt.colorEqual(entry.color, Color.accent)) return
      }
    }
    root.applySnapshot(root.preparedSnapshot)
    root.operation = Object.assign({}, root.operation, {visualCommitted: true})
    root.preparedSnapshot = null
    visualFallback.stop()
    root.actionStatus = "Finishing application updates…"
    if (root.pendingCompletion) root.finishAction(root.pendingCompletion.success)
  }

  function refresh(recovery) {
    if (root.busy && root.operation.phase !== "selecting" && recovery !== true) {
      root.refreshQueued = true
      return
    }
    if (statusProcess.running) { root.refreshQueued = true; return }
    root.refreshQueued = false
    root.statusReceived = false
    root.statusFinished = false
    root.statusError = ""
    root.statusGeneration = root.stateGeneration
    statusWatchdog.restart()
    statusProcess.running = true
  }

  function applyThemePalette(candidate) {
    if (!Array.isArray(candidate) || candidate.length !== 9) return false

    var normalized = []
    for (var i = 0; i < candidate.length; i++) {
      var entry = candidate[i]
      if (!entry || typeof entry !== "object") return false
      var roleName = String(entry.role || "")
      var label = String(entry.label || roleName)
      var value = String(entry.color || "")
      if (roleName === "" || value === "") return false
      normalized.push({ roleName: roleName, label: label, value: value })
    }

    var structureChanged = themePaletteModel.count !== normalized.length
    if (!structureChanged) {
      for (var row = 0; row < normalized.length; row++) {
        if (String(themePaletteModel.get(row).roleName || "") !== normalized[row].roleName) {
          structureChanged = true
          break
        }
      }
    }

    if (structureChanged) {
      themePaletteModel.clear()
      for (var appendIndex = 0; appendIndex < normalized.length; appendIndex++)
        themePaletteModel.append(normalized[appendIndex])
      return true
    }

    // Preserve the model rows so Repeater delegates never disappear. A
    // wallpaper-only refresh usually changes nothing; a theme refresh updates
    // just the role values, synchronously, before the next rendered frame.
    for (var updateIndex = 0; updateIndex < normalized.length; updateIndex++) {
      var current = themePaletteModel.get(updateIndex)
      var next = normalized[updateIndex]
      if (String(current.label || "") !== next.label)
        themePaletteModel.setProperty(updateIndex, "label", next.label)
      if (String(current.value || "") !== next.value)
        themePaletteModel.setProperty(updateIndex, "value", next.value)
    }
    return true
  }

  function consumeStatus(raw) {
    // Ignore inventories that started before an operation changed the desktop.
    if (root.statusGeneration !== root.stateGeneration) return
    if (root.busy && root.operation.phase !== "verifying" && root.operation.phase !== "selecting") return
    try {
      var payload = JSON.parse(String(raw || ""))
      if (!root.applySnapshot(payload)) throw new Error("Unsupported inventory response")
      root.statusReceived = true
      if (!root.busy) root.rememberCurrentWallpaper()
    } catch (error) { root.statusError = "Could not read appearance state" }
  }

  function validSnapshot(payload) {
    return payload && Number(payload.version) === 1 && payload.current
      && Array.isArray(payload.themes) && payload.pools
  }

  function applySnapshot(payload) {
    if (!root.validSnapshot(payload)) return false
    // One synchronous commit for labels, counts, mode and swatches. Reuse the
    // palette delegates; the renderer sees the complete snapshot next frame.
    if (!root.applyThemePalette(payload.palette)) themePaletteModel.clear()
    root.snapshot = payload
    root.ready = true
    return true
  }

  function statusExited(exitCode) {
    if (root.statusFinished) return
    root.statusFinished = true
    statusWatchdog.stop()
    if (!root.statusReceived && root.statusGeneration === root.stateGeneration) {
      root.lastError = root.statusError || "Could not refresh appearance state"
      root.ready = false
    }
    if (root.operation && root.operation.phase === "verifying") {
      if (root.statusGeneration !== root.stateGeneration) root.refresh(true)
      else root.finishAction(false)
      return
    }
    if (root.refreshQueued) Qt.callLater(function() { root.refresh() })
    else scheduleDebounce.restart()
  }

  function resetScheduleRetry() {
    root.scheduleFailureToken = ""
    root.scheduleFailureCount = 0
    root.scheduleRetryAt = 0
  }

  function checkSchedule() {
    if (!root.autoEnabled || !root.ready || root.themeNavigationBusy) return
    if (root.solarNeedsRefresh(Date.now())) root.requestSolarRefresh(false)
    var state = root.scheduleState(Date.now())
    if (!state.valid) return
    if (state.token === root.lastScheduleToken) return
    if (state.token === root.scheduleFailureToken && Date.now() < root.scheduleRetryAt) return
    var theme = root.themeForMode(state.mode)
    if (theme === "") return
    root.lastScheduleToken = state.token
    if (root.currentMode === state.mode && root.currentTheme === theme) return
    root.startTheme(state.mode, theme, true)
  }

  Process {
    id: statusProcess
    command: [root.helperPath, "status"]
    stdout: StdioCollector { waitForEnd: true; onStreamFinished: root.consumeStatus(text) }
    stderr: StdioCollector { waitForEnd: true; onStreamFinished: root.statusError = String(text || "").trim() }
    onExited: function(exitCode) { root.statusExited(exitCode) }
    onRunningChanged: if (!running) Qt.callLater(function() {
      if (!statusProcess.running && !root.statusFinished) root.statusExited(-1)
    })
  }

  Process {
    id: solarProcess
    stdout: StdioCollector { waitForEnd: true; onStreamFinished: root.consumeSolar(text) }
    stderr: StdioCollector { waitForEnd: true; onStreamFinished: root.solarProcessError = String(text || "").trim() }
    onExited: function(exitCode) { root.solarExited() }
    onRunningChanged: if (!running) Qt.callLater(function() {
      if (!solarProcess.running && !root.solarFinished) root.solarExited()
    })
  }

  function solarExited() {
    if (root.solarFinished) return
    root.solarFinished = true
    solarWatchdog.stop()
    root.solarLoading = false
    if (root.solarRequestGeneration !== root.solarGeneration) {
      Qt.callLater(function() { root.requestSolarRefresh(false) })
      return
    }
    if (!root.solarReceived) {
      root.solarReady = false
      root.solarError = root.solarProcessError || "Could not update sunrise and sunset"
    }
    if (root.solarRefreshQueued) Qt.callLater(function() { root.requestSolarRefresh(false) })
    else scheduleDebounce.restart()
  }

  Process {
    id: weatherPanelProcess
    command: ["omarchy-shell", "shell", "toggle", "omarchy.weather", "{}"]
  }

  Process {
    id: actionProcess
    stdout: SplitParser { onRead: function(data) { root.receiveActionLine(data) } }
    stderr: StdioCollector { waitForEnd: true; onStreamFinished: root.actionError = String(text || "").trim() }
    onStarted: root.actionStarted = true
    onExited: function(exitCode) { root.actionExited(exitCode) }
    onRunningChanged: if (!running) Qt.callLater(function() {
      if (!actionProcess.running && root.operation && root.operation.phase === "stopping") {
        root.recoverAction(root.lastError)
        return
      }
      if (!actionProcess.running && !root.actionFinished && root.operation) {
        root.actionFinished = true
        root.recoverAction(root.actionStarted ? "Appearance command stopped unexpectedly" : "Could not start appearance helper")
      }
    })
  }

  Process {
    id: selectionProcess
    stdout: StdioCollector { waitForEnd: true; onStreamFinished: root.selectionOutput = String(text || "").trim() }
    stderr: StdioCollector { waitForEnd: true; onStreamFinished: root.selectionError = String(text || "").trim() }
    onStarted: root.selectionStarted = true
    onExited: function(exitCode) { root.finishWallpaperSelection(exitCode) }
    onRunningChanged: if (!running) Qt.callLater(function() {
      if (!selectionProcess.running && !root.selectionFinished) root.finishWallpaperSelection(-1)
    })
  }

  Connections {
    target: Color
    function onShellValuesChanged() {
      // loadShell assigns a fresh object at native reveal, even when two
      // themes share exactly the same foundational colors.
      root.themeRenderSerial += 1
      Qt.callLater(root.commitPreparedVisual)
    }
    function onForegroundChanged() { Qt.callLater(root.commitPreparedVisual) }
    function onBackgroundChanged() { Qt.callLater(root.commitPreparedVisual) }
    function onAccentChanged() { Qt.callLater(root.commitPreparedVisual) }
  }

  FileView {
    path: root.statePath
    watchChanges: true
    printErrors: false
    onFileChanged: refreshDebounce.restart()
  }

  FileView {
    path: root.userThemesPath
    watchChanges: true
    printErrors: false
    onFileChanged: refreshDebounce.restart()
  }

  FileView {
    path: root.userBackgroundsPath
    watchChanges: true
    printErrors: false
    onFileChanged: refreshDebounce.restart()
  }

  FileView {
    path: root.weatherLocationPath
    watchChanges: true
    printErrors: false
    onFileChanged: {
      reload()
      root.invalidateSolar()
    }
    onLoadFailed: if (root.solarReady && root.solarLocationSource !== "ip") root.invalidateSolar()
  }

  Timer {
    id: refreshDebounce
    interval: 250
    onTriggered: root.refresh()
  }

  Timer {
    id: statusWatchdog
    interval: 10000
    onTriggered: {
      root.statusError = "Appearance inventory timed out"
      if (statusProcess.running) statusProcess.signal(9)
      else root.statusExited(-1)
    }
  }

  Timer {
    id: actionWatchdog
    interval: 75000
    onTriggered: {
      root.actionFinished = true
      actionProcess.signal(15)
      root.recoverAction("Appearance change timed out")
    }
  }

  Timer {
    id: solarWatchdog
    interval: 25000
    onTriggered: {
      root.solarProcessError = "Solar lookup timed out"
      if (solarProcess.running) solarProcess.signal(9)
      else root.solarExited()
    }
  }

  Timer {
    id: recoveryWatchdog
    interval: 3000
    onTriggered: {
      if (actionProcess.running) actionProcess.signal(9)
      else root.recoverAction(root.lastError)
    }
  }

  Timer {
    id: visualFallback
    interval: 1200
    onTriggered: {
      // Final adapter verification remains authoritative if the shell cannot
      // expose a matching palette (for example an invalid third-party theme).
      if (root.pendingCompletion) root.commitPreparedVisual(true)
      else root.preparedSnapshot = null
    }
  }

  Timer {
    id: scheduleDebounce
    interval: 350
    onTriggered: root.checkSchedule()
  }

  Timer {
    id: solarRequestDebounce
    interval: 350
    onTriggered: root.requestSolarRefresh(false)
  }

  Timer {
    interval: 30000
    running: true
    repeat: true
    triggeredOnStart: true
    onTriggered: {
      root.clockNow = Date.now()
      if (!root.ready) root.refresh()
      else {
        if (root.solarNeedsRefresh(Date.now())) root.requestSolarRefresh(false)
        root.checkSchedule()
      }
    }
  }

  Component.onCompleted: {
    root.refresh()
    if (root.usesSolarSchedule) solarRequestDebounce.restart()
  }

  IpcHandler {
    target: "appearance"

    function prepareVisual(requestId: string, payload: string): string {
      return root.prepareVisual(requestId, payload)
    }

    function status(): string {
      return JSON.stringify({
        ready: root.ready,
        busy: root.busy,
        phase: root.operation ? root.operation.phase : "idle",
        visualCommitted: root.operation ? root.operation.visualCommitted === true : false,
        mode: root.currentMode,
        theme: root.currentTheme,
        background: root.currentBackground,
        scope: root.wallpaperScope,
        automatic: root.autoEnabled,
        lightStart: root.lightStart,
        darkStart: root.darkStart,
        solarReady: root.solarReady,
        solarLocation: root.solarLocation,
        error: root.lastError
      })
    }
    function refresh(): string { root.refresh(); return "ok" }
    function toggle(): string { root.toggleMode(); return "ok" }
    function light(): string { root.requestMode("light", true); return "ok" }
    function dark(): string { root.requestMode("dark", true); return "ok" }
    function next(): string { root.cycleWallpaper("next"); return "ok" }
    function previous(): string { root.cycleWallpaper("previous"); return "ok" }
    function randomWallpaper(): string {
      return root.randomWallpaper() ? "ok" : (root.lastError || "unavailable")
    }
    function nextTheme(): string { root.cycleTheme("next"); return "ok" }
    function previousTheme(): string { root.previousTheme(); return "ok" }
    function randomTheme(): string {
      return root.randomTheme() ? "ok" : (root.lastError || "unavailable")
    }
  }
}
