import path from "node:path";
import { fileURLToPath } from "node:url";
import { bundle } from "@remotion/bundler";
import { renderStill, selectComposition, ensureBrowser } from "@remotion/renderer";

export const root = path.resolve(path.dirname(fileURLToPath(import.meta.url)), "..");

/** Empaquette le projet une seule fois ; `still(id, props, out, scale)` rend ensuite une image. */
export async function open() {
  await ensureBrowser();
  const serveUrl = await bundle({ entryPoint: path.join(root, "src/index.ts") });
  return {
    serveUrl,
    async still(id, inputProps, output, { scale = 1, frame = 0 } = {}) {
      const composition = await selectComposition({ serveUrl, id, inputProps });
      await renderStill({ composition, serveUrl, output, inputProps, scale, frame, imageFormat: "png" });
      console.log("→", path.relative(root, output));
    },
  };
}

/** Dernière image de la vidéo v2 : fin de la pastille finale (voir `CTA_END` dans src/promo2/Promo2.tsx : 15,8 s à 60 i/s). */
export const CTA_END_FRAME = 948;
