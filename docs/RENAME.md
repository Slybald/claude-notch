# Renommage : Claude Notch → Oriel

Plan et décisions du passage au nom **Oriel** (version 1.9.0). Règle : aucune installation existante ne doit perdre
sa mise à jour automatique, ses autorisations macOS, ses réglages ni ses données.

## Ce qui change

- **Nom affiché** : Oriel partout où l'utilisateur le lit (menus, réglages, assistant, alertes, demandes
  d'autorisation de l'Info.plist, textes FR/EN).
- **Bundle** `Oriel.app` (était `ClaudeNotch.app`), image disque `Oriel-<v>.dmg`, volume « Oriel ».
- **Dépôt** `github.com/Slybald/oriel` (renommé par l'orchestration, voir l'ordre plus bas).
- **Textes lus dans Claude** : « Message from Oriel » (message envoyé depuis la notch) et « The user denied this
  from Oriel. ». Les entrées de `~/.claude/settings.json` sont réécrites en silence au lancement, avec sauvegarde
  horodatée, comme à chaque mise à jour ; les sessions déjà ouvertes gardent l'ancien texte, toujours reconnu.

## Ce qui ne change pas

| Gardé | Pourquoi |
|---|---|
| Identifiant `io.github.slybald.claudenotch` | L'Updater des versions 1.1.0 à 1.8.0 refuse une app d'un autre identifiant (`validateBundle`). Un nouvel identifiant ferait aussi redemander toutes les autorisations (Calendriers, Contacts, Automatisation, Bluetooth, Accès complet au disque, Coller) et repartir les réglages de zéro. |
| Certificat « Claude Notch Self-Signed » et clé Ed25519 | L'exigence désignée (`identifier … and certificate leaf = H"…"`) garde les autorisations ; la clé publique est dans les apps installées. Le nom du certificat n'est montré nulle part. |
| Exécutable `Contents/MacOS/ClaudeNotch`, module Swift, fichiers sources, clés UserDefaults, `ClaudeNotchUpdateChannel` | Internes ; les renommer ne servirait qu'à créer des conflits avec les branches en cours. |
| `~/Library/Application Support/ClaudeNotch`, `~/Library/Logs/ClaudeNotch` | Les scripts de hook installés y lisent le jeton. Déplacer le dossier obligerait à réécrire le script Codex, et Codex redemande alors son approbation. Rien à migrer : aucune perte possible. |
| Hooks `claude-notch-hook.sh`, `codex-notch-hook.sh` et leurs entrées Codex (dont `statusMessage` « Claude Notch ») | Les noms se lisent « hook Claude / Codex de la notch ». Codex invalide l'approbation dès qu'une entrée change (docs/CODEX.md) : on n'y touche qu'avec le prochain changement obligatoire des hooks Codex. |
| Règle `/etc/sudoers.d/claude-notch-lowpower` (chemin et contenu) | La modifier redemanderait le mot de passe administrateur. |
| Label du LaunchAgent, port 47823, en-tête `X-Claude-Notch-Proof`, variables `CLAUDE_NOTCH_*` | Internes ; le chemin écrit dans le LaunchAgent, lui, suit le bundle (voir plus bas). |

## Mise à jour d'une app installée (1.1.0 à 1.8.0)

1. L'app interroge `api.github.com/repos/Slybald/claude-notch/releases/latest`. Après le renommage du dépôt, GitHub
   répond 301 vers `/repositories/<id>/releases/latest` et URLSession suit la redirection
   (`UpdaterTests.testLatestReleaseFollowsRepositoryRename`, sur un vrai serveur local).
2. Elle cherche `ClaudeNotch-<v>.dmg` et sa signature `.sig`. Chaque release publie donc **deux** images signées :
   `Oriel-<v>.dmg` (avec `Oriel.app`) et `ClaudeNotch-<v>.dmg` (la même app, dans un dossier `ClaudeNotch.app`).
3. Elle vérifie la signature, l'identifiant et la version, remplace `/Applications/ClaudeNotch.app` et la relance.
4. Au premier lancement, la nouvelle version se voit nommée `ClaudeNotch.app` dans Applications : elle se renomme
   `Oriel.app` sur place (un simple renommage, rien n'est copié), pointe le LaunchAgent vers le nouveau chemin et se
   relance depuis `Oriel.app` une fois sortie (une seule instance).
5. Ensuite, l'Updater d'Oriel prend `Oriel-<v>.dmg`.

Cas voisins :
- **`Oriel.app` installée à la main à côté d'une ancienne `ClaudeNotch.app`** : Oriel ferme l'ancienne instance, met
  l'ancien bundle (même identifiant, version inférieure ou égale) à la Corbeille et repointe le LaunchAgent.
- **`ClaudeNotch.app` plus récente qu'un `Oriel.app` présent** : la plus récente prend la place de l'autre.
- **Un `Oriel.app` d'un autre éditeur** est déjà là : rien n'est renommé ni jeté ; l'app garde son dossier
  `ClaudeNotch.app` et s'affiche Oriel.

Chaîne simulée de bout en bout dans `UpdaterTests.testLegacyUpdaterInstallsTheRenamedApp` : faux dépôt redirigé,
vraie image disque, Updater 1.8.0 (mêmes fonctions, anciens noms), premier lancement, puis mise à jour suivante.

## Ordre

1. Renommer le dépôt : `gh repo rename oriel --repo Slybald/claude-notch --yes`. GitHub redirige le web, git et l'API.
   Ne jamais recréer de dépôt `claude-notch` sous ce compte : la redirection, et donc la mise à jour des apps
   1.1.0 à 1.8.0, cesserait.
2. Fusionner cette branche. `release.yml` refuse de publier si le dépôt de l'Updater n'est pas celui de la release.
3. Pousser le tag `v1.9.0`.
4. Garder `ClaudeNotch-<v>.dmg` dans chaque release tant que des versions 1.8.0 ou plus anciennes peuvent tourner
   (elles ne lisent que la dernière release). Sans lui, leurs utilisateurs devront télécharger Oriel à la main.

## Risques restants

- Autorisations après le renommage du bundle : macOS les rattache à l'identifiant et à l'exigence désignée, pas au
  chemin. À confirmer sur un vrai Mac avec une 1.8.0 installée, avant l'annonce.
- Le vrai 301 de GitHub n'est vérifiable qu'une fois le dépôt renommé : lancer « Rechercher les mises à jour » sur une
  1.8.0 après le renommage.
- L'ancien nom reste visible à trois endroits : le texte que Codex affiche pendant une demande tenue par la notch,
  les noms des scripts de hook, le dossier de données.
