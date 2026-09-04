import QtQuick
import QtQuick.Effects
import Quickshell
import qs.Commons

Item {
  id: root

  required property url source
  property color color: Color.foreground
  property real iconSize: Style.font.icon

  implicitWidth: iconSize
  implicitHeight: iconSize

  Image {
    id: sourceImage
    anchors.centerIn: parent
    width: Math.min(root.width, root.iconSize)
    height: width
    source: root.source
    sourceSize.width: Math.round(width * Screen.devicePixelRatio)
    sourceSize.height: Math.round(height * Screen.devicePixelRatio)
    fillMode: Image.PreserveAspectFit
    smooth: true
    mipmap: true
    visible: false
    layer.enabled: true
  }

  MultiEffect {
    anchors.fill: sourceImage
    source: sourceImage
    colorization: 1.0
    colorizationColor: root.color
  }
}
