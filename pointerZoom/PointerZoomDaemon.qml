import QtQuick
import Quickshell
import Quickshell.Io
import Quickshell.Wayland
import qs.Common
import qs.Modules.Plugins

PluginComponent {
    id: root

    // Settings
    readonly property real step: (pluginData.step ?? 100) / 100
    readonly property real maxZoom: pluginData.maxZoom ?? 8
    readonly property real dimOpacity: (pluginData.dimOpacity ?? 50) / 100
    readonly property real zoomedDim: (pluginData.zoomedDim ?? 50) / 100
    readonly property int startRadius: pluginData.startRadius ?? 500
    readonly property int endRadius: pluginData.endRadius ?? 80
    readonly property int durationMs: pluginData.durationMs ?? 350
    readonly property bool showRing: pluginData.showRing ?? true
    readonly property bool rigid: pluginData.rigid ?? false

    // State
    property real zoom: 1          // factor last sent to Hyprland
    property real pendingZoom: 1   // target collected while the intro runs
    property bool pendingShow: false
    property bool active: false    // overlay shown (intro, zoomed, or fading out)

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
    // Hyprland magnifies the overlay along with everything else, so draw the
    // disc smaller by the zoom factor to keep it the same size on screen.
    readonly property real shownRadius: root.radius / root.zoom

    readonly property bool starting: root.pendingShow || intro.running

    function clamp(z) {
        return Math.max(1, Math.min(root.maxZoom, Math.round(z * 100) / 100));
    }

    // ---- public actions ---------------------------------------------------

    function zoomIn() {
        if (root.starting) {
            root.pendingZoom = root.clamp(root.pendingZoom + root.step);
            return "starting " + root.pendingZoom;
        }
        if (root.zoom <= 1)
            return root.startZoom(1 + root.step);
        root.setZoom(root.zoom + root.step);
        return String(root.zoom);
    }

    function zoomOut() {
        if (root.starting) {
            root.pendingZoom = root.clamp(root.pendingZoom - root.step);
            if (root.pendingZoom <= 1)
                root.cancelIntro();
            return String(root.pendingZoom);
        }
        root.setZoom(root.zoom - root.step);
        return String(root.zoom);
    }

    function reset() {
        // Bound to the SUPER/SHIFT release too, which fires after every
        // SUPER+SHIFT shortcut: skip hyprctl when there is nothing to undo.
        if (!root.starting && !root.active && root.zoom <= 1 && !zoomProc.running)
            return "1";
        root.cancelIntro();
        root.setZoom(1);
        return "1";
    }

    function setFactor(z) {
        if (root.starting) {
            root.pendingZoom = root.clamp(z);
            if (root.pendingZoom <= 1)
                root.cancelIntro();
            return String(root.pendingZoom);
        }
        if (root.zoom <= 1 && root.clamp(z) > 1)
            return root.startZoom(z);
        root.setZoom(z);
        return String(root.zoom);
    }

    // From 1x: read the pointer, play the intro, then zoom
    function startZoom(z) {
        root.pendingZoom = root.clamp(z);
        if (root.pendingZoom <= 1)
            return "1";
        root.pendingShow = true;
        showFallback.restart();
        cursorPoller.request();
        return "starting " + root.pendingZoom;
    }

    function setZoom(z) {
        root.zoom = root.clamp(z);
        zoomApplier.apply();
        if (root.zoom <= 1 && root.active && !outro.running)
            outro.restart();
    }

    function open() {
        showFallback.stop();
        root.pendingShow = false;
        root.drawX = root.cursorX;
        root.drawY = root.cursorY;
        root.radius = root.startRadius;
        root.dim = 0;
        outro.stop();
        settle.stop();
        root.active = true;
        intro.restart();
    }

    // Already zoomed (e.g. after a DMS restart): show the spotlight without the intro
    function openSteady() {
        root.radius = root.endRadius;
        root.dim = root.zoomedDim;
        root.active = true;
        cursorPoller.request();
    }

    function cancelIntro() {
        showFallback.stop();
        intro.stop();
        root.pendingShow = false;
        root.pendingZoom = 1;
        if (root.active && root.zoom <= 1 && !outro.running)
            outro.restart();
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

    function screenContains(s, x, y) {
        return !!s && x >= s.x && x < s.x + s.width && y >= s.y && y < s.y + s.height;
    }

    IpcHandler {
        target: "pointerZoom"

        function zoomIn(): string {
            return root.zoomIn();
        }

        function zoomOut(): string {
            return root.zoomOut();
        }

        function reset(): string {
            return root.reset();
        }

        function set(factor: string): string {
            const z = parseFloat(factor);
            if (isNaN(z))
                return "invalid factor";
            return root.setFactor(z);
        }

        function status(): string {
            return JSON.stringify({
                zoom: root.zoom,
                pendingZoom: root.pendingZoom,
                active: root.active,
                cursor: [root.cursorX, root.cursorY],
                tracking: cursorPoller.useHyprctl ? "hyprctl" : "socket",
                socketFailures: cursorPoller.failures
            });
        }
    }

    // ---- Hyprland zoom ----------------------------------------------------
    // The Lua config dropped `hyprctl keyword`, so options are set with `eval`.
    // Only one hyprctl runs at a time; whatever value is current when it exits
    // gets sent next, so fast scrolling never queues up stale steps.

    Item {
        id: zoomApplier

        property real sentZoom: -1
        property bool sentRigid: false
        property bool dirty: false

        function apply() {
            if (zoomProc.running) {
                dirty = true;
                return;
            }
            dirty = false;
            sentZoom = root.zoom;
            sentRigid = root.rigid;
            zoomProc.command = ["hyprctl", "eval", "hl.config({cursor={zoom_factor=" + sentZoom.toFixed(3)
                + ", zoom_rigid=" + (sentRigid ? "true" : "false") + "}})"];
            zoomProc.running = true;
        }

        Process {
            id: zoomProc
            onExited: {
                if (zoomApplier.dirty || zoomApplier.sentZoom !== root.zoom || zoomApplier.sentRigid !== root.rigid)
                    Qt.callLater(zoomApplier.apply);
            }
        }
    }

    onRigidChanged: zoomApplier.apply()

    // Pick up a zoom left over from before a DMS restart
    Process {
        id: readZoomProc
        running: true
        command: ["hyprctl", "getoption", "cursor:zoom_factor", "-j"]
        stdout: StdioCollector {
            onStreamFinished: {
                try {
                    const z = JSON.parse(text).float;
                    if (typeof z === "number" && !root.starting && !root.active) {
                        root.zoom = root.clamp(z);
                        if (root.zoom > 1)
                            root.openSteady();
                    }
                } catch (e) {}
            }
        }
    }

    // Don't leave the screen zoomed when the plugin is disabled
    Component.onDestruction: {
        if (root.zoom > 1)
            Quickshell.execDetached(["hyprctl", "eval", "hl.config({cursor={zoom_factor=1.0}})"]);
    }

    // Opens even if the first position read fails (uses the last known position)
    Timer {
        id: showFallback
        interval: 200
        onTriggered: {
            if (root.pendingShow)
                root.open();
        }
    }

    // ---- animation ----------------------------------------------------------

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
            duration: Math.min(200, root.durationMs)
            easing.type: Easing.OutQuad
        }
        onFinished: {
            if (!root.active)
                return;
            root.setZoom(root.pendingZoom);
            root.pendingZoom = 1;
            if (root.zoom > 1)
                settle.restart();
        }
    }

    // From the intro dim to the dim kept while zoomed
    NumberAnimation {
        id: settle
        target: root
        property: "dim"
        to: root.zoomedDim
        duration: 200
        easing.type: Easing.InOutQuad
    }

    NumberAnimation {
        id: outro
        target: root
        property: "dim"
        to: 0
        duration: 200
        easing.type: Easing.InQuad
        onStarted: settle.stop()
        onFinished: {
            if (root.zoom <= 1 && !root.starting)
                root.active = false;
        }
    }

    // ---- pointer tracking ---------------------------------------------------
    // Same as findPointer: the overlay lets clicks through, so it never sees the
    // mouse. Ask Hyprland for the cursor position over its request socket.
    // Hyprland closes the socket after each reply, and a Quickshell Socket can't
    // redial, so every request gets a fresh Socket. If the socket keeps failing,
    // fall back to `hyprctl cursorpos -j`.

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
    // One window per monitor, so the spotlight can follow the pointer across
    // monitors without recreating surfaces; only the pointer's monitor draws.

    Loader {
        active: root.active

        sourceComponent: Variants {
            model: ShellLayout.realScreens

            PanelWindow {
                id: win
                required property var modelData
                readonly property bool hasPointer: root.screenContains(win.modelData, root.cursorX, root.cursorY)

                // Pointer in this window's coordinates
                readonly property real cx: root.drawX - (win.modelData?.x ?? 0)
                readonly property real cy: root.drawY - (win.modelData?.y ?? 0)

                screen: win.modelData
                color: "transparent"

                WlrLayershell.namespace: "dms:pointer-zoom"
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

                // Same spotlight as findPointer: a ring-shaped Rectangle whose border
                // covers the whole screen, leaving a clear disc around the pointer.
                Rectangle {
                    id: shade
                    visible: win.hasPointer
                    readonly property real reach: Math.hypot(
                        Math.max(Math.abs(win.cx), Math.abs(win.cx - win.width)),
                        Math.max(Math.abs(win.cy), Math.abs(win.cy - win.height)))
                    readonly property real thickness: Math.max(1, shade.reach - root.shownRadius + 2)
                    readonly property real outer: root.shownRadius + shade.thickness

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
                    visible: root.showRing && win.hasPointer
                    x: win.cx - root.shownRadius
                    y: win.cy - root.shownRadius
                    width: root.shownRadius * 2
                    height: root.shownRadius * 2
                    radius: root.shownRadius
                    color: "transparent"
                    border.width: 3 / root.zoom
                    border.color: Theme.primary
                    // Fade with the dim, relative to whichever dim level is the peak
                    opacity: {
                        const peak = Math.max(root.dimOpacity, root.zoomedDim);
                        return peak > 0 ? Math.min(1, root.dim / peak) : 1;
                    }
                    antialiasing: true
                }
            }
        }
    }
}
