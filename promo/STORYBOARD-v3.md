# Storyboard minuté, version 3 : toutes les fonctions (remplacée par la v4 : [STORYBOARD.md](STORYBOARD.md))

Vidéo de présentation de **28,25 s** en **60 images/s**, muette. Même style que la v2 (validé par l'utilisateur :
[STORYBOARD-v2.md](STORYBOARD-v2.md), analyse mesurée de la référence dans [REFERENCE.md](REFERENCE.md)), mais elle montre
**toute l'app** au lieu de six onglets. La v1 est dans [STORYBOARD-v1.md](STORYBOARD-v1.md).

## Idée

> **La notch est l'unique acteur et tout se passe en un plan, sans coupe. Une roue de noms, sous elle, lit chaque
> fonction à l'instant où le curseur la déclenche.**

Demande de l'utilisateur : « présenter toutes les fonctionnalités, avec un texte interactif à effet déroulant, y compris
le fait de déplacer les applications avec un maintien ; montrer rapidement le potentiel plein de l'application ».

Ce qui est repris de la v2 : fond `#EDEDE8`, noir pur, blanc `#FDFDFD`, un seul ressort (raideur 460, ζ 0,68 pour
agrandir, 1 pour réduire), curseur qui déclenche chaque réaction, sélecteur élastique, contenu flou → net, plan
continu, boucle fermée pour le GIF.

## Écart voulu avec le style : la roue

Le style interdit tout texte hors de l'interface. Ici le texte est **demandé**, donc il devient un objet de plus et
suit les règles de la maison : une boîte blanche en rayon doux, petite par rapport au panneau, un seul mouvement à la
fois.

- Trois lignes : la fonction du moment est nette, au centre, sur une bande grise ; la précédente et la suivante
  s'éteignent et rétrécissent. À gauche, un **compteur à rouleaux** (01 → 20, mono) tourne avec elle.
- La roue passe à la ligne suivante **sur le geste** du curseur (ressort de raideur 520, ζ 0,8, flou de vitesse).
  Chaque nom reste lisible 0,7 s au moins (`T.wheel` dans `src/promo3/Promo3.tsx`).
- Elle reste en place sous le panneau pendant tout le film. À la fin elle **monte et se resserre en carte du lien**
  (le nom de l'app est sur la carte noire, le lien sur la roue devenue blanche) ; à la boucle elle redescend et le
  compteur repart à 01.
- 20 entrées : les noms des onglets et des réglages de l'app (`src/promo3/copy3.ts`, anglais et français).

## Identité de l'app : un seul fichier

`src/promo3/identity.ts` : nom (**Oriel**), slogan, lien (`github.com/Slybald/oriel`), mentions légales, icône. Le nom y
est lu partout où il apparaît : carte finale, assistant (« Bienvenue dans … »), menu « Quitter … ». Aucun numéro de
version dans le film : il serait faux dès la release suivante. Un changement de nom = modifier ce fichier, puis `node scripts/render.mjs`
(EN et `--lang=fr`) et `node scripts/gif.mjs`. L'icône est le rectangle au tiers haut plein (celui de l'assistant de
l'app) ; l'étoile orange (`"spark"`) est le logo de Claude et ne convient plus. Le lien suppose que le dépôt est
renommé `Slybald/oriel` (étape 1 de la publication, `docs/RENAME.md` de la PR de renommage).

## Plans

Temps en secondes depuis le début. Chaque réaction suit l'arrivée du curseur de 0,10 s (arrêt, puis clic). La colonne
« Roue » est l'entrée qui prend le centre à cet instant. Les onglets généraux passent d'abord ; **Claude et Codex
viennent ensuite et portent la mention « facultatif »** : l'app est pour tout le monde, ces deux intégrations n'existent
que si l'outil est sur le Mac.

| # | Début | Geste du curseur | Réaction et transformation | Roue |
|---|---|---|---|---|
| 1 | 0,00 | Entre du bas à droite, survole l'intercalaire de lecture (0,50) | La notch repliée porte ses **intercalaires** : lecture (équaliseur), Claude (main ambre, `2·2`), minuteur (`24:59`), Mail (`12`). Celui de la lecture **se déploie** en carte : pochette, titre, précédent / pause / suivant. | 01 Intercalaires |
| 2 | 1,20 | Clique la carte | La carte se replie, le panneau s'ouvre (ressort, dépassement) sur le **Lecteur**. | 02 Lecteur |
| 3 | 1,70 | Clique la pause, puis le jour 22 (2,20) | Le morceau passe en pause ; la semaine change de jour, les rendez-vous aussi. | 03 Calendrier (2,20) |
| 4 | 2,90 | Clique **Réglages rapides**, la tuile Caféine (3,50) | La capsule s'étire ; la tuile passe à l'orange (« Éveillé · 1 h »). | 04 Réglages rapides |
| 5 | 4,00 | Clique **Étagère**, prend un fichier (4,45), le dépose (5,00) | Cadre pointillé orange au survol ; le fichier se pose, 5 → 6. | 05 Étagère |
| 6 | 5,45 | Clique **Presse-papiers**, une copie (6,05) | Lignes en cascade de 50 ms ; la ligne passe à « Copié ». | 06 Presse-papiers |
| 7 | 6,50 | Clique **Minuteur** | La bague se trace, le compte à rebours se met en place. | 07 Minuteur |
| 8 | 7,25 | Clique **Notes rapides** | La note se remplit par rafales de mots. | 08 Notes rapides |
| 9 | 8,60 | Clique **Mail**, « Répondre » (9,30) | Trois derniers mails ; le champ de réponse s'ouvre, le texte se tape, « Envoyer » (10,30) : « Envoyé ». | 09 Mail |
| 10 | 11,00 | Clique l'onglet **Claude** (sa main ambre est dans la barre depuis le début), puis « Allow » (12,10) | Trois sessions ; la demande de permission se déplie (11,30), puis se replie : la carte passe en « Terminal ». | 10 Claude (facultatif), 11 Permissions (11,80) |
| 11 | 12,45 | Survole la carte « api », clique « Converser » (12,90) | Le bouton apparaît au survol ; la conversation se déplie, le message se tape, Entrée l'envoie (13,95) : bulle « Toi ». | 12 Conversation (12,90) |
| 12 | 14,50 | Clique l'onglet **Codex**, puis « Allow » (15,25) | Session en attente + demande d'approbation (Dans le terminal / Refuser / Autoriser) ; elle se replie. | 13 Codex (facultatif) |
| 13 | 15,85 | **Appui long** sur l'icône « Notes » (0,5 s) | À 16,35 : les icônes **tremblent**, un « − » apparaît sur chacune, « + » en bout de barre, « OK » remplace « … », le contenu s'assombrit. | 14 Appui long (15,90) |
| 14 | 16,60 | **Glisse** l'icône vers la gauche (0,65 s), la dépose en 3ᵉ place (17,25) | L'icône suit le curseur à 115 %, chaque onglet s'écarte quand elle passe, elle se pose. | 15 Glisse pour réordonner (16,60) |
| 15 | 17,60 | Clique « + » (17,60), « Messages » dans le menu (18,10), « OK » (18,60) | Le menu liste les onglets masqués ; **Messages** apparaît en bout de barre ; le mode édition se ferme. | 16 Ajoute ou masque (17,60) |
| 16 | 19,00 | Clique **Messages**, la 1ʳᵉ conversation (19,65) | Conversations, pastille orange ; le champ de réponse s'ouvre, le texte se tape, Entrée (20,50). | 17 Messages (19,00) |
| 17 | 21,10 | Clique « … », survole « Mises à jour automatiques » (21,50) | Le menu de l'app (réglages, afficher et masquer la notch, **✓ mises à jour automatiques**, quitter). | 18 Mises à jour automatiques (21,10) |
| 18 | 22,20 | — | Le panneau se replie en notch : elle porte **cinq intercalaires** (Mail, lecture, Claude ✓, minuteur, Messages). | |
| 19 | 23,05 | — | La notch **tombe** et devient la fenêtre de l'**assistant** : « Bienvenue dans Oriel », les quatre profils. | 19 Assistant de configuration (23,15) |
| 20 | 24,25 | Clique le profil **Créatif** | Cadre orange, coche ; l'aperçu passe aux onglets du profil (Lecteur, Étagère, Presse-papiers : ni Claude ni Codex). Le curseur sort. | 20 Profils (24,25) |
| 21 | 25,15 | — | La fenêtre **se resserre en carte noire** : icône de la notch, « Oriel », « Ta notch a enfin un travail. ». | |
| 22 | 26,00 | — | La roue monte et devient la carte blanche du lien `github.com/Slybald/oriel` ; mentions en bas. Tenue de 2,25 s. | lien |
| 23 | 28,25 | — | **Boucle du GIF seulement** (jusqu'à 28,95) : la carte remonte, redevient la notch du plan 1 ; le compteur repart à 01. La vidéo MP4 s'arrête à 28,25 sur la carte finale. | 01 |

Rythme : 20 fonctions nommées en 24,25 s, soit **1,2 s en moyenne** (0,7 à 2,4 s) ; la v2 faisait 1,4 s. Le film est
plus dense parce que la roue lit la fonction pendant que le geste a lieu. Les mouvements restent un par un : la
transformation dure 0,25 à 0,45 s, puis l'objet tient.

## Format et composition

- **16:9** : panneau à l'échelle 2 (1 288 px, 67 % de la largeur), accroché au bord haut ; roue de 980 × 190 px sous lui
  (haut à 858 px) ; fenêtre de l'assistant à l'échelle 1,55. Le curseur prend le fichier de l'étagère à droite, hors
  du panneau et de la roue.
- **9:16** (vrai recadrage, pas un zoom) : panneau à 1,55 (998 px), roue de 960 × 276 px (haut à 830 px), fenêtre à
  1,5 ; le curseur prend le fichier sous le panneau (y = 640). La zone haute peut être recouverte par l'interface des
  réseaux sociaux.
- 4K (3 840 × 2 160 et 2 160 × 3 840) : la composition est dessinée en 1080p et rendue à l'échelle 2, donc en vectoriel.

## Vérité de l'interface

Tout est recréé d'après le code et les captures de l'app (`Sources/ClaudeNotch/`), rien d'inventé :

| Montré | D'où ça vient |
|---|---|
| Intercalaires : forme, escalier de hauteur, soulignement coloré, carte de 236 pt au survol | `EarTabs.swift`, `EarTabViews.swift` |
| Appui long 0,5 s, tremblement, « − », « + » (menu des onglets masqués), « OK », glisser avec décalage des voisins | `NotchTabBar` dans `NotchViews.swift`, `TabEditing` |
| Permission, conversation (« Converser », champ, « Claude le lira tout de suite ») | `ReplyViews.swift`, `ConversationViews.swift` |
| Codex : cartes, approbation avec « Dans le terminal / Refuser / Autoriser » | `CodexViews.swift` |
| Lecteur + semaine du calendrier (choix d'un jour) | `MediaViews.swift` |
| Messages : lignes, pastille, champ de réponse | `MessagesViews.swift` |
| Mail : trois derniers mails, « Répondre » au survol, champ, « Envoyer » (PR « derniers mails et réponse », fusionnée dans main) | `MailViews.swift` |
| Menu « … » : réglages, afficher et masquer la notch, mises à jour automatiques, quitter (la ligne « Version » est omise) | `NotchMoreMenu`, `UpdateMenuItems` |
| Assistant : étape 1 avec les quatre profils (Développeur, Étudiant, Créatif, Minimal) et leurs onglets | `SetupAssistant.swift`, `ProfileViews.swift`, `Profiles.swift` |

Les données affichées (morceau, fichiers, copies, conversations, mails) sont fictives, comme dans les captures de l'app.
Ne sont pas montrés : la fenêtre des réglages, le mode plein écran compact, la section outils, le dépôt d'un fichier sur
la notch repliée, les raccourcis clavier, Claude Desktop.

## Son

Aucun, comme la v2 : pas de musique ajoutée ni téléchargée.
