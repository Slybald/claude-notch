import React from "react";
import { interpolate } from "remotion";
import { C, F, FONT } from "../theme";
import { useT } from "../i18n";
import {
  Battery,
  Bluetooth,
  Brain,
  ChevronDown,
  ChevronLeft,
  ChevronRight,
  Clipboard as ClipIcon,
  Cup,
  Leaf,
  Link as LinkIcon,
  Lock,
  Moon,
  Pause,
  PlayFill,
  Rewind,
  Forward,
  Pin,
  Scissors,
  Search,
  SkipNext,
  Stop,
  Wifi,
  FolderFill,
} from "./icons";
import { Card } from "./notch";

const mix = (a: number, b: number, t: number) => a + (b - a) * t;
const clamp01 = (n: number) => Math.max(0, Math.min(1, n));

// ───────────────────────────── Réglages rapides ─────────────────────────────

export type QuickState = { wifi: number; bt: number; focus: number; low: number; caf: number };

const Tile: React.FC<{
  title: string;
  sub: string;
  on?: number;
  icon: React.ReactNode;
  lock?: boolean;
  subColor?: string;
}> = ({ title, sub, on = 0, icon, lock, subColor }) => (
  <div
    style={{
      position: "relative",
      width: 192,
      height: 44,
      borderRadius: 12,
      background: C.card,
      boxSizing: "border-box",
      display: "flex",
      alignItems: "center",
      padding: "0 8px",
      gap: 8,
    }}
  >
    <div
      style={{
        position: "absolute",
        inset: 0,
        borderRadius: 12,
        background: `rgba(217,119,87,${0.12 * on})`,
        boxShadow: `inset 0 0 0 1px rgba(217,119,87,${0.55 * on})`,
      }}
    />
    <div
      style={{
        position: "relative",
        width: 28,
        height: 28,
        borderRadius: 14,
        background: `rgb(${Math.round(mix(38, 217, on))},${Math.round(mix(38, 119, on))},${Math.round(mix(38, 87, on))})`,
        display: "flex",
        alignItems: "center",
        justifyContent: "center",
        color: "#fff",
      }}
    >
      {icon}
    </div>
    <div style={{ position: "relative", lineHeight: 1.18, minWidth: 0 }}>
      <div style={{ fontSize: F(13), fontWeight: 600, color: "#fff", whiteSpace: "nowrap" }}>{title}</div>
      <div style={{ fontSize: F(12), fontWeight: 500, color: subColor ?? C.secondary, whiteSpace: "nowrap" }}>{sub}</div>
    </div>
    {lock && (
      <div style={{ position: "absolute", right: 7, top: 5, color: "rgba(255,255,255,0.4)" }}>
        <Lock size={8} />
      </div>
    )}
  </div>
);

const Scene: React.FC<{ title: string; sub: string; icon: React.ReactNode; dim?: boolean; hot?: number }> = ({
  title,
  sub,
  icon,
  dim,
  hot = 0,
}) => (
  <div
    style={{
      position: "relative",
      width: 192,
      height: 42,
      borderRadius: 12,
      background: C.card,
      display: "flex",
      alignItems: "center",
      gap: 8,
      padding: "0 8px 0 11px",
      opacity: dim ? 0.4 : 1,
    }}
  >
    <div
      style={{
        position: "absolute",
        inset: 0,
        borderRadius: 12,
        background: `rgba(217,119,87,${0.12 * hot})`,
        boxShadow: `inset 0 0 0 1px rgba(217,119,87,${0.55 * hot})`,
      }}
    />
    <div style={{ position: "relative", width: 20, display: "flex", justifyContent: "center", color: "#fff" }}>{icon}</div>
    <div style={{ position: "relative", lineHeight: 1.18 }}>
      <div style={{ fontSize: F(13), fontWeight: 600 }}>{title}</div>
      <div style={{ fontSize: F(12), color: C.secondary }}>{sub}</div>
    </div>
  </div>
);

export const QuickTab: React.FC<{ s?: Partial<QuickState>; hours?: 1 | 2 | 0; hot?: Partial<Record<"battery" | "normal" | "present", number>> }> = ({
  s = {},
  hours = 1,
  hot = {},
}) => {
  const t = useT();
  const st: QuickState = { wifi: 1, bt: 1, focus: 0, low: 0, caf: 0, ...s };
  const on = (n: number) => n > 0.5;
  const Pill = ({ label, sel }: { label: string; sel: boolean }) => (
    <div
      style={{
        minWidth: 26,
        padding: "3px 7px",
        borderRadius: 13,
        background: sel ? C.accent : "rgba(255,255,255,0.08)",
        color: "#fff",
        fontSize: F(11),
        fontWeight: 600,
        textAlign: "center",
        boxSizing: "content-box",
        height: 14,
        lineHeight: "14px",
      }}
    >
      {label}
    </div>
  );
  return (
    <div style={{ position: "absolute", inset: 0 }}>
      <div style={{ display: "flex", gap: 8 }}>
        <Tile title="Wi-Fi" sub={on(st.wifi) ? t("Connected", "Connecté") : t("Off", "Désactivé")} on={st.wifi} icon={<Wifi size={15} />} />
        <Tile title="Bluetooth" sub={on(st.bt) ? t("Enabled", "Activé") : t("Off", "Désactivé")} on={st.bt} icon={<Bluetooth size={14} />} />
        <Tile title={t("Focus", "Concentration")} sub={on(st.focus) ? t("On", "Activée") : t("Off", "Désactivé")} on={st.focus} icon={<Moon size={14} />} />
      </div>
      <div style={{ display: "flex", gap: 8, marginTop: 8 }}>
        <Tile title={t("Low Power", "Économie")} sub={on(st.low) ? t("On", "Activée") : t("Off", "Désactivée")} on={st.low} icon={<Leaf size={14} />} lock />
        <Tile title={t("Caffeine", "Caféine")} sub={on(st.caf) ? t("Awake · 1 h", "Éveillé · 1 h") : t("Off", "Désactivée")} on={st.caf} icon={<Cup size={15} />} />
        <Tile title="78 %" sub={t("3 h 47 left", "Il reste 3 h 47")} icon={<Battery size={18} level={0.78} />} />
      </div>
      <div style={{ position: "absolute", left: 2, right: 2, top: 106, height: 22, display: "flex", alignItems: "center", color: C.secondary }}>
        <Cup size={12} />
        <span style={{ marginLeft: 6, fontSize: F(11), fontWeight: 500 }}>{t("Caffeine duration", "Durée de la caféine")}</span>
        <div style={{ flex: 1 }} />
        <div style={{ display: "flex", gap: 6 }}>
          <Pill label="1 h" sel={hours === 1} />
          <Pill label="2 h" sel={hours === 2} />
          <Pill label="∞" sel={hours === 0} />
        </div>
      </div>
      <div style={{ position: "absolute", left: 2, top: 138, fontSize: F(11), fontWeight: 600, color: C.secondary }}>
        {t("Scenes", "Scènes")}
      </div>
      <div style={{ position: "absolute", left: 0, top: 158, display: "flex", gap: 8 }}>
        <Scene title={t("Battery Saver", "Autonomie")} sub={t("Low Power Mode", "Économie d'énergie")} icon={<Leaf size={13} />} hot={hot.battery} />
        <Scene title="Normal" sub={t("Nothing to restore", "Rien à restaurer")} icon={<Rewind size={11} />} dim hot={hot.normal} />
        <Scene title={t("Presentation", "Présentation")} sub={t("Screen on", "Écran allumé")} icon={<PlayFill size={12} />} hot={hot.present} />
      </div>
    </div>
  );
};

// ───────────────────────────── Lecteur + calendrier ─────────────────────────────

const Bars: React.FC<{ frame: number }> = ({ frame }) => (
  <div style={{ display: "flex", gap: 2, alignItems: "center", height: 12 }}>
    {[0, 1, 2, 3].map((i) => (
      <div
        key={i}
        style={{
          width: 2,
          borderRadius: 1,
          background: C.accent,
          height: 3 + 8 * Math.abs(Math.sin(frame / 5 + i * 1.3)),
        }}
      />
    ))}
  </div>
);
export { Bars as EqualizerBars };

export const PlayerTab: React.FC<{ progress?: number; playing?: boolean; frame?: number; day?: number }> = ({
  progress = 0.33,
  playing = true,
  day = 20,
}) => {
  const t = useT();
  const total = 3 * 60 + 50;
  const elapsed = Math.round(total * progress);
  const fmt = (n: number) => `${Math.floor(n / 60)}:${String(n % 60).padStart(2, "0")}`;
  const days = [19, 20, 21, 22, 23, 24, 25];
  const letters = ["M", "T", "W", "T", "F", "S", "S"];
  const lettersFr = ["L", "M", "M", "J", "V", "S", "D"];
  const events: [string, string, string][] = [
    [C.green, t("All day", "Journée"), t("Workshop", "Formation")],
    ["#4C8DFF", "09:00", t("Team sync", "Point d'équipe")],
    [C.accent, "14:30", t("Design review", "Revue de design")],
  ];
  return (
    <div style={{ position: "absolute", inset: 0, display: "flex", gap: 10 }}>
      <Card style={{ width: 314, height: 150, position: "relative" }} radius={12}>
        <div
          style={{
            position: "absolute",
            left: 10,
            top: 10,
            width: 60,
            height: 60,
            borderRadius: 8,
            background: "#DD2DF5",
            display: "flex",
            alignItems: "center",
            justifyContent: "center",
          }}
        >
          <div style={{ width: 30, height: 30, borderRadius: 15, background: "rgba(255,255,255,0.4)" }} />
        </div>
        <div style={{ position: "absolute", left: 82, top: 16, lineHeight: "16.5px" }}>
          <div style={{ fontSize: F(13.5), fontWeight: 700 }}>{t("City Lights", "Lumières de la ville")}</div>
          <div style={{ fontSize: F(12.5), color: C.secondary }}>{t("The Fictives", "Les Fictifs")}</div>
          <div style={{ fontSize: F(11.5), color: C.tertiary, fontWeight: 600 }}>{t("Music", "Musique")}</div>
        </div>
        <div style={{ position: "absolute", left: 10, right: 10, top: 80, height: 14, display: "flex", alignItems: "center", gap: 8 }}>
          <span style={{ width: 34, fontSize: F(11), fontWeight: 600, color: C.secondary, fontVariantNumeric: "tabular-nums" }}>{fmt(elapsed)}</span>
          <div style={{ flex: 1, height: 3.5, borderRadius: 2, background: "rgba(255,255,255,0.15)" }}>
            <div style={{ width: `${progress * 100}%`, height: 3.5, borderRadius: 2, background: C.accent }} />
          </div>
          <span style={{ width: 34, fontSize: F(11), fontWeight: 600, color: C.secondary, textAlign: "right", fontVariantNumeric: "tabular-nums" }}>-{fmt(total - elapsed)}</span>
        </div>
        <div style={{ position: "absolute", left: 0, right: 0, top: 114, display: "flex", justifyContent: "center", alignItems: "center", gap: 48 }}>
          <Rewind size={20} color="#fff" />
          {playing ? <Pause size={20} color="#fff" /> : <PlayFill size={20} color="#fff" />}
          <Forward size={20} color="#fff" />
        </div>
      </Card>
      <Card style={{ width: 268, height: 150, position: "relative" }} radius={12}>
        <div style={{ position: "absolute", left: 10, top: 12, fontSize: F(14), fontWeight: 700 }}>{t("October 2026", "Octobre 2026")}</div>
        <div style={{ position: "absolute", right: 10, top: 14, display: "flex", gap: 20, color: C.secondary }}>
          <ChevronLeft size={11} />
          <ChevronRight size={11} />
        </div>
        <div style={{ position: "absolute", left: 10, right: 10, top: 36, display: "flex", justifyContent: "space-between" }}>
          {days.map((d, i) => (
            <div key={d} style={{ width: 32, textAlign: "center" }}>
              <div style={{ fontSize: F(10), fontWeight: 600, color: C.secondary, height: 14 }}>{t(letters[i], lettersFr[i])}</div>
              <div
                style={{
                  margin: "-1px auto 0",
                  width: 22,
                  height: 22,
                  borderRadius: 11,
                  lineHeight: "22px",
                  fontSize: F(13),
                  fontWeight: 600,
                  background: d === day ? C.accent : "transparent",
                }}
              >
                {d}
              </div>
              <div style={{ height: 4, marginTop: 1, display: "flex", justifyContent: "center" }}>
                {d === day && <div style={{ width: 3, height: 3, borderRadius: 2, background: C.secondary }} />}
              </div>
            </div>
          ))}
        </div>
        <div
          style={{
            position: "absolute",
            left: 10,
            right: 10,
            top: 80,
            height: 64,
            overflow: "hidden",
            WebkitMaskImage: "linear-gradient(to bottom, #000 62%, transparent 100%)",
          }}
        >
          {events.map(([col, when, title], i) => (
            <div key={i} style={{ display: "flex", alignItems: "center", height: 21, gap: 7 }}>
              <div style={{ width: 3, height: 12, borderRadius: 2, background: col }} />
              <span style={{ width: 47, fontSize: F(11), fontWeight: 600, color: C.secondary }}>{when}</span>
              <span style={{ fontSize: F(12) }}>{title}</span>
            </div>
          ))}
        </div>
      </Card>
    </div>
  );
};

// ───────────────────────────── Étagère ─────────────────────────────

export type FileKind = "pdf" | "png" | "jpg" | "md" | "folder" | "zip" | "numbers" | "swift" | "key";

/** Icône de fichier dessinée pour la vidéo : feuille à coin plié et étiquette. */
export const FileGlyph: React.FC<{ kind: FileKind; size?: number }> = ({ kind, size = 1 }) => {
  const w = 30 * size;
  const h = 38 * size;
  if (kind === "folder") {
    return (
      <div style={{ width: 46 * size, height: 34 * size, position: "relative" }}>
        <div style={{ position: "absolute", left: 0, top: 0, width: 20 * size, height: 9 * size, borderRadius: `${3 * size}px ${3 * size}px 0 0`, background: "#4BA8E8" }} />
        <div style={{ position: "absolute", left: 0, top: 4 * size, right: 0, bottom: 0, borderRadius: 4 * size, background: "linear-gradient(#5FC0F5,#3C9BE0)" }} />
      </div>
    );
  }
  if (kind === "png" || kind === "jpg") {
    const bg = kind === "png" ? "linear-gradient(135deg,#17C6E3,#5E8BFF)" : "linear-gradient(135deg,#FF9A2E,#FF4A5E)";
    return <div style={{ width: 46 * size, height: 27 * size, borderRadius: 4 * size, background: bg }} />;
  }
  const label: Record<string, [string, string]> = {
    pdf: ["PDF", "#d0d0d0"],
    md: ["", "#ffffff"],
    zip: ["ZIP", "#d0d0d0"],
    numbers: ["NUMBERS", "#2a9d4b"],
    swift: ["SWIFT", "#F05138"],
    key: ["KEY", "#3d82f0"],
  };
  const [text, accent] = label[kind];
  return (
    <div style={{ width: w, height: h, position: "relative", background: "#f4f4f4", borderRadius: `${3 * size}px ${3 * size}px ${3 * size}px ${3 * size}px`, clipPath: `polygon(0 0, ${w - 9 * size}px 0, ${w}px ${9 * size}px, ${w}px ${h}px, 0 ${h}px)` }}>
      <div style={{ position: "absolute", right: 0, top: 0, width: 9 * size, height: 9 * size, background: "#d4d4d4", clipPath: "polygon(0 0, 100% 100%, 0 100%)" }} />
      {kind === "md" ? (
        <div style={{ position: "absolute", left: 5 * size, top: 12 * size, right: 5 * size }}>
          {[0, 1, 2, 3, 4].map((i) => (
            <div key={i} style={{ height: 1.6 * size, marginBottom: 2.6 * size, width: `${[100, 80, 90, 60, 85][i]}%`, background: ["#00B4D8", "#999", "#e05", "#999", "#4a7"][i], opacity: 0.8 }} />
          ))}
        </div>
      ) : (
        <>
          <div style={{ position: "absolute", left: 6 * size, top: 13 * size, width: 8 * size, height: 8 * size, borderRadius: 2 * size, background: kind === "pdf" || kind === "zip" ? "#bbb" : accent }} />
          <div style={{ position: "absolute", left: 0, right: 0, bottom: 4 * size, textAlign: "center", fontSize: F(5.4) * size, fontWeight: 700, color: "#777", letterSpacing: 0.4 }}>{text}</div>
        </>
      )}
    </div>
  );
};

export const SHELF_ITEMS: { name: string; kind: FileKind }[] = [
  { name: "Report 2026.pdf", kind: "pdf" },
  { name: "Homepage mockup.png", kind: "png" },
  { name: "Beach photo.jpg", kind: "jpg" },
  { name: "meeting-notes.md", kind: "md" },
  { name: "Notch project", kind: "folder" },
  { name: "Pitch.key", kind: "key" },
  { name: "Budget.numbers", kind: "numbers" },
  { name: "Archive.zip", kind: "zip" },
  { name: "script.swift", kind: "swift" },
];

export const ShelfTab: React.FC<{ count?: number; progressOf?: (i: number) => number; dropGlow?: number }> = ({
  count = 9,
  progressOf = () => 1,
  dropGlow = 0,
}) => {
  const items = SHELF_ITEMS.slice(0, count);
  return (
    <div style={{ position: "absolute", inset: 0 }}>
      {dropGlow > 0 && (
        <div
          style={{
            position: "absolute",
            inset: 0,
            borderRadius: 12,
            border: `1.5px dashed rgba(217,119,87,${0.85 * dropGlow})`,
            background: `rgba(217,119,87,${0.07 * dropGlow})`,
          }}
        />
      )}
      {items.map((it, i) => {
        const col = i % 7;
        const row = Math.floor(i / 7);
        const p = progressOf(i);
        return (
          <div
            key={it.name}
            style={{
              position: "absolute",
              left: col * 85.67,
              top: row * 96 + 8 + (1 - p) * 8,
              width: 78,
              textAlign: "center",
              opacity: clamp01(p * 1.4),
              transform: `scale(${mix(0.8, 1, clamp01(p))})`,
            }}
          >
            <div style={{ height: 38, display: "flex", alignItems: "center", justifyContent: "center" }}>
              <FileGlyph kind={it.kind} />
            </div>
            <div style={{ marginTop: 9, fontSize: F(12), fontWeight: 600, lineHeight: "13.5px", padding: "0 4px" }}>{it.name}</div>
          </div>
        );
      })}
    </div>
  );
};

// ───────────────────────────── Presse-papiers ─────────────────────────────

const SourceChip: React.FC<{ kind: "browser" | "term" | "files" | "notes" | "photos" }> = ({ kind }) => {
  const base: React.CSSProperties = { width: 14, height: 14, borderRadius: 4, flex: "none", position: "relative", overflow: "hidden" };
  if (kind === "browser")
    return (
      <div style={{ ...base, background: "linear-gradient(#2fa4ff,#1456d9)" }}>
        <div style={{ position: "absolute", inset: 3.2, borderRadius: 7, border: "1.4px solid #fff" }} />
      </div>
    );
  if (kind === "term")
    return (
      <div style={{ ...base, background: "#161616", boxShadow: "inset 0 0 0 0.6px rgba(255,255,255,0.25)", fontFamily: FONT.mono, fontSize: F(6), color: "#fff", display: "flex", alignItems: "center", paddingLeft: 2 }}>
        &gt;_
      </div>
    );
  if (kind === "files")
    return <div style={{ ...base, background: "linear-gradient(90deg,#3aa0ff 50%,#9ad0ff 50%)" }} />;
  if (kind === "photos")
    return <div style={{ ...base, background: "conic-gradient(#ff5e62,#ffc371,#6fe06f,#4ac8ff,#b46cff,#ff5e62)" }} />;
  return (
    <div style={{ ...base, background: "#f7d44a" }}>
      {[0, 1, 2].map((i) => (
        <div key={i} style={{ position: "absolute", left: 2.5, right: 2.5, top: 4 + i * 3, height: 1, background: "rgba(0,0,0,0.35)" }} />
      ))}
    </div>
  );
};

type ClipRow = { h: number; node: React.ReactNode; time: string; trail?: React.ReactNode };

export const ClipboardTab: React.FC<{ rows?: number; progressOf?: (i: number) => number; hoverRow?: number; copiedRow?: number }> = ({
  rows = 7,
  progressOf = () => 1,
  hoverRow = -1,
  copiedRow = -1,
}) => {
  const t = useT();
  const justNow = t("just now", "à l'instant");
  // [top, hauteur] de chaque rangée (pt, depuis le haut du contenu). La première est épinglée.
  const list: (ClipRow & { top: number })[] = [
    {
      top: 34,
      h: 31.5,
      time: t("1 d ago", "il y a 1 j"),
      trail: <Pin size={13} color={C.accent} />,
      node: (
        <>
          <SourceChip kind="notes" />
          <div style={{ fontSize: F(13), whiteSpace: "nowrap", overflow: "hidden", textOverflow: "ellipsis", maxWidth: 400 }}>
            {t("Meeting Thursday 2 pm with the product team to review the launch, Horizon room.", "Rendez-vous jeudi 14 h avec l'équipe produit pour la revue du lancement, salle Horizon.")}
          </div>
        </>
      ),
    },
    {
      top: 77.5,
      h: 37,
      time: justNow,
      node: (
        <>
          <SourceChip kind="browser" />
          <LinkIcon size={14} color={C.accent} />
          <div style={{ lineHeight: 1.2 }}>
            <div style={{ fontSize: F(13), fontWeight: 700 }}>swift.org</div>
            <div style={{ fontSize: F(12), color: C.secondary }}>/documentation/api-design-guidelines</div>
          </div>
        </>
      ),
    },
    {
      top: 118,
      h: 37.5,
      time: justNow,
      trail: <Scissors size={13} color={C.secondary} />,
      node: (
        <>
          <SourceChip kind="notes" />
          <div style={{ fontSize: F(13), lineHeight: "15px", width: 440, overflow: "hidden", display: "-webkit-box", WebkitLineClamp: 2, WebkitBoxOrient: "vertical" }}>
            {t(
              "Reminder: the invoice has to go out before Friday, with the signed quote attached and the new billing address.",
              "Rappel : la facture doit partir avant vendredi, avec le devis signé en pièce jointe et la nouvelle adresse de facturation.",
            )}
          </div>
        </>
      ),
    },
    {
      top: 159,
      h: 42.5,
      time: t("1 min ago", "il y a 1 min"),
      node: (
        <>
          <SourceChip kind="photos" />
          <div style={{ width: 52, height: 32, borderRadius: 4, background: "linear-gradient(135deg,#2cf2a0 0%,#7a5cff 45%,#ff5aa5 80%,#ffe36e 100%)" }} />
          <div style={{ lineHeight: 1.2 }}>
            <div style={{ fontSize: F(13), fontWeight: 700 }}>Image</div>
            <div style={{ fontSize: F(12), color: C.secondary }}>640 × 400 · 6 {t("KB", "ko")}</div>
          </div>
        </>
      ),
    },
    {
      top: 204.5,
      h: 38,
      time: t("6 min ago", "il y a 6 min"),
      node: (
        <>
          <SourceChip kind="files" />
          <FileGlyph kind="pdf" size={0.8} />
          <div style={{ lineHeight: 1.2 }}>
            <div style={{ fontSize: F(13), fontWeight: 700 }}>{t("Quarterly report.pdf", "Rapport trimestriel.pdf")}</div>
            <div style={{ fontSize: F(12), color: C.secondary }}>{t("and 1 other file", "et 1 autre fichier")}</div>
          </div>
        </>
      ),
    },
    {
      top: 245.5,
      h: 31.5,
      time: t("24 min ago", "il y a 24 min"),
      node: (
        <>
          <SourceChip kind="browser" />
          <div style={{ width: 16, height: 16, borderRadius: 8, background: C.accent }} />
          <div style={{ fontSize: F(14), fontWeight: 700 }}>#D97757</div>
        </>
      ),
    },
    {
      top: 280.5,
      h: 32,
      time: t("2 h ago", "il y a 2 h"),
      node: (
        <>
          <SourceChip kind="term" />
          <div style={{ fontSize: F(13), fontWeight: 500 }}>swift test --filter ClipboardSnapshotTests</div>
        </>
      ),
    },
  ];
  return (
    <div style={{ position: "absolute", inset: 0 }}>
      <div style={{ position: "absolute", left: 0, right: 0, top: 4, height: 18, borderRadius: 9, background: "rgba(255,255,255,0.08)", display: "flex", alignItems: "center", padding: "0 9px", gap: 7, color: C.secondary }}>
        <Search size={12} />
        <span style={{ fontSize: F(13) }}>{t("Search", "Rechercher")}</span>
      </div>
      <div style={{ position: "absolute", left: 0, right: 0, top: 71.5, height: 1, background: "rgba(255,255,255,0.08)" }} />
      {list.slice(0, rows).map((r, i) => {
        const p = progressOf(i);
        const hot = hoverRow === i;
        const copied = copiedRow === i;
        return (
          <div
            key={i}
            style={{
              position: "absolute",
              left: 0,
              right: 0,
              top: r.top + (1 - p) * 10,
              height: r.h,
              opacity: clamp01(p * 1.5),
              borderRadius: 10,
              background: copied ? "rgba(217,119,87,0.2)" : hot ? "rgba(255,255,255,0.1)" : C.card,
              display: "flex",
              alignItems: "center",
              padding: "0 12px",
              gap: 9,
            }}
          >
            {r.node}
            <div style={{ flex: 1 }} />
            {r.trail}
            <span style={{ fontSize: F(12), fontWeight: 600, color: copied ? C.accent : C.secondary, whiteSpace: "nowrap" }}>
              {copied ? t("Copied", "Copié") : r.time}
            </span>
          </div>
        );
      })}
    </div>
  );
};

// ───────────────────────────── Minuteur ─────────────────────────────

export const TimerTab: React.FC<{ remaining?: number; total?: number; mode?: "focus" | "break"; running?: boolean; dots?: number }> = ({
  remaining = 18 * 60 + 12,
  total = 25 * 60,
  mode = "focus",
  running = true,
}) => {
  const t = useT();
  const elapsed = clamp01(1 - remaining / total);
  const r = 54;
  const circ = 2 * Math.PI * r;
  const mm = Math.floor(remaining / 60);
  const ss = Math.floor(remaining % 60);
  return (
    <Card style={{ position: "absolute", inset: 0 }} radius={12}>
      <div style={{ position: "absolute", left: 11, top: 12, display: "flex", alignItems: "center", gap: 7 }}>
        <Brain size={15} color={C.accent} />
        <span style={{ fontSize: F(14), fontWeight: 700 }}>{mode === "focus" ? t("Focus", "Concentration") : t("Short break", "Pause courte")}</span>
      </div>
      <div style={{ position: "absolute", right: 12, top: 12, display: "flex", alignItems: "center", gap: 8 }}>
        <div style={{ display: "flex", gap: 6, alignItems: "center" }}>
          <div style={{ width: 7, height: 7, borderRadius: 4, background: C.accent }} />
          <div style={{ width: 7, height: 7, borderRadius: 4, background: C.accent }} />
          <div style={{ width: 7, height: 7, borderRadius: 4, boxSizing: "border-box", border: `1.6px solid ${C.accent}` }} />
          <div style={{ width: 7, height: 7, borderRadius: 4, background: "rgba(255,255,255,0.2)" }} />
        </div>
        <span style={{ fontSize: F(13), color: C.secondary, fontWeight: 500 }}>{t("5 sessions today", "5 sessions aujourd'hui")}</span>
      </div>
      <svg width={120} height={120} viewBox="-60 -60 120 120" style={{ position: "absolute", left: 9, top: 40, transform: "rotate(-90deg)" }}>
        <circle r={r} fill="none" stroke="rgba(255,255,255,0.1)" strokeWidth={4} />
        <circle r={r} fill="none" stroke={C.accent} strokeWidth={4} strokeLinecap="round" strokeDasharray={`${circ * elapsed} ${circ}`} />
      </svg>
      <div style={{ position: "absolute", left: 9, top: 40, width: 120, height: 120, display: "flex", alignItems: "center", justifyContent: "center", fontSize: F(29), fontWeight: 600, fontVariantNumeric: "tabular-nums", letterSpacing: -0.5 }}>
        {mm}:{String(ss).padStart(2, "0")}
      </div>
      <div style={{ position: "absolute", left: 144, top: 72, display: "flex", alignItems: "center", gap: 8 }}>
        <div style={{ width: 34, height: 34, borderRadius: 17, background: "#C26A4D", display: "flex", alignItems: "center", justifyContent: "center", color: "#fff" }}>
          {running ? <Pause size={13} /> : <PlayFill size={13} />}
        </div>
        <div style={{ height: 26, padding: "0 12px", borderRadius: 13, background: "rgba(255,255,255,0.1)", display: "flex", alignItems: "center", fontSize: F(13), fontWeight: 600 }}>
          {t("+1 min", "+1 min")}
        </div>
        <div style={{ width: 28, height: 28, borderRadius: 14, background: "rgba(255,255,255,0.1)", display: "flex", alignItems: "center", justifyContent: "center" }}>
          <Stop size={11} color="#fff" />
        </div>
        <div style={{ width: 28, height: 28, borderRadius: 14, background: "rgba(255,255,255,0.1)", display: "flex", alignItems: "center", justifyContent: "center" }}>
          <SkipNext size={12} color="#fff" />
        </div>
      </div>
      <div style={{ position: "absolute", left: 144, top: 114, fontSize: F(13), color: C.secondary, fontWeight: 500 }}>
        {t("Ends at 9:18", "Fin à 9:18")}
      </div>
    </Card>
  );
};

// ───────────────────────────── Notes rapides ─────────────────────────────

export const NotesTab: React.FC<{ typed?: number; selected?: number }> = ({ typed = 1, selected = 3 }) => {
  const t = useT();
  const notes: [string, string, boolean][] = [
    ["docker compose up -d", t("3 h ago", "il y a 3 h"), true],
    [t("Name idea for the app", "Idée de nom pour l'app"), t("Just now", "À l'instant"), false],
    [t("Guest wifi code: 4821-…", "Code wifi invité : 4821-…"), t("25 min ago", "il y a 25 min"), false],
    [t("Meeting Thursday 2 pm, room B", "Réunion jeudi 14h, salle B"), t("the day before yesterday", "avant-hier"), false],
  ];
  const lines = [
    t("Meeting Thursday 2 pm, room B", "Réunion jeudi 14h, salle B"),
    t("Prepare the quarter figures", "Préparer les chiffres du trimestre"),
    t("Ask about the training budget", "Demander le budget formation"),
  ];
  const full = lines.join("\n");
  const shown = full.slice(0, Math.round(full.length * clamp01(typed)));
  return (
    <div style={{ position: "absolute", inset: 0, display: "flex", gap: 8 }}>
      <Card style={{ width: 172, height: 214, position: "relative" }} radius={12}>
        <div style={{ position: "absolute", left: 8, top: 8, fontSize: F(13), fontWeight: 700, color: C.secondary }}>{t("Notes", "Notes")}</div>
        <div style={{ position: "absolute", right: 8, top: 6, width: 20, height: 20, borderRadius: 10, background: "#C26A4D", color: "#fff", display: "flex", alignItems: "center", justifyContent: "center", fontSize: F(16), fontWeight: 600, lineHeight: 1 }}>+</div>
        {notes.map(([title, when, pinned], i) => (
          <div
            key={i}
            style={{
              position: "absolute",
              left: 8,
              right: 8,
              top: 32 + i * 40,
              height: 38,
              borderRadius: 10,
              background: i === selected ? "rgba(217,119,87,0.26)" : "transparent",
              padding: "5px 7px",
              boxSizing: "border-box",
            }}
          >
            <div style={{ fontSize: F(14), fontWeight: 700, whiteSpace: "nowrap", overflow: "hidden", textOverflow: "ellipsis", display: "flex", gap: 4, alignItems: "center" }}>
              {pinned && <Pin size={11} color={C.accent} />}
              <span style={{ overflow: "hidden", textOverflow: "ellipsis" }}>{title}</span>
            </div>
            <div style={{ fontSize: F(12), color: C.secondary, marginTop: 1 }}>{when}</div>
          </div>
        ))}
      </Card>
      <Card style={{ width: 412, height: 214, position: "relative" }} radius={12}>
        <div style={{ position: "absolute", left: 11, top: 10, right: 11, fontSize: F(15), lineHeight: "20px", whiteSpace: "pre-wrap" }}>
          {shown}
          <span style={{ display: "inline-block", width: 1.5, height: 16, background: C.accent, verticalAlign: -3, marginLeft: 1 }} />
        </div>
        <div style={{ position: "absolute", left: 10, bottom: 8, fontSize: F(12), color: C.secondary }}>
          {shown.length} {t("characters", "caractères")}
        </div>
      </Card>
    </div>
  );
};

// ─────────────────── Helpers pour les scènes ───────────────────
export { ChevronDown, FolderFill, ClipIcon };
export const lerp = (f: number, a: [number, number], b: [number, number]) => interpolate(f, a, b);
