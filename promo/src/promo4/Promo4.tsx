import React from "react";
import { AbsoluteFill, Freeze, spring, useCurrentFrame } from "remotion";
import { useFontsReady } from "../fonts";
import { Lang, LangProvider } from "../i18n";
import { FPS2 } from "../motion2";
import { Key, Scene3, T, keysFor } from "../promo3/Promo3";
import { Format3, Layout3, layout3 } from "../promo3/layout3";
import { WINDOW_W } from "../ui/extra";

// v4 : la v3 (contenu, style, roue, appui long) rejouée avec le dynamisme mesuré dans les références de l'utilisateur
// (~/.claude/motion-design/KNOWLEDGE.md). Trois leviers, chacun justifié par une mesure de la v3 :
// 1. rampe de vitesse : la v3 est immobile 33 % du temps (références : 0 à 10 %) ; ses tenues passent en accéléré ;
// 2. caméra qui suit l'action (poussée vers le geste, recul pour révéler) : les références ont des zooms et des
//    travellings, la v3 aucun, et ses éléments bougent 3 à 7 fois moins vite ;
// 3. fouetté du contenu entre onglets et flou de vitesse sur les mouvements rapides.

// ─────────────────────────────── Rampe de vitesse ───────────────────────────────

const BASE = 1.12;
/** Tenues de la v3 (secondes, mesurées par analyze.py sur son rendu) et vitesse à laquelle les jouer. */
const RUSH: [number, number, number][] = [
  [0, 0.45, 1.7], // accroche : la notch réagit avant 0,4 s
  [1.03, 1.17, 2], [2.07, 2.17, 2], [2.68, 2.88, 2], [3.32, 3.5, 2], [3.82, 3.98, 2], [5.32, 5.43, 2],
  [5.9, 6.15, 2], [6.35, 6.48, 2], [7.1, 7.23, 2],
  [7.45, 8.35, 1.45], // saisie de la note
  [8.4, 8.58, 2], [9.08, 9.27, 2],
  [9.45, 10.28, 1.45], // saisie du mail, puis « Envoyer »
  [10.78, 10.98, 2],
  [13.1, 13.83, 1.35], // saisie de la conversation
  [14.28, 14.48, 2], [15.05, 15.25, 2], [15.72, 15.8, 2],
  [15.83, 16.37, 1], // appui long : 0,5 s réelles, comme dans l'app
  [16.47, 16.58, 2], [17.22, 17.4, 2], [18.88, 18.98, 2], [19.42, 19.62, 2],
  [19.8, 20.45, 1.4], // saisie du message
  [20.85, 21.08, 2], [21.48, 22.08, 2.1], [22.62, 22.93, 2.1], [23.58, 23.75, 2], [24.05, 24.22, 2],
  [24.92, 25.13, 2], [25.82, 25.98, 2],
  [26.45, 28.25, 1.6], // carte finale : 1,1 s au lieu de 1,8
];
const smoothstep = (a: number, b: number, x: number) => {
  const u = Math.max(0, Math.min(1, (x - a) / (b - a)));
  return u * u * (3 - 2 * u);
};
const speedAt = (t3: number) => {
  let s = BASE;
  for (const [a, b, v] of RUSH) s += (v - BASE) * smoothstep(a - 0.04, a + 0.04, t3) * (1 - smoothstep(b - 0.04, b + 0.04, t3));
  return s;
};
// Table temps v3 → temps v4, intégrée au 1/1200 s.
const STEP = 1 / 1200;
const TAU: number[] = [];
for (let i = 0, acc = 0; i * STEP <= T.loopEnd + 0.1; i++) {
  TAU.push(acc);
  acc += STEP / speedAt((i + 0.5) * STEP);
}
/** Instant de la v4 (s) où se joue l'instant `t3` de la v3. */
export const v4Of = (t3: number) => {
  const x = Math.max(0, t3 / STEP);
  const i = Math.min(TAU.length - 2, Math.floor(x));
  return TAU[i] + (TAU[i + 1] - TAU[i]) * (x - i);
};
/** Instant de la v3 joué à l'instant `t4` de la v4. */
export const v3Of = (t4: number) => {
  let lo = 0;
  let hi = TAU.length - 1;
  while (hi - lo > 1) {
    const m = (lo + hi) >> 1;
    if (TAU[m] <= t4) lo = m;
    else hi = m;
  }
  return (lo + (t4 - TAU[lo]) / Math.max(1e-9, TAU[hi] - TAU[lo])) * STEP;
};
/** Fin de la vidéo (carte finale) et de la boucle du GIF, en images à 60 i/s. */
export const CTA_END4 = Math.round(v4Of(T.ret) * FPS2);
export const DURATION4 = Math.round(v4Of(T.loopEnd) * FPS2);

// ─────────────────────────────── Caméra ───────────────────────────────

/** Plan de caméra (temps de la v3) : échelle, point visé en pt du panneau ; `x: "cursor"` vise la prochaine arrivée du curseur. */
type Shot = { at: number; s: number; x: number | "cursor"; y: number };
const SHOTS: Shot[] = [
  { at: 0, s: 2.4, x: 322, y: 8 }, // accroche : la notch en gros plan
  { at: 0.25, s: 1.6, x: "cursor", y: 20 }, // le curseur survole l'intercalaire
  { at: 1.05, s: 1.15, x: 322, y: 120 }, // le panneau s'ouvre : recul pour révéler
  { at: 1.5, s: 1.45, x: "cursor", y: 150 }, // pause
  { at: 2.0, s: 1.45, x: "cursor", y: 140 }, // jour du calendrier
  { at: 2.7, s: 1.2, x: 322, y: 120 }, // réglages rapides
  { at: 3.25, s: 1.55, x: "cursor", y: 140 }, // caféine
  { at: 3.8, s: 1.2, x: 322, y: 120 }, // étagère
  { at: 4.2, s: 1.0, x: 322, y: 120 }, // le fichier est pris hors du panneau : plan large
  { at: 4.75, s: 1.4, x: "cursor", y: 150 }, // il se pose
  { at: 5.3, s: 1.25, x: 322, y: 150 }, // presse-papiers
  { at: 5.8, s: 1.5, x: "cursor", y: 190 }, // copie
  { at: 6.3, s: 1.4, x: 322, y: 120 }, // minuteur
  { at: 7.05, s: 1.55, x: 322, y: 140 }, // notes : la saisie
  { at: 8.4, s: 1.2, x: 322, y: 140 }, // mail
  { at: 9.05, s: 1.55, x: "cursor", y: 150 }, // répondre, saisir, envoyer
  { at: 10.8, s: 1.15, x: 322, y: 180 }, // Claude : panneau haut
  { at: 11.85, s: 1.6, x: "cursor", y: 200 }, // « Allow »
  { at: 12.35, s: 1.35, x: "cursor", y: 160 }, // converser
  { at: 14.3, s: 1.2, x: 322, y: 140 }, // Codex
  { at: 15.0, s: 1.6, x: "cursor", y: 210 }, // « Allow »
  { at: 15.6, s: 1.85, x: "cursor", y: 50 }, // appui long sur l'icône : gros plan sur la barre
  { at: 16.5, s: 1.75, x: 170, y: 50 }, // glisser : la caméra suit l'icône
  { at: 17.4, s: 1.6, x: 300, y: 60 }, // « + » et le menu
  { at: 18.35, s: 1.35, x: "cursor", y: 60 }, // « OK »
  { at: 18.8, s: 1.3, x: 322, y: 140 }, // Messages
  { at: 19.45, s: 1.5, x: "cursor", y: 130 }, // réponse
  { at: 20.85, s: 1.5, x: 520, y: 120 }, // menu « … »
  { at: 22.0, s: 1.0, x: 322, y: 120 }, // la notch se replie : plan large
];
const CAM = { mass: 1, stiffness: 120, damping: 2 * 0.9 * Math.sqrt(120) }; // ζ 0,9, ω 11 : mesuré sur les caméras des références

type Cam = { s: number; tx: number; ty: number };
type Target = { at4: number; s: number; x: number; y: number };

function targetsFor(format: Format3, L: Layout3, keys: Key[]): Target[] {
  const left = L.cx - (644 * L.S) / 2;
  // En 9:16 le panneau remplit déjà la largeur : poussées réduites (sauf l'accroche sur la notch repliée).
  const k = (i: number) => (format === "wide" || i < 2 ? 1 : 0.3);
  const out = SHOTS.map((c, i) => {
    const next = keys.find((q) => q.arrive >= c.at) ?? keys[keys.length - 1];
    return { at4: v4Of(c.at), s: 1 + (c.s - 1) * k(i), x: c.x === "cursor" ? next.x : left + c.x * L.S, y: c.y * L.S };
  });
  // Assistant : poussée vers le profil choisi, puis plan large pour la carte du nom.
  const wl = L.cx - (WINDOW_W * L.win.S) / 2;
  out.push({ at4: v4Of(24.0), s: 1 + 0.25 * k(99), x: wl + 328 * L.win.S, y: L.win.top + 270 * L.win.S });
  out.push({ at4: v4Of(24.85), s: 1, x: L.cx, y: L.h / 2 });
  return out;
}

function cameraAt(t4: number, L: Layout3, tg: Target[]): Cam {
  const panelL = L.cx - (644 * L.S) / 2;
  const panelR = L.cx + (644 * L.S) / 2;
  let { s, x, y } = tg[0];
  for (let i = 1; i < tg.length; i++) {
    const p = spring({ frame: (t4 - tg[i].at4) * FPS2, fps: FPS2, config: CAM });
    s += (tg[i].s - tg[i - 1].s) * p;
    x += (tg[i].x - tg[i - 1].x) * p;
    y += (tg[i].y - tg[i - 1].y) * p;
  }
  // Le point visé va au centre (un peu au-dessus en hauteur), sans jamais montrer le bord de la scène :
  // la notch reste accrochée au haut du cadre tant que la caméra vise haut.
  // Tant que le panneau est ouvert, ses bords latéraux bornent le cadrage (aucun vide à côté d'un gros plan).
  const clamp = (v: number, lo: number, hi: number) => Math.max(lo, Math.min(hi, v));
  const free = L.w / 2 - x * s;
  const onStage = clamp(free, L.w - L.w * s, 0);
  const onPanel = (panelR - panelL) * s >= L.w ? clamp(free, L.w - panelR * s, -panelL * s) : L.w / 2 - L.cx * s;
  const k = smoothstep(v4Of(T.collapse - 0.1), v4Of(T.collapse + 0.4), t4);
  return { s, tx: onPanel + (onStage - onPanel) * k, ty: clamp(L.h * 0.42 - y * s, L.h - L.h * s, 0) };
}

// ─────────────────────────────── Flou de vitesse ───────────────────────────────

/** Fenêtres (temps de la v3) où le contenu bouge vite : fouetté des onglets, chute de la notch, carte, lien. */
const FAST: [number, number][] = [
  ...[T.quick, T.shelf, T.clip, T.timer, T.notes, T.mail, T.claude, T.codex, T.messages].map((a) => [a, a + 0.2] as [number, number]),
  [T.open, T.open + 0.25], [T.collapse, T.collapse + 0.3], [T.fall, T.fall + 0.4], [T.pill, T.pill + 0.3], [T.link, T.link + 0.3],
];

/** Flou de vitesse : moyenne de `n` instants répartis sur une demi-image, centrés sur l'image courante. */
const MotionBlur: React.FC<{ n: number; children: React.ReactNode }> = ({ n, children }) => {
  const f = useCurrentFrame();
  return (
    <AbsoluteFill style={{ isolation: "isolate" }}>
      {Array.from({ length: n }, (_, i) => (
        <AbsoluteFill key={i} style={{ mixBlendMode: "plus-lighter", filter: `opacity(${1 / n})` }}>
          <Freeze frame={f + 0.5 * ((i + 0.5) / n - 0.5)}>{children}</Freeze>
        </AbsoluteFill>
      ))}
    </AbsoluteFill>
  );
};

// ─────────────────────────────── Composition ───────────────────────────────

export type Promo4Props = { format: Format3; lang: Lang };

export const Promo4: React.FC<Promo4Props> = ({ format, lang }) => {
  useFontsReady();
  const f = useCurrentFrame();
  const L = React.useMemo(() => layout3(format), [format]);
  const tg = React.useMemo(() => targetsFor(format, L, keysFor(L)), [format, L]);
  const t4 = f / FPS2;
  const t3 = v3Of(t4);
  const a = cameraAt(t4, L, tg);
  const b = cameraAt(t4 - 1 / FPS2, L, tg);
  const camSpeed = Math.abs(a.tx - b.tx) + Math.abs(a.ty - b.ty) + Math.abs(a.s - b.s) * Math.max(L.w, L.h); // px par image
  const fast = camSpeed > 9 || FAST.some(([x, y]) => t3 >= x && t3 < y);
  const shot = <Shot format={format} lang={lang} L={L} tg={tg} />;
  return (
    <LangProvider lang={lang}>
      <AbsoluteFill style={{ background: "#EDEDE8" }}>{fast ? <MotionBlur n={6}>{shot}</MotionBlur> : shot}</AbsoluteFill>
    </LangProvider>
  );
};

const Shot: React.FC<{ format: Format3; lang: Lang; L: Layout3; tg: Target[] }> = ({ format, lang, L, tg }) => {
  const t4 = useCurrentFrame() / FPS2;
  const t3 = v3Of(t4);
  const cam = cameraAt(t4, L, tg);
  return (
    <AbsoluteFill style={{ background: "#EDEDE8", overflow: "hidden" }}>
      <AbsoluteFill style={{ transform: `translate(${cam.tx}px, ${cam.ty}px) scale(${cam.s})`, transformOrigin: "0 0" }}>
        <Scene3 format={format} lang={lang} layer="stage" whip frame={t3 * FPS2} />
      </AbsoluteFill>
      <Scene3 format={format} lang={lang} layer="hud" frame={t3 * FPS2} />
    </AbsoluteFill>
  );
};
