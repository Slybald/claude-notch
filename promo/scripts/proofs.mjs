// Rendus de contrôle de l'interface recréée, à comparer aux rendus de l'app.
import path from "node:path";
import { open, root } from "./lib.mjs";

const lang = process.argv[2] ?? "fr";
const tabs = process.argv.slice(3);
const all = ["claude", "player", "quick", "shelf", "clip", "timer", "notes", "reply", "chat", "ears"];
const { still } = await open();
for (const tab of tabs.length ? tabs : all) {
  await still("Proof", { tab, lang }, path.join(root, `tmp/proof-${tab}-${lang}.png`));
}
process.exit(0);
