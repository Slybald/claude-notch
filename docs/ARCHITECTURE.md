# Architecture and design decisions

For contributors. The [README](../README.md) describes the product; this page explains how the code is
organised and why some choices were made, so they are not undone by accident.

## Commands

- `swift build`: must produce **zero warnings** (the only tolerated one is the toolchain's
  "x86_64 architecture is deprecated" during the universal build).
- `swift test`: all green; 4 diagnostic tests are skipped unless their environment variables are set.
- Offscreen PNG renders: `CLAUDE_NOTCH_SNAPSHOT_DIR=/some/dir swift test --filter SnapshotTests`.
- `scripts/build.sh` (universal app, ad hoc signed, in `build/`; `VERSION=x.y.z` sets the version,
  `RELEASE_CHANNEL=1` marks a release build), `scripts/make-dmg.sh` (DMG + SHA-256), `scripts/install.sh`
  (developer install), `scripts/update-signing.swift` (Ed25519 key generation, signing, verification).
- Release: push a `vX.Y.Z` tag; `.github/workflows/release.yml` builds the app with `RELEASE_CHANNEL=1`,
  makes the DMG, signs it with the `UPDATE_SIGNING_KEY` secret and creates the release (DMG, `.sha256`, `.sig`).
- Live diagnostics of the running app: `GET http://127.0.0.1:47823/state` (sessions, notch, tools, jobs,
  version, updater).

## Code map (`Sources/ClaudeNotch/`)

- `HookServer`: minimal HTTP server on 127.0.0.1:47823. It resolves the process context *before* replying,
  while the hook process is still alive. `HookEvent`: tolerant JSON reading, every field optional.
- `ProcessInspector`: walks the ancestors of the hook's `$PPID` to find the Claude process, the host app
  (outermost `.app` bundle) and the source (CLI or Desktop). `ClaudeMonitor`: is Claude Desktop running,
  which `claude` processes are alive (2 s scan).
- `SessionStore`: per-session state machine, task lists (`~/.claude/tasks/<session_id>/`), Esc detection.
- `NotchController` (window, hover, visibility), `NotchViews` / `ToolsViews` (SwiftUI), `ToolsFeed`.
- `HookInstaller` + `OrderedJSON`: add and remove the hooks in `~/.claude/settings.json`. `Onboarding`:
  first-launch window and menu items. `AppIdentity`: bundle identifier and migration from early builds.
- `ActivityLog`: `files.jsonl` / `permissions.jsonl`. `JobRunner`: optional companion tool jobs.
- `Localization`: the `L()` helper. `LaunchAgent.swift` also holds `Preferences`.
- `Updater`: automatic updates from GitHub releases (check, signature, install, relaunch) and its menu items.

## Decisions worth keeping

- **Facts measured on Claude Code 2.1.29x**: `PermissionRequest` carries no `tool_use_id` (it is matched to the
  last active tool with the same name); internal agents send `SubagentStop` with an empty `agent_type`
  (ignored); a background agent's result comes back as a `UserPromptSubmit` starting with
  `<task-notification>`; the hook's `$PPID` is the claude process; the native CLI process is named after its
  version (e.g. `2.1.296`) and is recognised by its path.
- **Esc**: no hook fires. During a turn the transcript is read every second; only a `type: user` line whose
  text starts with `[Request interrupted by user` counts, not a mere quotation of that text.
- **~0 % CPU when collapsed**: no fast timer and no file reads while the panel is collapsed. The spinner and the
  pulsing hand are Core Animation animations (`AnimatedGlyphView`); a SwiftUI `TimelineView` re-ran the whole
  hosting view layout on every frame (~10 % CPU).
- **Shape size** is reported through `NotchSizeKey` with a `max` reduce (a plain `nextValue()` let a sibling's
  default value win, leaving the hover zone at zero). The expanded panel stays under 460 pt.
- **Window level**: `isFloatingPanel = true` must be set *before* `level`: that setter resets the level to
  `.floating` (3, measured with `CGWindowListCopyWindowInfo`, see `WindowLevelTests`). At level 3 the menu bar
  (24) and its icons were drawn above the notch and a full-screen app hid it; this is what an earlier version of
  this page described as "menu bar icons are drawn above the notch whatever its level", which was wrong. The
  panel now sits at `mainMenu + 3` (27), checked by `/state` (`level`, `windowServerLevel`), and is ordered front
  again 0.4 s after each Space change.
- **Menu bar band**: the expanded panel keeps a menu-bar-high empty band and the header sits below it: the
  middle of that band is the physical notch (nothing visible there) and, at level 27, the band covers the menu
  bar items on both sides while the panel is open. The collapsed ears also live in that band, next to the
  notch, and are drawn above the menu bar.
- **Protected folders** (Documents, Desktop, Downloads): never touched on the main thread (a macOS permission
  prompt would freeze the notch), and not at all when no companion tool is installed.
- **Companion tools** run from `JobRunner`, not launchd: macOS denies protected folders to launchd jobs, while
  processes started by the app inherit the access granted to it.
- **Installer**: byte-for-byte identical to `scripts/hooks_config.py` (tested), key order preserved,
  timestamped backup, nothing written when the JSON is invalid or nothing changes.
- **Opening a Desktop session**: `claude://code/continue?session=<local_…>`, a format read from Claude Desktop's
  `open-url` handler; the identifier is passed by the hook from `CLAUDE_CODE_HOST_SESSION_ID`.
- **Localization**: the French strings are the keys, English lives in `Resources/en.lproj`; any user-visible
  `String` goes through `L()`; `LocalizationTests` checks coverage.
- Ad hoc signature, no notarization: macOS blocks the first launch and may ask again for folder access after
  each reinstall.
- **Update channel**: only an app built with `RELEASE_CHANNEL=1` (Info.plist key `ClaudeNotchUpdateChannel =
  release`, set by the release workflow) checks for updates; local builds and `scripts/install.sh` never do.
  The signal is a GitHub release (`/releases/latest`, drafts and pre-releases ignored), not a commit.
  Checks run 60 s after launch, then every 6 h (low-frequency timers with tolerance, ~0 % CPU).
- **Signed updates**: a DMG is installed only if its Ed25519 signature (`ClaudeNotch-<v>.dmg.sig`, base64 of
  the signature of every byte of the DMG) matches the public key in `Updater.swift`. The CI signs with the
  `UPDATE_SIGNING_KEY` secret and checks the result against that public key, so a wrong secret fails the release
  instead of shipping an update nobody can install. The private key also lives in the maintainer's keychain;
  losing it breaks automatic updates for every existing installation.
- **Install**: `hdiutil attach` on a private mount point, the volume's `ClaudeNotch.app` must have our bundle
  identifier and the announced version, `ditto` into a hidden folder next to the installed app (same volume),
  detach, then two renames (current → `.ClaudeNotch-old.app`, new → current path) with a rollback if the second
  fails: never a half-replaced app. Only from `/Applications` or `~/Applications` with a writable folder;
  otherwise the menu links to the release page. `hdiutil` prints a deprecation notice on recent macOS; it stays
  because the app supports macOS 13.
- **When to install**: at launch, as soon as a version is found; later, only when no session is working or
  waiting (`SessionStore.hasBusySessions`), retried every 10 min. With the preference off, the version is only
  announced in the menu.
- **Relaunch**: a `/bin/sh` relay started with `posix_spawn` waits for the old PID to exit, then runs
  `open` on the app. `POSIX_SPAWN_SETSID` because launchd kills the process group of a LaunchAgent job when the
  app quits; `POSIX_SPAWN_CLOEXEC_DEFAULT` because an inherited socket would keep port 47823 busy and the new
  instance would quit at once.
- **Hooks after an update**: when the entries in `settings.json` are current and only the bundled hook script
  changed (`HookInstaller.Status.scriptOutdated`), the script is rewritten silently at launch and
  `settings.json` is not touched.

## Conventions

- Code comments and commit messages are in French; conventional commits.
- Public repository: no personal data (paths, e-mail addresses, project names, real session identifiers).
- Prove before fixing: reproduce with a test, a command or `/state`.
