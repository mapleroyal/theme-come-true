import QtQuick
import qs.Ui

// Dropdown owns its selection cursor, but the service owns the accepted value.
// The shared control assigns value before emitting changed(), which otherwise
// removes a caller's binding after the first selection.
Dropdown {
  id: root

  property string modelValue: ""
  signal selectionRequested(string selection)

  value: modelValue
  onChanged: function(selection) {
    root.selectionRequested(selection)
    root.value = Qt.binding(function() { return root.modelValue })
  }
}
