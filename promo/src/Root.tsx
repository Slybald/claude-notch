import React from "react";
import { Composition, Still } from "remotion";
import { Proof, ProofProps } from "./Proof";
import { ConceptA, ConceptB, ConceptC } from "./concepts";
import { DURATION, Promo, PromoProps } from "./promo/Promo";
import { FPS } from "./motion";
import { DURATION2, Promo2 } from "./promo2/Promo2";
import { FPS2 } from "./motion2";
import { README_FRAMES, README_SIZE, Readme } from "./promo/Readme";

const base: PromoProps = { format: "wide", lang: "en", music: null };

export const Root: React.FC = () => (
  <>
    <Composition id="Promo16x9" component={Promo} width={1920} height={1080} fps={FPS} durationInFrames={DURATION} defaultProps={base} />
    <Composition id="Promo9x16" component={Promo} width={1080} height={1920} fps={FPS} durationInFrames={DURATION} defaultProps={{ ...base, format: "tall" }} />
    <Composition id="Promo2-16x9" component={Promo2} width={1920} height={1080} fps={FPS2} durationInFrames={DURATION2} defaultProps={{ format: "wide" as const, lang: "en" as const }} />
    <Composition id="Promo2-9x16" component={Promo2} width={1080} height={1920} fps={FPS2} durationInFrames={DURATION2} defaultProps={{ format: "tall" as const, lang: "en" as const }} />
    <Composition id="Readme" component={Readme} width={README_SIZE.w} height={README_SIZE.h} fps={FPS} durationInFrames={README_FRAMES} defaultProps={{ lang: "en" as const }} />
    <Still id="Proof" component={Proof as React.FC<any>} width={1400} height={960} defaultProps={{ tab: "quick", lang: "fr" } satisfies ProofProps} />
    <Still id="ConceptA" component={ConceptA} width={1920} height={1080} />
    <Still id="ConceptB" component={ConceptB} width={1920} height={1080} />
    <Still id="ConceptC" component={ConceptC} width={1920} height={1080} />
  </>
);
