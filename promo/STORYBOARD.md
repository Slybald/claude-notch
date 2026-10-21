# Claude Notch — storyboard minuté

Vidéo de présentation, 40 s, 30 images/s, **120 BPM** : un temps = 0,5 s = 15 images, une mesure = 2 s = 60 images.
Toutes les coupes et les arrivées de texte tombent sur un temps. Même timeline pour le 16:9 (1920 × 1080, rendu
en 4K) et le 9:16 (1080 × 1920) : seule la mise en page change (voir « Cadrage vertical »).

## Idée forte

Chaque MacBook a une zone noire au milieu du haut de l'écran qui ne sert à rien. Le problème qui disparaît :
**ce trou devient la barre d'outils de tout le monde** (musique, réglages, fichiers, copies, minuteur, notes) et,
pour qui code avec Claude Code, le poste de pilotage de ses sessions. La vidéo commence par la blague que tout
propriétaire de MacBook connaît, puis le trou ouvre la bouche.

## Les trois concepts (images-clés dans `concepts/`)

| | Histoire en une phrase | Direction visuelle | Rythme | Références (idées, pas copies) |
|---|---|---|---|---|
| **A — « Le trou »** (retenu) | « Ton Mac a un trou dans l'écran. Il ne sert à rien. Plus maintenant. » La notch s'ouvre et devient utile. | Affiche typographique crème et noir, orange `#D97757` de l'app. Titres Bricolage Grotesque 800 condensé, légendes en JetBrains Mono. La notch, forme noire pendue au bord haut, est le seul objet. | 120 BPM, coupes sèches, un mot par temps. | Affiches suisses à très gros caractères ; pages produit « type d'abord » de minimal.gallery et godly.website ; le catalogue d'effets de kinetics.colorion.co m'a surtout servi de **liste de ce qu'il faut éviter** (machine à écrire, scramble, apparition en fondu). |
| **B — « Le détour »** | « Sept détours pour faire une petite chose. Un seul geste vers le haut. » | Papier pointillé, un trait orange qui serpente d'une corvée à l'autre, puis un trait noir droit jusqu'à la notch. Mono + condensé. | 100 BPM, tracé qui se dessine. | Cartes de parcours et infographies de trajets (tracé en `stroke-dashoffset`). |
| **C — « 9:00 → 18:00 »** | « Une journée de travail, une seule constante : la notch. » | Fond graphite, horloge géante en mono, frise horaire, l'onglet change avec l'heure. | 112 BPM, un onglet par heure. | Frises horaires d'éditeurs audio, chronos de film. |

**Choix : A.** Le gag du trou est compris en une seconde par tous les propriétaires de MacBook, il présente l'objet
(la notch) avant même le produit, et la typographie lourde contre une petite forme noire donne un look d'affiche,
pas de générateur. B est plus malin sur le papier mais montre le produit en dernier et oblige à inventer des
parcours dans des fenêtres tierces (fausse interface). C est propre mais banal (« une journée avec… ») et son UI
noire sur fond sombre manque de contraste.
On garde de B le **geste unique vers le haut** : le curseur monte d'un trait vers la notch (plan 3).

## Système visuel

- Fond crème `#EFEAE0` (« bureau clair »), encre `#0B0B0B`, orange app `#D97757`. Une seule scène sur fond sombre
  `#181818` (développeurs), amenée par la notch qui grossit jusqu'à remplir le cadre.
- Interface recréée en composants vectoriels d'après les rendus et le code de l'app (mesures en pt, ressort
  `notchSpring` de l'app : response 0,42, damping 0,78).
- Hiérarchie : un seul élément principal bouge à la fois ; le panneau est l'acteur, le mot géant est le décor qui
  change sur les temps.

## Plans

Les temps sont comptés depuis le début (temps 0 = image 0).

| # | Temps | Secondes | Images | Texte (EN / FR) | Ce qui bouge |
|---|---|---|---|---|---|
| 1 | 0–4 | 0,0–2,0 | 0–60 | « Your Mac / has a hole / in the screen. » — « Ton Mac / a un trou / dans l'écran. » | Notch noire seule en haut. Une ligne entre au temps 0, 1 et 2 (révélation par masque, 10 images, sortie expo). Au temps 2 la notch « bat » (ressort) : c'est elle, le trou. |
| 2 | 4–6 | 2,0–3,0 | 60–90 | « It does / nothing. » — « Il ne / sert à rien. » | Coupe sèche : les 3 lignes tombent (6 images), 2 lignes les remplacent. Rien d'autre ne bouge : le vide fait la blague. |
| 3 | 6–7 | 3,0–3,5 | 90–105 | « Until now. » (orange) — « Plus maintenant. » | Le curseur monte d'un trait depuis le bas du cadre jusqu'à la notch (1 geste, 12 images). La phrase orange remplace la précédente sur le temps. |
| 4 | 7–12 | 3,5–6,0 | 105–180 | « Listen. » — « Écoute. » + « Now playing. Your week. » | La notch s'ouvre (ressort app) sur **Lecteur** : pochette, progression, calendrier. Le mot géant entre au temps 8. Curseur au repos sur la barre d'onglets. |
| 5 | 12–18 | 6,0–9,0 | 180–270 | « Switch. » — « Bascule. » + « Wi-Fi, Bluetooth, caffeine. » | Le curseur survole l'onglet **Réglages rapides**, le panneau change de hauteur (ressort), clic sur Caféine : la tuile passe à l'orange. |
| 6 | 18–26 | 9,0–13,0 | 270–390 | « Drop. » — « Dépose. » + « Files wait on the notch. » | Onglet **Étagère**. Un fichier traîne jusqu'au panneau (cadre pointillé orange « déposer »), se pose, les icônes s'écartent, le compteur passe de 5 à 6 éléments. |
| 7 | 26–31 | 13,0–15,5 | 390–465 | « Reuse. » — « Reprends. » + « Your last copies, one click. » | Onglet **Presse-papiers**. Les lignes entrent en cascade (un temps sur deux), survol, clic : « Copié ». |
| 8 | 31–36 | 15,5–18,0 | 465–540 | « Focus. » — « Concentre-toi. » + « Timer and Pomodoro. » | Onglet **Minuteur** : l'anneau avance, le compte à rebours défile. |
| 9 | 36–40 | 18,0–20,0 | 540–600 | « Jot. » — « Note. » + « Quick notes. » | Onglet **Notes rapides** : la note se remplit par rafales de mots, sur les temps. |
| 10 | 40–42 | 20,0–21,0 | 600–630 | — | **La notch grossit jusqu'à remplir le cadre** (le trou avale l'écran, 14 images), pendant qu'elle se replie en oreilles : main ambre à gauche, `2·2` à droite. Fond sombre. |
| 11 | 42–48 | 21,0–24,0 | 630–720 | « Code with Claude Code? » (légende) puis « It asks. » — « Il demande. » | Les oreilles pulsent. Le curseur monte, le panneau s'ouvre sur **Claude** : trois sessions, la première bordée d'ambre. |
| 12 | 48–52 | 24,0–26,0 | 720–780 | « You answer. » — « Tu réponds. » | Survol de la carte, la demande se déplie (`rm -rf build && …`), clic sur **Allow** : la carte passe en « Terminal ». |
| 13 | 52–56 | 26,0–28,0 | 780–840 | « From the notch. » — « Depuis la notch. » + « Optional. Off until you turn it on. » | Survol de « mon-app » : bouton **Chat**, la conversation s'ouvre, le message se tape par rafales et part. |
| 14 | 56–60 | 28,0–30,0 | 840–900 | — | La notch se rétracte vers le haut, le fond redevient crème. Retour sur la barre d'onglets. |
| 15 | 60–66 | 30,0–33,0 | 900–990 | « Yours. » — « À toi. » + « Press, hold, drag. » | Appui long sur la barre : les icônes oscillent, les `−` apparaissent, une icône est glissée à sa nouvelle place, une autre masquée. |
| 16 | 66–80 | 33,0–40,0 | 990–1200 | « Claude Notch. » + « Your notch finally has a job. » + 3 pastilles (« Everything stays on your Mac », « Signed automatic updates », « Setup in four steps ») + lien | Le panneau se replie en notch à oreilles (coche verte, `1·0`). Titre géant au temps 67, légende 69, une pastille par temps (70, 71, 72), lien au temps 74. Au temps 76 les oreilles alternent (comme dans l'app, toutes les 4 s). Dernier plan fixe 2 s. Mention en petit : projet indépendant, non affilié à Anthropic. |

## Accroche et appel à l'action

- Accroche : le gag du trou (plans 1–3), produit réel visible à 3,5 s, mais la notch est à l'écran dès l'image 0.
- Appel à l'action : nom, « Free and open source · macOS 13+ » et `github.com/Slybald/claude-notch`.

## Tempo et musique

- **120 BPM**, 4/4, premier temps sur l'image 0. Les coupes tombent sur les images 0, 15, 30, 45, 60…
- La piste audio est prévue dans la composition : déposer le fichier choisi dans `public/music.mp3` ; le script
  de rendu le détecte (voir `README.md`). Morceaux proposés : voir `README.md`.
- Pas d'effets sonores ajoutés : la vidéo est livrée muette.

## Cadrage vertical (9:16)

Pas un zoom : même timeline, mise en page refaite. La notch et son panneau (échelle 1,6) restent accrochés au haut
du cadre, centrés ; le mot géant passe dessous, sur la moitié basse, sur 1 à 2 lignes ; la légende en mono se
place entre le panneau et le mot. Les scènes à fond sombre et les pastilles finales sont recomposées en colonne.
