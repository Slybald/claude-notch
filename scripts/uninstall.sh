#!/bin/sh
# Retire les hooks, le LaunchAgent et l'app.
set -eu

ROOT=$(cd "$(dirname "$0")/.." && pwd)
CONFIG_DIR=${CLAUDE_CONFIG_DIR:-$HOME/.claude}

/usr/bin/python3 -I "$ROOT/scripts/hooks_config.py" uninstall
rm -f "$CONFIG_DIR/hooks/claude-notch-hook.sh"

# Identifiant actuel, puis celui des premières versions.
for LABEL in io.github.slybald.claudenotch local.claudenotch; do
    launchctl bootout "gui/$(id -u)/$LABEL" 2>/dev/null || true
    rm -f "$HOME/Library/LaunchAgents/$LABEL.plist"
done

# Règle sudo de l'économie d'énergie, posée par l'app à la demande de l'utilisateur : root seul peut la retirer.
LOWPOWER_RULE=/etc/sudoers.d/claude-notch-lowpower
if [ -e "$LOWPOWER_RULE" ]; then
    echo "Règle sudo de Claude Notch trouvée ($LOWPOWER_RULE) : retrait avec sudo, ton mot de passe est demandé."
    sudo /bin/rm -f "$LOWPOWER_RULE" || echo "Règle non retirée. Pour la retirer : sudo rm $LOWPOWER_RULE"
fi

pkill -x ClaudeNotch 2>/dev/null || true
for dir in /Applications "$HOME/Applications"; do
    if [ -d "$dir/ClaudeNotch.app" ]; then
        rm -rf "$dir/ClaudeNotch.app"
        echo "App supprimée : $dir/ClaudeNotch.app"
    fi
done
echo "Claude Notch désinstallé."
