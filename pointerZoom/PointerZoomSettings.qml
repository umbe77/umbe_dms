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
        text: "Zoom the monitor under the mouse pointer with SUPER+SHIFT + wheel. Starting a zoom "
            + "dims the monitor and closes a circle on the pointer; the spotlight follows the pointer until the zoom is back to 1x.\n\n"
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
        text: "dms keybinds set hyprland \"SUPER SHIFT + mouse_up\" \"exec dms ipc call pointerZoom zoomIn\" --desc \"Zoom in\"\n"
            + "dms keybinds set hyprland \"SUPER SHIFT + mouse_down\" \"exec dms ipc call pointerZoom zoomOut\" --desc \"Zoom out\"\n"
            + "dms keybinds set hyprland \"SUPER SHIFT + Shift_L\" \"exec dms ipc call pointerZoom reset\" --flags rt --desc \"Reset zoom on release\"\n"
            + "dms keybinds set hyprland \"SUPER SHIFT + Super_L\" \"exec dms ipc call pointerZoom reset\" --flags rt --desc \"Reset zoom on release\""
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
        description: "How dark the monitor gets while the circle closes in"
        defaultValue: 50
        minimum: 10
        maximum: 95
        unit: "%"
    }

    SliderSetting {
        settingKey: "zoomedDim"
        label: "Dimming while zoomed"
        description: "How dark the monitor stays around the pointer while zoomed"
        defaultValue: 50
        minimum: 0
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
        description: "Disc radius while zoomed (stays the same size at every zoom level)"
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
