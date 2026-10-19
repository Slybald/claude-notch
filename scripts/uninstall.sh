#!/bin/sh
# Retire les hooks, le LaunchAgent et l'app.
set -eu

ROOT=$(cd "$(dirname "$0")/.." && pwd)
LABEL=local.claudenotch
CONFIG_DIR=${CLAUDE_CONFIG_DIR:-$HOME/.claude}
AGENT="$HOME/Library/LaunchAgents/$LABEL.plist"

/usr/bin/python3 -I "$ROOT/scripts/hooks_config.py" uninstall
rm -f "$CONFIG_DIR/hooks/claude-notch-hook.sh"

launchctl bootout "gui/$(id -u)/$LABEL" 2>/dev/null || true
rm -f "$AGENT"

pkill -x ClaudeNotch 2>/dev/null || true
for dir in /Applications "$HOME/Applications"; do
    if [ -d "$dir/ClaudeNotch.app" ]; then
        rm -rf "$dir/ClaudeNotch.app"
        echo "App supprimée : $dir/ClaudeNotch.app"
    fi
done
echo "Claude Notch désinstallé."
