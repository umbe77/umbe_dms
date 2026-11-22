# AGENTS.md

Personal plugins for **DankMaterialShell (DMS) 2.x**, the Quickshell/QML desktop shell
(DUX shell). Every top-level directory that contains a `plugin.json` is one plugin.
User-facing docs (features, keybinds, settings) live in `README.md`.

## DUX shell / DMS docs

For documentation about the DUX shell and the DMS plugin API, use https://duxlabs.dev/docs/

## Layout

| Directory         | Type     | Entry component              | Compositor |
|-------------------|----------|------------------------------|------------|
| `hyprLayout/`     | `widget` | `HyprLayoutWidget.qml`       | Hyprland   |
| `keyboardFlag/`   | `widget` | `KeyboardFlagWidget.qml`     | any (uses `KeyboardLayoutService`) |
| `findPointer/`    | `daemon` | `FindPointerDaemon.qml`      | Hyprland   |
| `focusMonitor/`   | `daemon` | `FocusMonitorDaemon.qml`     | Hyprland   |
| `focusIndicator/` | `widget` | `FocusIndicatorWidget.qml`   | Hyprland   |
| `windowSwitcher/` | `daemon` | `WindowSwitcherDaemon.qml`   | Hyprland   |
| `dockerStacks/`   | `widget` | `DockerStacksWidget.qml`     | any (runs `docker`) |

Each plugin directory holds:

- `plugin.json`: manifest (`id`, `name`, `type`, `capabilities`, `component`,
  `settings`, `requires_dms`, `compositors`, `permissions`). The `id` is camelCase and
  matches the directory name; it is also the install link name and the IPC target.
- `<Name>Widget.qml` or `<Name>Daemon.qml`: root is a `PluginComponent`.
- `<Name>Settings.qml`: root is `PluginSettings` with `pluginId` set to the plugin id.

`install.sh` symlinks plugin directories into `~/.config/dms/plugins/<id>` (the
plugins installed here are already links into this repo, so edits take effect after
`dms restart`). There is no build step and no test suite.

## Conventions

- **Imports**: `QtQuick`, `Quickshell`, `Quickshell.Io` (Process, Socket, IpcHandler),
  `Quickshell.Wayland`, `Quickshell.Hyprland`, and DMS modules `qs.Common` (Theme),
  `qs.Services`, `qs.Widgets` (StyledText, ...), `qs.DCommon.Widgets` (DIcon),
  `qs.Modules.Plugins` (PluginComponent, PluginSettings, SelectionSetting, ...).
- **Settings**: read in the component as
  `readonly property <type> foo: pluginData.foo ?? <default>`, grouped under a
  `// Settings` comment. The same default must be used as `defaultValue` in the
  settings file. Keep the `settingKey` names identical in both files.
- **Bar widgets** provide both `horizontalBarPill` and `verticalBarPill` components,
  use `root.iconSize` / `root.textSize` and `Theme.*` for sizes, spacing and colors,
  and set `Accessible.name`. Clicks go through `pillClickAction`.
- **Daemons** have no bar UI. They expose an `IpcHandler { target: "<pluginId>" }`
  whose functions return a short status string, and are driven by DMS keybinds
  (`dms keybinds set hyprland ... "exec dms ipc call <id> <fn>"`), since plugins cannot
  register keys themselves. Overlays are `PanelWindow`s on `WlrLayer.Overlay` with
  `WlrLayershell.namespace: "dms:<kebab-name>"` and `exclusiveZone: -1`, created
  lazily (Loader) only while shown.
- **Hyprland**: prefer the `Quickshell.Hyprland` singleton (`Hyprland.monitorFor`,
  `focusedMonitor`, `toplevels`, `dispatch`, `rawEvent`, `refresh*()`); fall back to the
  request socket or `hyprctl ... -j` via `Process` only for data it does not expose
  (e.g. cursor position). A Quickshell `Socket` cannot redial, so use a fresh one per
  request and never destroy it from inside its own signal handler.
- Use `root.` for property references, `const` in JS, and short comments that explain
  *why* (Hyprland quirks, event gaps) rather than what.
- Any new permission or capability must be declared in `plugin.json`
  (`process` is needed to run external commands).

## Adding or changing a plugin

1. Create `<pluginId>/` with `plugin.json`, the component and the settings file,
   following an existing plugin of the same type.
2. Add it to the table and add a section in `README.md` (description, keybinds, IPC,
   settings).
3. Update the table in this file.
4. Test with `./install.sh <dir>`, `dms restart`, then enable it in
   Settings → Plugins. Check DMS logs (`journalctl --user -u dms -f`) for QML errors,
   and call IPC functions with `dms ipc call <id> <fn>`.

## Commits

Conventional-commit style subjects (`feat: ...`, `fix: ...`). Don't commit `*.qmlc` /
`*.jsc` caches (ignored).
