import QtQuick
import Quickshell
import qs.Common
import qs.Services
import qs.Widgets
import qs.DCommon.Widgets
import qs.Modules.Plugins

PluginComponent {
    id: root

    // Settings
    readonly property string displayMode: pluginData.displayMode ?? "both"   // "both" | "flag" | "text"
    readonly property string labelStyle: pluginData.labelStyle ?? "code"     // "code" | "name"

    // Same data source as DMS's built-in keyboard layout widget
    readonly property string compactName: KeyboardLayoutService.compactLayout ?? ""
    readonly property string fullName: KeyboardLayoutService.currentLayout ?? ""

    // Language name -> xkb layout code, for compositors that only report full
    // names (niri/sway: "English (US)", "Italian", ...)
    readonly property var nameCodes: ({
        "english": "us", "italian": "it", "german": "de", "french": "fr",
        "spanish": "es", "portuguese": "pt", "russian": "ru", "ukrainian": "ua",
        "polish": "pl", "czech": "cz", "slovak": "sk", "hungarian": "hu",
        "romanian": "ro", "bulgarian": "bg", "greek": "gr", "turkish": "tr",
        "dutch": "nl", "swedish": "se", "norwegian": "no", "danish": "dk",
        "finnish": "fi", "estonian": "ee", "latvian": "lv", "lithuanian": "lt",
        "croatian": "hr", "serbian": "rs", "slovenian": "si", "japanese": "jp",
        "korean": "kr", "chinese": "cn", "arabic": "ara", "hebrew": "il",
        "persian": "ir", "hindi": "in", "thai": "th", "vietnamese": "vn",
        "icelandic": "is", "irish": "ie", "belarusian": "by", "georgian": "ge",
        "armenian": "am", "esperanto": "epo"
    })

    // xkb layout codes that are not ISO-3166 country codes
    readonly property var countryExceptions: ({
        "uk": "GB", "en": "GB", "latam": "MX", "ara": "SA", "epo": "", "brai": "",
        "custom": ""
    })

    // Lowercase xkb layout code without variant ("us", "it", ...)
    readonly property string layoutCode: {
        const compact = root.compactName.trim();
        if (compact.length > 0 && compact !== "Unknown" && /^[a-z]{2,5}(-|$)/i.test(compact) && !compact.includes(" "))
            return compact.split("-")[0].toLowerCase();
        const name = root.fullName.trim();
        if (name.length === 0 || name === "Unknown")
            return "";
        // "English (US)" -> "us", "English (UK)" -> "gb"
        const paren = name.match(/\(([A-Za-z]{2})\)/);
        if (paren)
            return paren[1].toLowerCase();
        const first = name.split(/[\s(]/)[0].toLowerCase();
        return root.nameCodes[first] ?? "";
    }

    readonly property string countryCode: {
        const c = root.layoutCode;
        if (c.length === 0)
            return "";
        if (c in root.countryExceptions)
            return root.countryExceptions[c];
        return /^[a-z]{2}$/.test(c) ? c.toUpperCase() : "";
    }

    // Two regional indicator symbols -> flag emoji
    readonly property string flag: root.countryCode.length === 2
        ? String.fromCodePoint(0x1F1E6 + root.countryCode.charCodeAt(0) - 65, 0x1F1E6 + root.countryCode.charCodeAt(1) - 65)
        : ""

    readonly property string codeLabel: root.layoutCode.length > 0 ? root.layoutCode.toUpperCase() : "?"
    readonly property string label: root.labelStyle === "name" && root.fullName.length > 0 && root.fullName !== "Unknown"
        ? root.fullName
        : root.codeLabel

    readonly property bool showFlag: displayMode !== "text"
    readonly property bool showText: displayMode !== "flag"

    pillClickAction: () => KeyboardLayoutService.cycle()

    Component.onCompleted: KeyboardLayoutService.consumers++
    Component.onDestruction: KeyboardLayoutService.consumers--

    component FlagGlyph: Item {
        implicitWidth: root.flag.length > 0 ? flagText.implicitWidth : fallbackIcon.size
        implicitHeight: root.flag.length > 0 ? flagText.implicitHeight : fallbackIcon.size

        Text {
            id: flagText
            anchors.centerIn: parent
            visible: root.flag.length > 0
            text: root.flag
            font.family: "Noto Color Emoji"
            font.pixelSize: Math.round(root.iconSize * 1.05)
        }

        DIcon {
            id: fallbackIcon
            anchors.centerIn: parent
            visible: root.flag.length === 0
            name: "keyboard"
            size: Math.round(root.iconSize * 1.25)
            color: Theme.surfaceText
        }
    }

    horizontalBarPill: Component {
        Item {
            implicitWidth: hRow.implicitWidth
            implicitHeight: hRow.implicitHeight
            Accessible.name: "Keyboard layout: " + root.label

            Row {
                id: hRow
                spacing: Theme.spacingXS

                FlagGlyph {
                    visible: root.showFlag
                    anchors.verticalCenter: parent.verticalCenter
                }

                StyledText {
                    text: root.label
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
            Accessible.name: "Keyboard layout: " + root.label

            Column {
                id: vCol
                spacing: Theme.spacingXS

                FlagGlyph {
                    visible: root.showFlag
                    anchors.horizontalCenter: parent.horizontalCenter
                }

                StyledText {
                    text: root.codeLabel.slice(0, 3)
                    font.pixelSize: root.textSize
                    color: Theme.surfaceText
                    visible: root.showText
                    anchors.horizontalCenter: parent.horizontalCenter
                }
            }
        }
    }
}
