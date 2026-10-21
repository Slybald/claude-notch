// GIF du README : node scripts/gif.mjs [--lang=en] [--fps=15] → ../docs/media/claude-notch[-fr].gif (moins de 5 Mo)
import fs from "node:fs";
import path from "node:path";
import { spawnSync } from "node:child_process";
import { bundle } from "@remotion/bundler";
import { ensureBrowser, renderMedia, selectComposition } from "@remotion/renderer";
import { root } from "./lib.mjs";

const arg = (n, d) => (process.argv.find((a) => a.startsWith(`--${n}=`)) ?? `=${d}`).split("=")[1];
const lang = arg("lang", "en");
const fps = Number(arg("fps", 15));
const scale = Number(arg("scale", 1));
const colors = Number(arg("colors", 128));
const inputProps = { lang };

await ensureBrowser();
const serveUrl = await bundle({ entryPoint: path.join(root, "src/index.ts") });
const composition = await selectComposition({ serveUrl, id: "Readme", inputProps });
fs.mkdirSync(path.join(root, "tmp"), { recursive: true });
const mp4 = path.join(root, "tmp", `readme-${lang}.mp4`);
await renderMedia({ composition, serveUrl, inputProps, codec: "h264", outputLocation: mp4, scale, crf: 10, pixelFormat: "yuv420p", overwrite: true });

const outDir = path.join(root, "..", "docs", "media");
fs.mkdirSync(outDir, { recursive: true });
const gif = path.join(outDir, lang === "fr" ? "claude-notch-fr.gif" : "claude-notch.gif");
const palette = path.join(root, "tmp", "palette.png");
const run = (a) => {
  const r = spawnSync("ffmpeg", ["-y", "-loglevel", "error", ...a], { stdio: "inherit" });
  if (r.status !== 0) process.exit(r.status ?? 1);
};
// Palette adaptée au contenu, tramage léger : l'interface est surtout de grands aplats.
run(["-i", mp4, "-vf", `fps=${fps},palettegen=max_colors=${colors}:stats_mode=diff`, palette]);
run(["-i", mp4, "-i", palette, "-lavfi", `fps=${fps}[x];[x][1:v]paletteuse=dither=bayer:bayer_scale=4:diff_mode=rectangle`, "-loop", "0", gif]);
const kb = Math.round(fs.statSync(gif).size / 1024);
console.log("→", path.relative(path.join(root, ".."), gif), `${kb} Ko`);
process.exit(0);
