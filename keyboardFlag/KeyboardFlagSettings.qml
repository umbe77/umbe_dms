import QtQuick
import qs.Common
import qs.Widgets
import qs.Modules.Plugins

PluginSettings {
    id: root
    pluginId: "keyboardFlag"

    StyledText {
        width: parent.width
        text: "Keyboard Layout Flag"
        font.pixelSize: Theme.fontSizeLarge
        font.weight: Font.Bold
        color: Theme.surfaceText
    }

    StyledText {
        width: parent.width
        text: "Shows the current keyboard layout with its country flag. Click the pill to switch layout."
        font.pixelSize: Theme.fontSizeSmall
        color: Theme.surfaceVariantText
        wrapMode: Text.WordWrap
    }

    SelectionSetting {
        settingKey: "displayMode"
        label: "Display"
        description: "What the bar pill shows"
        options: [
            { label: "Flag + text", value: "both" },
            { label: "Flag only", value: "flag" },
            { label: "Text only", value: "text" }
        ]
        defaultValue: "both"
    }

    SelectionSetting {
        settingKey: "labelStyle"
        label: "Label"
        description: "Layout code (US) or full keymap name (English (US))"
        options: [
            { label: "Code", value: "code" },
            { label: "Full name", value: "name" }
        ]
        defaultValue: "code"
    }
}
