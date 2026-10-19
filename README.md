# Claude Notch

A native macOS app that lives in your MacBook's notch and keeps track of your Claude Code sessions,
whether they run in a terminal or an editor (CLI) or in the Code tab of Claude Desktop. Hover the notch
and the panel unfolds with a summary of every session: state, current tool, task list, subagents.

<p align="center">
  <img src="docs/collapsed.png" width="380" alt="Collapsed notch: a raised hand on the left ear, 2·2 on the right ear">
</p>
<p align="center">
  <img src="docs/expanded.png" width="620" alt="Expanded panel with three sessions: one waiting for permission, one running a command with a task list, one done">
</p>

The interface is in French for now. Screenshots use sample data.

*Not affiliated with or endorsed by Anthropic. Claude is a trademark of Anthropic.*

[Version française plus bas](#français)

## Features

- **Session states at a glance**: ready, thinking, running a tool (with the command or the file),
  waiting for your permission, waiting for your answer, plan to review, done, error, compacting the context.
  Sessions that need you are listed first, with an amber outline.
- **Collapsed notch with two "ears"**: the left one shows the overall state (a raised hand when a session
  needs you, a spinner while Claude works, a check mark when a turn ends); the right one shows
  `active sessions·running subagents`, for example `1·6`, or the progress of the task list (`2/5`).
- **Permissions**: the card shows what Claude is asking for (`Terminal · rm -rf build`, the file to edit,
  the question asked).
- **Tasks**: progress bar and current task of Claude Code's task list; the chevron unfolds the whole list.
- **Subagents**: number of subagents running in each session.
- **Click to go back**: clicking a card brings the host app to the front (Terminal, iTerm2, Ghostty, VS Code,
  Claude Desktop…). For a session in the Code tab of Claude Desktop, the click opens that exact session.
- **Claude Desktop**: a row shows whether Claude Desktop is open, with a button to bring it to the front.
- **Optional tools section**: files recently written by Claude, Git status of your repositories, today's usage.
  It only appears when its data files exist (see [Tools section](#tools-section)).
- Works on screens without a notch too (external display, closed lid): a small notch is drawn at the top
  center of the screen.

<p align="center">
  <img src="docs/tools.png" width="620" alt="Expanded panel with the tools section: recent files, two Git repositories to deal with, today's usage">
</p>

## Installation

1. Download `ClaudeNotch-<version>.dmg` from the [Releases](https://github.com/Slybald/claude-notch/releases) page.
2. Open it and drag **ClaudeNotch** onto **Applications**.
3. Optional: check the download against the `.sha256` file published next to it:
   `shasum -a 256 -c ClaudeNotch-<version>.dmg.sha256` (run it in the download folder).

### First launch

Claude Notch is not notarized (there is no Apple Developer ID behind it, the app is signed ad hoc), so macOS
blocks it the first time you open it. Two ways around it:

- Open the app once, dismiss the warning, then go to **System Settings › Privacy & Security**, scroll down
  and click **Open Anyway** next to the message about ClaudeNotch. Confirm.
- Or, in Terminal:

  ```sh
  xattr -dr com.apple.quarantine /Applications/ClaudeNotch.app
  ```

On first launch, a window offers to install the Claude Code hooks. It adds Claude Notch's entries to
`~/.claude/settings.json` (a timestamped backup is written next to it first, and your existing hooks are kept)
and installs the hook script in `~/.claude/hooks/`. You can reinstall them later from the **…** menu ›
**Installer les hooks**. Sessions that were already open show up at their next message.

### Requirements

- macOS 13 Ventura or later, Apple silicon or Intel.
- Claude Code (CLI, or the Code tab of Claude Desktop).
- Claude Code configuration in `~/.claude`. `CLAUDE_CONFIG_DIR` is not supported by the app: the hooks are
  always installed in `~/.claude`.

## Privacy

- Everything stays on your Mac. Claude Notch sends no data anywhere: no analytics, no outgoing network request.
- The app listens on `127.0.0.1:47823` only, on the loopback interface: it cannot be reached from the network.
- The hook script only talks to that local address, with `curl`.
- What the app reads: the hook events, the end of the transcript of a running session (to detect Esc),
  Claude Code's task files, the process list (to find the host app).
- What the app writes: two local logs in `~/Library/Application Support/ClaudeNotch/` (see
  [Shared logs](#shared-logs)), and the hooks in `~/.claude` when you ask for it.

## How it works

- Each hook event is relayed by `curl` to `http://127.0.0.1:47823/hook`, along with the hook's parent process
  ID and a few environment variables. The hooks are declared `async: true`: they add no latency to Claude.
- From that process ID, the app walks up the process tree to find the Claude process (to detect the end of
  the session) and the host app (Terminal, iTerm2, Ghostty, VS Code, Claude Desktop…). A session with Claude
  Desktop among its ancestors is a Desktop session; the click opens it with
  `claude://code/continue?session=local_…` (the ID comes from `CLAUDE_CODE_HOST_SESSION_ID`).
- If the app is not running, the hook relaunches it on the next `SessionStart` or `UserPromptSubmit`.
- Interrupting with Esc fires no hook: during a turn, the app reads the end of the transcript every second and
  switches the session back to "ready" when it finds the interruption.
- Diagnostics: `GET http://127.0.0.1:47823/state` returns the state of the sessions and of the notch as JSON
  (read only, local only).

## Tools section

A compact card between the session list and the Claude Desktop row. Each part only shows up when its file exists:

- **Recent files** (folded by default, the header shows the latest one): the last 5 distinct paths of
  `files.jsonl`, excluding temporary folders (`/tmp`, `/var/folders`, scratch spaces). A deleted file is greyed
  out. Click: Finder selects the file (or its parent folder if it is gone).
- **Git**, from `~/Library/Application Support/GitRadar/state.json` when it is less than 2 hours old:
  "everything pushed" or "N repositories to deal with", with branch, commits to push or pull, local changes.
- **Usage**, from `~/Library/Application Support/ClaudeUsage/today.json` when it is dated today: active time
  and number of sessions.

The files are only read while the panel is open (every 15 s, on a background queue); nothing runs while it is
folded. The Git and usage files are produced by separate command-line tools that are not part of this repository.

### Companion tool jobs

If companion tools are installed in `~/.local/share/<tool>/` (`git-radar`, `claude-usage`, `course-sorter`,
`claude-recap`), Claude Notch runs their background jobs itself instead of LaunchAgents: macOS denies
`~/Documents`, `~/Desktop` and `~/Downloads` to scripts started by launchd, while the access granted once to
an app is inherited by the processes it starts. A missing tool is skipped. Logs:
`~/Library/Logs/ClaudeNotch/<tool>.log`; state: `jobs` key of `/state`. Since the app is signed ad hoc, macOS
may ask for these accesses again after each update.

## Shared logs

The app appends one JSON line per event to two files in `~/Library/Application Support/ClaudeNotch/`, from
hooks it already receives:

- `files.jsonl`: every file written by Claude (successful `PostToolUse` of Write, Edit, MultiEdit,
  NotebookEdit): `{"ts", "path", "tool", "session_id", "project", "cwd", "source"}`.
- `permissions.jsonl`: every permission request: `{"ts", "session_id", "project", "tool", "detail"}`, where
  `detail` is the first line of the command for Bash, the file path for an edit, otherwise the tool's short
  description, truncated to 200 characters.

## Limitations

- Chat conversations in Claude Desktop do not go through hooks: for them, only "Claude Desktop open /
  frontmost" is shown.
- A session opened before the hooks were installed only appears at its next message.
- After a permission is granted, the card stays on "waiting for your permission" until the tool finishes:
  no hook reports the approval itself.
- Esc while Claude is thinking, before any text: Claude writes nothing to the transcript, so the card stays on
  "thinking" until the next event.
- A `claude` session started from a terminal opened inside Claude Desktop is classified as Desktop (Claude.app
  is among its ancestors).
- Logs are only written while the app runs (the hook relaunches the app only at the start of a session or a
  turn). They are never rotated (about 250 bytes per line); beyond 16 MB, the app only reads the end of
  `files.jsonl`.
- `permissions.jsonl` also contains AskUserQuestion and ExitPlanMode: Claude Code routes them through
  `PermissionRequest`.
- Task list: the TaskCreate/TaskUpdate tools are only enabled by default on some models. Otherwise, set
  `CLAUDE_CODE_ENABLE_TODO_TOOLS=1`. Claude Code deletes the task files once the whole list is done: the
  progress bar then disappears.

## Uninstall

**…** menu › **Désinstaller Claude Notch…** removes the hooks and what the app installed, then quits.
Then drag `ClaudeNotch.app` from Applications to the Trash.

## Development

Swift Package (no Xcode project), Swift 5.10 tools, macOS 13+.

```sh
swift build
swift test
scripts/build.sh      # universal (arm64 + x86_64) build/ClaudeNotch.app, signed ad hoc
scripts/make-dmg.sh   # build/ClaudeNotch-<version>.dmg and its .sha256, checked after creation
```

- `VERSION=1.2.3 scripts/build.sh` sets the app version (default: `CFBundleShortVersionString` of
  `Resources/Info.plist`).
- `scripts/install.sh` builds and installs from source; `scripts/uninstall.sh` removes it.
- PNG snapshots of the panel, with sample data: `CLAUDE_NOTCH_SNAPSHOT_DIR=/some/folder swift test --filter SnapshotTests`.
- **Publishing a release**: push a `vX.Y.Z` tag. GitHub Actions runs the tests, builds the universal app in
  version X.Y.Z, makes the DMG and creates the release with the DMG and its SHA-256.

  ```sh
  git tag v1.0.0
  git push origin v1.0.0
  ```

## License

[MIT](LICENSE).

---

## Français

App macOS native qui vit dans la notch du MacBook et suit les sessions Claude Code, dans un terminal ou un
éditeur (CLI) comme dans l'onglet Code de Claude Desktop. Survole la notch : le panneau se déplie et résume
chaque session (état, outil en cours, liste de tâches, sous-agents). Les captures ci-dessus utilisent des
données fictives.

*Projet indépendant, ni affilié à Anthropic ni approuvé par Anthropic. Claude est une marque d'Anthropic.*

### Fonctionnalités

- **États des sessions** : prête, réfléchit, outil en cours (avec la commande ou le fichier), attend ta
  permission, attend ta réponse, plan à valider, terminé, erreur, compacte le contexte. Les sessions qui
  t'attendent passent en tête, avec un contour ambre.
- **Notch repliée avec deux « oreilles »** : à gauche l'état global (main levée quand une session t'attend,
  un spinner pendant que Claude travaille, une coche à la fin d'un tour) ;
  à droite `sessions actives·sous-agents en cours`, par exemple `1·6`, ou l'avancement de la liste de tâches
  (`2/5`).
- **Permissions** : la carte montre ce que Claude demande (`Terminal · rm -rf build`, le fichier à modifier,
  la question posée).
- **Tâches** : barre de progression et tâche en cours de la liste de Claude Code ; le chevron déplie la liste.
- **Sous-agents** : nombre de sous-agents en cours dans chaque session.
- **Clic → retour à la session** : un clic sur une carte ramène l'app hôte au premier plan (Terminal, iTerm2,
  Ghostty, VS Code, Claude Desktop…). Pour une session de l'onglet Code de Claude Desktop, le clic ouvre
  cette session précise.
- **Claude Desktop** : une ligne indique si Claude Desktop est ouvert, avec un bouton pour le ramener devant.
- **Section outils (optionnelle)** : fichiers récemment écrits par Claude, état Git de tes dépôts, usage du
  jour. Elle n'apparaît que si ses fichiers de données existent (voir [Section outils](#section-outils)).
- Marche aussi sur un écran sans notch (écran externe, capot fermé) : une petite notch est dessinée en haut
  au centre de l'écran.

### Installation

1. Télécharge `ClaudeNotch-<version>.dmg` depuis la page [Releases](https://github.com/Slybald/claude-notch/releases).
2. Ouvre-le et glisse **ClaudeNotch** sur **Applications**.
3. Facultatif : vérifie le téléchargement avec le fichier `.sha256` publié à côté :
   `shasum -a 256 -c ClaudeNotch-<version>.dmg.sha256` (dans le dossier du téléchargement).

#### Premier lancement

Claude Notch n'est pas notarisée (pas de compte Apple Developer ID, l'app est signée ad hoc) : macOS la
bloque à la première ouverture. Deux façons de passer outre :

- Ouvre l'app une fois, ferme l'avertissement, puis va dans **Réglages Système › Confidentialité et
  sécurité**, descends et clique sur **Ouvrir quand même** à côté du message sur ClaudeNotch. Confirme.
- Ou, dans le Terminal :

  ```sh
  xattr -dr com.apple.quarantine /Applications/ClaudeNotch.app
  ```

Au premier lancement, une fenêtre propose d'installer les hooks de Claude Code. Elle ajoute les entrées de
Claude Notch dans `~/.claude/settings.json` (une sauvegarde horodatée est faite à côté avant, tes hooks
existants sont conservés) et installe le script de hook dans `~/.claude/hooks/`. Tu peux les réinstaller
plus tard depuis le menu **…** › **Installer les hooks**. Une session déjà ouverte apparaît à son prochain
message.

#### Prérequis

- macOS 13 Ventura ou plus récent, Apple silicon ou Intel.
- Claude Code (CLI, ou onglet Code de Claude Desktop).
- Configuration de Claude Code dans `~/.claude`. `CLAUDE_CONFIG_DIR` n'est pas pris en charge par l'app :
  les hooks sont toujours installés dans `~/.claude`.

### Confidentialité

- Tout reste sur ton Mac. Claude Notch n'envoie aucune donnée : pas de statistiques, aucune requête réseau
  sortante.
- L'app n'écoute que sur `127.0.0.1:47823`, sur l'interface de bouclage : elle est injoignable depuis le réseau.
- Le script de hook ne parle qu'à cette adresse locale, avec `curl`.
- Ce que l'app lit : les événements de hook, la fin du transcript d'une session en cours (pour détecter
  Esc), les fichiers de tâches de Claude Code, la liste des processus (pour trouver l'app hôte).
- Ce que l'app écrit : deux journaux locaux dans `~/Library/Application Support/ClaudeNotch/` (voir
  [Registres partagés](#registres-partagés)), et les hooks dans `~/.claude` quand tu le demandes.

### Fonctionnement

- Chaque événement de hook est relayé par `curl` vers `http://127.0.0.1:47823/hook`, avec le PID du
  processus parent du hook et quelques variables d'environnement. Les hooks sont déclarés `async: true` :
  aucune latence pour Claude.
- À partir de ce PID, l'app remonte la chaîne de processus pour trouver le processus Claude (détection de
  fin de session) et l'app hôte (Terminal, iTerm2, Ghostty, VS Code, Claude Desktop…). Une session qui a
  Claude Desktop parmi ses ancêtres est une session Desktop ; le clic l'ouvre avec
  `claude://code/continue?session=local_…` (identifiant transmis par `CLAUDE_CODE_HOST_SESSION_ID`).
- Si l'app est fermée, le hook la relance au prochain `SessionStart` ou `UserPromptSubmit`.
- Une interruption par Esc ne déclenche aucun hook : pendant un tour, l'app relit la fin du transcript chaque
  seconde et repasse la session en « Prête » si elle y trouve l'interruption.
- Diagnostic : `GET http://127.0.0.1:47823/state` renvoie l'état des sessions et de la notch en JSON
  (lecture seule, local uniquement).

### Section outils

Une carte compacte entre la liste des sessions et la ligne Claude Desktop. Chaque partie n'apparaît que si
son fichier existe :

- **Fichiers récents** (replié par défaut, l'en-tête montre le dernier) : les 5 derniers chemins distincts de
  `files.jsonl`, hors dossiers temporaires (`/tmp`, `/var/folders`, espaces jetables). Un fichier supprimé
  est grisé. Clic : le Finder sélectionne le fichier (ou son dossier parent s'il a disparu).
- **Git**, depuis `~/Library/Application Support/GitRadar/state.json` s'il a moins de 2 h : « tout est
  poussé » ou « N dépôts à traiter », avec branche, commits à pousser ou à récupérer, modifications locales.
- **Usage**, depuis `~/Library/Application Support/ClaudeUsage/today.json` s'il est daté du jour : temps
  actif et nombre de sessions.

Les fichiers ne sont lus que panneau ouvert (toutes les 15 s, sur une queue de fond) ; replié, rien ne
tourne. Les fichiers Git et usage viennent d'outils en ligne de commande séparés, absents de ce dépôt.

#### Tâches des outils compagnons

Si des outils compagnons sont installés dans `~/.local/share/<outil>/` (`git-radar`, `claude-usage`,
`course-sorter`, `claude-recap`), Claude Notch lance lui-même leurs tâches de fond à la place de
LaunchAgents : macOS refuse `~/Documents`, `~/Desktop` et `~/Downloads` aux scripts démarrés par launchd,
alors que l'accès accordé une fois à une app est hérité par les processus qu'elle lance. Un outil absent est
ignoré. Journaux : `~/Library/Logs/ClaudeNotch/<outil>.log` ; état : clé `jobs` de `/state`. L'app étant
signée ad hoc, macOS peut redemander ces accès après chaque mise à jour.

### Registres partagés

L'app ajoute une ligne JSON par événement à deux fichiers de `~/Library/Application Support/ClaudeNotch/`, à
partir de hooks qu'elle reçoit déjà :

- `files.jsonl` : chaque fichier écrit par Claude (`PostToolUse` réussi de Write, Edit, MultiEdit,
  NotebookEdit) : `{"ts", "path", "tool", "session_id", "project", "cwd", "source"}`.
- `permissions.jsonl` : chaque demande de permission : `{"ts", "session_id", "project", "tool", "detail"}`,
  où `detail` est la 1re ligne de la commande pour Bash, le chemin du fichier pour une édition, sinon la
  description courte de l'outil, tronqué à 200 caractères.

### Limites

- Les conversations « chat » de Claude Desktop ne passent pas par les hooks : seul l'état « Claude Desktop
  ouvert / au premier plan » est affiché pour elles.
- Une session ouverte avant l'installation des hooks n'apparaît qu'à son prochain message.
- Après une permission accordée, la carte reste en « Attend ta permission » jusqu'à la fin de l'outil : aucun
  hook ne signale l'accord lui-même.
- Esc pendant la réflexion, avant le moindre texte : Claude n'écrit rien dans le transcript, la carte reste en
  « Réfléchit » jusqu'au prochain événement.
- Une session `claude` lancée depuis un terminal ouvert dans Claude Desktop est classée Desktop (Claude.app
  figure parmi ses ancêtres).
- Registres : écrits seulement pendant que l'app tourne (le hook ne relance l'app qu'au début d'une session
  ou d'un tour). Pas de rotation (environ 250 octets par ligne) ; au-delà de 16 Mo, l'app ne lit que la fin
  de `files.jsonl`.
- `permissions.jsonl` contient aussi AskUserQuestion et ExitPlanMode : Claude Code les fait passer par
  `PermissionRequest`.
- Liste de tâches : les outils TaskCreate/TaskUpdate ne sont actifs par défaut que sur certains modèles.
  Sinon, `CLAUDE_CODE_ENABLE_TODO_TOOLS=1`. Claude Code supprime les fichiers de tâches quand toute la liste
  est terminée : la barre disparaît.

### Désinstallation

Menu **…** › **Désinstaller Claude Notch…** retire les hooks et ce que l'app a installé, puis la quitte.
Jette ensuite `ClaudeNotch.app` du dossier Applications à la Corbeille.

### Développement

Swift Package (pas de projet Xcode), swift-tools 5.10, macOS 13+.

```sh
swift build
swift test
scripts/build.sh      # build/ClaudeNotch.app universelle (arm64 + x86_64), signée ad hoc
scripts/make-dmg.sh   # build/ClaudeNotch-<version>.dmg et son .sha256, vérifié après création
```

- `VERSION=1.2.3 scripts/build.sh` fixe la version de l'app (par défaut : `CFBundleShortVersionString` de
  `Resources/Info.plist`).
- `scripts/install.sh` compile et installe depuis les sources ; `scripts/uninstall.sh` retire tout.
- Captures PNG du panneau, avec des données fictives :
  `CLAUDE_NOTCH_SNAPSHOT_DIR=/un/dossier swift test --filter SnapshotTests`.
- **Publier une version** : pousse un tag `vX.Y.Z`. GitHub Actions lance les tests, compile l'app universelle
  en version X.Y.Z, fabrique le DMG et crée la release avec le DMG et son SHA-256.

  ```sh
  git tag v1.0.0
  git push origin v1.0.0
  ```

### Licence

[MIT](LICENSE).
