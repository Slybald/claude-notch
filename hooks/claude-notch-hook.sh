#!/bin/sh
# Hook Claude Code de Claude Notch : parle à l'app sur http://127.0.0.1:47823, avec le jeton qu'elle écrit dans
# un fichier 0600 (passé à curl par -H @fichier, jamais en argument). Trois modes :
#   (sans argument)  relaie l'événement vers /hook. Lancé en `async: true` : aucune latence. Sort avec 0.
#   permission       PermissionRequest synchrone : la décision prise dans la notch (JSON) part sur la sortie
#                    standard. Sans décision, app arrêtée ou réglage coupé : rien, le dialogue du terminal garde
#                    la main (jamais d'autorisation par défaut).
#   inbox            attente `asyncRewake` (SessionStart, Stop) d'un message envoyé depuis la notch : le texte
#                    part sur stderr avec le code 2, ce qui réveille Claude. Sinon 0.

URL="http://127.0.0.1:${CLAUDE_NOTCH_PORT:-47823}"
TOKEN="$HOME/Library/Application Support/ClaudeNotch/hook-token"

case "${1:-}" in
permission)
    [ -r "$TOKEN" ] || exit 0
    # exec : un « No » au terminal tue curl (SIGTERM), l'app voit la connexion se fermer et retire sa carte.
    exec curl -q -sf --noproxy "*" --connect-timeout 0.5 --max-time 598 \
        -H @"$TOKEN" \
        -H 'Content-Type: application/json' \
        -H 'Expect:' \
        -H "X-Claude-PPID: $PPID" \
        --data-binary @- \
        "$URL/permission"
    ;;
inbox)
    [ -r "$TOKEN" ] || exit 0
    IN=$(mktemp "${TMPDIR:-/tmp}/claude-notch.XXXXXX") || exit 0
    OUT=$(mktemp "${TMPDIR:-/tmp}/claude-notch.XXXXXX") || { rm -f "$IN"; exit 0; }
    trap 'rm -f "$IN" "$OUT"' EXIT
    # Hook arrêté (fin de session, timeout) : curl part avec lui, l'app voit l'attente se fermer.
    CURL=
    trap 'if [ -n "$CURL" ]; then kill "$CURL" 2>/dev/null; fi; exit 0' HUP INT TERM
    cat > "$IN"
    curl -q -sf --noproxy "*" -o "$OUT" --connect-timeout 0.5 --max-time 86000 \
        -H @"$TOKEN" \
        -H 'Content-Type: application/json' \
        -H 'Expect:' \
        -H "X-Claude-PPID: $PPID" \
        --data-binary @"$IN" \
        "$URL/inbox" &
    CURL=$!
    wait "$CURL" || exit 0
    [ -s "$OUT" ] || exit 0
    cat "$OUT" >&2
    exit 2
    ;;
esac

TMP=$(mktemp "${TMPDIR:-/tmp}/claude-notch.XXXXXX") || exit 0
trap 'rm -f "$TMP"' EXIT
trap 'exit 0' HUP INT TERM
cat > "$TMP"

send() {
    curl -q -s --noproxy "*" -o /dev/null --connect-timeout 0.5 --max-time 2 \
        -H @"$TOKEN" \
        -H 'Content-Type: application/json' \
        -H 'Expect:' \
        -H "X-Claude-PPID: $PPID" \
        -H "X-Term-Program: ${TERM_PROGRAM:-}" \
        -H "X-Bundle-Id: ${__CFBundleIdentifier:-}" \
        -H "X-Entrypoint: ${CLAUDE_CODE_ENTRYPOINT:-}" \
        -H "X-Task-List-Id: ${CLAUDE_CODE_TASK_LIST_ID:-}" \
        -H "X-Config-Dir: ${CLAUDE_CONFIG_DIR:-}" \
        -H "X-Host-Session-Id: ${CLAUDE_CODE_HOST_SESSION_ID:-}" \
        --data-binary @"$TMP" \
        "$URL/hook" 2>/dev/null
}

if ! send; then
    # App fermée (ou jeton pas encore écrit) : on la relance au début d'une session ou d'un tour, puis on réessaie.
    if grep -Eq '"hook_event_name"[[:space:]]*:[[:space:]]*"(SessionStart|UserPromptSubmit)"' "$TMP"; then
        open -g -b io.github.slybald.claudenotch >/dev/null 2>&1 || exit 0
        i=0
        while [ "$i" -lt 10 ]; do
            sleep 0.3
            send && break
            i=$((i + 1))
        done
    fi
fi
exit 0
