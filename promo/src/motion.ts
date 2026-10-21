import { Easing, interpolate, spring } from "remotion";

export const FPS = 30;
/** Tempo de la vidéo : 120 BPM, donc un temps = 0,5 s = 15 images, une mesure = 2 s = 60 images. */
export const BPM = 120;
export const BEAT = (FPS * 60) / BPM;
export const beat = (n: number) => Math.round(n * BEAT);
export const bar = (n: number) => beat(n * 4);

/** Ressort SwiftUI `.spring(response:dampingFraction:)` traduit en ressort physique (masse 1). */
export function swiftSpring(response: number, dampingFraction: number) {
  const w = (2 * Math.PI) / response;
  return { mass: 1, stiffness: w * w, damping: 2 * dampingFraction * w };
}
/** `notchSpring` de l'app : response 0,42, damping 0,78. */
export const NOTCH_SPRING = swiftSpring(0.42, 0.78);

export function sp(frame: number, at: number, config = NOTCH_SPRING, durationInFrames?: number) {
  return spring({ frame: frame - at, fps: FPS, config, durationInFrames });
}

// Courbes à la main : départ vif, arrivée longue. Jamais de linear ni d'ease-in-out par défaut.
export const outExpo = Easing.bezier(0.16, 1, 0.3, 1);
export const outQuart = Easing.bezier(0.25, 1, 0.5, 1);
export const inQuart = Easing.bezier(0.5, 0, 0.75, 0);
export const inOutCubic = Easing.bezier(0.65, 0, 0.35, 1);

export function ramp(frame: number, from: number, to: number, a = 0, b = 1, easing = outExpo) {
  return interpolate(frame, [from, to], [a, b], {
    easing,
    extrapolateLeft: "clamp",
    extrapolateRight: "clamp",
  });
}
