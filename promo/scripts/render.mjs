// Rendu des vidéos : node scripts/render.mjs [--v=4|3|2|1] [--target=16x9|9x16|both] [--lang=en|fr] [--scale=2] [--preview] [--frames=0-120] [--concurrency=8]
// v4 (par défaut) et v3 : 60 i/s, muettes, sortie dans out/v4/ ou out/v3/ (notch-promo-*). v2 : out/v2/ (claude-notch-*). v1 : 30 i/s, musique facultative (public/music.*), sortie dans out/.
// 4K par défaut (scale 2 sur la composition 1080p), puis 1080p dérivé par ffmpeg.
import fs from "node:fs";
import path from "node:path";
import { spawnSync } from "node:child_process";
import { bundle } from "@remotion/bundler";
import { ensureBrowser, renderMedia, selectComposition } from "@remotion/renderer";
import { root } from "./lib.mjs";
import { CTA_END_FRAME, CTA_END_FRAME_V3, CTA_END_FRAME_V4 } from "./lib.mjs";

const arg = (name, def) => {
  const hit = process.argv.find((a) => a === `--${name}` || a.startsWith(`--${name}=`));
  if (!hit) return def;
  return hit.includes("=") ? hit.split("=")[1] : true;
};
const v = arg("v", "4");
const preview = arg("preview", false) === true;
const target = arg("target", "both");
const lang = arg("lang", "en");
const scale = Number(arg("scale", preview ? 0.5 : 2));
// v2 : la vidéo s'arrête sur la pastille finale ; la boucle complète (retour à la notch fermée) sert au GIF.
const END = { 4: CTA_END_FRAME_V4, 3: CTA_END_FRAME_V3, 2: CTA_END_FRAME }[v];
const frames = arg("frames", END ? `0-${END - 1}` : null);
const suffix = lang === "fr" ? "-fr" : "";

// Piste audio facultative : public/music.mp3 (ou .wav/.m4a/.ogg) + public/music.json {"bpm":118,"startFromSeconds":0}
const pub = path.join(root, "public");
const musicFile = v === "1" ? ["mp3", "wav", "m4a", "ogg"].map((e) => `music.${e}`).find((f) => fs.existsSync(path.join(pub, f))) : undefined;
let music = null;
if (musicFile) {
  const meta = fs.existsSync(path.join(pub, "music.json")) ? JSON.parse(fs.readFileSync(path.join(pub, "music.json"), "utf8")) : {};
  music = { file: musicFile, startFromSeconds: meta.startFromSeconds ?? 0, playbackRate: meta.bpm ? 120 / meta.bpm : 1 };
  console.log("Musique :", musicFile, music);
} else {
  console.log("Vidéo muette.");
}

await ensureBrowser();
const serveUrl = await bundle({ entryPoint: path.join(root, "src/index.ts") });
const outDir = path.join(root, preview ? "tmp" : v === "1" ? "out" : `out/v${v}`);
fs.mkdirSync(outDir, { recursive: true });

const jobs = [];
const idOf = (shape) => (v === "1" ? `Promo${shape}` : `Promo${v}-${shape}`);
const base = v === "3" || v === "4" ? "notch-promo" : "claude-notch";
if (target === "16x9" || target === "both") jobs.push([idOf("16x9"), "wide", `${base}-16x9`]);
if (target === "9x16" || target === "both") jobs.push([idOf("9x16"), "tall", `${base}-9x16`]);

for (const [id, format, name] of jobs) {
  const inputProps = v === "1" ? { format, lang, music } : { format, lang };
  const composition = await selectComposition({ serveUrl, id, inputProps });
  const raw = path.join(outDir, `${name}${suffix}${preview ? "-preview" : "-master"}.mp4`);
  let last = 0;
  await renderMedia({
    composition,
    serveUrl,
    inputProps,
    codec: "h264",
    outputLocation: raw,
    scale,
    crf: preview ? 24 : 15,
    x264Preset: preview ? "veryfast" : "slow",
    concurrency: arg("concurrency", null) ? Number(arg("concurrency", null)) : null,
    pixelFormat: "yuv420p",
    frameRange: frames ? frames.split("-").map(Number) : null,
    audioCodec: "aac",
    overwrite: true,
    onProgress: ({ progress }) => {
      const pct = Math.floor(progress * 100);
      if (pct >= last + 10) {
        last = pct;
        console.log(`${id} ${pct} %`);
      }
    },
  });
  if (preview) {
    console.log("→", path.relative(root, raw));
    continue;
  }
  // Version de diffusion : master 4K + 1080p, faststart.
  const final4k = path.join(outDir, `${name}${suffix}-4k.mp4`);
  const final = path.join(outDir, `${name}${suffix}.mp4`);
  const run = (a) => {
    const r = spawnSync("ffmpeg", ["-y", "-loglevel", "error", ...a], { stdio: "inherit" });
    if (r.status !== 0) process.exit(r.status ?? 1);
  };
  run(["-i", raw, "-c", "copy", "-movflags", "+faststart", final4k]);
  const w = composition.width;
  const h = composition.height;
  run(["-i", raw, "-vf", `scale=${w}:${h}:flags=lanczos`, "-c:v", "libx264", "-preset", "slow", "-crf", "17", "-pix_fmt", "yuv420p", "-c:a", "copy", "-movflags", "+faststart", final]);
  fs.rmSync(raw);
  console.log("→", path.relative(root, final), "et", path.relative(root, final4k));
}
process.exit(0);
