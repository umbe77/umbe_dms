import QtQuick
import Quickshell
import Quickshell.Io
import Quickshell.Wayland
import Quickshell.Widgets
import Quickshell.Hyprland
import qs.Common
import qs.Services
import qs.Widgets
import qs.Modules.Plugins

PluginComponent {
    id: root

    // Settings
    readonly property int thumbHeight: pluginData.thumbHeight ?? 160
    readonly property int showDelayMs: pluginData.showDelayMs ?? 120
    readonly property bool showTitles: pluginData.showTitles ?? true

    // State
    property bool open: false          // a switch is in progress (Alt held)
    property bool shown: false         // the overlay is on screen
    property var windows: []           // snapshot: [{ address, toplevel, title, appId, aspect }]
    property int selected: 0
    property var screen: null          // screen the overlay is shown on

    // Our own most-recently-used list of window addresses (normalized),
    // most recent first. Seeded from Hyprland's focusHistoryID at startup.
    property var mru: []

    // ---- helpers ------------------------------------------------------------

    function normAddr(a) {
        return String(a ?? "").toLowerCase().replace(/^0x/, "");
    }

    function touch(addr) {
        const a = normAddr(addr);
        if (!a)
            return;
        const list = root.mru.filter(x => x !== a);
        list.unshift(a);
        root.mru = list;
    }

    function forget(addr) {
        const a = normAddr(addr);
        root.mru = root.mru.filter(x => x !== a);
    }

    function isMapped(t) {
        if (!t)
            return false;
        if (t.mapped === false || t.lastIpcObject?.mapped === false)
            return false;
        if (t.hidden === true || t.lastIpcObject?.hidden === true)
            return false;
        return true;
    }

    function workspaceIdOf(t) {
        return t.lastIpcObject?.workspace?.id ?? t.workspace?.id ?? null;
    }

    function seedMru() {
        const items = Array.from(Hyprland.toplevels?.values ?? []).filter(t => t?.address);
        items.sort((a, b) => (a.lastIpcObject?.focusHistoryID ?? 1e9) - (b.lastIpcObject?.focusHistoryID ?? 1e9));
        const seeded = items.map(t => normAddr(t.address));
        // Keep anything already tracked in front
        root.mru = root.mru.concat(seeded.filter(a => !root.mru.includes(a)));
    }

    function buildList() {
        const wsId = Hyprland.focusedWorkspace?.id ?? Hyprland.focusedMonitor?.activeWorkspace?.id;
        if (wsId === undefined || wsId === null)
            return [];

        const items = Array.from(Hyprland.toplevels?.values ?? [])
            .filter(t => t?.address && t.wayland && root.isMapped(t) && root.workspaceIdOf(t) === wsId);

        function rank(t) {
            const i = root.mru.indexOf(root.normAddr(t.address));
            if (i >= 0)
                return i;
            return 100000 + (t.lastIpcObject?.focusHistoryID ?? 100000);
        }
        items.sort((a, b) => rank(a) - rank(b));

        return items.map(t => {
            const size = t.lastIpcObject?.size;
            let aspect = (size && size[0] > 0 && size[1] > 0) ? size[0] / size[1] : 16 / 9;
            aspect = Math.max(0.5, Math.min(2.5, aspect));
            const appId = t.wayland?.appId || t.lastIpcObject?.class || "";
            return {
                address: t.address,
                toplevel: t,
                title: t.title || t.wayland?.title || appId,
                appId: appId,
                aspect: aspect
            };
        });
    }

    function focusedScreen() {
        const name = Hyprland.focusedMonitor?.name ?? "";
        const screens = Quickshell.screens;
        for (let i = 0; i < screens.length; i++) {
            if (screens[i].name === name)
                return screens[i];
        }
        return screens.length > 0 ? screens[0] : null;
    }

    // ---- public actions -----------------------------------------------------

    function step(delta) {
        if (!root.open) {
            const list = root.buildList();
            if (list.length < 2)
                return "nothing";
            root.windows = list;
            root.screen = root.focusedScreen();
            // First press goes to the previous window (or the last one, backwards)
            root.selected = delta > 0 ? 1 : list.length - 1;
            root.open = true;
            if (root.showDelayMs > 0)
                showTimer.restart();
            else
                root.shown = true;
            return "opened";
        }
        const n = root.windows.length;
        root.selected = ((root.selected + delta) % n + n) % n;
        return "selected " + root.selected;
    }

    function commit() {
        if (!root.open)
            return "closed";
        const w = root.windows[root.selected];
        const wasShown = root.shown;
        root.close();
        if (!w)
            return "committed";
        if (wasShown) {
            // Hyprland ignores focus requests while our exclusive-keyboard
            // layer is still mapped, so wait for it to go away first.
            root.pendingFocus = w;
            focusTimer.attempts = 0;
            focusTimer.restart();
        } else {
            root.focusWindow(w);
        }
        return "committed";
    }

    // Window to focus once the overlay is unmapped
    property var pendingFocus: null

    Timer {
        id: focusTimer
        property int attempts: 0
        interval: 40
        onTriggered: {
            const w = root.pendingFocus;
            if (!w || root.open) {
                root.pendingFocus = null;
                return;
            }
            const active = root.normAddr(Hyprland.activeToplevel?.address);
            if (attempts > 0 && active === root.normAddr(w.address)) {
                root.pendingFocus = null;
                return;
            }
            if (attempts >= 5) {
                root.pendingFocus = null;
                return;
            }
            attempts++;
            root.focusWindow(w);
            // Check again shortly and retry if focus didn't land
            focusTimer.restart();
        }
    }

    function cancel() {
        root.close();
        return "cancelled";
    }

    function close() {
        showTimer.stop();
        root.open = false;
        root.shown = false;
    }

    function select(index) {
        if (!root.open || index < 0 || index >= root.windows.length)
            return;
        root.selected = index;
    }

    function focusWindow(w) {
        if (HyprlandService.luaConfigActive) {
            HyprlandService.focusWindow(w.address);
        } else if (w.toplevel?.wayland) {
            w.toplevel.wayland.activate();
        } else {
            Hyprland.dispatch("focuswindow address:0x" + root.normAddr(w.address));
        }
        root.touch(w.address);
    }

    Timer {
        id: showTimer
        interval: root.showDelayMs
        onTriggered: {
            if (root.open)
                root.shown = true;
        }
    }

    // ---- focus tracking -----------------------------------------------------

    Component.onCompleted: {
        Hyprland.refreshToplevels();
        seedTimer.start();
    }

    Timer {
        id: seedTimer
        interval: 500
        onTriggered: root.seedMru()
    }

    Connections {
        target: Hyprland
        function onRawEvent(event) {
            const n = event.name;
            if (n === "activewindowv2") {
                const addr = String(event.data ?? "").trim();
                if (addr && addr !== ",")
                    root.touch(addr);
            } else if (n === "closewindow") {
                root.forget(String(event.data ?? "").trim());
                if (root.open) {
                    // A window in the snapshot went away: drop it
                    const a = root.normAddr(event.data);
                    const list = root.windows.filter(w => root.normAddr(w.address) !== a);
                    if (list.length !== root.windows.length) {
                        if (list.length < 2) {
                            root.close();
                        } else {
                            root.windows = list;
                            root.selected = Math.min(root.selected, list.length - 1);
                        }
                    }
                }
            }
        }
    }

    // ---- IPC ----------------------------------------------------------------

    IpcHandler {
        target: "windowSwitcher"

        function next(): string {
            return root.step(1);
        }

        function prev(): string {
            return root.step(-1);
        }

        function commit(): string {
            return root.commit();
        }

        function cancel(): string {
            return root.cancel();
        }

        function status(): string {
            return JSON.stringify({
                open: root.open,
                shown: root.shown,
                selected: root.selected,
                active: Hyprland.activeToplevel?.address ?? "",
                lua: HyprlandService.luaConfigActive,
                windows: root.windows.map(w => ({ address: w.address, appId: w.appId, title: w.title })),
                current: root.buildList().map(w => ({ address: w.address, appId: w.appId, title: w.title }))
            });
        }
    }

    // ---- overlay ------------------------------------------------------------

    Loader {
        active: root.shown && !!root.screen
        asynchronous: false

        sourceComponent: PanelWindow {
            id: win

            screen: root.screen
            color: "transparent"

            WlrLayershell.namespace: "dms:window-switcher"
            WlrLayershell.layer: WlrLayer.Overlay
            WlrLayershell.exclusiveZone: -1
            WlrLayershell.keyboardFocus: WlrKeyboardFocus.Exclusive

            anchors {
                top: true
                left: true
                right: true
                bottom: true
            }

            // Click outside the panel cancels
            MouseArea {
                anchors.fill: parent
                onClicked: root.cancel()
            }

            FocusScope {
                id: keyScope
                anchors.fill: parent
                focus: true

                function altHeld(event) {
                    return (event.modifiers & (Qt.AltModifier | Qt.MetaModifier)) !== 0;
                }

                Keys.onPressed: event => {
                    event.accepted = true;
                    switch (event.key) {
                    case Qt.Key_Escape:
                        root.cancel();
                        return;
                    case Qt.Key_Return:
                    case Qt.Key_Enter:
                    case Qt.Key_Space:
                        root.commit();
                        return;
                    case Qt.Key_Right:
                    case Qt.Key_Down:
                        root.step(1);
                        return;
                    case Qt.Key_Left:
                    case Qt.Key_Up:
                        root.step(-1);
                        return;
                    case Qt.Key_Tab:
                    case Qt.Key_Backtab:
                        // With Alt held the compositor bind already moved the selection
                        if (!keyScope.altHeld(event))
                            root.step(event.key === Qt.Key_Backtab || (event.modifiers & Qt.ShiftModifier) ? -1 : 1);
                        return;
                    case Qt.Key_Alt:
                    case Qt.Key_Meta:
                    case Qt.Key_Shift:
                        return;
                    default:
                        event.accepted = false;
                    }
                }

                Keys.onReleased: event => {
                    if (event.key === Qt.Key_Alt || event.key === Qt.Key_AltGr || event.key === Qt.Key_Meta) {
                        event.accepted = true;
                        root.commit();
                    }
                }

                Component.onCompleted: Qt.callLater(() => keyScope.forceActiveFocus())
            }

            Rectangle {
                id: panel

                readonly property real pad: Theme.spacingL
                readonly property real gap: Theme.spacingM
                readonly property real labelHeight: root.showTitles ? 28 : 0
                readonly property real naturalWidth: {
                    let w = 0;
                    for (const item of root.windows)
                        w += root.thumbHeight * item.aspect;
                    return w + gap * Math.max(0, root.windows.length - 1) + pad * 2;
                }
                // Shrink the tiles if they don't fit on screen
                readonly property real scale: Math.min(1, (win.width * 0.92) / Math.max(1, naturalWidth))
                readonly property real tileHeight: root.thumbHeight * scale

                anchors.centerIn: parent
                width: Math.min(naturalWidth, win.width * 0.92)
                height: tileHeight + labelHeight + pad * 2 + Theme.spacingS
                radius: Theme.cornerRadius * 1.5
                color: Theme.withAlpha(Theme.surfaceContainer, 0.95)
                border.color: Theme.withAlpha(Theme.outline, 0.3)
                border.width: 1

                // Swallow clicks on the panel background
                MouseArea {
                    anchors.fill: parent
                }

                Row {
                    id: tiles
                    anchors.centerIn: parent
                    spacing: panel.gap

                    Repeater {
                        model: root.windows

                        Item {
                            id: tile
                            required property var modelData
                            required property int index
                            readonly property bool isSelected: tile.index === root.selected

                            width: panel.tileHeight * tile.modelData.aspect
                            height: panel.tileHeight + panel.labelHeight + Theme.spacingS

                            ClippingRectangle {
                                id: thumb
                                width: parent.width
                                height: panel.tileHeight
                                radius: Theme.cornerRadius
                                color: Theme.surfaceContainerHigh

                                ScreencopyView {
                                    anchors.fill: parent
                                    captureSource: tile.modelData.toplevel?.wayland ?? null
                                    live: true
                                }

                                IconImage {
                                    anchors.right: parent.right
                                    anchors.bottom: parent.bottom
                                    anchors.margins: Theme.spacingS
                                    implicitSize: Math.max(20, Math.min(40, panel.tileHeight * 0.25))
                                    source: {
                                        const id = tile.modelData.appId;
                                        if (!id)
                                            return "";
                                        const entry = DesktopEntries.heuristicLookup(Paths.moddedAppId(id));
                                        return Paths.getAppIcon(id, entry) || "";
                                    }
                                }
                            }

                            Rectangle {
                                anchors.fill: thumb
                                anchors.margins: -3
                                radius: Theme.cornerRadius + 3
                                color: "transparent"
                                border.width: tile.isSelected ? 3 : 0
                                border.color: Theme.primary
                            }

                            StyledText {
                                visible: root.showTitles
                                anchors.top: thumb.bottom
                                anchors.topMargin: Theme.spacingS
                                width: parent.width
                                horizontalAlignment: Text.AlignHCenter
                                elide: Text.ElideRight
                                text: tile.modelData.title
                                font.pixelSize: Theme.fontSizeSmall
                                font.weight: tile.isSelected ? Font.Bold : Font.Normal
                                color: tile.isSelected ? Theme.surfaceText : Theme.surfaceVariantText
                            }

                            MouseArea {
                                anchors.fill: parent
                                cursorShape: Qt.PointingHandCursor
                                onClicked: {
                                    root.select(tile.index);
                                    root.commit();
                                }
                            }
                        }
                    }
                }
            }
        }
    }
}
