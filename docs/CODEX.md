# Codex in the notch: what is possible, and why

Short feasibility notes behind the **Codex** tab. Everything below was checked on a real Mac with Codex CLI
0.154.0 (macOS, ChatGPT sign-in), not assumed. [Français plus bas](#codex-dans-la-notch).

## Conclusion

Codex ships **hooks** (the same idea as Claude Code's), which is the official, supported way to follow a session and
to answer an approval. Claude Notch uses them, and nothing else:

| Need | Source | Status |
| --- | --- | --- |
| Which sessions run, working / done, last message | hooks `SessionStart`, `UserPromptSubmit`, `PreToolUse`, `PostToolUse`, `Stop`, `Interrupt`, `SessionEnd` | works |
| Approve or deny a command or a patch | hook `PermissionRequest` (synchronous) | works, with a short hold (see below) |
| Open the session | bring the host app (terminal, editor, Codex app) to the front | works |
| Send a free message to a running session | none that is safe | not possible |
| Answer Codex's own questions (`request_user_input`) | none (no hook; app-server only) | not possible |

## What was measured

- **Hooks** live in `~/.codex/hooks.json` (or inline `[hooks]` in `config.toml`, or per project). Several sources
  run together, so ours never replaces the user's. `[features] hooks = false` turns them all off.
- **Trust**: a new or changed hook is skipped until the user reviews it with `/hooks` in Codex. Codex then writes
  `hooks.state."<file>:<event>:<group>:<hook>".trusted_hash` in `config.toml`. Claude Notch does not write this: the
  review stays the user's. `hooks/list` (app-server) reports `trustStatus` (`untrusted`, `trusted`, `modified`).
- **Payload** (stdin JSON): `session_id`, `cwd`, `hook_event_name`, `model`, `permission_mode`, `transcript_path`
  (null here), plus `turn_id`, `prompt` (`UserPromptSubmit`), `tool_name` / `tool_input` / `tool_use_id`
  (`PreToolUse`, `PostToolUse`), `tool_response` (`PostToolUse`), `last_assistant_message` (`Stop`). `PermissionRequest`
  has `tool_name` and `tool_input` (`command`, `description`) but no `tool_use_id`. Tools: `Bash`, `apply_patch`
  (the patch is in `tool_input.command`), `mcp__<server>__<tool>`.
- **`$PPID` of the hook is the `codex` process** (CLI, or the app's server), the same for every event of a run.
  That gives the host app (by walking up) and a `kqueue` to notice the end of the process.
- **`PermissionRequest` output**: `{"hookSpecificOutput":{"hookEventName":"PermissionRequest","decision":{"behavior":"allow"}}}`
  or `"deny"` with a `message`. `allow` runs the command without Codex's prompt; `deny` blocks it (Codex reports the
  message). No `updatedInput`, no `updatedPermissions`. No decision: Codex shows its normal prompt.
- **The hook runs before Codex's prompt, and the prompt waits for it** (a hook held for 6 s delayed the prompt by 6 s).
  Unlike Claude Code, the terminal does not show its dialog in parallel. So the notch holds a request for 4 s if its
  card was never shown, 60 s once it was, then gives the hand back; the hook timeout in `hooks.json` is 75 s.
  "In the terminal" gives it back at once.
- `codex exec` forces `approval: never`: `PermissionRequest` never fires there. It fires in the interactive CLI and
  through `codex app-server`, which the Codex app builds on. (The app's window itself was not driven.)
- `SessionEnd` and `Interrupt` hooks are capped at 3 s by Codex. Hooks marked `async` cannot block, which suits relays. They
  do run, but Codex announces only the synchronous ones (`hook/started`, `hook/completed`), and a relay can reach the app
  *after* the synchronous `PermissionRequest` of the same call: the store ignores such late tool events for 1.5 s
  (`CodexStore.reorderWindow`). They are killed with Codex, so a relay sent just before it exits can be lost.
- Re-checking it all with a real Codex: `CLAUDE_NOTCH_CODEX_LIVE=1 swift test --filter CodexLiveTests` runs three short
  turns (allow, deny, "in the terminal") through the real installer, script and server, in a throwaway `CODEX_HOME`
  (only `auth.json` is a link to the real one) and uses a little quota.

## What was not used, and why

- **`notify`** in `config.toml`: one program only, called on `agent-turn-complete` only (no approval, no start), and it
  is often already taken by another tool. Using it would mean overwriting that or chaining a wrapper around it. So
  `config.toml` is never written. Settings › Codex states it.
- **Session files** (`~/.codex/sessions/…/rollout-*.jsonl.zst`): in 0.154 they are zstd-compressed, with SQLite state
  beside them; an internal format that changes between versions. Hooks give everything the notch needs, so no file is
  watched or read.
- **app-server** (JSON-RPC over stdio / WebSocket / Unix socket): approvals are *server requests* answered by the client
  that owns the thread (`item/commandExecution/requestApproval`, `item/fileChange/requestApproval`), and
  `thread/status/changed` carries `waitingOnApproval`, but only for the connected client. A second program cannot
  observe or answer another client's threads, except through the experimental shared daemon (`codex app-server daemon`,
  `codex agents`, `codex queue --thread … --message …`), which a normal CLI or app session is not on. Not used.
- **A free message to a running session** would need a `Stop` hook held open (Codex waits for it, so the terminal is
  stuck) or the daemon above. Neither is safe. The card offers to bring the session to the front instead.

## Installing and removing

Settings › Codex › **Install Codex hooks** copies `codex-notch-hook.sh` to `~/.codex/hooks/` and adds one entry per
event to `~/.codex/hooks.json`, after a timestamped backup (`hooks.json.claude-notch-YYYYMMDD-HHMMSS.bak`). It keeps
the user's own hooks and key order, writes nothing when nothing changes, refuses an invalid file, and never touches
`config.toml` or its `notify`. **Remove the hooks** (or Uninstall Claude Notch) takes only its entries away. Then run
`/hooks` in Codex once to trust them.

---

# Codex dans la notch

Notes de faisabilité derrière l'onglet **Codex**, vérifiées sur un vrai Mac (Codex CLI 0.154.0), pas supposées.

## Conclusion

Codex a des **hooks** (même principe que ceux de Claude Code) : c'est la voie officielle pour suivre une session et
répondre à une approbation. Claude Notch n'utilise qu'eux.

- **Marche** : sessions en cours, travaille / terminé, dernier message ; autoriser ou refuser une commande ou un patch
  (hook `PermissionRequest` synchrone) ; ramener l'app hôte devant.
- **Impossible** : envoyer un message libre à une session qui tourne (il faudrait un hook `Stop` tenu, que Codex attend :
  le terminal resterait bloqué ; ou le démon partagé expérimental) ; répondre aux questions propres de Codex
  (`request_user_input` : aucun hook, app-server seulement).

## Points mesurés

- Hooks dans `~/.codex/hooks.json` ; ils s'ajoutent à ceux de l'utilisateur. Un hook neuf ou modifié est **ignoré tant
  que l'utilisateur ne l'a pas validé** avec `/hooks` dans Codex : Claude Notch n'écrit pas cette validation.
- Le hook tourne **avant** l'invite de Codex et **elle l'attend** : contrairement à Claude Code, le terminal n'affiche
  pas son dialogue en parallèle. La notch tient donc la demande 4 s si sa carte n'a jamais été vue, 60 s sinon, puis
  rend la main (sans décision) ; « Dans le terminal » la rend tout de suite. Timeout du hook : 75 s.
- `codex exec` force `approval: never` : pas de `PermissionRequest` là. Il se déclenche en CLI interactif et via
  `codex app-server` (base de l'app Codex). La fenêtre de l'app elle-même n'a pas été pilotée.
- `$PPID` du hook = le processus `codex` : l'app hôte s'en déduit, et un `kqueue` voit la fin du processus.

## Pas utilisé

- **`notify`** : un seul programme, seulement `agent-turn-complete`, souvent déjà pris par un autre outil. `config.toml`
  n'est donc jamais écrit.
- **Fichiers de session** (`rollout-*.jsonl.zst`) : compressés en zstd en 0.154, format interne changeant : les hooks
  suffisent, aucun fichier n'est lu ni surveillé.
- **app-server** : les approbations sont des requêtes serveur adressées au client qui possède le fil ; un second
  programme ne peut ni les voir ni y répondre.

## Pose et retrait

Réglages › Codex › **Installer les hooks Codex** : copie du script dans `~/.codex/hooks/`, une entrée par événement dans
`~/.codex/hooks.json`, après une sauvegarde horodatée ; tes hooks et l'ordre des clés restent ; rien n'est écrit si rien
ne change ; un fichier invalide est refusé ; `config.toml` et son `notify` ne sont jamais touchés. **Retirer les hooks**
(ou désinstaller Claude Notch) n'enlève que nos entrées. Ensuite, tape `/hooks` dans Codex une fois pour les valider.
