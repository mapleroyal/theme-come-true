// Pure navigation decisions; callers commit a returned history/bag only after
// the corresponding desktop action succeeds. Values can be theme ids or paths.
function optionValues(options) {
  var result = []
  var source = Array.isArray(options) ? options : []
  for (var i = 0; i < source.length; i++) {
    var option = source[i]
    var value = String(option && typeof option === "object" ? option.value || "" : option || "")
    if (value !== "" && result.indexOf(value) < 0) result.push(value)
  }
  return result
}

function nextValue(options, current, direction) {
  var values = optionValues(options)
  if (values.length === 0 || (direction !== "next" && direction !== "previous")) return ""
  var index = values.indexOf(current)
  if (index < 0) return values[direction === "previous" ? values.length - 1 : 0]
  return values[(index + (direction === "previous" ? -1 : 1) + values.length) % values.length]
}

function backTarget(history, tip, current, availableValues) {
  var entries = Array.isArray(history) ? history.slice() : []
  if (tip !== current) return { history: [], tip: "", target: "", invalidated: true }
  var available = availableValues === undefined ? null : optionValues(availableValues)
  while (entries.length > 0) {
    var target = String(entries[entries.length - 1] || "")
    if (target !== "" && target !== current && (available === null || available.indexOf(target) >= 0))
      return { history: entries, tip: tip, target: target, invalidated: false }
    entries.pop()
  }
  return { history: [], tip: "", target: "", invalidated: false }
}

function commitHistory(history, tip, kind, from, to, limit) {
  var entries = Array.isArray(history) ? history.slice() : []
  if (kind === "random" || kind === "select") {
    if (to === "") return { history: [], tip: "" }
    if (tip !== "" && tip !== from) entries = []
    if (from !== "" && from !== to) entries.push(from)
    var cap = limit === undefined ? 32 : Math.max(0, Math.floor(Number(limit) || 0))
    entries = cap === 0 ? [] : entries.slice(-cap)
    return { history: entries, tip: to }
  }
  if (kind === "history-back" && to !== "" && tip === from && entries.length > 0
      && String(entries[entries.length - 1]) === to) {
    entries.pop()
    return { history: entries, tip: to }
  }
  return { history: [], tip: "" }
}

function recentValues(history, current, limit) {
  var entries = Array.isArray(history) ? history : []
  var result = current === "" ? [] : [current]
  var count = 0
  for (var i = entries.length - 1; i >= 0 && count < limit; i--) {
    var value = String(entries[i] || "")
    if (value !== "" && result.indexOf(value) < 0) {
      result.push(value)
      count++
    }
  }
  return result
}

function chooseRandom(options, current, storedBag, history, randomValue) {
  var values = optionValues(options)
  var stored = optionValues(storedBag)
  var bag = []
  for (var b = 0; b < stored.length; b++) {
    if (stored[b] !== current && values.indexOf(stored[b]) >= 0) bag.push(stored[b])
  }
  if (bag.length === 0) {
    for (var i = 0; i < values.length; i++) {
      if (values.length === 1 || values[i] !== current) bag.push(values[i])
    }
  }
  if (bag.length === 0) return { target: "", bag: [] }
  var recent = recentValues(history, current, 3)
  var candidates = []
  for (var c = 0; c < bag.length; c++) {
    if (recent.indexOf(bag[c]) < 0) candidates.push(c)
  }
  if (candidates.length === 0) {
    for (var fallback = 0; fallback < bag.length; fallback++) candidates.push(fallback)
  }
  var random = Number(randomValue)
  if (!isFinite(random)) random = 0
  random = Math.max(0, Math.min(1, random))
  var index = candidates[Math.min(candidates.length - 1, Math.floor(random * candidates.length))]
  var target = bag[index]
  bag.splice(index, 1)
  return { target: target, bag: bag }
}
