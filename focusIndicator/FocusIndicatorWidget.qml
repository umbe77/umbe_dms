import QtQuick
import Quickshell
import Quickshell.Hyprland
import qs.Common
import qs.Widgets
import qs.DCommon.Widgets
import qs.Modules.Plugins

PluginComponent {
    id: root

    // Settings
    readonly property string displayMode: pluginData.displayMode ?? "icon"   // "both" | "icon" | "text"
    readonly property bool hideInactive: pluginData.hideInactive ?? false

    // Monitor this bar lives on
    readonly property var monitor: root.parentScreen ? Hyprland.monitorFor(root.parentScreen) : null
    readonly property bool isFocused: !!root.monitor && Hyprland.focusedMonitor === root.monitor
    readonly property string monitorName: root.monitor?.name ?? root.parentScreen?.name ?? "?"

    readonly property color tint: root.isFocused ? Theme.primary : Theme.surfaceVariantText
    readonly property real fade: root.isFocused ? 1 : (root.hideInactive ? 0 : 0.45)
    readonly property string iconName: root.isFocused ? "radio_button_checked" : "radio_button_unchecked"
    readonly property string a11y: root.monitorName + (root.isFocused ? ": focused" : ": not focused")

    readonly property bool showIcon: root.displayMode !== "text"
    readonly property bool showText: root.displayMode !== "icon"

    horizontalBarPill: Component {
        Item {
            implicitWidth: hRow.implicitWidth
            implicitHeight: hRow.implicitHeight
            opacity: root.fade
            Accessible.name: root.a11y
            Behavior on opacity { NumberAnimation { duration: 150 } }

            Row {
                id: hRow
                spacing: Theme.spacingXS

                DIcon {
                    name: root.iconName
                    size: root.iconSize
                    color: root.tint
                    visible: root.showIcon
                    anchors.verticalCenter: parent.verticalCenter
                }

                StyledText {
                    text: root.monitorName
                    font.pixelSize: root.textSize
                    font.weight: root.isFocused ? Font.Bold : Font.Normal
                    color: root.tint
                    visible: root.showText
                    anchors.verticalCenter: parent.verticalCenter
                }
            }
        }
    }

    verticalBarPill: Component {
        Item {
            implicitWidth: vIcon.implicitWidth
            implicitHeight: vIcon.implicitHeight
            opacity: root.fade
            Accessible.name: root.a11y
            Behavior on opacity { NumberAnimation { duration: 150 } }

            // Monitor names don't fit a vertical bar, so always the icon
            DIcon {
                id: vIcon
                name: root.iconName
                size: root.iconSize
                color: root.tint
                anchors.centerIn: parent
            }
        }
    }
}
