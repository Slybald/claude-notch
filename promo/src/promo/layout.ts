export type Format = "wide" | "tall";

export type Layout = {
  w: number;
  h: number;
  /** Échelle du panneau (1 pt de l'app = S px de la vidéo). */
  S: number;
  /** Centre horizontal de la notch. */
  cx: number;
  margin: number;
  maxTextW: number;
  hook: { top: number; size: number };
  verb: { size: number; bottom: number };
  caption: { y: number; size: number };
  tag: { x: number; y: number };
};

export const layoutFor = (f: Format): Layout =>
  f === "wide"
    ? {
        w: 1920,
        h: 1080,
        S: 1.7,
        cx: 1290,
        margin: 96,
        maxTextW: 1728,
        hook: { top: 150, size: 228 },
        verb: { size: 290, bottom: 950 },
        caption: { y: 975, size: 30 },
        tag: { x: 96, y: 64 },
      }
    : {
        w: 1080,
        h: 1920,
        S: 1.6,
        cx: 540,
        margin: 60,
        maxTextW: 960,
        hook: { top: 640, size: 200 },
        verb: { size: 300, bottom: 1500 },
        caption: { y: 1545, size: 32 },
        tag: { x: 60, y: 1830 },
      };

/** Corps de caractères qui tient dans `maxW` (largeur moyenne d'un caractère condensé mesurée ≈ 0,36 em, marge comprise). */
export const fit = (text: string, maxW: number, base: number, k = 0.4) =>
  Math.min(base, Math.floor(maxW / (Math.max(1, text.length) * k)));
