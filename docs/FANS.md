# Fans in the notch: what was measured, what is assumed

Notes behind the **Fans** card of the Quick Settings tab. Read-only measurements were made on a MacBook Pro M3 Pro,
macOS 27.0.1, on 2026-10-21. [Français plus bas](#ventilateurs-dans-la-notch).

## Verdict

| Need | How | Status |
|---|---|---|
| Read fan speeds and bounds | SMC through IOKit (`AppleSMC`), no privileges | **Measured** |
| Read CPU / GPU temperatures | SMC keys `Tp…`, `Te…`, `Tg…` (`flt `) | **Measured** |
| Set a fixed speed | SMC writes, **root only** → small helper `fanctl` started with `sudo -n` | Code ready, real write: see [Write trial](#write-trial) |
| Fanless Mac (MacBook Air) | `FNum` = 0 → no card | By design |
| Intel Mac | different keys (`FS!`, `fpe2`) | Read-only card, fixed speed not offered |
| M5 | reported to use `F0md` (lower case) and no `Ftst` | Not supported: read-only |

## Measured on this Mac (read-only)

- `IOServiceOpen` on `AppleSMC` works as a normal user. Reading uses method 2 with an 80-byte structure: key at 0, data
  size at 28, data type at 32, attributes at 36, result at 40, command at 42 (5 = read, 8 = key by index, 9 = key
  info), index at 44, data at 48. Writing would be command 6; the kernel refuses it without root.
- 2,422 keys (`#KEY`). Listing them all takes about 0.4 s; one SMC call takes about 1 ms. The app therefore reads on a
  background queue, caches key types, and lists the keys once.
- `FNum` (`ui8 `) = 2. For each fan `n` (0 and 1), all `flt ` (IEEE-754 float, **little-endian**, e.g. 2317 =
  `00 d0 10 45`):
  - `F<n>Mn` = 2317 rpm, `F<n>Mx` = 6800 rpm (read-only attribute `0x84`/`0x85`),
  - `F<n>Ac` (actual) 2,300 to 4,400 rpm depending on load, `F<n>Tg` (target, writable attribute `0xd4`).
- `F<n>Md` (`ui8 `, writable attribute `0xd0`) = 0: automatic.
- `Ftst` (`ui8 `, writable attribute `0xd0`) = 0. `FS!` (the Intel force bitmask) does not exist.
- Temperatures (`flt `): 48 `Tp…` keys (performance cores), 13 `Te…` (efficiency cores), 18 `Tg…` (GPU), and
  `TCMz` (CPU die maximum). Under heavy load **in automatic mode** (a dozen builds running), the hottest `Tp…` reached
  about 105 °C with both fans around 4,000–4,400 rpm: macOS lets this chip run that hot. Some `Tf…` keys read negative
  values and are ignored.

## Assumed (from open-source projects, not yet observed here)

- Writing `F<n>Md` = 1 may be refused on M3 and later while macOS keeps control; writing `Ftst` = 1 unlocks it after a
  few seconds (projects retry for 3 to 10 s). The helper tries `F<n>Md` = 1 first, then `Ftst` = 1 and retries every
  100 ms for at most 10 s, then writes `F<n>Tg`.
- Back to automatic: `F<n>Md` = 0 for every fan, then `Ftst` = 0.
- The SMC does **not** enforce `Mn`/`Mx`: the bounds are checked by the app and checked again by the helper.
- Waking from sleep resets `Ftst` (control is lost); a reboot resets everything. Behaviour after the controlling
  process is killed is contradictory between sources: the helper never relies on it.

## Design

- **Helper** `fanctl` (`Sources/fanctl`, shared code in `Sources/FanControl`), built by `scripts/build.sh` into
  `Contents/Helpers/fanctl`, never run from there. On the user's click (first fixed speed, or Settings › Quick
  Settings › Fans), one administrator prompt runs, as root: copy the bundled helper to a root-owned temporary file,
  check its SHA-256 against the one the app read, write the sudoers rule to another root-owned temporary file, check it
  with `visudo -c`, then install `/Library/PrivilegedHelperTools/io.github.slybald.claudenotch.fanctl`
  (root:wheel 0755) and `/etc/sudoers.d/claude-notch-fans` (0440). Temporary files are removed in every case.
- **Rule**: `<user> ALL=(root) NOPASSWD: <helper> auto, <helper> hold`. sudo refuses any other argument.
- **Helper commands**: `fanctl auto` (every fan back to macOS) and `fanctl hold`, which reads one line at a time from
  the app: `ping`, `fan <n> <rpm>`, `auto`. Strict syntax (ASCII digits, no sign, single spaces); fan number must
  exist; speed between `Mn` and `Mx` read from the SMC. Anything else is refused and changes nothing.
- **Safety**, all of which give control back to macOS:
  - the app quits or crashes (the helper's input closes), logs out, sleeps, or its session becomes inactive;
  - no valid line for 30 s (the app writes every 10 s): app frozen, Mac woken from sleep;
  - hottest CPU/GPU probe at or above 105 °C (the measured automatic maximum), unless every held fan is already at its
    maximum (macOS could not do better);
  - macOS takes a held fan back (`F<n>Md` no longer 1): the helper does not fight it;
  - the SMC refuses a write; the helper receives SIGTERM, SIGINT, SIGHUP or SIGQUIT;
  - the helper stops without confirming: the app runs `fanctl auto`, and again at next launch if needed.
- **"Give control back to macOS"** is always visible while a fixed speed is active. The card reads the SMC every 2 s
  only while the tab is shown; nothing is read when the notch is collapsed (the index tab just shows the requested
  speed).
- **Removal**: "Remove the authorization" (Settings), the in-app uninstaller and `scripts/uninstall.sh` run
  `fanctl auto`, then delete the rule and the helper.

## Write trial

Not done yet: no SMC write happens on the development Mac without the owner's explicit agreement.

## Projects consulted

Behaviour and key names only; no code was copied.

| Project | License | Used for |
|---|---|---|
| [exelban/stats](https://github.com/exelban/stats) | MIT | Apple Silicon keys, `Ftst` unlock and retries |
| [agoodkind/macos-smc-fan](https://github.com/agoodkind/macos-smc-fan) | MIT | `Ftst` notes, thermalmonitord behaviour |
| [raminsharifi/MacFanControl](https://github.com/raminsharifi/MacFanControl) | MIT | M3 Pro bounds, sleep resets `Ftst`, temperature filtering |
| [maroffo/fanset](https://github.com/maroffo/fanset) | Apache-2.0 | rollback and read-back ideas |
| [beltex/SMCKit](https://github.com/beltex/SMCKit) | MIT | SMC structure (Intel era) |
| [dkorunic/iSMC](https://github.com/dkorunic/iSMC) | GPL-3.0 | temperature key names only, no code |
| [hholtmann/smcFanControl](https://github.com/hholtmann/smcFanControl) | GPL-2.0 | not used |
| Asahi Linux `macsmc-hwmon` | GPL-2.0 | key types only, no code |
| Macs Fan Control | proprietary | behaviour only (M3/M4 release notes) |

---

## Ventilateurs dans la notch

Résumé en français. Mesures en lecture seule sur un MacBook Pro M3 Pro, macOS 27.0.1, le 21/10/2026.

- **Mesuré** : le SMC se lit sans droits. Deux ventilateurs, minimum 2317 et maximum 6800 tr/min, vitesse et cible en
  `flt ` petit-boutiste, mode `F<n>Md` = 0 (automatique), clé `Ftst` présente (0), pas de `FS!`. Sondes `Tp…` (cœurs
  performance), `Te…` (efficacité), `Tg…` (GPU). En automatique et sous forte charge, la plus chaude a atteint environ
  105 °C, ventilateurs vers 4000 tr/min. Un appel au SMC coûte environ 1 ms : lecture hors du fil principal, toutes
  les 2 s, seulement onglet affiché.
- **Supposé** (projets libres ci-dessus, pas encore observé ici) : sur M3 et suivantes, `F<n>Md` = 1 peut être refusé
  tant que `Ftst` ne vaut pas 1 ; le SMC n'impose pas les bornes ; la veille remet `Ftst` à 0.
- **Écriture** : seulement par l'outil `fanctl`, installé une fois sur clic (mot de passe administrateur) dans
  /Library/PrivilegedHelperTools, avec une règle sudoers qui n'autorise que `fanctl auto` et `fanctl hold`. L'outil
  vérifie chaque ligne (ventilateur existant, vitesse entre le minimum et le maximum lus dans le SMC).
- **Garde-fous** : retour en automatique si l'app quitte ou plante, se fige (bail de 30 s), en veille, au changement
  de session, au-delà de 105 °C (sauf ventilateurs déjà au maximum), si macOS reprend la main, ou sur un signal ;
  « Rendre la main à macOS » toujours visible ; retrait de l'outil et de la règle par « Retirer l'autorisation » et à
  la désinstallation.
- **Essai d'écriture réel** : pas encore fait, il attend l'accord du propriétaire du Mac.
