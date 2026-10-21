// Images extraites de la composition : node scripts/frames.mjs <Promo16x9|Promo9x16|Promo2-…|Promo3-16x9|Promo3-9x16> <fr|en> 10,40,... [dossier] [échelle]
import path from "node:path";
import fs from "node:fs";
import { open, root } from "./lib.mjs";

const [id, lang, list, dir = "tmp/frames", scale = "1"] = process.argv.slice(2);
const out = path.join(root, dir);
fs.mkdirSync(out, { recursive: true });
const { still } = await open();
const format = id.includes("9x16") ? "tall" : "wide";
for (const fr of list.split(",").map(Number)) {
  await still(id, { format, lang, music: null }, path.join(out, `f${String(fr).padStart(4, "0")}.png`), { frame: fr, scale: Number(scale) });
}
process.exit(0);
