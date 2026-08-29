# Omarchy Workspace Peek

Preview your Hyprland workspaces while switching. Works with your mouse too.

![Workspace Peek](preview.png)

## Controls

- Switching workspaces opens the overview automatically.
- Mouse: touch the bottom edge of the focused monitor to open it, then click a workspace card to switch there.
- The overview stays open while the pointer is over the cards and hides after it leaves.

## Features

- Recreates tiled and floating layouts from Hyprland geometry.
- Shows current wallpaper and theme styling, with the focused workspace highlighted.
- Follows the focused monitor and avoids a bottom-positioned bar.
- Captures one still thumbnail per window; no live capture or idle GPU work.

## Install

```sh
omarchy plugin add https://github.com/pablopunk/omarchy-workspace-overview.git --enable
```

Requires Omarchy Quattro with Hyprland and Quickshell. There are no external dependencies.

## Configure

Edit `~/.config/omarchy/plugins/pablopunk.workspace-overview/WorkspaceOverview.qml`.
Available settings include `duration` (1300 ms), `cardWidth`, `cardGap`, `panelMargin`, `edgeEnabled` (true), and `edgeHeight`.

Restart after code changes:

```sh
omarchy restart shell
```

## Commands

```sh
omarchy-shell workspace-overview open
omarchy-shell workspace-overview close
omarchy-shell workspace-overview toggle
omarchy-shell workspace-overview state
```

## Remove

```sh
omarchy plugin remove pablopunk.workspace-overview
```

## License

[MIT](LICENSE)
