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
    readonly property int startRadius: pluginData.startRadius ?? 500
    readonly property int endRadius: pluginData.endRadius ?? 80
    readonly property int durationMs: pluginData.durationMs ?? 350
    readonly property bool showRing: pluginData.showRing ?? true
    readonly property bool rigid: pluginData.rigid ?? false

    // State
    property real zoom: 1          // factor last sent to Hyprland
    property real pendingZoom: 1   // target collected while the intro runs
    property bool pendingShow: false
    property bool active: false    // overlay shown

    property real cursorX: 0
    property real cursorY: 0
    property real radius: startRadius
    property real dim: 0

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
        if (root.zoom <= 1) {
            root.pendingZoom = root.clamp(1 + root.step);
            if (root.pendingZoom <= 1)
                return "1";
            // Read the pointer first so the circle closes on the right spot
            root.pendingShow = true;
            showFallback.restart();
            cursorProc.running = true;
            return "starting " + root.pendingZoom;
        }
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
        root.cancelIntro();
        root.setZoom(1);
        return "1";
    }

    function setZoom(z) {
        root.zoom = root.clamp(z);
        zoomApplier.apply();
    }

    function open() {
        showFallback.stop();
        root.pendingShow = false;
        root.radius = root.startRadius;
        root.dim = 0;
        root.active = true;
        outro.stop();
        intro.restart();
    }

    function cancelIntro() {
        showFallback.stop();
        intro.stop();
        outro.stop();
        root.pendingShow = false;
        root.active = false;
        root.pendingZoom = 1;
    }

    function screenAt(x, y) {
        const screens = ShellLayout.realScreens;
        for (let i = 0; i < screens.length; i++) {
            const s = screens[i];
            if (x >= s.x && x < s.x + s.width && y >= s.y && y < s.y + s.height)
                return s;
        }
        return screens.length > 0 ? screens[0] : null;
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
            root.cancelIntro();
            root.setZoom(z);
            return String(root.zoom);
        }

        function status(): string {
            return JSON.stringify({
                zoom: root.zoom,
                pendingZoom: root.pendingZoom,
                active: root.active,
                cursor: [root.cursorX, root.cursorY]
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
                    if (typeof z === "number" && !root.starting)
                        root.zoom = root.clamp(z);
                } catch (e) {}
            }
        }
    }

    // Don't leave the screen zoomed when the plugin is disabled
    Component.onDestruction: {
        if (root.zoom > 1)
            Quickshell.execDetached(["hyprctl", "eval", "hl.config({cursor={zoom_factor=1.0}})"]);
    }

    // ---- pointer position ---------------------------------------------------

    Process {
        id: cursorProc
        command: ["hyprctl", "cursorpos", "-j"]
        stdout: StdioCollector {
            onStreamFinished: {
                try {
                    const obj = JSON.parse(text);
                    if (typeof obj.x === "number" && typeof obj.y === "number") {
                        root.cursorX = obj.x;
                        root.cursorY = obj.y;
                    }
                } catch (e) {}
                if (root.pendingShow)
                    root.open();
            }
        }
    }

    // Opens even if the position read fails (uses the last known position)
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
            outro.restart();
        }
    }

    NumberAnimation {
        id: outro
        target: root
        property: "dim"
        to: 0
        duration: 200
        easing.type: Easing.InQuad
        onFinished: root.active = false
    }

    // ---- overlay ------------------------------------------------------------

    Loader {
        active: root.active

        sourceComponent: PanelWindow {
            id: win
            readonly property var targetScreen: root.screenAt(root.cursorX, root.cursorY)

            // Pointer in this window's coordinates
            readonly property real cx: root.cursorX - (win.targetScreen?.x ?? 0)
            readonly property real cy: root.cursorY - (win.targetScreen?.y ?? 0)

            screen: win.targetScreen
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
