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
  en JSON (lecture seule, local uniquement).

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
- Liste de tâches : les outils TaskCreate/TaskUpdate ne sont actifs par défaut que sur
  certains modèles (constaté : absents avec Sonnet). Sinon, `CLAUDE_CODE_ENABLE_TODO_TOOLS=1`.
  Claude Code supprime les fichiers de tâches quand toute la liste est terminée : la barre disparaît.

## Préférences (menu « … »)

Toujours visible · Lancer à l'ouverture de session · Effacer les sessions terminées · Quitter.
