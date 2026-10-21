# Codex in the notch: what is possible, and why

Short feasibility notes behind the **Codex** tab. Everything below was checked on a real Mac with Codex CLI
0.154.0 and with the Codex inside the ChatGPT app (0.162, macOS, ChatGPT sign-in), not assumed.
[Français plus bas](#codex-dans-la-notch).

## Conclusion

Codex ships **hooks** (the same idea as Claude Code's), which is the official, supported way to follow a session and
to answer an approval. Claude Notch uses them, and nothing else:

| Need | Source | Status |
| --- | --- | --- |
| Which sessions run, working / done, last message | hooks `SessionStart`, `UserPromptSubmit`, `PreToolUse`, `PostToolUse`, `Stop`, `Interrupt`, `SessionEnd` | works |
| Approve or deny a command or a patch | hook `PermissionRequest` (synchronous) | works, with a short hold (see below) |
| Open the session | bring the host app (terminal, editor, ChatGPT app) to the front; ChatGPT app: `codex://threads/<id>` | works (the link comes from the app's routing, not clicked live) |
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

## The ChatGPT app (Codex 0.162)

The Codex app is now part of **ChatGPT** (`/Applications/ChatGPT.app`, bundle `com.openai.codex`, URL scheme `codex://`).
It embeds its own CLI (`Contents/Resources/codex-cli/CodexCLI.app`, codex-cli 0.162) and runs `codex app-server` over
stdio as a child process, on the default `~/.codex`. Measured with that very binary:

- **Same hooks, same file.** `~/.codex/hooks.json` is read by the app's server. The hook's `$PPID` is that
  `codex app-server` process, whose path is inside `ChatGPT.app`: the card's source reads **ChatGPT** and `Open` knows
  the bundle. `PermissionRequest` fires there too (policy `on-request`), so approving from the notch works in the app.
- **Silent until approved.** With a new, unapproved hook the server ran no hook at all (0 calls), and the app does not
  say so in the conversation. The app has its own screen for it: a **Review hooks** button (yellow dot) in the composer
  and Settings › Hooks. Both send `hooks/list` and then `config/batchWrite`.
- **The official method.** There is no dedicated "trust" request. `hooks/list` returns, per hook, `key`, `command`,
  `sourcePath`, `trustStatus` (`trusted`, `untrusted`, `modified`, `managed`) and `currentHash`; approving is
  `config/batchWrite` with `hooks.state."<key>".trusted_hash = <currentHash>` (`upsert`): the app's own dialog does exactly
  this. `key` is `<real path of hooks.json>:<event in snake_case>:<group>:<rank>` (the path is canonical, `/var` shows as
  `/private/var`; group and rank are the positions in hooks.json).
- **No restart.** A second process can approve (the running server sees `trusted` on its next `hooks/list`), and the app
  does not need to be relaunched. But hooks are fixed when a conversation starts: an open conversation keeps running
  without them (a second turn ran no hook), a **new** one runs them. Hence "start a new conversation".
- **Modified hooks ask again.** `trustStatus` becomes `modified` as soon as the entry changes (a new timeout, another
  path), which is why updating the hooks asks for a new approval.
- **Deep link.** The app's URL router has a `threads` route (`codex://threads/<thread id>`, the id being the hook's
  `session_id`) that opens the conversation. Not clicked live, so as not to move the user's window.
- **Speed.** `hooks/list` answers in 0.1 to 0.5 s on a warm `CODEX_HOME`, 8 to 15 s on a brand-new one.

## What Claude Notch does with it

- **State, read only.** `hooks.json` and `config.toml` (never written) give an estimate: not installed, installed, and
  per hook whether `config.toml` has a `trusted_hash` for its key. Then `codex app-server` is started for a moment
  (the app's own binary first, else the `codex` command; minimal environment, `CODEX_HOME` set) and `hooks/list` tells
  the truth (`modified` included). This runs by itself only while approval is pending (at most every 30 s); once the hooks
  are active no Codex process is started for the hooks unless you press **Check** (the quota gauge below starts its own, short
  one while the panel is open). The tab says: *hooks not installed* → *to approve in Codex* → *active*. Any hook event
  received also proves they run. While approval is pending and a view is shown, two `stat` calls every 2.5 s notice an
  approval made elsewhere (`/hooks`, the app), so the tab updates by itself; nothing runs when it is not pending.
- **Approve, only on a click.** **Approve in Codex** (tab or Settings) starts `codex app-server`, lists the hooks, and
  sends `config/batchWrite` for the hooks whose command is our script *and* whose file is this `hooks.json`, nothing else,
  then lists again. Codex writes `config.toml` itself; the app never does.
- **Quota gauge** (Settings › Codex › Show quota, on by default). `account/rateLimits/read` returns `rateLimits.primary` and
  `secondary` (`usedPercent`, `windowDurationMins`, `resetsAt` in seconds), `planType` and `credits`; the schema comes from
  `codex app-server generate-json-schema`. Measured with the app's Codex 0.162 and the `codex` command 0.154 on a ChatGPT
  sign-in: `primary` 300 min (5 h), `secondary` 10 080 min (7 days), the same figures from both, answered in 1.2 s,
  one extra notification (`remoteControl/status/changed`) and no token in the answer. Codex reads it with its own sign-in;
  the app starts `codex app-server` (same binary, minimal environment) and sends this one request. Only while the panel is
  open: at once if the last figure is older than a minute, then every 5 minutes, one timer, stopped when the panel closes. An
  error (API key, no sign-in, no Codex) keeps the last figure and waits 15 minutes. The `account/rateLimits/updated`
  notification only reaches a client that owns a thread, so it is not used.

## What was not used, and why

- **`notify`** in `config.toml`: one program only, called on `agent-turn-complete` only (no approval, no start), and it
  is often already taken by another tool. Using it would mean overwriting that or chaining a wrapper around it. So
  the app never writes `config.toml` itself (Codex does, when asked to approve). Settings › Codex states it.
- **Session files** (`~/.codex/sessions/…/rollout-*.jsonl.zst`): in 0.154 they are zstd-compressed, with SQLite state
  beside them; an internal format that changes between versions. Hooks give everything the notch needs, so no file is
  watched or read.
- **app-server** (JSON-RPC over stdio / WebSocket / Unix socket): approvals are *server requests* answered by the client
  that owns the thread (`item/commandExecution/requestApproval`, `item/fileChange/requestApproval`), and
  `thread/status/changed` carries `waitingOnApproval`, but only for the connected client. A second program cannot
  observe or answer another client's threads, except through the experimental shared daemon (`codex app-server daemon`,
  `codex agents`, `codex queue --thread … --message …`), which a normal CLI or app session is not on. Not used for
  sessions. (It is used for the hooks' approval state only, in a short-lived process of its own: see above.)
- **A free message to a running session** would need a `Stop` hook held open (Codex waits for it, so the terminal is
  stuck) or the daemon above. Neither is safe. The card offers to bring the session to the front instead.

## Installing and removing

Settings › Codex › **Install Codex hooks** copies `codex-notch-hook.sh` to `~/.codex/hooks/` and adds one entry per
event to `~/.codex/hooks.json`, after a timestamped backup (`hooks.json.claude-notch-YYYYMMDD-HHMMSS.bak`). It keeps
the user's own hooks and key order, writes nothing when nothing changes, refuses an invalid file, and never touches
`config.toml` or its `notify`. **Remove the hooks** (or Uninstall Claude Notch) takes only its entries away. Then
**Approve in Codex** (or **Review hooks** in the ChatGPT app, or `/hooks` in a terminal), and start a new conversation.

Not covered: a hook turned off by hand in Codex (`enabled = false` in `hooks.state`) still counts as active, and no
free-text answer or Codex question is possible (see above).

---

# Codex dans la notch

Notes de faisabilité derrière l'onglet **Codex**, vérifiées sur un vrai Mac (Codex CLI 0.154.0 et Codex de l'app
ChatGPT 0.162), pas supposées.

## Conclusion

Codex a des **hooks** (même principe que ceux de Claude Code) : c'est la voie officielle pour suivre une session et
répondre à une approbation. Claude Notch n'utilise qu'eux.

- **Marche** : sessions en cours, travaille / terminé, dernier message ; autoriser ou refuser une commande ou un patch
  (hook `PermissionRequest` synchrone) ; ramener l'app hôte devant (app ChatGPT : ouvrir la conversation par
  `codex://threads/<id>`, lien tiré du routage de l'app, non cliqué en vrai).
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

## L'app ChatGPT (Codex 0.162)

L'app Codex fait maintenant partie de **ChatGPT** (`/Applications/ChatGPT.app`, bundle `com.openai.codex`, schéma
`codex://`). Elle embarque son propre CLI (`Contents/Resources/codex-cli/CodexCLI.app`, codex-cli 0.162) et lance
`codex app-server` (stdio) en processus enfant, sur le `~/.codex` par défaut. Mesuré avec ce binaire :

- **Mêmes hooks, même fichier.** Le serveur de l'app lit `~/.codex/hooks.json`. `$PPID` du hook est ce processus
  `codex app-server`, dont le chemin est dans `ChatGPT.app` : la carte dit **ChatGPT** et « Ouvrir » connaît le bundle.
  `PermissionRequest` y est appelé aussi (politique `on-request`) : approuver depuis la notch marche dans l'app.
- **Silence tant que non approuvé.** Avec un hook neuf non approuvé, le serveur n'a lancé aucun hook (0 appel) et l'app
  ne le dit pas dans la conversation. Elle a son propre écran : un bouton **Review hooks** (point jaune) dans la zone de
  saisie et Réglages › Hooks. Les deux envoient `hooks/list` puis `config/batchWrite`.
- **La méthode officielle.** Pas de requête « trust » dédiée. `hooks/list` donne par hook `key`, `command`, `sourcePath`,
  `trustStatus` (`trusted`, `untrusted`, `modified`, `managed`) et `currentHash` ; approuver, c'est `config/batchWrite`
  avec `hooks.state."<key>".trusted_hash = <currentHash>` (`upsert`) : le dialogue de l'app fait exactement cela. `key`
  vaut `<chemin réel de hooks.json>:<événement en snake_case>:<groupe>:<rang>` (chemin canonique, `/var` devient
  `/private/var` ; groupe et rang sont les positions dans hooks.json).
- **Pas de redémarrage.** Un second processus peut approuver (le serveur en marche voit `trusted` au `hooks/list`
  suivant), et l'app n'a pas à être relancée. Mais les hooks sont fixés au début d'une conversation : une conversation
  ouverte continue sans eux (un deuxième tour n'a lancé aucun hook), une **nouvelle** les lance. D'où « ouvre une nouvelle
  conversation ».
- **Un hook modifié se redemande.** `trustStatus` passe à `modified` dès que l'entrée change (autre timeout, autre
  chemin) : mettre les hooks à jour demande donc une nouvelle approbation.
- **Lien profond.** Le routage d'URL de l'app a une route `threads` (`codex://threads/<id du fil>`, l'id étant le
  `session_id` du hook) qui ouvre la conversation. Non cliqué en vrai, pour ne pas bouger la fenêtre de l'utilisateur.
- **Vitesse.** `hooks/list` répond en 0,1 à 0,5 s sur un `CODEX_HOME` déjà utilisé, 8 à 15 s sur un neuf.

## Ce que fait Claude Notch

- **État, en lecture seule.** `hooks.json` et `config.toml` (jamais écrit) donnent une estimation : non posés, posés, et
  pour chaque hook, présence d'un `trusted_hash` à sa clé. Puis `codex app-server` est lancé un instant (le binaire de
  l'app d'abord, sinon la commande `codex` ; environnement minimal, `CODEX_HOME` posé) et `hooks/list` dit la vérité
  (`modified` compris), tout seul seulement tant que l'approbation attend (au plus toutes les 30 s) ; une fois les hooks actifs,
  aucun processus Codex n'est lancé pour les hooks sans que tu appuies sur **Vérifier** (la jauge de quota, plus bas, lance le
  sien, bref, tant que le panneau est ouvert). L'onglet dit : *hooks non posés* → *à approuver dans Codex* → *actifs*. Un événement de hook reçu
  prouve aussi qu'ils tournent. Tant que l'approbation attend et qu'une vue est affichée, deux `stat` toutes les 2,5 s
  repèrent une approbation faite ailleurs (`/hooks`, l'app) : l'onglet se met à jour tout seul ; rien ne tourne hors attente.
- **Approuver, sur un clic seulement.** **Approuver dans Codex** (onglet ou réglages) lance `codex app-server`, liste les
  hooks, envoie `config/batchWrite` pour ceux dont la commande est notre script *et* dont le fichier est ce `hooks.json`,
  rien d'autre, puis relit. Codex écrit `config.toml` lui-même ; l'app jamais.
- **Jauge de quota** (Réglages › Codex › Afficher le quota, activé par défaut). `account/rateLimits/read` renvoie
  `rateLimits.primary` et `secondary` (`usedPercent`, `windowDurationMins`, `resetsAt` en secondes), `planType` et `credits` ;
  le schéma vient de `codex app-server generate-json-schema`. Mesuré avec le Codex de l'app 0.162 et la commande `codex` 0.154
  sur un compte ChatGPT : `primary` 300 min (5 h), `secondary` 10 080 min (7 jours), les mêmes chiffres des deux, réponse
  en 1,2 s, une notification en plus (`remoteControl/status/changed`) et aucun jeton dans la réponse. Codex la lit avec sa propre
  connexion ; l'app lance `codex app-server` (même binaire, environnement minimal) et n'envoie que cette requête. Seulement
  panneau ouvert : tout de suite si le dernier chiffre a plus d'une minute, puis toutes les 5 minutes, un seul minuteur, arrêté
  à la fermeture. Une erreur (clé d'API, pas de connexion, pas de Codex) garde le dernier chiffre et attend 15 minutes. La
  notification `account/rateLimits/updated` n'arrive qu'à un client qui possède un fil : elle n'est pas utilisée.

## Pas utilisé

- **`notify`** : un seul programme, seulement `agent-turn-complete`, souvent déjà pris par un autre outil. `config.toml`
  n'est donc jamais écrit par l'app (c'est Codex qui l'écrit, quand on lui demande d'approuver).
- **Fichiers de session** (`rollout-*.jsonl.zst`) : compressés en zstd en 0.154, format interne changeant : les hooks
  suffisent, aucun fichier n'est lu ni surveillé.
- **app-server** : les approbations sont des requêtes serveur adressées au client qui possède le fil ; un second
  programme ne peut ni les voir ni y répondre. Pas utilisé pour les sessions, seulement pour l'état d'approbation des
  hooks, dans un processus court à part (voir plus haut).

## Pose et retrait

Réglages › Codex › **Installer les hooks Codex** : copie du script dans `~/.codex/hooks/`, une entrée par événement dans
`~/.codex/hooks.json`, après une sauvegarde horodatée ; tes hooks et l'ordre des clés restent ; rien n'est écrit si rien
ne change ; un fichier invalide est refusé ; ton `notify` n'est jamais touché ; `config.toml` n'est jamais écrit par l'installateur. **Retirer les hooks**
(ou désinstaller Claude Notch) n'enlève que nos entrées. Ensuite, **Approuver dans Codex** (ou **Review hooks** dans l'app
ChatGPT, ou `/hooks` dans un terminal), puis ouvre une nouvelle conversation.

Non couvert : un hook désactivé à la main dans Codex (`enabled = false` dans `hooks.state`) compte encore comme actif.
