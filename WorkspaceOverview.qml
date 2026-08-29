import QtQuick
import QtQuick.Layouts
import Quickshell
import Quickshell.Io
import Quickshell.Wayland
import Quickshell.Hyprland
import qs.Commons
import qs.Ui
import "Workspaces.js" as Workspaces

// Workspace switcher overlay.
//
// A bottom-centered strip of miniature monitor previews, one per Hyprland
// workspace. Appears whenever the focused workspace changes or the pointer
// touches the bottom edge of the focused monitor, and hides after a short
// delay. The focused workspace is highlighted with the theme accent.
//
// Window thumbnails are single-frame toplevel exports. Capture sources exist
// only while the overlay is open, keeping compositor and battery cost brief.
Item {
  id: root

  // Injected by the shell panel loader.
  property var shell: null
  property var manifest: null
  property string omarchyPath: ""

  property bool opened: false
  property int duration: 1300
  property int cardWidth: Style.space(112)
  property int cardGap: Style.space(10)
  property int outerPad: Style.space(14)
  property int panelMargin: Style.space(44)
  property bool edgeEnabled: true
  property int edgeHeight: Style.space(6)

  // Shrink cards when the full row would not fit the focused monitor.
  readonly property int effectiveCardWidth: {
    var n = Math.max(1, root.workspaces.length)
    var screen = root.activeScreen
    var avail = screen ? screen.width : 1920
    var maxW = Math.floor((avail - root.panelMargin * 2 - root.cardGap * (n - 1) - root.outerPad * 2 - 4) / n)
    return Math.max(64, Math.min(root.cardWidth, maxW))
  }

  readonly property int hideAnim: 150
  readonly property int cornerRadius: Style.cornerRadius
  property var workspaces: []
  property string wallpaperPath: ""
  property bool ready: false

  Timer {
    id: readyTimer
    interval: 1500
    onTriggered: root.ready = true
  }

  Component.onCompleted: {
    readyTimer.start()
    wallpaperProc.running = true
  }

  // Show / hide / toggle are the shell panel contract.
  function open(payloadJson) { show() }
  function close() { hide() }
  function toggle() { opened ? hide() : show() }

  function show() {
    wallpaperProc.running = true
    ready = true
    opened = true
    Hyprland.refreshToplevels()
    modelRefreshTimer.restart()
  }

  function hide() {
    hideTimer.stop()
    opened = false
  }

  // Reactive screen resolution: QML tracks focusedMonitor.name and
  // Quickshell.screens so this re-evaluates when either changes.
  readonly property var activeScreen: {
    var mon = Hyprland.focusedMonitor
    var name = mon ? String(mon.name || "") : ""
    var screens = Quickshell.screens
    if (name.length > 0) {
      for (var i = 0; i < screens.length; i++) {
        if (String(screens[i].name || "") === name) return screens[i]
      }
    }
    return screens.length > 0 ? screens[0] : null
  }

  // Bar-aware bottom margin so the strip never sits under a bottom bar.
  readonly property real cardBottomMargin: {
    var bar = shell ? shell.bar : null
    if (bar && bar.position === "bottom" && !bar.barHidden) {
      return panelMargin + Number(bar.barSize || 0)
    }
    return panelMargin
  }

  Timer {
    id: hideTimer
    interval: root.duration
    onTriggered: root.opened = false
  }

  // refreshToplevels() updates lastIpcObject asynchronously. Geometry is not
  // usable until that reply lands; building immediately would put every window
  // into the tiny unknown-geometry fallback.
  Timer {
    id: modelRefreshTimer
    interval: 100
    onTriggered: {
      root.workspaces = Workspaces.buildWorkspaces()
      hideTimer.restart()
    }
  }

  // Settle rapid workspace event bursts (Hyprland emits several events per
  // switch) into one refresh.
  Timer {
    id: settleTimer
    interval: 120
    onTriggered: root.show()
  }

  Connections {
    target: Hyprland

    function onRawEvent(event) {
      var name = String(event && event.name ? event.name : "")
      // Ignore the initial workspace/focus events Hyprland emits while the
      // shell is coming up, so the strip never flashes at login.
      if (!root.ready) return
      if (name === "workspace" || name === "workspacev2") {
        settleTimer.restart()
      } else if (name === "movewindow" || name === "moveworkspace" || name === "openwindow" || name === "closewindow") {
        if (root.opened) settleTimer.restart()
      }
    }
  }

  Process {
    id: wallpaperProc
    command: ["readlink", "-f", Quickshell.env("HOME") + "/.local/state/omarchy/current/background"]
    stdout: StdioCollector {
      id: wallpaperOut
      waitForEnd: true
      onStreamFinished: {
        var next = String(text || "").trim()
        if (next.length > 0 && next !== root.wallpaperPath) root.wallpaperPath = next
      }
    }
  }

  IpcHandler {
    target: "workspace-overview"
    function open(): string { root.show(); return "ok" }
    function close(): string { root.hide(); return "ok" }
    function toggle(): string { root.toggle(); return "ok" }
    function state(): string { return root.opened ? "open" : "closed" }
    function debug(): string {
      var ws = []
      for (var i = 0; i < root.workspaces.length; i++) {
        var w = root.workspaces[i]
        ws.push({
          id: w.id,
          label: w.label,
          focused: w.focused,
          windows: w.windowCount,
          mw: w.monitorWidth,
          mh: w.monitorHeight,
          geometry: w.windows.map(function(win) {
            return { x: win.x, y: win.y, w: win.w, h: win.h, noGeo: win.noGeo }
          })
        })
      }
      return JSON.stringify({
        opened: root.opened,
        screen: root.activeScreen ? String(root.activeScreen.name) : null,
        wallpaper: root.wallpaperPath,
        cardWidth: root.cardWidth,
        workspaces: ws
      })
    }
  }

  PanelWindow {
    id: panel
    screen: root.activeScreen
    visible: root.opened || strip.opacity > 0
    anchors { top: true; bottom: true; left: true; right: true }
    color: "transparent"
    WlrLayershell.namespace: "omarchy-workspace-overview"
    WlrLayershell.layer: WlrLayer.Overlay
    WlrLayershell.keyboardFocus: WlrKeyboardFocus.None
    exclusionMode: ExclusionMode.Ignore
    // Visual-only surface: clicks pass straight through to the desktop.
    mask: Region {}

    BorderSurface {
      id: strip
      anchors.horizontalCenter: parent.horizontalCenter
      anchors.bottom: parent.bottom
      anchors.bottomMargin: root.cardBottomMargin + (root.opened ? 0 : Style.space(14))
      height: cardsRow.implicitHeight + root.outerPad * 2 + borderTop + borderBottom
      width: root.effectiveCardWidth * Math.max(1, root.workspaces.length)
        + root.cardGap * Math.max(0, root.workspaces.length - 1)
        + root.outerPad * 2 + borderLeft + borderRight
      radius: root.cornerRadius
      color: Util.alpha(Color.popups.background, 0.97)
      borderSpec: Border.surfaceSpec("popups", "border", Color.popups.border, Math.max(1, Style.space(2)))
      opacity: root.opened ? 1 : 0

      Behavior on opacity {
        NumberAnimation { duration: root.hideAnim; easing.type: Easing.OutCubic }
      }
      Behavior on anchors.bottomMargin {
        NumberAnimation { duration: root.hideAnim; easing.type: Easing.OutCubic }
      }

      Row {
        id: cardsRow
        anchors.top: parent.top
        anchors.topMargin: root.outerPad
        anchors.horizontalCenter: parent.horizontalCenter
        spacing: root.cardGap

        Repeater {
          model: root.workspaces

          WorkspaceCard {
            required property var modelData

            width: root.effectiveCardWidth

            ws: modelData
            wallpaper: root.wallpaperPath.length > 0 ? Util.fileUrl(root.wallpaperPath) : ""
            // Cards take one still frame, then captureSource becomes null when
            // the overlay closes, releasing compositor and texture resources.
            captureEnabled: root.opened
          }
        }
      }
    }
  }

  // Invisible bottom hot edge. Touching the bottom of the focused monitor
  // shows the overview the same way a workspace switch does.
  PanelWindow {
    id: edge
    screen: root.activeScreen
    visible: root.edgeEnabled
    anchors { bottom: true; left: true; right: true }
    implicitHeight: root.edgeHeight
    color: "transparent"
    WlrLayershell.namespace: "omarchy-workspace-overview-edge"
    WlrLayershell.layer: WlrLayer.Overlay
    WlrLayershell.keyboardFocus: WlrKeyboardFocus.None
    exclusionMode: ExclusionMode.Ignore

    Item {
      anchors.fill: parent
      HoverHandler {
        onHoveredChanged: if (hovered && root.ready) root.show()
      }
    }
  }
}
