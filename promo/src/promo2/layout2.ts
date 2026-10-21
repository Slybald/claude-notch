export type Format2 = "wide" | "tall";

export type Layout2 = {
  w: number;
  h: number;
  /** Échelle du panneau (1 pt de l'app = S px de la vidéo). */
  S: number;
  cx: number;
  /** Largeur du dessin du curseur (px). */
  cursor: number;
  /** Ordonnée de la zone libre sous le panneau, où le curseur attend et prend le fichier. */
  lowY: number;
  /** Pastille finale : carte noire du nom, carte blanche du lien, ordonnée du haut de la pile. */
  end: { cardW: number; cardH: number; linkW: number; linkH: number; gap: number; top: number; title: number; caption: number; link: number; legal: number; legalY: number };
};

export const layout2 = (f: Format2): Layout2 =>
  f === "wide"
    ? {
        w: 1920,
        h: 1080,
        S: 2.25,
        cx: 960,
        cursor: 32,
        lowY: 930,
        end: { cardW: 820, cardH: 176, linkW: 700, linkH: 104, gap: 28, top: 386, title: 56, caption: 30, link: 33, legal: 19, legalY: 968 },
      }
    : {
        w: 1080,
        h: 1920,
        S: 1.55,
        cx: 540,
        cursor: 40,
        lowY: 760,
        end: { cardW: 900, cardH: 196, linkW: 820, linkH: 116, gap: 30, top: 770, title: 62, caption: 33, link: 31, legal: 21, legalY: 1810 },
      };
