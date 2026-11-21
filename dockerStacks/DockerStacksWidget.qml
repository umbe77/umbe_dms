import QtQuick
import Quickshell
import Quickshell.Io
import Quickshell.Wayland
import qs.Common
import qs.Services
import qs.Widgets
import qs.DCommon.Widgets
import qs.Modules.Plugins

PluginComponent {
    id: root

    // Settings
    readonly property string dockerBin: (pluginData.dockerBin ?? "docker") || "docker"
    readonly property bool showCount: pluginData.showCount ?? true
    readonly property bool showStandalone: pluginData.showStandalone ?? true
    readonly property int pollIntervalSec: pluginData.pollIntervalSec ?? 30

    // State
    property var containers: []        // [{ id, name, image, state, status, ports, project, service, workdir }]
    property string error: ""
    property bool loaded: false
    property bool shown: false
    property var screen: null
    property var busy: ({})            // container id -> true while an action runs
    property var collapsed: ({})       // group key -> true
    property string confirmDelete: ""  // container id awaiting delete confirmation

    readonly property int runningCount: root.containers.filter(c => c.state === "running").length

    // Compose projects sorted by name, then the standalone group
    readonly property var groups: {
        const byKey = {};
        for (const c of root.containers) {
            const key = c.project || "";
            if (key === "" && !root.showStandalone)
                continue;
            if (!byKey[key])
                byKey[key] = { key: key, name: key || "Standalone", workdir: c.workdir || "", containers: [] };
            byKey[key].containers.push(c);
        }
        const keys = Object.keys(byKey).filter(k => k !== "").sort((a, b) => a.localeCompare(b));
        if (byKey[""])
            keys.push("");
        return keys.map(k => {
            const g = byKey[k];
            g.containers.sort((a, b) => (a.service || a.name).localeCompare(b.service || b.name));
            g.running = g.containers.filter(c => c.state === "running").length;
            return g;
        });
    }

    // One JSON object per line. Labels are looked up one by one because the raw
    // Labels string is comma-joined and label values can contain commas.
    readonly property string psFormat: '{"id":{{json .ID}},"name":{{json .Names}},"image":{{json .Image}},'
        + '"state":{{json .State}},"status":{{json .Status}},"ports":{{json .Ports}},'
        + '"project":{{json (.Label "com.docker.compose.project")}},'
        + '"service":{{json (.Label "com.docker.compose.service")}},'
        + '"workdir":{{json (.Label "com.docker.compose.project.working_dir")}}}'

    // ---- helpers ------------------------------------------------------------

    // "0.0.0.0:8080->80/tcp, [::]:8080->80/tcp, 5432/tcp" -> "8080→80/tcp, 5432/tcp"
    function formatPorts(ports) {
        const seen = [];
        for (const raw of String(ports ?? "").split(",")) {
            let p = raw.trim();
            if (!p)
                continue;
            p = p.replace(/^(0\.0\.0\.0|\[::\]|::):/, "").replace("->", "→");
            if (!seen.includes(p))
                seen.push(p);
        }
        return seen.join(", ");
    }

    function stateColor(state) {
        switch (state) {
        case "running": return Theme.success;
        case "paused":
        case "restarting": return Theme.warning;
        case "dead": return Theme.error;
        default: return Theme.surfaceVariantText;
        }
    }

    function setBusy(ids, value) {
        const b = Object.assign({}, root.busy);
        for (const id of ids) {
            if (value)
                b[id] = true;
            else
                delete b[id];
        }
        root.busy = b;
    }

    function toggleCollapsed(key) {
        const c = Object.assign({}, root.collapsed);
        if (c[key])
            delete c[key];
        else
            c[key] = true;
        root.collapsed = c;
    }

    function notifyError(message, details) {
        if (typeof ToastService !== "undefined" && ToastService.showError)
            ToastService.showError(message, details ?? "");
        else
            root.error = message + (details ? ": " + details : "");
    }

    // ---- public actions -----------------------------------------------------

    function refresh() {
        if (listProc.running) {
            listProc.again = true;
            return;
        }
        listProc.out = "";
        listProc.err = "";
        listProc.pending = 0;
        listProc.running = true;
    }

    // verb: start | stop | restart | rm
    function act(verb, ids) {
        ids = (ids ?? []).filter(id => id && !root.busy[id]);
        if (ids.length === 0)
            return "nothing";
        const args = verb === "rm" ? ["rm", "-f"] : [verb];
        const proc = actionComponent.createObject(root, {
            verb: verb,
            ids: ids,
            command: [root.dockerBin].concat(args, ids)
        });
        root.setBusy(ids, true);
        proc.running = true;
        return verb + " " + ids.length;
    }

    function open(screen) {
        root.screen = screen ?? root.parentScreen ?? (Quickshell.screens.length > 0 ? Quickshell.screens[0] : null);
        root.confirmDelete = "";
        root.shown = true;
        root.refresh();
        return "opened";
    }

    function close() {
        root.shown = false;
        root.confirmDelete = "";
        return "closed";
    }

    function toggle(screen) {
        return root.shown ? root.close() : root.open(screen);
    }

    // Keybinds go through IPC, which only one bar's instance receives: open on
    // the focused monitor rather than on that instance's bar
    function focusedScreen() {
        return CompositorService.getFocusedScreen?.() ?? null;
    }

    pillClickAction: () => root.toggle()

    Component.onCompleted: root.refresh()

    // ---- docker processes ---------------------------------------------------

    Process {
        id: listProc

        property string out: ""
        property string err: ""
        property int code: 0
        property int pending: 0   // exit + 2 streams must all finish before parsing
        property bool again: false

        command: [root.dockerBin, "ps", "-a", "--no-trunc", "--format", root.psFormat]

        function step() {
            if (++listProc.pending < 3)
                return;
            if (listProc.code !== 0) {
                root.error = listProc.err.trim() || ("docker exited with code " + listProc.code);
                root.containers = [];
            } else {
                const list = [];
                for (const line of listProc.out.split("\n")) {
                    if (!line.trim())
                        continue;
                    try {
                        const c = JSON.parse(line);
                        c.ports = root.formatPorts(c.ports);
                        list.push(c);
                    } catch (e) {
                        console.warn("dockerStacks: cannot parse", line);
                    }
                }
                root.containers = list;
                root.error = "";
            }
            root.loaded = true;
            if (listProc.again) {
                listProc.again = false;
                Qt.callLater(root.refresh);
            }
        }

        stdout: StdioCollector {
            onStreamFinished: {
                listProc.out = text;
                listProc.step();
            }
        }
        stderr: StdioCollector {
            onStreamFinished: {
                listProc.err = text;
                listProc.step();
            }
        }
        onExited: exitCode => {
            listProc.code = exitCode;
            listProc.step();
        }
    }

    // Long-running event stream; every container event triggers a debounced refresh
    Process {
        id: eventsProc
        command: [root.dockerBin, "events", "--filter", "type=container", "--format", "{{.Action}}"]
        running: true
        stdout: SplitParser {
            onRead: debounce.restart()
        }
        // Dies when the docker daemon stops or restarts: retry later
        onExited: eventsRetry.restart()
    }

    Timer {
        id: eventsRetry
        interval: 5000
        onTriggered: {
            eventsProc.running = true;
            root.refresh();
        }
    }

    Timer {
        id: debounce
        interval: 400
        onTriggered: root.refresh()
    }

    Timer {
        interval: Math.max(5, root.pollIntervalSec) * 1000
        running: true
        repeat: true
        onTriggered: root.refresh()
    }

    Timer {
        id: confirmTimer
        interval: 4000
        onTriggered: root.confirmDelete = ""
    }

    onConfirmDeleteChanged: {
        if (root.confirmDelete)
            confirmTimer.restart();
        else
            confirmTimer.stop();
    }

    Component {
        id: actionComponent

        Process {
            id: proc

            property string verb: ""
            property var ids: []
            property string err: ""
            property int code: 0
            property int pending: 0

            function step() {
                if (++proc.pending < 2)
                    return;
                root.setBusy(proc.ids, false);
                if (proc.code !== 0)
                    root.notifyError("docker " + proc.verb + " failed", proc.err.trim());
                root.refresh();
                // Never destroy a Process from inside its own signal handler
                Qt.callLater(() => proc.destroy());
            }

            stderr: StdioCollector {
                onStreamFinished: {
                    proc.err = text;
                    proc.step();
                }
            }
            onExited: exitCode => {
                proc.code = exitCode;
                proc.step();
            }
        }
    }

    // ---- IPC ----------------------------------------------------------------

    IpcHandler {
        target: "dockerStacks"

        function toggle(): string {
            return root.toggle(root.focusedScreen());
        }

        function open(): string {
            return root.open(root.focusedScreen());
        }

        function close(): string {
            return root.close();
        }

        function refresh(): string {
            root.refresh();
            return "refreshing";
        }

        function status(): string {
            return JSON.stringify({
                shown: root.shown,
                running: root.runningCount,
                total: root.containers.length,
                groups: root.groups.map(g => ({ name: g.name, running: g.running, total: g.containers.length })),
                error: root.error
            });
        }
    }

    // ---- bar pill -----------------------------------------------------------

    horizontalBarPill: Component {
        Item {
            implicitWidth: hRow.implicitWidth
            implicitHeight: hRow.implicitHeight
            Accessible.name: "Docker: " + root.runningCount + " running"

            Row {
                id: hRow
                spacing: Theme.spacingXS

                DNFIcon {
                    name: "docker"
                    size: Math.round(root.iconSize * 1.1)
                    color: root.error ? Theme.error : Theme.surfaceText
                    anchors.verticalCenter: parent.verticalCenter
                }

                StyledText {
                    text: String(root.runningCount)
                    font.pixelSize: root.textSize
                    color: root.runningCount > 0 ? Theme.surfaceText : Theme.surfaceVariantText
                    visible: root.showCount && root.loaded
                    anchors.verticalCenter: parent.verticalCenter
                }
            }
        }
    }

    verticalBarPill: Component {
        Item {
            implicitWidth: vCol.implicitWidth
            implicitHeight: vCol.implicitHeight
            Accessible.name: "Docker: " + root.runningCount + " running"

            Column {
                id: vCol
                spacing: Theme.spacingXS

                DNFIcon {
                    name: "docker"
                    size: Math.round(root.iconSize * 1.1)
                    color: root.error ? Theme.error : Theme.surfaceText
                    anchors.horizontalCenter: parent.horizontalCenter
                }

                StyledText {
                    text: String(root.runningCount)
                    font.pixelSize: root.textSize
                    color: root.runningCount > 0 ? Theme.surfaceText : Theme.surfaceVariantText
                    visible: root.showCount && root.loaded
                    anchors.horizontalCenter: parent.horizontalCenter
                }
            }
        }
    }

    // ---- floating window ----------------------------------------------------

    Loader {
        active: root.shown && !!root.screen
        asynchronous: false

        sourceComponent: PanelWindow {
            id: win

            screen: root.screen
            color: "transparent"

            WlrLayershell.namespace: "dms:docker-stacks"
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

            FocusScope {
                id: keyScope
                anchors.fill: parent
                focus: true

                Keys.onPressed: event => {
                    if (event.key === Qt.Key_Escape) {
                        event.accepted = true;
                        if (root.confirmDelete)
                            root.confirmDelete = "";
                        else
                            root.close();
                    } else if (event.key === Qt.Key_F5 || (event.key === Qt.Key_R && (event.modifiers & Qt.ControlModifier))) {
                        event.accepted = true;
                        root.refresh();
                    }
                }

                Component.onCompleted: Qt.callLater(() => keyScope.forceActiveFocus())
            }

            Rectangle {
                id: panel

                readonly property real pad: Theme.spacingL

                anchors.centerIn: parent
                width: Math.min(960, win.width * 0.8)
                height: Math.min(header.height + Theme.spacingM + Math.max(body.contentHeight, 80) + pad * 2, win.height * 0.8)
                radius: Theme.cornerRadius * 1.5
                color: Theme.withAlpha(Theme.surfaceContainer, 0.97)
                border.color: Theme.withAlpha(Theme.outline, 0.3)
                border.width: 1

                // Swallow clicks on the panel background
                MouseArea {
                    anchors.fill: parent
                }

                // Header
                Item {
                    id: header
                    anchors.top: parent.top
                    anchors.left: parent.left
                    anchors.right: parent.right
                    anchors.margins: panel.pad
                    height: 36

                    Row {
                        anchors.left: parent.left
                        anchors.verticalCenter: parent.verticalCenter
                        spacing: Theme.spacingS

                        DNFIcon {
                            name: "docker"
                            size: Math.round(Theme.iconSize)
                            color: Theme.primary
                            anchors.verticalCenter: parent.verticalCenter
                        }

                        StyledText {
                            text: "Docker containers"
                            font.pixelSize: Theme.fontSizeLarge
                            font.weight: Font.Bold
                            color: Theme.surfaceText
                            anchors.verticalCenter: parent.verticalCenter
                        }

                        StyledText {
                            text: root.runningCount + " running / " + root.containers.length + " total"
                            font.pixelSize: Theme.fontSizeSmall
                            color: Theme.surfaceVariantText
                            anchors.verticalCenter: parent.verticalCenter
                        }
                    }

                    Row {
                        anchors.right: parent.right
                        anchors.verticalCenter: parent.verticalCenter
                        spacing: Theme.spacingXS

                        DSpinner {
                            size: 18
                            visible: listProc.running
                            anchors.verticalCenter: parent.verticalCenter
                        }

                        DIconButton {
                            iconName: "refresh"
                            tooltipText: "Refresh (F5)"
                            onClicked: root.refresh()
                        }

                        DIconButton {
                            iconName: "close"
                            tooltipText: "Close (Esc)"
                            onClicked: root.close()
                        }
                    }
                }

                Flickable {
                    id: body
                    anchors.top: header.bottom
                    anchors.topMargin: Theme.spacingM
                    anchors.left: parent.left
                    anchors.right: parent.right
                    anchors.bottom: parent.bottom
                    anchors.leftMargin: panel.pad
                    anchors.rightMargin: panel.pad
                    anchors.bottomMargin: panel.pad
                    contentHeight: groupsCol.implicitHeight
                    clip: true
                    boundsBehavior: Flickable.StopAtBounds

                    Column {
                        id: groupsCol
                        width: body.width
                        spacing: Theme.spacingM

                        // Error banner (also shown above a stale list)
                        Rectangle {
                            visible: root.error.length > 0
                            width: parent.width
                            height: errText.implicitHeight + Theme.spacingM * 2
                            radius: Theme.cornerRadius
                            color: Theme.withAlpha(Theme.error, 0.15)

                            StyledText {
                                id: errText
                                anchors.fill: parent
                                anchors.margins: Theme.spacingM
                                text: root.error
                                color: Theme.error
                                font.pixelSize: Theme.fontSizeSmall
                                wrapMode: Text.WordWrap
                            }
                        }

                        StyledText {
                            visible: root.loaded && !root.error && root.groups.length === 0
                            width: parent.width
                            height: 60
                            horizontalAlignment: Text.AlignHCenter
                            verticalAlignment: Text.AlignVCenter
                            text: "No containers"
                            color: Theme.surfaceVariantText
                        }

                        Repeater {
                            model: root.groups

                            Column {
                                id: group
                                required property var modelData
                                readonly property bool isCompose: group.modelData.key !== ""
                                readonly property bool isCollapsed: !!root.collapsed[group.modelData.key]

                                width: groupsCol.width
                                spacing: 2

                                // Group header
                                Rectangle {
                                    width: parent.width
                                    height: 44
                                    radius: Theme.cornerRadius
                                    color: Theme.surfaceContainerHigh

                                    MouseArea {
                                        anchors.fill: parent
                                        cursorShape: Qt.PointingHandCursor
                                        onClicked: root.toggleCollapsed(group.modelData.key)
                                    }

                                    Row {
                                        anchors.left: parent.left
                                        anchors.leftMargin: Theme.spacingS
                                        anchors.right: groupActions.left
                                        anchors.rightMargin: Theme.spacingS
                                        anchors.verticalCenter: parent.verticalCenter
                                        spacing: Theme.spacingS

                                        DIcon {
                                            name: group.isCollapsed ? "chevron_right" : "expand_more"
                                            size: Theme.iconSize
                                            color: Theme.surfaceVariantText
                                            anchors.verticalCenter: parent.verticalCenter
                                        }

                                        DIcon {
                                            visible: group.isCompose
                                            name: "stacks"
                                            size: Theme.iconSizeSmall + 2
                                            color: group.modelData.running > 0 ? Theme.primary : Theme.surfaceVariantText
                                            anchors.verticalCenter: parent.verticalCenter
                                        }

                                        DNFIcon {
                                            visible: !group.isCompose
                                            name: "docker"
                                            size: Math.round(Theme.iconSizeSmall + 2)
                                            color: group.modelData.running > 0 ? Theme.primary : Theme.surfaceVariantText
                                            anchors.verticalCenter: parent.verticalCenter
                                        }

                                        StyledText {
                                            text: group.modelData.name
                                            font.pixelSize: Theme.fontSizeMedium
                                            font.weight: Font.Bold
                                            color: Theme.surfaceText
                                            anchors.verticalCenter: parent.verticalCenter
                                        }

                                        StyledText {
                                            text: group.modelData.running + "/" + group.modelData.containers.length + " running"
                                            font.pixelSize: Theme.fontSizeSmall
                                            color: Theme.surfaceVariantText
                                            anchors.verticalCenter: parent.verticalCenter
                                        }

                                        StyledText {
                                            visible: group.isCompose && group.modelData.workdir.length > 0
                                            text: group.modelData.workdir
                                            width: Math.min(implicitWidth, 320)
                                            elide: Text.ElideMiddle
                                            font.pixelSize: Theme.fontSizeSmall
                                            color: Theme.withAlpha(Theme.surfaceVariantText, 0.7)
                                            anchors.verticalCenter: parent.verticalCenter
                                        }
                                    }

                                    Row {
                                        id: groupActions
                                        visible: group.isCompose
                                        anchors.right: parent.right
                                        anchors.rightMargin: Theme.spacingXS
                                        anchors.verticalCenter: parent.verticalCenter
                                        spacing: 0

                                        readonly property var allIds: group.modelData.containers.map(c => c.id)
                                        readonly property bool anyBusy: allIds.some(id => !!root.busy[id])

                                        DSpinner {
                                            size: 18
                                            visible: groupActions.anyBusy
                                            anchors.verticalCenter: parent.verticalCenter
                                        }

                                        DIconButton {
                                            iconName: "play_arrow"
                                            tooltipText: "Start all"
                                            visible: !groupActions.anyBusy && group.modelData.running < group.modelData.containers.length
                                            onClicked: root.act("start", group.modelData.containers.filter(c => c.state !== "running").map(c => c.id))
                                        }

                                        DIconButton {
                                            iconName: "stop"
                                            tooltipText: "Stop all"
                                            visible: !groupActions.anyBusy && group.modelData.running > 0
                                            onClicked: root.act("stop", group.modelData.containers.filter(c => c.state === "running").map(c => c.id))
                                        }

                                        DIconButton {
                                            iconName: "restart_alt"
                                            tooltipText: "Restart all"
                                            visible: !groupActions.anyBusy
                                            onClicked: root.act("restart", groupActions.allIds)
                                        }
                                    }
                                }

                                // Container rows
                                Repeater {
                                    model: group.isCollapsed ? [] : group.modelData.containers

                                    Rectangle {
                                        id: row
                                        required property var modelData
                                        readonly property var c: row.modelData
                                        readonly property bool isRunning: row.c.state === "running"
                                        readonly property bool isBusy: !!root.busy[row.c.id]
                                        readonly property bool confirming: root.confirmDelete === row.c.id

                                        width: group.width
                                        height: 52
                                        radius: Theme.cornerRadius
                                        color: hover.hovered ? Theme.withAlpha(Theme.surfaceContainerHigh, 0.6) : "transparent"

                                        HoverHandler {
                                            id: hover
                                        }

                                        Rectangle {
                                            id: dot
                                            anchors.left: parent.left
                                            anchors.leftMargin: Theme.spacingM + Theme.spacingS
                                            anchors.verticalCenter: parent.verticalCenter
                                            width: 10
                                            height: 10
                                            radius: 5
                                            color: root.stateColor(row.c.state)
                                        }

                                        readonly property real infoWidth: row.width - dot.x - dot.width - actions.width - Theme.spacingM * 4

                                        Column {
                                            id: nameCol
                                            anchors.left: dot.right
                                            anchors.leftMargin: Theme.spacingM
                                            anchors.verticalCenter: parent.verticalCenter
                                            width: row.infoWidth * 0.4
                                            spacing: 2

                                            StyledText {
                                                width: parent.width
                                                text: row.c.name
                                                elide: Text.ElideRight
                                                font.pixelSize: Theme.fontSizeMedium
                                                font.weight: Font.Medium
                                                color: Theme.surfaceText
                                            }

                                            StyledText {
                                                width: parent.width
                                                text: row.c.image
                                                elide: Text.ElideMiddle
                                                font.pixelSize: Theme.fontSizeSmall
                                                color: Theme.surfaceVariantText
                                            }
                                        }

                                        StyledText {
                                            id: portsText
                                            anchors.left: nameCol.right
                                            anchors.leftMargin: Theme.spacingM
                                            anchors.verticalCenter: parent.verticalCenter
                                            width: row.infoWidth * 0.3
                                            text: row.c.ports || "—"
                                            elide: Text.ElideRight
                                            maximumLineCount: 2
                                            wrapMode: Text.WrapAtWordBoundaryOrAnywhere
                                            font.pixelSize: Theme.fontSizeSmall
                                            color: row.c.ports ? Theme.surfaceText : Theme.surfaceVariantText
                                        }

                                        StyledText {
                                            anchors.left: portsText.right
                                            anchors.leftMargin: Theme.spacingM
                                            anchors.verticalCenter: parent.verticalCenter
                                            width: row.infoWidth * 0.3
                                            text: row.c.status
                                            elide: Text.ElideRight
                                            font.pixelSize: Theme.fontSizeSmall
                                            color: root.stateColor(row.c.state)
                                        }

                                        Row {
                                            id: actions
                                            anchors.right: parent.right
                                            anchors.rightMargin: Theme.spacingXS
                                            anchors.verticalCenter: parent.verticalCenter
                                            spacing: 0

                                            DSpinner {
                                                size: 18
                                                visible: row.isBusy
                                                anchors.verticalCenter: parent.verticalCenter
                                            }

                                            // Normal buttons
                                            DIconButton {
                                                iconName: "play_arrow"
                                                tooltipText: "Start"
                                                visible: !row.isBusy && !row.confirming && !row.isRunning
                                                onClicked: root.act("start", [row.c.id])
                                            }

                                            DIconButton {
                                                iconName: "stop"
                                                tooltipText: "Stop"
                                                visible: !row.isBusy && !row.confirming && row.isRunning
                                                onClicked: root.act("stop", [row.c.id])
                                            }

                                            DIconButton {
                                                iconName: "restart_alt"
                                                tooltipText: "Restart"
                                                visible: !row.isBusy && !row.confirming && row.isRunning
                                                onClicked: root.act("restart", [row.c.id])
                                            }

                                            DIconButton {
                                                iconName: "delete"
                                                tooltipText: "Delete"
                                                iconColor: Theme.error
                                                visible: !row.isBusy && !row.confirming
                                                onClicked: root.confirmDelete = row.c.id
                                            }

                                            // Delete confirmation
                                            StyledText {
                                                visible: !row.isBusy && row.confirming
                                                text: "Delete?"
                                                font.pixelSize: Theme.fontSizeSmall
                                                font.weight: Font.Bold
                                                color: Theme.error
                                                anchors.verticalCenter: parent.verticalCenter
                                            }

                                            DIconButton {
                                                iconName: "check"
                                                tooltipText: "Confirm delete"
                                                iconColor: Theme.error
                                                visible: !row.isBusy && row.confirming
                                                onClicked: {
                                                    root.confirmDelete = "";
                                                    root.act("rm", [row.c.id]);
                                                }
                                            }

                                            DIconButton {
                                                iconName: "close"
                                                tooltipText: "Cancel"
                                                visible: !row.isBusy && row.confirming
                                                onClicked: root.confirmDelete = ""
                                            }
                                        }
                                    }
                                }
                            }
                        }
                    }
                }
            }
        }
    }
}
