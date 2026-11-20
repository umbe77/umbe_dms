#!/usr/bin/env bash
# Symlink the plugins in this repo into the DMS plugins directory.
# Each subdirectory containing a plugin.json is one plugin.
# Usage: ./install.sh [--uninstall] [plugin-dir ...]
set -euo pipefail

REPO_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
PLUGINS_DIR="${XDG_CONFIG_HOME:-$HOME/.config}/dms/plugins"

UNINSTALL=0
if [[ "${1:-}" == "--uninstall" ]]; then
    UNINSTALL=1
    shift
fi

# Plugin source dirs: the ones named on the command line, or all of them
SOURCES=()
if [[ $# -gt 0 ]]; then
    for d in "$@"; do SOURCES+=("$REPO_DIR/${d%/}"); done
else
    for f in "$REPO_DIR"/*/plugin.json; do SOURCES+=("$(dirname "$f")"); done
fi

plugin_id() {
    sed -n 's/^[[:space:]]*"id"[[:space:]]*:[[:space:]]*"\([^"]*\)".*/\1/p' "$1/plugin.json" | head -n1
}

points_into_repo() {
    # $1 = target link, $2 = expected source dir (or the repo root, for the old layout)
    [[ -L "$1" ]] && [[ "$(readlink -f "$1")" == "$(readlink -f "$2")" ]]
}

dms_running() {
    command -v dms >/dev/null 2>&1 && systemctl --user is-active --quiet dms 2>/dev/null
}

[[ $UNINSTALL -eq 0 ]] && mkdir -p "$PLUGINS_DIR"
INSTALLED_IDS=()

for SRC in "${SOURCES[@]}"; do
    if [[ ! -f "$SRC/plugin.json" ]]; then
        echo "Skipping $SRC: no plugin.json" >&2
        continue
    fi
    ID="$(plugin_id "$SRC")"
    if [[ -z "$ID" ]]; then
        echo "Skipping $SRC: no id in plugin.json" >&2
        continue
    fi
    TARGET="$PLUGINS_DIR/$ID"

    if [[ $UNINSTALL -eq 1 ]]; then
        if points_into_repo "$TARGET" "$SRC" || points_into_repo "$TARGET" "$REPO_DIR"; then
            rm "$TARGET"
            echo "Removed $TARGET"
        elif [[ -e "$TARGET" || -L "$TARGET" ]]; then
            echo "Error: $TARGET does not point into $REPO_DIR; leaving it alone." >&2
        else
            echo "Nothing to uninstall for $ID ($TARGET does not exist)."
        fi
        continue
    fi

    if points_into_repo "$TARGET" "$SRC"; then
        echo "Already installed: $TARGET -> $SRC"
    elif [[ -L "$TARGET" ]]; then
        echo "Replacing existing symlink $TARGET -> $(readlink "$TARGET")"
        ln -sfn "$SRC" "$TARGET"
    elif [[ -e "$TARGET" ]]; then
        echo "Error: $TARGET exists and is not a symlink; refusing to overwrite." >&2
        continue
    else
        ln -s "$SRC" "$TARGET"
        echo "Installed: $TARGET -> $SRC"
    fi

    INSTALLED_IDS+=("$ID")
done

# Enable the plugins in the running shell (best effort). The scan is debounced,
# so give it a moment before enabling.
if [[ $UNINSTALL -eq 0 && ${#INSTALLED_IDS[@]} -gt 0 ]] && dms_running; then
    dms ipc call plugin-scan scan >/dev/null 2>&1 || true
    sleep 2
    for ID in "${INSTALLED_IDS[@]}"; do
        echo "Enabling $ID: $(dms ipc call plugins enable "$ID" 2>&1 || true)"
    done
fi

if [[ $UNINSTALL -eq 0 ]]; then
    dms_running || echo "DMS is not running; enable the plugins in DMS Settings -> Plugins after starting it."
    cat <<MSG

Next step: restart DMS (dms restart), then DMS Settings -> Dank Bar -> add the widgets to a section.
MSG
fi
