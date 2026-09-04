import QtQuick
import qs.Commons
import qs.Ui

Button {
  id: root

  required property url iconSource
  property string label: ""
  readonly property color contentColor: selected
    ? Style.selectedStateColor(foreground, accent)
    : foreground

  text: ""
  iconText: ""
  bordered: true
  implicitWidth: contentRow.implicitWidth + horizontalPadding * 2
    + Math.max(2, Style.normalBorderWidth * 2)
  implicitHeight: contentRow.implicitHeight + verticalPadding * 2
    + Math.max(2, Style.normalBorderWidth * 2)

  Row {
    id: contentRow
    anchors.centerIn: parent
    spacing: Style.spacing.controlGap

    TintedSvgIcon {
      anchors.verticalCenter: parent.verticalCenter
      width: root.iconSize
      height: width
      iconSize: width
      source: root.iconSource
      color: root.contentColor
    }

    Text {
      anchors.verticalCenter: parent.verticalCenter
      textFormat: Text.PlainText
      text: root.label
      color: root.contentColor
      font.family: root.fontFamily
      font.pixelSize: root.fontSize
      font.bold: root.selected
    }
  }
}
