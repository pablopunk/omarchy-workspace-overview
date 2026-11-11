import QtQuick
import QtQuick.Layouts
import Quickshell
import Quickshell.Wayland
import Quickshell.Hyprland
import qs.Commons
import qs.Ui

// One miniature preview per Hyprland workspace.
//
// The preview is a fixed 16:9 thumbnail that fits everything on the
// workspace: the monitor viewport plus every window, including columns
// scrolled out of view in the scrolling layout. Wider content scales down
// and letterboxes; cards keep a uniform shape.
// There is no chrome: transparent surfaces, no wallpaper or dimming, and the
// only border drawn is the accent around the focused window. Every window
// gets one still screencopy while the overlay is open; a titled placeholder
// remains available if capture is unsupported.
Item {
  id: root

  required property var ws
  property bool captureEnabled: false
  property bool focused: false
  property int captureToken: 0
  property var activeToplevel: null
  // Reference width: the width of a 16:9 card. The actual card scales with
  // content aspect (see cardWidth in the overview), preview height is fixed.
  property real refWidth: 112

  signal activate(var ws)
  signal activateWindow(var ws, var win)

  readonly property real previewHeight: Math.round(refWidth * 9 / 16)
  readonly property real labelHeight: Math.max(Style.space(12), Style.font.caption + Style.space(4))

  // Uniform card shape; the whole workspace content (viewport plus any
  // off-screen windows) is fitted inside and centered, so nothing clips.
  readonly property real contentX: (ws && isFinite(Number(ws.contentX))) ? Number(ws.contentX) : 0
  readonly property real contentY: (ws && isFinite(Number(ws.contentY))) ? Number(ws.contentY) : 0
  readonly property real contentW: (ws && Number(ws.contentW) > 0) ? Number(ws.contentW) : root.width
  readonly property real contentH: (ws && Number(ws.contentH) > 0) ? Number(ws.contentH) : root.previewHeight
  readonly property real fitScale: Math.min(root.width / contentW, previewHeight / contentH)
  readonly property real fitOX: (root.width - contentW * fitScale) / 2
  readonly property real fitOY: (previewHeight - contentH * fitScale) / 2
  readonly property bool hasScale: fitScale > 0 && isFinite(fitScale)

  function fitX(v) { return Math.round((v - contentX) * fitScale + fitOX) }
  function fitY(v) { return Math.round((v - contentY) * fitScale + fitOY) }
  function fitW(v) { return Math.max(4, Math.round(v * fitScale)) }
  function fitH(v) { return Math.max(4, Math.round(v * fitScale)) }

  readonly property string label: ws ? String(ws.label || ws.id) : ""

  implicitHeight: previewHeight + labelHeight
  implicitWidth: root.width

  // Card surface: transparent layout frame, no background, no border. Only
  // the focused window tile draws a border (below).
  BorderSurface {
    id: card
    anchors.top: parent.top
    anchors.horizontalCenter: parent.horizontalCenter
    width: root.width
    height: root.previewHeight + root.labelHeight
    radius: Style.cornerRadius
    color: Util.alpha(Color.background, 0.6)
    borderSpec: Border.none()
    clip: true

    // -------- preview area --------
    Item {
      id: preview
      anchors.top: parent.top
      anchors.topMargin: card.contentTopInset
      anchors.left: parent.left
      anchors.leftMargin: card.contentLeftInset
      width: card.width - card.contentLeftInset - card.contentRightInset
      height: root.previewHeight
      clip: true

      // Window tiles at fitted geometry. z-order follows the model's reading
      // order, so Repeater stacking is correct.
      Repeater {
        model: root.ws ? root.ws.windows : []

        Item {
          id: windowTile
          required property var modelData
          readonly property var win: modelData
          property bool captureQueued: false
          property int captureToken: root.captureToken
          property bool componentReady: false
          property int captureAttempts: 0

          Component.onCompleted: componentReady = true

          function requestCapture() {
            if (captureQueued) return
            if (!root.captureEnabled) return
            var source = capture.captureSource
            if (!source) return
            captureQueued = true
            Qt.callLater(function() {
              captureQueued = false
              if (root.captureEnabled && capture.captureSource === source) capture.captureFrame()
            })
          }

          // Fitted workspace geometry; unknown geometry falls back to a small
          // cascade so several such tiles don't stack.
          x: root.hasScale && !win.noGeo ? root.fitX(win.x) : win.fx
          y: root.hasScale && !win.noGeo ? root.fitY(win.y) : win.fy
          width: root.hasScale && !win.noGeo ? root.fitW(win.w) : 24
          height: root.hasScale && !win.noGeo ? root.fitH(win.h) : 24

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
          }

          // A source that is not ready on the first frame stays blank
          // forever without a retry, so keep re-requesting while the overlay
          // stays open (cheap single shots, never a stream). This also fills
          // tiles in if their window scrolls into view mid-overview.
          // Truly uncapturable windows keep the title placeholder below.
          Timer {
            id: captureRetry
            interval: 350
            repeat: true
            running: root.captureEnabled && !capture.hasContent && windowTile.captureAttempts < 60
            onTriggered: {
              windowTile.captureAttempts += 1
              windowTile.requestCapture()
            }
          }

          onCaptureTokenChanged: {
            if (componentReady) {
              windowTile.captureAttempts = 0
              if (capture.captureSource) requestCapture()
            }
          }

          // Title on a translucent tile — the fallback when a window has no
          // pixels to copy (e.g. far offscreen). Hidden while a capture is
          // actually rendering.
          Rectangle {
            anchors.fill: parent
            radius: Math.max(1, Math.min(Style.cornerRadius, 4))
            color: Util.alpha(Color.background, 0.55)
            visible: !capture.hasContent
          }

          Text {
            anchors.centerIn: parent
            width: parent.width - 6
            visible: !capture.hasContent
            text: win.title.length > 0 ? win.title : String(win.appId || "window")
            textFormat: Text.PlainText
            font.family: Style.font.family
            font.pixelSize: Math.max(6, Style.font.caption - 2)
            color: Color.popups.text
            horizontalAlignment: Text.AlignHCenter
            elide: Text.ElideRight
            maximumLineCount: 2
            wrapMode: Text.Wrap
          }

          // Accent border around the focused window; nothing else draws chrome.
          // Tracks live focus without rebuilding the model: the tile whose
          // surface is the active toplevel gets the border, falling back to
          // the model flag when either side is missing.
          Rectangle {
            anchors.fill: parent
            color: "transparent"
            radius: Math.max(1, Math.min(Style.cornerRadius, 4))
            border.color: Color.accent
            border.width: 2
            visible: (win.wayland && activeToplevel) ? activeToplevel === win.wayland : win.activated === true
          }

          // Clicking a tile focuses that exact window; clicks elsewhere on
          // the card fall through to the card-level workspace switch.
          MouseArea {
            anchors.fill: parent
            hoverEnabled: true
            cursorShape: Qt.PointingHandCursor
            onClicked: function(mouse) { mouse.accepted = true; root.activateWindow(root.ws, win) }
          }
        }
      }
    }

    // -------- label row (left-aligned with the tiles) --------
    RowLayout {
      anchors.top: preview.bottom
      anchors.left: parent.left
      anchors.leftMargin: card.contentLeftInset + Style.space(4)
      anchors.topMargin: Style.space(1)
      spacing: Style.space(4)

      Text {
        text: root.label
        textFormat: Text.PlainText
        font.family: Style.font.family
        font.pixelSize: Style.font.caption
        font.bold: root.focused
        color: root.focused ? Color.accent : Util.alpha(Color.popups.text, 0.7)
      }

      Rectangle {
        visible: root.ws && root.ws.urgent
        width: Style.space(5)
        height: Style.space(5)
        radius: width / 2
        color: Color.urgent
      }
    }

    // Clicking a card switches to that workspace.
    MouseArea {
      anchors.fill: parent
      hoverEnabled: true
      cursorShape: Qt.PointingHandCursor
      onClicked: root.activate(root.ws)
    }
  }
}
