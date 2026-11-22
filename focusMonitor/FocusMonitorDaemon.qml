import QtQuick
import Quickshell
import Quickshell.Io
import Quickshell.Wayland
import Quickshell.Hyprland
import qs.Common
import qs.Modules.Plugins

PluginComponent {
    id: root

    // Settings
    readonly property int holdMs: pluginData.holdMs ?? 800
    readonly property int fadeMs: pluginData.fadeMs ?? 300
    readonly property real dimOpacity: (pluginData.dimOpacity ?? 40) / 100
    readonly property int frameWidth: pluginData.frameWidth ?? 6
    readonly property bool keepDimmed: pluginData.keepDimmed ?? false
    readonly property bool singleMonitor: pluginData.singleMonitor ?? false

    // State
    // 0..1, drives the frame and the flash dim
    property real flash: 0
    property bool flashing: false
    // Session override from IPC toggleDim(); null follows the setting
    property var dimOverride: null
    readonly property bool dimOn: root.dimOverride ?? root.keepDimmed
    // Hyprland sets focusedMonitor once at startup; don't flash for that
    property bool ready: false

    Component.onCompleted: Qt.callLater(() => root.ready = true)

    function flashNow() {
        root.flashing = true;
        // Restarting picks up from the current value, so quick focus changes
        // extend the flash instead of stacking
        flashAnim.restart();
    }

    Connections {
        target: Hyprland
        function onFocusedMonitorChanged() {
            if (!root.ready || !Hyprland.focusedMonitor)
                return;
            if (ShellLayout.realScreens.length < 2 && !root.singleMonitor)
                return;
            root.flashNow();
        }
    }

    SequentialAnimation {
        id: flashAnim
        NumberAnimation {
            target: root
            property: "flash"
            to: 1
            duration: 120
            easing.type: Easing.OutQuad
        }
        PauseAnimation {
            duration: root.holdMs
        }
        NumberAnimation {
            target: root
            property: "flash"
            to: 0
            duration: root.fadeMs
            easing.type: Easing.InQuad
        }
        ScriptAction {
            script: root.flashing = false
        }
    }

    IpcHandler {
        target: "focusMonitor"

        function flash(): string {
            root.flashNow();
            return "flashed";
        }

        function toggleDim(): string {
            root.dimOverride = !root.dimOn;
            return root.dimOn ? "dim on" : "dim off";
        }

        function status(): string {
            return JSON.stringify({
                focused: Hyprland.focusedMonitor?.name ?? null,
                flashing: root.flashing,
                keepDimmed: root.dimOn
            });
        }
    }

    // ---- overlay ------------------------------------------------------------

    Loader {
        active: root.flashing || root.dimOn

        sourceComponent: Variants {
            model: ShellLayout.realScreens

            PanelWindow {
                id: win
                required property var modelData
                readonly property HyprlandMonitor monitor: Hyprland.monitorFor(win.modelData)
                readonly property bool isFocused: !!win.monitor && Hyprland.focusedMonitor === win.monitor

                screen: win.modelData
                color: "transparent"

                WlrLayershell.namespace: "dms:focus-monitor"
                WlrLayershell.layer: WlrLayer.Overlay
                WlrLayershell.exclusiveZone: -1
                WlrLayershell.keyboardFocus: WlrKeyboardFocus.None

                anchors {
                    top: true
                    left: true
                    right: true
                    bottom: true
                }

                // Click-through: empty input region
                mask: Region {}

                // Dim on the monitors without focus
                Rectangle {
                    anchors.fill: parent
                    color: "black"
                    opacity: win.isFocused ? 0 : (root.dimOn ? root.dimOpacity : root.dimOpacity * root.flash)
                    // Smooth the persistent dim as it moves between monitors;
                    // during a flash the opacity already follows `flash`
                    Behavior on opacity {
                        enabled: root.dimOn
                        NumberAnimation { duration: 150 }
                    }
                }

                // Accent frame on the focused monitor
                Rectangle {
                    anchors.fill: parent
                    visible: win.isFocused
                    color: "transparent"
                    border.width: root.frameWidth
                    border.color: Theme.primary
                    opacity: root.flash
                }
            }
        }
    }
}
