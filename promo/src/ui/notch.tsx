import React from "react";
import { C, F, FONT } from "../theme";
import { useT } from "../i18n";
import { CodeIcon, MailIcon, MessageIcon } from "./icons3";
import {
  Clipboard,
  Ellipsis,
  Hand,
  Minus,
  NoteText,
  PlayCircle,
  Plus,
  Spark,
  Switch2,
  TimerIcon,
  Tray,
} from "./icons";

export type TabId = "claude" | "codex" | "player" | "quick" | "shelf" | "clip" | "timer" | "notes" | "messages" | "mail";
export const DEFAULT_ORDER: TabId[] = ["claude", "player", "quick", "shelf", "clip", "timer", "notes"];

export const TAB_TITLE: Record<TabId, [string, string]> = {
  claude: ["Claude", "Claude"],
  codex: ["Codex", "Codex"],
  player: ["Player", "Lecteur"],
  quick: ["Quick Settings", "Réglages rapides"],
  shelf: ["Shelf", "Étagère"],
  clip: ["Clipboard", "Presse-papiers"],
  timer: ["Timer", "Minuteur"],
  notes: ["Quick notes", "Notes rapides"],
  messages: ["Messages", "Messages"],
  mail: ["Mail", "Mail"],
};

/** Hauteur du contenu de chaque onglet, relevée sur les rendus de l'app (en pt). */
export const TAB_CONTENT_H: Record<TabId, number> = {
  claude: 209,
  codex: 251,
  messages: 211,
  mail: 205,
  player: 150,
  quick: 217,
  shelf: 184,
  clip: 313,
  timer: 170,
  notes: 214,
};

// Géométrie du panneau (ExpandedPanel / NotchShape dans l'app).
export const NOTCH_W = 185;
export const NOTCH_H = 32;
export const HEADER_H = 24;
export const SPACING = 10;
export const PAD = 14;
export const panelHeight = (contentH: number) => NOTCH_H + HEADER_H + SPACING + contentH + PAD;

/** Trace de NotchShape : haut évasé (concave), bas arrondi. */
export function notchPath(w: number, h: number, top: number, bottom: number) {
  const t = Math.max(0, Math.min(top, w / 4, h / 2));
  const b = Math.max(0, Math.min(bottom, (w - 2 * t) / 2, h - t));
  return [
    `M0 0`,
    `Q${t} 0 ${t} ${t}`,
    `L${t} ${h - b}`,
    `Q${t} ${h} ${t + b} ${h}`,
    `L${w - t - b} ${h}`,
    `Q${w - t} ${h} ${w - t} ${h - b}`,
    `L${w - t} ${t}`,
    `Q${w - t} 0 ${w} 0`,
    `Z`,
  ].join(" ");
}

/** La forme noire de la notch, avec son ombre. `children` est placé dans le repère de la forme. */
export const NotchBody: React.FC<{
  w: number;
  h: number;
  top?: number;
  bottom?: number;
  shadow?: boolean;
  fill?: string;
  /** Remplace l'ombre par défaut de l'app (valeur CSS de `filter`). */
  shadowFilter?: string;
  children?: React.ReactNode;
}> = ({ w, h, top = 12, bottom = 24, shadow = true, fill = "#000", shadowFilter, children }) => (
  <div
    style={{
      position: "relative",
      width: w,
      height: h,
      filter: shadow ? (shadowFilter ?? "drop-shadow(0 6px 14px rgba(0,0,0,0.45))") : undefined,
    }}
  >
    <div
      style={{
        position: "absolute",
        inset: 0,
        background: fill,
        clipPath: `path('${notchPath(w, h, top, bottom)}')`,
        overflow: "hidden",
      }}
    >
      {children}
    </div>
  </div>
);

const TabGlyph: React.FC<{ id: TabId; color: string; state?: "idle" | "attention" }> = ({ id, color, state }) => {
  const s = 17;
  switch (id) {
    case "claude":
      return state === "attention" ? <Hand size={15} color={C.amber} /> : <Spark size={15} color={C.accent} />;
    case "codex":
      return <CodeIcon size={s} color={color} />;
    case "messages":
      return <MessageIcon size={s} color={color} />;
    case "mail":
      return <MailIcon size={s} color={color} />;
    case "player":
      return <PlayCircle size={s} color={color} />;
    case "quick":
      return <Switch2 size={s} color={color} />;
    case "shelf":
      return <Tray size={s} color={color} />;
    case "clip":
      return <Clipboard size={s} color={color} />;
    case "timer":
      return <TimerIcon size={s} color={color} />;
    case "notes":
      return <NoteText size={s} color={color} />;
  }
};

/** Barre d'onglets : 7 capsules de 27 × 22 pt. En mode édition les icônes oscillent, `−` apparaît sur chacune. */
export const TabBar: React.FC<{
  order: TabId[];
  active: TabId;
  frame?: number;
  editing?: boolean;
  /** Apparition des badges « − » (0 à 1). */
  badge?: number;
  claudeState?: "idle" | "attention";
  /** Position x (pt) imposée à un onglet : glisser-déposer. Par défaut, rang × 29. */
  xs?: Partial<Record<TabId, number>>;
  opacities?: Partial<Record<TabId, number>>;
  lifted?: TabId | null;
  activeX?: number;
  /** Capsule imposée (pt) : position et largeur, pour l'étirement entre deux onglets. */
  capsule?: { x: number; w: number };
  /** Nombre d'onglets compté pour la largeur de la barre. */
  count?: number;
}> = ({ order, active, frame = 0, editing, badge = 1, claudeState, xs = {}, opacities = {}, lifted, activeX, capsule, count }) => {
  const pitch = 29;
  const idx = order.indexOf(active);
  const capsuleX = activeX ?? (idx < 0 ? 0 : (xs[active] ?? idx * pitch));
  return (
    <div style={{ position: "relative", height: 22, width: (count ?? order.length) * pitch - 2 }}>
      <div
        style={{
          position: "absolute",
          left: capsule?.x ?? capsuleX,
          top: 0,
          width: capsule?.w ?? 27,
          height: 22,
          borderRadius: 11,
          background: "rgba(255,255,255,0.12)",
          opacity: idx < 0 ? 0 : (opacities[active] ?? 1),
        }}
      />
      {order.map((id, i) => {
        const isActive = id === active;
        const wiggle = editing ? Math.sin((frame / 30) * Math.PI * 2 * 3 + i * 1.7) * 2.4 * (i % 2 ? 1 : -1) : 0;
        const x = xs[id] ?? i * pitch;
        const op = opacities[id] ?? 1;
        return (
          <div
            key={id}
            style={{
              position: "absolute",
              left: x,
              top: 0,
              width: 27,
              height: 22,
              display: "flex",
              alignItems: "center",
              justifyContent: "center",
              zIndex: lifted === id ? 2 : 0,
              opacity: op,
              transform: lifted === id ? "scale(1.15)" : op < 1 ? `scale(${0.6 + 0.4 * op})` : undefined,
            }}
          >
            <div style={{ transform: `rotate(${wiggle}deg)` }}>
              <TabGlyph
                id={id}
                state={claudeState}
                color={isActive ? "#fff" : editing ? "rgba(255,255,255,0.75)" : "rgba(255,255,255,0.5)"}
              />
            </div>
            {editing && order.length > 1 && badge > 0 && (
              <div
                style={{
                  position: "absolute",
                  left: -3,
                  top: -4,
                  width: 12,
                  height: 12,
                  borderRadius: 6,
                  background: "rgba(255,255,255,0.9)",
                  display: "flex",
                  alignItems: "center",
                  justifyContent: "center",
                  transform: `scale(${badge})`,
                }}
              >
                <Minus size={7} color="#000" />
              </div>
            )}
          </div>
        );
      })}
    </div>
  );
};

/** « … » du menu de la notch. */
export const MoreButton: React.FC = () => (
  <div style={{ width: 22, height: 22, display: "flex", alignItems: "center", justifyContent: "center", color: "#fff" }}>
    <Ellipsis size={14} />
  </div>
);

export const AddButton: React.FC = () => (
  <div
    style={{
      width: 20,
      height: 20,
      borderRadius: 10,
      background: "rgba(255,255,255,0.12)",
      display: "flex",
      alignItems: "center",
      justifyContent: "center",
      color: "#fff",
      marginLeft: 4,
    }}
  >
    <Plus size={10} />
  </div>
);

/** Pastille de l'en-tête (CLI, Desktop). */
export const StatusPill: React.FC<{ text: string; on?: boolean }> = ({ text, on }) => (
  <div
    style={{
      height: 22,
      padding: "0 10px",
      borderRadius: 11,
      background: "rgba(255,255,255,0.08)",
      display: "flex",
      alignItems: "center",
      gap: 5,
      fontFamily: FONT.ui,
      fontSize: F(11),
      fontWeight: 600,
      color: on ? "#fff" : "rgba(255,255,255,0.6)",
    }}
  >
    {text}
    <span style={{ width: 6, height: 6, borderRadius: 3, background: on ? C.green : "rgba(255,255,255,0.35)" }} />
  </div>
);

/** « OK » : prend la place du menu « … » en mode édition des onglets. */
export const OkButton: React.FC<{ press?: number }> = ({ press = 0 }) => {
  const t = useT();
  return (
    <div
      style={{
        height: 20,
        padding: "0 12px",
        borderRadius: 10,
        background: C.accent,
        color: "#000",
        fontSize: F(12),
        fontWeight: 600,
        display: "flex",
        alignItems: "center",
        transform: `scale(${1 - 0.08 * press})`,
      }}
    >
      {t("Done", "OK")}
    </div>
  );
};

/**
 * Contenu du panneau déplié, à sa largeur finale : en-tête (onglets, titre, accessoire, « … ») puis contenu.
 * Dimensions en pt ; `NotchBody` le découpe pendant l'ouverture.
 */
export const PanelInner: React.FC<{
  tab: TabId;
  order?: TabId[];
  width?: number;
  contentH?: number;
  frame?: number;
  editing?: boolean;
  claudeState?: "idle" | "attention";
  accessory?: React.ReactNode;
  hideTitle?: boolean;
  tabBarProps?: Partial<React.ComponentProps<typeof TabBar>>;
  titleOpacity?: number;
  contentOpacity?: number;
  okPress?: number;
  titleTab?: TabId;
  /** Remplace le bouton « + » du mode édition (par défaut, celui de la v1). */
  addSlot?: React.ReactNode;
  children?: React.ReactNode;
}> = ({
  tab,
  order = DEFAULT_ORDER,
  width = 620,
  contentH,
  frame = 0,
  editing,
  claudeState,
  accessory,
  hideTitle,
  tabBarProps,
  titleOpacity = 1,
  contentOpacity = 1,
  okPress = 0,
  titleTab,
  addSlot,
  children,
}) => {
  const t = useT();
  const ch = contentH ?? TAB_CONTENT_H[tab];
  const [en, fr] = TAB_TITLE[titleTab ?? tab];
  return (
    <>
      <div
        style={{
          position: "absolute",
          left: 12 + PAD,
          width: width - 2 * PAD,
          top: NOTCH_H,
          height: HEADER_H,
          display: "flex",
          alignItems: "center",
          fontFamily: FONT.ui,
        }}
      >
        <TabBar order={order} active={tab} frame={frame} editing={editing} claudeState={claudeState} {...tabBarProps} />
        {editing && (addSlot ?? <AddButton />)}
        {!hideTitle && !editing && (
          <div
            style={{
              marginLeft: 6,
              fontSize: F(12),
              fontWeight: 600,
              color: "#fff",
              whiteSpace: "nowrap",
              opacity: titleOpacity,
            }}
          >
            {t(en, fr)}
          </div>
        )}
        <div style={{ flex: 1 }} />
        <div style={{ display: "flex", alignItems: "center", gap: 6 }}>
          {editing ? <OkButton press={okPress} /> : <>{accessory}<MoreButton /></>}
        </div>
      </div>
      <div
        style={{
          position: "absolute",
          left: 12 + PAD,
          width: width - 2 * PAD,
          top: NOTCH_H + HEADER_H + SPACING,
          height: ch,
          opacity: contentOpacity,
          fontFamily: FONT.ui,
          color: "#fff",
        }}
      >
        {children}
      </div>
    </>
  );
};

/** Panneau déplié complet (forme + contenu), pour les rendus de contrôle. */
export const Panel: React.FC<React.ComponentProps<typeof PanelInner> & { shadow?: boolean }> = ({ shadow = true, ...p }) => {
  const width = p.width ?? 620;
  const ch = p.contentH ?? TAB_CONTENT_H[p.tab];
  return (
    <NotchBody w={width + 24} h={panelHeight(ch)} shadow={shadow}>
      <PanelInner {...p} />
    </NotchBody>
  );
};

/** Carte arrondie des onglets (blanc à 5 %). */
export const Card: React.FC<{
  style?: React.CSSProperties;
  children?: React.ReactNode;
  radius?: number;
}> = ({ style, children, radius = 14 }) => (
  <div style={{ background: C.card, borderRadius: radius, ...style }}>{children}</div>
);
