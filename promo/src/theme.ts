// Couleurs de l'app (Palette dans Sources/ClaudeNotch/NotchViews.swift) et de la vidéo.
export const C = {
  black: "#000000",
  accent: "#D97757",
  amber: "#F5B83D",
  green: "#4ADE80",
  red: "#F87171",
  white: "#FFFFFF",
  // Surfaces de l'app : blanc à 5 % sur noir.
  card: "rgba(255,255,255,0.05)",
  cardHi: "rgba(255,255,255,0.08)",
  secondary: "rgba(255,255,255,0.6)",
  tertiary: "rgba(255,255,255,0.4)",
  // Fonds de la vidéo.
  paper: "#EFEAE0",
  paperDeep: "#E2DBCB",
  ink: "#0B0B0B",
  graphite: "#121214",
};

export const FONT = {
  // Inter (OFL 1.1) tient la place de la police système de macOS.
  ui: '"Inter", system-ui, sans-serif',
  mono: '"JetBrains Mono", ui-monospace, monospace',
  // Bricolage Grotesque (OFL 1.1) : titres de la vidéo, axe de largeur pour les caractères condensés.
  display: '"Bricolage Grotesque Variable", "Inter", sans-serif',
};

/** Corps de texte de l'interface recréée : Inter est environ 7 % plus large que la police système de macOS,
 *  on réduit donc les corps pour garder les largeurs mesurées sur les rendus de l'app. */
export const F = (pt: number) => Math.round(pt * 0.93 * 100) / 100;
