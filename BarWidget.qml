pragma ComponentBehavior: Bound

import QtQuick
import QtQuick.Controls
import QtQuick.Effects
import Quickshell
import qs.Commons
import qs.Ui

Panel {
  id: root
  moduleName: "io.github.mapleroyal.theme-come-true"
  manageIpc: false

  readonly property var appearance: bar && bar.shell ? bar.shell.serviceFor(moduleName) : null
  readonly property string mode: appearance ? appearance.currentMode : "dark"
  readonly property color foreground: bar ? bar.foreground : Color.foreground
  readonly property color dim: Qt.darker(foreground, 1.5)
  readonly property color urgent: bar ? bar.urgent : Color.urgent
  readonly property string fontFamily: bar ? bar.fontFamily : Style.font.family
  readonly property url lightModeIconSource: Qt.resolvedUrl("assets/icons/sun.svg")
  readonly property url darkModeIconSource: Qt.resolvedUrl("assets/icons/full-moon.svg")

  function requestMode(mode) {
    if (appearance) appearance.requestMode(mode, true)
  }

  function cycleWallpaper(direction) {
    if (appearance) appearance.cycleWallpaper(direction)
  }

  function randomWallpaper() {
    if (appearance) appearance.randomWallpaper()
  }

  function browseWallpapers() {
    var service = appearance
    if (!service) return
    root.close()
    service.browseWallpapers()
  }

  function choosePersonalWallpaper() {
    var service = appearance
    if (!service) return
    var importFile = service.importPersonalWallpaper
    root.close()
    service.choosePersonalWallpaper(importFile)
  }

  function cycleTheme(direction) {
    if (appearance) appearance.cycleTheme(direction)
  }

  function previousTheme() {
    if (appearance) appearance.previousTheme()
  }

  function randomTheme() {
    if (appearance) appearance.randomTheme()
  }

  implicitWidth: button.implicitWidth
  implicitHeight: button.implicitHeight

  onOpenedChanged: if (opened && appearance) {
    Style.scheduleRefresh()
    appearance.refresh()
    Qt.callLater(function() { modeButtons.forceActiveFocus() })
  }

  BarIconButton {
    id: button
    anchors.fill: parent
    bar: root.bar
    iconComponent: Component {
      TintedSvgIcon {
        iconSize: Style.bar.iconCanvas
        source: root.mode === "light" ? root.lightModeIconSource : root.darkModeIconSource
        color: button.foreground
      }
    }
    dimmed: !root.appearance || root.appearance.busy
    active: root.opened
    useActiveColor: false
    tooltipText: root.appearance
      ? "Theme Come True · " + (root.mode === "light" ? "Light" : "Dark")
          + " · Right-click toggles · Middle-click cycles wallpaper"
      : "Theme Come True"

    onPressed: function(mouseButton) {
      if (!root.appearance) return
      if (mouseButton === Qt.RightButton) root.appearance.toggleMode()
      else if (mouseButton === Qt.MiddleButton) root.cycleWallpaper("next")
      else root.toggle()
    }
  }

  KeyboardPanel {
    id: panel
    anchorItem: button
    owner: root
    bar: root.bar
    open: root.opened
    focusTarget: modeButtons
    contentWidth: panel.fittedContentWidth(Style.space(390))
    readonly property real footerHeight: statusFooter.height + (statusFooter.visible ? Style.space(8) : 0)
    contentHeight: panel.fittedContentHeight(contentColumn.implicitHeight + footerHeight,
      Style.space(690) + footerHeight)

    FocusScope {
      anchors.fill: parent

      Keys.priority: Keys.AfterItem
      Keys.onPressed: function(event) {
        if (event.key === Qt.Key_Escape) {
          root.close()
          event.accepted = true
        }
      }

      Flickable {
        id: panelScroll
        anchors.top: parent.top
        anchors.left: parent.left
        anchors.right: parent.right
        anchors.bottom: statusFooter.top
        anchors.bottomMargin: statusFooter.visible ? Style.space(8) : 0
        contentWidth: width
        contentHeight: contentColumn.implicitHeight
        clip: true
        boundsBehavior: Flickable.StopAtBounds
        flickableDirection: Flickable.VerticalFlick
        interactive: contentHeight > height
        ScrollBar.vertical: ScrollBar { policy: ScrollBar.AsNeeded }

        Column {
          id: contentColumn
          width: panelScroll.width
          spacing: Style.space(8)

          PanelHero {
            width: parent.width
            title: "Theme Come True"
            meta: root.appearance
              ? root.appearance.currentThemeLabel + " · " + root.mode
              : "Loading appearance"
            detail: root.appearance && root.appearance.autoEnabled ? "AUTO" : "MANUAL"
            foreground: root.foreground
            fontFamily: root.fontFamily
            iconComponent: Component {
              TintedSvgIcon {
                iconSize: Style.font.display
                source: root.mode === "light" ? root.lightModeIconSource : root.darkModeIconSource
                color: root.foreground
              }
            }
          }

          Row {
            id: modeButtons
            anchors.horizontalCenter: parent.horizontalCenter
            spacing: Style.spacing.md
            enabled: root.appearance && root.appearance.ready && !root.appearance.themeNavigationBusy

            property int cursorIndex: root.mode === "light" ? 0 : 1
            readonly property real optionWidth: Math.max(lightModeButton.implicitWidth, darkModeButton.implicitWidth)

            activeFocusOnTab: true

            function activate(index) {
              cursorIndex = index
              var nextMode = index === 0 ? "light" : "dark"
              if (nextMode !== root.mode) root.requestMode(nextMode)
            }

            onActiveFocusChanged: if (activeFocus)
              cursorIndex = root.mode === "light" ? 0 : 1

            Keys.priority: Keys.BeforeItem
            Keys.onPressed: function(event) {
              if (event.key === Qt.Key_Left || event.key === Qt.Key_H || event.text === "h") {
                cursorIndex = Math.max(0, cursorIndex - 1)
                event.accepted = true
              } else if (event.key === Qt.Key_Right || event.key === Qt.Key_L || event.text === "l") {
                cursorIndex = Math.min(1, cursorIndex + 1)
                event.accepted = true
              } else if (event.key === Qt.Key_Return || event.key === Qt.Key_Enter || event.key === Qt.Key_Space) {
                activate(cursorIndex)
                event.accepted = true
              }
            }

            ModeButton {
              id: lightModeButton
              width: modeButtons.optionWidth
              label: "Light"
              iconSource: root.lightModeIconSource
              selected: root.mode === "light"
              hasCursor: modeButtons.activeFocus && modeButtons.cursorIndex === 0
              focusable: false
              foreground: root.foreground
              background: Color.popups.background
              fontFamily: root.fontFamily
              onClicked: {
                modeButtons.forceActiveFocus()
                modeButtons.activate(0)
              }
            }

            ModeButton {
              id: darkModeButton
              width: modeButtons.optionWidth
              label: "Dark"
              iconSource: root.darkModeIconSource
              selected: root.mode === "dark"
              hasCursor: modeButtons.activeFocus && modeButtons.cursorIndex === 1
              focusable: false
              foreground: root.foreground
              background: Color.popups.background
              fontFamily: root.fontFamily
              onClicked: {
                modeButtons.forceActiveFocus()
                modeButtons.activate(1)
              }
            }
          }

          Item {
            id: paletteStrip
            width: parent.width
            implicitHeight: paletteSwatches.implicitHeight
            visible: root.appearance && root.appearance.themePaletteCount === 9

            Row {
              id: paletteSwatches
              anchors.horizontalCenter: parent.horizontalCenter
              spacing: Math.min(Style.space(6),
                Math.max(0, (paletteStrip.width - Style.space(12) * 9) / 8))
              readonly property real swatchSize: Math.min(Style.space(20),
                Math.max(1, (paletteStrip.width - spacing * 8) / 9))

              Repeater {
                model: root.appearance ? root.appearance.themePaletteModel : null

                delegate: Rectangle {
                  id: swatch
                  required property string roleName
                  required property string label
                  required property string value

                  readonly property color swatchColor: Style.colorFromHex(
                    value, "#000000")

                  width: paletteSwatches.swatchSize
                  height: width
                  radius: Style.cornerRadius > 0 ? width / 2 : 0
                  color: swatchColor
                  border.width: 1
                  border.color: Style.normalBorderFor(root.foreground, Color.accent, root.urgent)

                  Accessible.role: Accessible.Graphic
                  Accessible.name: label + " theme color, " + value

                  HoverHandler { id: swatchHover }

                  PanelToolTip {
                    visible: swatchHover.hovered
                    text: swatch.label + " · " + swatch.value
                    fontFamily: root.fontFamily
                  }
                }
              }
            }
          }

          PanelSeparator { foreground: root.foreground }

          PanelSectionHeader {
            text: "AUTOMATION"
            foreground: root.foreground
            fontFamily: root.fontFamily
          }

          Toggle {
            width: parent.width
            label: "Automatic switching"
            description: root.appearance ? root.appearance.scheduleSummary() : "Loading schedule"
            checked: root.appearance && root.appearance.autoEnabled
            enabled: root.appearance && root.appearance.ready && !root.appearance.busy
            foreground: root.foreground
            fontFamily: root.fontFamily
            onClicked: if (root.appearance) root.appearance.setAutomatic(!root.appearance.autoEnabled)
          }

          Row {
            visible: root.appearance && root.appearance.autoEnabled
            width: parent.width
            spacing: Style.space(8)

            BoundDropdown {
              width: (parent.width - parent.spacing) / 2
              label: "Light begins"
              modelValue: root.appearance ? root.appearance.lightStart : "07:00"
              options: root.appearance ? root.appearance.lightStartOptions : []
              enabled: root.appearance && !root.appearance.busy
              foreground: root.foreground
              fontFamily: root.fontFamily
              onSelectionRequested: function(value) {
                if (root.appearance) root.appearance.setScheduleTime("light", value)
              }
            }

            BoundDropdown {
              width: (parent.width - parent.spacing) / 2
              label: "Dark begins"
              modelValue: root.appearance ? root.appearance.darkStart : "19:00"
              options: root.appearance ? root.appearance.darkStartOptions : []
              enabled: root.appearance && !root.appearance.busy
              foreground: root.foreground
              fontFamily: root.fontFamily
              onSelectionRequested: function(value) {
                if (root.appearance) root.appearance.setScheduleTime("dark", value)
              }
            }
          }

          Row {
            id: solarStatusRow
            visible: root.appearance && root.appearance.autoEnabled
              && root.appearance.usesSolarSchedule
            width: parent.width
            spacing: Style.space(8)

            Column {
              width: Math.max(0, solarStatusRow.width - weatherButton.width - solarStatusRow.spacing)
              spacing: Style.space(3)

              Text {
                width: parent.width
                textFormat: Text.PlainText
                text: root.appearance ? root.appearance.solarLocationSummary() : "Detecting location…"
                color: root.foreground
                font.family: root.fontFamily
                font.pixelSize: Style.font.bodySmall
                elide: Text.ElideRight
              }

              Text {
                width: parent.width
                textFormat: Text.PlainText
                text: root.appearance ? root.appearance.solarTimesSummary() : "Loading solar times…"
                color: root.appearance && root.appearance.solarError !== "" ? root.urgent : root.dim
                font.family: root.fontFamily
                font.pixelSize: Style.font.caption
                wrapMode: Text.WordWrap
              }
            }

            Button {
              id: weatherButton
              width: Style.space(86)
              anchors.verticalCenter: parent.verticalCenter
              text: "Location"
              bordered: true
              focusable: true
              enabled: root.appearance && !root.appearance.busy
              foreground: root.foreground
              fontFamily: root.fontFamily
              onClicked: {
                root.close()
                root.appearance.openWeatherLocation()
              }
            }
          }

          PanelSeparator { foreground: root.foreground }

          PanelSectionHeader {
            text: "THEME PAIR"
            foreground: root.foreground
            fontFamily: root.fontFamily
          }

          Row {
            width: parent.width
            spacing: Style.space(8)

            BoundDropdown {
              width: (parent.width - parent.spacing) / 2
              label: "Light theme"
              modelValue: root.appearance ? root.appearance.displayLightTheme : ""
              options: root.appearance ? root.appearance.lightThemeOptions : []
              enabled: root.appearance && root.appearance.ready && !root.appearance.themeNavigationBusy
              foreground: root.foreground
              fontFamily: root.fontFamily
              onSelectionRequested: function(theme) {
                if (root.appearance) root.appearance.chooseTheme("light", theme)
              }
            }

            BoundDropdown {
              width: (parent.width - parent.spacing) / 2
              label: "Dark theme"
              modelValue: root.appearance ? root.appearance.displayDarkTheme : ""
              options: root.appearance ? root.appearance.darkThemeOptions : []
              enabled: root.appearance && root.appearance.ready && !root.appearance.themeNavigationBusy
              foreground: root.foreground
              fontFamily: root.fontFamily
              onSelectionRequested: function(theme) {
                if (root.appearance) root.appearance.chooseTheme("dark", theme)
              }
            }
          }

          Row {
            width: parent.width
            spacing: Style.space(8)

            Button {
              width: (parent.width - parent.spacing * 2) / 3
              text: "Previous"
              iconText: "←"
              tooltipText: "Previous " + root.mode + " theme"
              bordered: true
              focusable: true
              enabled: root.appearance && root.appearance.ready && !root.appearance.themeNavigationBusy
                && root.appearance.currentModeThemeCount > 1
              foreground: root.foreground
              fontFamily: root.fontFamily
              onClicked: root.previousTheme()
            }

            Button {
              width: (parent.width - parent.spacing * 2) / 3
              text: "Randomize"
              tooltipText: "Randomize " + (root.appearance ? root.appearance.currentModeThemeCount : 0)
                + " " + root.mode + " themes without repeats"
              bordered: true
              focusable: true
              enabled: root.appearance && root.appearance.ready && !root.appearance.themeNavigationBusy
                && root.appearance.currentModeThemeCount > 1
              foreground: root.foreground
              fontFamily: root.fontFamily
              onClicked: root.randomTheme()
            }

            Button {
              width: (parent.width - parent.spacing * 2) / 3
              text: "Next"
              iconText: "→"
              tooltipText: "Next " + root.mode + " theme"
              bordered: true
              focusable: true
              enabled: root.appearance && root.appearance.ready && !root.appearance.themeNavigationBusy
                && root.appearance.currentModeThemeCount > 1
              foreground: root.foreground
              fontFamily: root.fontFamily
              onClicked: root.cycleTheme("next")
            }
          }

          PanelSeparator { foreground: root.foreground }

          PanelSectionHeader {
            text: "WALLPAPER"
            foreground: root.foreground
            fontFamily: root.fontFamily
          }

          BorderSurface {
            id: previewCard
            width: parent.width
            height: Style.space(100)
            radius: Style.cornerRadius
            color: Style.normalFillFor(root.foreground, Color.accent)
            borderSpec: Border.controlSpec(activeFocus ? "focus"
              : previewMouse.containsMouse ? "hover-cursor" : "normal",
              root.foreground, Color.accent)

            activeFocusOnTab: previewMouse.enabled
            Accessible.role: Accessible.Button
            Accessible.name: "Browse wallpapers in the current pool"

            Keys.onReturnPressed: if (previewMouse.enabled) root.browseWallpapers()
            Keys.onEnterPressed: if (previewMouse.enabled) root.browseWallpapers()
            Keys.onSpacePressed: if (previewMouse.enabled) root.browseWallpapers()

            Item {
              id: previewContents
              anchors.fill: parent
              anchors.topMargin: previewCard.borderTop
              anchors.rightMargin: previewCard.borderRight
              anchors.bottomMargin: previewCard.borderBottom
              anchors.leftMargin: previewCard.borderLeft
              layer.enabled: true
              layer.smooth: true
              layer.effect: MultiEffect {
                maskEnabled: true
                maskSource: previewMask
                maskThresholdMin: 0.3
                maskSpreadAtMin: 0.3
              }

              Image {
                id: wallpaperPreview
                anchors.fill: parent
                source: root.appearance && root.appearance.currentBackground !== ""
                  ? Util.fileUrl(root.appearance.currentBackground) : ""
                fillMode: Image.PreserveAspectCrop
                sourceSize.width: Math.max(1, Math.ceil(width * Screen.devicePixelRatio))
                asynchronous: true
                retainWhileLoading: true
                cache: true
              }

              // Warm the same image-cache entry before the service commits a
              // staged desktop change. Keep the visible preview authoritative.
              Image {
                anchors.fill: parent
                visible: false
                source: root.appearance && root.appearance.previewBackground !== ""
                  ? Util.fileUrl(root.appearance.previewBackground) : ""
                fillMode: wallpaperPreview.fillMode
                sourceSize.width: wallpaperPreview.sourceSize.width
                asynchronous: true
                cache: true
              }

              Rectangle {
                anchors.left: parent.left
                anchors.right: parent.right
                anchors.bottom: parent.bottom
                height: wallpaperLabel.implicitHeight + Style.space(12)
                color: previewMouse.containsMouse
                  ? Qt.rgba(0, 0, 0, 0.74)
                  : Qt.rgba(0, 0, 0, 0.62)

                Text {
                  id: wallpaperLabel
                  anchors.left: parent.left
                  anchors.right: browseLabel.left
                  anchors.verticalCenter: parent.verticalCenter
                  anchors.leftMargin: Style.space(10)
                  anchors.rightMargin: Style.space(8)
                  textFormat: Text.PlainText
                  text: root.appearance ? root.appearance.currentBackgroundName : "Loading…"
                  color: "white"
                  font.family: root.fontFamily
                  font.pixelSize: Style.font.body
                  elide: Text.ElideRight
                }

                Text {
                  id: browseLabel
                  anchors.right: parent.right
                  anchors.verticalCenter: parent.verticalCenter
                  anchors.rightMargin: Style.space(10)
                  textFormat: Text.PlainText
                  text: "Browse "
                    + (root.appearance ? root.appearance.currentWallpaperPoolCount : 0)
                    + "  ›"
                  color: "white"
                  font.family: root.fontFamily
                  font.pixelSize: Style.font.bodySmall
                  font.bold: true
                }
              }
            }

            Rectangle {
              id: previewMask
              anchors.fill: previewContents
              radius: Math.max(0, previewCard.radius - Math.max(
                previewCard.borderTop,
                previewCard.borderRight,
                previewCard.borderBottom,
                previewCard.borderLeft))
              color: "white"
              antialiasing: true
              visible: false
              layer.enabled: true
            }

            MouseArea {
              id: previewMouse
              anchors.fill: parent
              enabled: root.appearance && root.appearance.ready && !root.appearance.busy
                && root.appearance.currentWallpaperPoolCount > 0
              hoverEnabled: true
              cursorShape: Qt.PointingHandCursor
              onClicked: {
                previewCard.forceActiveFocus()
                root.browseWallpapers()
              }
            }
          }

          Row {
            width: parent.width
            spacing: Style.space(8)

            Button {
              width: (parent.width - parent.spacing * 2) / 3
              text: "Previous"
              iconText: "←"
              tooltipText: "Previous wallpaper in the current pool"
              bordered: true
              focusable: true
              enabled: root.appearance && root.appearance.ready && !root.appearance.busy
              foreground: root.foreground
              fontFamily: root.fontFamily
              onClicked: root.cycleWallpaper("previous")
            }

            Button {
              width: (parent.width - parent.spacing * 2) / 3
              text: "Randomize"
              tooltipText: "Randomize "
                + (root.appearance ? root.appearance.currentWallpaperPoolCount : 0)
                + " wallpapers in the current pool"
              bordered: true
              focusable: true
              enabled: root.appearance && root.appearance.ready && !root.appearance.busy
                && root.appearance.canRandomizeWallpaper
              foreground: root.foreground
              fontFamily: root.fontFamily
              onClicked: root.randomWallpaper()
            }

            Button {
              width: (parent.width - parent.spacing * 2) / 3
              text: "Next"
              iconText: "→"
              tooltipText: "Next wallpaper in the current pool"
              bordered: true
              focusable: true
              enabled: root.appearance && root.appearance.ready && !root.appearance.busy
              foreground: root.foreground
              fontFamily: root.fontFamily
              onClicked: root.cycleWallpaper("next")
            }
          }

          Toggle {
            width: parent.width
            label: "All " + root.mode + " themes"
            description: root.appearance
              ? (root.appearance.wallpaperScope === "mode"
                  ? root.appearance.modeWallpaperCount + " wallpapers in the " + root.mode + " pool"
                  : root.appearance.themeWallpaperCount + " wallpapers in " + root.appearance.currentThemeLabel)
              : "Choose the wallpaper pool"
            checked: root.appearance && root.appearance.wallpaperScope === "mode"
            enabled: root.appearance && root.appearance.ready && !root.appearance.busy
            foreground: root.foreground
            fontFamily: root.fontFamily
            onClicked: if (root.appearance) root.appearance.setWallpaperScope(
              root.appearance.wallpaperScope === "mode" ? "theme" : "mode")
          }

          Row {
            id: personalWallpaperRow
            width: parent.width
            spacing: Style.space(8)

            Button {
              id: chooseFileButton
              width: Math.min(parent.width * 0.42, Style.space(148))
              text: "Choose file…"
              tooltipText: root.appearance && root.appearance.importPersonalWallpaper
                ? "Choose an image and add a durable copy to the current theme"
                : "Choose an image and use it from its current location"
              bordered: true
              focusable: true
              enabled: root.appearance && root.appearance.ready && !root.appearance.busy
              foreground: root.foreground
              fontFamily: root.fontFamily
              onClicked: root.choosePersonalWallpaper()
            }

            Item {
              id: importChoice
              width: Math.max(0, personalWallpaperRow.width - chooseFileButton.width
                - personalWallpaperRow.spacing)
              height: chooseFileButton.implicitHeight
              enabled: root.appearance && root.appearance.ready && !root.appearance.busy
              activeFocusOnTab: enabled

              Accessible.role: Accessible.CheckBox
              Accessible.name: "Add personal wallpaper to current theme"
              Accessible.checked: root.appearance && root.appearance.importPersonalWallpaper

              function toggleImport() {
                if (enabled && root.appearance) root.appearance.setImportPersonalWallpaper(
                  !root.appearance.importPersonalWallpaper)
              }

              Keys.onReturnPressed: toggleImport()
              Keys.onEnterPressed: toggleImport()
              Keys.onSpacePressed: toggleImport()

              MouseArea {
                anchors.left: parent.left
                anchors.top: parent.top
                anchors.bottom: parent.bottom
                anchors.right: importPersonalToggle.left
                anchors.rightMargin: Style.space(4)
                enabled: importChoice.enabled
                cursorShape: Qt.PointingHandCursor
                onClicked: importChoice.toggleImport()
              }

              Text {
                anchors.left: parent.left
                anchors.right: importPersonalToggle.left
                anchors.rightMargin: Style.space(6)
                anchors.verticalCenter: parent.verticalCenter
                textFormat: Text.PlainText
                text: "Add to current theme"
                color: root.foreground
                font.family: root.fontFamily
                font.pixelSize: Style.font.bodySmall
                elide: Text.ElideRight
              }

              ToggleSwitch {
                id: importPersonalToggle
                anchors.right: parent.right
                anchors.verticalCenter: parent.verticalCenter
                checked: root.appearance && root.appearance.importPersonalWallpaper
                busy: root.appearance && root.appearance.busy
                interactive: importChoice.enabled
                cursorRing: false
                foreground: root.foreground
                onToggled: importChoice.toggleImport()
              }
            }
          }

        }
      }

      // Reserve space outside the scrolling controls, including when the
      // panel hits its screen-height cap and cannot grow for a new message.
      Column {
        id: statusFooter
        anchors.left: parent.left
        anchors.right: parent.right
        anchors.bottom: parent.bottom
        visible: root.appearance && (root.appearance.busy || root.appearance.lastError !== "")
        height: visible ? implicitHeight : 0
        spacing: Style.space(8)

        Text {
          visible: root.appearance && root.appearance.lastError !== ""
          width: parent.width
          text: root.appearance ? root.appearance.lastError : ""
          color: root.urgent
          font.family: root.fontFamily
          font.pixelSize: Style.font.bodySmall
          wrapMode: Text.WordWrap
        }

        Text {
          visible: root.appearance && root.appearance.busy
          width: parent.width
          text: root.appearance ? root.appearance.actionStatus : ""
          color: root.dim
          font.family: root.fontFamily
          font.pixelSize: Style.font.bodySmall
          horizontalAlignment: Text.AlignHCenter
          wrapMode: Text.WordWrap
        }
      }
    }
  }
}
