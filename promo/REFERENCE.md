# Référence de style de la vidéo v2

Analyse de l'enregistrement d'écran fourni par l'utilisateur (« Enregistrement de l'écran 2026-10-21 à 13.43.37.mov »).
Tout ce qui suit est **mesuré** sur les images (ffmpeg, ffprobe, Python avec NumPy/SciPy), sauf mention « estimé ».
Ni la vidéo ni ses images ne sont dans le dépôt : elles restent hors du projet. On reprend un **style**, jamais le
**contenu** (voir « Ce qu'on ne reprend pas »).

## 1. Ce que c'est

Un enregistrement d'écran d'une page web qui lit une vidéo de **14 s en boucle**, en carré (1054 × 1048). Le fichier
dure 27,8 s :

| Intervalle | Contenu |
|---|---|
| 0 – 7,2 s | La vidéo est en pause : la pastille de départ est immobile, la barre de lecture du navigateur est visible. **Artefact d'enregistrement.** |
| 7,2 – 21,2 s | Une boucle complète. |
| 21,2 – 27,8 s | La boucle recommence ; à 26,5 s le Centre de contrôle de macOS entre par le bord droit (**artefact**). |

Les images sont enregistrées à 60 i/s réels (45 en moyenne : l'enregistreur saute les images identiques). Il n'y a
**aucune piste audio**. Détection de plans (`select='gt(scene,x)'`) : **zéro coupe à 0,25 et à 0,1** ; à 0,05 deux
événements, qui sont des morphings. C'est **un seul plan continu, sans coupe** : chaque objet se transforme en le
suivant.

## 2. Le principe

> Un seul objet noir ou blanc, au centre d'un champ gris clair vide. Un curseur le manipule ; l'objet réagit, puis se
> **transforme** en l'interface suivante. Aucun titre, aucune légende, aucun décor.

La boucle (temps `L` compté depuis le clic, `L = 0` à 7,955 s dans l'enregistrement) :

| # | L (s) | Durée | Objet et geste | Transformation vers le suivant |
|---|---|---|---|---|
| 1 | −0,62 → 0 | 0,6 | Pastille noire « Generate » ; le curseur arrive du bas à droite, s'arrête 0,1 s sur la pastille, clique. | Elle se contracte en cercle (0,30 s) avec un anneau de chargement. |
| 2 | 0 → 1,2 | 1,2 | Cercle, anneau (0,25 s), coche qui « pop » (×1,075, 0,17 s). | Le cercle s'étire en pastille large (0,2 s) : pochette + barres d'égaliseur. |
| 3 | 1,2 → 3,1 | 1,9 | Carte « lecteur » ; le curseur appuie sur pause, puis fait glisser la barre de progression. | La carte se fond en curseur de volume (0,3 s). |
| 4 | 3,1 → 4,6 | 1,5 | Curseur de volume : le pouce est tiré à 0 puis à fond ; au-delà du maximum la pastille s'étire (+8 %) et revient. | Elle se replie en interrupteur (0,27 s). |
| 5 | 4,6 → 5,65 | 1,05 | Interrupteur : trois bascules. | Il s'ouvre en contrôle segmenté blanc. |
| 6 | 5,65 → 6,6 | 0,95 | Segments Jour / Semaine / Mois : la capsule noire glisse deux fois (0,27 s chacune), étirée en route. | Il devient carte blanche. |
| 7 | 6,6 → 9,05 | 2,45 | Carte graphique : le gros chiffre défile, la courbe se trace, le curseur survole la courbe (infobulle noire), puis change de période. | La carte se réduit en pastille de recherche. |
| 8 | 9,05 → 11,5 | 2,45 | Palette de commandes : liste, saisie de « frame » (8 car./s), filtrage, sélection, entrée. | La ligne choisie devient une pastille noire avec coche (0,1 s). |
| 9 | 11,5 → 14,0 | 2,5 | Pastille noire avec coche (tenue 0,6 s), le texte est remplacé par « Generate » (flou) et tient 2 s. | **Retour à l'état initial : la boucle est fermée.** |

Rythme : 9 temps forts en 14 s, soit **1,55 s en moyenne**, de 0,95 à 2,5 s. Chaque temps suit le schéma
**geste → réaction → tenue** : la transformation dure 0,25 à 0,45 s, puis l'objet **reste immobile 0,3 à 0,6 s**
avant le geste suivant. Rien ne bouge en même temps que l'objet principal, sauf le curseur.

## 3. Composition et échelle

- Cadre carré 1054 × 1048, un seul objet **centré** (centre mesuré : 531, 523 sur toute la boucle). Les morphings se
  font **autour du centre** : l'objet grandit et rétrécit vers tous les côtés.
- L'objet est **grand** : de 34 % à 75 % de la largeur. Les textes sont **petits par rapport à l'objet** (libellé 4,4 %
  de la hauteur du cadre), donc lisibles parce que l'objet est agrandi, pas parce que le texte est gros.
- Marge vide autour : jamais moins de 12 % de chaque côté. Le vide fait partie du style.

| Objet | Largeur × hauteur (px) | % de la largeur du cadre |
|---|---|---|
| Pastille « Generate » | 464 × 148 | 44 % |
| Cercle (chargement, coche) | 160 × 160 | 15 % |
| Pastille large (pochette + égaliseur) | 640 × 164 | 61 % |
| Carte lecteur | 716 × 456 (rayon ≈ 14 % de la hauteur) | 68 % |
| Curseur de volume | 780 × 136 | 74 % |
| Interrupteur | 356 × 196 | 34 % |
| Contrôle segmenté | ≈ 860 × 120 | 82 % |
| Carte graphique | 792 × 608 | 75 % |
| Palette de commandes | ≈ 750 × 470 | 71 % |
| Pastille de conclusion | ≈ 700 × 130 | 66 % |

## 4. Couleurs (relevées sur les images, pleine résolution)

| Rôle | Valeur |
|---|---|
| Fond | `#EDEDE8` (237, 237, 232), gris chaud ; bords `#ECECE7` |
| Halo derrière l'objet | `#F0F0EC`, très léger, plus clair au centre (+3 niveaux) |
| Objet noir | `#000000` pur |
| Carte blanche | `#FDFDFD` (pas de blanc pur) |
| Texte sur noir | blanc ; secondaire gris moyen (≈ `#8A8A8A`) ; durées en gris foncé (≈ `#6F6F6F`) |
| Piste de la barre sur noir | gris très sombre (≈ `#2A2A2A`), remplissage blanc |
| Ligne sélectionnée de la palette | `#1B1B1B` (pas du noir pur) |
| Accent | **aucun**, sauf la pochette (dégradé orange → rose → violet, 100 px) |

Une seule teinte de fond du début à la fin : pas de scène sombre, pas de changement d'ambiance.

## 5. Typographie

- Famille probable (confiance moyenne, glyphes vus à 1:1) : **grotesque néo-humaniste proche d'Inter ou de Geist** :
  « G » sans éperon, « a » à deux étages, « t » à coupe oblique. Durées en **monospace** (« 0:48 », « −2:11 »).
- Graisses : libellé de pastille 500, titre de carte 600–700, grand chiffre 700, légende 400 en gris. Interlettrage
  **serré** (≈ −0,02 em, plus fort sur le grand chiffre).
- Corps estimés (cadre de 1048 px de haut ; le libellé de pastille vient de la hauteur de capitale mesurée, 33 px) :
  libellé de pastille ≈ 46 px, titre de carte ≈ 36 px, légende ≈ 30 px, durée ≈ 22 px mono, grand chiffre ≈ 82 px.
- Casse : minuscules et phrases (« motion study 02 », « total views », « Every frame is code »). Pas de capitales
  d'affiche, pas de mots géants, pas de texte en dehors des objets.
- Animation du texte : le contenu d'un objet arrive en **flou → net en 120 ms** (mesuré : netteté de 10 % à 99 % entre
  9,42 et 9,53 s), 100 ms après que la forme a fini de bouger. Chiffres qui défilent avec un flou de mouvement. Saisie
  lettre par lettre à **8 caractères par seconde**, curseur de saisie clignotant. Jamais de machine à écrire sans
  curseur, jamais de fondu centré.

## 6. Matière

- **2D plat**, aucune perspective, aucune caméra, aucun parallaxe. La profondeur vient seulement de l'ombre.
- Ombre portée **vers le bas**, large et douce, sans décalage latéral (mesure sous la pastille, en niveaux de gris
  sur 237 : −48 à 8 px, −33 à 16 px, −16 à 32 px, −4 à 56 px, 0 à 64 px ; à gauche de la pastille : −15 à 8 px). Équivalent CSS retenu pour la v2 (trois ombres, mesuré sur son rendu : −65, −44, −22, −13, −4 à 8, 16, 32,
  40, 48 px) : `0 22px 30px rgba(0,0,0,.22), 0 5px 8px rgba(0,0,0,.2), 0 34px 44px rgba(0,0,0,.07)`. Un peu plus dense que la
  référence près du bord (écart ≤ 17 niveaux à 8 px).
- Pastilles et curseurs : **rayon maximal** (pastille). Cartes : rayon ≈ 14 % de la hauteur.
- Cartes blanches sur le fond gris, cartes noires sur le fond gris : le contraste noir / blanc / gris est la seule
  palette.

### Traitement des interfaces

Interfaces **simplifiées**, une seule idée par objet : une carte = un geste. Pas de barre de menus, pas de fenêtre,
pas de bureau, pas de capture : tout est dessiné. Texte d'interface réduit au minimum utile. États intermédiaires
visibles (chargement, survol, pression) : c'est la réaction qui raconte, pas le texte.

## 7. Mouvement

### 7.1 Les ressorts (ajustement sur les mesures de largeur et de hauteur)

Un **seul ressort de raideur ≈ 460** (pulsation propre ≈ 21,5 rad/s, « response » ≈ 0,29 s) pour tous les morphings,
avec deux amortissements :

| Mouvement | Mesure | Amortissement estimé |
|---|---|---|
| Agrandir (pastille → carte lecteur) | pic de hauteur à 0,19 s après le départ, **dépassement +5 % sur la hauteur finale** (480 pour 456, soit 8 % de la course), calme en 0,45 s | ζ ≈ 0,63 (amortissement ≈ 27) |
| Réduire (pastille → cercle) | 61 % de la course à 0,09 s, 93 % à 0,20 s, 99 % à 0,27 s, aucun dépassement | ζ = 1 (amortissement ≈ 43) |
| Pastille → pastille large | largeur 176 → 640 en 0,2 s, dépassement de 4,5 % de la course | ζ ≈ 0,7 |
| Contrôle segmenté → carte graphique | hauteur 120 → 624 → 608, dépassement de 3 % de la course | ζ ≈ 0,74 |

En pratique : amortissement entre 0,63 et 0,74 pour agrandir (0,68 retenu), 1 pour réduire.

### 7.2 Le curseur (moteur de la vidéo)

- Flèche de macOS : noire, liseré blanc, hauteur 4,2 % du cadre (44 px). Il **arrive du bas à droite** et **pose sa
  pointe dans le tiers inférieur de l'objet**, pas au centre.
- Approche mesurée : 424 px en 0,53 s ; 50 % de la course à 0,2 s, 94 % à 0,37 s ; vitesse de pointe **≈ 1,7 fois la
  vitesse moyenne**, atteinte à 46 % de la course, longue fin douce. Estimation : `cubic-bezier(0.5, 0.1, 0.2, 1)`.
  Vitesse moyenne ≈ 800 px/s.
- Arrêt de 0,1 à 0,15 s sur la cible avant la réaction. Le clic lui-même n'est pas dessiné (pas d'onde) : seule la
  réaction de l'objet le montre. Tassement du curseur au clic : non mesurable, estimé à ≈ 10 % pendant 80 ms.
- Dans les mouvements rapides, le curseur et les valeurs qui changent laissent des **traînées** (3 à 4 copies
  décalées, flou de mouvement par accumulation).

### 7.3 Détails de mouvement à reprendre

- **Sélecteur élastique** : la capsule noire du contrôle segmenté se déplace en 0,27 s, le **bord avant part en
  premier**, le bord arrière suit (largeur 260 → 346 → 280, soit +33 % en route).
- **Bande élastique** : tiré au-delà du maximum, le curseur de volume s'allonge de 8 % (780 → 846) puis revient en
  ressort.
- **Chiffres** qui montent de 40 616 à 84 320 en 0,55 s, sortie douce, chaque chiffre flou pendant le défilement.
- **Courbe** qui se trace de gauche à droite en 0,4 s ; **infobulle** noire qui suit le curseur sur la courbe.
- **Contenu qui change** : l'ancien contenu sort en ≈ 80 à 100 ms (flou + fondu, estimé), la forme se transforme pendant ce temps,
  le nouveau contenu entre en flou → net (120 ms) quand la forme est presque posée.
- **Pression** (estimé) : le bouton se tasse (≈ ×0,96) à la première image de la réaction.
- **Mise en cascade** (estimé) : les lignes de la palette entrent l'une après l'autre sur ≈ 0,25 s.

### 7.4 Interdit par le style (rien de tout cela dans la référence)

Courbes linéaires, mouvements simultanés, caméra qui flotte, texte qui apparaît en fondu au centre, coupes, effets de
transition de modèle, titre géant, musique.

## 8. Profondeur, transitions

- Profondeur : 2D. Ombre seulement.
- Transitions : **aucune transition rapportée**. La transition est le morphing de l'objet lui-même (forme et contenu).
- Une seule « coupe » dans toute la vidéo : la boucle, qui retombe sur l'état initial sans saut.

## 9. Ce qu'on ne reprend pas (contenu)

Le style oui, le contenu non. Ne pas reproduire : la pastille « Generate » qui devient une coche, le lecteur
« motion study 02 » et sa pochette dégradée, le curseur de volume, l'interrupteur, le contrôle Jour / Semaine /
Mois, la carte « 84 320 total views », la palette de commandes « frame » / « Every frame is code ». Ni leurs textes,
ni leur ordre. Le contenu de la v2 est celui de Claude Notch : les vrais onglets de l'app, recréés d'après ses rendus.
Et jamais d'artefact d'enregistrement : barre de lecture du navigateur, Centre de contrôle, bordure sombre de 5 px,
0 – 7 s de pause.

## 10. Vidéo actuelle (v1) → ce qu'il faut changer

| Axe | v1 (storyboard `STORYBOARD.md` v1) | Référence mesurée | Pour la v2 |
|---|---|---|---|
| Durée | 40 s | 14 s en boucle | ≈ 17 s, boucle fermée (GIF) |
| Cadence | 30 i/s | 60 i/s | **60 i/s** |
| Coupes | 16 plans, ≈ 35 coupes sèches sur les temps d'un 120 BPM | **0 coupe**, un plan continu | Aucune coupe : l'objet se transforme |
| Acteur | Le **texte** : mots géants de 230 à 400 px, la notch à droite comme décor | L'**objet** seul, centré, 34–75 % de la largeur | La notch est l'unique acteur ; aucun mot géant |
| Texte | Bricolage Grotesque 800 condensé, légendes mono, révélation par masque, ≈ 12 mots géants | Une grotesque, 500–700, serrée, **petite** ; texte seulement dans l'objet | Un seul texte hors de l'interface : la pastille finale. Pas de légende |
| Couleurs | Crème `#EFEAE0`, encre, orange `#D97757`, **scène sombre** `#181818` | Un gris chaud `#EDEDE8`, noir pur, blanc `#FDFDFD`, **aucun accent** | Fond `#EDEDE8`, halo `#F0F0EC` ; l'orange reste celui de l'app, dans l'interface seulement ; plus de scène sombre |
| Rythme | Un mot par temps, tenue figée | geste → réaction → tenue (0,3–0,6 s) ; 1,55 s par temps | Mêmes proportions |
| Mouvement | Ressort de l'app (response 0,42, ζ 0,78), masques de texte, sorties en exponentielle | Ressort sec (ωn 21,5), ζ 0,63 pour agrandir, 1 pour réduire ; élasticité, bande élastique, flou de mouvement | Ressorts mesurés ci-dessus ; sélecteur élastique sur la barre d'onglets |
| Curseur | Discret, suit des images-clés | Moteur de chaque changement : arrive du bas à droite, 0,5 s, clique dans le tiers bas | Chaque réaction a son geste ; traînée à vitesse haute |
| Transitions | Rideau (la notch grossit jusqu'à remplir le cadre), volets de texte | Aucune ; le morphing en tient lieu | Morphing forme + flou de contenu ; fin : la notch devient la pastille du nom |
| Cadrage | 16:9 : texte à gauche, panneau à droite ; 9:16 recomposé en colonne | Objet centré, grand | Même composition aux trois formats, seule l'échelle change |
| Matière | Ombre courte de la notch | Ombre vers le bas, large (`0 24px 48px` pour une pastille de 148 px) | Même ombre, proportionnelle à l'échelle |
| Fin | Titre géant + 3 pastilles + lien, plan fixe 2 s | La fin est un objet de plus, puis retour au début | Pastille noire du nom + tagline, pastille blanche du lien, retour à la notch fermée |
| Son | Muet, calage à 120 BPM pour une musique éventuelle | Aucune piste | Muet ; pas de calage sur un tempo |

## 11. Vérification de la v2 contre la référence

Planches côte à côte (mêmes moments clés, référence à gauche, v2 à droite) : deux planches de six paires, hors dépôt.
Mesures refaites sur le rendu avec les mêmes outils que sur la référence.

| Point | Référence | v2 mesurée |
|---|---|---|
| Cadence, coupes | 60 i/s, 0 coupe | 60 i/s, 0 coupe ; saut isolé : pics de 0,8 et 1,1 sur 255 seulement (un autre, de 6, venait d'un flou de sortie trop sec : corrigé) |
| Ouverture : dépassement de hauteur | +5,3 % de la hauteur finale | +4,7 % |
| Ouverture : pic, calme | 0,19 s, 0,45 s | 0,20 s, 0,42 s |
| Rythme moyen d'un temps fort | 1,55 s (0,95 à 2,5 s) | 1,4 s (0,8 à 2,15 s) |
| Ombre sous la pastille (niveaux de gris) | −48, −33, −16, −11, −7 à 8, 16, 32, 40, 48 px | −65, −44, −22, −13, −4 |
| Boucle | retour à l'état initial | écart de 0,1 sur 255 entre la première et la dernière image du GIF |
| GIF | — | 330 images, 20 i/s, 960 × 540, 2,5 Mo |

Ce qui colle : fond, noir, blanc et halo ; un seul objet à la fois ; morphing continu sans coupe ; ressorts (agrandir
avec dépassement, réduire sans) ; flou → net du contenu ; capsule élastique ; curseur qui arrive, s'arrête puis
déclenche la réaction ; carte finale qui porte le message ; retour à l'état initial.

Ce qui diffère encore :

- **Composition** : la référence centre l'objet, la notch pend du bord haut (voulu, c'est le produit). Au repos la
  notch ne fait que 23 % de la largeur, contre 44 % pour la pastille de la référence ; le bas du cadre reste vide, et
  plus encore en 9:16 (panneau à 998 px de large sur 1 080, haut du cadre seulement).
- **Densité** : l'interface réelle porte plus de texte et de contrôles que les cartes de la référence ; le texte y est
  donc plus petit par rapport à l'objet.
- **Pochette** : la référence a un élément coloré qui suit la forme pendant le morphing ; la v2 n'a que la barre
  d'onglets, qui arrive avant le contenu.
- **Accent** : la référence n'a aucune couleur vive, la v2 garde l'orange et l'ambre de la vraie interface.
- **Ombre** : un peu plus dense près du bord (voir tableau).
- **Durée** : 15,8 s pour 14 s ; la carte finale tient 2,3 s, la référence boucle après 2 s de repos.
- **Traînées** : trois copies du curseur à vitesse haute ; la référence en laisse aussi sur les chiffres et le pouce du
  curseur, pas ici.
- **Format** : la référence est carrée, la v2 est en 16:9 et 9:16 (pas de 1:1).
