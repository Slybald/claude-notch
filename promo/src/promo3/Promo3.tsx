import React from "react";
import { AbsoluteFill, useCurrentFrame } from "remotion";
import { useFontsReady } from "../fonts";
import { LangProvider, Lang, useLang } from "../i18n";
import { C, FONT } from "../theme";
import { BLUR_EASE, CURSOR_EASE, FPS2, GROW, SHRINK, SNAP, clamp01, fr, lerp, outExpo, ramp2, sp2 } from "../motion2";
import { NotchBody, NOTCH_H, PanelInner, TabId, panelHeight } from "../ui/notch";
import { ClipboardTab, EqualizerBars, FileGlyph, NotesTab, PlayerTab, QuickTab, SHELF_ITEMS, ShelfTab, TimerTab } from "../ui/tabs";
import { Conversation, PermissionReply, SessionCard } from "../ui/claude";
import { Cursor, PauseCircle, Radio, Spark, Trash } from "../ui/icons";
import { MessageIcon, NotchGlyph } from "../ui/icons3";
import { CodexTab, IndexTabs, MacMenu, MailTab, MediaCardDetail, MenuEntry, MessagesTab, PlainPlus, SetupWindow, WINDOW_H, WINDOW_W, idxTabs } from "../ui/extra";
import { APP } from "./identity";
import { FEATURES } from "./copy3";
import { Wheel } from "./Wheel";
import { Format3, Layout3, layout3 } from "./layout3";

// ─────────────────────────────── Calendrier (secondes) ───────────────────────────────
// Un temps fort tous les 0,5 à 1,5 s. Chaque réaction suit l'arrivée du curseur de 0,10 s (arrêt, puis clic).
export const T = {
  hover: 0.5, // le curseur survole l'intercalaire de lecture : il se déploie
  open: 1.2, // clic sur la carte : le panneau s'ouvre sur le lecteur
  pause: 1.7,
  day: 2.2,
  quick: 2.9,
  caf: 3.5,
  shelf: 4.0,
  pick: 4.45,
  drop: 5.0,
  clip: 5.45,
  copy: 6.05,
  timer: 6.5,
  notes: 7.25,
  typeNotes: 7.45,
  mail: 8.6,
  reply: 9.3,
  typeMail: 9.45,
  mailSend: 10.3,
  claude: 11.0, // l'onglet Claude (facultatif) : une session attend
  ask: 11.3,
  allow: 12.1,
  chatHover: 12.45,
  chat: 12.9,
  typeFrom: 13.1,
  typeTo: 13.75,
  send: 13.95,
  codex: 14.5,
  cAllow: 15.25,
  press: 15.85, // appui long sur la barre d'onglets
  edit: 16.35, // 0,5 s plus tard : le mode édition
  drag: 16.6,
  drop2: 17.25,
  plus: 17.6,
  pick2: 18.1,
  done: 18.6,
  messages: 19.0,
  msgReply: 19.65,
  typeMsg: 19.8,
  msgSend: 20.5,
  more: 21.1,
  menuHover: 21.5,
  menuClose: 22.1,
  collapse: 22.2,
  fall: 23.05, // la notch tombe et devient la fenêtre de l'assistant
  profile: 24.25,
  pill: 25.15, // la fenêtre se resserre en carte du nom
  pillText: 25.55,
  link: 26.0, // la roue monte et devient la carte du lien
  /** Fin de la vidéo ; la boucle du GIF continue jusqu'à `loopEnd`. */
  ret: 28.25,
  loopEnd: 28.95,
  /** La roue : instants où elle passe à la fonction suivante (une valeur par entrée de FEATURES, sauf la première). */
  wheel: [1.2, 2.2, 2.9, 4.0, 5.45, 6.5, 7.25, 8.6, 11.0, 11.8, 12.9, 14.5, 15.9, 16.6, 17.6, 19.0, 21.1, 23.15, 24.25],
};
export const CTA_END = fr(T.ret);
export const DURATION3 = fr(T.loopEnd);

const ORDER0: TabId[] = ["claude", "codex", "player", "quick", "shelf", "clip", "timer", "notes", "mail"];
const ORDER1: TabId[] = ["claude", "codex", "notes", "player", "quick", "shelf", "clip", "timer", "mail", "messages"];
const ALL: TabId[] = ORDER1;
const PITCH = 29;
const tabs: { tab: TabId; at: number }[] = [
  { tab: "player", at: T.open },
  { tab: "quick", at: T.quick },
  { tab: "shelf", at: T.shelf },
  { tab: "clip", at: T.clip },
  { tab: "timer", at: T.timer },
  { tab: "notes", at: T.notes },
  { tab: "mail", at: T.mail },
  { tab: "claude", at: T.claude },
  { tab: "codex", at: T.codex },
  { tab: "messages", at: T.messages },
];
const orderAt = (at: number) => (at < T.edit ? ORDER0 : ORDER1);
const slotOf = (id: TabId, at: number) => orderAt(at).indexOf(id) * PITCH;
/** Centre (pt) d'un onglet de la barre dans le repère du panneau. */
const tabCenter = (id: TabId, at: number) => ({ x: 26 + 13.5 + slotOf(id, at), y: 44 });

// Géométrie de la notch (pt)
const W_PLAIN = 197;
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

export type Promo3Props = { format: Format3; lang: Lang };

export const Promo3: React.FC<Promo3Props> = ({ format, lang }) => {
  useFontsReady();
  return (
    <LangProvider lang={lang}>
      <Scene3 format={format} lang={lang} />
    </LangProvider>
  );
};

/** Position de l'icône glissée (pt) et progression, partagées par l'icône et le curseur. */
const dragE = (t: number) => CURSOR_EASE(clamp01((t - T.drag) / (T.drop2 - T.drag)));
/** Instant où l'icône glissée passe le milieu de la place `slot` : l'onglet qui l'occupe s'écarte alors d'une place. */
const crossAt = (slot: number) => {
  const thr = slot * PITCH + PITCH / 2;
  for (let tt = T.drag; tt < T.drop2; tt += 0.01) if (lerp(7 * PITCH, 2 * PITCH, dragE(tt)) <= thr) return tt;
  return T.drop2;
};
const CROSS = [2, 3, 4, 5, 6].map(crossAt);

const Scene3: React.FC<{ format: Format3; lang: Lang }> = ({ format, lang }) => {
  const f = useCurrentFrame();
  const t = f / FPS2;
  const L = layout3(format);
  const S = L.S;
  const tr = (en: string, frn: string) => (lang === "fr" ? frn : en);
  const R = (a: number, b: number, easing = outExpo) => ramp2(f, a, b, 0, 1, easing);

  // ── Claude : permission, puis conversation ──
  const askP = clamp01(sp2(f, T.ask, GROW) - sp2(f, T.allow + 0.02, SHRINK));
  const allowed = t >= T.allow;
  const chatP = sp2(f, T.chat, GROW);
  const sentP = R(T.send, T.send + 0.2);
  const convH = 109 + 47 * sentP;
  const chatBtn = R(T.chatHover, T.chatHover + 0.16) * (t < T.chat ? 1 : 0);
  const claudeBase = 207.5 + 109 * askP;
  const claudeH = lerp(claudeBase, 65 + convH, chatP);
  // ── Codex : la demande se replie après « Allow » ──
  const approved = clamp01(sp2(f, T.cAllow + 0.02, SHRINK));
  // ── Mail et Messages : réponse rapide ──
  const typedOf = (a: number, b: number) => clamp01((t - a) / (b - a));
  const mailReply = sp2(f, T.reply, GROW);
  const mailHot = R(T.reply - 0.3, T.reply - 0.16) * (t < T.reply ? 1 : 0);
  const msgReply = sp2(f, T.msgReply, GROW);
  const msgHot = R(T.msgReply - 0.3, T.msgReply - 0.16) * (t < T.msgReply ? 1 : 0);

  const tabOut = (tab: TabId, at: number): TabOut => {
    switch (tab) {
      case "claude": {
        const cardTop = 65 + 109 * askP + (chatP > 0 ? convH * chatP + 8 * chatP : 0);
        const lastTop = cardTop + 85.5;
        const pulse = 0.6 + 0.4 * Math.sin(f / 9);
        return {
          h: claudeH,
          node: (
            <div style={{ position: "absolute", inset: 0, overflow: "hidden" }}>
              <div style={{ position: "absolute", left: 0, top: 0 }}>
                <SessionCard
                  kind={allowed ? "running" : "attention"}
                  name="api"
                  time={allowed ? "1 s" : "2 s"}
                  status={allowed ? "Terminal" : tr("Needs your permission", "Attend ta permission")}
                  detail={allowed ? "rm -rf build && swift build" : "Terminal · rm -rf build"}
                  outline={allowed ? 0 : pulse * 0.35 + 0.65}
                  chatButton={chatBtn}
                  frame={f / 2}
                />
              </div>
              {askP > 0.01 && (
                <div style={{ position: "absolute", left: 0, top: 65, height: 101 * askP, overflow: "hidden", opacity: clamp01(askP * 1.4) }}>
                  <PermissionReply command="rm -rf build && swift build -c release" reason={tr("Clean rebuild", "Rebuild propre")} pressAllow={t >= T.allow && t < T.allow + 0.1 ? 1 : 0} />
                </div>
              )}
              {chatP > 0.01 && (
                <div style={{ position: "absolute", left: 0, top: 65, height: convH * chatP, overflow: "hidden", opacity: clamp01(chatP * 1.5) }}>
                  <Conversation
                    said={tr("Rebuild done, all 142 tests pass.", "Rebuild terminé, les 142 tests passent.")}
                    you={tr("Run the linter too", "Lance aussi le linter")}
                    typed={typedOf(T.typeFrom, T.typeTo)}
                    sent={sentP > 0.2}
                    showYou={sentP > 0.2}
                    frame={f / 2}
                  />
                </div>
              )}
              <div style={{ position: "absolute", left: 0, top: cardTop }}>
                <SessionCard kind="running" name="mon-app" agents={tr("2 agents", "2 agents")} time="2 s" status="Terminal" detail="npm test -- --watch=false" task={{ done: 1, total: 3, title: tr("Fix the parser", "Correction du parseur") }} frame={f / 2} />
              </div>
              <div style={{ position: "absolute", left: 0, top: lastTop }}>
                <SessionCard kind="done" name="site" time={tr("just now", "à l'instant")} status={tr("Done", "Terminé")} detail={tr("README updated: installation section rewritten.", "README à jour : section installation réécrite.")} detailMono={false} />
              </div>
            </div>
          ),
        };
      }
      case "codex":
        return { h: 251 - 129 * approved, node: <CodexTab approved={approved} pressAllow={t >= T.cAllow && t < T.cAllow + 0.1 ? 1 : 0} /> };
      case "player":
        return {
          h: 150,
          accessory: t < T.pause ? <EqualizerBars frame={f / 2} /> : undefined,
          node: <PlayerTab progress={0.33 + Math.min(t, T.pause) / 230} playing={t < T.pause} day={t >= T.day ? 22 : 20} />,
        };
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
          node: <ClipboardTab rows={5} progressOf={(i) => R(at + 0.06 + i * 0.05, at + 0.28 + i * 0.05)} hoverRow={t >= T.copy - 0.4 && t < T.copy ? 2 : -1} copiedRow={t >= T.copy && t < T.copy + 0.9 ? 2 : -1} />,
        };
      case "timer": {
        const wind = outExpo(clamp01((t - at - 0.15) / 0.6));
        const remaining = lerp(25 * 60, 18 * 60 + 12, wind) - Math.max(0, t - at - 0.75);
        return { h: 170, node: <TimerTab remaining={remaining} /> };
      }
      case "notes": {
        const marks = [0, 0.1, 0.2, 0.3, 0.45, 0.55, 0.65, 0.78, 0.9];
        const steps = marks.filter((m) => t >= T.typeNotes + m).length;
        return { h: 214, node: <NotesTab typed={steps / marks.length} selected={3} /> };
      }
      case "mail":
        return {
          h: 201 + 30 * mailReply,
          node: (
            <MailTab
              hot={mailHot}
              replying={mailReply}
              typed={typedOf(T.typeMail, T.typeMail + 0.6)}
              sent={R(T.mailSend, T.mailSend + 0.1)}
              sendPress={t >= T.mailSend && t < T.mailSend + 0.1 ? 1 : 0}
              frame={f / 2}
              rowsIn={(i) => R(at + 0.06 + i * 0.05, at + 0.28 + i * 0.05)}
            />
          ),
        };
      case "messages":
        return {
          h: 177 + 30 * msgReply,
          node: (
            <MessagesTab
              hot={msgHot}
              replying={msgReply}
              typed={typedOf(T.typeMsg, T.typeMsg + 0.5)}
              sent={R(T.msgSend, T.msgSend + 0.1)}
              sendPress={t >= T.msgSend && t < T.msgSend + 0.1 ? 1 : 0}
              frame={f / 2}
              rowsIn={(i) => R(at + 0.06 + i * 0.05, at + 0.28 + i * 0.05)}
            />
          ),
        };
    }
  };

  // ── Onglet affiché et transition ──
  let ti = 0;
  tabs.forEach((x, i) => {
    if (t >= x.at) ti = i;
  });
  const cur = tabs[ti];
  const prev = tabs[Math.max(0, ti - 1)];
  const switching = ti > 0 && t < cur.at + 0.3;
  const curOut = tabOut(cur.tab, cur.at);
  const prevOut = switching ? tabOut(prev.tab, prev.at) : curOut;
  const p = ti === 0 ? 1 : sp2(f, cur.at, curOut.h >= prevOut.h ? GROW : SHRINK);
  const contentH = lerp(prevOut.h, curOut.h, p);
  const panelH = panelHeight(contentH);

  // Sélecteur élastique : le bord avant part en premier, le bord arrière suit.
  const a = slotOf(prev.tab, prev.at);
  const b = slotOf(cur.tab, cur.at);
  const lead = ti === 0 ? b : a + (b - a) * sp2(f, cur.at, { mass: 1, stiffness: 520, damping: 2 * 0.75 * Math.sqrt(520) });
  const trail = ti === 0 ? b : a + (b - a) * sp2(f, cur.at + 0.04, { mass: 1, stiffness: 300, damping: 2 * 0.95 * Math.sqrt(300) });
  const left = b >= a ? trail : lead;
  const right = (b >= a ? lead : trail) + 27;
  const capsule = { x: left, w: right - left };

  const outA = 1 - R(cur.at, cur.at + 0.1, (v) => v);
  const inA = ti === 0 ? R(T.open + 0.12, T.open + 0.26, BLUR_EASE) : R(cur.at + 0.07, cur.at + 0.2, BLUR_EASE);
  const titleOp = ti === 0 || p > 0.98 ? 1 : outA > 0.02 ? outA : inA;
  const titleTab = outA > 0.02 && ti > 0 ? prev.tab : cur.tab;

  // ── Mode édition des onglets : appui long, tremblement, glisser, « + », OK ──
  const editing = t >= T.edit && t < T.done;
  const badge = R(T.edit, T.edit + 0.14) * (editing ? 1 : 0);
  const dragMove = t < T.drag ? 0 : dragE(t);
  const addP = clamp01(sp2(f, T.pick2, SNAP));
  const xs: Partial<Record<TabId, number>> = {};
  ORDER0.forEach((id, i) => {
    let x = i * PITCH;
    if (id === "notes") x = lerp(7 * PITCH, 2 * PITCH, dragMove);
    else if (i >= 2 && i <= 6) x = x + PITCH * clamp01(sp2(f, CROSS[i - 2], SNAP));
    xs[id] = x;
  });
  xs.messages = 9 * PITCH;
  const opacities: Partial<Record<TabId, number>> = { messages: addP };
  const lifted = t >= T.drag && t < T.drop2 + 0.12 ? ("notes" as TabId) : null;
  const barCount = 9 + addP;
  const editFade = R(T.edit, T.edit + 0.2) * (1 - R(T.done, T.done + 0.2));

  // ── Menus (« + », puis « … ») ──
  const plusMenuP = sp2(f, T.plus, SNAP) * (1 - R(T.pick2, T.pick2 + 0.08, (v) => v));
  const moreMenuP = sp2(f, T.more, SNAP) * (1 - R(T.menuClose, T.menuClose + 0.08, (v) => v));

  // ── Mode de la notch : repliée avec intercalaires, déployée, repliée, puis carte ──
  const oRaw = sp2(f, T.open, GROW) - sp2(f, T.collapse, SHRINK);
  const oc = Math.max(0, oRaw);
  const wPt = lerp(W_PLAIN, W_OPEN, oRaw);
  const hPt = lerp(NOTCH_H, panelH, oc);
  const topR = lerp(6, 12, clamp01(oc));
  const botR = lerp(9, 24, clamp01(oc));
  const contentFade = t < T.collapse ? R(T.open + 0.04, T.open + 0.16) : 1 - R(T.collapse - 0.02, T.collapse + 0.1);

  // Intercalaires : visibles au repos, ils laissent la place au panneau.
  const afterRet = t >= T.ret;
  const tabsFade = t < T.open ? 1 : t < T.collapse ? 0 : t < T.fall ? R(T.collapse + 0.25, T.collapse + 0.4) * (1 - R(T.fall - 0.1, T.fall)) : afterRet ? R(T.ret + 0.2, T.ret + 0.4) : 0;
  const unfoldP = sp2(f, T.hover + 0.04, GROW) * (1 - R(T.open - 0.01, T.open + 0.05, (v) => v));
  const endSet = t >= T.open && t < T.ret;
  const timerLeft = lerp(25 * 60, 18 * 60 + 12, outExpo(clamp01((t - T.timer - 0.15) / 0.6))) - Math.max(0, t - T.timer - 0.75);
  const mm = (s: number) => `${Math.floor(s / 60)}:${String(Math.floor(s % 60)).padStart(2, "0")}`;
  const idx = endSet
    ? [
        idxTabs.claude({ alert: false, sessions: 2 }),
        idxTabs.timer(mm(t >= T.timer ? timerLeft : 24 * 60 + 59)),
        idxTabs.media(f / 2),
        idxTabs.messages(3),
        idxTabs.mail(11),
      ]
    : [idxTabs.claude({ alert: true, sessions: 2, agents: 2 }), idxTabs.timer("24:59"), idxTabs.media(f / 2), idxTabs.mail(12)];

  // La carte noire : notch → fenêtre de l'assistant → carte du nom → notch (boucle du GIF). Une seule forme.
  const FALL = { mass: 1, stiffness: 220, damping: 2 * 0.85 * Math.sqrt(220) };
  const cardP = sp2(f, T.fall, GROW) - sp2(f, T.ret, SHRINK);
  const showNotch = 1 - Math.min(1, Math.max(0, cardP) * 25);

  const px = (v: number) => v / S;
  const shadow = `drop-shadow(0 ${px(20)}px ${px(26)}px rgba(0,0,0,0.22)) drop-shadow(0 ${px(5)}px ${px(8)}px rgba(0,0,0,0.2)) drop-shadow(0 ${px(34)}px ${px(44)}px rgba(0,0,0,0.07))`;
  const panelLeft = L.cx - (W_OPEN * S) / 2;

  // ── Roue : une valeur continue, somme de ressorts ──
  const wheelCfg = { mass: 1, stiffness: 520, damping: 2 * 0.8 * Math.sqrt(520) };
  const wheelAt = (frame: number) => (frame / FPS2 >= T.ret ? 0 : T.wheel.reduce((s, at) => s + sp2(frame, at, wheelCfg), 0));
  const index = wheelAt(f);
  const speed = (index - wheelAt(f - 1)) * FPS2;
  const morph = Math.max(0, sp2(f, T.link, GROW) - sp2(f, T.ret, SHRINK));
  const E = L.end;
  const names = FEATURES.map(([en, frn]) => tr(en, frn));

  return (
    <AbsoluteFill style={{ background: "#EDEDE8", overflow: "hidden" }}>
      <div style={{ position: "absolute", inset: 0, background: `radial-gradient(ellipse 62% 58% at 50% ${format === "wide" ? 40 : 32}%, #F1F1ED 0%, rgba(237,237,232,0) 100%)` }} />

      <Wheel
        index={index}
        speed={speed}
        names={names}
        W={L.wheel}
        cx={L.cx}
        morph={morph}
        link={{ top: E.top + E.cardH + E.gap, w: E.linkW, h: E.linkH, font: E.link, text: APP.link }}
      />

      {/* la notch, ses intercalaires et le panneau */}
      <div style={{ position: "absolute", left: L.cx, top: 0, transform: `scale(${S})`, transformOrigin: "0 0", opacity: showNotch, filter: shadow }}>
        <IndexTabs
          tabs={idx}
          fade={tabsFade}
          halfWidth={L.w / 2 / S}
          unfold={{
            id: "media",
            p: unfoldP,
            title: tr("Player", "Lecteur"),
            detailH: 74,
            detail: <MediaCardDetail title={tr("City Lights", "Lumières de la ville")} artist={tr("The Fictives", "Les Fictifs")} />,
          }}
        />
        <div style={{ position: "absolute", left: -wPt / 2, top: 0 }}>
          <NotchBody w={wPt} h={hPt} top={topR} bottom={botR} shadow={false}>
            {oc > 0.02 && (
              <div style={{ position: "absolute", left: (wPt - W_OPEN) / 2, top: 0, width: W_OPEN, height: hPt, opacity: contentFade }}>
                <PanelInner
                  tab={cur.tab}
                  titleTab={titleTab}
                  order={ALL}
                  frame={f / 2}
                  editing={editing}
                  claudeState={!allowed ? "attention" : "idle"}
                  contentH={contentH}
                  contentOpacity={1 - 0.65 * editFade}
                  titleOpacity={titleOp}
                  accessory={p > 0.5 ? curOut.accessory : prevOut.accessory}
                  addSlot={<PlainPlus press={t >= T.plus && t < T.plus + 0.1 ? 1 : 0} />}
                  okPress={t >= T.done && t < T.done + 0.1 ? 1 : 0}
                  tabBarProps={{ capsule, count: barCount, xs, opacities, lifted, badge }}
                >
                  {switching && outA > 0.01 && <div style={{ position: "absolute", inset: 0, opacity: outA, filter: `blur(${(1 - outA) * 5}px)` }}>{prevOut.node}</div>}
                  <div style={{ position: "absolute", inset: 0, opacity: inA, filter: inA < 1 ? `blur(${(1 - inA) * 6}px)` : undefined }}>{curOut.node}</div>
                </PanelInner>
              </div>
            )}
          </NotchBody>
        </div>
      </div>

      {/* menus : posés au-dessus du panneau, dans son repère */}
      <div style={{ position: "absolute", left: panelLeft, top: 0, transform: `scale(${S})`, transformOrigin: "0 0", opacity: showNotch }}>
        {plusMenuP > 0.01 && (
          <div style={{ position: "absolute", left: 26 + 9 * PITCH - 2, top: 59, transformOrigin: "0 0", opacity: 1 }}>
            <MacMenu
              p={plusMenuP}
              width={136}
              hover={t >= T.pick2 - 0.3 ? 0 : -1}
              pressed={t >= T.pick2 && t < T.pick2 + 0.08}
              entries={[{ label: tr("Messages", "Messages"), icon: <MessageIcon size={12} color="#fff" /> }]}
            />
          </div>
        )}
        {moreMenuP > 0.01 && (
          <div style={{ position: "absolute", left: 26 + 592 - 232, top: 58 }}>
            <MacMenu p={moreMenuP} width={232} hover={t >= T.menuHover - 0.1 ? 7 : -1} entries={moreEntries(lang)} />
          </div>
        )}
      </div>

      <BlackCard f={f} t={t} L={L} lang={lang} FALL={FALL} />

      <FileAndCursor f={f} t={t} L={L} />
      <Legal f={f} t={t} L={L} lang={lang} />
    </AbsoluteFill>
  );
};

const moreEntries = (lang: Lang): MenuEntry[] => {
  const tr = (en: string, fr_: string) => (lang === "fr" ? fr_ : en);
  return [
    { label: tr("Settings…", "Réglages…"), shortcut: "⌘," },
    "sep",
    { label: tr("Show the Notch", "Afficher la notch"), sub: true },
    { label: tr("Hide the Notch", "Masquer la notch"), sub: true },
    { label: tr("Launch at Login", "Lancer à l'ouverture de session") },
    "sep",
    { label: tr(`Version ${APP.version}`, `Version ${APP.version}`), disabled: true },
    { label: tr("Automatic Updates", "Mises à jour automatiques"), check: true },
    { label: tr("Check for Updates", "Rechercher les mises à jour") },
    "sep",
    { label: tr(`Quit ${APP.name}`, `Quitter ${APP.name}`) },
  ];
};

// ─────────────────────────────── Curseur ───────────────────────────────

type Key = { arrive: number; x: number; y: number };

function keysFor(L: Layout3): Key[] {
  const S = L.S;
  const left = L.cx - (W_OPEN * S) / 2;
  const P = (x: number, y: number) => ({ x: left + x * S, y: y * S });
  const tab = (id: TabId, at: number) => {
    const c = tabCenter(id, at);
    return P(c.x, c.y);
  };
  const hold = 0.1;
  // « + » : après le dernier onglet (9 onglets avant l'ajout). Menu : première ligne.
  const plusX = 26 + 9 * PITCH - 2 + 13.5;
  return [
    { arrive: 0, x: L.cx + 0.24 * L.w, y: L.h - 130 },
    { arrive: T.hover, x: L.cx - 168 * S, y: 13 * S },
    { arrive: T.open - hold, x: L.cx - 262 * S, y: 62 * S },
    { arrive: T.pause - hold, ...P(183, 190) },
    { arrive: T.day - hold, ...P(484, 127) },
    { arrive: T.quick - hold, ...tab("quick", T.quick) },
    { arrive: T.caf - hold, ...P(322, 140) },
    { arrive: T.shelf - hold, ...tab("shelf", T.shelf) },
    { arrive: T.pick, x: L.pick.x, y: L.pick.y },
    { arrive: T.drop - hold, ...P(322, 150) },
    { arrive: T.clip - hold, ...tab("clip", T.clip) },
    { arrive: T.copy - hold, ...P(322, 202) },
    { arrive: T.timer - hold, ...tab("timer", T.timer) },
    { arrive: T.notes - hold, ...tab("notes", T.notes) },
    { arrive: T.mail - hold, ...tab("mail", T.mail) },
    { arrive: T.reply - hold, ...P(567, 80) },
    { arrive: T.claude - hold, ...tab("claude", T.claude) },
    { arrive: T.allow - hold, ...P(584, 209.5) },
    { arrive: T.chatHover, ...P(330, 96) },
    { arrive: T.chat - hold, ...P(550, 85) },
    { arrive: T.codex - hold, ...tab("codex", T.codex) },
    { arrive: T.cAllow - hold, ...P(582, 230) },
    { arrive: T.press - hold, ...tab("notes", T.press) },
    { arrive: T.drop2, ...tab("notes", T.drop2) },
    { arrive: T.plus - hold, ...P(plusX, 44) },
    { arrive: T.pick2 - hold, ...P(26 + 9 * PITCH - 2 + 50, 75) },
    { arrive: T.done - hold, ...P(595, 44) },
    { arrive: T.messages - hold, ...tab("messages", T.messages) },
    { arrive: T.msgReply - hold, ...P(300, 87) },
    { arrive: T.more - hold, ...P(607, 44) },
    { arrive: T.menuHover - hold, ...P(26 + 592 - 232 + 120, 58 + 148) },
    { arrive: T.profile - hold, x: L.cx + 0, y: 0 }, // remplacé plus bas (position de la carte « Créatif »)
    { arrive: T.profile + 0.9, x: L.cx + 0.3 * L.w, y: L.h + 70 },
  ];
}

/** Position du curseur : il attend, puis rejoint la clé suivante (0,3 à 0,62 s selon la distance). */
function cursorAt(keys: Key[], t: number, L: Layout3) {
  // Glisser de l'icône : le curseur suit l'icône exactement.
  if (t >= T.drag && t < T.drop2) {
    const c0 = tabCenter("notes", T.press);
    const c1 = tabCenter("notes", T.drop2);
    const left = L.cx - (W_OPEN * L.S) / 2;
    const e = dragE(t);
    return { x: left + lerp(c0.x, c1.x, e) * L.S, y: 44 * L.S };
  }
  let pos = { x: keys[0].x, y: keys[0].y };
  for (let i = 1; i < keys.length; i++) {
    const k = keys[i];
    const from = keys[i - 1];
    const dist = Math.hypot(k.x - from.x, k.y - from.y);
    const dur = Math.max(0.3, Math.min(0.62, 0.3 + dist / 1500));
    const start = Math.max(from.arrive + 0.16, k.arrive - dur);
    if (t >= k.arrive) pos = { x: k.x, y: k.y };
    else if (t > start) {
      const e = CURSOR_EASE((t - start) / (k.arrive - start));
      return { x: from.x + (k.x - from.x) * e, y: from.y + (k.y - from.y) * e };
    } else break;
  }
  return pos;
}

const CLICKS = [T.open, T.pause, T.day, T.quick, T.caf, T.shelf, T.clip, T.copy, T.timer, T.notes, T.mail, T.reply, T.claude, T.allow, T.chat, T.codex, T.cAllow, T.plus, T.pick2, T.done, T.messages, T.msgReply, T.more, T.profile];

const FileAndCursor: React.FC<{ f: number; t: number; L: Layout3 }> = ({ f, t, L }) => {
  const keys = React.useMemo(() => {
    const k = keysFor(L);
    // Carte « Créatif » de la fenêtre : 3e carte, centre à (28 + 232, 138 + 2×54 + 24) pt dans la fenêtre.
    const wl = L.cx - (WINDOW_W * L.win.S) / 2;
    const i = k.findIndex((x) => x.arrive === T.profile - 0.1);
    k[i] = { arrive: T.profile - 0.1, x: wl + (28 + 300) * L.win.S, y: L.win.top + (138 + 2 * 54 + 24) * L.win.S };
    return k;
  }, [L]);
  const { x, y } = cursorAt(keys, t, L);
  const exit = T.profile + 0.9;
  const vis = ramp2(f, 0, 0.14, 0, 1) * (1 - ramp2(f, exit - 0.05, exit, 0, 1, (v) => v));
  const press = Math.max(
    0,
    ...CLICKS.map((c) => (t >= c - 0.03 && t <= c + 0.1 ? 1 - Math.abs((t - c - 0.035) / 0.065) : 0)),
    t >= T.pick && t < T.drop ? 0.9 : 0,
    t >= T.press && t < T.drop2 ? 0.9 : 0, // appui long, puis glisser : le bouton reste enfoncé
  );
  const speed = (() => {
    const q = cursorAt(keys, t - 1 / FPS2, L);
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
        <div style={{ position: "absolute", left: x - 8, top: y - 6, opacity: filePop, transform: `scale(${L.S * (0.8 + 0.25 * filePop)}) rotate(-6deg)`, transformOrigin: "0 0", filter: "drop-shadow(0 8px 10px rgba(0,0,0,0.3))" }}>
          <FileGlyph kind={item.kind} />
        </div>
      )}
      {ghosts.map((k) => {
        const q = cursorAt(keys, t - k / FPS2 / 2, L);
        return (
          <div key={k} style={{ position: "absolute", left: q.x - 1.4 * (size / 16), top: q.y - 1.2 * (size / 16), opacity: (vis * 0.2) / k }}>
            <Cursor size={size} />
          </div>
        );
      })}
      <div style={{ position: "absolute", left: x - 1.4 * (size / 16), top: y - 1.2 * (size / 16), opacity: vis, transform: `scale(${1 - 0.1 * press})`, transformOrigin: "1px 1px", filter: "drop-shadow(0 3px 5px rgba(0,0,0,0.3))" }}>
        <Cursor size={size} />
      </div>
    </>
  );
};

// ─────────────────────────────── Carte noire : fenêtre de l'assistant, puis carte du nom ───────────────────────────────

type Rect = { x: number; y: number; w: number; h: number; r: number };

const BlackCard: React.FC<{ f: number; t: number; L: Layout3; lang: Lang; FALL: { mass: number; stiffness: number; damping: number } }> = ({ f, t, L, lang, FALL }) => {
  const E = L.end;
  const Sw = L.win.S;
  const cardP = sp2(f, T.fall, GROW) - sp2(f, T.ret, SHRINK);
  if (cardP <= 0.0005) return null;
  // Trois rectangles : A = la notch repliée, B = la fenêtre, C = la carte du nom.
  const A: Rect = { w: 197 * L.S, h: NOTCH_H * L.S, y: 0, x: L.cx - (197 * L.S) / 2, r: 9 * L.S };
  const B: Rect = { w: WINDOW_W * Sw, h: WINDOW_H * Sw, y: L.win.top, x: L.cx - (WINDOW_W * Sw) / 2, r: 14 * Sw };
  const Z: Rect = { w: E.cardW, h: E.cardH, y: E.top, x: L.cx - E.cardW / 2, r: E.cardH / 2 };
  const s1 = sp2(f, T.fall, GROW);
  const s2 = sp2(f, T.pill, SHRINK);
  const s3 = sp2(f, T.ret, SHRINK);
  const y1 = sp2(f, T.fall, FALL);
  const y2 = sp2(f, T.pill, FALL);
  const y3 = sp2(f, T.ret, FALL);
  const mixR = (k: "x" | "y" | "w" | "h" | "r", a1: number, a2: number, a3: number) => A[k] + (B[k] - A[k]) * a1 + (Z[k] - B[k]) * a2 - (Z[k] - A[k]) * a3;
  const w = mixR("w", s1, s2, s3);
  const h = mixR("h", s1, s2, s3);
  const top = mixR("y", y1, y2, y3);
  const r = Math.min(h / 2, mixR("r", s1, s2, s3));
  const winOp = R(f, T.fall + 0.2, T.fall + 0.34) * (1 - R(f, T.pill, T.pill + 0.1));
  const textIn = R(f, T.pillText, T.pillText + 0.16) * (1 - R(f, T.ret - 0.05, T.ret + 0.05));
  const shadow = "0 22px 30px rgba(0,0,0,0.22), 0 5px 8px rgba(0,0,0,0.2), 0 34px 44px rgba(0,0,0,0.07)";
  const chosenP = R(f, T.profile, T.profile + 0.14);
  return (
    <div style={{ position: "absolute", left: L.cx - w / 2, top, width: w, height: h, borderRadius: r, background: "#000", boxShadow: shadow, opacity: Math.min(1, cardP * 25), overflow: "hidden" }}>
      {winOp > 0.01 && (
        <div style={{ position: "absolute", left: (w - WINDOW_W * Sw) / 2, top: 0, width: WINDOW_W, height: WINDOW_H, transform: `scale(${Sw})`, transformOrigin: "0 0", opacity: winOp, filter: winOp < 1 ? `blur(${(1 - winOp) * 6}px)` : undefined }}>
          <SetupWindow appName={APP.name} chosen={t >= T.profile ? "creative" : null} chosenP={chosenP} hot={t >= T.profile - 0.25 && t < T.profile ? "creative" : null} />
        </div>
      )}
      {textIn > 0.01 && (
        <div style={{ position: "absolute", inset: 0, display: "flex", alignItems: "center", justifyContent: "center", gap: E.cardH * 0.2, opacity: textIn, filter: textIn < 1 ? `blur(${(1 - textIn) * 8}px)` : undefined, fontFamily: FONT.ui, color: "#fff", whiteSpace: "nowrap" }}>
          {APP.icon === "spark" ? <Spark size={E.cardH * 0.4} color={C.accent} /> : <NotchGlyph size={E.cardH * 0.4} color={C.accent} />}
          <div>
            <div style={{ fontSize: E.title, fontWeight: 700, letterSpacing: "-0.025em", lineHeight: 1.05 }}>{APP.name}</div>
            <div style={{ fontSize: E.caption, fontWeight: 400, color: "rgba(255,255,255,0.55)", marginTop: E.cardH * 0.04, letterSpacing: "-0.01em" }}>{lang === "fr" ? APP.tagline[1] : APP.tagline[0]}</div>
          </div>
        </div>
      )}
    </div>
  );
};

// ramp2 prend la frame en premier : petit alias pour BlackCard, qui n'a pas `R`.
function R(f: number, a: number, b: number, easing: (t: number) => number = outExpo) {
  return ramp2(f, a, b, 0, 1, easing);
}

const Legal: React.FC<{ f: number; t: number; L: Layout3; lang: Lang }> = ({ f, t, L, lang }) => {
  const e = L.end;
  const legalIn = R(f, T.link + 0.2, T.link + 0.4) * (1 - R(f, T.ret - 0.05, T.ret + 0.05));
  if (legalIn <= 0.001) return null;
  const pick = (p: [string, string]) => (lang === "fr" ? p[1] : p[0]);
  return (
    <div style={{ position: "absolute", left: 0, right: 0, top: e.legalY, textAlign: "center", fontFamily: FONT.mono, fontSize: e.legal, lineHeight: 1.5, color: "#8A8A84", opacity: legalIn }}>
      <div>{pick(APP.free)}</div>
      {APP.legal.map((line, i) => (
        <div key={i}>{pick(line)}</div>
      ))}
    </div>
  );
};
