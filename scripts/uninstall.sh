#!/bin/sh
# Retire les hooks, le LaunchAgent et l'app.
set -eu

ROOT=$(cd "$(dirname "$0")/.." && pwd)
CONFIG_DIR=${CLAUDE_CONFIG_DIR:-$HOME/.claude}

/usr/bin/python3 -I "$ROOT/scripts/hooks_config.py" uninstall
rm -f "$CONFIG_DIR/hooks/claude-notch-hook.sh"
if grep -qs codex-notch-hook.sh "$HOME/.codex/hooks.json"; then
    echo "Hooks Codex encore posés dans ~/.codex/hooks.json : retire-les d'abord (Réglages > Codex > Retirer les hooks)."
fi

# Identifiant actuel, puis celui des premières versions.
for LABEL in io.github.slybald.claudenotch local.claudenotch; do
    launchctl bootout "gui/$(id -u)/$LABEL" 2>/dev/null || true
    rm -f "$HOME/Library/LaunchAgents/$LABEL.plist"
done

# Règle sudo de l'économie d'énergie, posée par l'app à la demande de l'utilisateur : root seul peut la retirer.
LOWPOWER_RULE=/etc/sudoers.d/claude-notch-lowpower
if [ -e "$LOWPOWER_RULE" ]; then
    echo "Règle sudo d'Oriel trouvée ($LOWPOWER_RULE) : retrait avec sudo, ton mot de passe est demandé."
    sudo /bin/rm -f "$LOWPOWER_RULE" || echo "Règle non retirée. Pour la retirer : sudo rm $LOWPOWER_RULE"
fi

pkill -x ClaudeNotch 2>/dev/null || true
# Nom actuel, puis celui d'avant le renommage.
for dir in /Applications "$HOME/Applications"; do
    for app in Oriel.app ClaudeNotch.app; do
        if [ -d "$dir/$app" ]; then
            rm -rf "${dir:?}/$app"
            echo "App supprimée : $dir/$app"
        fi
    done
done
echo "Oriel désinstallé."
