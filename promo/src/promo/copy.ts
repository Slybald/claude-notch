import { Lang } from "../i18n";

type Pair = [string, string];
const pick = (lang: Lang, p: Pair) => (lang === "fr" ? p[1] : p[0]);

export const COPY = {
  hook1: [
    ["Your Mac", "Ton Mac"],
    ["has a hole", "a un trou"],
    ["in the screen.", "dans l'écran."],
  ] as Pair[],
  hook2: [
    ["It does", "Il ne"],
    ["nothing.", "sert à rien."],
  ] as Pair[],
  hook3: ["Until now.", "Plus maintenant."] as Pair,
  // verbe géant, légende en mono
  player: [["Listen.", "Écoute."], ["Now playing. Your week.", "Le morceau en cours. Ta semaine."]] as [Pair, Pair],
  quick: [["Switch.", "Bascule."], ["Wi-Fi, Bluetooth, caffeine.", "Wi-Fi, Bluetooth, caféine."]] as [Pair, Pair],
  shelf: [["Drop.", "Dépose."], ["Files wait on the notch.", "Tes fichiers attendent dans la notch."]] as [Pair, Pair],
  clip: [["Reuse.", "Reprends."], ["Your last copies, one click.", "Tes dernières copies, un clic."]] as [Pair, Pair],
  timer: [["Focus.", "Concentre-toi."], ["Timer and Pomodoro.", "Minuteur et Pomodoro."]] as [Pair, Pair],
  notes: [["Jot.", "Note."], ["Quick notes.", "Notes rapides."]] as [Pair, Pair],
  devIntro: ["If you code with Claude Code…", "Si tu codes avec Claude Code…"] as Pair,
  asks: [["It asks.", "Il demande."], ["Permissions, questions, plans.", "Permissions, questions, plans."]] as [Pair, Pair],
  answer: [["You answer.", "Tu réponds."], ["Allow or deny, with a reason.", "Autorise ou refuse, avec un motif."]] as [Pair, Pair],
  fromNotch: [["From the notch.", "Depuis la notch."], ["Optional. Off until you turn it on.", "En option. Coupé tant que tu ne l'actives pas."]] as [Pair, Pair],
  yours: [["Yours.", "À toi."], ["Press, hold, drag. Like home-screen apps.", "Appui long, glisse. Comme les apps d'un écran d'accueil."]] as [Pair, Pair],
  title: ["Claude Notch.", "Claude Notch."] as Pair,
  titleTall: [["Claude", "Claude"], ["Notch.", "Notch."]] as Pair[],
  tagline: ["Your notch finally has a job.", "Ta notch a enfin un travail."] as Pair,
  chips: [
    ["Everything stays on your Mac", "Tout reste sur ton Mac"],
    ["Signed automatic updates", "Mises à jour signées et automatiques"],
    ["Setup in four steps", "Réglage en quatre étapes"],
  ] as Pair[],
  free: ["Free and open source · macOS 13+", "Gratuit et open source · macOS 13+"] as Pair,
  link: "github.com/Slybald/claude-notch",
  legal: [
    "Independent project, not affiliated with or endorsed by Anthropic. Claude is a trademark of Anthropic.",
    "Projet indépendant, ni affilié à Anthropic ni approuvé par Anthropic. Claude est une marque d'Anthropic.",
  ] as Pair,
  tag: "CLAUDE NOTCH 1.5",
};

export const tx = (lang: Lang, p: Pair) => pick(lang, p);
