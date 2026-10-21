# Vidéo de présentation d'Oriel (ex-Claude Notch)

Vidéo en motion design codée avec [Remotion](https://www.remotion.dev) (composition React, rendu déterministe).

- **Version 3 (courante)** : toutes les fonctions de l'app (intercalaires, Claude, Codex, lecteur et calendrier,
  réglages rapides, étagère, presse-papiers, minuteur, notes, Mail, Messages, déplacement des onglets par appui long,
  mises à jour automatiques, assistant et profils), 28,25 s, même style que la v2, avec une **roue de noms** qui lit
  chaque fonction pendant le geste. Plan par plan : [STORYBOARD.md](STORYBOARD.md). Code : `src/promo3/`.
  **Le nom, le slogan, le lien et l'icône de l'app sont dans un seul fichier : `src/promo3/identity.ts`.**
- **Version 2** : refaite dans le style d'une vidéo de référence fournie par l'utilisateur. Un seul objet noir, un
  curseur, des transformations continues, 60 i/s, muette, 15,8 s. Analyse mesurée de la référence :
  [REFERENCE.md](REFERENCE.md). Plan par plan : [STORYBOARD-v2.md](STORYBOARD-v2.md). Code : `src/promo2/`. Rendu avec `--v=2`.
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
npm run studio                                      # aperçu interactif (compositions Promo3-16x9, Promo3-9x16, Promo2-…)
node scripts/render.mjs                             # v3 : out/v3/notch-promo-16x9.mp4 et -9x16.mp4 (+ versions 4K)
node scripts/render.mjs --lang=fr                   # mêmes fichiers avec le suffixe -fr
node scripts/render.mjs --preview --target=16x9     # demi-résolution dans tmp/, pour relire vite
node scripts/render.mjs --v=2                       # version 2 dans out/v2/ (claude-notch-*), --v=1 : version 1 dans out/
node scripts/gif.mjs                                # ../docs/media/claude-notch.gif (boucle complète de la v3, 16:9, 16 i/s)
node scripts/frames.mjs Promo3-16x9 en 100,200      # images isolées dans tmp/frames/ (numéros d'images à 60 i/s) ; 5ᵉ argument : échelle
```

Chaque composition est dessinée en 1080p ; le rendu se fait à l'échelle 2, donc en vraie 4K vectorielle
(3840 × 2160 et 2160 × 3840). Le 1080p est ensuite dérivé du master par ffmpeg (Lanczos). H.264, `-crf 15` pour le
master, `-crf 17` pour le 1080p, `-movflags +faststart`.

| Fichier (`out/v3/`) | Contenu |
|---|---|
| `notch-promo-16x9.mp4` | 1920 × 1080, 28,25 s, 60 i/s |
| `notch-promo-16x9-4k.mp4` | 3840 × 2160 (master) |
| `notch-promo-9x16.mp4` | 1080 × 1920 : mise en page verticale refaite, pas un zoom |
| `notch-promo-9x16-4k.mp4` | 2160 × 3840 (master) |
| `*-fr.mp4` | mêmes fichiers, textes en français |
| `../docs/media/claude-notch.gif` | boucle de 28,95 s pour le README, 16 i/s, 960 × 540 (versionnée, moins de 5 Mo) |

`out/` et `tmp/` ne sont pas versionnés. La vidéo MP4 s'arrête sur la carte finale (image 1695) ; le GIF va jusqu'à
l'image 1736, où la notch redevient fermée, pour que la boucle soit sans saut. Un rendu 4K complet (EN + FR, 2 formats)
et le GIF prennent une demi-heure environ.

### Changer le nom de l'app

Le nom actuel est **Oriel** (version 1.9.0). Pour le changer : modifier `src/promo3/identity.ts` (nom, version, slogan,
lien, mentions, icône), puis relancer `node scripts/render.mjs`, `node scripts/render.mjs --lang=fr` et
`node scripts/gif.mjs`. Les noms de fichiers (`notch-promo-*`) ne contiennent pas le nom de l'app. L'icône est celle de
la notch (`icon: "notch"`) ; l'étoile orange (`"spark"`) est le logo de Claude. Le lien `github.com/Slybald/oriel`
suppose le dépôt renommé.

Le panneau est accroché au bord haut du cadre, comme la vraie notch : dans le 9:16, la zone haute peut être recouverte
par l'interface des réseaux sociaux (Reels, TikTok, Shorts).

## Musique (version 1 seulement)

Les v2 et v3 sont muettes, comme la référence. Ce qui suit ne concerne que la v1.

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

- `src/promo3/` : la v3. `Promo3.tsx` (timeline unique `T` en secondes, tout est calculé depuis le numéro d'image),
  `Wheel.tsx` (la roue et son compteur), `copy3.ts` (les noms de la roue), `identity.ts` (nom, slogan, icône),
  `layout3.ts` (16:9 et 9:16).
- `src/promo2/` : la v2. `Promo2.tsx`, `layout2.ts`. `src/motion2.ts` : ressorts et courbes ajustés sur la référence,
  communs à la v2 et à la v3.
- `src/promo/` : la v1 (`Promo.tsx`, `copy.ts`, `layout.ts`, `parts.tsx`). `copy.ts` fournit aussi les textes de la
  carte finale de la v2.
- `src/ui/` : l'interface de la notch (forme, onglets, cartes des sessions, oreilles), partagée ; `extra.tsx` et
  `icons3.tsx` pour la v3 (intercalaires, onglets Codex, Messages et Mail, menus, fenêtre de l'assistant).
- `src/Proof.tsx`, `scripts/proofs.mjs` : rendus de contrôle de l'interface recréée, à comparer aux rendus de l'app.
- `src/concepts.tsx`, `scripts/concepts.mjs` : images-clés des trois concepts de la v1.

Pour décaler un temps fort de la v3 : éditer `T` en haut de `src/promo3/Promo3.tsx` (secondes ; `T.wheel` pour la roue).
Si `T.ret` change, mettre à jour `CTA_END_FRAME_V3` dans `scripts/lib.mjs` (`T.ret × 60`). Même règle pour la v2
(`CTA_END_FRAME`, `T.ret` de `src/promo2/Promo2.tsx`).
