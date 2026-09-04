import QtQuick
import Quickshell
import "." as Appearance
import "ScheduleModel.js" as Schedule
import "NavigationModel.js" as Navigation

ShellRoot {
  id: root
  property string displayTheme: "a"
  property string scheduleTime: "07:00"
  property string requestedTheme: ""
  property bool acceptImmediately: false

  Item {
    Appearance.BoundDropdown {
      id: theme
      modelValue: root.displayTheme
      options: ["a", "b", "c"]
      onSelectionRequested: function(selection) {
        root.requestedTheme = selection
        if (root.acceptImmediately) root.displayTheme = selection
      }
    }
    Appearance.BoundDropdown {
      id: schedule
      modelValue: root.scheduleTime
      options: ["sunrise", "07:00", "08:00"]
      onSelectionRequested: function(selection) { root.scheduleTime = selection }
    }
  }

  function assertEqual(actual, expected, message) {
    if (actual !== expected) throw new Error(message + ": expected " + expected + ", got " + actual)
  }

  function selector(node) {
    if (typeof node.selectCurrent === "function") return node
    var groups = []
    if (node.children) groups.push(node.children)
    if (node.data) groups.push(node.data)
    if (node.contentItem) groups.push([node.contentItem])
    for (var group of groups) {
      for (var child of group) {
        if (!child || child === node) continue
        var result = selector(child)
        if (result) return result
      }
    }
    return null
  }

  function select(control, index) {
    var list = selector(control)
    if (!list) throw new Error("Installed Dropdown selection contract changed")
    list.currentIndex = index
    list.selectCurrent()
  }

  Timer {
    running: true
    interval: 100
    onTriggered: {
      try {
        root.assertEqual(theme.value, "a", "Initial theme")
        root.select(theme, 1)
        root.assertEqual(root.requestedTheme, "b", "Selection intent")
        root.assertEqual(theme.value, "a", "Uncommitted or rejected selection stays authoritative")
        root.displayTheme = "b"
        root.assertEqual(theme.value, "b", "Delayed visual commit")
        root.displayTheme = "c"
        root.assertEqual(theme.value, "c", "Subsequent Next/Randomize keeps the binding")
        root.acceptImmediately = true
        root.select(theme, 0)
        root.assertEqual(theme.value, "a", "Synchronous acceptance")
        root.displayTheme = "c"
        root.assertEqual(theme.value, "c", "Binding after another selection")
        root.select(schedule, 0)
        root.assertEqual(schedule.value, "sunrise", "Schedule selection")
        root.scheduleTime = "08:00"
        root.assertEqual(schedule.value, "08:00", "External schedule setting update")
        root.assertEqual(Navigation.nextValue(["a", "b"], "b", "next"), "a", "QML model import")
        var spring = Schedule.fixedBoundaryEvents("light", "07:00", new Date("2026-03-08T12:00:00-05:00").getTime())
        root.assertEqual(spring[1].epoch - spring[0].epoch, 23 * 3600000, "Qt calendar DST behavior")
        console.log("appearance-ui-tests: PASS")
      } catch (error) {
        console.error("appearance-ui-tests: FAIL", error)
      }
      Qt.quit()
    }
  }
}
