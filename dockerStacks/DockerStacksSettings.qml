import QtQuick
import qs.Common
import qs.Widgets
import qs.Modules.Plugins

PluginSettings {
    id: root
    pluginId: "dockerStacks"

    StyledText {
        width: parent.width
        text: "Docker Stacks"
        font.pixelSize: Theme.fontSizeLarge
        font.weight: Font.Bold
        color: Theme.surfaceText
    }

    StyledText {
        width: parent.width
        text: "Click the bar pill to manage containers, grouped by compose project. Your user must be able to reach the Docker socket (e.g. be in the docker group)."
        font.pixelSize: Theme.fontSizeSmall
        color: Theme.surfaceVariantText
        wrapMode: Text.WordWrap
    }

    StringSetting {
        settingKey: "dockerBin"
        label: "Docker command"
        description: "Executable used for all calls (name on PATH or absolute path)"
        placeholder: "docker"
        defaultValue: "docker"
    }

    ToggleSetting {
        settingKey: "showCount"
        label: "Show running count"
        description: "Show the number of running containers next to the icon"
        defaultValue: true
    }

    ToggleSetting {
        settingKey: "showStandalone"
        label: "Show standalone containers"
        description: "List containers that are not part of a compose project"
        defaultValue: true
    }

    SliderSetting {
        settingKey: "logTail"
        label: "Log history"
        description: "Past log lines loaded when the logs pane opens"
        defaultValue: 200
        minimum: 50
        maximum: 2000
        unit: " lines"
    }

    StringSetting {
        settingKey: "terminalCmd"
        label: "Terminal"
        description: "Terminal used for container shells; empty uses the DMS terminal or $TERMINAL"
        placeholder: "auto"
        defaultValue: ""
    }

    StringSetting {
        settingKey: "terminalExecFlag"
        label: "Terminal exec flag"
        description: "Argument(s) before the command: -e for kitty, ghostty, foot, alacritty; \"start --\" for wezterm"
        placeholder: "-e"
        defaultValue: "-e"
    }

    SliderSetting {
        settingKey: "pollIntervalSec"
        label: "Fallback refresh"
        description: "Full refresh interval; changes are normally picked up instantly from docker events"
        defaultValue: 30
        minimum: 5
        maximum: 300
        unit: "s"
    }
}
