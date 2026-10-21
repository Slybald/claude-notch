import React from "react";

// Pictogrammes dessinés pour la vidéo (viewBox 24). Ils imitent les symboles de l'interface sans reprendre
// les glyphes d'un jeu d'icônes tiers. Couleur par `currentColor`.
type P = { size?: number; color?: string; style?: React.CSSProperties };

const svg = (p: P, children: React.ReactNode, sw?: number) => (
  <svg
    width={p.size ?? 17}
    height={p.size ?? 17}
    viewBox="0 0 24 24"
    fill="none"
    stroke="currentColor"
    strokeWidth={sw ?? 1.8}
    strokeLinecap="round"
    strokeLinejoin="round"
    style={{ color: p.color, display: "block", flex: "none", overflow: "visible", ...p.style }}
  >
    {children}
  </svg>
);

/** « ✻ » : l'icône de l'onglet Claude au repos. Six branches arrondies. */
export const Spark = (p: P) =>
  svg(
    p,
    <g stroke="currentColor" strokeWidth={2.5}>
      {[0, 60, 120, 180, 240, 300].map((a) => (
        <line key={a} x1="12" y1="12" x2="12" y2="3.6" transform={`rotate(${a} 12 12)`} />
      ))}
    </g>,
  );

export const Hand = (p: P) =>
  svg(
    p,
    <g fill="currentColor" stroke="none">
      <rect x="6.2" y="10.5" width="12.3" height="10.5" rx="5" />
      <rect x="7" y="3.6" width="2.7" height="12" rx="1.35" />
      <rect x="10" y="2" width="2.7" height="13" rx="1.35" />
      <rect x="13" y="3" width="2.7" height="12.6" rx="1.35" />
      <rect x="16" y="5.6" width="2.5" height="10" rx="1.25" />
      <rect x="2.9" y="11" width="2.7" height="8.2" rx="1.35" transform="rotate(-32 4.2 15)" />
    </g>,
  );

export const PlayCircle = (p: P) =>
  svg(
    p,
    <>
      <circle cx="12" cy="12" r="9" />
      <path d="M10.2 8.4 L15.4 12 L10.2 15.6 Z" fill="currentColor" strokeWidth={1.2} />
    </>,
  );

export const Switch2 = (p: P) =>
  svg(
    p,
    <>
      <rect x="3" y="3.8" width="18" height="7.2" rx="3.6" />
      <circle cx="7" cy="7.4" r="1.9" fill="currentColor" stroke="none" />
      <rect x="3" y="13" width="18" height="7.2" rx="3.6" />
      <circle cx="17" cy="16.6" r="1.9" fill="currentColor" stroke="none" />
    </>,
    1.7,
  );

export const Tray = (p: P) =>
  svg(
    p,
    <>
      <path d="M3.4 13.6 L6.1 5.9 Q6.5 4.8 7.7 4.8 H16.3 Q17.5 4.8 17.9 5.9 L20.6 13.6 V17.6 Q20.6 19.2 19 19.2 H5 Q3.4 19.2 3.4 17.6 Z" />
      <path d="M3.4 13.6 H8.4 Q9 15.8 12 15.8 Q15 15.8 15.6 13.6 H20.6" />
    </>,
  );

export const Clipboard = (p: P) =>
  svg(
    p,
    <>
      <rect x="3.6" y="5" width="12" height="15.4" rx="2.2" />
      <rect x="6.6" y="2.8" width="6" height="3.8" rx="1.3" fill="currentColor" />
      <rect x="9" y="8.6" width="11.4" height="12.8" rx="2.2" fill="#000" />
      <path d="M12 13 H17.6 M12 16.4 H16" />
    </>,
  );

export const TimerIcon = (p: P) =>
  svg(
    p,
    <>
      <circle cx="12" cy="13.4" r="8" />
      <path d="M9.6 2.9 H14.4" />
      <path d="M12 13.4 L15.2 9.8" />
    </>,
  );

export const NoteText = (p: P) =>
  svg(
    p,
    <>
      <rect x="3.4" y="4" width="17.2" height="16" rx="3.2" fill="#000" />
      <path d="M7.4 9 H16.6 M7.4 12.2 H16.6 M7.4 15.4 H13" />
    </>,
  );

export const Ellipsis = (p: P) =>
  svg(
    p,
    <g fill="currentColor" stroke="none">
      <circle cx="4.2" cy="12" r="2" />
      <circle cx="12" cy="12" r="2" />
      <circle cx="19.8" cy="12" r="2" />
    </g>,
  );

export const Wifi = (p: P) =>
  svg(
    p,
    <>
      <path d="M2.4 9.2 C7.6 4.4 16.4 4.4 21.6 9.2" strokeWidth={2.1} />
      <path d="M5.6 12.7 C9 9.7 15 9.7 18.4 12.7" strokeWidth={2.1} />
      <path d="M8.8 16 C10.8 14.3 13.2 14.3 15.2 16" strokeWidth={2.1} />
      <circle cx="12" cy="19.4" r="1.5" fill="currentColor" stroke="none" />
    </>,
  );

export const Bluetooth = (p: P) =>
  svg(p, <path d="M6.6 7.8 L17 16.2 L12 20.6 V3.4 L17 7.8 L6.6 16.2" strokeWidth={2.1} />);

export const Moon = (p: P) =>
  svg(
    p,
    <path
      d="M20.2 14.6 A8.6 8.6 0 1 1 9.4 3.8 A7.2 7.2 0 0 0 20.2 14.6 Z"
      fill="currentColor"
      stroke="none"
    />,
  );

export const Leaf = (p: P) =>
  svg(
    p,
    <>
      <path d="M4.6 19.4 C4.4 9.6 10.4 4.2 20 4.2 C20.2 13.6 14.6 19.6 4.6 19.4 Z" fill="currentColor" stroke="none" />
      <path d="M5 19 L13.2 10.8" stroke="#1a1a1a" strokeWidth={1.4} />
    </>,
  );

export const Cup = (p: P) =>
  svg(
    p,
    <>
      <path d="M6 8.6 H17.4 V12.8 A5.2 5.2 0 0 1 12.2 18 H11.2 A5.2 5.2 0 0 1 6 12.8 Z" fill="currentColor" stroke="none" />
      <path d="M17.4 10 H19 A2.2 2.2 0 0 1 19 14.4 H17" strokeWidth={1.7} />
      <ellipse cx="11.7" cy="19.4" rx="8.2" ry="1.7" fill="currentColor" stroke="none" />
    </>,
  );

export const Battery = (p: P & { level?: number }) =>
  svg(
    p,
    <>
      <rect x="1.8" y="7" width="18.4" height="10" rx="3" strokeWidth={1.6} opacity={0.55} />
      <rect x="3.6" y="8.8" width={14.8 * (p.level ?? 0.78)} height="6.4" rx="1.5" fill="currentColor" stroke="none" />
      <path d="M22 10.4 V13.6" strokeWidth={1.8} opacity={0.55} />
    </>,
  );

export const Lock = (p: P) =>
  svg(
    p,
    <>
      <rect x="5.4" y="10.6" width="13.2" height="9.8" rx="2.4" fill="currentColor" stroke="none" />
      <path d="M8.4 10.6 V8 A3.6 3.6 0 0 1 15.6 8 V10.6" strokeWidth={2} />
    </>,
  );

export const Rewind = (p: P) =>
  svg(
    p,
    <g fill="currentColor" stroke="none">
      <path d="M12.4 12 L21.6 5.6 V18.4 Z" />
      <path d="M2.4 12 L11.6 5.6 V18.4 Z" />
    </g>,
  );
export const Forward = (p: P) => (
  <div style={{ transform: "scaleX(-1)", display: "block" }}>
    <Rewind {...p} />
  </div>
);
export const Pause = (p: P) =>
  svg(
    p,
    <g fill="currentColor" stroke="none">
      <rect x="5.4" y="3.6" width="4.6" height="16.8" rx="1.3" />
      <rect x="14" y="3.6" width="4.6" height="16.8" rx="1.3" />
    </g>,
  );
export const PlayFill = (p: P) =>
  svg(p, <path d="M7 3.8 L20 12 L7 20.2 Z" fill="currentColor" stroke="none" />);
export const Stop = (p: P) =>
  svg(p, <rect x="5.2" y="5.2" width="13.6" height="13.6" rx="2.4" fill="currentColor" stroke="none" />);
export const SkipNext = (p: P) =>
  svg(
    p,
    <g fill="currentColor" stroke="none">
      <path d="M4.6 4.6 L16 12 L4.6 19.4 Z" />
      <rect x="17.4" y="4.4" width="3.2" height="15.2" rx="1.2" />
    </g>,
  );

export const ChevronLeft = (p: P) => svg(p, <path d="M15 5.4 L8.4 12 L15 18.6" />, 2.4);
export const ChevronRight = (p: P) => svg(p, <path d="M9 5.4 L15.6 12 L9 18.6" />, 2.4);
export const ChevronDown = (p: P) => svg(p, <path d="M5.4 9 L12 15.6 L18.6 9" />, 2.4);

export const Check = (p: P) => svg(p, <path d="M5 12.6 L10 17.4 L19 7" />, 2.6);

export const CheckCircleFill = (p: P) =>
  svg(
    p,
    <>
      <circle cx="12" cy="12" r="10.4" fill="currentColor" stroke="none" />
      <path d="M7.2 12.4 L10.6 15.6 L16.8 8.8" stroke="#000" strokeWidth={2.6} />
    </>,
  );

export const Search = (p: P) =>
  svg(
    p,
    <>
      <circle cx="10.4" cy="10.4" r="6.4" />
      <path d="M15.2 15.2 L20.4 20.4" />
    </>,
    2,
  );

export const PauseCircle = (p: P) =>
  svg(
    p,
    <>
      <circle cx="12" cy="12" r="9.2" />
      <path d="M9.6 8.6 V15.4 M14.4 8.6 V15.4" strokeWidth={2.4} />
    </>,
  );

export const Trash = (p: P) =>
  svg(
    p,
    <>
      <path d="M4 6.6 H20 M9.4 6.6 V4.4 H14.6 V6.6" />
      <path d="M6 6.6 L6.9 19.4 Q7 20.6 8.2 20.6 H15.8 Q17 20.6 17.1 19.4 L18 6.6" />
      <path d="M10 10.6 V16.6 M14 10.6 V16.6" />
    </>,
    1.6,
  );

export const Radio = (p: P) =>
  svg(
    p,
    <>
      <circle cx="12" cy="12" r="1.8" fill="currentColor" stroke="none" />
      <path d="M8.6 8.6 A5 5 0 0 0 8.6 15.4 M15.4 8.6 A5 5 0 0 1 15.4 15.4" />
      <path d="M5.8 5.8 A9 9 0 0 0 5.8 18.2 M18.2 5.8 A9 9 0 0 1 18.2 18.2" />
    </>,
    1.6,
  );

export const Pin = (p: P) =>
  svg(
    p,
    <g fill="currentColor" stroke="none" transform="rotate(35 12 12)">
      <path d="M8.4 3.4 H15.6 L14.8 5 V10.2 L17.6 13.4 H6.4 L9.2 10.2 V5 Z" />
      <rect x="11.2" y="13" width="1.6" height="7.4" rx="0.8" />
    </g>,
  );

export const Scissors = (p: P) =>
  svg(
    p,
    <>
      <circle cx="6.4" cy="17.6" r="2.8" />
      <circle cx="6.4" cy="6.4" r="2.8" />
      <path d="M8.6 8.2 L20 17.6 M8.6 15.8 L20 6.4" />
    </>,
    1.6,
  );

export const Link = (p: P) =>
  svg(
    p,
    <>
      <path d="M10.2 13.8 A4.2 4.2 0 0 0 16.2 13.8 L19.4 10.6 A4.2 4.2 0 0 0 13.4 4.6 L12.2 5.8" />
      <path d="M13.8 10.2 A4.2 4.2 0 0 0 7.8 10.2 L4.6 13.4 A4.2 4.2 0 0 0 10.6 19.4 L11.8 18.2" />
    </>,
    2,
  );

export const XCircleFill = (p: P) =>
  svg(
    p,
    <>
      <circle cx="12" cy="12" r="10.4" fill="currentColor" stroke="none" />
      <path d="M8.2 8.2 L15.8 15.8 M15.8 8.2 L8.2 15.8" stroke="#1d1d1d" strokeWidth={2.4} />
    </>,
  );

export const ArrowUp = (p: P) => svg(p, <path d="M12 19.4 V5 M6 10.8 L12 4.8 L18 10.8" />, 2.6);

export const Minus = (p: P) => svg(p, <path d="M5.4 12 H18.6" />, 3.4);
export const Plus = (p: P) => svg(p, <path d="M12 5.4 V18.6 M5.4 12 H18.6" />, 3);

export const InboxSmall = (p: P) => <Tray {...p} />;

export const Brain = (p: P) =>
  svg(
    p,
    <>
      <path d="M12.4 3 C7.6 3 4.4 6.4 4.4 10.6 C4.4 12.6 5 13.6 5.6 14.8 C6 15.6 5.6 17 5.4 18.4 H9.4 V21 H17.6 V16.4 C19 15.2 19.8 13.2 19.8 10.8 C19.8 6.4 16.6 3 12.4 3 Z" />
      <path d="M9.6 8.4 C11 7.6 12 8.6 12 9.8 C12 11 10.8 11.4 10 10.8 M13.4 8.8 C14.6 8.2 15.6 9.2 15.2 10.4 M10.6 13.2 C11.8 12.6 13 13.4 13 14.4 C13 15.4 12 15.8 11.2 15.4" strokeWidth={1.3} />
    </>,
    1.7,
  );

export const Bolt = (p: P) => svg(p, <path d="M13.4 2.8 L5.4 13.4 H11.4 L10.2 21.2 L18.6 10.4 H12.4 Z" fill="currentColor" stroke="none" />);

export const Terminal = (p: P) =>
  svg(
    p,
    <>
      <rect x="2.6" y="4.4" width="18.8" height="15.2" rx="3" />
      <path d="M6.6 9.4 L9.8 12 L6.6 14.6 M12.2 15 H16.6" />
    </>,
    1.6,
  );

export const FolderFill = (p: P) =>
  svg(
    p,
    <path
      d="M2.6 7.4 Q2.6 5.4 4.6 5.4 H9.2 L11.4 7.6 H19.4 Q21.4 7.6 21.4 9.6 V17.6 Q21.4 19.6 19.4 19.6 H4.6 Q2.6 19.6 2.6 17.6 Z"
      fill="currentColor"
      stroke="none"
    />,
  );

/** Curseur de souris dessiné pour la vidéo (flèche noire à liseré blanc). */
export const Cursor = ({ size = 22 }: { size?: number }) => (
  <svg width={size} height={size * 1.4} viewBox="0 0 16 22" style={{ display: "block", overflow: "visible" }}>
    <path
      d="M1.4 1.2 L1.4 17.2 L5.4 13.6 L8 19.8 L10.8 18.6 L8.2 12.6 L13.6 12.4 Z"
      fill="#0b0b0b"
      stroke="#fff"
      strokeWidth={1.5}
      strokeLinejoin="round"
    />
  </svg>
);
