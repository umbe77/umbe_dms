import QtQuick
import Quickshell
import Quickshell.Io
import Quickshell.Hyprland
import qs.Common
import qs.Widgets
import qs.DCommon.Widgets
import qs.Modules.Plugins

PluginComponent {
    id: root

    // Settings
    readonly property string displayMode: pluginData.displayMode ?? "both"   // "both" | "icon" | "text"
    readonly property bool capitalize: pluginData.capitalize ?? true

    // Global fallback (general:layout), read once at startup
    property string globalLayout: ""

    // Set instantly by a "custom>>hyprlayout,<layout>" event, cleared once
    // the workspace's tiledLayout has caught up
    property string layoutOverride: ""

    // Monitor this bar lives on (falls back to the focused one)
    readonly property var monitor: (root.parentScreen ? Hyprland.monitorFor(root.parentScreen) : null) ?? Hyprland.focusedMonitor
    readonly property var workspace: monitor?.activeWorkspace ?? null

    readonly property string layout: {
        if (root.layoutOverride.length > 0)
            return root.layoutOverride;
        const ws = root.workspace?.lastIpcObject?.tiledLayout;
        if (ws && ws.length > 0)
            return ws;
        return root.globalLayout.length > 0 ? root.globalLayout : "?";
    }

    // Custom Lua layouts are reported as "lua:<name>"
    readonly property string layoutName: layout.replace(/^lua:/, "")

    readonly property string layoutLabel: capitalize && layoutName.length > 0
        ? layoutName.charAt(0).toUpperCase() + layoutName.slice(1)
        : layoutName

    readonly property string layoutIcon: {
        switch (layoutName) {
        case "dwindle": return "view_quilt";
        case "master": return "vertical_split";
        case "scrolling": return "view_column";
        case "monocle": return "fullscreen";
        default: return "dashboard";
        }
    }

    readonly property bool showIcon: displayMode !== "text"
    readonly property bool showText: displayMode !== "icon"

    function refresh() {
        Hyprland.refreshMonitors();
        Hyprland.refreshWorkspaces();
    }

    Component.onCompleted: {
        refresh();
        globalLayoutProc.running = true;
    }

    Process {
        id: globalLayoutProc
        command: ["hyprctl", "getoption", "general:layout", "-j"]
        stdout: StdioCollector {
            onStreamFinished: {
                try {
                    const obj = JSON.parse(text);
                    root.globalLayout = obj.str ?? "";
                } catch (e) {
                    root.globalLayout = "";
                }
            }
        }
    }

    Timer {
        id: overrideTimer
        interval: 300
        onTriggered: {
            root.refresh();
            root.layoutOverride = "";
        }
    }

    Connections {
        target: Hyprland
        function onRawEvent(event) {
            const n = event.name;
            if (n === "custom") {
                const data = String(event.data ?? "");
                if (data.startsWith("hyprlayout,")) {
                    const value = data.slice("hyprlayout,".length).trim();
                    if (value.length > 0) {
                        root.layoutOverride = value;
                        root.globalLayout = value;
                        root.refresh();
                        overrideTimer.restart();
                    }
                }
                return;
            }
            if (n.startsWith("workspace") || n.startsWith("focusedmon") || n.startsWith("moveworkspace")
                || n.startsWith("createworkspace") || n.startsWith("destroyworkspace")
                || n === "openwindow" || n === "closewindow" || n === "configreloaded") {
                root.refresh();
                if (n === "configreloaded")
                    globalLayoutProc.running = true;
            }
        }
    }

    horizontalBarPill: Component {
        Item {
            implicitWidth: hRow.implicitWidth
            implicitHeight: hRow.implicitHeight
            Accessible.name: "Layout: " + root.layout

            Row {
                id: hRow
                spacing: Theme.spacingXS

                DIcon {
                    name: root.layoutIcon
                    size: Math.round(root.iconSize * 1.25)
                    color: Theme.surfaceText
                    visible: root.showIcon
                    anchors.verticalCenter: parent.verticalCenter
                }

                StyledText {
                    text: root.layoutLabel
                    font.pixelSize: root.textSize
                    color: Theme.surfaceText
                    visible: root.showText
                    anchors.verticalCenter: parent.verticalCenter
                }
            }
        }
    }

    verticalBarPill: Component {
        Item {
            implicitWidth: vCol.implicitWidth
            implicitHeight: vCol.implicitHeight
            Accessible.name: "Layout: " + root.layout

            Column {
                id: vCol
                spacing: Theme.spacingXS

                DIcon {
                    name: root.layoutIcon
                    size: Math.round(root.iconSize * 1.25)
                    color: Theme.surfaceText
                    visible: root.showIcon
                    anchors.horizontalCenter: parent.horizontalCenter
                }

                StyledText {
                    text: root.layoutLabel.slice(0, 3)
                    font.pixelSize: root.textSize
                    color: Theme.surfaceText
                    visible: root.displayMode === "text"
                    anchors.horizontalCenter: parent.horizontalCenter
                }
            }
        }
    }
}
