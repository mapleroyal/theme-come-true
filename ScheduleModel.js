// Pure schedule calculations. nowMs and returned epochs use milliseconds;
// persisted manualOverrideUntil and solar API event epochs use seconds.
function validTime(value) {
  return /^([01][0-9]|2[0-3]):[0-5][0-9]$/.test(String(value || ""))
}

function normalizedBoundary(kind, value) {
  if (kind === "light" && value === "sunrise") return "sunrise"
  if (kind === "dark" && value === "sunset") return "sunset"
  if (validTime(value)) return value
  return kind === "light" ? "07:00" : "19:00"
}

function parseMinutes(value) {
  if (!validTime(value)) return 0
  var parts = String(value).split(":")
  return Number(parts[0]) * 60 + Number(parts[1])
}

function fixedBoundaryEvents(mode, value, nowMs) {
  var now = new Date(nowMs)
  var minutes = parseMinutes(value)
  var result = []
  // Construct each local calendar day independently: adjacent boundaries can
  // be 23 or 25 hours apart when daylight saving time changes.
  for (var offset = -1; offset <= 2; offset++) {
    var candidate = new Date(now.getFullYear(), now.getMonth(), now.getDate() + offset,
      Math.floor(minutes / 60), minutes % 60, 0, 0)
    result.push({ mode: mode, event: "time", epoch: candidate.getTime() })
  }
  return result
}

function boundaryEvents(lightStart, darkStart, solarEvents, nowMs) {
  var result = []
  var solar = Array.isArray(solarEvents) ? solarEvents : []
  var boundaries = [
    { mode: "light", value: lightStart, solar: "sunrise" },
    { mode: "dark", value: darkStart, solar: "sunset" }
  ]
  for (var b = 0; b < boundaries.length; b++) {
    var boundary = boundaries[b]
    if (boundary.value !== boundary.solar) {
      result = result.concat(fixedBoundaryEvents(boundary.mode, boundary.value, nowMs))
      continue
    }
    for (var i = 0; i < solar.length; i++) {
      var event = solar[i]
      var epoch = Number(event && event.epoch) * 1000
      if (event && event.event === boundary.solar && isFinite(epoch) && epoch > 0)
        result.push({ mode: boundary.mode, event: boundary.solar, epoch: epoch })
    }
  }
  // When two boundaries coincide, dark follows light, matching the previous
  // light-then-dark insertion order independently of the engine's sort.
  result.sort(function(a, b) {
    return a.epoch - b.epoch || (a.mode === b.mode ? 0 : a.mode === "light" ? -1 : 1)
  })
  return result
}

function scheduleState(settings, nowMs) {
  var currentMode = settings.currentMode === "light" ? "light" : "dark"
  var overrideUntil = Number(settings.manualOverrideUntil || 0)
  var overrideMode = settings.manualOverrideMode
  if (overrideUntil * 1000 > nowMs && (overrideMode === "light" || overrideMode === "dark")) {
    return {
      valid: true, mode: overrideMode, nextEpoch: overrideUntil * 1000,
      nextMode: "", nextEvent: "override",
      token: "override:" + overrideMode + ":" + overrideUntil
    }
  }

  var lightStart = normalizedBoundary("light", settings.lightStart)
  var darkStart = normalizedBoundary("dark", settings.darkStart)
  var usesSolar = lightStart === "sunrise" || darkStart === "sunset"
  if (usesSolar && !settings.solarReady)
    return { valid: false, mode: currentMode, nextEpoch: 0, token: "solar:waiting" }

  // Identical fixed times intentionally preserve the current mode.
  if (!usesSolar && lightStart === darkStart) {
    var equalEvents = fixedBoundaryEvents(currentMode, lightStart, nowMs)
    var equalNext = 0
    for (var e = 0; e < equalEvents.length; e++) {
      if (equalEvents[e].epoch > nowMs && (equalNext === 0 || equalEvents[e].epoch < equalNext))
        equalNext = equalEvents[e].epoch
    }
    return {
      valid: equalNext > 0, mode: currentMode, nextEpoch: equalNext,
      nextMode: currentMode, nextEvent: "time", token: "equal:" + currentMode + ":" + equalNext
    }
  }

  var events = boundaryEvents(lightStart, darkStart, settings.solarEvents, nowMs)
  var previous = null
  var next = null
  for (var i = 0; i < events.length; i++) {
    if (events[i].epoch <= nowMs) previous = events[i]
    else if (!next) next = events[i]
  }
  if (!previous || !next)
    return { valid: false, mode: currentMode, nextEpoch: 0, token: "schedule:incomplete" }
  return {
    valid: true, mode: previous.mode, nextEpoch: next.epoch,
    nextMode: next.mode, nextEvent: next.event,
    token: "schedule:" + previous.mode + ":" + next.epoch
  }
}
