import { Easing, interpolate, spring } from "remotion";

// Mouvement de la v2, ajusté sur les mesures de la référence (voir REFERENCE.md, § 7).
export const FPS2 = 60;
/** Secondes → images. */
export const fr = (s: number) => Math.round(s * FPS2);

/** Un seul ressort pour tous les morphings : raideur 460 (ωn ≈ 21,5 rad/s, « response » ≈ 0,29 s). */
const K = 460;
const damping = (zeta: number, k = K) => 2 * zeta * Math.sqrt(k);
/** Agrandir : ζ 0,68, dépassement visible (+3 à +8 % de la course). */
export const GROW = { mass: 1, stiffness: K, damping: damping(0.68) };
/** Réduire : ζ = 1, aucun dépassement. */
export const SHRINK = { mass: 1, stiffness: K, damping: damping(1) };
/** Petits éléments (tuile qui s'allume, bouton) : plus raide. */
export const SNAP = { mass: 1, stiffness: 700, damping: damping(0.8, 700) };

/** Progression d'un ressort qui démarre à `at` (secondes). */
export const sp2 = (frame: number, at: number, config = GROW) => spring({ frame: frame - fr(at), fps: FPS2, config });

/** Course du curseur mesurée : pointe de vitesse à ≈ 46 % de la course, longue fin douce. */
export const CURSOR_EASE = Easing.bezier(0.5, 0.1, 0.2, 1);
export const outExpo = Easing.bezier(0.16, 1, 0.3, 1);

export function ramp2(frame: number, fromS: number, toS: number, a = 0, b = 1, easing: (t: number) => number = outExpo) {
  return interpolate(frame, [fr(fromS), fr(toS)], [a, b], {
    easing,
    extrapolateLeft: "clamp",
    extrapolateRight: "clamp",
  });
}

export const lerp = (a: number, b: number, t: number) => a + (b - a) * t;
export const clamp01 = (n: number) => Math.max(0, Math.min(1, n));
