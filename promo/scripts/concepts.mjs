// Images-clés des trois concepts → promo/concepts/
import path from "node:path";
import { open, root } from "./lib.mjs";

const { still } = await open();
for (const [id, name] of [["ConceptA", "A-le-trou"], ["ConceptB", "B-le-detour"], ["ConceptC", "C-une-journee"]]) {
  await still(id, {}, path.join(root, `concepts/${name}.png`));
}
process.exit(0);
