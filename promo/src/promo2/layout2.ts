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
        end: { cardW: 1100, cardH: 232, linkW: 960, linkH: 136, gap: 34, top: 339, title: 74, caption: 39, link: 41, legal: 19, legalY: 968 },
      }
    : {
        w: 1080,
        h: 1920,
        S: 1.55,
        cx: 540,
        cursor: 40,
        lowY: 760,
        end: { cardW: 940, cardH: 216, linkW: 860, linkH: 124, gap: 32, top: 760, title: 68, caption: 36, link: 33, legal: 21, legalY: 1810 },
      };
