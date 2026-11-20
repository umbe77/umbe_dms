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
    readonly property int doubleTapMs: pluginData.doubleTapMs ?? 350
    readonly property real dimOpacity: (pluginData.dimOpacity ?? 60) / 100
    readonly property int startRadius: pluginData.startRadius ?? 600
    readonly property int endRadius: pluginData.endRadius ?? 70
    readonly property int durationMs: pluginData.durationMs ?? 700
    readonly property bool showRing: pluginData.showRing ?? true

    // State
    property bool active: false
    property bool pendingShow: false
    property real lastTapTime: 0

    // Pointer position in global (layout, logical) coordinates
    property real cursorX: 0
    property real cursorY: 0
    // What the overlay draws: follows cursorX/Y, smoothed between polls
    property real drawX: 0
    property real drawY: 0
    Behavior on drawX {
        enabled: root.active
        NumberAnimation { duration: pollTimer.interval }
    }
    Behavior on drawY {
        enabled: root.active
        NumberAnimation { duration: pollTimer.interval }
    }

    property real radius: startRadius
    property real dim: 0

    // ---- public actions ---------------------------------------------------

    function tap() {
        if (root.active || root.pendingShow) {
            root.lastTapTime = 0;
            root.hide();
            return "hidden";
        }
        const now = Date.now();
        if (root.lastTapTime > 0 && now - root.lastTapTime <= root.doubleTapMs) {
            root.lastTapTime = 0;
            root.show();
            return "shown";
        }
        root.lastTapTime = now;
        return "armed";
    }

    function show() {
        if (root.active || root.pendingShow)
            return;
        // Read the pointer position first so the circle starts in the right place
        root.pendingShow = true;
        showFallback.restart();
        cursorPoller.request();
    }

    function open() {
        showFallback.stop();
        root.pendingShow = false;
        root.drawX = root.cursorX;
        root.drawY = root.cursorY;
        root.radius = root.startRadius;
        root.dim = 0;
        root.active = true;
        intro.restart();
    }

    function hide() {
        showFallback.stop();
        intro.stop();
        root.pendingShow = false;
        root.active = false;
    }

    function setCursor(x, y) {
        root.cursorX = x;
        root.cursorY = y;
        if (root.active) {
            root.drawX = x;
            root.drawY = y;
        } else if (root.pendingShow) {
            root.open();
        }
    }

    IpcHandler {
        target: "findPointer"

        function tap(): string {
            return root.tap();
        }

        function show(): string {
            root.show();
            return "shown";
        }

        function hide(): string {
            root.hide();
            return "hidden";
        }

        function status(): string {
            return JSON.stringify({
                active: root.active,
                cursor: [root.cursorX, root.cursorY],
                radius: Math.round(root.radius),
                tracking: cursorPoller.useHyprctl ? "hyprctl" : "socket",
                socketFailures: cursorPoller.failures
            });
        }

        function toggle(): string {
            if (root.active || root.pendingShow) {
                root.hide();
                return "hidden";
            }
            root.show();
            return "shown";
        }
    }

    // Opens even if the first position read fails
    Timer {
        id: showFallback
        interval: 200
        onTriggered: {
            if (root.pendingShow)
                root.open();
        }
    }

    ParallelAnimation {
        id: intro
        NumberAnimation {
            target: root
            property: "radius"
            from: root.startRadius
            to: root.endRadius
            duration: root.durationMs
            easing.type: Easing.OutCubic
        }
        NumberAnimation {
            target: root
            property: "dim"
            from: 0
            to: root.dimOpacity
            duration: Math.min(250, root.durationMs)
            easing.type: Easing.OutQuad
        }
    }

    // ---- pointer tracking ---------------------------------------------------
    // The overlay lets clicks through, so it never sees the mouse. Instead, ask
    // Hyprland for the cursor position over its request socket. Hyprland closes
    // the socket after each reply, and a Quickshell Socket can't redial, so
    // every request gets a fresh Socket. If the socket keeps failing, fall back
    // to `hyprctl cursorpos -j`.

    Timer {
        id: pollTimer
        interval: 16
        repeat: true
        running: root.active
        onTriggered: cursorPoller.request()
    }

    Item {
        id: cursorPoller

        readonly property string socketPath: Quickshell.env("XDG_RUNTIME_DIR") + "/hypr/"
            + Quickshell.env("HYPRLAND_INSTANCE_SIGNATURE") + "/.socket.sock"
        property bool busy: false
        property string buffer: ""
        property int failures: 0
        readonly property bool useHyprctl: failures >= 5

        function request() {
            if (busy)
                return;
            busy = true;
            buffer = "";
            watchdog.restart();
            if (useHyprctl) {
                hyprctlProc.running = true;
                return;
            }
            socketLoader.active = false;
            socketLoader.active = true;
        }

        function parse(text) {
            try {
                const obj = JSON.parse(text);
                if (typeof obj.x === "number" && typeof obj.y === "number") {
                    root.setCursor(obj.x, obj.y);
                    return true;
                }
            } catch (e) {}
            return false;
        }

        function onData(data) {
            buffer += data;
            if (parse(buffer)) {
                failures = 0;
                finish();
            }
        }

        function finish() {
            if (!busy)
                return;
            busy = false;
            watchdog.stop();
            // Don't destroy the Socket from inside its own signal handler
            Qt.callLater(() => {
                if (!cursorPoller.busy)
                    socketLoader.active = false;
            });
        }

        function fail() {
            if (!busy)
                return;
            failures++;
            finish();
        }

        Loader {
            id: socketLoader
            active: false
            // Dial once `item` is set, so early signals see a valid socket
            onLoaded: item.connected = true

            sourceComponent: Socket {
                path: cursorPoller.socketPath
                parser: SplitParser {
                    splitMarker: ""
                    onRead: data => cursorPoller.onData(data)
                }
                onConnectionStateChanged: {
                    if (connected) {
                        write("j/cursorpos");
                        flush();
                    } else if (cursorPoller.busy) {
                        // Closed without a full reply
                        cursorPoller.fail();
                    }
                }
                onError: cursorPoller.fail()
            }
        }

        Process {
            id: hyprctlProc
            command: ["hyprctl", "cursorpos", "-j"]
            stdout: StdioCollector {
                onStreamFinished: {
                    cursorPoller.parse(text);
                    cursorPoller.finish();
                }
            }
        }

        Timer {
            id: watchdog
            interval: 500
            onTriggered: cursorPoller.fail()
        }
    }

    // ---- overlay ------------------------------------------------------------

    Loader {
        active: root.active
        asynchronous: false

        sourceComponent: Variants {
            model: ShellLayout.realScreens

            PanelWindow {
                id: win
                required property var modelData
                readonly property HyprlandMonitor monitor: Hyprland.monitorFor(win.modelData)
                readonly property bool isFocused: !!win.monitor && Hyprland.focusedMonitor === win.monitor

                // Pointer in this window's coordinates
                readonly property real cx: root.drawX - (win.modelData?.x ?? 0)
                readonly property real cy: root.drawY - (win.modelData?.y ?? 0)

                screen: win.modelData
                color: "transparent"

                WlrLayershell.namespace: "dms:find-pointer"
                WlrLayershell.layer: WlrLayer.Overlay
                WlrLayershell.exclusiveZone: -1
                WlrLayershell.keyboardFocus: win.isFocused ? WlrKeyboardFocus.Exclusive : WlrKeyboardFocus.None

                anchors {
                    top: true
                    left: true
                    right: true
                    bottom: true
                }

                // Click-through: empty input region
                mask: Region {}

                FocusScope {
                    id: keyScope
                    anchors.fill: parent
                    focus: true

                    Keys.onEscapePressed: event => {
                        event.accepted = true;
                        root.hide();
                    }

                    Component.onCompleted: Qt.callLater(() => keyScope.forceActiveFocus())
                }

                onIsFocusedChanged: {
                    if (win.isFocused)
                        Qt.callLater(() => keyScope.forceActiveFocus());
                }

                // Spotlight hole: a ring-shaped Rectangle whose border is thick
                // enough to cover the whole screen, leaving a clear disc of
                // `root.radius` around the pointer.
                Rectangle {
                    id: shade
                    // Distance from the pointer to this screen's farthest corner
                    readonly property real reach: Math.hypot(
                        Math.max(Math.abs(win.cx), Math.abs(win.cx - win.width)),
                        Math.max(Math.abs(win.cy), Math.abs(win.cy - win.height)))
                    readonly property real thickness: Math.max(1, shade.reach - root.radius + 2)
                    readonly property real outer: root.radius + shade.thickness

                    x: win.cx - shade.outer
                    y: win.cy - shade.outer
                    width: shade.outer * 2
                    height: shade.outer * 2
                    radius: shade.outer
                    color: "transparent"
                    border.width: shade.thickness
                    border.color: Qt.rgba(0, 0, 0, root.dim)
                    antialiasing: true
                }

                Rectangle {
                    visible: root.showRing
                    x: win.cx - root.radius
                    y: win.cy - root.radius
                    width: root.radius * 2
                    height: root.radius * 2
                    radius: root.radius
                    color: "transparent"
                    border.width: 3
                    border.color: Theme.primary
                    opacity: root.dimOpacity > 0 ? Math.min(1, root.dim / root.dimOpacity) : 1
                    antialiasing: true
                }
            }
        }
    }
}
