import React from "react";
import { C, F, FONT } from "../theme";
import { useT } from "../i18n";
import { Card, NOTCH_W, TabBar, TabId } from "./notch";
import { CheckCircleFill, Hand, TimerIcon, ChevronDown } from "./icons";
import { Check } from "./icons";
import { HostPill } from "./claude";
import {
  Checkmark,
  CircleEmpty,
  CheckFill,
  CodeBracket,
  GraduationCap,
  MailFill,
  MessageFill,
  MusicNote,
  NotchGlyph,
  OpenApp,
  Paintbrush,
  PaperPlane,
  People,
  ReplyArrow,
  SmallChevronRight,
} from "./icons3";

const clamp01 = (n: number) => Math.max(0, Math.min(1, n));
const mix = (a: number, b: number, t: number) => a + (b - a) * t;

// ───────────────────────────── Intercalaires de la notch repliée ─────────────────────────────
// Géométrie et couleurs de EarTabs.swift / EarTabViews.swift (en pt, origine au centre haut de la notch).

const PAD = 7;
const ICON_W = 14;
const GAP = 4;
const CHAR_W = 6.5;
const MAX_TEXT = 38;
const BARS_W = 16;
const REST_R = 6;
const CARD_R = 14;
export const CARD_W = 236;

export type IdxTab = {
  id: string;
  icon: React.ReactNode;
  /** Information courte (« 24:59 ») ; le nombre de caractères fixe la largeur. */
  text?: React.ReactNode;
  chars?: number;
  bars?: boolean;
  accent: string;
  /** Apparition (0 à 1) de l'intercalaire. */
  appear?: number;
};

const info = (t: IdxTab) => (t.bars ? BARS_W : t.chars ? Math.min(t.chars * CHAR_W, MAX_TEXT) : 0);
const restWidth = (t: IdxTab) => 2 * PAD + ICON_W + (info(t) > 0 ? GAP + info(t) : 0);

export type IdxItem = { tab: IdxTab; side: "left" | "right"; rank: number; inner: number; width: number; height: number };

/** Répartition de EarTabs.distribute : le plus prioritaire à gauche contre la notch, le suivant à droite, etc. */
export function layoutIdx(tabs: IdxTab[]): IdxItem[] {
  const left: IdxTab[] = [];
  const right: IdxTab[] = [];
  tabs.forEach((t, i) => (i % 2 === 0 ? left : right).push(t));
  const place = (arr: IdxTab[], side: "left" | "right"): IdxItem[] => {
    let inner = NOTCH_W / 2;
    return arr.map((tab, rank) => {
      const width = restWidth(tab);
      const it = { tab, side, rank, inner, width, height: 32 - 3 * (rank + 1) };
      inner += width;
      return it;
    });
  };
  return [...place(left, "left"), ...place(right, "right")];
}

const EqBars: React.FC<{ frame: number; color: string }> = ({ frame, color }) => (
  <div style={{ display: "flex", gap: 2, alignItems: "center", height: 12, width: BARS_W, justifyContent: "center" }}>
    {[0, 1, 2, 3].map((i) => (
      <div key={i} style={{ width: 2, borderRadius: 1, background: color, height: 3 + 8 * Math.abs(Math.sin(frame / 5 + i * 1.3)) }} />
    ))}
  </div>
);

/** « 2·2 » : sessions, sous-agents en orange. */
export const ClaudeCount: React.FC<{ a: number | string; b?: number | string }> = ({ a, b }) => (
  <span style={{ fontSize: F(11), fontWeight: 600, fontVariantNumeric: "tabular-nums" }}>
    <span style={{ color: "rgba(255,255,255,0.85)" }}>{a}</span>
    {b !== undefined && (
      <>
        <span style={{ color: C.secondary }}>·</span>
        <span style={{ color: C.accent }}>{b}</span>
      </>
    )}
  </span>
);

const InfoText: React.FC<{ children: React.ReactNode }> = ({ children }) => (
  <span style={{ fontSize: F(11), fontWeight: 600, color: "rgba(255,255,255,0.85)", fontVariantNumeric: "tabular-nums", whiteSpace: "nowrap" }}>{children}</span>
);

export const idxTabs = {
  claude: (a: { alert: boolean; done?: boolean; sessions: number; agents?: number; appear?: number }): IdxTab => ({
    id: "claude",
    icon: a.alert ? <Hand size={13} color={C.amber} /> : <CheckCircleFill size={13} color={C.green} />,
    text: <ClaudeCount a={a.sessions} b={a.agents} />,
    chars: a.agents !== undefined ? 3 : 1,
    accent: C.accent,
    appear: a.appear,
  }),
  timer: (text: string, appear?: number): IdxTab => ({ id: "timer", icon: <TimerIcon size={13} color="#F5B83D" />, text: <InfoText>{text}</InfoText>, chars: text.length, accent: "#F5B83D", appear }),
  media: (frame: number, appear?: number): IdxTab => ({ id: "media", icon: <MusicNote size={13} color="#FB7185" />, bars: true, text: <EqBars frame={frame} color="#FB7185" />, accent: "#FB7185", appear }),
  mail: (n: number, appear?: number): IdxTab => ({ id: "mail", icon: <MailFill size={14} color="#60A5FA" />, text: <InfoText>{n}</InfoText>, chars: String(n).length, accent: "#60A5FA", appear }),
  messages: (n: number, appear?: number): IdxTab => ({ id: "messages", icon: <MessageFill size={14} color="#4ADE80" />, text: <InfoText>{n}</InfoText>, chars: String(n).length, accent: "#4ADE80", appear }),
};

const shapeRadius = (side: "left" | "right", outer: number, inner: number) =>
  side === "left" ? `0 0 ${inner}px ${outer}px` : `0 0 ${outer}px ${inner}px`;

/**
 * Intercalaires de part et d'autre de la notch. `unfold` : l'intercalaire survolé grandit en carte (largeur 236, rayon 14),
 * son bord intérieur ne bouge pas. `fade` : voile global (le panneau déplié les remplace).
 */
export const IndexTabs: React.FC<{
  tabs: IdxTab[];
  fade?: number;
  unfold?: { id: string; p: number; title: string; detail: React.ReactNode; detailH: number };
}> = ({ tabs, fade = 1, unfold }) => {
  const items = layoutIdx(tabs);
  return (
    <div style={{ position: "absolute", left: 0, top: 0, opacity: fade, fontFamily: FONT.ui }}>
      {items.map((it) => {
        const open = unfold && unfold.id === it.tab.id ? unfold.p : 0;
        const appear = it.tab.appear ?? 1;
        if (appear <= 0.001) return null;
        const cardH = unfold && unfold.id === it.tab.id ? 32 + unfold.detailH + 10 : 0;
        const w = mix(it.width, CARD_W, open);
        const h = mix(it.height, cardH, open);
        // Le prolongement sous la notch (12 pt contre elle, 2 pt entre intercalaires) évite un filet clair à la jointure.
        const ov = (it.rank === 0 ? 12 : 2) * (1 - clamp01(open * 6));
        const x = it.side === "left" ? -it.inner - w : it.inner - ov;
        const restOp = 1 - clamp01(open * 4);
        return (
          <div
            key={it.tab.id}
            style={{
              position: "absolute",
              left: x,
              top: 0,
              width: w + ov,
              height: h,
              background: "#000",
              borderRadius: shapeRadius(it.side, mix(REST_R, CARD_R, open), mix(0, CARD_R, open)),
              overflow: "hidden",
              opacity: appear,
              transform: appear < 1 ? `translateY(${(1 - appear) * -8}px)` : undefined,
              zIndex: open > 0 ? 2 : 1,
            }}
          >
            <div style={{ position: "absolute", left: it.side === "right" ? ov : 0, top: 0, width: it.width, height: it.height, opacity: restOp, display: "flex", alignItems: "center", justifyContent: "center", gap: GAP, padding: `0 ${PAD}px`, boxSizing: "border-box" }}>
              <div style={{ width: ICON_W, display: "flex", justifyContent: "center" }}>{it.tab.icon}</div>
              {it.tab.text}
              <div style={{ position: "absolute", left: PAD + 1, right: PAD + 1, bottom: 2, height: 2, borderRadius: 1, background: it.tab.accent, opacity: 0.9 }} />
            </div>
            {open > 0.02 && unfold && (
              <div style={{ position: "absolute", left: it.side === "left" ? w - CARD_W : ov, top: 0, width: CARD_W, opacity: clamp01((open - 0.3) * 3) }}>
                <div style={{ height: 32, display: "flex", alignItems: "center", gap: 6, padding: "0 12px" }}>
                  <div style={{ width: ICON_W, display: "flex", justifyContent: "center" }}>{it.tab.icon}</div>
                  <span style={{ fontSize: F(12), fontWeight: 600, color: "#fff" }}>{unfold.title}</span>
                  <div style={{ flex: 1 }} />
                  {it.tab.text}
                </div>
                <div style={{ padding: "0 10px" }}>{unfold.detail}</div>
              </div>
            )}
          </div>
        );
      })}
    </div>
  );
};

/** Ligne de résumé d'une session dans l'intercalaire de Claude déployé (42 pt). */
export const SummaryRow: React.FC<{ name: string; status: string; detail?: string; attention?: boolean; width?: number }> = ({ name, status, detail, attention, width = CARD_W - 20 }) => (
  <div style={{ width, height: 42, borderRadius: 12, background: C.card, boxSizing: "border-box", display: "flex", alignItems: "center", gap: 9, padding: "0 10px" }}>
    <div style={{ width: 13, display: "flex", justifyContent: "center" }}>
      {attention ? <Hand size={13} color={C.amber} /> : <div style={{ width: 3, height: 3, borderRadius: 2, background: C.accent }} />}
    </div>
    <div style={{ lineHeight: "16px", minWidth: 0 }}>
      <div style={{ fontSize: F(13.5), fontWeight: 700, color: "#fff" }}>{name}</div>
      <div style={{ fontSize: F(11.5), whiteSpace: "nowrap", overflow: "hidden", textOverflow: "clip" }}>
        <span style={{ color: attention ? C.amber : C.accent, fontWeight: 500 }}>{status}</span>
        {detail && <span style={{ color: "rgba(255,255,255,0.75)" }}> · {detail}</span>}
      </div>
    </div>
  </div>
);

// ───────────────────────────── Onglet Codex ─────────────────────────────

const Model: React.FC = () => <span style={{ fontSize: F(12.5), color: C.secondary }}>gpt-6-astra</span>;

const CapsuleButton: React.FC<{ label: string; tone: "primary" | "danger" | "soft"; press?: number; icon?: React.ReactNode }> = ({ label, tone, press = 0, icon }) => (
  <div
    style={{
      height: 22,
      padding: "0 11px",
      borderRadius: 11,
      background: tone === "primary" ? C.accent : tone === "danger" ? "rgba(248,113,113,0.18)" : "rgba(255,255,255,0.1)",
      color: tone === "danger" ? C.red : "#fff",
      fontSize: F(11),
      fontWeight: 700,
      display: "flex",
      alignItems: "center",
      gap: 4,
      transform: `scale(${1 - 0.07 * press})`,
      filter: press > 0 ? `brightness(${1 + 0.15 * press})` : undefined,
      whiteSpace: "nowrap",
    }}
  >
    {icon}
    {label}
  </div>
);

/** Onglet Codex : une session qui attend, la demande d'approbation (commande, Refuser / Autoriser), une session qui travaille. */
export const CodexTab: React.FC<{ approved?: number; pressAllow?: number; frame?: number }> = ({ approved = 0, pressAllow = 0 }) => {
  const t = useT();
  const cmd = "rm -rf build && swift build -c release";
  const card = (extra: React.CSSProperties = {}): React.CSSProperties => ({ position: "relative", width: 592, borderRadius: 12, background: C.card, boxSizing: "border-box", ...extra });
  const askH = 121 * (1 - approved);
  return (
    <div style={{ position: "absolute", inset: 0 }}>
      <div style={card({ height: 57, boxShadow: approved < 1 ? `inset 0 0 0 1px rgba(245,184,61,${1 - approved})` : undefined })}>
        <div style={{ position: "absolute", left: 13, top: 11, width: 13, display: "flex", justifyContent: "center" }}>
          {approved < 0.5 ? <Hand size={14} color={C.amber} /> : <div style={{ width: 3, height: 3, borderRadius: 2, background: C.accent, marginTop: 6 }} />}
        </div>
        <div style={{ position: "absolute", left: 36, top: 8, height: 20, display: "flex", alignItems: "center", gap: 8 }}>
          <span style={{ fontSize: F(15), fontWeight: 700 }}>api</span>
          <HostPill text="iTerm2" />
          <Model />
        </div>
        <span style={{ position: "absolute", right: 12, top: 11, fontSize: F(13), color: C.secondary }}>0 s</span>
        <div style={{ position: "absolute", left: 12, top: 30, height: 20, display: "flex", alignItems: "center", gap: 8, whiteSpace: "nowrap" }}>
          <span style={{ fontSize: F(13), fontWeight: 600, color: approved < 0.5 ? C.amber : C.accent }}>{approved < 0.5 ? t("Needs your approval", "Attend ton approbation") : "Terminal"}</span>
          <span style={{ fontFamily: FONT.mono, fontSize: F(12), color: "rgba(255,255,255,0.85)" }}>{approved < 0.5 ? cmd : "swift build -c release"}</span>
        </div>
      </div>
      <div style={{ height: askH, marginTop: 8 * (1 - approved), overflow: "hidden", opacity: clamp01(1 - approved * 1.6) }}>
        <div style={card({ height: 121, boxShadow: "inset 0 0 0 1px rgba(245,184,61,0.4)" })}>
          <div style={{ position: "absolute", left: 10, top: 9, display: "flex", alignItems: "center", gap: 7 }}>
            <Hand size={13} color={C.amber} />
            <span style={{ fontSize: F(13), fontWeight: 700 }}>{t("Allow Terminal?", "Autoriser Terminal ?")}</span>
            <span style={{ fontSize: F(12), color: C.secondary }}>{t("Clean rebuild", "Rebuild propre")}</span>
          </div>
          <div style={{ position: "absolute", left: 10, right: 10, top: 32, height: 26, borderRadius: 8, background: "rgba(0,0,0,0.4)", fontFamily: FONT.mono, fontSize: F(12), display: "flex", alignItems: "center", padding: "0 8px", whiteSpace: "nowrap", color: "rgba(255,255,255,0.92)" }}>{cmd}</div>
          <div style={{ position: "absolute", left: 10, top: 64, display: "flex", alignItems: "center", gap: 6, fontSize: F(12), color: C.secondary }}>
            <TimerIcon size={12} />
            {t("No click within 60 s: Codex asks you again in the terminal.", "Sans clic sous 60 s, Codex te le redemande dans le terminal.")}
          </div>
          <div style={{ position: "absolute", right: 10, top: 88, display: "flex", gap: 6 }}>
            <CapsuleButton label={t("In the terminal", "Dans le terminal")} tone="soft" />
            <CapsuleButton label={t("Deny", "Refuser")} tone="danger" />
            <CapsuleButton label={t("Allow", "Autoriser")} tone="primary" press={pressAllow} />
          </div>
        </div>
      </div>
      <div style={card({ height: 57, marginTop: 8 })}>
        <div style={{ position: "absolute", left: 13, top: 11, width: 13, display: "flex", justifyContent: "center", marginTop: 6 }}>
          <div style={{ width: 3, height: 3, borderRadius: 2, background: C.accent }} />
        </div>
        <div style={{ position: "absolute", left: 36, top: 8, height: 20, display: "flex", alignItems: "center", gap: 8 }}>
          <span style={{ fontSize: F(15), fontWeight: 700 }}>mon-app</span>
          <HostPill text="VS Code" />
          <Model />
        </div>
        <span style={{ position: "absolute", right: 12, top: 11, fontSize: F(13), color: C.secondary }}>0 s</span>
        <div style={{ position: "absolute", left: 12, top: 30, height: 20, display: "flex", alignItems: "center", gap: 8, whiteSpace: "nowrap" }}>
          <span style={{ fontSize: F(13), fontWeight: 600, color: C.accent }}>Terminal</span>
          <span style={{ fontFamily: FONT.mono, fontSize: F(12), color: "rgba(255,255,255,0.85)" }}>swift test --parallel</span>
        </div>
      </div>
    </div>
  );
};

// ───────────────────────────── Messages et Mail ─────────────────────────────

type Row = { title: string; time: string; line: string; unread?: boolean; badge?: number; group?: boolean; bold?: boolean; lines?: string[]; sub?: string };

const ListRow: React.FC<{ r: Row; y: number; h: number; hot?: number; selected?: number; reply?: number; width?: number }> = ({ r, y, h, hot = 0, selected = 0, reply = 0, width = 592 }) => {
  const t = useT();
  return (
  <div
    style={{
      position: "absolute",
      left: 0,
      top: y,
      width,
      height: h,
      borderRadius: 12,
      boxSizing: "border-box",
      background: `rgba(255,255,255,${0.05 + 0.05 * hot})`,
    }}
  >
    <div style={{ position: "absolute", inset: 0, borderRadius: 12, background: `rgba(217,119,87,${0.2 * selected})` }} />
    <div style={{ position: "absolute", left: 8, top: r.sub ? 10.5 : 11, width: 7, height: 7, borderRadius: 4, background: r.unread ? C.accent : "transparent" }} />
    <div style={{ position: "absolute", left: 23, right: 8, top: r.sub ? 4 : 6, lineHeight: 1.2 }}>
      <div style={{ display: "flex", alignItems: "center", gap: 5, height: r.sub ? 20 : 17 }}>
        {r.group && <People size={11} color={C.secondary} />}
        <span style={{ fontSize: F(12.5), fontWeight: r.unread || r.bold ? 600 : 500, color: "#fff", whiteSpace: "nowrap" }}>{r.title}</span>
        <div style={{ flex: 1 }} />
        <span style={{ fontSize: F(10.5), color: C.secondary, opacity: 1 - reply, marginRight: r.badge ? 26 : 0 }}>{r.time}</span>
      </div>
      <div style={{ fontSize: F(11.5), fontWeight: r.sub ? (r.unread ? 500 : 400) : 400, color: r.unread ? "rgba(255,255,255,0.9)" : C.secondary, whiteSpace: "nowrap", marginTop: 1 }}>{r.line}</div>
      {r.lines && (
        <div style={{ fontSize: F(11), color: "rgba(255,255,255,0.4)", lineHeight: "14px", marginTop: 1 }}>
          {r.lines.map((l, i) => (
            <div key={i} style={{ whiteSpace: "nowrap" }}>{l}</div>
          ))}
        </div>
      )}
    </div>
    {r.badge ? (
      <div style={{ position: "absolute", right: 8, top: 8, minWidth: 18, height: 16, padding: "0 6px", boxSizing: "border-box", borderRadius: 8, background: C.accent, color: "#000", fontSize: F(10), fontWeight: 700, display: "flex", alignItems: "center", justifyContent: "center" }}>{r.badge}</div>
    ) : null}
    {reply > 0 && (
      <div style={{ position: "absolute", right: 6, top: 3, opacity: reply, transform: `scale(${0.92 + 0.08 * reply})`, transformOrigin: "100% 0" }}>
        <div style={{ height: 22, padding: "0 10px", borderRadius: 11, background: "rgba(217,119,87,0.16)", color: C.accent, display: "flex", alignItems: "center", gap: 4, fontSize: F(11), fontWeight: 700 }}>
          <ReplyArrow size={11} color={C.accent} />
          {t("Reply", "Répondre")}
        </div>
      </div>
    )}
  </div>
  );
};

/** Champ de réponse sous une ligne : texte (frappé), Envoyer, Ouvrir dans l'app. */
const ReplyBar: React.FC<{ y: number; placeholder: string; text: string; caret: boolean; sendLabel?: string; sendPress?: number; sent?: boolean }> = ({ y, placeholder, text, caret, sendLabel, sendPress = 0, sent }) => {
  const can = text.length > 0 && !sent;
  return (
    <div style={{ position: "absolute", left: 4, right: 4, top: y, height: 26, display: "flex", alignItems: "center", gap: 6 }}>
      <div style={{ flex: 1, height: 26, borderRadius: 12, background: "rgba(255,255,255,0.08)", boxSizing: "border-box", padding: "0 8px", display: "flex", alignItems: "center", fontSize: F(12), color: text ? "#fff" : "rgba(255,255,255,0.45)", whiteSpace: "nowrap", overflow: "hidden" }}>
        {sent ? placeholder : text || placeholder}
        {caret && !sent && <span style={{ width: 1.5, height: 13, background: C.accent, marginLeft: 1 }} />}
      </div>
      {sendLabel ? (
        <div style={{ opacity: can ? 1 : 0.45, transform: `scale(${1 - 0.07 * sendPress})` }}>
          <div style={{ height: 22, padding: "0 11px", borderRadius: 11, background: C.accent, color: "#fff", display: "flex", alignItems: "center", gap: 4, fontSize: F(11), fontWeight: 700 }}>
            <PaperPlane size={11} color="#fff" />
            {sendLabel}
          </div>
        </div>
      ) : (
        <div style={{ width: 22, height: 22, display: "flex", alignItems: "center", justifyContent: "center", transform: `scale(${1 - 0.1 * sendPress})` }}>
          <PaperPlane size={14} color={can ? C.accent : "rgba(255,255,255,0.3)"} />
        </div>
      )}
      <div style={{ width: 22, height: 22, display: "flex", alignItems: "center", justifyContent: "center" }}>
        <OpenApp size={13} color="rgba(255,255,255,0.75)" />
      </div>
    </div>
  );
};

export const MessagesTab: React.FC<{ hot?: number; replying?: number; typed?: number; sent?: number; sendPress?: number; frame?: number; rowsIn?: (i: number) => number }> = ({ hot = 0, replying = 0, typed = 0, sent = 0, sendPress = 0, frame = 0, rowsIn = () => 1 }) => {
  const t = useT();
  const rows: Row[] = [
    { title: "Camille Martin", time: t("2 min ago", "il y a 2 min"), line: t("Meet at 7 pm in front of the cinema?", "On se retrouve à 19 h devant le cinéma ?"), unread: true, badge: 2 },
    { title: t("Ski weekend", "Week-end ski"), time: t("39 min ago", "il y a 39 min"), line: t("Weekend photo", "Photo du week-end"), unread: true, group: true },
    { title: "Alex Durand", time: t("3 h ago", "il y a 3 h"), line: t("You: Thanks for the help!", "Vous : Merci pour le coup de main !") },
    { title: "+15550103", time: t("2 days ago", "avant-hier"), line: t("Your parcel arrives tomorrow.", "Votre colis arrive demain.") },
  ];
  const draft = t("Yes, 7 pm at the entrance!", "Oui, à 19 h devant l'entrée !");
  const text = draft.slice(0, Math.round(draft.length * typed));
  const shift = 30 * replying;
  let y = 0;
  return (
    <div style={{ position: "absolute", inset: 0 }}>
      {rows.map((r, i) => {
        const top = y + (i > 0 ? shift : 0);
        const el = (
          <div key={i} style={{ opacity: rowsIn(i), transform: `translateY(${(1 - rowsIn(i)) * 6}px)` }}>
            <ListRow r={{ ...r, unread: r.unread && !(i === 0 && sent > 0.5) }} y={top} h={42} hot={i === 0 ? Math.max(hot, replying) : 0} selected={i === 0 ? replying : 0} />
          </div>
        );
        y += 45;
        return el;
      })}
      {replying > 0.01 && (
        <div style={{ position: "absolute", left: 0, right: 0, top: 0, opacity: replying }}>
          <ReplyBar y={46} placeholder={sent > 0.5 ? t("Sent", "Envoyé") : t("Reply…", "Répondre…")} text={text} caret={frame % 30 < 18} sendPress={sendPress} sent={sent > 0.5} />
        </div>
      )}
    </div>
  );
};

export const MailTab: React.FC<{ hot?: number; replying?: number; typed?: number; sendPress?: number; sent?: number; frame?: number; rowsIn?: (i: number) => number }> = ({ hot = 0, replying = 0, typed = 0, sendPress = 0, sent = 0, frame = 0, rowsIn = () => 1 }) => {
  const t = useT();
  const rows: Row[] = [
    {
      title: "Camille Martin",
      time: t("4 min ago", "il y a 4 min"),
      line: t("September invoice", "Facture de septembre"),
      unread: true,
      sub: "1",
      lines: [t("Hi Nicolas, here is this month's invoice, with the detail of hours", "Bonjour Nicolas, voici la facture du mois, avec le détail des heures"), t("and travel. Tell me if everything is fine.", "et des déplacements. Dis-moi si tout te va.")],
    },
    {
      title: "Alex Durand",
      time: t("24 min ago", "il y a 24 min"),
      line: t("Thursday 2 pm meeting: agenda and documents to reread", "Réunion jeudi 14 h : ordre du jour et documents à relire"),
      sub: "1",
      lines: [t("Hi, sending the agenda. Please reread both documents before", "Salut, je t'envoie l'ordre du jour. Pense à relire les deux documents"), t("Thursday, we won't go through them in the meeting.", "avant jeudi, on ne les parcourra pas en séance.")],
    },
    {
      title: t("Online shop", "Boutique en ligne"),
      time: t("1 h ago", "il y a 1 h"),
      line: t("(no subject)", "(sans objet)"),
      sub: "1",
    },
  ];
  const draft = t("Thanks Camille, all good for me. I'll pay this week.", "Merci Camille, c'est bon pour moi. Je te règle cette semaine.");
  const text = draft.slice(0, Math.round(draft.length * typed));
  const heights = [72, 72, 51];
  const shift = 30 * replying;
  let y = 0;
  return (
    <div style={{ position: "absolute", inset: 0 }}>
      {rows.map((r, i) => {
        const top = y + (i > 0 ? shift : 0);
        const el = (
          <div key={i} style={{ opacity: rowsIn(i), transform: `translateY(${(1 - rowsIn(i)) * 6}px)` }}>
            <ListRow
              r={{ ...r, unread: r.unread && !(i === 0 && sent > 0.5) }}
              y={top}
              h={heights[i]}
              hot={i === 0 ? Math.max(hot, replying) : 0}
              selected={i === 0 ? replying : 0}
              reply={i === 0 ? hot * (1 - replying) : 0}
            />
          </div>
        );
        y += heights[i] + 3;
        return el;
      })}
      {replying > 0.01 && (
        <div style={{ position: "absolute", left: 0, right: 0, top: 0, opacity: replying }}>
          <ReplyBar y={74} placeholder={sent > 0.5 ? t("Sent", "Envoyé") : t("Reply to Camille Martin…", "Répondre à Camille Martin…")} text={text} caret={frame % 30 < 18} sendLabel={t("Send", "Envoyer")} sendPress={sendPress} sent={sent > 0.5} />
        </div>
      )}
    </div>
  );
};

// ───────────────────────────── Menus macOS (menu « + », menu « … ») ─────────────────────────────

export type MenuEntry = { label: string; icon?: React.ReactNode; shortcut?: string; check?: boolean; sub?: boolean; disabled?: boolean } | "sep";

/** Menu de macOS en apparence sombre : fond gris, liseré clair, ligne survolée en gris clair. */
export const MacMenu: React.FC<{ entries: MenuEntry[]; width: number; hover?: number; pressed?: boolean; p?: number }> = ({ entries, width, hover = -1, pressed, p = 1 }) => (
  <div
    style={{
      width,
      boxSizing: "border-box",
      padding: 5,
      borderRadius: 10,
      background: "#2A2A2C",
      boxShadow: "inset 0 0 0 1px rgba(255,255,255,0.12), 0 10px 24px rgba(0,0,0,0.4), 0 2px 6px rgba(0,0,0,0.35)",
      fontFamily: FONT.ui,
      opacity: clamp01(p * 2.2),
      transform: `scale(${0.94 + 0.06 * p})`,
      transformOrigin: "100% 0",
      color: "#fff",
    }}
  >
    {entries.map((e, i) =>
      e === "sep" ? (
        <div key={i} style={{ height: 1, margin: "5px 8px", background: "rgba(255,255,255,0.14)" }} />
      ) : (
        <div
          key={i}
          style={{
            height: 22,
            borderRadius: 5,
            display: "flex",
            alignItems: "center",
            gap: 6,
            padding: "0 8px 0 6px",
            fontSize: F(13),
            background: hover === i ? (pressed ? "rgba(255,255,255,0.26)" : "rgba(255,255,255,0.18)") : "transparent",
            color: e.disabled ? "rgba(255,255,255,0.4)" : "#fff",
            whiteSpace: "nowrap",
          }}
        >
          <div style={{ width: 14, display: "flex", justifyContent: "center" }}>{e.check ? <Check size={11} color="#fff" /> : e.icon}</div>
          <span style={{ flex: 1 }}>{e.label}</span>
          {e.shortcut && <span style={{ color: "rgba(255,255,255,0.5)", fontSize: F(12) }}>{e.shortcut}</span>}
          {e.sub && <SmallChevronRight size={9} color="rgba(255,255,255,0.7)" />}
        </div>
      ),
    )}
  </div>
);

/** « + » du mode édition : 27 × 22 pt, sans fond (NotchTabBar.addMenu). */
export const PlainPlus: React.FC<{ press?: number }> = ({ press = 0 }) => (
  <div style={{ width: 27, height: 22, display: "flex", alignItems: "center", justifyContent: "center", color: "rgba(255,255,255,0.85)", transform: `scale(${1 - 0.15 * press})` }}>
    <svg width={11} height={11} viewBox="0 0 24 24" fill="none" stroke="currentColor" strokeWidth={3.6} strokeLinecap="round">
      <path d="M12 3.4 V20.6 M3.4 12 H20.6" />
    </svg>
  </div>
);

// ───────────────────────────── Assistant de configuration ─────────────────────────────

export const WINDOW_W = 520;
export const WINDOW_H = 500;

export type ProfileId = "developer" | "student" | "creative" | "minimal";
const PROFILES: { id: ProfileId; icon: (c: string) => React.ReactNode; en: string; fr: string; tabs: TabId[] }[] = [
  { id: "developer", icon: (c) => <CodeBracket size={15} color={c} />, en: "Developer", fr: "Développeur", tabs: ["claude", "codex", "clip", "timer", "notes"] },
  { id: "student", icon: (c) => <GraduationCap size={16} color={c} />, en: "Student", fr: "Étudiant", tabs: ["player", "timer", "notes", "quick"] },
  { id: "creative", icon: (c) => <Paintbrush size={15} color={c} />, en: "Creative", fr: "Créatif", tabs: ["player", "shelf", "clip"] },
  { id: "minimal", icon: (c) => <svg width={15} height={15} viewBox="0 0 24 24" fill="none" stroke={c} strokeWidth={1.8} strokeLinecap="round" strokeLinejoin="round"><path d="M5 20 C5 9 11 4 20 4 C20 13 15 20 5 20 Z M5 20 L13 11" /></svg>, en: "Minimal", fr: "Minimal", tabs: ["player", "quick"] },
];
const TAB_NAMES: Record<string, [string, string]> = {
  claude: ["Claude", "Claude"],
  codex: ["Codex", "Codex"],
  player: ["Player", "Lecteur"],
  quick: ["Quick Settings", "Réglages rapides"],
  shelf: ["Shelf", "Étagère"],
  clip: ["Clipboard", "Presse-papiers"],
  timer: ["Timer", "Minuteur"],
  notes: ["Quick notes", "Notes rapides"],
};

/** Première étape de l'assistant : bienvenue, quatre profils, les onglets que le profil affichera. `chosen` : fondu de la sélection (0 à 1). */
export const SetupWindow: React.FC<{ appName: string; chosen?: ProfileId | null; chosenP?: number; prevChosen?: ProfileId | null; hot?: ProfileId | null; pressStart?: number }> = ({ appName, chosen = null, chosenP = 1, prevChosen = null, hot = null, pressStart = 0 }) => {
  const t = useT();
  const sel = (id: ProfileId) => (id === chosen ? chosenP : id === prevChosen ? 1 - chosenP : 0);
  const shown = PROFILES.find((p) => p.id === (chosenP > 0.5 ? chosen : prevChosen))?.tabs ?? [];
  const tabNames = shown.map((id) => t(...TAB_NAMES[id])).join(", ");
  return (
    <div style={{ position: "absolute", inset: 0, fontFamily: FONT.ui, color: "#fff" }}>
      <div style={{ position: "absolute", left: 28, right: 28, top: 22, display: "flex", gap: 6 }}>
        {[0, 1, 2, 3].map((i) => (
          <div key={i} style={{ flex: 1, height: 3, borderRadius: 2, background: i === 0 ? C.accent : "rgba(255,255,255,0.15)" }} />
        ))}
      </div>
      <div style={{ position: "absolute", left: 28, top: 44, display: "flex", gap: 14, width: WINDOW_W - 56 }}>
        <div style={{ width: 44, height: 44, borderRadius: 12, background: "rgba(217,119,87,0.16)", display: "flex", alignItems: "center", justifyContent: "center", flex: "none" }}>
          <NotchGlyph size={22} color={C.accent} />
        </div>
        <div>
          <div style={{ fontSize: F(20), fontWeight: 700, letterSpacing: "-0.01em" }}>{t(`Welcome to ${appName}`, `Bienvenue dans ${appName}`)}</div>
          <div style={{ fontSize: F(12.5), color: C.secondary, marginTop: 3, lineHeight: "16px" }}>
            {t("Turns the notch of your Mac into a toolbox: music, calendar, notes, clipboard and more.", "Transforme la notch de ton Mac en panneau d'outils : musique, calendrier, notes, presse-papiers et plus encore.")}
          </div>
        </div>
      </div>
      <div style={{ position: "absolute", left: 28, top: 116, fontSize: F(12), fontWeight: 600 }}>{t("To start, pick a profile (optional)", "Pour commencer, un profil (facultatif)")}</div>
      {PROFILES.map((p, i) => {
        const s = sel(p.id);
        const h = hot === p.id ? 1 : 0;
        return (
          <div
            key={p.id}
            style={{
              position: "absolute",
              left: 28,
              width: WINDOW_W - 56,
              top: 138 + i * 54,
              height: 48,
              borderRadius: 12,
              boxSizing: "border-box",
              background: `rgba(255,255,255,${0.05 + 0.03 * h})`,
              boxShadow: `inset 0 0 0 1px rgba(217,119,87,${0.5 * s})`,
              display: "flex",
              alignItems: "center",
              gap: 12,
              padding: "0 12px",
            }}
          >
            <div style={{ width: 32, height: 32, borderRadius: 9, background: `rgba(${Math.round(mix(255, 217, s))},${Math.round(mix(255, 119, s))},${Math.round(mix(255, 87, s))},${mix(0.06, 0.18, s)})`, display: "flex", alignItems: "center", justifyContent: "center" }}>
              {p.icon(s > 0.5 ? C.accent : "rgba(255,255,255,0.6)")}
            </div>
            <div style={{ lineHeight: "17px" }}>
              <div style={{ fontSize: F(13), fontWeight: 600 }}>{t(p.en, p.fr)}</div>
              <div style={{ fontSize: F(11.5), color: C.secondary, whiteSpace: "nowrap" }}>{p.tabs.map((id) => t(...TAB_NAMES[id])).join(", ")}</div>
            </div>
            <div style={{ flex: 1 }} />
            <div style={{ position: "relative", width: 18, height: 18 }}>
              <div style={{ position: "absolute", inset: 0, opacity: 1 - s }}>
                <CircleEmpty size={18} color="rgba(255,255,255,0.25)" />
              </div>
              <div style={{ position: "absolute", inset: 0, opacity: s, transform: `scale(${0.7 + 0.3 * s})` }}>
                <CheckFill size={18} color={C.accent} />
              </div>
            </div>
          </div>
        );
      })}
      <div style={{ position: "absolute", left: 28, width: WINDOW_W - 56, top: 360, height: 66, borderRadius: 12, background: C.card, boxSizing: "border-box", padding: "9px 12px", opacity: chosen || prevChosen ? 1 : 0.55 }}>
        <div style={{ display: "flex", gap: 2, height: 22 }}>
          <TabBar order={shown.length ? shown : (["player", "quick"] as TabId[])} active={(shown[0] ?? "player") as TabId} count={Math.max(shown.length, 2)} />
        </div>
        <div style={{ fontSize: F(11.5), color: C.secondary, marginTop: 5, whiteSpace: "nowrap" }}>{shown.length ? tabNames : t("Everything stays editable.", "Tout reste modifiable.")}</div>
      </div>
      <div style={{ position: "absolute", left: 28, bottom: 24, fontSize: F(13), color: C.secondary }}>{t("Skip", "Passer")}</div>
      <div style={{ position: "absolute", right: 28, bottom: 18, height: 28, padding: "0 16px", borderRadius: 14, background: "rgba(255,255,255,0.12)", display: "flex", alignItems: "center", fontSize: F(13), fontWeight: 600, transform: `scale(${1 - 0.06 * pressStart})` }}>{t("Start", "Commencer")}</div>
    </div>
  );
};

export { Checkmark, ChevronDown };
