import React from "react";
import { AbsoluteFill } from "remotion";
import { useFontsReady } from "./fonts";
import { LangProvider } from "./i18n";
import { C, FONT } from "./theme";
import { NotchBody, Panel } from "./ui/notch";
import { ClipboardTab, QuickTab } from "./ui/tabs";
import { Ears, SessionCount } from "./ui/claude";
import { Check, Hand } from "./ui/icons";

const display = (size: number, extra: React.CSSProperties = {}): React.CSSProperties => ({
  fontFamily: FONT.display,
  fontStretch: "75%",
  fontWeight: 800,
  fontSize: size,
  lineHeight: 0.88,
  letterSpacing: -size * 0.015,
  ...extra,
});

/** Place un panneau (unités pt) à l'échelle `s`, centré sur `cx`, accroché au haut du cadre. */
const Hung: React.FC<{ cx: number; s: number; w?: number; children: React.ReactNode }> = ({ cx, s, w = 644, children }) => (
  <div style={{ position: "absolute", left: cx - w / 2, top: 0, transform: `scale(${s})`, transformOrigin: "50% 0" }}>{children}</div>
);

// ── Concept A : « Le trou » — affiche typographique, crème et noir ─────────────────────────
export const ConceptA: React.FC = () => {
  useFontsReady();
  return (
    <LangProvider lang="en">
      <AbsoluteFill style={{ background: C.paper }}>
        <div style={{ position: "absolute", left: 96, top: 150, color: C.ink, ...display(228) }}>
          Your Mac
          <br />
          has a hole
          <br />
          in the screen<span style={{ color: C.accent }}>.</span>
        </div>
        <div style={{ position: "absolute", left: 100, bottom: 70, fontFamily: FONT.mono, fontSize: 24, color: C.ink, opacity: 0.7, letterSpacing: 0.5 }}>
          CLAUDE NOTCH — FOR macOS · OPEN SOURCE
        </div>
        <Hung cx={1380} s={1.2}>
          <Panel tab="quick" contentH={200}>
            <QuickTab s={{ wifi: 1, bt: 1, focus: 0, low: 0, caf: 1 }} />
          </Panel>
        </Hung>
      </AbsoluteFill>
    </LangProvider>
  );
};

// ── Concept B : « Le détour » — le trajet du curseur, en ligne ────────────────────────────
const path =
  "M150 930 C 420 960, 620 760, 470 640 S 250 430, 520 380 S 900 520, 760 700 S 1140 900, 1260 700 S 1040 420, 1330 400 S 1700 560, 1560 760 S 1740 960, 1800 880";
const stops: [number, number, string][] = [
  [470, 640, "System Settings › Wi-Fi"],
  [520, 380, "Finder › Downloads"],
  [760, 700, "Cmd-Tab › Terminal"],
  [1260, 700, "Notes — where was it?"],
  [1330, 400, "Menu bar › Bluetooth"],
  [1560, 760, "Scroll through copies…"],
];
export const ConceptB: React.FC = () => {
  useFontsReady();
  return (
    <LangProvider lang="en">
      <AbsoluteFill style={{ background: "#F6F4EE" }}>
        <svg width="1920" height="1080" style={{ position: "absolute", inset: 0 }}>
          <defs>
            <pattern id="dots" width="40" height="40" patternUnits="userSpaceOnUse">
              <circle cx="2" cy="2" r="1.6" fill="#0B0B0B" opacity="0.14" />
            </pattern>
          </defs>
          <rect width="1920" height="1080" fill="url(#dots)" />
          <path d={path} fill="none" stroke={C.accent} strokeWidth={6} strokeLinecap="round" strokeLinejoin="round" />
          {stops.map(([x, y, label]) => (
            <g key={label}>
              <circle cx={x} cy={y} r={11} fill="#F6F4EE" stroke={C.ink} strokeWidth={3} />
              <text x={x + 22} y={y + 8} fontFamily={FONT.mono} fontSize={23} fill={C.ink}>
                {label}
              </text>
            </g>
          ))}
          <path d="M1790 880 L1790 90" stroke={C.ink} strokeWidth={6} strokeLinecap="round" fill="none" />
          <circle cx={1790} cy={880} r={11} fill={C.ink} />
        </svg>
        <div style={{ position: "absolute", left: 96, top: 90, color: C.ink, ...display(150) }}>
          Seven detours.
          <br />
          <span style={{ color: C.accent }}>One flick.</span>
        </div>
        <Hung cx={1790} s={1} w={257}>
          <Ears left={<Check size={14} color={C.green} />} right={<SessionCount a="1" b="0" />} shadow />
        </Hung>
      </AbsoluteFill>
    </LangProvider>
  );
};

// ── Concept C : « Une journée dans la notch » — l'heure, une frise ───────────────────────
export const ConceptC: React.FC = () => {
  useFontsReady();
  const hours = [9, 10, 11, 12, 13, 14, 15, 16, 17, 18];
  const x0 = 140;
  const dx = 182;
  const nowX = x0 + dx * (5 + 32 / 60);
  return (
    <LangProvider lang="en">
      <AbsoluteFill style={{ background: C.graphite }}>
        <div style={{ position: "absolute", left: 100, top: 300, fontFamily: FONT.mono, fontWeight: 700, fontSize: 330, letterSpacing: -14, color: "#ECE9E2", lineHeight: 1 }}>
          14<span style={{ color: C.accent }}>:</span>32
        </div>
        <div style={{ position: "absolute", left: 108, top: 650, fontFamily: FONT.mono, fontSize: 28, color: "rgba(236,233,226,0.6)" }}>
          copied twice, pasted once, never lost.
        </div>
        <Hung cx={1380} s={1.05}>
          <Panel tab="clip" contentH={246}>
            <ClipboardTab rows={4} />
          </Panel>
        </Hung>
        <svg width="1920" height="1080" style={{ position: "absolute", inset: 0 }}>
          <line x1={x0} y1={930} x2={x0 + dx * 9} y2={930} stroke="rgba(236,233,226,0.35)" strokeWidth={2} />
          {hours.map((h, i) => (
            <g key={h}>
              <line x1={x0 + dx * i} y1={918} x2={x0 + dx * i} y2={942} stroke="rgba(236,233,226,0.55)" strokeWidth={2} />
              <text x={x0 + dx * i} y={985} textAnchor="middle" fontFamily={FONT.mono} fontSize={24} fill="rgba(236,233,226,0.55)">
                {String(h).padStart(2, "0")}:00
              </text>
            </g>
          ))}
          <line x1={nowX} y1={890} x2={nowX} y2={960} stroke={C.accent} strokeWidth={5} strokeLinecap="round" />
          <circle cx={nowX} cy={890} r={9} fill={C.accent} />
        </svg>
      </AbsoluteFill>
    </LangProvider>
  );
};
