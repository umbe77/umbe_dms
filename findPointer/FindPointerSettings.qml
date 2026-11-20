import QtQuick
import qs.Common
import qs.Widgets
import qs.Modules.Plugins

PluginSettings {
    id: root
    pluginId: "findPointer"

    StyledText {
        width: parent.width
        text: "Find Pointer"
        font.pixelSize: Theme.fontSizeLarge
        font.weight: Font.Bold
        color: Theme.surfaceText
    }

    StyledText {
        width: parent.width
        text: "Double-tap Ctrl to dim every monitor and spotlight the mouse pointer. "
            + "Clicks pass through to the apps below; press ESC (or double-tap Ctrl again) to close it.\n\n"
            + "Bind it in Settings → Keybinds: key CTRL + Control_L, action "
            + "\"exec dms ipc call findPointer tap\", with the release flag. Or from a terminal:"
        font.pixelSize: Theme.fontSizeSmall
        color: Theme.surfaceVariantText
        wrapMode: Text.WordWrap
    }

    TextEdit {
        width: parent.width
        readOnly: true
        selectByMouse: true
        wrapMode: TextEdit.WrapAnywhere
        text: "dms keybinds set hyprland \"CTRL + Control_L\" \"exec dms ipc call findPointer tap\" --flags r --desc \"Find pointer\""
        font.family: "monospace"
        font.pixelSize: Theme.fontSizeSmall
        color: Theme.surfaceText
        selectionColor: Theme.primary
        selectedTextColor: Theme.onPrimary
    }

    SliderSetting {
        settingKey: "doubleTapMs"
        label: "Double-tap window"
        description: "Maximum time between the two Ctrl taps"
        defaultValue: 350
        minimum: 150
        maximum: 800
        unit: "ms"
    }

    SliderSetting {
        settingKey: "dimOpacity"
        label: "Dimming"
        description: "How dark the screens get"
        defaultValue: 60
        minimum: 10
        maximum: 95
        unit: "%"
    }

    SliderSetting {
        settingKey: "startRadius"
        label: "Start radius"
        description: "Circle radius when the animation starts"
        defaultValue: 600
        minimum: 100
        maximum: 1500
        unit: "px"
    }

    SliderSetting {
        settingKey: "endRadius"
        label: "End radius"
        description: "Circle radius once the animation stops"
        defaultValue: 70
        minimum: 20
        maximum: 300
        unit: "px"
    }

    SliderSetting {
        settingKey: "durationMs"
        label: "Animation duration"
        defaultValue: 700
        minimum: 100
        maximum: 2000
        unit: "ms"
    }

    ToggleSetting {
        settingKey: "showRing"
        label: "Accent ring"
        description: "Draw a ring in the accent color around the clear disc"
        defaultValue: true
    }
}
