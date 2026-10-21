import { useEffect, useState } from "react";
import { continueRender, delayRender } from "remotion";
import "@fontsource/inter/400.css";
import "@fontsource/inter/500.css";
import "@fontsource/inter/600.css";
import "@fontsource/inter/700.css";
import "@fontsource/inter/800.css";
import "@fontsource/jetbrains-mono/400.css";
import "@fontsource/jetbrains-mono/500.css";
import "@fontsource/jetbrains-mono/700.css";
import "@fontsource-variable/bricolage-grotesque/wdth.css";

const FACES = [
  '400 16px "Inter"',
  '500 16px "Inter"',
  '600 16px "Inter"',
  '700 16px "Inter"',
  '800 16px "Inter"',
  '400 16px "JetBrains Mono"',
  '500 16px "JetBrains Mono"',
  '700 16px "JetBrains Mono"',
  '800 16px "Bricolage Grotesque Variable"',
];

/** Bloque le rendu jusqu'au chargement des polices (sinon les premières images changent de police). */
export function useFontsReady() {
  const [handle] = useState(() => delayRender("polices"));
  useEffect(() => {
    Promise.all(FACES.map((f) => document.fonts.load(f)))
      .then(() => document.fonts.ready)
      .finally(() => continueRender(handle));
  }, [handle]);
}
