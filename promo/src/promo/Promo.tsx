import React from "react";
import { AbsoluteFill, Audio, staticFile, useCurrentFrame } from "remotion";
import { useFontsReady } from "../fonts";
import { LangProvider, Lang, useLang } from "../i18n";
import { C, FONT } from "../theme";
import { beat, outExpo, outQuart, NOTCH_SPRING, ramp, sp, swiftSpring } from "../motion";
import { DEFAULT_ORDER, NotchBody, NOTCH_H, PanelInner, TabId, panelHeight } from "../ui/notch";
import { ClipboardTab, FileGlyph, NotesTab, PlayerTab, QuickTab, SHELF_ITEMS, ShelfTab, TimerTab } from "../ui/tabs";
import { Conversation, PermissionReply, SessionCard, SessionCount } from "../ui/claude";
import { Check, Hand, PauseCircle, Radio, Trash } from "../ui/icons";
import { COPY, tx } from "./copy";
import { Format, Layout, fit, fitMono, layoutFor } from "./layout";
import { Chip, MonoLine, MaskLine, PKey, Pointer, hexMix, pointerAt } from "./parts";

const B = beat;
export const DURATION = B(80);
const clamp01 = (n: number) => Math.max(0, Math.min(1, n));
const lerp = (a: number, b: number, t: number) => a + (b - a) * t;

// ─────────────────────────────── Calendrier ───────────────────────────────
const T = {
  thump: B(2),
  hook2: B(4),
  hook3: B(6),
  open1: 104,
  curtain: B(40),
  openDev: 645,
  retract: B(56),
  editPress: 870,
  editOn: 888,
  dragStart: 892,
  drop: 920,
  hideAt: 942,
  editOff: 966,
  collapse: B(66),
  alt: B(76),
};

const TABS: { tab: TabId; at: number }[] = [
  { tab: "player", at: B(7) },
  { tab: "quick", at: B(12) },
  { tab: "shelf", at: B(18) },
  { tab: "clip", at: B(26) },
  { tab: "timer", at: B(31) },
  { tab: "notes", at: B(36) },
  { tab: "claude", at: T.openDev },
];

/** Verbes géants : [clé, début, fin]. */
const VERBS: { key: "player" | "quick" | "shelf" | "clip" | "timer" | "notes" | "asks" | "answer" | "fromNotch" | "yours"; from: number; to: number; dark?: boolean }[] = [
  { key: "player", from: B(8), to: B(12) },
  { key: "quick", from: B(12), to: B(18) },
  { key: "shelf", from: B(18), to: B(26) },
  { key: "clip", from: B(26), to: B(31) },
  { key: "timer", from: B(31), to: B(36) },
  { key: "notes", from: B(36), to: B(40) },
  { key: "asks", from: B(44), to: B(48), dark: true },
  { key: "answer", from: B(48), to: B(52), dark: true },
  { key: "fromNotch", from: B(52), to: B(56), dark: true },
  { key: "yours", from: B(58), to: B(66) },
];

// Ressorts réglés à la main
const SNAP = swiftSpring(0.3, 0.72); // onglet qui change, tuile qui s'allume
const SOFT = swiftSpring(0.5, 0.82); // carte qui se déplie
const open = (f: number, at: number) => sp(f, at, NOTCH_SPRING);

// ─────────────────────────────── Géométrie de la notch ───────────────────────────────
const W_PLAIN = 197;
const W_EARS = 257;
const W_OPEN = 644;

// ─────────────────────────────── Contenu des onglets ───────────────────────────────

type TabOut = { node: React.ReactNode; h: number; accessory?: React.ReactNode };

const ShelfAccessory: React.FC<{ n: number }> = ({ n }) => {
  const lang = useLang();
  return (
    <div style={{ display: "flex", alignItems: "center", gap: 8, color: C.secondary, fontSize: 12.5, fontWeight: 600 }}>
      <span>{n} {lang === "fr" ? "éléments" : "items"}</span>
      <Radio size={15} />
      <Trash size={15} />
    </div>
  );
};

const CAFFEINE_AT = 222;

function claudeParts(f: number) {
  // Dépliage de la demande, puis conversation.
  const rep = clamp01(sp(f, 696, SOFT) - sp(f, 742, SOFT));
  const allowed = f >= 742;
  const chatP = clamp01(sp(f, 770, SOFT));
  const sent = clamp01(sp(f, 832, SOFT));
  const reset = clamp01(sp(f, T.retract, SOFT));
  return { rep, allowed, chatP: chatP * (1 - reset), sent: sent * (1 - reset), reset };
}

function claudeHeight(f: number) {
  const { rep, chatP, sent } = claudeParts(f);
  // api 57 + mon-app 77,5 + dernier bloc (site 57 → conversation 160) + écarts
  return 207.5 + 109 * rep + 103 * chatP + 46 * sent;
}

function tabOut(tab: TabId, lf: number, f: number, lang: Lang): TabOut {
  const t = (en: string, fr: string) => (lang === "fr" ? fr : en);
  switch (tab) {
    case "player":
      return { h: 150, node: <PlayerTab progress={0.33 + lf / 30 / 230} /> };
    case "quick": {
      const cafOn = ramp(f, CAFFEINE_AT, CAFFEINE_AT + 6, 0, 1);
      return { h: 200, node: <QuickTab s={{ caf: cafOn }} hours={1} /> };
    }
    case "shelf": {
      const n = f >= 336 ? 6 : 5;
      const glow = ramp(f, 318, 326, 0, 1) * (1 - ramp(f, 336, 342, 0, 1));
      const landed = ramp(f, 336, 350, 0, 1, outExpo);
      return {
        h: 184,
        accessory: <ShelfAccessory n={n} />,
        node: <ShelfTab count={n} dropGlow={glow} progressOf={(i) => (i < 5 ? ramp(lf, 4 + i * 2, 16 + i * 2, 0, 1) : landed)} />,
      };
    }
    case "clip": {
      const copied = f >= 428 && f < 452 ? 2 : -1;
      return {
        h: 246,
        accessory: <PauseCircle size={15} color={C.secondary} />,
        node: <ClipboardTab rows={5} progressOf={(i) => ramp(lf, 3 + i * 3, 16 + i * 3, 0, 1)} hoverRow={f >= 410 && f < 428 ? 2 : -1} copiedRow={copied} />,
      };
    }
    case "timer": {
      const rem = 18 * 60 + 12 - lf / 30;
      return { h: 170, node: <TimerTab remaining={rem} /> };
    }
    case "notes": {
      const words = [0, 6, 13, 19, 27, 33, 41, 47, 54];
      const steps = lf < 8 ? 0 : words.filter((w) => lf >= 8 + w).length;
      const typed = steps / words.length;
      return { h: 214, node: <NotesTab typed={Math.min(1, typed)} selected={3} /> };
    }
    case "claude": {
      const { rep, allowed, chatP, sent, reset } = claudeParts(f);
      const monTop = 65 + 109 * rep;
      const lastTop = monTop + 85.5;
      const pulse = 0.6 + 0.4 * Math.sin(f / 4.5);
      const apiKind = allowed ? "running" : "attention";
      const hover = f >= 756 && f < 832;
      const chatBtn = ramp(f, 756, 764, 0, 1) * (1 - ramp(f, 826, 834, 0, 1)) * (1 - reset);
      const typedFrac = (() => {
        const marks = [782, 790, 797, 803, 812];
        const cum = [4, 8, 11, 15, 23];
        const k = marks.filter((m) => f >= m).length;
        if (k === 0) return 0;
        const prev = k === 1 ? 0 : cum[k - 2];
        const cur = cum[k - 1];
        const t = clamp01((f - marks[k - 1]) / 3);
        return (prev + (cur - prev) * t) / 23;
      })();
      return {
        h: claudeHeight(f),
        node: (
          <div style={{ position: "absolute", inset: 0 }}>
            <div style={{ position: "absolute", left: 0, top: 0 }}>
              <SessionCard
                kind={apiKind}
                name="api"
                time={allowed ? "1 s" : "2 s"}
                status={allowed ? "Terminal" : t("Needs your permission", "Attend ta permission")}
                detail={allowed ? "rm -rf build && swift build" : "Terminal · rm -rf build"}
                outline={allowed ? 0 : pulse * 0.35 + 0.65}
                frame={f}
              />
            </div>
            {rep > 0.01 && (
              <div style={{ position: "absolute", left: 0, top: 65, height: 101 * rep, overflow: "hidden", opacity: clamp01(rep * 1.4) }}>
                <PermissionReply command="rm -rf build && swift build -c release" reason={t("Clean rebuild", "Rebuild propre")} pressAllow={f >= 736 && f < 744 ? 1 : 0} />
              </div>
            )}
            <div style={{ position: "absolute", left: 0, top: monTop }}>
              <SessionCard
                kind="running"
                name="mon-app"
                agents={t("2 agents", "2 agents")}
                time="2 s"
                status="Terminal"
                detail="npm test -- --watch=false"
                task={{ done: 1, total: 3, title: t("Fix the parser", "Correction du parseur") }}
                chatButton={hover ? chatBtn : 0}
                frame={f}
              />
            </div>
            <div style={{ position: "absolute", left: 0, top: lastTop, opacity: 1 - clamp01(chatP * 3) }}>
              <SessionCard kind="done" name="site" time={t("just now", "à l'instant")} status={t("Done", "Terminé")} detail={t("README updated: installation section rewritten.", "README à jour : section installation réécrite.")} detailMono={false} />
            </div>
            {chatP > 0.01 && (
              <div style={{ position: "absolute", left: 0, top: lastTop, height: (160 + 46 * sent) * chatP, overflow: "hidden", opacity: clamp01(chatP * 1.5) }}>
                <Conversation
                  said={t("README updated: installation section rewritten.", "README à jour : section installation réécrite.")}
                  you={t("Also add an FAQ section", "Ajoute aussi une section FAQ")}
                  typed={typedFrac}
                  sent={sent > 0.2}
                  showYou={sent > 0.2}
                  frame={f}
                />
              </div>
            )}
          </div>
        ),
      };
    }
  }
}

// ─────────────────────────────── Composition ───────────────────────────────

export type PromoProps = {
  format: Format;
  lang: Lang;
  music?: { file: string; startFromSeconds?: number; playbackRate?: number } | null;
};

export const Promo: React.FC<PromoProps> = ({ format, lang, music }) => {
  useFontsReady();
  return (
    <LangProvider lang={lang}>
      <Scene format={format} lang={lang} />
      {music ? <Audio src={staticFile(music.file)} startFrom={Math.round((music.startFromSeconds ?? 0) * 30)} playbackRate={music.playbackRate ?? 1} /> : null}
    </LangProvider>
  );
};

const Scene: React.FC<{ format: Format; lang: Lang }> = ({ format, lang }) => {
  const f = useCurrentFrame();
  const L = layoutFor(format);
  const wide = format === "wide";

  // ── mode de la notch : repliée simple, oreilles, déployée ──
  const oRaw = open(f, T.open1) - open(f, T.curtain) + open(f, T.openDev) - open(f, T.collapse);
  const ears = clamp01(open(f, T.curtain) - open(f, T.openDev) + open(f, T.collapse));
  const thumpK = f >= T.thump ? Math.exp(-(f - T.thump) / 5) * Math.sin((f - T.thump) * 0.95) : 0;

  // ── onglet affiché, transition ──
  let ti = -1;
  TABS.forEach((x, i) => {
    if (f >= x.at) ti = i;
  });
  const cur = TABS[Math.max(0, ti)];
  const prev = TABS[Math.max(0, ti - 1)] ?? cur;
  const p = ti <= 0 ? 1 : sp(f, cur.at, SNAP);
  const curOut = tabOut(cur.tab, f - cur.at, f, lang);
  const prevOut = p < 0.999 ? tabOut(prev.tab, f - prev.at, f, lang) : curOut;
  const contentH = lerp(prevOut.h, curOut.h, p);
  const panelH = panelHeight(contentH);

  // ── mode édition des onglets ──
  const editing = f >= T.editOn && f < T.editOff;
  const badge = ramp(f, T.editOn, T.editOn + 8, 0, 1, outExpo) * (editing ? 1 : 0);
  const orderAfterDrag: TabId[] = ["claude", "notes", "player", "quick", "shelf", "clip", "timer"];
  const orderAfterHide: TabId[] = ["claude", "notes", "player", "quick", "shelf", "timer"];
  const dragMove = ramp(f, T.dragStart, T.drop - 4, 0, 1, outQuart);
  const shiftP = clamp01(sp(f, T.dragStart + 14, SNAP));
  const hideP = clamp01(sp(f, T.hideAt + 4, SNAP));
  const clipFade = 1 - ramp(f, T.hideAt, T.hideAt + 6, 0, 1);
  const xs: Partial<Record<TabId, number>> = {};
  const ops: Partial<Record<TabId, number>> = {};
  DEFAULT_ORDER.forEach((id, i) => {
    let x = i * 29;
    if (id === "notes") x = lerp(6 * 29, 1 * 29, dragMove);
    else x = lerp(x, orderAfterDrag.indexOf(id) * 29, shiftP);
    if (f >= T.hideAt) {
      const target = id === "clip" ? x : orderAfterHide.indexOf(id) * 29;
      x = lerp(x, target, hideP);
    }
    xs[id] = x;
    if (id === "clip") ops[id] = clipFade;
  });
  const barOrder: TabId[] = DEFAULT_ORDER;
  const barCount = 7 - hideP;
  const lifted = f >= T.dragStart && f < T.drop + 6 ? ("notes" as TabId) : null;

  // titre : fondu croisé pendant le changement d'onglet
  const titleOp = ti <= 0 || p > 0.98 ? 1 : p < 0.3 ? 1 - p / 0.3 : clamp01((p - 0.3) / 0.4);
  const titleTab = p < 0.3 ? prev.tab : cur.tab;
  const activeX = ti <= 0 ? undefined : lerp(xs[prev.tab] ?? 0, xs[cur.tab] ?? 0, p);

  // ── rideau (la notch avale le cadre) ──
  const gIn = clamp01(sp(f, T.curtain, swiftSpring(0.34, 0.9)));
  const gOut = clamp01(sp(f, T.retract, swiftSpring(0.34, 0.9)));
  const g = clamp01(gIn - gOut);
  // Échelle du panneau : plus petite dans la scène sombre, où le panneau Claude est plus haut.
  const S = lerp(L.S, L.S * L.devRatio, g);
  const Sdev = L.S * L.devRatio;
  const darkAmt = ramp(g, 0.7, 0.98, 0, 1, (x) => x);
  const bg = C.paper;
  const ink = hexMix("#0B0B0B", "#EFEAE0", darkAmt);
  const curtainColor = hexMix("#000000", "#181818", ramp(f, T.curtain + 26, T.curtain + 42, 0, 1) * (1 - ramp(f, T.retract - 2, T.retract + 6, 0, 1)));

  // rectangle du panneau déplié (px), au moment du rideau et pendant l'édition
  const panelLeftPx = L.cx - (W_OPEN * S) / 2;
  const rectH = panelH * S;
  const curtainRect = {
    left: lerp(panelLeftPx, 0, g),
    top: 0,
    width: lerp(W_OPEN * S, L.w, g),
    height: lerp(rectH, L.h, g),
    radius: lerp(24 * S, 0, g),
  };

  // ── géométrie du corps de la notch (pt) ──
  const earsW = lerp(W_PLAIN, W_EARS, ears);
  const wPt = Math.max(150, lerp(earsW, W_OPEN, clamp01(oRaw)));
  const oc = Math.max(0, oRaw);
  const hPt = lerp(NOTCH_H * (1 + 0.28 * thumpK), panelH, oc);
  const topR = lerp(6, 12, clamp01(oc));
  const botR = lerp(lerp(9, 12, ears), 24, clamp01(oc));
  const bodyLeftPx = L.cx - (wPt * S) / 2;
  const contentFade = f < T.curtain ? ramp(f, T.open1 + 4, T.open1 + 14, 0, 1) : f < T.openDev ? 0 : f < T.collapse ? ramp(f, T.openDev + 4, T.openDev + 14, 0, 1) : 0;
  const openContentFade = f >= T.curtain && f < T.curtain + 6 ? 1 - ramp(f, T.curtain, T.curtain + 6, 0, 1) : contentFade;
  const earsFade = ears > 0.01 ? clamp01(ramp(f, f < T.openDev ? T.curtain + 6 : T.collapse + 6, f < T.openDev ? T.curtain + 14 : T.collapse + 14, 0, 1) * (1 - clamp01(oc * 2))) : 0;

  // ── oreilles : trois états ──
  const earsPhase = f < T.openDev ? "dev" : f < T.alt ? "done" : "alt";
  const altP = ramp(f, T.alt, T.alt + 10, 0, 1, outExpo);
  const pulse = 0.65 + 0.35 * Math.sin(f / 3.2);
  const earLeft =
    earsPhase === "dev" ? (
      <div style={{ opacity: 0.45 + 0.55 * pulse, transform: `scale(${0.9 + 0.16 * pulse})` }}>
        <Hand size={15} color={C.amber} />
      </div>
    ) : (
      <div style={{ position: "relative", width: 20, height: 20 }}>
        <div style={{ position: "absolute", inset: 0, display: "flex", alignItems: "center", opacity: 1 - altP, transform: `translateY(${-altP * 8}px)` }}>
          <Check size={15} color={C.green} />
        </div>
        <div style={{ position: "absolute", left: 0, top: 0, width: 19, height: 19, borderRadius: 5, background: "#DD2DF5", opacity: altP, transform: `translateY(${(1 - altP) * 8}px)`, display: "flex", alignItems: "center", justifyContent: "center" }}>
          <div style={{ width: 9, height: 9, borderRadius: 5, background: "rgba(255,255,255,0.4)" }} />
        </div>
      </div>
    );
  const earRight =
    earsPhase === "dev" ? (
      <SessionCount a={2} b={2} />
    ) : (
      <div style={{ position: "relative", width: 26, height: 20, display: "flex", justifyContent: "flex-end" }}>
        <div style={{ position: "absolute", right: 0, top: 1, opacity: 1 - altP, transform: `translateY(${-altP * 8}px)` }}>
          <SessionCount a={1} b={0} />
        </div>
        <div style={{ position: "absolute", right: 0, top: 4, opacity: altP, transform: `translateY(${(1 - altP) * 8}px)`, display: "flex", gap: 2, alignItems: "center", height: 12 }}>
          {[0, 1, 2, 3].map((i) => (
            <div key={i} style={{ width: 2, borderRadius: 1, background: C.accent, height: 3 + 8 * Math.abs(Math.sin(f / 5 + i * 1.3)) }} />
          ))}
        </div>
      </div>
    );

  // ── pointeur (px) ──
  const pxS = (s: number, xpt: number, ypt: number) => ({ x: L.cx - (W_OPEN * s) / 2 + xpt * s, y: ypt * s });
  const px = (xpt: number, ypt: number) => pxS(L.S, xpt, ypt);
  const pd = (xpt: number, ypt: number) => pxS(Sdev, xpt, ypt);
  const tabC = (i: number) => px(39.5 + 29 * i, 44);
  const kp = (fr: number, p2: { x: number; y: number }, d?: number): PKey => ({ f: fr, x: p2.x, y: p2.y, d });
  const notchTop = { x: L.cx, y: 26 * L.S };
  const off1 = { x: wide ? 420 : 180, y: L.h + 40 };
  const keys: PKey[] = [
    kp(86, off1),
    kp(104, notchTop, 16),
    kp(124, tabC(1), 16),
    kp(174, tabC(2), 10),
    kp(206, px(322, 140), 16),
    kp(264, tabC(3), 14),
    kp(290, { x: wide ? 520 : 300, y: L.h - 130 }, 12),
    kp(334, px(322, 150), 36),
    kp(384, tabC(4), 20),
    kp(408, px(322, 202), 14),
    kp(459, tabC(5), 16),
    kp(534, tabC(6), 12),
    // acte 4
    kp(622, off1, 1),
    kp(642, { x: L.cx, y: 26 * Sdev }, 18),
    kp(690, pd(322, 94.5), 20),
    kp(730, pd(584, 209.5), 14),
    kp(756, pd(322, 169), 12),
    kp(764, pd(559, 149), 8),
    kp(826, pd(579.5, 285), 22),
    // acte 5
    kp(862, tabC(6), 20),
    kp(916, tabC(1), 22),
    kp(938, px(174, 35), 14),
    kp(960, px(597, 44), 14),
  ];
  const presses = [222, 336, 428, 738, 768, 830, 942, 964];
  const holds: [number, number][] = [[T.editPress, T.editOn + 4], [T.dragStart - 2, T.drop]];
  const visible: [number, number][] = [
    [86, T.curtain - 2],
    [622, T.retract + 4],
    [850, 984],
  ];

  // fichier traîné sur l'étagère
  const dragFileP = ramp(f, 292, 296, 0, 1) * (1 - ramp(f, 336, 340, 0, 1));

  // ── typographie ──
  const hookSize = format === "wide" ? L.hook.size : fit("in the screen.", L.maxTextW, L.hook.size);
  const hookLine = hookSize * 0.9;
  const hookLeft = L.margin;
  const hook1 = COPY.hook1.map((p2) => tx(lang, p2));
  const hook2 = COPY.hook2.map((p2) => tx(lang, p2));
  const hook3 = tx(lang, COPY.hook3);
  const hookSize1 = Math.min(hookSize, fit(hook1.reduce((a, b) => (b.length > a.length ? b : a), ""), L.maxTextW, hookSize));
  const hookSize2 = Math.min(hookSize, fit(hook2.reduce((a, b) => (b.length > a.length ? b : a), ""), L.maxTextW, hookSize));
  const hookSize3 = Math.min(hookSize, fit(hook3, L.maxTextW, hookSize));

  const verbs = VERBS.map((v) => {
    const [vp, cp] = COPY[v.key];
    const verb = tx(lang, vp);
    const caption = tx(lang, cp);
    const size = fit(verb, L.maxTextW, L.verb.size);
    return { ...v, verb, caption, size };
  });

  const title = tx(lang, COPY.title);
  const closing = (() => {
    const base = 300;
    return wide ? { size: fit(title, L.maxTextW, base), top: 150 } : { size: base, top: 600 };
  })();

  const chipTexts = COPY.chips.map((c) => tx(lang, c));
  const chipSize = wide ? 28 : 31;
  const chipW = (txt: string) => txt.length * chipSize * 0.62 + chipSize * 1.7 + 8;
  const chipPositions = (() => {
    if (wide) {
      let x = L.margin;
      return chipTexts.map((c) => {
        const pos = { left: x, top: 605 };
        x += chipW(c) + 22;
        return pos;
      });
    }
    return chipTexts.map((_, i) => ({ left: L.margin, top: 1330 + i * 104 }));
  })();

  const textColor = ink;
  const subColor = hexMix("#5b5750", "#a8a398", darkAmt);

  return (
    <AbsoluteFill style={{ background: bg, overflow: "hidden" }}>
      {/* rideau : la notch qui grossit */}
      {g > 0.001 && (
        <div
          style={{
            position: "absolute",
            left: curtainRect.left,
            top: curtainRect.top,
            width: curtainRect.width,
            height: curtainRect.height,
            background: curtainColor,
            borderRadius: `0 0 ${curtainRect.radius}px ${curtainRect.radius}px`,
          }}
        />
      )}

      {/* étiquette produit */}
      <MonoLine text={COPY.tag} size={wide ? 22 : 24} frame={f} inAt={B(8)} outAt={T.collapse - 4} color={subColor} left={L.tag.x} top={L.tag.y} weight={500} />

      {/* accroche */}
      {hook1.map((line, i) => (
        <MaskLine key={`h1-${i}`} text={line} size={hookSize1} frame={f} inAt={B(i)} outAt={T.hook2 + i} color={ink} left={hookLeft} top={L.hook.top + i * hookLine * 0.97} />
      ))}
      {hook2.map((line, i) => (
        <MaskLine key={`h2-${i}`} text={line} size={hookSize2} frame={f} inAt={T.hook2 + 4 + i * 3} outAt={T.hook3 + i} color={ink} left={hookLeft} top={L.hook.top + i * hookLine * 0.97} />
      ))}
      <MaskLine text={hook3} size={hookSize3} frame={f} inAt={T.hook3} outAt={106} color={C.accent} left={hookLeft} top={L.hook.top} />

      {/* verbes */}
      {verbs.map((v) => {
        const cap = wide ? L.caption.size : L.caption.size;
        return (
          <React.Fragment key={v.key}>
            <MaskLine text={v.verb} size={v.size} frame={f} inAt={v.from} outAt={v.to - 7} color={textColor} left={L.margin} top={L.verb.bottom - v.size} />
            <MonoLine text={v.caption} size={fitMono(v.caption, L.maxTextW - 12, cap)} frame={f} inAt={v.from + 4} outAt={v.to - 6} color={subColor} left={L.margin + 6} top={L.caption.y} />
          </React.Fragment>
        );
      })}
      <MonoLine text={tx(lang, COPY.devIntro)} size={fitMono(tx(lang, COPY.devIntro), L.maxTextW, wide ? 46 : 40)} frame={f} inAt={B(42)} outAt={B(44) - 7} color={subColor} left={L.margin} top={L.verb.bottom - (wide ? 100 : 90)} />

      {/* panneau / notch */}
      <div style={{ position: "absolute", left: bodyLeftPx, top: 0, transform: `scale(${S})`, transformOrigin: "0 0" }}>
        <NotchBody w={wPt} h={hPt} top={topR} bottom={botR} shadow={oc > 0.2 && darkAmt < 0.5}>
          {earsFade > 0.01 && (
            <>
              <div style={{ position: "absolute", left: 20, top: 0, height: 32, display: "flex", alignItems: "center", opacity: earsFade, fontFamily: FONT.ui }}>{earLeft}</div>
              <div style={{ position: "absolute", right: 20, top: 0, height: 32, display: "flex", alignItems: "center", opacity: earsFade, fontFamily: FONT.ui }}>{earRight}</div>
            </>
          )}
          {oc > 0.02 && (
            <div style={{ position: "absolute", left: (wPt - W_OPEN) / 2, top: 0, width: W_OPEN, height: hPt, opacity: openContentFade }}>
              <PanelInner
                tab={cur.tab}
                titleTab={titleTab}
                order={barOrder}
                frame={f}
                editing={editing}
                claudeState={cur.tab === "claude" && !claudeParts(f).allowed ? "attention" : "idle"}
                contentH={contentH}
                titleOpacity={titleOp}
                accessory={p > 0.5 ? curOut.accessory : prevOut.accessory}
                contentOpacity={editing ? 0.35 : 1}
                okPress={f >= 962 && f < 968 ? 1 : 0}
                tabBarProps={{ xs, opacities: ops, lifted, activeX, count: barCount, badge }}
              >
                {p < 0.999 && <div style={{ position: "absolute", inset: 0, opacity: 1 - clamp01(p * 4) }}>{prevOut.node}</div>}
                <div style={{ position: "absolute", inset: 0, opacity: p >= 0.999 ? 1 : clamp01((p - 0.2) * 3) }}>{curOut.node}</div>
              </PanelInner>
            </div>
          )}
        </NotchBody>
      </div>

      {/* fichier traîné */}
      {dragFileP > 0 && <DraggedFile f={f} keys={keys} p={dragFileP} S={L.S} />}

      <Pointer frame={f} keys={keys} presses={presses} holds={holds} visible={visible} size={wide ? 30 : 34} />

      {/* final */}
      <Closing f={f} L={L} lang={lang} color={textColor} sub={subColor} closing={closing} chipPositions={chipPositions} chipSize={chipSize} />
    </AbsoluteFill>
  );
};

const DraggedFile: React.FC<{ f: number; keys: PKey[]; p: number; S: number }> = ({ f, keys, p, S }) => {
  // Même trajet que le pointeur ; le fichier est tenu juste sous la pointe.
  const { x, y } = pointerAt(f, keys);
  const item = SHELF_ITEMS[5];
  return (
    <div style={{ position: "absolute", left: x - 8, top: y - 6, opacity: p, transform: `scale(${S * 1.05}) rotate(-6deg)`, transformOrigin: "0 0", filter: "drop-shadow(0 8px 10px rgba(0,0,0,0.3))" }}>
      <FileGlyph kind={item.kind} />
    </div>
  );
};

const Closing: React.FC<{
  f: number;
  L: Layout;
  lang: Lang;
  color: string;
  sub: string;
  closing: { size: number; top: number };
  chipPositions: { left: number; top: number }[];
  chipSize: number;
}> = ({ f, L, lang, color, sub, closing, chipPositions, chipSize }) => {
  const wide = L.w > L.h;
  const base = B(66);
  const titleLines = wide ? [tx(lang, COPY.title)] : COPY.titleTall.map((p2) => tx(lang, p2));
  const chipTexts = COPY.chips.map((c) => tx(lang, c));
  return (
    <>
      {titleLines.map((line, i) => (
        <MaskLine key={i} text={line} size={closing.size} frame={f} inAt={base + 15 + i * 3} color={color} left={L.margin} top={closing.top + i * closing.size * 0.92} inDur={12} />
      ))}
      <MonoLine
        text={tx(lang, COPY.tagline)}
        size={fitMono(tx(lang, COPY.tagline), L.maxTextW, 36)}
        frame={f}
        inAt={B(69)}
        color={C.accent}
        left={L.margin + 6}
        top={wide ? closing.top + closing.size * 1.08 + 8 : closing.top + closing.size * 1.84 + 28}
        weight={700}
      />
      {chipTexts.map((txt, i) => (
        <Chip key={i} text={txt} frame={f} at={B(70) + i * 15} left={chipPositions[i].left} top={chipPositions[i].top} color={color} size={chipSize} />
      ))}
      <MonoLine text={COPY.link} size={fitMono(COPY.link, L.maxTextW, wide ? 46 : 40)} frame={f} inAt={B(74)} color={color} left={L.margin} top={wide ? 790 : 1720} weight={700} />
      <MonoLine text={tx(lang, COPY.free)} size={fitMono(tx(lang, COPY.free), L.maxTextW, wide ? 30 : 29)} frame={f} inAt={B(74) + 4} color={sub} left={L.margin + 4} top={wide ? 860 : 1782} />
      {COPY.legal.map((line, i) => (
        <MonoLine key={i} text={tx(lang, line)} size={fitMono(tx(lang, line), L.maxTextW, wide ? 18 : 19)} frame={f} inAt={B(75) + i * 2} color={sub} left={L.margin + 4} top={(wide ? 1004 : 1836) + i * (wide ? 28 : 30)} />
      ))}
    </>
  );
};

