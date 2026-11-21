# umbe DMS plugins

DankMaterialShell (2.x) bar widgets. Each subdirectory is one plugin.

| Directory       | Plugin               | What it shows                                        |
|-----------------|----------------------|------------------------------------------------------|
| `hyprLayout/`   | Hyprland Layout      | Tiling layout of the workspace on each bar's monitor |
| `keyboardFlag/` | Keyboard Layout Flag | Current keyboard layout with its country flag        |
| `findPointer/`  | Find Pointer         | Double-tap Ctrl to spotlight the mouse pointer (daemon) |
| `windowSwitcher/` | Window Switcher    | Alt+Tab between the windows of the current workspace (daemon) |
| `dockerStacks/` | Docker Stacks        | Running container count; click to manage containers by compose project |

## Install

```sh
./install.sh                    # symlink every plugin into ~/.config/dms/plugins/<id>
./install.sh keyboardFlag       # just one
./install.sh --uninstall        # remove all (or name some)
```

Then restart DMS (`dms restart`), enable the plugins in Settings → Plugins and add
the widgets to a bar section.

---

## Hyprland Layout (`hyprLayout`)

Shows the tiling layout (`dwindle`, `master`, `scrolling`, `monocle`, …) of the
workspace that is active on each bar's monitor. It reads Hyprland's per-workspace
`tiledLayout` and updates on workspace/monitor focus changes and config reloads.

### Settings

- **Display**: icon + text, icon only, or text only
- **Capitalize name**

### Instant updates

Changing the layout at runtime with `hl.config({ general = { layout = ... } })`
does not emit any socket2 event, so the widget can't notice it on its own.
Add this line to your layout-switch bind, after the `hl.config` call:

```lua
hl.dispatch(hl.dsp.event("hyprlayout," .. next_layout))
```

The widget listens for `custom>>hyprlayout,<layout>` and updates immediately.

---

## Keyboard Layout Flag (`keyboardFlag`)

Like DMS's built-in keyboard layout widget, but with the country flag:
`🇺🇸 US`, `🇮🇹 IT`, … Clicking the pill switches to the next layout.

It uses DMS's own `KeyboardLayoutService`, so it works on Hyprland, niri, sway and
MangoWC. The flag is derived from the xkb layout code (`it` → 🇮🇹, `gb` → 🇬🇧,
`latam` → 🇲🇽, …); layouts without a country (e.g. `epo`) show a keyboard icon.

Flags need a color emoji font (`noto-fonts-emoji`).

### Settings

- **Display**: flag + text, flag only, or text only
- **Label**: layout code (`US`) or full keymap name (`English (US)`)

---

## Find Pointer (`findPointer`)

A daemon (no bar widget). Double-tap Ctrl and every monitor dims, leaving a clear
disc around the mouse pointer that shrinks from large to small. Once the animation
ends, the dimming and the disc stay and follow the pointer, across monitors too,
until you press **ESC** (or double-tap Ctrl again). Clicks pass through to the apps
below. Hyprland only.

The pointer position is read from Hyprland's request socket (`j/cursorpos`) about 60
times a second, only while the overlay is shown. If the socket keeps failing, it
falls back to `hyprctl cursorpos -j`.

### Keybind

DMS plugins can't register keys themselves, so bind the plugin's IPC call the DMS way:
in Settings → Keybinds add `CTRL + Control_L` with the action
`exec dms ipc call findPointer tap` and the **release** flag, or run:

```sh
dms keybinds set hyprland "CTRL + Control_L" "exec dms ipc call findPointer tap" --flags r --desc "Find pointer"
```

Each Ctrl release is one `tap`. Two taps inside the double-tap window open the
overlay, and a tap while it's open closes it.

IPC: `dms ipc call findPointer tap|show|hide|toggle|status`.

### Settings

- **Double-tap window** (ms)
- **Dimming** (%)
- **Start radius** / **End radius** (px)
- **Animation duration** (ms)
- **Accent ring** around the disc

---

## Window Switcher (`windowSwitcher`)

A daemon (no bar widget). Hold Alt and press Tab to cycle through the windows of the
**current workspace**, most recently used first. A row of live thumbnails is shown on
the focused monitor. Releasing Alt focuses the selected window. Hyprland only.

- **Alt+Tab** / **Alt+Shift+Tab**: next / previous window (the first press selects the previous window)
- **Release Alt**, **Enter** or a click on a thumbnail: switch to it
- **Esc** or a click outside the panel: cancel

A quick Alt+Tab switches straight to the previous window without the switcher flashing up
(see *Show delay*).

### Keybind

```sh
dms keybinds set hyprland "ALT + Tab"       "exec dms ipc call windowSwitcher next"   --desc "Window switcher"
dms keybinds set hyprland "ALT SHIFT + Tab" "exec dms ipc call windowSwitcher prev"   --desc "Window switcher (back)"
dms keybinds set hyprland "ALT + Alt_L"     "exec dms ipc call windowSwitcher commit" --flags rt --desc "Window switcher commit"
```

The third bind is what switches when you release Alt, so it's required. It needs both
flags: `r` (fire on release) and `t` (transparent). Without `t`, Hyprland skips the Alt
release bind because Tab was pressed while Alt was held. The switcher can't see the
release itself: Alt was already down when it took keyboard focus, so Hyprland never
sends that key's release to it.

IPC: `dms ipc call windowSwitcher next|prev|commit|cancel|status`.

### Settings

- **Thumbnail height** (px)
- **Show delay** (ms)
- **Window titles** under the thumbnails

---

## Docker Stacks (`dockerStacks`)

A bar pill that shows the Docker icon and the number of running containers. Click it to
open a window in the middle of the screen that lists every container, grouped by compose
project, with the containers that don't belong to a project under **Standalone**. Each
row shows the state, name, image, published ports and status, plus buttons for:

- **Start** (stopped containers), **Stop** and **Restart** (running containers)
- **Delete**: asks for confirmation on the row first, then runs `docker rm -f`

The header of each compose group can start, stop or restart the whole project, and a
click on it collapses or expands the group. The list updates live from `docker events`,
with a slower full refresh as a fallback. **Esc** or a click outside closes the window,
and **F5** refreshes it.

Your user needs access to the Docker socket (usually through the `docker` group). The
plugin id is `dockerStacks` so it doesn't clash with the third-party `dockerManager`
plugin.

IPC: `dms ipc call dockerStacks toggle|open|close|refresh|status`. These only work once
the widget is on a bar. `toggle` and `open` show the window on the focused monitor. Keybind
(`SUPER+D` is taken by the DMS dash):

```sh
dms keybinds set hyprland "SUPER+SHIFT+D" "exec dms ipc call dockerStacks toggle" --desc "Docker containers"
```

### Settings

- **Docker command**: the executable to run (`docker` by default)
- **Show running count** next to the icon
- **Show standalone containers**
- **Fallback refresh** interval (s)
