# umbe DMS plugins

DankMaterialShell (2.x) bar widgets. Each subdirectory is one plugin.

| Directory       | Plugin               | What it shows                                        |
|-----------------|----------------------|------------------------------------------------------|
| `hyprLayout/`   | Hyprland Layout      | Tiling layout of the workspace on each bar's monitor |
| `keyboardFlag/` | Keyboard Layout Flag | Current keyboard layout with its country flag        |

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
