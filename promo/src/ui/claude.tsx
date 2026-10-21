import React from "react";
import { C, F, FONT } from "../theme";
import { useT } from "../i18n";
import { ArrowUp, CheckCircleFill, ChevronDown, Hand, XCircleFill } from "./icons";
import { NotchBody, Card } from "./notch";

const mono = FONT.mono;

export const HostPill: React.FC<{ text: string; tone?: "plain" | "agents" }> = ({ text, tone = "plain" }) => (
  <div
    style={{
      height: 16.5,
      padding: "0 8px",
      borderRadius: 8.25,
      background: tone === "agents" ? "rgba(217,119,87,0.18)" : "rgba(255,255,255,0.08)",
      color: tone === "agents" ? C.accent : "rgba(255,255,255,0.75)",
      fontSize: F(11),
      fontWeight: 600,
      display: "flex",
      alignItems: "center",
      whiteSpace: "nowrap",
    }}
  >
    {text}
  </div>
);

export const Spinner: React.FC<{ frame: number; size?: number; color?: string }> = ({ frame, size = 12, color = C.accent }) => (
  <svg width={size} height={size} viewBox="-10 -10 20 20" style={{ display: "block", transform: `rotate(${frame * 14}deg)` }}>
    <circle r={7.4} fill="none" stroke="rgba(217,119,87,0.25)" strokeWidth={2.4} />
    <path d="M0 -7.4 A7.4 7.4 0 0 1 7.4 0" fill="none" stroke={color} strokeWidth={2.4} strokeLinecap="round" />
  </svg>
);

export type CardKind = "attention" | "running" | "done" | "thinking";

/** Carte d'une session (onglet Claude). Les mesures viennent des rendus de l'app. */
export const SessionCard: React.FC<{
  kind: CardKind;
  name: string;
  host?: string;
  agents?: string;
  time: string;
  status: string;
  detail?: string;
  detailMono?: boolean;
  task?: { done: number; total: number; title: string };
  outline?: number;
  chatButton?: number;
  frame?: number;
  width?: number;
  children?: React.ReactNode;
  style?: React.CSSProperties;
}> = ({ kind, name, host = "iTerm2", agents, time, status, detail, detailMono = true, task, outline = 0, chatButton = 0, frame = 0, width = 592, children, style }) => {
  const statusColor = kind === "attention" ? C.amber : kind === "done" ? C.green : C.accent;
  const h = task ? 77.5 : 57;
  const t = useT();
  return (
    <Card style={{ position: "relative", width, height: h, ...style }} radius={12}>
      {outline > 0 && (
        <div style={{ position: "absolute", inset: 0, borderRadius: 12, boxShadow: `inset 0 0 0 1px rgba(245,184,61,${outline})`, background: `rgba(245,184,61,${0.02 * outline})` }} />
      )}
      <div style={{ position: "absolute", left: 13, top: 11, width: 13, height: 15, display: "flex", alignItems: "center", justifyContent: "center" }}>
        {kind === "attention" ? (
          <Hand size={14} color={C.amber} />
        ) : kind === "done" ? (
          <CheckCircleFill size={13} color={C.green} />
        ) : (
          <div style={{ width: 3, height: 3, borderRadius: 2, background: C.accent }} />
        )}
      </div>
      <div style={{ position: "absolute", left: 36, top: 8, height: 20, display: "flex", alignItems: "center", gap: 8 }}>
        <span style={{ fontSize: F(15), fontWeight: 700, color: "#fff" }}>{name}</span>
        <HostPill text={host} />
        {agents && <HostPill text={agents} tone="agents" />}
      </div>
      <div style={{ position: "absolute", right: 12, top: 8, height: 20, display: "flex", alignItems: "center", gap: 8 }}>
        {chatButton > 0 && (
          <div
            style={{
              height: 22,
              padding: "0 10px",
              borderRadius: 11,
              background: `rgba(217,119,87,${chatButton})`,
              color: "#fff",
              opacity: Math.min(1, chatButton * 1.6),
              fontSize: F(11),
              fontWeight: 600,
              display: "flex",
              alignItems: "center",
              transform: `scale(${0.9 + 0.1 * chatButton})`,
            }}
          >
            {t("Chat", "Converser")}
          </div>
        )}
        <span style={{ fontSize: F(13), color: C.secondary }}>{time}</span>
      </div>
      <div style={{ position: "absolute", left: 12, top: 30, height: 20, display: "flex", alignItems: "center", gap: 8, whiteSpace: "nowrap" }}>
        <span style={{ fontSize: F(13), fontWeight: 600, color: statusColor }}>{status}</span>
        {detail && (
          <span style={{ fontFamily: detailMono ? mono : FONT.ui, fontSize: F(detailMono ? 12 : 13), color: "rgba(255,255,255,0.85)" }}>{detail}</span>
        )}
      </div>
      {task && (
        <div style={{ position: "absolute", left: 12, right: 12, top: 52, height: 17, display: "flex", alignItems: "center" }}>
          <div style={{ width: 72, height: 3.5, borderRadius: 2, background: "rgba(255,255,255,0.15)" }}>
            <div style={{ width: `${(task.done / task.total) * 100}%`, height: 3.5, borderRadius: 2, background: C.green }} />
          </div>
          <span style={{ marginLeft: 9, fontSize: F(13), fontWeight: 700 }}>
            {task.done}/{task.total}
          </span>
          <span style={{ marginLeft: 9, fontSize: F(13), color: C.secondary }}>{task.title}</span>
          <div style={{ flex: 1 }} />
          <ChevronDown size={11} color={C.secondary} />
        </div>
      )}
      {children}
    </Card>
  );
};

const Button: React.FC<{ label: string; kind: "danger" | "primary" | "secondary"; press?: number }> = ({ label, kind, press = 0 }) => {
  const bg =
    kind === "primary" ? C.accent : kind === "danger" ? "rgba(248,113,113,0.18)" : "rgba(255,255,255,0.1)";
  const color = kind === "danger" ? C.red : "#fff";
  return (
    <div
      style={{
        height: 22,
        padding: "0 11px",
        borderRadius: 11,
        background: bg,
        color,
        fontSize: F(11),
        fontWeight: 700,
        display: "flex",
        alignItems: "center",
        transform: `scale(${1 - 0.07 * press})`,
        filter: press > 0 ? `brightness(${1 + 0.15 * press})` : undefined,
      }}
    >
      {label}
    </div>
  );
};
export { Button as ReplyButton };

/** Carte « Autoriser Terminal ? » : la commande demandée, un motif facultatif, Refuser / Autoriser. */
export const PermissionReply: React.FC<{ command: string; reason: string; pressAllow?: number; width?: number }> = ({
  command,
  reason,
  pressAllow = 0,
  width = 592,
}) => {
  const t = useT();
  return (
    <div
      style={{
        width,
        height: 101,
        borderRadius: 12,
        background: C.card,
        boxShadow: "inset 0 0 0 1px rgba(245,184,61,0.4)",
        position: "relative",
      }}
    >
      <div style={{ position: "absolute", left: 10, top: 9, display: "flex", alignItems: "center", gap: 7 }}>
        <Hand size={13} color={C.amber} />
        <span style={{ fontSize: F(13), fontWeight: 700 }}>{t("Allow Terminal?", "Autoriser Terminal ?")}</span>
        <span style={{ fontSize: F(12), color: C.secondary }}>{reason}</span>
      </div>
      <div
        style={{
          position: "absolute",
          left: 10,
          right: 10,
          top: 32,
          height: 26,
          borderRadius: 8,
          background: "rgba(0,0,0,0.4)",
          fontFamily: mono,
          fontSize: F(12),
          display: "flex",
          alignItems: "center",
          padding: "0 8px",
          color: "rgba(255,255,255,0.92)",
          whiteSpace: "nowrap",
        }}
      >
        {command}
      </div>
      <div style={{ position: "absolute", left: 10, right: 10, top: 66, height: 25, display: "flex", alignItems: "center", gap: 6 }}>
        <div style={{ flex: 1, height: 25, borderRadius: 8, background: "rgba(255,255,255,0.1)", display: "flex", alignItems: "center", padding: "0 8px", fontSize: F(12), color: "rgba(255,255,255,0.45)" }}>
          {t("Why deny? (optional)", "Pourquoi refuser ? (facultatif)")}
        </div>
        <Button label={t("Deny", "Refuser")} kind="danger" />
        <Button label={t("Allow", "Autoriser")} kind="primary" press={pressAllow} />
      </div>
    </div>
  );
};

const Bubble: React.FC<{ who: "you" | "claude"; text: string; width?: number }> = ({ who, text }) => {
  const t = useT();
  const you = who === "you";
  return (
    <div style={{ display: "flex", flexDirection: "column", alignItems: you ? "flex-end" : "flex-start", gap: 2 }}>
      <span style={{ fontSize: F(9.5), fontWeight: 700, color: C.accent, padding: "0 4px" }}>{you ? t("You", "Toi") : "Claude"}</span>
      <div
        style={{
          padding: "6px 9px",
          borderRadius: 8,
          background: you ? "rgba(217,119,87,0.18)" : "rgba(255,255,255,0.07)",
          fontSize: F(11.5),
          lineHeight: "15px",
          color: "rgba(255,255,255,0.9)",
          maxWidth: 440,
          textAlign: you ? "right" : "left",
        }}
      >
        {text}
      </div>
    </div>
  );
};

/** Zone de conversation : dernières répliques puis champ de message. `typed` : fraction du message écrite. */
export const Conversation: React.FC<{
  said: string;
  you?: string;
  typed?: number;
  sent?: boolean;
  width?: number;
  showYou?: boolean;
  frame?: number;
}> = ({ said, you = "", typed = 0, sent = false, width = 592, showYou = false, frame = 0 }) => {
  const t = useT();
  const text = sent ? "" : you.slice(0, Math.round(you.length * typed));
  const canSend = text.length > 0;
  return (
    <div style={{ width, borderRadius: 12, background: "rgba(255,255,255,0.07)", padding: 8, boxSizing: "border-box", display: "flex", flexDirection: "column", gap: 8 }}>
      <div style={{ display: "flex", flexDirection: "column", gap: 6 }}>
        <Bubble who="claude" text={said} />
        {showYou && <Bubble who="you" text={you} />}
      </div>
      <div style={{ display: "flex", flexDirection: "column", gap: 6 }}>
        <div style={{ display: "flex", alignItems: "center", gap: 6 }}>
          <div style={{ flex: 1, height: 25, borderRadius: 8, background: "rgba(255,255,255,0.1)", display: "flex", alignItems: "center", padding: "0 8px", fontSize: F(12), color: text ? "#fff" : "rgba(255,255,255,0.45)" }}>
            {text || t("Message to Claude…", "Message à Claude…")}
            {text && !sent && frame % 30 < 18 && (
              <span style={{ width: 1.5, height: 13, background: C.accent, marginLeft: 1 }} />
            )}
          </div>
          <div style={{ color: canSend ? C.accent : "rgba(255,255,255,0.25)", width: 19, height: 19, borderRadius: 10, background: "currentColor", display: "flex", alignItems: "center", justifyContent: "center" }}>
            <ArrowUp size={12} color="#000" />
          </div>
          <XCircleFill size={15} color={C.secondary} />
        </div>
        <div style={{ display: "flex", alignItems: "center", gap: 5, fontSize: F(10.5), color: C.secondary, paddingLeft: 2 }}>
          <span style={{ width: 6, height: 6, borderRadius: 3, background: C.green }} />
          {t("Claude will read it right away", "Claude le lira tout de suite")}
        </div>
      </div>
    </div>
  );
};

// ─────────────────────────────── Oreilles (notch repliée) ───────────────────────────────

/** Notch repliée : la forme de l'app avec une oreille de chaque côté (257 × 32 pt par défaut). */
export const Ears: React.FC<{ left?: React.ReactNode; right?: React.ReactNode; w?: number; shadow?: boolean; leftOffset?: number }> = ({
  left,
  right,
  w = 257,
  shadow = false,
}) => (
  <NotchBody w={w} h={32} top={6} bottom={12} shadow={shadow}>
    <div style={{ position: "absolute", left: 6 + 12, top: 0, height: 32, display: "flex", alignItems: "center", fontFamily: FONT.ui }}>
      {left}
    </div>
    <div style={{ position: "absolute", right: 6 + 12, top: 0, height: 32, display: "flex", alignItems: "center", fontFamily: FONT.ui }}>
      {right}
    </div>
  </NotchBody>
);

/** « 2·2 » : sessions actives, sous-agents en cours. */
export const SessionCount: React.FC<{ a: number | string; b: number | string }> = ({ a, b }) => (
  <div style={{ fontSize: F(14), fontWeight: 700, letterSpacing: 0.2 }}>
    <span style={{ color: "rgba(255,255,255,0.88)" }}>{a}</span>
    <span style={{ color: C.secondary }}>·</span>
    <span style={{ color: C.accent }}>{b}</span>
  </div>
);
