# Omarchy Workspace Preview

Preview your Hyprland workspaces on switch.

![Workspace Preview](preview.png)

## Features

- Shows only workspaces containing windows
- Recreates tiled and floating window layouts from Hyprland geometry
- Highlights the focused workspace using the active Omarchy theme
- Uses the current wallpaper, colors, typography, spacing, and corner radius
- Follows the focused monitor and avoids a bottom-positioned Omarchy bar
- Captures one still frame per window, then releases all capture sources when hidden
- Debounces rapid workspace changes and performs no capture work while idle

## Requirements

- Omarchy Quattro
- Hyprland and Quickshell as provided by Omarchy

There are no external dependencies, privileged operations, background services, or network requests.

## Install

```sh
omarchy plugin add https://github.com/pablopunk/omarchy-workspace-preview.git --enable
```

The plugin starts automatically and appears briefly after the focused Hyprland workspace changes.

## Configure

The defaults are defined near the top of `WorkspacePreview.qml`:

- `duration`: visibility in milliseconds, default `1300`
- `cardWidth`: preferred workspace card width
- `cardGap`: spacing between workspace cards
- `panelMargin`: distance from the bottom screen edge

User plugin files live at:

```text
~/.config/omarchy/plugins/pol.workspace-preview/
```

Restart the shell after changing plugin code:

```sh
omarchy restart shell
```

## Commands

```sh
omarchy-shell workspace-preview open
omarchy-shell workspace-preview close
omarchy-shell workspace-preview toggle
omarchy-shell workspace-preview state
```

## Remove

```sh
omarchy plugin remove pol.workspace-preview
```

## Performance

The plugin never runs live video captures. When opened, it requests one thumbnail-sized frame for each visible window. Capture sources are cleared as soon as the overlay closes, leaving no ongoing compositor or GPU work.

## License

[MIT](LICENSE)
