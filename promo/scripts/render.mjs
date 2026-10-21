// Rendu des vidéos : node scripts/render.mjs [--v=2|1] [--target=16x9|9x16|both] [--lang=en|fr] [--scale=2] [--preview] [--frames=0-120]
// v2 (par défaut) : 60 i/s, muette, sortie dans out/v2/. v1 : 30 i/s, musique facultative (public/music.*), sortie dans out/.
// 4K par défaut (scale 2 sur la composition 1080p), puis 1080p dérivé par ffmpeg.
import fs from "node:fs";
import path from "node:path";
import { spawnSync } from "node:child_process";
import { bundle } from "@remotion/bundler";
import { ensureBrowser, renderMedia, selectComposition } from "@remotion/renderer";
import { root } from "./lib.mjs";
import { CTA_END_FRAME } from "./lib.mjs";

const arg = (name, def) => {
  const hit = process.argv.find((a) => a === `--${name}` || a.startsWith(`--${name}=`));
  if (!hit) return def;
  return hit.includes("=") ? hit.split("=")[1] : true;
};
const v = arg("v", "2");
const preview = arg("preview", false) === true;
const target = arg("target", "both");
const lang = arg("lang", "en");
const scale = Number(arg("scale", preview ? 0.5 : 2));
// v2 : la vidéo s'arrête sur la pastille finale ; la boucle complète (retour à la notch fermée) sert au GIF.
const frames = arg("frames", v === "2" ? `0-${CTA_END_FRAME - 1}` : null);
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
const outDir = path.join(root, preview ? "tmp" : v === "2" ? "out/v2" : "out");
fs.mkdirSync(outDir, { recursive: true });

const jobs = [];
const idOf = (shape) => (v === "2" ? `Promo2-${shape}` : `Promo${shape}`);
if (target === "16x9" || target === "both") jobs.push([idOf("16x9"), "wide", "claude-notch-16x9"]);
if (target === "9x16" || target === "both") jobs.push([idOf("9x16"), "tall", "claude-notch-9x16"]);

for (const [id, format, name] of jobs) {
  const inputProps = v === "2" ? { format, lang } : { format, lang, music };
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
