# Editions of Oriel / Les « versions » d'Oriel

Oriel is for everyone; the current build is the "developer" way to use it (Claude tab, soon Codex). People
want other ways to use it (student, creative, minimal). Three ways to deliver that.

## English

| | A. Profiles in one app | B. Separate builds | C. Installable modules |
|---|---|---|---|
| What it is | A profile = a starting set of tabs, their order and a few settings, picked in the setup assistant and changeable in Settings › General. | One app per edition: its own name, bundle ID and default settings, built from the same code. | The app ships a core; tabs are downloaded and loaded separately. |
| Updates | One release, one DMG, one `.sig`, one check of `/releases/latest`. Nothing changes. | One DMG + signature per edition per release; the updater must know its edition (asset name, channel) and CI builds N apps. | The core and every module need their own signed download and version check. |
| Signature and macOS access | Unchanged: one certificate, one bundle ID, the calendar/Bluetooth/folder access you granted stays. | Same certificate but one bundle ID per edition: each edition asks for macOS access again, and two editions side by side do not share settings. | Loading code at run time means signing and verifying it (Ed25519) and no stable Swift ABI between builds. |
| Cost | Small: pure logic + one assistant card + one Settings sheet. | Medium to large: build scripts, CI matrix, release notes, support ×N. | Large: a plug-in format, a download path, a security review. |
| Switching later | One click, tab data kept. | Reinstall another app; data stays in the old one. | Download or remove modules. |

**Recommendation: A.** It gives each audience a good first screen at almost no cost, keeps one update and one
signature, and never locks anyone in (a profile is only a starting point; every setting stays editable). B or C
can come later if an edition needs something a profile cannot do (a different name or icon, code that must not
ship to everyone).

### What A does

A profile writes only: which tabs are on, their order, the opening mode (hover/click) and the ears. It never
touches the data of a tab, the hooks, visibility, appearance, shortcuts or screen.

| Profile | Tabs (in order) | Opens | Ears |
|---|---|---|---|
| Developer | Claude and Codex (only if detected), Clipboard, Timer, Notes | on hover | on |
| Student | Player + calendar, Timer (Pomodoro), Notes, Quick Settings | on click | on |
| Creative | Player + calendar, Shelf, Clipboard | on hover | on |
| Minimal | Player + calendar, Quick Settings | on click | off |

Tabs that do not exist yet (Codex, Messages, Mail…) are referenced by ID; a profile ignores any ID the app does
not have, so adding a tab to a profile is one line in `NotchProfile` (`Sources/ClaudeNotch/Profiles.swift`).
Claude and Codex are offered only if found on the Mac, as in the setup assistant, and a profile never installs
hooks.

- **First launch:** the first step of the setup assistant is the profile; the tabs and behavior steps then start
  from it. Without a choice nothing changes.
- **Later:** Settings › General › Change Profile… shows what will be shown, hidden and changed, then asks for a
  confirmation. Hidden tabs stop but keep their data (notes, clipboard history, shelf); a running timer will not
  ring any more. They come back from Settings › Tabs.
- Settings › General shows the profile whose tabs match yours, or "Custom".

## Français

La notch est pour tout le monde ; la version actuelle est la façon « développeur » de s'en servir (onglet Claude,
bientôt Codex). On veut d'autres façons (étudiant, créatif, minimal). Trois manières de les livrer.

| | A. Profils dans une seule app | B. Builds séparés | C. Modules installables |
|---|---|---|---|
| Principe | Un profil = des onglets de départ, leur ordre et quelques réglages, choisis dans l'assistant et modifiables dans Réglages › Général. | Une app par version : son nom, son identifiant et ses réglages par défaut, issue du même code. | L'app contient un noyau ; les onglets se téléchargent et se chargent à part. |
| Mises à jour | Une release, un DMG, une `.sig`, un contrôle de `/releases/latest`. Rien ne change. | Un DMG + une signature par version et par release ; le programme de mise à jour doit connaître sa version (nom du fichier, canal), la CI construit N apps. | Le noyau et chaque module ont leur téléchargement signé et leur contrôle de version. |
| Signature et accès macOS | Inchangés : un certificat, un identifiant, les accès accordés (calendrier, Bluetooth, dossiers) restent. | Même certificat mais un identifiant par version : chacune redemande les accès, et deux versions côte à côte ne partagent pas leurs réglages. | Charger du code à l'exécution oblige à le signer et le vérifier (Ed25519), sans ABI Swift stable entre builds. |
| Coût | Faible : logique pure + une carte dans l'assistant + une feuille dans Réglages. | Moyen à fort : scripts de build, matrice CI, notes de version, support ×N. | Fort : format de plug-in, téléchargement, revue de sécurité. |
| Changer plus tard | Un clic, les données des onglets restent. | Réinstaller une autre app ; les données restent dans l'ancienne. | Télécharger ou retirer des modules. |

**Recommandation : A.** Chaque public a un bon premier écran pour presque rien, une seule mise à jour et une seule
signature, et personne n'est enfermé (un profil n'est qu'un point de départ ; tout reste réglable). B ou C pourront
venir si une version a besoin de ce qu'un profil ne sait pas faire (un autre nom ou une autre icône, du code qui ne
doit pas être livré à tout le monde).

### Ce que fait A

Un profil écrit seulement : les onglets activés, leur ordre, le mode d'ouverture (survol/clic) et les oreilles. Il ne
touche ni aux données d'un onglet, ni aux hooks, ni à la visibilité, l'apparence, les raccourcis ou l'écran.

| Profil | Onglets (dans l'ordre) | Ouverture | Oreilles |
|---|---|---|---|
| Développeur | Claude et Codex (seulement s'ils sont détectés), Presse-papiers, Minuteur, Notes | survol | oui |
| Étudiant | Lecteur + calendrier, Minuteur (Pomodoro), Notes, Réglages rapides | clic | oui |
| Créatif | Lecteur + calendrier, Étagère, Presse-papiers | survol | oui |
| Minimal | Lecteur + calendrier, Réglages rapides | clic | non |

Les onglets qui n'existent pas encore (Codex, Messages, Mail…) sont désignés par leur identifiant ; un profil ignore
tout identifiant que l'app n'a pas, donc ajouter un onglet à un profil = une ligne dans `NotchProfile`
(`Sources/ClaudeNotch/Profiles.swift`). Claude et Codex ne sont proposés que s'ils sont trouvés sur le Mac, comme
dans l'assistant, et un profil n'installe jamais de hooks.

- **Premier lancement :** la première étape de l'assistant est le profil ; les étapes onglets et comportement
  partent de lui. Sans choix, rien ne change.
- **Plus tard :** Réglages › Général › Changer de profil… montre ce qui sera affiché, masqué et modifié, puis demande
  confirmation. Les onglets masqués s'arrêtent mais gardent leurs données (notes, historique du presse-papiers,
  étagère) ; un minuteur en cours ne sonnera plus. Ils reviennent depuis Réglages › Onglets.
- Réglages › Général affiche le profil dont les onglets correspondent aux tiens, ou « Personnalisé ».
