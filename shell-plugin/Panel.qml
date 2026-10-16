import QtQuick
import Quickshell.Io
import qs.Commons
import qs.Ui
import "Model.js" as Model

// Bar button + click-through popup showing `omarchy-identity status --json`.
// Cosmetic only: it never runs a privileged command, never blocks the shell
// (the CLI runs in a Process with a 5s timeout), and any failure collapses to
// "identity: unavailable". Not a security boundary.
Panel {
  id: root
  moduleName: "brady.identity-status"
  ipcTarget: "brady.identity-status"

  readonly property color foreground: bar ? bar.foreground : Color.foreground
  readonly property color urgent: bar ? bar.urgent : Color.urgent
  readonly property color dim: Qt.darker(foreground, 1.55)
  readonly property string fontFamily: bar ? bar.fontFamily : Style.font.family
  readonly property int refreshIntervalSec: Math.max(5, Number(setting("refreshIntervalSec", 60)) || 60)

  property var status: Model.parse("")
  property string lastOutput: ""

  function refresh() {
    if (statusProc.running) return
    root.lastOutput = ""
    statusProc.running = true
  }

  Process {
    id: statusProc
    // sh gives a clean exit 127 when the CLI is absent instead of a spawn error.
    command: ["sh", "-c", "exec timeout 5 omarchy-identity status --json"]
    stdout: StdioCollector {
      waitForEnd: true
      onStreamFinished: root.lastOutput = text
    }
    onExited: function(exitCode) {
      root.status = exitCode === 0
        ? Model.parse(root.lastOutput)
        : Model.unavailable("omarchy-identity exited " + exitCode)
    }
  }

  Timer {
    interval: root.refreshIntervalSec * 1000
    repeat: true
    running: true
    triggeredOnStart: true
    onTriggered: root.refresh()
  }

  BarIconButton {
    id: button
    anchors.fill: parent
    bar: root.bar
    text: Model.glyph(root.status.state)
    active: root.status.state === "warn"
    tooltipText: root.status.summary
    onPressed: function(buttonCode) {
      if (buttonCode === Qt.MiddleButton) root.refresh()
      else root.toggle()
    }
  }

  PopupCard {
    anchorItem: button
    owner: root
    bar: root.bar
    open: root.opened
    contentWidth: Style.space(300)
    contentHeight: column.implicitHeight + padding * 2

    Column {
      id: column
      width: parent ? parent.width : Style.space(300)
      spacing: Style.space(6)

      Text {
        textFormat: Text.PlainText
        width: parent.width
        text: root.status.summary
        color: root.status.state === "warn" ? root.urgent : root.foreground
        font.family: root.fontFamily
        font.pixelSize: Style.font.body
        font.bold: true
        wrapMode: Text.WordWrap
      }

      Text {
        visible: root.status.state === "unavailable"
        textFormat: Text.PlainText
        width: parent.width
        text: (root.status.reason !== "" ? root.status.reason + ". " : "") + "Is the omarchy-identity package installed?"
        color: root.dim
        font.family: root.fontFamily
        font.pixelSize: Style.font.bodySmall
        wrapMode: Text.WordWrap
      }

      PanelSeparator { visible: root.status.rows.length > 0; foreground: root.foreground }

      Repeater {
        model: root.status.rows
        delegate: Row {
          required property var modelData
          width: column.width
          spacing: Style.space(8)
          Text {
            textFormat: Text.PlainText
            width: Math.round(parent.width * 0.4)
            text: modelData.label
            color: root.dim
            font.family: root.fontFamily
            font.pixelSize: Style.font.bodySmall
          }
          Text {
            textFormat: Text.PlainText
            width: parent.width - Math.round(parent.width * 0.4) - parent.spacing
            text: modelData.value
            color: root.foreground
            font.family: root.fontFamily
            font.pixelSize: Style.font.bodySmall
            wrapMode: Text.WordWrap
          }
        }
      }

      PanelSeparator { visible: root.status.warnings.length > 0; foreground: root.foreground }

      Repeater {
        model: root.status.warnings
        delegate: Text {
          required property string modelData
          textFormat: Text.PlainText
          width: column.width
          text: "⚠ " + modelData
          color: root.urgent
          font.family: root.fontFamily
          font.pixelSize: Style.font.bodySmall
          wrapMode: Text.WordWrap
        }
      }

      Text {
        textFormat: Text.PlainText
        width: parent.width
        text: "Middle-click the bar icon to refresh. Informational only."
        color: root.dim
        font.family: root.fontFamily
        font.pixelSize: Style.font.caption
        wrapMode: Text.WordWrap
      }
    }
  }
}
