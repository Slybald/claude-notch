# Vidéo de présentation de Claude Notch

Vidéo en motion design codée avec [Remotion](https://www.remotion.dev) (composition React, rendu déterministe).

- **Version 2 (courante)** : refaite dans le style d'une vidéo de référence fournie par l'utilisateur. Un seul objet
  noir, un curseur, des transformations continues, 60 i/s, muette. Analyse mesurée de la référence :
  [REFERENCE.md](REFERENCE.md). Plan par plan : [STORYBOARD.md](STORYBOARD.md). Code : `src/promo2/`.
- **Version 1** : 40 s, mots géants sur fond crème, coupes sur 120 BPM. Conservée dans le code (`src/promo/`) ;
  [STORYBOARD-v1.md](STORYBOARD-v1.md), concepts : [concepts/](concepts/). Rendu avec `--v=1`.

L'interface de la notch est recréée en composants vectoriels (`src/ui/`) d'après les rendus de l'app et le code de
ses vues : même géométrie en points, mêmes couleurs. Aucune capture, aucune image, aucun logo tiers. Les pictogrammes
sont dessinés pour la vidéo. Le texte des interfaces vient des fichiers de traduction de l'app (anglais et français).
La référence elle-même (vidéo et images) n'est pas dans le dépôt.

## Rendre

```sh
cd promo
npm install
npm run studio                                      # aperçu interactif (compositions Promo2-16x9, Promo2-9x16)
node scripts/render.mjs                             # v2 : out/v2/claude-notch-16x9.mp4 et -9x16.mp4 (+ versions 4K)
node scripts/render.mjs --lang=fr                   # mêmes fichiers avec le suffixe -fr
node scripts/render.mjs --preview --target=16x9     # demi-résolution dans tmp/, pour relire vite
node scripts/render.mjs --v=1                       # version 1 dans out/ (30 i/s, musique facultative)
node scripts/gif.mjs                                # ../docs/media/claude-notch.gif (boucle complète de la v2, 16:9)
node scripts/frames.mjs Promo2-16x9 en 100,200      # images isolées dans tmp/frames/ (numéros d'images à 60 i/s)
```

Chaque composition est dessinée en 1080p ; le rendu se fait à l'échelle 2, donc en vraie 4K vectorielle
(3840 × 2160 et 2160 × 3840). Le 1080p est ensuite dérivé du master par ffmpeg (Lanczos). H.264, `-crf 15` pour le
master, `-crf 17` pour le 1080p, `-movflags +faststart`.

| Fichier (`out/v2/`) | Contenu |
|---|---|
| `claude-notch-16x9.mp4` | 1920 × 1080, 15,8 s, 60 i/s |
| `claude-notch-16x9-4k.mp4` | 3840 × 2160 (master) |
| `claude-notch-9x16.mp4` | 1080 × 1920 : mise en page verticale refaite, pas un zoom |
| `claude-notch-9x16-4k.mp4` | 2160 × 3840 (master) |
| `*-fr.mp4` | mêmes fichiers, textes en français |
| `../docs/media/claude-notch.gif` | boucle de 16,5 s pour le README, 20 i/s, 960 × 540 (versionnée) |

`out/` et `tmp/` ne sont pas versionnés. La vidéo MP4 s'arrête sur la carte finale (image 948) ; le GIF va jusqu'à
l'image 989, où la notch redevient fermée, pour que la boucle soit sans saut.

Le panneau est accroché au bord haut du cadre, comme la vraie notch : dans le 9:16, la zone haute peut être recouverte
par l'interface des réseaux sociaux (Reels, TikTok, Shorts).

## Musique (version 1 seulement)

La v2 est muette, comme la référence. Ce qui suit ne concerne que la v1.

**Aucune musique n'est livrée ni téléchargée.** La vidéo est calée sur **120 BPM** (un temps = 15 images, premier
temps sur l'image 0) : toutes les coupes tombent sur les images 0, 15, 30, 45…

Pour ajouter la piste : déposer le fichier dans `public/music.mp3` (ou `.wav`, `.m4a`, `.ogg`) et, si son tempo n'est
pas 120, un fichier `public/music.json` :

```json
{ "bpm": 118, "startFromSeconds": 0 }
```

Le script de rendu étire alors la piste (`120 / bpm`) pour garder les coupes sur les temps, et décale le départ si
besoin. Ces fichiers sont ignorés par git. La vidéo dure 40 s : prévoir un fondu de fin de 1 s avec ffmpeg
(`-af afade=t=out:st=39:d=1`) si le morceau est coupé.

Trois morceaux proposés (instrumentaux, funk et house légers, à coupes sèches). Pages ouvertes et licences lues le
2026-10-21 ; je n'ai écouté aucun des trois ni téléchargé aucun fichier audio.

1. **« Funky 4x4 Instrumental C 120bpm »**, PrdbyD, 2:28.
   [pixabay.com/music/beats-funky-4x4-instrumental-c-120bpm-374796](https://pixabay.com/music/beats-funky-4x4-instrumental-c-120bpm-374796/).
   Licence : Pixabay Content License (« Free for use »), pas d'attribution exigée. 120 BPM indiqué dans le titre :
   c'est le seul des trois dont le tempo est annoncé, donc le plus sûr pour le calage. La page renvoie aussi vers CC BY-SA 4.0
   sans dire que cela vaut pour ce morceau ; en cas de doute, créditer PrdbyD dans la description de la vidéo.
2. **« Funky House »**, Aurec, 2:43.
   [pixabay.com/music/house-funky-house-582286](https://pixabay.com/music/house-funky-house-582286/).
   Licence : Pixabay Content License. Tempo non indiqué : le mesurer, puis renseigner `bpm` dans `public/music.json`.
3. **« Minimal Tech Lounge - Atmospheric Beat »**, sonicaura, 2:29.
   [pixabay.com/music/soft-house-minimal-tech-lounge-atmospheric-beat-561837](https://pixabay.com/music/soft-house-minimal-tech-lounge-atmospheric-beat-561837/).
   Licence : Pixabay Content License. Tempo non indiqué : à mesurer. Plus doux que les deux autres.

La licence Pixabay interdit de redistribuer le fichier audio seul : ne pas le déposer dans le dépôt (c'est pour cela
que `public/music.*` est ignoré).

## Polices

Installées depuis npm (@fontsource), embarquées dans le rendu, licences SIL Open Font License 1.1 :

| Police | Usage | Paquet |
|---|---|---|
| Bricolage Grotesque (variable, axe de largeur) | titres de la v1 seulement | `@fontsource-variable/bricolage-grotesque` |
| Inter | interface recréée (remplace la police système de macOS, non redistribuable) et carte du nom de la v2 | `@fontsource/inter` |
| JetBrains Mono | code, lien et mentions de la v2, légendes de la v1 | `@fontsource/jetbrains-mono` |

## Structure

- `src/promo2/` : la v2. `Promo2.tsx` (timeline unique en secondes, tout est calculé depuis le numéro d'image),
  `layout2.ts` (16:9 et 9:16). `src/motion2.ts` : ressorts et courbes ajustés sur la référence.
- `src/promo/` : la v1 (`Promo.tsx`, `copy.ts`, `layout.ts`, `parts.tsx`). `copy.ts` fournit aussi les textes de la
  carte finale de la v2.
- `src/ui/` : l'interface de la notch (forme, onglets, cartes des sessions, oreilles), partagée.
- `src/Proof.tsx`, `scripts/proofs.mjs` : rendus de contrôle de l'interface recréée, à comparer aux rendus de l'app.
- `src/concepts.tsx`, `scripts/concepts.mjs` : images-clés des trois concepts de la v1.

Pour décaler un temps fort de la v2 : éditer `T` en haut de `src/promo2/Promo2.tsx` (secondes). Si `T.ret` change,
mettre à jour `CTA_END_FRAME` dans `scripts/lib.mjs` (`T.ret × 60`).
