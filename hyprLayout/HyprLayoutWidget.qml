import QtQuick
import Quickshell
import Quickshell.Io
import Quickshell.Wayland
import Quickshell.Hyprland
import qs.Common
import qs.Services
import qs.Widgets
import qs.DCommon.Widgets
import qs.Modules.Plugins

PluginComponent {
    id: root

    // Settings
    readonly property string displayMode: pluginData.displayMode ?? "both"   // "both" | "icon" | "text"
    readonly property bool capitalize: pluginData.capitalize ?? true
    readonly property string extraLayouts: pluginData.extraLayouts ?? ""   // comma-separated, e.g. "lua:foo"

    // Hyprland has no request that lists layouts, so start from the built-ins
    readonly property var builtinLayouts: ["dwindle", "master", "scrolling", "monocle"]
    readonly property var availableLayouts: {
        const list = root.builtinLayouts.slice();
        for (const raw of root.extraLayouts.split(",")) {
            const name = raw.trim();
            if (name.length > 0 && !list.includes(name))
                list.push(name);
        }
        return list;
    }

    // Picker state
    property bool shown: false
    property var screen: null
    property string query: ""
    property int selectedIndex: 0

    readonly property var filteredLayouts: {
        const q = root.query.trim();
        if (q.length === 0)
            return root.availableLayouts;
        return root.availableLayouts
            .map((name, i) => ({ name: name, i: i, score: root.fuzzyScore(q, name) }))
            .filter(x => x.score >= 0)
            .sort((a, b) => b.score - a.score || a.i - b.i)
            .map(x => x.name);
    }

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

    readonly property string layoutLabel: root.labelFor(root.layout)
    readonly property string layoutIcon: root.iconFor(root.layout)

    readonly property bool showIcon: displayMode !== "text"
    readonly property bool showText: displayMode !== "icon"

    // Custom Lua layouts are reported as "lua:<name>"
    function labelFor(name) {
        const n = String(name).replace(/^lua:/, "");
        return root.capitalize && n.length > 0 ? n.charAt(0).toUpperCase() + n.slice(1) : n;
    }

    function iconFor(name) {
        switch (String(name).replace(/^lua:/, "")) {
        case "dwindle": return "view_quilt";
        case "master": return "vertical_split";
        case "scrolling": return "view_column";
        case "monocle": return "fullscreen";
        default: return "dashboard";
        }
    }

    // Case-insensitive subsequence match; -1 when it does not match. Rewards a
    // prefix match, runs of consecutive chars and chars at word starts.
    function fuzzyScore(query, text) {
        const q = query.toLowerCase();
        const t = String(text).toLowerCase();
        let score = t.startsWith(q) ? 100 : 0;
        let ti = 0;
        let prev = -2;
        for (let qi = 0; qi < q.length; qi++) {
            const c = q.charAt(qi);
            if (c === " ")
                continue;
            const at = t.indexOf(c, ti);
            if (at < 0)
                return -1;
            score += 1;
            if (at === prev + 1)
                score += 5;
            if (at === 0 || ":-_ ".includes(t.charAt(at - 1)))
                score += 8;
            score -= Math.min(at - ti, 5);   // gaps cost a little
            prev = at;
            ti = at + 1;
        }
        return score;
    }

    // Keybinds go through IPC, which only one bar's instance receives: open on
    // the focused monitor rather than on that instance's bar
    function focusedScreen() {
        return CompositorService.getFocusedScreen?.() ?? null;
    }

    function open(screen) {
        root.screen = screen ?? root.parentScreen ?? (Quickshell.screens.length > 0 ? Quickshell.screens[0] : null);
        root.query = "";
        root.selectedIndex = Math.max(0, root.availableLayouts.indexOf(root.layout));
        root.shown = true;
        return "opened";
    }

    function close() {
        root.shown = false;
        return "closed";
    }

    function toggle(screen) {
        return root.shown ? root.close() : root.open(screen);
    }

    function moveSelection(delta) {
        const n = root.filteredLayouts.length;
        if (n === 0)
            return;
        root.selectedIndex = (root.selectedIndex + delta + n) % n;
    }

    function applySelected() {
        const name = root.filteredLayouts[root.selectedIndex];
        return name ? root.setLayout(name) : "nothing";
    }

    function setLayout(name) {
        name = String(name ?? "").trim();
        // Interpolated into a Lua string below
        if (!/^[A-Za-z0-9_:.\-]+$/.test(name))
            return "invalid layout: " + name;
        root.close();
        root.layoutOverride = name;
        overrideTimer.restart();
        // Same as the SUPER+SHIFT+M bind: set the global layout, then emit the
        // event that every bar's widget listens for (hl.config emits none)
        setLayoutProc.command = ["hyprctl", "eval",
            `hl.config({ general = { layout = "${name}" } }); hl.dispatch(hl.dsp.event("hyprlayout,${name}"))`];
        setLayoutProc.running = true;
        return "layout " + name;
    }

    pillClickAction: () => root.toggle()

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

    Process {
        id: setLayoutProc
        stdout: StdioCollector {
            onStreamFinished: {
                // hyprctl eval prints "ok" on success, the Lua error otherwise
                const out = text.trim();
                if (out.length > 0 && out !== "ok")
                    console.warn("hyprLayout: hyprctl eval:", out);
            }
        }
        onExited: code => {
            if (code !== 0)
                console.warn("hyprLayout: hyprctl eval exited with code", code);
        }
    }

    IpcHandler {
        target: "hyprLayout"

        function toggle(): string {
            return root.toggle(root.focusedScreen());
        }

        function open(): string {
            return root.open(root.focusedScreen());
        }

        function close(): string {
            return root.close();
        }

        function list(): string {
            return root.availableLayouts.join(",");
        }

        function set(name: string): string {
            return root.setLayout(name);
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

    // ---- layout picker ------------------------------------------------------

    Loader {
        active: root.shown && !!root.screen

        sourceComponent: PanelWindow {
            id: win

            screen: root.screen
            color: "transparent"

            WlrLayershell.namespace: "dms:hypr-layout"
            WlrLayershell.layer: WlrLayer.Overlay
            WlrLayershell.exclusiveZone: -1
            WlrLayershell.keyboardFocus: WlrKeyboardFocus.Exclusive

            anchors {
                top: true
                left: true
                right: true
                bottom: true
            }

            // Scrim; clicking outside the panel closes
            Rectangle {
                anchors.fill: parent
                color: Theme.withAlpha("#000000", 0.3)

                MouseArea {
                    anchors.fill: parent
                    onClicked: root.close()
                }
            }

            // Receives every key from the search field first (Keys.forwardTo);
            // keys it does not accept fall through to the text input
            Item {
                id: keyHandler

                Keys.onPressed: event => {
                    const ctrl = (event.modifiers & Qt.ControlModifier) !== 0;
                    if (event.key === Qt.Key_Down || (ctrl && (event.key === Qt.Key_J || event.key === Qt.Key_N))) {
                        root.moveSelection(1);
                    } else if (event.key === Qt.Key_Up || (ctrl && (event.key === Qt.Key_K || event.key === Qt.Key_P))) {
                        root.moveSelection(-1);
                    } else if (event.key === Qt.Key_Return || event.key === Qt.Key_Enter) {
                        root.applySelected();
                    } else if (event.key === Qt.Key_Escape) {
                        root.close();
                    } else {
                        event.accepted = false;
                        return;
                    }
                    event.accepted = true;
                }
            }

            Rectangle {
                id: panel

                readonly property real pad: Theme.spacingL
                readonly property real rowHeight: Math.round(Theme.fontSizeMedium * 2.6)

                anchors.centerIn: parent
                width: Math.min(420, win.width * 0.8)
                height: pad * 2 + search.height + Theme.spacingM
                    + Math.min(Math.max(list.contentHeight, rowHeight), win.height * 0.6)
                radius: Theme.cornerRadius * 1.5
                color: Theme.withAlpha(Theme.surfaceContainer, 0.97)
                border.color: Theme.withAlpha(Theme.outline, 0.3)
                border.width: 1

                // Swallow clicks on the panel background
                MouseArea {
                    anchors.fill: parent
                }

                DTextField {
                    id: search

                    anchors.top: parent.top
                    anchors.left: parent.left
                    anchors.right: parent.right
                    anchors.margins: panel.pad

                    leftIconName: "search"
                    placeholderText: "Search layouts…"
                    keyForwardTargets: [keyHandler]
                    Accessible.name: "Search layouts"

                    onTextEdited: {
                        root.query = search.text;
                        root.selectedIndex = 0;
                    }

                    Component.onCompleted: Qt.callLater(() => search.forceActiveFocus())
                }

                ListView {
                    id: list

                    anchors.top: search.bottom
                    anchors.topMargin: Theme.spacingM
                    anchors.left: parent.left
                    anchors.right: parent.right
                    anchors.bottom: parent.bottom
                    anchors.leftMargin: panel.pad
                    anchors.rightMargin: panel.pad
                    anchors.bottomMargin: panel.pad

                    clip: true
                    spacing: 2
                    model: root.filteredLayouts
                    currentIndex: root.selectedIndex
                    boundsBehavior: Flickable.StopAtBounds
                    highlightMoveDuration: 0

                    delegate: Rectangle {
                        id: row

                        required property string modelData
                        required property int index
                        readonly property bool selected: row.index === root.selectedIndex
                        readonly property bool current: row.modelData === root.layout

                        width: ListView.view.width
                        height: panel.rowHeight
                        radius: Theme.cornerRadius
                        color: row.selected ? Theme.withAlpha(Theme.primary, 0.16) : "transparent"
                        Accessible.role: Accessible.ListItem
                        Accessible.name: root.labelFor(row.modelData) + (row.current ? " (current)" : "")

                        DIcon {
                            id: rowIcon
                            anchors.left: parent.left
                            anchors.leftMargin: Theme.spacingM
                            anchors.verticalCenter: parent.verticalCenter
                            name: root.iconFor(row.modelData)
                            size: Theme.iconSize
                            color: row.selected ? Theme.primary : Theme.surfaceText
                        }

                        StyledText {
                            anchors.left: rowIcon.right
                            anchors.leftMargin: Theme.spacingM
                            anchors.right: check.left
                            anchors.verticalCenter: parent.verticalCenter
                            text: root.labelFor(row.modelData)
                            font.pixelSize: Theme.fontSizeMedium
                            color: row.selected ? Theme.primary : Theme.surfaceText
                            elide: Text.ElideRight
                        }

                        DIcon {
                            id: check
                            anchors.right: parent.right
                            anchors.rightMargin: Theme.spacingM
                            anchors.verticalCenter: parent.verticalCenter
                            name: "check"
                            size: Theme.iconSize
                            color: Theme.primary
                            visible: row.current
                        }

                        MouseArea {
                            anchors.fill: parent
                            hoverEnabled: true
                            cursorShape: Qt.PointingHandCursor
                            onEntered: root.selectedIndex = row.index
                            onClicked: root.setLayout(row.modelData)
                        }
                    }

                    StyledText {
                        anchors.centerIn: parent
                        visible: list.count === 0
                        text: "No matching layout"
                        font.pixelSize: Theme.fontSizeMedium
                        color: Theme.surfaceVariantText
                    }
                }
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
