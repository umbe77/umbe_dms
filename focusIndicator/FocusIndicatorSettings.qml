import QtQuick
import qs.Common
import qs.Widgets
import qs.Modules.Plugins

PluginSettings {
    id: root
    pluginId: "focusIndicator"

    StyledText {
        width: parent.width
        text: "Focus Indicator"
        font.pixelSize: Theme.fontSizeLarge
        font.weight: Font.Bold
        color: Theme.surfaceText
    }

    StyledText {
        width: parent.width
        text: "Shows this bar's monitor. On the bar of the focused monitor it is drawn "
            + "in the accent color; on the other bars it is dimmed (or hidden)."
        font.pixelSize: Theme.fontSizeSmall
        color: Theme.surfaceVariantText
        wrapMode: Text.WordWrap
    }

    SelectionSetting {
        settingKey: "displayMode"
        label: "Display"
        description: "What the bar pill shows"
        options: [
            { label: "Icon only", value: "icon" },
            { label: "Icon + monitor name", value: "both" },
            { label: "Monitor name only", value: "text" }
        ]
        defaultValue: "icon"
    }

    ToggleSetting {
        settingKey: "hideInactive"
        label: "Hide on unfocused monitors"
        description: "Show the indicator only on the bar of the focused monitor"
        defaultValue: false
    }
}
