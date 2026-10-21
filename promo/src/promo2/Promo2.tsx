import React from "react";
import { AbsoluteFill, useCurrentFrame } from "remotion";
import { useFontsReady } from "../fonts";
import { LangProvider, Lang, useLang } from "../i18n";
import { C, FONT } from "../theme";
import { BLUR_EASE, CURSOR_EASE, FPS2, GROW, SHRINK, SNAP, clamp01, fr, lerp, outExpo, ramp2, sp2 } from "../motion2";
import { DEFAULT_ORDER, NotchBody, NOTCH_H, PanelInner, TabId, panelHeight } from "../ui/notch";
import { ClipboardTab, FileGlyph, NotesTab, PlayerTab, QuickTab, SHELF_ITEMS, ShelfTab, TimerTab } from "../ui/tabs";
import { PermissionReply, SessionCard, SessionCount } from "../ui/claude";
import { Check, Cursor, Hand, PauseCircle, Radio, Spark, Trash } from "../ui/icons";
import { COPY, tx } from "../promo/copy";
import { Format2, Layout2, layout2 } from "./layout2";

// ─────────────────────────────── Calendrier (secondes) ───────────────────────────────
// Un temps fort tous les 0,9 à 2,4 s ; la transformation dure 0,3 à 0,45 s, puis l'objet tient 0,3 à 0,6 s.
// Chaque réaction suit l'arrivée du curseur de 0,10 s (arrêt, puis clic).
const T = {
  open: 0.68,
  pause: 1.5,
  quick: 2.25,
  caf: 3.05,
  shelf: 3.9,
  pick: 4.5,
  drop: 5.2,
  clip: 6.05,
  copy: 6.85,
  timer: 7.6,
  notes: 8.4,
  typeFrom: 8.7,
  nudge: 9.45,
  claude: 10.15,
  ask: 10.55,
  allow: 11.25,
  exit: 12.1,
  collapse: 11.75,
  pill: 12.65,
  pillText: 13.0,
  link: 13.5,
  /** Fin de la vidéo (pastille finale tenue) ; la boucle du GIF continue jusqu'à `loopEnd`. */
  ret: 15.8,
  loopEnd: 16.5,
};
export const CTA_END = fr(T.ret);
export const DURATION2 = fr(T.loopEnd);

const TABS: { tab: TabId; at: number }[] = [
  { tab: "player", at: T.open },
  { tab: "quick", at: T.quick },
  { tab: "shelf", at: T.shelf },
  { tab: "clip", at: T.clip },
  { tab: "timer", at: T.timer },
  { tab: "notes", at: T.notes },
  { tab: "claude", at: T.claude },
];
const slot = (id: TabId) => DEFAULT_ORDER.indexOf(id) * 29;

// Géométrie de la notch (pt)
const W_PLAIN = 197;
const W_EARS = 257;
const W_OPEN = 644;

type TabOut = { node: React.ReactNode; h: number; accessory?: React.ReactNode };

const ShelfAccessory: React.FC<{ n: number }> = ({ n }) => {
  const lang = useLang();
  return (
    <div style={{ display: "flex", alignItems: "center", gap: 8, color: C.secondary, fontSize: 12.5, fontWeight: 600 }}>
      <span>
        {n} {lang === "fr" ? "éléments" : "items"}
      </span>
      <Radio size={15} />
      <Trash size={15} />
    </div>
  );
};

// ─────────────────────────────── Composition ───────────────────────────────

export type Promo2Props = { format: Format2; lang: Lang };

export const Promo2: React.FC<Promo2Props> = ({ format, lang }) => {
  useFontsReady();
  return (
    <LangProvider lang={lang}>
      <Scene2 format={format} lang={lang} />
    </LangProvider>
  );
};

const Scene2: React.FC<{ format: Format2; lang: Lang }> = ({ format, lang }) => {
  const f = useCurrentFrame();
  const t = f / FPS2;
  const L = layout2(format);
  const S = L.S;
  const tr = (en: string, frn: string) => (lang === "fr" ? frn : en);
  const R = (a: number, b: number, easing = outExpo) => ramp2(f, a, b, 0, 1, easing);

  // ── Claude : la demande se déplie, puis se replie quand on autorise ──
  const askP = clamp01(sp2(f, T.ask, GROW) - sp2(f, T.allow + 0.02, SHRINK));
  const allowed = t >= T.allow;
  const nudged = t >= T.nudge && !allowed;
  const claudeH = 207.5 + 109 * askP;

  const tabOut = (tab: TabId, at: number): TabOut => {
    switch (tab) {
      case "player":
        return { h: 150, node: <PlayerTab progress={0.33 + Math.min(t, T.pause) / 230} playing={t < T.pause} /> };
      case "quick":
        return { h: 200, node: <QuickTab s={{ caf: sp2(f, T.caf, SNAP) }} hours={1} /> };
      case "shelf": {
        const n = t >= T.drop ? 6 : 5;
        const glow = R(T.drop - 0.45, T.drop - 0.3) * (1 - R(T.drop, T.drop + 0.1));
        const landed = R(T.drop, T.drop + 0.3);
        return {
          h: 184,
          accessory: <ShelfAccessory n={n} />,
          node: <ShelfTab count={n} dropGlow={glow} progressOf={(i) => (i < 5 ? R(at + 0.08 + i * 0.035, at + 0.3 + i * 0.035) : landed)} />,
        };
      }
      case "clip":
        return {
          h: 246,
          accessory: <PauseCircle size={15} color={C.secondary} />,
          node: (
            <ClipboardTab
              rows={5}
              progressOf={(i) => R(at + 0.06 + i * 0.05, at + 0.28 + i * 0.05)}
              hoverRow={t >= T.copy - 0.4 && t < T.copy ? 2 : -1}
              copiedRow={t >= T.copy && t < T.copy + 0.9 ? 2 : -1}
            />
          ),
        };
      case "timer": {
        // La bague et le compte à rebours se mettent en place, puis le temps s'écoule normalement.
        const wind = outExpo(clamp01((t - at - 0.15) / 0.6));
        const remaining = lerp(25 * 60, 18 * 60 + 12, wind) - Math.max(0, t - at - 0.75);
        return { h: 170, node: <TimerTab remaining={remaining} /> };
      }
      case "notes": {
        const marks = [0, 0.1, 0.2, 0.3, 0.45, 0.55, 0.65, 0.78, 0.9];
        const steps = marks.filter((m) => t >= T.typeFrom + m).length;
        return { h: 214, node: <NotesTab typed={steps / marks.length} selected={3} /> };
      }
      case "claude": {
        const monTop = 65 + 109 * askP;
        const lastTop = monTop + 85.5;
        const pulse = 0.6 + 0.4 * Math.sin(f / 9);
        return {
          h: claudeH,
          node: (
            <div style={{ position: "absolute", inset: 0 }}>
              <div style={{ position: "absolute", left: 0, top: 0 }}>
                <SessionCard
                  kind={allowed ? "running" : "attention"}
                  name="api"
                  time={allowed ? "1 s" : "2 s"}
                  status={allowed ? "Terminal" : tr("Needs your permission", "Attend ta permission")}
                  detail={allowed ? "rm -rf build && swift build" : "Terminal · rm -rf build"}
                  outline={allowed ? 0 : pulse * 0.35 + 0.65}
                  frame={f / 2}
                />
              </div>
              {askP > 0.01 && (
                <div style={{ position: "absolute", left: 0, top: 65, height: 101 * askP, overflow: "hidden", opacity: clamp01(askP * 1.4) }}>
                  <PermissionReply command="rm -rf build && swift build -c release" reason={tr("Clean rebuild", "Rebuild propre")} pressAllow={t >= T.allow && t < T.allow + 0.1 ? 1 : 0} />
                </div>
              )}
              <div style={{ position: "absolute", left: 0, top: monTop }}>
                <SessionCard
                  kind="running"
                  name="mon-app"
                  agents={tr("2 agents", "2 agents")}
                  time="2 s"
                  status="Terminal"
                  detail="npm test -- --watch=false"
                  task={{ done: 1, total: 3, title: tr("Fix the parser", "Correction du parseur") }}
                  frame={f / 2}
                />
              </div>
              <div style={{ position: "absolute", left: 0, top: lastTop }}>
                <SessionCard kind="done" name="site" time={tr("just now", "à l'instant")} status={tr("Done", "Terminé")} detail={tr("README updated: installation section rewritten.", "README à jour : section installation réécrite.")} detailMono={false} />
              </div>
            </div>
          ),
        };
      }
    }
  };

  // ── Onglet affiché et transition ──
  let ti = 0;
  TABS.forEach((x, i) => {
    if (t >= x.at) ti = i;
  });
  const cur = TABS[ti];
  const prev = TABS[Math.max(0, ti - 1)];
  const switching = ti > 0 && t < cur.at + 0.3;
  const curOut = tabOut(cur.tab, cur.at);
  const prevOut = switching ? tabOut(prev.tab, prev.at) : curOut;
  // Agrandir : ressort qui dépasse ; réduire : ressort amorti (REFERENCE.md § 7.1).
  const p = ti === 0 ? 1 : sp2(f, cur.at, curOut.h >= prevOut.h ? GROW : SHRINK);
  const contentH = lerp(prevOut.h, curOut.h, p);
  const panelH = panelHeight(contentH);

  // Sélecteur élastique : le bord avant part en premier, le bord arrière suit.
  const a = slot(prev.tab);
  const b = slot(cur.tab);
  const lead = ti === 0 ? b : a + (b - a) * sp2(f, cur.at, { mass: 1, stiffness: 520, damping: 2 * 0.75 * Math.sqrt(520) });
  const trail = ti === 0 ? b : a + (b - a) * sp2(f, cur.at + 0.04, { mass: 1, stiffness: 300, damping: 2 * 0.95 * Math.sqrt(300) });
  const left = b >= a ? trail : lead;
  const right = (b >= a ? lead : trail) + 27;
  const capsule = { x: left, w: right - left };

  // Contenu : l'ancien sort en 80 ms avec du flou, le nouveau entre en flou → net.
  const outA = 1 - R(cur.at, cur.at + 0.1, (v) => v);
  // Ouverture : la barre d'onglets arrive d'abord, le contenu ensuite (comme la pochette de la référence, qui suit la forme).
  const inA = ti === 0 ? R(T.open + 0.12, T.open + 0.26, BLUR_EASE) : R(cur.at + 0.07, cur.at + 0.2, BLUR_EASE);
  const titleOp = ti === 0 || p > 0.98 ? 1 : outA > 0.02 ? outA : inA;
  const titleTab = outA > 0.02 && ti > 0 ? prev.tab : cur.tab;

  // ── Mode de la notch : repliée, oreilles, déployée, puis pastille ──
  const oRaw = sp2(f, T.open, GROW) - sp2(f, T.collapse, SHRINK);
  const earsAmt = clamp01(sp2(f, T.collapse, GROW) - sp2(f, T.ret + 0.15, SHRINK));
  const oc = Math.max(0, oRaw);
  const wPt = lerp(lerp(W_PLAIN, W_EARS, earsAmt), W_OPEN, oRaw);
  const hPt = lerp(NOTCH_H, panelH, oc);
  const topR = lerp(6, 12, clamp01(oc));
  const botR = lerp(lerp(9, 12, earsAmt), 24, clamp01(oc));
  const bodyLeft = L.cx - (wPt * S) / 2;
  const contentFade = t < T.collapse ? R(T.open + 0.04, T.open + 0.16) : 1 - R(T.collapse - 0.02, T.collapse + 0.1);
  const earsFade = R(T.collapse + 0.22, T.collapse + 0.38) * (1 - R(T.ret - 0.05, T.ret + 0.05)) * (1 - clamp01(oc * 2));

  const endP = sp2(f, T.pill, GROW) - sp2(f, T.ret, SHRINK);
  const showNotch = 1 - Math.min(1, Math.max(0, endP) * 25);

  const earLeft = allowed ? <Check size={15} color={C.green} /> : <Hand size={15} color={C.amber} />;
  const earRight = <SessionCount a={allowed ? 1 : 2} b={allowed ? 0 : 2} />;

  // Ombres : mesurées sur la référence, en px puis converties dans le repère du panneau.
  const px = (v: number) => v / S;
  const shadow = `drop-shadow(0 ${px(20)}px ${px(26)}px rgba(0,0,0,0.22)) drop-shadow(0 ${px(5)}px ${px(8)}px rgba(0,0,0,0.2)) drop-shadow(0 ${px(34)}px ${px(44)}px rgba(0,0,0,0.07))`;

  return (
    <AbsoluteFill style={{ background: "#EDEDE8", overflow: "hidden" }}>
      <div
        style={{
          position: "absolute",
          inset: 0,
          background: `radial-gradient(ellipse 62% 58% at 50% ${format === "wide" ? 40 : 32}%, #F1F1ED 0%, rgba(237,237,232,0) 100%)`,
        }}
      />

      {/* la notch / le panneau */}
      <div style={{ position: "absolute", left: bodyLeft, top: 0, transform: `scale(${S})`, transformOrigin: "0 0", opacity: showNotch }}>
        <NotchBody w={wPt} h={hPt} top={topR} bottom={botR} shadow shadowFilter={shadow}>
          {earsFade > 0.01 && (
            <>
              <div style={{ position: "absolute", left: 20, top: 0, height: 32, display: "flex", alignItems: "center", opacity: earsFade, fontFamily: FONT.ui }}>{earLeft}</div>
              <div style={{ position: "absolute", right: 20, top: 0, height: 32, display: "flex", alignItems: "center", opacity: earsFade, fontFamily: FONT.ui }}>{earRight}</div>
            </>
          )}
          {oc > 0.02 && (
            <div style={{ position: "absolute", left: (wPt - W_OPEN) / 2, top: 0, width: W_OPEN, height: hPt, opacity: contentFade }}>
              <PanelInner
                tab={cur.tab}
                titleTab={titleTab}
                order={DEFAULT_ORDER}
                frame={f / 2}
                claudeState={nudged || (cur.tab === "claude" && !allowed) ? "attention" : "idle"}
                contentH={contentH}
                titleOpacity={titleOp}
                accessory={p > 0.5 ? curOut.accessory : prevOut.accessory}
                tabBarProps={{ capsule, count: 7 }}
              >
                {switching && outA > 0.01 && (
                  <div style={{ position: "absolute", inset: 0, opacity: outA, filter: `blur(${(1 - outA) * 5}px)` }}>{prevOut.node}</div>
                )}
                <div style={{ position: "absolute", inset: 0, opacity: inA, filter: inA < 1 ? `blur(${(1 - inA) * 6}px)` : undefined }}>{curOut.node}</div>
              </PanelInner>
            </div>
          )}
        </NotchBody>
      </div>

      <FileAndCursor f={f} t={t} L={L} />
      <EndCards f={f} t={t} L={L} lang={lang} endP={endP} />
    </AbsoluteFill>
  );
};

// ─────────────────────────────── Curseur ───────────────────────────────

type Key = { arrive: number; x: number; y: number };

function keysFor(L: Layout2): Key[] {
  const S = L.S;
  const left = L.cx - (W_OPEN * S) / 2;
  const P = (x: number, y: number) => ({ x: left + x * S, y: y * S });
  const tab = (i: number) => P(39.5 + 29 * i, 44);
  const hold = 0.1;
  return [
    { arrive: 0, x: L.cx + 0.22 * L.w, y: L.lowY - 50 },
    { arrive: T.open - 0.08, ...P(322, 26) },
    { arrive: T.pause - hold, ...P(183, 190) },
    { arrive: T.quick - hold, ...tab(2) },
    { arrive: T.caf - hold, ...P(322, 140) },
    { arrive: T.shelf - hold, ...tab(3) },
    { arrive: T.pick, x: L.cx + 0.2 * L.w, y: L.lowY },
    { arrive: T.drop - hold, ...P(322, 150) },
    { arrive: T.clip - hold, ...tab(4) },
    { arrive: T.copy - hold, ...P(322, 202) },
    { arrive: T.timer - hold, ...tab(5) },
    { arrive: T.notes - hold, ...tab(6) },
    { arrive: T.claude - hold, ...tab(0) },
    { arrive: T.allow - hold, ...P(584, 209.5) },
    { arrive: T.exit, x: L.cx + 0.3 * L.w, y: L.h + 70 },
  ];
}

/** Position du curseur à l'instant `t` : il attend, puis rejoint la clé suivante (≈ 0,3 à 0,6 s selon la distance). */
function cursorAt(keys: Key[], t: number) {
  let pos = { x: keys[0].x, y: keys[0].y };
  for (let i = 1; i < keys.length; i++) {
    const k = keys[i];
    const from = keys[i - 1];
    const dist = Math.hypot(k.x - from.x, k.y - from.y);
    const dur = Math.max(0.3, Math.min(0.62, 0.3 + dist / 1500));
    const start = Math.max(from.arrive + 0.03, k.arrive - dur);
    if (t >= k.arrive) pos = { x: k.x, y: k.y };
    else if (t > start) {
      const e = CURSOR_EASE((t - start) / (k.arrive - start));
      return { x: from.x + (k.x - from.x) * e, y: from.y + (k.y - from.y) * e };
    } else break;
  }
  return pos;
}

const FALL = { mass: 1, stiffness: 220, damping: 2 * 0.85 * Math.sqrt(220) };
const CLICKS = [T.pause, T.quick, T.caf, T.shelf, T.clip, T.copy, T.timer, T.notes, T.claude, T.allow];

const FileAndCursor: React.FC<{ f: number; t: number; L: Layout2 }> = ({ f, t, L }) => {
  const keys = React.useMemo(() => keysFor(L), [L]);
  const { x, y } = cursorAt(keys, t);
  const vis = ramp2(f, 0, 0.14, 0, 1) * (1 - ramp2(f, T.exit - 0.05, T.exit, 0, 1, (v) => v));
  const press = Math.max(
    0,
    ...CLICKS.map((c) => (t >= c - 0.03 && t <= c + 0.1 ? 1 - Math.abs((t - c - 0.035) / 0.065) : 0)),
    t >= T.pick && t < T.drop ? 0.9 : 0,
  );
  const speed = (() => {
    const q = cursorAt(keys, t - 1 / FPS2);
    return Math.hypot(x - q.x, y - q.y) * FPS2;
  })();
  const ghosts = speed > 650 ? [1, 2, 3] : [];
  const size = L.cursor;
  const dragging = t >= T.pick && t < T.drop;
  const filePop = ramp2(f, T.pick, T.pick + 0.18, 0, 1, (v) => 1 - Math.pow(1 - v, 3));
  const item = SHELF_ITEMS[5];
  if (vis <= 0.001) return null;
  return (
    <>
      {dragging && (
        <div
          style={{
            position: "absolute",
            left: x - 8,
            top: y - 6,
            opacity: filePop,
            transform: `scale(${L.S * (0.8 + 0.25 * filePop)}) rotate(-6deg)`,
            transformOrigin: "0 0",
            filter: "drop-shadow(0 8px 10px rgba(0,0,0,0.3))",
          }}
        >
          <FileGlyph kind={item.kind} />
        </div>
      )}
      {ghosts.map((k) => {
        const q = cursorAt(keys, t - k / FPS2 / 2);
        return (
          <div key={k} style={{ position: "absolute", left: q.x - 1.4 * (size / 16), top: q.y - 1.2 * (size / 16), opacity: vis * 0.2 / k }}>
            <Cursor size={size} />
          </div>
        );
      })}
      <div
        style={{
          position: "absolute",
          left: x - 1.4 * (size / 16),
          top: y - 1.2 * (size / 16),
          opacity: vis,
          transform: `scale(${1 - 0.1 * press})`,
          transformOrigin: "1px 1px",
          filter: "drop-shadow(0 3px 5px rgba(0,0,0,0.3))",
        }}
      >
        <Cursor size={size} />
      </div>
    </>
  );
};

// ─────────────────────────────── Pastille finale ───────────────────────────────

const EndCards: React.FC<{ f: number; t: number; L: Layout2; lang: Lang; endP: number }> = ({ f, t, L, lang, endP }) => {
  const e = L.end;
  const R = (a: number, b: number) => ramp2(f, a, b, 0, 1, outExpo);
  const p = Math.max(0, endP);
  if (p <= 0.0005) return null;
  // La forme change vite (ressort de la référence) ; la chute est plus lente, pour qu'on la voie tomber.
  const fall = Math.max(0, sp2(f, T.pill, FALL) - sp2(f, T.ret, FALL));
  const w = lerp(W_EARS * L.S, e.cardW, p);
  const h = lerp(NOTCH_H * L.S, e.cardH, p);
  const top = lerp(0, e.top, fall);
  const out = 1 - R(T.ret - 0.05, T.ret + 0.05);
  const textIn = R(T.pillText, T.pillText + 0.16) * out;
  const lp = Math.max(0, sp2(f, T.link, GROW) - sp2(f, T.ret, SHRINK));
  const linkTop = e.top + e.cardH + e.gap;
  const legalIn = R(T.link + 0.2, T.link + 0.4) * out;
  const shadow = "0 22px 30px rgba(0,0,0,0.22), 0 5px 8px rgba(0,0,0,0.2), 0 34px 44px rgba(0,0,0,0.07)";
  return (
    <>
      <div
        style={{
          position: "absolute",
          left: L.cx - w / 2,
          top,
          width: w,
          height: h,
          borderRadius: Math.min(h / 2, e.cardH / 2),
          background: "#000",
          boxShadow: shadow,
          opacity: Math.min(1, p * 25),
        }}
      >
        <div
          style={{
            position: "absolute",
            inset: 0,
            display: "flex",
            alignItems: "center",
            justifyContent: "center",
            gap: e.cardH * 0.2,
            opacity: textIn,
            filter: textIn < 1 ? `blur(${(1 - textIn) * 8}px)` : undefined,
            fontFamily: FONT.ui,
            color: "#fff",
            overflow: "hidden",
            whiteSpace: "nowrap",
          }}
        >
          <Spark size={e.cardH * 0.4} color={C.accent} />
          <div>
            <div style={{ fontSize: e.title, fontWeight: 700, letterSpacing: "-0.025em", lineHeight: 1.05 }}>Claude Notch</div>
            <div style={{ fontSize: e.caption, fontWeight: 400, color: "rgba(255,255,255,0.55)", marginTop: e.cardH * 0.04, letterSpacing: "-0.01em" }}>{tx(lang, COPY.tagline)}</div>
          </div>
        </div>
      </div>

      {lp > 0.001 && (
        <div
          style={{
            position: "absolute",
            left: L.cx - e.linkW / 2,
            top: linkTop,
            width: e.linkW,
            height: e.linkH,
            borderRadius: e.linkH / 2,
            background: "#FDFDFD",
            boxShadow: "0 18px 26px rgba(0,0,0,0.12), 0 4px 8px rgba(0,0,0,0.1)",
            opacity: Math.min(1, lp * 3.5),
            transform: `translateY(${(1 - lp) * -e.linkH * 0.7}px) scale(${0.8 + 0.2 * lp})`,
            transformOrigin: "50% 0",
            display: "flex",
            alignItems: "center",
            justifyContent: "center",
            fontFamily: FONT.mono,
            fontSize: e.link,
            fontWeight: 500,
            color: "#0B0B0B",
            letterSpacing: "-0.02em",
          }}
        >
          <span style={{ opacity: R(T.link + 0.06, T.link + 0.2) * out, filter: `blur(${(1 - R(T.link + 0.06, T.link + 0.2)) * 6}px)` }}>{COPY.link}</span>
        </div>
      )}

      <div
        style={{
          position: "absolute",
          left: 0,
          right: 0,
          top: e.legalY,
          textAlign: "center",
          fontFamily: FONT.mono,
          fontSize: e.legal,
          lineHeight: 1.5,
          color: "#8A8A84",
          opacity: legalIn,
        }}
      >
        <div>{tx(lang, COPY.free)}</div>
        {COPY.legal.map((line, i) => (
          <div key={i}>{tx(lang, line)}</div>
        ))}
      </div>
    </>
  );
};
