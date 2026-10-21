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

/** Dernière image des vidéos : fin de la carte finale (`CTA_END` dans src/promo2/Promo2.tsx : 15,8 s ; `T.ret` dans src/promo3/Promo3.tsx : 28,25 s ; 60 i/s). */
export const CTA_END_FRAME = 948;
export const CTA_END_FRAME_V3 = 1695;
/** v4 : `CTA_END4` dans src/promo4/Promo4.tsx (T.ret de la v3 après la rampe de vitesse, 22,0 s). À recalculer si la rampe change. */
export const CTA_END_FRAME_V4 = 1320;
