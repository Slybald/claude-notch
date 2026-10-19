#!/bin/sh
# Relaie un événement de hook Claude Code vers Claude Notch (http://127.0.0.1:47823/hook).
# Lancé en `async: true` : n'ajoute aucune latence à Claude. Sort toujours avec 0.

TMP=$(mktemp "${TMPDIR:-/tmp}/claude-notch.XXXXXX") || exit 0
trap 'rm -f "$TMP"' EXIT
trap 'exit 0' HUP INT TERM
cat > "$TMP"

send() {
    curl -s -o /dev/null --connect-timeout 0.5 --max-time 2 \
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
        http://127.0.0.1:47823/hook
}

if ! send; then
    # App fermée : on la relance au début d'une session ou d'un tour, puis on réessaie.
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
