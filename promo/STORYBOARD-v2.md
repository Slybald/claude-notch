# Claude Notch — storyboard minuté, version 2 (remplacée par la v3 : [STORYBOARD.md](STORYBOARD.md))

Vidéo de présentation de **15,8 s** en **60 images/s**, muette, refaite dans le style de la vidéo de référence de
l'utilisateur ([REFERENCE.md](REFERENCE.md) : analyse mesurée et tableau « v1 → à changer »). La v1 (40 s, mots géants
sur fond crème, coupes sur 120 BPM) reste dans le code (`src/promo/`) et dans [STORYBOARD-v1.md](STORYBOARD-v1.md) ;
ses trois concepts sont dans [concepts/](concepts/).

## Idée

> **Un seul objet noir au centre d'un champ vide. Un curseur le manipule, il se transforme en l'interface suivante.**

Le problème qui disparaît : la zone noire du haut de l'écran ne sert à rien. Ici, **la notch est l'unique acteur** :
elle s'ouvre, change d'onglet, reçoit un fichier, se replie, puis tombe au centre et devient la carte qui porte son
nom. Aucun titre, aucune légende, aucun mot géant. Les textes sont ceux de l'interface recréée.

Ce qu'on reprend de la référence : un plan continu sans coupe ; fond gris chaud, noir pur, blanc ; objet grand (70 %
de la largeur) et vide autour ; ressorts secs mesurés ; curseur qui déclenche chaque réaction ; sélecteur élastique ;
contenu qui passe de flou à net ; rythme « geste → réaction → tenue » ; boucle fermée.
Ce qu'on ne reprend pas : tout son contenu (pastille « Generate », lecteur, curseur de volume, interrupteur,
segments, graphique, palette de commandes).

## Écarts voulus avec la référence

| Référence | v2 | Pourquoi |
|---|---|---|
| Objet flottant au centre du cadre | Notch **accrochée au bord haut**, comme dans l'app ; seule la carte finale est au centre | C'est la vérité du produit : un panneau qui pend de l'écran |
| Carré 1:1 | 16:9 et 9:16 | Formats demandés ; même composition, seule l'échelle change |
| Aucune couleur vive | L'orange de l'app reste **dans** l'interface (onglet actif, tuile allumée, bouton Allow) | C'est la vraie interface |
| Ressort de la référence | Même raideur, pas le ressort de l'app (response 0,42 / ζ 0,78) | Plus sec : c'est ce qui fait le style ; la notch de l'app est plus douce |

## Système visuel

- Fond `#EDEDE8`, halo `#F1F1ED` au centre ; notch `#000` ; carte blanche `#FDFDFD` ; aucun autre fond.
- Interface recréée en composants vectoriels (`src/ui/`) d'après les rendus et le code de l'app. Échelle : **2,25 px
  par point** en 16:9 (panneau de 1 449 px, 75 % de la largeur), **1,55** en 9:16 (panneau de 998 px).
- Ombre portée vers le bas, large et douce, proportionnelle au cadre.
- Polices : Inter pour l'interface (tient la place de la police système de macOS) et pour la carte du nom,
  JetBrains Mono pour le lien et les mentions.

## Mouvement

Un seul ressort de raideur 460 pour tous les morphings (REFERENCE.md § 7.1) : amortissement **0,68** pour agrandir
(dépassement de 5 %), **1** pour réduire. Le curseur suit `cubic-bezier(0.5, 0.1, 0.2, 1)`, 0,3 à 0,6 s selon la
distance, arrêt de 0,1 s avant chaque clic, traînée au-dessus de 650 px/s. Le contenu d'un onglet sort en 100 ms avec
du flou ; le suivant entre en 130 ms de flou à net. La capsule de la barre d'onglets s'étire : bord avant d'abord,
bord arrière 40 ms après.

## Plans

Temps en secondes depuis le début. Chaque réaction suit l'arrivée du curseur de 0,10 s (arrêt, puis clic).

| # | Début – fin | Durée | Geste du curseur | Réaction et transformation |
|---|---|---|---|---|
| 1 | 0,00 – 0,68 | 0,68 | Entre du bas à droite, se pose sur la notch (0,5 s). | Notch fermée seule en haut du cadre. À 0,68 elle s'ouvre sur **Lecteur** : forme 0,2 s avec dépassement, contenu net à 0,95. |
| 2 | 0,68 – 2,25 | 1,57 | Va sur la pause, clique à 1,50. | L'icône pause devient lecture. Tenue. |
| 3 | 2,25 – 3,90 | 1,65 | Clique l'onglet **Réglages rapides** (2,25), puis la tuile Caféine (3,05). | La capsule s'étire d'un onglet à l'autre, le panneau grandit (ressort), flou → net ; la tuile passe à l'orange (« Éveillé · 1 h »). |
| 4 | 3,90 – 6,05 | 2,15 | Clique **Étagère** (3,90), sort du panneau, prend un fichier (4,50), le glisse (4,75), le dépose (5,20). | Les cinq éléments entrent en cascade ; cadre pointillé orange au survol ; l'élément se pose, 5 → 6. |
| 5 | 6,05 – 7,60 | 1,55 | Clique **Presse-papiers** (6,05), survole une copie, clique (6,85). | Le panneau grandit, les lignes entrent une à une (50 ms) ; la ligne passe à « Copié ». |
| 6 | 7,60 – 8,40 | 0,80 | Clique **Minuteur** (7,60). | Le panneau rétrécit (ressort critique) ; la bague se trace, le compte à rebours se met en place. |
| 7 | 8,40 – 10,15 | 1,75 | Clique **Notes rapides** (8,40). | La note se remplit par rafales de mots (8,70 – 9,60). À 9,45 l'icône de l'onglet Claude devient une main ambre : Claude attend. |
| 8 | 10,15 – 11,75 | 1,60 | Traverse la barre d'onglets, clique **Claude** (10,15), puis **Allow** (11,25). | La demande se déplie (10,55) ; au clic elle se replie et la carte passe en « Terminal ». |
| 9 | 11,75 – 12,65 | 0,90 | Sort du cadre par le bas à droite. | Le panneau se replie en notch à oreilles : coche verte à gauche, `1·0` à droite. |
| 10 | 12,65 – 15,80 | 3,15 | — | La notch **tombe** (0,45 s) et devient la carte noire : étoile orange, « Claude Notch », « Your notch finally has a job. » (texte net à 13,17). À 13,50 la carte blanche du lien `github.com/Slybald/claude-notch` en sort ; mentions « Free and open source · macOS 13+ » et « projet indépendant, non affilié à Anthropic » à 13,70. Tenue de 2,3 s. |
| 11 | 15,80 – 16,50 | 0,70 | — | **Boucle du GIF seulement** : la carte remonte, redevient la notch fermée, état identique à l'image 0. La vidéo MP4 s'arrête à 15,80 sur la carte finale. |

Rythme : 9 temps forts en 12,65 s avant la carte finale, soit **1,4 s en moyenne** (référence : 1,55 s). Le plus court
dure 0,8 s (Minuteur), le plus long 2,15 s (Étagère, où le fichier fait un aller-retour).

## Accroche et appel à l'action

- Accroche : la notch est à l'écran dès l'image 0 et **s'ouvre à 0,68 s** ; l'interface réelle est visible avant 1 s.
- Appel à l'action : nom, tagline, `github.com/Slybald/claude-notch`, « gratuit et open source », sur la carte finale
  tenue 2,3 s.

## Cadrage vertical (9:16)

Même timeline, mise en page refaite : panneau à l'échelle 1,55 (998 px sur 1 080), accroché au haut du cadre ; le
curseur attend et prend le fichier dans la zone libre sous le panneau (y = 760) ; la carte du nom (900 × 196 px) et la
carte du lien (820 × 116 px) sont centrées à y = 770 ; les mentions sont en bas. Un recadrage plus serré (panneau plus
large que le cadre, caméra qui suit le curseur) a été essayé et abandonné : il coupe le texte aux bords. La zone
haute peut être recouverte par l'interface des réseaux sociaux (Reels, TikTok, Shorts).

## Retiré par rapport à la v1

Les mots géants, le calage sur 120 BPM, la scène sombre « développeurs » avec le rideau, la conversation avec Claude,
le mode édition des onglets (appui long, glisser, masquer). Raison : le style de référence n'a ni texte autour de
l'objet ni changement d'ambiance, et ses temps forts durent 1 à 2,5 s. Le mode édition tiendrait seul 3 s : il peut
faire une vidéo à part.

## Son

Aucun. La référence n'a pas de piste audio ; la vidéo est livrée muette, sans musique.

## Vérité de l'interface

Rien d'inventé : onglets, textes, mesures et couleurs viennent des rendus de l'app et de ses fichiers de traduction.
Les données affichées (morceau, fichiers, copies) sont fictives, comme dans les captures de l'app. Les gestes montrés
sont des fonctions réelles : pause, tuile Caféine, dépôt d'un fichier sur l'étagère, copie d'un élément, minuteur,
note, réponse à une demande d'autorisation. Le dépôt se fait ici sur le panneau déplié ; le README annonce aussi le
dépôt sur la notch repliée, non montré.
