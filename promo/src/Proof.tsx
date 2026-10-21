import React from "react";
import { AbsoluteFill } from "remotion";
import { useFontsReady } from "./fonts";
import { LangProvider, Lang } from "./i18n";
import { Panel, TabId } from "./ui/notch";
import { QuickTab, PlayerTab, ShelfTab, ClipboardTab, TimerTab, NotesTab } from "./ui/tabs";
import { SessionCard, PermissionReply, Conversation, Ears, SessionCount } from "./ui/claude";
import { Hand } from "./ui/icons";
import { C } from "./theme";

export type ProofProps = { tab: TabId | "ears" | "reply" | "chat"; lang: Lang };

/** Rendu de contrôle : même cadrage que les rendus de l'app (x2, fond gris) pour comparer côte à côte. */
export const Proof: React.FC<ProofProps> = ({ tab, lang }) => {
  useFontsReady();
  const body = () => {
    switch (tab) {
      case "quick":
        return <Panel tab="quick" contentH={200}><QuickTab /></Panel>;
      case "player":
        return <Panel tab="player"><PlayerTab /></Panel>;
      case "shelf":
        return <Panel tab="shelf"><ShelfTab /></Panel>;
      case "clip":
        return <Panel tab="clip"><ClipboardTab /></Panel>;
      case "timer":
        return <Panel tab="timer"><TimerTab /></Panel>;
      case "notes":
        return <Panel tab="notes"><NotesTab /></Panel>;
      case "claude":
        return (
          <Panel tab="claude" claudeState="attention">
            <div style={{ display: "flex", flexDirection: "column", gap: 8 }}>
              <SessionCard kind="attention" name="api" time="2 s" status={lang === "fr" ? "Attend ta permission" : "Needs your permission"} detail="Terminal · rm -rf build" outline={1} />
              <SessionCard kind="running" name="mon-app" agents="2 agents" time="2 s" status="Terminal" detail="npm test -- --watch=false" task={{ done: 1, total: 3, title: lang === "fr" ? "Correction du parseur" : "Fix the parser" }} />
              <SessionCard kind="done" name="site" time={lang === "fr" ? "à l'instant" : "just now"} status={lang === "fr" ? "Terminé" : "Done"} detail="README à jour : section installation réécrite." detailMono={false} />
            </div>
          </Panel>
        );
      case "reply":
        return (
          <Panel tab="claude" width={540} contentH={300} claudeState="attention">
            <div style={{ display: "flex", flexDirection: "column", gap: 8 }}>
              <SessionCard width={512} kind="attention" name="api" time="0 s" status="Needs your permission" detail="Terminal · Clean rebuild" outline={1} />
              <PermissionReply width={512} command="rm -rf build && swift build -c release" reason="Clean rebuild" />
            </div>
          </Panel>
        );
      case "chat":
        return (
          <Panel tab="claude" width={540} contentH={300}>
            <div style={{ display: "flex", flexDirection: "column", gap: 8, width: 512 }}>
              <SessionCard width={512} kind="running" name="api" time="0 s" status="Terminal" detail="swift test --parallel" />
              <Conversation width={512} said="README updated: installation section rewritten." you="Also add an FAQ section" typed={1} />
            </div>
          </Panel>
        );
      case "ears":
        return (
          <div style={{ display: "flex", flexDirection: "column", gap: 20 }}>
            <Ears left={<Hand size={15} color={C.amber} />} right={<SessionCount a={2} b={2} />} />
          </div>
        );
    }
  };
  return (
    <LangProvider lang={lang}>
      <AbsoluteFill style={{ background: "#D9D9D9" }}>
        <div style={{ position: "absolute", left: 80, top: 0, transform: "scale(2)", transformOrigin: "0 0" }}>{body()}</div>
      </AbsoluteFill>
    </LangProvider>
  );
};
