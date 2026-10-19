# Claude Notch

App macOS native qui vit dans la notch du MacBook Pro et suit les sessions Claude Code :
CLI dans un terminal ou un éditeur, et onglet Code de Claude Desktop. Survol de la notch →
le panneau se déplie et résume chaque session (état, outil en cours, tâches, sous-agents).

## Installation

```sh
./scripts/install.sh
claude doctor
```

`install.sh` compile en release, copie l'app dans `/Applications` (ou `~/Applications`),
installe `~/.claude/hooks/claude-notch-hook.sh`, ajoute les hooks dans `~/.claude/settings.json`
(sauvegarde horodatée à côté, tes hooks existants sont conservés) et charge le LaunchAgent
`~/Library/LaunchAgents/local.claudenotch.plist`.

`CLAUDE_CONFIG_DIR` est respecté. Pour tout retirer : `./scripts/uninstall.sh`.

Développement : `swift build`, `swift test`, `./scripts/build.sh` (assemble `build/ClaudeNotch.app`).
Captures PNG du panneau (dont la section outils) : `CLAUDE_NOTCH_SNAPSHOT_DIR=/chemin swift test --filter SnapshotTests`.
Ajoute `CLAUDE_NOTCH_TOOLS_DIR=/dossier` (contenant `files.jsonl`, `state.json`, `today.json`) pour rendre
la section avec d'autres données, ou `CLAUDE_NOTCH_TOOLS_DIR=standard` pour tes vrais fichiers (lecture seule).

## Fonctionnement

- Chaque événement de hook (`async: true`, aucune latence pour Claude) est relayé par `curl`
  vers `http://127.0.0.1:47823/hook`, avec le PPID du hook et quelques variables d'environnement.
- L'app remonte la chaîne de processus depuis ce PPID pour trouver le processus Claude
  (détection de fin de session) et l'app hôte (Terminal, iTerm2, Ghostty, VS Code, Desktop…).
  Un clic sur une carte ramène cette app au premier plan. Pour une session de l'onglet Code de
  Claude Desktop, le clic ouvre directement cette session (`claude://code/continue?session=local_…`,
  identifiant transmis par le hook via `CLAUDE_CODE_HOST_SESSION_ID`).
- Si l'app est fermée, le hook la relance au prochain `SessionStart` ou `UserPromptSubmit`.
- Interruption par Esc : aucun hook ne part. L'app lit la fin du transcript toutes les 2 s
  pendant un tour et repasse la session en « Prête » si elle y trouve l'interruption.
- Diagnostic : `GET http://127.0.0.1:47823/state` renvoie l'état des sessions et de la notch
  en JSON (lecture seule, local uniquement). La clé `tools` résume la section outils : fichiers récents,
  dépôts à traiter, usage du jour, lignes écrites dans les registres depuis le lancement, écritures ratées.

## Tâches des outils compagnons

Claude Notch lance lui-même les tâches de fond des outils installés à côté (`~/.local/share/<outil>/`),
à la place de LaunchAgents : macOS refuse `~/Documents`, `~/Desktop` et `~/Downloads` aux scripts démarrés
par launchd (« Operation not permitted »), alors que l'accès accordé une fois à l'app est hérité par les
processus qu'elle lance. Au premier passage, macOS demande l'accès pour « Claude Notch » : accepte.

- `git-radar scan --quiet` : 20 s après le lancement, puis toutes les 15 min.
- `claude-usage refresh --quiet` : 40 s après le lancement, puis toutes les 30 min.
- `course-sorter run` : 12 s après chaque arrivée dans Téléchargements, et toutes les 5 min.
- `claude-recap morning` : une fois par jour, au premier passage après 8 h 30.

Un outil absent est ignoré. Journaux : `~/Library/Logs/ClaudeNotch/<outil>.log`. État : clé `jobs` de `/state`.
Les `install.sh` de ces outils ne déposent pas de LaunchAgent quand Claude Notch est installé.

## Registres partagés

L'app écrit deux journaux, une ligne JSON par événement, dans `~/Library/Application Support/ClaudeNotch/`.
Aucun nouveau hook : `PostToolUse` et `PermissionRequest` étaient déjà relayés.

- `files.jsonl` : chaque fichier écrit par Claude (`PostToolUse` réussi de Write, Edit, MultiEdit,
  NotebookEdit ; jamais `PostToolUseFailure`).
  `{"ts": "2026-10-19T10:34:56Z", "path": "/abs/fichier", "tool": "Edit", "session_id": "…", "project": "mon-app", "cwd": "/…/mon-app", "source": "live"}`.
  L'outil `claude-files` y ajoute les écritures passées (`"source": "backfill"`).
- `permissions.jsonl` : chaque demande de permission.
  `{"ts", "session_id", "project", "tool", "detail"}` ; `detail` = 1re ligne de la commande pour Bash,
  chemin du fichier pour une édition, sinon la description courte de l'outil, tronqué à 200 caractères.

Écriture en ajout (`O_APPEND`) sur une queue série, hors du main thread ; le dossier est créé au besoin.

## Section outils

Entre la liste des sessions et la ligne Claude Desktop, une carte compacte :

- **Fichiers récents** (replié par défaut, l'en-tête montre le dernier) : les 5 derniers chemins distincts
  de `files.jsonl`, classés par date, hors dossiers temporaires et espaces jetables (`/tmp`, `/var/folders`,
  `scratch-workspaces`, `scratchpad`). Nom en gras, projet et « il y a 3 min » en gris, grisé et marqué
  « supprimé » si le fichier n'existe plus. Clic : le Finder sélectionne le fichier (ou son dossier parent
  s'il a disparu) et le panneau se referme.
- **Git** (si `~/Library/Application Support/GitRadar/state.json` date de moins de 2 h) : pastille verte
  « Git · tout est poussé » ou ambre « Git · 2 dépôts à traiter ». Le chevron liste les dépôts concernés
  (branche, ↑ à pousser, ↓ à récupérer, ● modifiés et non suivis, « sans upstream ») ; clic = Finder.
- **Usage** (si `~/Library/Application Support/ClaudeUsage/today.json` est daté d'aujourd'hui) :
  « Aujourd'hui · 2 h 10 · 6 sessions », top projets en infobulle.

Un seul volet ouvert à la fois. Rien n'apparaît si les fichiers sont absents. Les fichiers ne sont lus qu'à
l'ouverture du panneau, puis toutes les 15 s tant qu'il reste ouvert, sur une queue utilitaire ; replié,
aucune lecture ni timer. `files.jsonl` est lu de façon incrémentale : la première fois ses 16 derniers Mo
au plus, ensuite seulement les lignes ajoutées (un gros rattrapage ancien ne chasse pas les fichiers récents).
Quand la section grandit, la liste des sessions rétrécit (120 pt minimum, fondu en bas) pour que
le panneau reste sous 460 pt.

## Limites

- Les conversations « chat » de Claude Desktop ne passent pas par les hooks : seul l'état
  « Claude Desktop ouvert / au premier plan » est affiché pour elles.
- Une session déjà ouverte avant l'installation n'apparaît qu'à son prochain message.
- Après une permission accordée, la carte reste en « Attend ta permission » jusqu'à la fin
  de l'outil : aucun hook ne signale l'accord lui-même.
- Esc pendant la réflexion, avant le moindre texte : Claude n'écrit rien dans le transcript,
  la carte reste en « Réfléchit » jusqu'au prochain événement.
- Une session `claude` lancée depuis un terminal ouvert dans Claude Desktop est classée Desktop
  (Claude.app figure parmi ses ancêtres).
- Registres : seulement pendant que l'app tourne (le hook ne relance l'app qu'au début d'une session
  ou d'un tour) ; `claude-files` comble les trous. Pas de rotation : les fichiers grossissent
  (environ 250 octets par ligne) ; au-delà de 16 Mo, l'app n'en lit que la fin.
- `ts` en direct = heure de réception du hook, à la seconde. Une ligne en direct et la ligne de rattrapage
  du même fichier n'ont pas forcément le même `ts` : la déduplication par (path, session_id, ts) peut les
  garder toutes les deux. Sans effet sur « Fichiers récents » (dédupliqué par chemin).
- `permissions.jsonl` contient aussi AskUserQuestion et ExitPlanMode : Claude Code les fait passer par
  `PermissionRequest`.
- Les fichiers écrits dans un espace jetable (`scratch-workspaces` de Claude Desktop, `/tmp`) n'apparaissent
  jamais dans « Fichiers récents ».
- Liste de tâches : les outils TaskCreate/TaskUpdate ne sont actifs par défaut que sur
  certains modèles (constaté : absents avec Sonnet). Sinon, `CLAUDE_CODE_ENABLE_TODO_TOOLS=1`.
  Claude Code supprime les fichiers de tâches quand toute la liste est terminée : la barre disparaît.

## Préférences (menu « … »)

Toujours visible · Lancer à l'ouverture de session · Effacer les sessions terminées · Quitter.
