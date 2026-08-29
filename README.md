# Workspace Preview

See your workspaces at a glance.

Workspace Preview appears when you switch Hyprland workspaces, showing a compact snapshot of every occupied workspace and highlighting the one you selected. It looks and feels native to Omarchy because it follows your current theme, wallpaper, spacing, typography, and window rounding.

![Workspace Preview](preview.png)

## Features

- Shows only workspaces that contain windows
- Recreates tiled and floating layouts from their real Hyprland geometry
- Captures actual window contents, including windows on other workspaces
- Highlights the selected workspace with your theme accent
- Follows the focused monitor and stays clear of a bottom-positioned bar
- Adapts automatically when your Omarchy theme or display scale changes

## Install

```sh
omarchy plugin add https://github.com/pablopunk/omarchy-workspace-preview.git --enable
```

That is all. Switch workspaces normally and the preview will appear near the bottom of the focused display.

## Battery Friendly

Workspace Preview does not stream window contents.

It captures one small still frame per visible window when the overlay opens, displays it briefly, then releases every capture source when the overlay closes. Rapid workspace changes are debounced, and the plugin performs no capture work while hidden.

## Configure

The defaults live near the top of `WorkspacePreview.qml`:

| Setting | Default | Purpose |
| --- | ---: | --- |
| `duration` | `1300` | Time the preview remains visible, in milliseconds |
| `cardWidth` | `112` | Preferred width of each workspace card |
| `cardGap` | `10` | Space between cards |
| `panelMargin` | `44` | Distance from the bottom edge |

After editing the installed plugin, reload the shell:

```sh
omarchy restart shell
```

You can also open the preview manually:

```sh
omarchy-shell workspace-preview open
```

## Requirements

- Omarchy Quattro
- Hyprland and Quickshell as provided by Omarchy

There are no external dependencies, privileged operations, background services, analytics, or network requests.

## Remove

```sh
omarchy plugin remove pol.workspace-preview
```

## License

[MIT](LICENSE)
