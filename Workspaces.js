// Workspace model builder for pablopunk.workspace-overview.
//
// Converts Quickshell's live Hyprland object model into plain JS objects so a
// Repeater can render one card per workspace. Rebuilt on demand; nothing here
// is reactive — callers rebuild after Hyprland events settle.

function clamp(n, lo, hi) {
  var v = Number(n)
  if (!isFinite(v)) return lo
  return Math.max(lo, Math.min(hi, v))
}

// Hyprland reports window geometry through lastIpcObject. Prefer fresh values
// when present; a toplevel whose IPC object has not resolved yet falls back to
// a neutral rect and the caller cascades it so tiles don't stack.
function windowGeometry(toplevel, monitor) {
  var at = [0, 0]
  var size = [1, 1]
  var known = false
  var ipc = toplevel && toplevel.lastIpcObject
  // QVariantList values exposed by QML are array-like but fail
  // Array.isArray(), so test their shape instead.
  if (ipc && ipc.at && ipc.at.length >= 2 && ipc.size && ipc.size.length >= 2) {
    at = [Number(ipc.at[0]) || 0, Number(ipc.at[1]) || 0]
    size = [Number(ipc.size[0]) || 1, Number(ipc.size[1]) || 1]
    known = true
  }

  // Window coordinates are absolute in Hyprland's layout space; the card
  // renders them relative to the workspace monitor's origin.
  var ox = monitor ? (Number(monitor.x) || 0) : 0
  var oy = monitor ? (Number(monitor.y) || 0) : 0
  return { x: at[0] - ox, y: at[1] - oy, w: clamp(size[0], 1, 100000), h: clamp(size[1], 1, 100000), known: known }
}

function titleOf(toplevel) {
  return toplevel && typeof toplevel.title === "string" ? toplevel.title : ""
}

function appIdOf(toplevel) {
  var t = toplevel && toplevel.wayland ? toplevel.wayland : null
  if (t && typeof t.appId === "string" && t.appId.length > 0) return t.appId
  return ""
}

// One card per occupied workspace. Includes the focused flag, logical monitor
// dimensions for the card aspect ratio, and a window list sorted in reading
// order (top-to-bottom, then left-to-right) so tiles overlap correctly.
function buildWorkspaces() {
  var values = (typeof Hyprland !== "undefined" && Hyprland.workspaces) ? Hyprland.workspaces.values : []
  var out = []
  for (var i = 0; i < values.length; i++) {
    var ws = values[i]
    if (!ws) continue

    var id = Number(ws.id)
    var name = String(ws.name || "")
    var label = name.length > 0 ? name : String(ws.id)
    var monitor = ws.monitor
    var monitorScale = monitor ? (Number(monitor.scale) || 1) : 1
    // Quickshell reports physical monitor dimensions, while Hyprland client
    // geometry is in logical coordinates. Keeping both in the same space makes
    // tiled windows fill the miniature workspace exactly as they do on screen.
    var mw = monitor ? (Number(monitor.width) || 0) / monitorScale : 0
    var mh = monitor ? (Number(monitor.height) || 0) / monitorScale : 0

    var windows = []
    var toplevels = ws.toplevels && ws.toplevels.values ? ws.toplevels.values : []
    var fallbackN = 0
    for (var j = 0; j < toplevels.length; j++) {
      var tl = toplevels[j]
      if (!tl) continue
      var g = windowGeometry(tl, monitor)
      windows.push({
        title: titleOf(tl),
        appId: appIdOf(tl),
        wayland: tl.wayland ? tl.wayland : null,
        x: g.x, y: g.y, w: g.w, h: g.h,
        noGeo: !g.known,
        // Card-space cascade for windows whose IPC geometry never arrived,
        // so several unknown tiles do not stack on the same pixel.
        fx: 4 + (fallbackN % 4) * 14,
        fy: 4 + Math.floor(fallbackN / 4) * 14,
        fullscreen: !!(tl.wayland && tl.wayland.fullscreen),
        activated: tl.activated === true,
        urgent: tl.urgent === true
      })
      fallbackN++
    }
    windows.sort(function (a, b) { return a.y === b.y ? a.x - b.x : a.y - b.y })

    if (windows.length === 0) continue

    out.push({
      id: ws.id,
      name: name,
      label: label,
      focused: ws.focused === true,
      active: ws.active === true,
      urgent: ws.urgent === true,
      hasFullscreen: ws.hasFullscreen === true,
      monitorWidth: mw,
      monitorHeight: mh,
      windows: windows,
      windowCount: windows.length
    })
  }

  out.sort(function (a, b) {
    var aid = Number(a.id)
    var bid = Number(b.id)
    if (aid < 0 && bid >= 0) return 1
    if (bid < 0 && aid >= 0) return -1
    return aid - bid
  })
  return out
}
