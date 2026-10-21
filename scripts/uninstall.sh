#!/bin/sh
# Retire les hooks, le LaunchAgent et l'app.
set -eu

ROOT=$(cd "$(dirname "$0")/.." && pwd)
CONFIG_DIR=${CLAUDE_CONFIG_DIR:-$HOME/.claude}

/usr/bin/python3 -I "$ROOT/scripts/hooks_config.py" uninstall
rm -f "$CONFIG_DIR/hooks/claude-notch-hook.sh"
if grep -qs claude-notch-statusline.sh "$CONFIG_DIR/settings.json"; then
    echo "Relais de statusLine encore posé dans $CONFIG_DIR/settings.json : retire-le d'abord (Réglages > Claude > Jauges de quota)."
fi
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
    echo "Règle sudo de Claude Notch trouvée ($LOWPOWER_RULE) : retrait avec sudo, ton mot de passe est demandé."
    sudo /bin/rm -f "$LOWPOWER_RULE" || echo "Règle non retirée. Pour la retirer : sudo rm $LOWPOWER_RULE"
fi

# Outil des ventilateurs et sa règle sudo (Réglages rapides) : l'app quitte d'abord (sa tenue rend la main à
# macOS), puis l'outil remet l'automatique une dernière fois avant d'être retiré.
FAN_HELPER=/Library/PrivilegedHelperTools/io.github.slybald.claudenotch.fanctl
FAN_RULE=/etc/sudoers.d/claude-notch-fans
pkill -x ClaudeNotch 2>/dev/null || true
if [ -e "$FAN_HELPER" ] || [ -e "$FAN_RULE" ]; then
    echo "Outil des ventilateurs de Claude Notch trouvé : retrait avec sudo, ton mot de passe est demandé."
    sudo /bin/sh -c "[ -x $FAN_HELPER ] && $FAN_HELPER auto; /bin/rm -f $FAN_RULE $FAN_HELPER" \
        || echo "Outil non retiré. Pour le retirer : sudo rm $FAN_RULE $FAN_HELPER"
fi
for dir in /Applications "$HOME/Applications"; do
    if [ -d "$dir/ClaudeNotch.app" ]; then
        rm -rf "$dir/ClaudeNotch.app"
        echo "App supprimée : $dir/ClaudeNotch.app"
    fi
done
echo "Claude Notch désinstallé."
