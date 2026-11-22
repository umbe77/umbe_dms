import QtQuick
import qs.Common
import qs.Widgets
import qs.Modules.Plugins

PluginSettings {
    id: root
    pluginId: "focusMonitor"

    StyledText {
        width: parent.width
        text: "Focus Monitor"
        font.pixelSize: Theme.fontSizeLarge
        font.weight: Font.Bold
        color: Theme.surfaceText
    }

    StyledText {
        width: parent.width
        text: "When focus moves to another monitor, it gets an accent frame "
            + "and the other monitors dim for a moment. Clicks pass through.\n\n"
            + "To show it on demand, bind \"exec dms ipc call focusMonitor flash\" in "
            + "Settings → Keybinds, or from a terminal:"
        font.pixelSize: Theme.fontSizeSmall
        color: Theme.surfaceVariantText
        wrapMode: Text.WordWrap
    }

    TextEdit {
        width: parent.width
        readOnly: true
        selectByMouse: true
        wrapMode: TextEdit.WrapAnywhere
        text: "dms keybinds set hyprland \"SUPER + grave\" \"exec dms ipc call focusMonitor flash\" --desc \"Show focused monitor\""
        font.family: "monospace"
        font.pixelSize: Theme.fontSizeSmall
        color: Theme.surfaceText
        selectionColor: Theme.primary
        selectedTextColor: Theme.onPrimary
    }

    SliderSetting {
        settingKey: "holdMs"
        label: "Hold time"
        description: "How long the indicator stays fully visible"
        defaultValue: 800
        minimum: 100
        maximum: 3000
        unit: "ms"
    }

    SliderSetting {
        settingKey: "fadeMs"
        label: "Fade out"
        defaultValue: 300
        minimum: 50
        maximum: 1500
        unit: "ms"
    }

    SliderSetting {
        settingKey: "dimOpacity"
        label: "Dimming"
        description: "How dark the inactive monitors get"
        defaultValue: 40
        minimum: 0
        maximum: 90
        unit: "%"
    }

    SliderSetting {
        settingKey: "frameWidth"
        label: "Frame width"
        defaultValue: 6
        minimum: 0
        maximum: 30
        unit: "px"
    }

    ToggleSetting {
        settingKey: "keepDimmed"
        label: "Keep inactive monitors dimmed"
        description: "Dim the monitors without focus all the time, not only during the flash"
        defaultValue: false
    }

    ToggleSetting {
        settingKey: "singleMonitor"
        label: "Flash with one monitor"
        description: "Also flash on focus changes when only one monitor is connected"
        defaultValue: false
    }
}
