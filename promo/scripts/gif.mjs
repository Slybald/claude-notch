// GIF du README : node scripts/gif.mjs [--lang=en] [--fps=20] [--scale=0.5] [--gl=angle] → ../docs/media/claude-notch[-fr].gif (moins de 5 Mo)
// C'est la boucle complète de la v4 en 16:9 (retour à la notch fermée), pas la vidéo coupée sur la carte finale.
import fs from "node:fs";
import path from "node:path";
import { spawnSync } from "node:child_process";
import { bundle } from "@remotion/bundler";
import { ensureBrowser, renderMedia, selectComposition } from "@remotion/renderer";
import { root } from "./lib.mjs";

const arg = (n, d) => (process.argv.find((a) => a.startsWith(`--${n}=`)) ?? `=${d}`).split("=")[1];
const lang = arg("lang", "en");
const fps = Number(arg("fps", 16));
const scale = Number(arg("scale", 0.5));
const colors = Number(arg("colors", 96));
const inputProps = { format: "wide", lang };

await ensureBrowser();
const serveUrl = await bundle({ entryPoint: path.join(root, "src/index.ts") });
const composition = await selectComposition({ serveUrl, id: "Promo4-16x9", inputProps });
fs.mkdirSync(path.join(root, "tmp"), { recursive: true });
const mp4 = path.join(root, "tmp", `readme-${lang}.mp4`);
const gl = arg("gl", "");
await renderMedia({ composition, serveUrl, inputProps, codec: "h264", outputLocation: mp4, scale, crf: 10, pixelFormat: "yuv420p", overwrite: true, chromiumOptions: gl ? { gl } : {} });

const outDir = path.join(root, "..", "docs", "media");
fs.mkdirSync(outDir, { recursive: true });
const gif = path.join(outDir, lang === "fr" ? "claude-notch-fr.gif" : "claude-notch.gif");
const palette = path.join(root, "tmp", "palette.png");
const run = (a) => {
  const r = spawnSync("ffmpeg", ["-y", "-loglevel", "error", ...a], { stdio: "inherit" });
  if (r.status !== 0) process.exit(r.status ?? 1);
};
// Palette adaptée au contenu : fond gris clair, aplats noirs, un peu d'orange.
run(["-i", mp4, "-vf", `fps=${fps},palettegen=max_colors=${colors}:stats_mode=diff`, palette]);
run(["-i", mp4, "-i", palette, "-lavfi", `fps=${fps}[x];[x][1:v]paletteuse=dither=bayer:bayer_scale=5:diff_mode=rectangle`, "-loop", "0", gif]);
const kb = Math.round(fs.statSync(gif).size / 1024);
console.log("→", path.relative(path.join(root, ".."), gif), `${kb} Ko`);
if (kb > 5000) console.error("Trop lourd (> 5 Mo) : baisser --fps, --scale ou --colors.");
process.exit(0);
