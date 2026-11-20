import QtQuick
import qs.Common
import qs.Widgets
import qs.Modules.Plugins

PluginSettings {
    id: root
    pluginId: "windowSwitcher"

    StyledText {
        width: parent.width
        text: "Window Switcher"
        font.pixelSize: Theme.fontSizeLarge
        font.weight: Font.Bold
        color: Theme.surfaceText
    }

    StyledText {
        width: parent.width
        text: "Alt+Tab cycles the windows of the current workspace, most recently used first, "
            + "with live thumbnails. Releasing Alt focuses the selected window; Esc cancels.\n\n"
            + "Bind it in Settings → Keybinds. The third bind switches when Alt is released and needs "
            + "both the release and transparent flags (--flags rt). Or from a terminal:"
        font.pixelSize: Theme.fontSizeSmall
        color: Theme.surfaceVariantText
        wrapMode: Text.WordWrap
    }

    TextEdit {
        width: parent.width
        readOnly: true
        selectByMouse: true
        wrapMode: TextEdit.WrapAnywhere
        text: "dms keybinds set hyprland \"ALT + Tab\" \"exec dms ipc call windowSwitcher next\" --desc \"Window switcher\"\n"
            + "dms keybinds set hyprland \"ALT SHIFT + Tab\" \"exec dms ipc call windowSwitcher prev\" --desc \"Window switcher (back)\"\n"
            + "dms keybinds set hyprland \"ALT + Alt_L\" \"exec dms ipc call windowSwitcher commit\" --flags rt --desc \"Window switcher commit\""
        font.family: "monospace"
        font.pixelSize: Theme.fontSizeSmall
        color: Theme.surfaceText
        selectionColor: Theme.primary
        selectedTextColor: Theme.onPrimary
    }

    SliderSetting {
        settingKey: "thumbHeight"
        label: "Thumbnail height"
        description: "Tiles shrink automatically when they don't fit on screen"
        defaultValue: 160
        minimum: 80
        maximum: 400
        unit: "px"
    }

    SliderSetting {
        settingKey: "showDelayMs"
        label: "Show delay"
        description: "A quick Alt+Tab switches without showing the switcher"
        defaultValue: 120
        minimum: 0
        maximum: 500
        unit: "ms"
    }

    ToggleSetting {
        settingKey: "showTitles"
        label: "Window titles"
        description: "Show the window title under each thumbnail"
        defaultValue: true
    }
}
