# Claude Notch — contexte pour Claude Code

App macOS (Swift Package, swift-tools 5.10, macOS 13+, mode Swift 5, pas de projet Xcode) qui vit dans la
notch et suit les sessions Claude Code (CLI et onglet Code de Claude Desktop) grâce à des hooks.
Dépôt public : github.com/Slybald/claude-notch. Le README (anglais + français) décrit le produit ; ce
fichier garde les commandes et les décisions qu'il ne faut pas défaire.

## Commandes

- `swift build` : **zéro warning** exigé (le seul toléré : « x86_64 architecture is deprecated » du build universel).
- `swift test` : tout vert ; 4 tests de diagnostic sont sautés sans leurs variables d'env.
- Rendus PNG hors écran : `CLAUDE_NOTCH_SNAPSHOT_DIR=/dossier swift test --filter SnapshotTests`, puis regarder les images.
- `scripts/build.sh` (app universelle signée ad hoc dans `build/`, `VERSION=x.y.z` pour la version),
  `scripts/make-dmg.sh` (DMG + SHA-256).
- `scripts/install.sh` : installation développeur (compile, copie dans /Applications, hooks, LaunchAgent).
- Publier : pousser un tag `vX.Y.Z` ; `.github/workflows/release.yml` construit le DMG et crée la release.
- Diagnostic de l'app qui tourne : `GET http://127.0.0.1:47823/state` (JSON : sessions, notch, outils, tâches).

## Carte du code (`Sources/ClaudeNotch/`)

- `HookServer` : serveur HTTP minimal sur 127.0.0.1:47823 ; résout le contexte processus AVANT de répondre
  (le hook est encore vivant). `HookEvent` : lecture tolérante du JSON, tout optionnel.
- `ProcessInspector` : chaîne des ancêtres depuis `X-Claude-PPID` → PID de Claude, app hôte (bundle le plus
  externe), source CLI/Desktop. `ClaudeMonitor` : Desktop ouvert ? processus `claude` vivants (scan 2 s) ?
- `SessionStore` : machine à états par session, tâches (`~/.claude/tasks/<session_id>/`), détection d'Esc.
- `NotchController` (fenêtre, survol, visibilité), `NotchViews` / `ToolsViews` (SwiftUI), `ToolsFeed`.
- `HookInstaller` + `OrderedJSON` : pose/retire les hooks dans `~/.claude/settings.json`. `Onboarding` :
  fenêtre de premier lancement et menu. `AppIdentity` : identifiant et migration de `local.claudenotch`.
- `ActivityLog` : registres `files.jsonl` / `permissions.jsonl`. `JobRunner` : tâches des outils compagnons.
- `Localization` : helper `L()`. `LaunchAgent.swift` contient aussi `Preferences`.

## Décisions à ne pas défaire

- **Faits mesurés sur Claude Code 2.1.29x** : `PermissionRequest` n'a pas de `tool_use_id` (rattaché au
  dernier outil actif du même nom) ; les agents internes envoient `SubagentStop` avec `agent_type` vide (ignorés) ;
  le résultat d'un agent d'arrière-plan arrive comme un `UserPromptSubmit` « <task-notification> » ;
  `$PPID` du hook est le processus claude ; le CLI natif s'appelle `2.1.296` (reconnu par son chemin).
- **Esc** : aucun hook. Le transcript est relu chaque seconde pendant un tour ; seule une ligne `type: user`
  dont le texte commence par « [Request interrupted by user » compte (pas une simple citation).
- **CPU ≈ 0 % replié** : aucun timer rapide ni lecture de fichier quand le panneau est replié ; spinner et main
  qui pulse sont des animations Core Animation (`AnimatedGlyphView`), pas des `TimelineView` (≈ 10 % de CPU).
- **Taille de la forme** remontée par `NotchSizeKey` avec un `reduce` en `max` (sinon zéro et zone de survol
  fausse). Le panneau déplié reste sous 460 pt.
- **Barre des menus** : ses icônes passent par-dessus la notch quel que soit le niveau de fenêtre ; la bande à
  hauteur de barre reste vide et l'en-tête est dessous. Les oreilles repliées restent dans la barre.
- **Dossiers protégés** (Documents, Bureau, Téléchargements) : jamais d'accès sur le main thread (une fenêtre
  d'autorisation macOS figerait la notch), et aucun accès si aucun outil compagnon n'est installé.
- **Outils compagnons** lancés par `JobRunner`, pas par launchd : launchd n'a pas accès aux dossiers protégés.
- **Installateur** : résultat identique octet pour octet à `scripts/hooks_config.py` (tests), ordre des clés
  conservé, sauvegarde horodatée, rien n'est écrit si le JSON est invalide ou si rien ne change.
- **Lien vers une session Desktop** : `claude://code/continue?session=<local_…>`, format lu dans le gestionnaire
  `open-url` de Claude Desktop ; identifiant transmis par le hook via `CLAUDE_CODE_HOST_SESSION_ID`.
- **Localisation** : les textes français sont les clés ; traductions dans `Resources/en.lproj` ; toute chaîne
  visible construite en `String` passe par `L()` ; `LocalizationTests` vérifie la couverture.
- Signature ad hoc, pas de notarisation : macOS bloque le premier lancement et peut redemander les accès après
  chaque réinstallation.

## Conventions

- Commentaires et messages de commit en français, commits conventionnels avec le trailer d'attribution.
- Dépôt public : aucune donnée personnelle (chemins, e-mail, noms de projets, identifiants de session réels).
  Les commits utilisent l'adresse noreply GitHub (configurée dans ce dépôt).
- Prouver avant de corriger : reproduire par un test, une commande ou `/state`.
