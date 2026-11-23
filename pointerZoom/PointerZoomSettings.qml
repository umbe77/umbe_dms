import QtQuick
import qs.Common
import qs.Widgets
import qs.Modules.Plugins

PluginSettings {
    id: root
    pluginId: "pointerZoom"

    StyledText {
        width: parent.width
        text: "Pointer Zoom"
        font.pixelSize: Theme.fontSizeLarge
        font.weight: Font.Bold
        color: Theme.surfaceText
    }

    StyledText {
        width: parent.width
        text: "Zoom the monitor under the mouse pointer with SUPER+ALT + wheel. Starting a zoom "
            + "dims the monitor and closes a circle on the pointer.\n\n"
            + "Bind it in Settings → Keybinds, or from a terminal:"
        font.pixelSize: Theme.fontSizeSmall
        color: Theme.surfaceVariantText
        wrapMode: Text.WordWrap
    }

    TextEdit {
        width: parent.width
        readOnly: true
        selectByMouse: true
        wrapMode: TextEdit.WrapAnywhere
        text: "dms keybinds set hyprland \"SUPER ALT + mouse_up\" \"exec dms ipc call pointerZoom zoomIn\" --desc \"Zoom in\"\n"
            + "dms keybinds set hyprland \"SUPER ALT + mouse_down\" \"exec dms ipc call pointerZoom zoomOut\" --desc \"Zoom out\"\n"
            + "dms keybinds set hyprland \"SUPER ALT + 0\" \"exec dms ipc call pointerZoom reset\" --desc \"Reset zoom\""
        font.family: "monospace"
        font.pixelSize: Theme.fontSizeSmall
        color: Theme.surfaceText
        selectionColor: Theme.primary
        selectedTextColor: Theme.onPrimary
    }

    SliderSetting {
        settingKey: "step"
        label: "Zoom step"
        description: "Zoom added per wheel notch (100% = +1x)"
        defaultValue: 100
        minimum: 10
        maximum: 200
        unit: "%"
    }

    SliderSetting {
        settingKey: "maxZoom"
        label: "Maximum zoom"
        defaultValue: 8
        minimum: 2
        maximum: 16
        unit: "x"
    }

    ToggleSetting {
        settingKey: "rigid"
        label: "Rigid zoom"
        description: "Keep the view fixed until the pointer reaches the edge, instead of following it"
        defaultValue: false
    }

    SliderSetting {
        settingKey: "dimOpacity"
        label: "Dimming"
        description: "How dark the monitor gets when a zoom starts"
        defaultValue: 50
        minimum: 10
        maximum: 95
        unit: "%"
    }

    SliderSetting {
        settingKey: "startRadius"
        label: "Start radius"
        description: "Circle radius when the animation starts"
        defaultValue: 500
        minimum: 100
        maximum: 1500
        unit: "px"
    }

    SliderSetting {
        settingKey: "endRadius"
        label: "End radius"
        description: "Circle radius when the zoom kicks in"
        defaultValue: 80
        minimum: 20
        maximum: 300
        unit: "px"
    }

    SliderSetting {
        settingKey: "durationMs"
        label: "Animation duration"
        defaultValue: 350
        minimum: 100
        maximum: 1500
        unit: "ms"
    }

    ToggleSetting {
        settingKey: "showRing"
        label: "Accent ring"
        description: "Draw a ring in the accent color around the clear disc"
        defaultValue: true
    }
}
