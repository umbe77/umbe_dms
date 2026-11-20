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
        text: "Shows the tiling layout of the active workspace on this bar's monitor."
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
}
