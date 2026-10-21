# Storyboard minuté, version 4 : la v3, dynamique

Vidéo de présentation de **22,0 s** (boucle du GIF : 22,6 s) en **60 images/s**, muette. Même contenu que la v3
([STORYBOARD-v3.md](STORYBOARD-v3.md)) : toutes les fonctions, la roue de noms (texte déroulant), le déplacement des
onglets par appui long, le nom **Oriel**. Même style validé (fond `#EDEDE8`, noir pur, blanc `#FDFDFD`, ressort de
raideur 460, curseur qui déclenche chaque réaction, contenu flou → net).

## Pourquoi une v4

Demande de l'utilisateur : la v3 lui plaît mais elle n'est « pas assez dynamique » ; il veut le dynamisme de ses vidéos
de référence. Ces références ont été **mesurées** (plans, rythme, énergie, courbes, caméra, texte) avec le même outil
que la v3 ; l'outil et la base de connaissances sont hors du dépôt (`~/.claude/motion-design/`), les vidéos aussi.
Ce qui rendait la v3 plate, chiffré :

| Mesure | v3 | Références (3 vidéos) |
|---|---|---|
| Temps immobile | 32,9 % | 0,2 – 10,5 % |
| Tenue la plus longue | 1,03 s | 0 – 0,58 s |
| Intensité d'un temps fort (flux optique) | 0,20 diag/s | 0,37 – 0,82 diag/s |
| Plan médian (entre deux changements visuels forts) | 2,98 s | 0,92 – 2,18 s |
| Caméra (zooms, travellings) | aucune | 1 à 5 zooms |

Le pouls de la v3 (un accent toutes les 0,9 s, attaque de 0,07 s) était déjà celui des références : il manquait
l'amplitude, la continuité et la caméra.

## Les trois leviers (`src/promo4/Promo4.tsx`)

1. **Rampe de vitesse** (`RUSH`) : la v3 est rejouée 1,12 fois plus vite, et ses tenues mesurées passent à ×2
   (les saisies de texte à ×1,35 – 1,45, la carte finale à ×1,6). L'appui long reste à **0,5 s réelles**, comme dans
   l'app. 28,25 s → 22,0 s ; la première réaction arrive à 0,31 s (accroche).
2. **Caméra qui suit l'action** (`SHOTS`) : elle pousse vers le prochain geste du curseur (×1,4 à ×1,85) et recule
   pour révéler (ouverture du panneau, fichier pris hors du panneau, notch repliée). Ressort ζ 0,9, ω 11 rad/s, mesuré
   sur les caméras des références. Tant que le panneau est ouvert, ses bords bornent le cadrage (jamais de vide à côté
   d'un gros plan) ; la notch reste accrochée au haut du cadre quand la caméra vise haut. La roue et les mentions ne
   bougent pas avec elle (calque au-dessus). En 9:16 le panneau remplit déjà la largeur : poussées réduites à 30 %,
   sauf l'accroche.
3. **Fouetté et flou de vitesse** : au changement d'onglet, l'ancien contenu part du côté opposé et le nouveau arrive
   du côté de l'onglet choisi (avec flou) ; sur les mouvements rapides (pointe des grands mouvements de caméra, au-delà de 20 px par image, fouettés,
   chute de la notch, carte, lien), chaque image est la moyenne de 5 instants sur une demi-image.

## Plans

Temps v4 (s). Le contenu de chaque plan est celui de la v3, au même ordre.

| # | v4 | Geste et réaction | Caméra |
|---|---|---|---|
| 1 | 0,00 | La notch repliée et ses intercalaires ; le curseur entre | gros plan ×2,4 sur la notch |
| 2 | 0,31 | Survol de l'intercalaire de lecture : il se déploie | ×1,6 vers l'intercalaire |
| 3 | 0,88 | Clic : le panneau s'ouvre sur le **Lecteur** | recul à ×1,15 |
| 4 | 1,32 – 1,72 | Pause, puis jour 22 du **Calendrier** | ×1,45, suit le curseur |
| 5 | 2,27 – 2,73 | **Réglages rapides**, tuile Caféine | ×1,2 puis ×1,55 sur la tuile |
| 6 | 3,11 – 4,00 | **Étagère** : le fichier est pris hors du panneau (3,51) et déposé | ×1,2, plan large ×1, puis ×1,4 sur le dépôt |
| 7 | 4,35 – 4,83 | **Presse-papiers**, une copie | ×1,25 puis ×1,5 |
| 8 | 5,13 | **Minuteur** | ×1,4 |
| 9 | 5,75 | **Notes rapides** : saisie | ×1,55 |
| 10 | 6,69 – 7,96 | **Mail** : répondre, saisir, envoyer | ×1,2 puis ×1,55 sur la réponse |
| 11 | 8,50 – 11,02 | **Claude** (facultatif) : permission « Allow » (9,48), conversation (10,20) | ×1,15, ×1,6 sur « Allow », ×1,35 |
| 12 | 11,43 – 12,02 | **Codex** (facultatif) : « Allow » | ×1,2 puis ×1,6 |
| 13 | 12,52 – 13,76 | **Appui long** (0,5 s), mode édition (13,02), l'icône glisse et se pose | gros plan ×1,85 sur la barre, la caméra suit l'icône |
| 14 | 14,01 – 14,91 | « + », Messages ajouté, « OK » | ×1,6 puis ×1,35 |
| 15 | 15,22 – 16,36 | **Messages** : répondre, saisir, envoyer | ×1,3 puis ×1,5 |
| 16 | 16,80 | Menu « … », **mises à jour automatiques** | ×1,5 sur le menu |
| 17 | 17,53 | Le panneau se replie : cinq intercalaires | recul à ×1 |
| 18 | 18,15 – 19,08 | La notch tombe et devient l'**assistant** ; profil Créatif | ×1,25 sur le profil |
| 19 | 19,80 – 22,02 | Carte noire « Oriel », puis le lien sur la roue devenue carte | plan large |
| 20 | 22,02 – 22,64 | Boucle du GIF seulement : retour à la notch repliée | |

## Vérification

`analyze.py` (même outil que pour les références) sur le rendu 1080p : voir la PR pour le tableau avant / après.
Images regardées : planches contact 16:9 et 9:16, images isolées en pleine résolution (flou de vitesse, cadrage).
