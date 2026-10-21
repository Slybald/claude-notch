// IDENTITÉ DE L'APP dans la vidéo : le seul fichier à modifier si l'app change de nom.
// Nom, version, slogan, lien et mentions viennent d'ici partout : carte finale, assistant (« Bienvenue dans … »),
// menu « Quitter … », message de mise à jour. Puis `node scripts/render.mjs` et `node scripts/gif.mjs`.
//
// `icon` : « spark » (l'étoile orange, sans « Claude » dans le nom elle n'a plus de sens : passer à « notch ») ou
// « notch » (le rectangle au tiers haut plein, l'icône de l'assistant de l'app).

type Pair = [string, string];

export const APP = {
  name: "Claude Notch",
  version: "1.8.0",
  icon: "spark" as "spark" | "notch",
  tagline: ["Your notch finally has a job.", "Ta notch a enfin un travail."] as Pair,
  link: "github.com/Slybald/claude-notch",
  free: ["Free and open source · macOS 13+", "Gratuit et open source · macOS 13+"] as Pair,
  legal: [
    ["Independent project, not affiliated with or endorsed by Anthropic.", "Projet indépendant, ni affilié à Anthropic ni approuvé par Anthropic."],
    ["Claude is a trademark of Anthropic.", "Claude est une marque d'Anthropic."],
  ] as Pair[],
};
