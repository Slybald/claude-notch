import React from "react";

// Pictogrammes de la v3 (onglets Codex, Messages, Mail, intercalaires, fenêtre de l'assistant). Même convention que
// icons.tsx : viewBox 24, dessinés pour la vidéo, couleur par `currentColor`.
type P = { size?: number; color?: string; style?: React.CSSProperties };

const svg = (p: P, children: React.ReactNode, sw = 1.8) => (
  <svg
    width={p.size ?? 17}
    height={p.size ?? 17}
    viewBox="0 0 24 24"
    fill="none"
    stroke="currentColor"
    strokeWidth={sw}
    strokeLinecap="round"
    strokeLinejoin="round"
    style={{ color: p.color, display: "block", flex: "none", overflow: "visible", ...p.style }}
  >
    {children}
  </svg>
);

/** « </> » : symbole de l'onglet Codex. */
export const CodeIcon = (p: P) => svg(p, <path d="M8.6 6.4 L3 12 L8.6 17.6 M15.4 6.4 L21 12 L15.4 17.6 M13.6 4.6 L10.4 19.4" />, 2);

const bubble = "M12 3.6 C7 3.6 3.2 6.8 3.2 10.9 C3.2 13.1 4.3 15 6.1 16.4 C5.9 17.7 5.3 18.8 4.4 19.7 C6.3 19.7 7.9 19.1 9 18.3 C9.9 18.5 10.9 18.6 12 18.6 C17 18.6 20.8 15.4 20.8 11.3 C20.8 7.2 17 3.6 12 3.6 Z";
export const MessageIcon = (p: P) => svg(p, <path d={bubble} />, 1.7);
export const MessageFill = (p: P) => svg(p, <path d={bubble} fill="currentColor" stroke="none" />);

export const MailIcon = (p: P) =>
  svg(
    p,
    <>
      <rect x="2.8" y="5" width="18.4" height="14" rx="2.6" />
      <path d="M3.6 6.6 L12 13 L20.4 6.6" />
    </>,
    1.7,
  );
export const MailFill = (p: P) =>
  svg(
    p,
    <>
      <rect x="2.4" y="4.6" width="19.2" height="14.8" rx="2.8" fill="currentColor" stroke="none" />
      <path d="M3.8 6.4 L12 12.8 L20.2 6.4" stroke="#000" strokeWidth={1.7} />
    </>,
  );

export const MusicNote = (p: P) =>
  svg(
    p,
    <>
      <path d="M9 17.6 V5.4 L19 3.4 V15.6" strokeWidth={2} />
      <ellipse cx="6.6" cy="17.8" rx="2.8" ry="2.4" fill="currentColor" stroke="none" />
      <ellipse cx="16.6" cy="15.8" rx="2.8" ry="2.4" fill="currentColor" stroke="none" />
    </>,
  );

export const PaperPlane = (p: P) => svg(p, <path d="M20.6 3.4 L3.2 10.6 L10.4 13.4 L13.2 20.6 Z" fill="currentColor" stroke="none" />);
export const ReplyArrow = (p: P) => svg(p, <path d="M9.6 5 L3.8 10.4 L9.6 15.8 M4.6 10.4 H14 C17.8 10.4 20 12.6 20 16.4 V18.6" />, 2);
export const OpenApp = (p: P) =>
  svg(
    p,
    <>
      <rect x="3.6" y="3.6" width="16.8" height="16.8" rx="4" />
      <path d="M9.6 14.4 L14.8 9.2 M10.4 9.2 H14.8 V13.6" />
    </>,
    1.7,
  );
export const People = (p: P) =>
  svg(
    p,
    <g fill="currentColor" stroke="none">
      <circle cx="8.4" cy="8" r="3" />
      <circle cx="16.2" cy="9" r="2.5" />
      <path d="M2.6 18.6 C2.6 15.2 5 13.4 8.4 13.4 C11.8 13.4 14.2 15.2 14.2 18.6 Z" />
      <path d="M15 14 C18.4 13.6 21.4 15 21.4 18.6 H16.4 C16.4 16.6 15.9 15.2 15 14 Z" />
    </g>,
  );

/** Icône de l'app dans l'assistant : rectangle dont le tiers haut est plein (la notch). */
export const NotchGlyph = (p: P) =>
  svg(
    p,
    <>
      <rect x="3" y="4.4" width="18" height="15.2" rx="3.4" />
      <path d="M3.2 6.4 Q3.2 4.4 5.2 4.4 H18.8 Q20.8 4.4 20.8 6.4 V9.4 H3.2 Z" fill="currentColor" stroke="none" />
    </>,
    1.8,
  );

export const GraduationCap = (p: P) =>
  svg(
    p,
    <>
      <path d="M2.4 9.6 L12 5 L21.6 9.6 L12 14.2 Z" />
      <path d="M6.2 11.6 V16 Q12 19.4 17.8 16 V11.6" />
      <path d="M21.6 9.6 V15" />
    </>,
    1.7,
  );
export const Paintbrush = (p: P) =>
  svg(
    p,
    <>
      <path d="M19.6 3.6 Q21 5 19.4 7 L11.6 14.6 L9.4 12.4 L17 4.6 Q18.4 2.6 19.6 3.6 Z" />
      <path d="M9 13.2 C6.6 13 4.4 14.6 4.4 17.2 C4.4 19 3.6 19.8 3 20.2 C6.4 21.4 11 20.6 11 16.6" />
    </>,
    1.6,
  );
export const CodeBracket = (p: P) => svg(p, <path d="M8.6 6.4 L3 12 L8.6 17.6 M15.4 6.4 L21 12 L15.4 17.6 M13.6 4.6 L10.4 19.4" />, 1.9);
export const CheckFill = (p: P) =>
  svg(
    p,
    <>
      <circle cx="12" cy="12" r="10" fill="currentColor" stroke="none" />
      <path d="M7 12.4 L10.6 16 L17.2 8.6" stroke="#000" strokeWidth={2.4} />
    </>,
  );
export const CircleEmpty = (p: P) => svg(p, <circle cx="12" cy="12" r="9.4" />, 1.6);
export const Checkmark = (p: P) => svg(p, <path d="M5 12.6 L10 17.4 L19 7" />, 2.8);
export const SmallChevronRight = (p: P) => svg(p, <path d="M9.4 5.6 L15.8 12 L9.4 18.4" />, 2.6);
