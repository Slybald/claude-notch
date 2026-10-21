export type Format3 = "wide" | "tall";

export type Layout3 = {
  w: number;
  h: number;
  /** Échelle du panneau (1 pt de l'app = S px de la vidéo). */
  S: number;
  cx: number;
  cursor: number;
  /** Où le curseur prend le fichier de l'étagère (zone libre sous le panneau). */
  pick: { x: number; y: number };
  /** Roue : boîte blanche sous le panneau, trois lignes. */
  wheel: { w: number; h: number; top: number; pitch: number; font: number; counter: number };
  /** Fenêtre de l'assistant : échelle et ordonnée du haut. */
  win: { S: number; top: number };
  end: { cardW: number; cardH: number; linkW: number; linkH: number; gap: number; top: number; title: number; caption: number; link: number; legal: number; legalY: number };
};

export const layout3 = (f: Format3): Layout3 =>
  f === "wide"
    ? {
        w: 1920,
        h: 1080,
        S: 2,
        cx: 960,
        cursor: 32,
        pick: { x: 1580, y: 690 },
        wheel: { w: 980, h: 190, top: 858, pitch: 64, font: 47, counter: 28 },
        win: { S: 1.55, top: 30 },
        end: { cardW: 1100, cardH: 232, linkW: 960, linkH: 136, gap: 34, top: 339, title: 74, caption: 39, link: 41, legal: 19, legalY: 968 },
      }
    : {
        w: 1080,
        h: 1920,
        S: 1.55,
        cx: 540,
        cursor: 40,
        pick: { x: 860, y: 640 },
        wheel: { w: 960, h: 276, top: 830, pitch: 92, font: 64, counter: 40 },
        win: { S: 1.5, top: 40 },
        end: { cardW: 940, cardH: 216, linkW: 860, linkH: 124, gap: 32, top: 760, title: 68, caption: 36, link: 33, legal: 21, legalY: 1810 },
      };
