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
        settingKey: "pollIntervalSec"
        label: "Fallback refresh"
        description: "Full refresh interval; changes are normally picked up instantly from docker events"
        defaultValue: 30
        minimum: 5
        maximum: 300
        unit: "s"
    }
}
