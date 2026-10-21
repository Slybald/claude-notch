// IDENTITÉ DE L'APP dans la vidéo : le seul fichier à modifier si l'app change de nom.
// Nom, slogan, lien et mentions viennent d'ici partout : carte finale, assistant (« Bienvenue dans … »),
// menu « Quitter … ». Aucun numéro de version dans le film : il serait faux dès la release suivante.
// Après un changement : `node scripts/render.mjs` (EN et `--lang=fr`) puis `node scripts/gif.mjs`.
//
// `icon` : « notch » (le rectangle au tiers haut plein, l'icône de l'assistant de l'app) ou « spark » (l'étoile
// orange, le logo de Claude : seulement si le nom de l'app le reprend).

type Pair = [string, string];

export const APP = {
  name: "Oriel",
  icon: "notch" as "spark" | "notch",
  tagline: ["Your notch finally has a job.", "Ta notch a enfin un travail."] as Pair,
  link: "github.com/Slybald/oriel",
  free: ["Free and open source · macOS 13+", "Gratuit et open source · macOS 13+"] as Pair,
  legal: [
    ["Independent project, not affiliated with or endorsed by Anthropic.", "Projet indépendant, ni affilié à Anthropic ni approuvé par Anthropic."],
    ["Claude is a trademark of Anthropic.", "Claude est une marque d'Anthropic."],
  ] as Pair[],
};
