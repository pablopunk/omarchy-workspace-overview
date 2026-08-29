import QtQuick
import QtQuick.Layouts
import Quickshell
import Quickshell.Wayland
import Quickshell.Hyprland
import qs.Commons
import qs.Ui

// One miniature monitor preview for a single Hyprland workspace.
//
// The preview is a fixed 16:9 monitor-shaped thumbnail: the wallpaper as its
// backdrop, each window positioned at geometry scaled down from the
// workspace monitor. Every window gets one still screencopy while the overlay
// is open; a titled placeholder remains available if capture is unsupported.
Item {
  id: root

  required property var ws
  property string wallpaper: ""
  property bool captureEnabled: false

  readonly property real previewHeight: Math.round(root.width * 9 / 16)
  readonly property real labelHeight: Math.max(Style.space(12), Style.font.caption + Style.space(4))

  // Uniform aspect keeps every card the same shape; scale factors still come
  // from the workspace monitor so window geometry maps faithfully.
  readonly property real scaleX: (ws && ws.monitorWidth > 0) ? root.width / ws.monitorWidth : 0
  readonly property real scaleY: (ws && ws.monitorHeight > 0) ? previewHeight / ws.monitorHeight : 0
  readonly property bool hasScale: scaleX > 0 && scaleY > 0

  readonly property color focusedBorder: Color.accent
  readonly property color idleBorder: Util.alpha(Color.popups.border, 0.4)
  readonly property color borderColor: ws && ws.focused ? focusedBorder : idleBorder
  readonly property int borderWidth: ws && ws.focused ? Math.max(2, Style.space(2)) : 1

  readonly property string label: ws ? String(ws.label || ws.id) : ""

  implicitHeight: previewHeight + labelHeight + borderWidth * 2
  implicitWidth: root.width

  // Card surface: the monitor-shaped preview plus a small label row.
  BorderSurface {
    id: card
    anchors.top: parent.top
    anchors.horizontalCenter: parent.horizontalCenter
    width: root.width
    height: root.previewHeight + root.labelHeight + root.borderWidth * 2
    radius: Style.cornerRadius
    color: Util.alpha(Color.background, 0.6)
    borderSpec: Border.flat(root.borderColor, root.borderWidth)
    clip: true

    // -------- preview area (inset so the card border stays visible) --------
    Item {
      id: preview
      anchors.top: parent.top
      anchors.topMargin: card.contentTopInset
      anchors.left: parent.left
      anchors.leftMargin: card.contentLeftInset
      width: card.width - card.contentLeftInset - card.contentRightInset
      height: root.previewHeight
      clip: true

      // Wallpaper backdrop, cropped to fill.
      Image {
        anchors.fill: parent
        source: root.wallpaper
        fillMode: Image.PreserveAspectCrop
        asynchronous: true
        visible: root.wallpaper.length > 0
      }

      // Subtle dim so the border and tiles stay readable over any wallpaper.
      Rectangle {
        anchors.fill: parent
        color: Util.alpha(Color.background, 0.25)
      }

      // Window tiles at scaled geometry. z-order follows the model's reading
      // order, so Repeater stacking is correct.
      Repeater {
        model: root.ws ? root.ws.windows : []

        Item {
          required property var modelData
          readonly property var win: modelData

          // Scaled monitor geometry when available; unknown geometry falls
          // back to a small cascade so several such tiles don't stack.
          x: root.hasScale && !win.noGeo ? Math.round(win.x * root.scaleX) : win.fx
          y: root.hasScale && !win.noGeo ? Math.round(win.y * root.scaleY) : win.fy
          width: root.hasScale && !win.noGeo ? Math.max(4, Math.round(win.w * root.scaleX)) : 24
          height: root.hasScale && !win.noGeo ? Math.max(4, Math.round(win.h * root.scaleY)) : 24

          // Dark tile so empty/uncapturable windows still read as windows.
          Rectangle {
            anchors.fill: parent
            radius: Math.max(1, Math.min(Style.cornerRadius, 4))
            color: Util.alpha(Color.background, 0.85)
          }

          ScreencopyView {
            id: capture
            anchors.fill: parent
            captureSource: root.captureEnabled && win.wayland ? win.wayland : null
            // One frame per overlay opening. Never stream, including for the
            // focused workspace, so compositor/GPU work ends immediately.
            live: false
            constraintSize: Qt.size(Math.max(1, width), Math.max(1, height))
            paintCursor: false
            visible: capture.hasContent

            onCaptureSourceChanged: {
              if (captureSource) Qt.callLater(function() { capture.captureFrame() })
            }
          }

          // Title on the placeholder — the only hint non-capturable windows
          // get. Hidden while a capture is actually rendering.
          Text {
            anchors.centerIn: parent
            width: parent.width - 6
            visible: !capture.hasContent
            text: win.title.length > 0 ? win.title : String(win.appId || "window")
            font.family: Style.font.family
            font.pixelSize: Math.max(6, Style.font.caption - 2)
            color: Util.alpha(Color.popups.text, 0.75)
            horizontalAlignment: Text.AlignHCenter
            elide: Text.ElideRight
            maximumLineCount: 2
            wrapMode: Text.Wrap
          }
        }
      }
    }

    // -------- label row --------
    RowLayout {
      anchors.top: preview.bottom
      anchors.horizontalCenter: parent.horizontalCenter
      anchors.topMargin: Style.space(1)
      spacing: Style.space(4)

      Text {
        text: root.label
        font.family: Style.font.family
        font.pixelSize: Style.font.caption
        font.bold: root.ws && root.ws.focused
        color: root.ws && root.ws.focused ? Color.accent : Util.alpha(Color.popups.text, 0.7)
      }

      Rectangle {
        visible: root.ws && root.ws.urgent
        width: Style.space(5)
        height: Style.space(5)
        radius: width / 2
        color: Color.urgent
      }
    }
  }
}
