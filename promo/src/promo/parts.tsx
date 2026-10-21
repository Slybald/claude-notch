import React from "react";
import { C, FONT } from "../theme";
import { inQuart, outExpo, outQuart, ramp } from "../motion";
import { Cursor } from "../ui/icons";

export const display = (size: number): React.CSSProperties => ({
  fontFamily: FONT.display,
  fontStretch: "75%",
  fontWeight: 800,
  fontSize: size,
  lineHeight: 1,
  letterSpacing: -size * 0.015,
  whiteSpace: "nowrap",
});

/**
 * Une ligne de titre révélée par un masque : elle monte depuis sa ligne de base (10 images, sortie expo) et,
 * à la sortie, tombe (6 images, entrée vive). Aucun fondu.
 */
export const MaskLine: React.FC<{
  text: string;
  size: number;
  frame: number;
  inAt: number;
  outAt?: number;
  color: string;
  left: number;
  top: number;
  inDur?: number;
}> = ({ text, size, frame, inAt, outAt = Infinity, color, left, top, inDur = 10 }) => {
  if (frame < inAt - 1 || frame > outAt + 8) return null;
  const enter = ramp(frame, inAt, inAt + inDur, 1, 0, outExpo);
  const exit = Number.isFinite(outAt) ? ramp(frame, outAt, outAt + 6, 0, 1, inQuart) : 0;
  const ty = (enter + exit) * 108;
  return (
    <div style={{ position: "absolute", left, top, height: size * 1.02, overflow: "hidden", paddingRight: size * 0.1 }}>
      <div style={{ ...display(size), color, transform: `translateY(${ty}%)`, willChange: "transform" }}>{text}</div>
    </div>
  );
};

/** Légende en mono : même révélation, plus petite. */
export const MonoLine: React.FC<{
  text: string;
  size: number;
  frame: number;
  inAt: number;
  outAt?: number;
  color: string;
  left: number;
  top: number;
  weight?: number;
}> = ({ text, size, frame, inAt, outAt = Infinity, color, left, top, weight = 500 }) => {
  if (frame < inAt - 1 || frame > outAt + 8) return null;
  const enter = ramp(frame, inAt, inAt + 9, 1, 0, outExpo);
  const exit = Number.isFinite(outAt) ? ramp(frame, outAt, outAt + 5, 0, 1, inQuart) : 0;
  return (
    <div style={{ position: "absolute", left, top, height: size * 1.5, overflow: "hidden" }}>
      <div style={{ fontFamily: FONT.mono, fontWeight: weight, fontSize: size, lineHeight: 1.5, color, whiteSpace: "nowrap", transform: `translateY(${(enter + exit) * 108}%)` }}>
        {text}
      </div>
    </div>
  );
};

export type PKey = { f: number; x: number; y: number; d?: number };

/** Position du pointeur : il attend à sa dernière position, puis rejoint la suivante en `d` images (sortie vive). */
export function pointerAt(frame: number, keys: PKey[]) {
  let pos = { x: keys[0].x, y: keys[0].y };
  for (let i = 1; i < keys.length; i++) {
    const k = keys[i];
    const d = k.d ?? 10;
    const start = k.f - d;
    if (frame >= k.f) pos = { x: k.x, y: k.y };
    else if (frame > start) {
      const t = outQuart((frame - start) / d);
      pos = { x: pos.x + (k.x - pos.x) * t, y: pos.y + (k.y - pos.y) * t };
      break;
    } else break;
  }
  return pos;
}

export const Pointer: React.FC<{
  frame: number;
  keys: PKey[];
  presses?: number[];
  /** Appuis maintenus : [début, fin]. */
  holds?: [number, number][];
  visible: [number, number][];
  size?: number;
}> = ({ frame, keys, presses = [], holds = [], visible, size = 30 }) => {
  const vis = visible.reduce((a, [f0, f1]) => Math.max(a, ramp(frame, f0, f0 + 4, 0, 1) * (1 - ramp(frame, f1 - 4, f1, 0, 1))), 0);
  if (vis <= 0) return null;
  const { x, y } = pointerAt(frame, keys);
  const pulse = presses.reduce((a, p) => Math.max(a, frame >= p && frame <= p + 8 ? 1 - Math.abs((frame - p - 3) / 5) : 0), 0);
  const held = holds.reduce((a, [h0, h1]) => Math.max(a, ramp(frame, h0, h0 + 3, 0, 1) * (1 - ramp(frame, h1, h1 + 3, 0, 1))), 0);
  const press = Math.max(pulse, held);
  const s = 1 - 0.16 * Math.max(0, press);
  return (
    <div style={{ position: "absolute", left: x - 1.4 * (size / 16), top: y - 1.2 * (size / 16), opacity: vis, transform: `scale(${s})`, transformOrigin: "1px 1px", filter: "drop-shadow(0 3px 5px rgba(0,0,0,0.35))" }}>
      <Cursor size={size} />
    </div>
  );
};

/** Pastille de fin : texte en mono dans un contour. Entre avec un ressort sec sur son temps. */
export const Chip: React.FC<{ text: string; frame: number; at: number; left: number; top: number; color: string; size: number }> = ({
  text,
  frame,
  at,
  left,
  top,
  color,
  size,
}) => {
  if (frame < at) return null;
  const p = ramp(frame, at, at + 9, 0, 1, outExpo);
  return (
    <div
      style={{
        position: "absolute",
        left,
        top,
        padding: `${size * 0.42}px ${size * 0.85}px`,
        border: `${Math.max(2, size * 0.08)}px solid ${color}`,
        borderRadius: 999,
        fontFamily: FONT.mono,
        fontSize: size,
        fontWeight: 500,
        color,
        whiteSpace: "nowrap",
        opacity: Math.min(1, p * 2.5),
        transform: `translateY(${(1 - p) * size * 0.9}px)`,
      }}
    >
      {text}
    </div>
  );
};

export const mix = (a: number, b: number, t: number) => a + (b - a) * t;
export const hexMix = (a: string, b: string, t: number) => {
  const pa = [1, 3, 5].map((i) => parseInt(a.slice(i, i + 2), 16));
  const pb = [1, 3, 5].map((i) => parseInt(b.slice(i, i + 2), 16));
  return `rgb(${pa.map((v, i) => Math.round(mix(v, pb[i], t))).join(",")})`;
};
export { C };
