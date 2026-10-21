import React, { createContext, useContext } from "react";

export type Lang = "en" | "fr";
const LangContext = createContext<Lang>("en");

export const LangProvider: React.FC<{ lang: Lang; children: React.ReactNode }> = ({ lang, children }) => (
  <LangContext.Provider value={lang}>{children}</LangContext.Provider>
);

export const useLang = () => useContext(LangContext);

/** Choisit le texte selon la langue : `t("Allow", "Autoriser")`. Les textes de l'interface viennent des
 *  fichiers de traduction de l'app (Resources/en.lproj et le français du code). */
export const useT = () => {
  const lang = useLang();
  return (en: string, fr: string) => (lang === "fr" ? fr : en);
};
