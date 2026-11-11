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
// A strip of miniature monitor previews, one per Hyprland workspace. Appears
// whenever the focused workspace changes or the pointer touches the screen
// edge, and hides after a short delay. The focused workspace is highlighted
// with the theme accent. Set `orientation` to "vertical" for a side-centered
// column instead of the default bottom-centered row.
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
  property int outerPad: Style.space(10)
  property int panelMargin: Style.space(44)
  property int sideMargin: Style.space(12)
  property int maxCardWidth: Style.space(360)
  property bool edgeEnabled: true
  property int edgeHeight: Style.space(6)
  property int edgeWidth: Style.space(6)
  property string orientation: "horizontal" // "horizontal" or "vertical"
  property string verticalSide: "right" // vertical strip/edge side: "left" or "right"

  // Anything but an explicit "vertical" falls back to the horizontal row.
  readonly property bool isVertical: root.orientation === "vertical"
  // Anything but an explicit "left" docks the vertical strip on the right.
  readonly property string effectiveSide: root.verticalSide === "left" ? "left" : "right"

  // Shrink cards when the full strip would not fit the focused monitor. The
  // horizontal row fits against the screen width; the vertical column fits
  // against the screen height (cards stay 16:9, stacked top to bottom).
  readonly property int labelHeightEst: Math.max(Style.space(12), Style.font.caption + Style.space(4))
  readonly property int cardBorderEst: Math.max(2, Style.space(2))
  readonly property int effectiveCardWidth: {
    var n = Math.max(1, root.workspaces.length)
    var screen = root.activeScreen
    if (root.isVertical) {
      var availH = screen ? screen.height : 1080
      var perCardH = (availH - root.panelMargin * 2 - root.cardGap * (n - 1) - root.outerPad * 2 - 4) / n
      var maxWV = Math.floor((perCardH - root.labelHeightEst - root.cardBorderEst * 2) * 16 / 9)
      return Math.max(64, Math.min(root.cardWidth, maxWV))
    }
    // Horizontal cards vary in width with their content aspect, so solve the
    // reference width (the width of a 16:9 card) for the whole row at once.
    var totalAspect = 0
    for (var i = 0; i < root.workspaces.length; i++) {
      var cw = Number(root.workspaces[i].contentW) || 0
      var ch = Number(root.workspaces[i].contentH) || 0
      totalAspect += (cw > 0 && ch > 0) ? cw / ch : 16 / 9
    }
    if (!(totalAspect > 0)) totalAspect = 16 / 9
    var avail = screen ? screen.width : 1920
    var maxW = Math.floor((avail - root.panelMargin * 2 - root.cardGap * (n - 1) - root.outerPad * 2 - 4) / n)
    var maxRef = Math.floor((avail - root.panelMargin * 2 - root.cardGap * (n - 1) - root.outerPad * 2 - 4) / (9 / 16 * totalAspect))
    return Math.max(64, Math.min(root.cardWidth, maxW, maxRef))
  }

  // Card width follows content aspect at a common scale: a workspace holding
  // scrolled-out columns renders wider than a single-screen one, like a true
  // miniature. Reference (16:9) width comes from effectiveCardWidth.
  function cardWidthFor(ws) {
    var cw = ws ? Number(ws.contentW) : 0
    var ch = ws ? Number(ws.contentH) : 0
    var aspect = (cw > 0 && ch > 0) ? cw / ch : 16 / 9
    return Math.max(48, Math.min(root.maxCardWidth, root.effectiveCardWidth * aspect * 9 / 16))
  }

  readonly property int hideAnim: 100
  readonly property int cornerRadius: Style.cornerRadius
  property var workspaces: []
  property bool ready: false
  property bool modelDirty: true
  property int captureToken: 0
  property bool geometryRefreshPending: false
  property bool geometryRefreshInFlight: false

  Timer {
    id: readyTimer
    interval: 1500
    onTriggered: root.ready = true
  }

  Component.onCompleted: {
    readyTimer.start()
  }

  // Show / hide / toggle are the shell panel contract.
  function open(payloadJson) { show() }
  function close() { hide() }
  function toggle() { opened ? hide() : show() }

  function refreshModel() {
    root.workspaces = Workspaces.buildWorkspaces()
    root.modelDirty = false
    if (root.opened && root.workspaces.length === 0) root.hide()
  }

  // Refresh the expensive IPC geometry request once per topology burst. The
  // first model is useful immediately; the delayed rebuild picks up fresh
  // positions/sizes without delaying the initial overlay.
  function requestGeometryRefresh() {
    root.geometryRefreshPending = true
    if (root.geometryRefreshInFlight) return
    root.geometryRefreshInFlight = true
    Hyprland.refreshToplevels()
    geometryRefreshTimer.restart()
  }

  function restartHideTimer() {
    if (stripHover.hovered) hideTimer.stop()
    else hideTimer.restart()
  }

  function show() {
    var wasOpen = root.opened
    var rebuilt = root.modelDirty
    ready = true
    if (rebuilt) {
      // Focus changes do not alter workspace membership, so reuse the card
      // tree for the common path. Topology events mark this model dirty.
      refreshModel()
    }
    if (root.workspaces.length === 0) {
      if (root.opened) root.hide()
      return
    }
    if (!rebuilt && wasOpen) root.captureToken += 1
    opened = true
    restartHideTimer()
  }

  function hide() {
    hideTimer.stop()
    settleTimer.stop()
    opened = false
  }

  // Escape a value for the inner Lua string literal before quoting the outer
  // shell argument.
  function luaEscape(value) {
    return String(value).replace(/[\\"\x00-\x1f\x7f]/g, function(ch) {
      if (ch === "\\") return "\\\\"
      if (ch === '"') return '\\"'
      var decimal = ch.charCodeAt(0).toString()
      return "\\" + ("000" + decimal).slice(-3)
    })
  }

  // Switch to the workspace behind a clicked card. Omarchy runs Hyprland in
  // Lua mode, so workspace focus goes through the Lua dispatcher.
  function focusWorkspace(ws) {
    if (!ws) return
    var target = (ws.name && String(ws.name).length > 0) ? String(ws.name) : String(ws.id)
    var expr = 'hl.dsp.focus({ workspace = "' + root.luaEscape(target) + '" })'
    Util.execDetached('hyprctl dispatch ' + Util.shellQuote(expr))
  }

  // Focus the exact window behind a clicked tile. Falls back to the workspace
  // when the tile carries no address (uncapturable or unknown geometry).
  function focusWindow(ws, win) {
    if (!win) { root.focusWorkspace(ws); return }
    var target = (win.address && String(win.address).length > 0) ? String(win.address) : ""
    if (target.length === 0) { root.focusWorkspace(ws); return }
    var expr = 'hl.dsp.focus({ window = "address:' + root.luaEscape(target) + '" })'
    Util.execDetached('hyprctl dispatch ' + Util.shellQuote(expr))
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

  readonly property var focusedWorkspaceId: {
    var ws = Hyprland.focusedWorkspace
    return ws ? ws.id : null
  }

  // Live focused window. Window/workspace actions while the overview is open
  // push the auto-hide back; the overview only closes after a quiet spell.
  readonly property var activeToplevel: ToplevelManager.activeToplevel

  onActiveToplevelChanged: {
    if (root.opened) root.restartHideTimer()
  }

  // Bar-aware bottom margin so the strip never sits under a bottom bar.
  readonly property real cardBottomMargin: {
    var bar = shell ? shell.bar : null
    if (bar && bar.position === "bottom" && !bar.barHidden) {
      return panelMargin + Number(bar.barSize || 0)
    }
    return panelMargin
  }

  // Side-aware margin so the vertical strip never sits under a side bar.
  readonly property real cardSideMargin: {
    var sidebar = shell ? shell.bar : null
    if (sidebar && !sidebar.barHidden) {
      if (root.effectiveSide === "right" && sidebar.position === "right") {
        return sideMargin + Number(sidebar.barSize || 0)
      }
      if (root.effectiveSide === "left" && sidebar.position === "left") {
        return sideMargin + Number(sidebar.barSize || 0)
      }
    }
    return sideMargin
  }

  Timer {
    id: hideTimer
    interval: root.duration
    onTriggered: root.hide()
  }

  Timer {
    id: geometryRefreshTimer
    interval: 100
    onTriggered: {
      root.geometryRefreshInFlight = false
      if (!root.geometryRefreshPending) return
      root.geometryRefreshPending = false
      root.refreshModel()
      if (root.workspaces.length === 0) return
      if (root.opened) root.restartHideTimer()
    }
  }

  // Settle rapid window-topology events into one model rebuild.
  Timer {
    id: settleTimer
    interval: 40
    onTriggered: root.show()
  }

  Connections {
    target: Hyprland

    function onFocusedWorkspaceChanged() {
      if (root.ready) root.show()
    }

    function onRawEvent(event) {
      var name = String(event && event.name ? event.name : "")
      // Ignore the initial workspace/focus events Hyprland emits while the
      // shell is coming up, so the strip never flashes at login.
      if (!root.ready) return
      var geometryEvent = ["movewindow", "moveworkspace", "openwindow", "closewindow", "changefloatingmode", "fullscreen", "pin", "minimize"].indexOf(name) !== -1
      var modelEvent = geometryEvent || name === "renameworkspace" || name === "urgent"
      if (!modelEvent) return

      root.modelDirty = true
      if (geometryEvent) root.requestGeometryRefresh()
      else if (root.opened) settleTimer.restart()
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
          focused: root.focusedWorkspaceId !== null && Number(w.id) === Number(root.focusedWorkspaceId),
          windows: w.windowCount,
          mw: w.monitorWidth,
          mh: w.monitorHeight,
          content: { x: w.contentX, y: w.contentY, w: w.contentW, h: w.contentH },
          geometry: w.windows.map(function(win) {
            return { x: win.x, y: win.y, w: win.w, h: win.h, noGeo: win.noGeo }
          })
        })
      }
      return JSON.stringify({
        opened: root.opened,
        screen: root.activeScreen ? String(root.activeScreen.name) : null,
        cardWidth: root.cardWidth,
        effectiveCardWidth: root.effectiveCardWidth,
        orientation: root.orientation,
        verticalSide: root.verticalSide,
        effectiveSide: root.effectiveSide,
        activeMatches: (function() {
          var n = 0
          var active = ToplevelManager.activeToplevel
          if (!active) return -1
          for (var i = 0; i < root.workspaces.length; i++) {
            var wins = root.workspaces[i].windows
            for (var j = 0; j < wins.length; j++) {
              if (wins[j].wayland && wins[j].wayland === active) n++
            }
          }
          return n
        })(),
        strip: { x: Math.round(strip.x), y: Math.round(strip.y), w: Math.round(strip.width), h: Math.round(strip.height) },
        window: { w: panel.width, h: panel.height },
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
    // Only the strip receives input; clicks elsewhere pass through to the
    // desktop, so a stray click dismisses the overview without swallowing it.
    mask: Region { item: strip }

    BorderSurface {
      id: strip
      height: cardsGrid.implicitHeight + root.outerPad * 2 + borderTop + borderBottom
      width: cardsGrid.implicitWidth + root.outerPad * 2 + borderLeft + borderRight
      radius: root.cornerRadius
      // No outer box: the strip is an invisible layout frame, only the
      // workspace cards themselves draw a surface.
      color: "transparent"
      borderSpec: Border.none()
      opacity: root.opened ? 1 : 0

      // Explicit positioning from the fullscreen window size: window anchor
      // lines do not resolve for side/center docking, so anchors alone leave
      // the strip stranded at the origin. Horizontal stays bottom-centered;
      // vertical docks side-centered on the configured side.
      x: {
        if (!root.isVertical) return Math.round((panel.width - width) / 2)
        var mx = root.cardSideMargin + (root.opened ? 0 : Style.space(14))
        if (root.effectiveSide === "right") return Math.round(panel.width - width - mx)
        return Math.round(mx)
      }
      y: {
        if (!root.isVertical) {
          var my = root.cardBottomMargin + (root.opened ? 0 : Style.space(14))
          return Math.round(panel.height - height - my)
        }
        return Math.round((panel.height - height) / 2)
      }

      // Keep the overview open while the pointer is over it, so a click can
      // land; the auto-hide countdown resumes once the pointer leaves.
      HoverHandler {
        id: stripHover
        onHoveredChanged: {
          if (hovered) hideTimer.stop()
          else if (root.opened) hideTimer.restart()
        }
      }

      Behavior on opacity {
        NumberAnimation { duration: root.hideAnim; easing.type: Easing.OutCubic }
      }
      Behavior on x {
        NumberAnimation { duration: root.hideAnim; easing.type: Easing.OutCubic }
      }
      Behavior on y {
        NumberAnimation { duration: root.hideAnim; easing.type: Easing.OutCubic }
      }

      // One grid serves both orientations: a single row for horizontal, a
      // single column for vertical, in workspace-id order either way.
      Grid {
        id: cardsGrid
        anchors.top: parent.top
        anchors.topMargin: root.outerPad
        anchors.horizontalCenter: parent.horizontalCenter
        columns: root.isVertical ? 1 : Math.max(1, root.workspaces.length)
        rows: root.isVertical ? Math.max(1, root.workspaces.length) : 1
        columnSpacing: root.cardGap
        rowSpacing: root.cardGap
        horizontalItemAlignment: Grid.AlignLeft
        verticalItemAlignment: Grid.AlignTop

        Repeater {
          model: root.workspaces

          WorkspaceCard {
            required property var modelData

            refWidth: root.effectiveCardWidth
            width: root.cardWidthFor(modelData)

            ws: modelData
            // Cards take one still frame, then captureSource becomes null when
            // the overlay closes, releasing compositor and texture resources.
            captureEnabled: root.opened
            captureToken: root.captureToken
            focused: root.focusedWorkspaceId !== null
              && Number(root.focusedWorkspaceId) === Number(modelData.id)
            activeToplevel: root.activeToplevel
            onActivate: function(ws) { root.focusWorkspace(ws) }
            onActivateWindow: function(ws, win) { root.focusWindow(ws, win) }
          }
        }
      }
    }
  }

  // Invisible hot edges. Touching the edge of the focused monitor shows the
  // overview the same way a workspace switch does: the bottom edge for the
  // horizontal row, the configured side edge for the vertical column.
  PanelWindow {
    id: bottomEdge
    screen: root.activeScreen
    visible: root.edgeEnabled && !root.isVertical
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

  PanelWindow {
    id: sideEdge
    screen: root.activeScreen
    visible: root.edgeEnabled && root.isVertical
    anchors {
      top: true; bottom: true
      left: root.effectiveSide === "left"
      right: root.effectiveSide === "right"
    }
    implicitWidth: root.edgeWidth
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
