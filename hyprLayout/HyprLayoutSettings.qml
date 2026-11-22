import QtQuick
import qs.Common
import qs.Widgets
import qs.Modules.Plugins

PluginSettings {
    id: root
    pluginId: "hyprLayout"

    StyledText {
        width: parent.width
        text: "Hyprland Layout"
        font.pixelSize: Theme.fontSizeLarge
        font.weight: Font.Bold
        color: Theme.surfaceText
    }

    StyledText {
        width: parent.width
        text: "Shows the tiling layout of the active workspace on this bar's monitor. Click it to switch layout."
        font.pixelSize: Theme.fontSizeSmall
        color: Theme.surfaceVariantText
        wrapMode: Text.WordWrap
    }

    SelectionSetting {
        settingKey: "displayMode"
        label: "Display"
        description: "What the bar pill shows"
        options: [
            { label: "Icon + text", value: "both" },
            { label: "Icon only", value: "icon" },
            { label: "Text only", value: "text" }
        ]
        defaultValue: "both"
    }

    ToggleSetting {
        settingKey: "capitalize"
        label: "Capitalize name"
        description: "Show \"Scrolling\" instead of \"scrolling\""
        defaultValue: true
    }

    StringSetting {
        settingKey: "extraLayouts"
        label: "Extra layouts"
        description: "Comma-separated layouts added to the click picker after the built-ins (e.g. lua:mylayout)"
        placeholder: "lua:mylayout"
        defaultValue: ""
    }
}
