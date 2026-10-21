import React from "react";
import { FONT } from "../theme";
import { Layout3 } from "./layout3";

const clamp01 = (n: number) => Math.max(0, Math.min(1, n));
const lerp = (a: number, b: number, t: number) => a + (b - a) * t;

/** Chiffre d'un compteur à rouleaux : colonne 0…9 puis 0, déplacée en continu. */
const Digit: React.FC<{ pos: number; size: number }> = ({ pos, size }) => {
  const lh = size * 1.3;
  return (
    <div style={{ height: lh, width: size * 0.62, overflow: "hidden", position: "relative" }}>
      <div style={{ position: "absolute", left: 0, top: 0, transform: `translateY(${-pos * lh}px)` }}>
        {[0, 1, 2, 3, 4, 5, 6, 7, 8, 9, 0].map((d, i) => (
          <div key={i} style={{ height: lh, lineHeight: `${lh}px`, textAlign: "center" }}>{d}</div>
        ))}
      </div>
    </div>
  );
};

/**
 * La roue : une boîte blanche, trois lignes, la fonction du moment au centre. `index` est continu (le ressort est
 * calculé par l'appelant) ; la ligne centrale est nette, les voisines s'éteignent et rétrécissent. À la fin (`morph`),
 * la boîte monte et se resserre en carte du lien.
 */
export const Wheel: React.FC<{
  index: number;
  speed: number;
  names: string[];
  W: Layout3["wheel"];
  cx: number;
  morph?: number;
  link: { top: number; w: number; h: number; font: number; text: string };
  appear?: number;
}> = ({ index, speed, names, W, cx, morph = 0, link, appear = 1 }) => {
  const w = lerp(W.w, link.w, morph);
  const h = lerp(W.h, link.h, morph);
  const top = lerp(W.top, link.top, morph);
  const radius = lerp(W.h * 0.14, h / 2, clamp01(morph * 1.4));
  const drumOp = 1 - clamp01(morph * 3);
  const linkOp = clamp01((morph - 0.5) * 3);
  const v = index + 1;
  const u = v % 10;
  const tens = Math.floor(v / 10) + clamp01(u - 9);
  const blurV = Math.min(3.2, Math.abs(speed) * 0.5);
  return (
    <div
      style={{
        position: "absolute",
        left: cx - w / 2,
        top,
        width: w,
        height: h,
        borderRadius: radius,
        background: "#FDFDFD",
        boxShadow: "0 18px 26px rgba(0,0,0,0.12), 0 4px 8px rgba(0,0,0,0.1)",
        opacity: appear,
        transform: `translateY(${(1 - appear) * 40}px)`,
        fontFamily: FONT.ui,
        color: "#0B0B0B",
        overflow: "hidden",
      }}
    >
      {drumOp > 0.01 && (
        <div style={{ position: "absolute", inset: 0, opacity: drumOp, filter: morph > 0 ? `blur(${morph * 6}px)` : undefined, WebkitMaskImage: "linear-gradient(to bottom, transparent 0%, #000 24%, #000 76%, transparent 100%)" }}>
          <div style={{ position: "absolute", left: W.h * 0.12, right: W.h * 0.12, top: h / 2 - W.pitch * 0.46, height: W.pitch * 0.92, borderRadius: W.pitch * 0.3, background: "rgba(0,0,0,0.045)" }} />
          <div style={{ position: "absolute", left: W.h * 0.26, top: h / 2 - W.counter * 0.65, display: "flex", fontFamily: FONT.mono, fontWeight: 500, fontSize: W.counter, color: "#8A8A84", letterSpacing: "-0.02em" }}>
            <Digit pos={tens} size={W.counter} />
            <Digit pos={u} size={W.counter} />
          </div>
          {names.map((name, i) => {
            const d = i - index;
            const ad = Math.abs(d);
            if (ad > 2.2) return null;
            const o = clamp01(1 - ad * 0.74);
            const sc = 1 - 0.14 * Math.min(ad, 1);
            return (
              <div
                key={i}
                style={{
                  position: "absolute",
                  left: W.h * 0.26 + W.counter * 1.24 + W.counter * 0.9,
                  top: h / 2 + d * W.pitch - W.pitch / 2,
                  height: W.pitch,
                  display: "flex",
                  alignItems: "center",
                  fontSize: W.font,
                  fontWeight: 600,
                  letterSpacing: "-0.025em",
                  whiteSpace: "nowrap",
                  opacity: o,
                  transform: `scale(${sc})`,
                  transformOrigin: "0 50%",
                  filter: `blur(${Math.min(ad, 1) * 1.1 + blurV}px)`,
                }}
              >
                {name}
              </div>
            );
          })}
        </div>
      )}
      {linkOp > 0.01 && (
        <div style={{ position: "absolute", inset: 0, display: "flex", alignItems: "center", justifyContent: "center", opacity: linkOp, filter: linkOp < 1 ? `blur(${(1 - linkOp) * 6}px)` : undefined, fontFamily: FONT.mono, fontSize: link.font, fontWeight: 500, letterSpacing: "-0.02em" }}>
          {link.text}
        </div>
      )}
    </div>
  );
};
