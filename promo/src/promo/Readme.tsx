import React from "react";
import { AbsoluteFill, useCurrentFrame } from "remotion";
import { useFontsReady } from "../fonts";
import { LangProvider, Lang } from "../i18n";
import { C } from "../theme";
import { NOTCH_SPRING, ramp, sp, swiftSpring } from "../motion";
import { NotchBody, PanelInner, TabId, panelHeight } from "../ui/notch";
import { ClipboardTab, NotesTab, PlayerTab, QuickTab, ShelfTab, TimerTab } from "../ui/tabs";
import { PauseCircle, Radio, Trash } from "../ui/icons";
import { PKey, Pointer } from "./parts";

const lerp = (a: number, b: number, t: number) => a + (b - a) * t;
const clamp01 = (n: number) => Math.max(0, Math.min(1, n));
const SNAP = swiftSpring(0.3, 0.72);

export const README_FRAMES = 300;
export const README_SIZE = { w: 840, h: 440 };
const S = 1.15;
const CX = README_SIZE.w / 2;
const OPEN = 12;
const CLOSE = 278;
const TABS: { tab: TabId; at: number; h: number }[] = [
  { tab: "player", at: 18, h: 150 },
  { tab: "quick", at: 62, h: 200 },
  { tab: "shelf", at: 108, h: 184 },
  { tab: "clip", at: 152, h: 246 },
  { tab: "timer", at: 198, h: 170 },
  { tab: "notes", at: 238, h: 214 },
];

/** Boucle courte pour le README : la notch s'ouvre, parcourt les six onglets, se referme. */
export const Readme: React.FC<{ lang: Lang }> = ({ lang }) => {
  useFontsReady();
  const f = useCurrentFrame();
  const o = Math.max(0, sp(f, OPEN, NOTCH_SPRING) - sp(f, CLOSE, NOTCH_SPRING));
  let ti = 0;
  TABS.forEach((t, i) => {
    if (f >= t.at) ti = i;
  });
  const cur = TABS[ti];
  const prev = TABS[Math.max(0, ti - 1)];
  const p = ti === 0 ? 1 : sp(f, cur.at, SNAP);
  const contentH = lerp(prev.h, cur.h, p);
  const wPt = lerp(197, 644, clamp01(o));
  const hPt = lerp(32, panelHeight(contentH), o);

  const content = (tab: TabId, at: number) => {
    const lf = f - at;
    switch (tab) {
      case "player":
        return <PlayerTab progress={0.33 + lf / 30 / 230} />;
      case "quick":
        return <QuickTab s={{ caf: ramp(f, 88, 94, 0, 1) }} />;
      case "shelf":
        return <ShelfTab count={6} progressOf={(i) => ramp(lf, 4 + i * 2, 16 + i * 2, 0, 1)} />;
      case "clip":
        return <ClipboardTab rows={5} progressOf={(i) => ramp(lf, 3 + i * 3, 16 + i * 3, 0, 1)} hoverRow={f >= 170 && f < 182 ? 2 : -1} copiedRow={f >= 182 && f < 200 ? 2 : -1} />;
      case "timer":
        return <TimerTab remaining={18 * 60 + 12 - lf / 30} />;
      case "notes": {
        const marks = [8, 14, 21, 27, 35, 41, 49, 55, 62];
        return <NotesTab typed={marks.filter((m) => lf >= m).length / marks.length} />;
      }
    }
  };
  const accessory = (tab: TabId) =>
    tab === "shelf" ? (
      <div style={{ display: "flex", alignItems: "center", gap: 8, color: C.secondary, fontSize: 12, fontWeight: 600 }}>
        <span>6 {lang === "fr" ? "éléments" : "items"}</span>
        <Radio size={15} />
        <Trash size={15} />
      </div>
    ) : tab === "clip" ? (
      <PauseCircle size={15} color={C.secondary} />
    ) : undefined;

  const titleOp = ti === 0 || p > 0.98 ? 1 : p < 0.3 ? 1 - p / 0.3 : clamp01((p - 0.3) / 0.4);
  const titleTab = p < 0.3 ? prev.tab : cur.tab;
  const idx = (t: TabId) => ["claude", "player", "quick", "shelf", "clip", "timer", "notes"].indexOf(t);
  const activeX = lerp(idx(prev.tab) * 29, idx(cur.tab) * 29, p);

  const left = CX - (wPt * S) / 2;
  const px = (xpt: number, ypt: number): PKey => ({ f: 0, x: CX - (644 * S) / 2 + xpt * S, y: ypt * S });
  const tabC = (t: TabId, at: number): PKey => ({ ...px(39.5 + 29 * idx(t), 44), f: at - 6, d: 12 });
  const keys: PKey[] = [
    { f: 0, x: 90, y: README_SIZE.h + 30 },
    { ...px(322, 26), f: OPEN - 1, d: 14 },
    { ...px(68.5, 44), f: 16, d: 12 },
    tabC("quick", TABS[1].at),
    { ...px(322, 140), f: 86, d: 14 },
    tabC("shelf", TABS[2].at),
    tabC("clip", TABS[3].at),
    { ...px(322, 202), f: 168, d: 12 },
    tabC("timer", TABS[4].at),
    tabC("notes", TABS[5].at),
  ];

  return (
    <LangProvider lang={lang}>
      <AbsoluteFill style={{ background: C.paper, overflow: "hidden" }}>
        <div style={{ position: "absolute", left, top: 0, transform: `scale(${S})`, transformOrigin: "0 0" }}>
          <NotchBody w={wPt} h={hPt} top={lerp(6, 12, clamp01(o))} bottom={lerp(9, 24, clamp01(o))} shadow={o > 0.2}>
            {o > 0.02 && (
              <div style={{ position: "absolute", left: (wPt - 644) / 2, top: 0, width: 644, height: hPt, opacity: ramp(f, OPEN + 4, OPEN + 14, 0, 1) * (1 - ramp(f, CLOSE - 2, CLOSE + 4, 0, 1)) }}>
                <PanelInner
                  tab={cur.tab}
                  titleTab={titleTab}
                  frame={f}
                  contentH={contentH}
                  titleOpacity={titleOp}
                  accessory={accessory(p > 0.5 ? cur.tab : prev.tab)}
                  tabBarProps={{ activeX }}
                >
                  {p < 0.999 && <div style={{ position: "absolute", inset: 0, opacity: 1 - clamp01(p * 4) }}>{content(prev.tab, prev.at)}</div>}
                  <div style={{ position: "absolute", inset: 0, opacity: p >= 0.999 ? 1 : clamp01((p - 0.2) * 3) }}>{content(cur.tab, cur.at)}</div>
                </PanelInner>
              </div>
            )}
          </NotchBody>
        </div>
        <Pointer frame={f} keys={keys} presses={[90, 172]} visible={[[0, CLOSE - 8]]} size={20} />
      </AbsoluteFill>
    </LangProvider>
  );
};
