# Architecture and design decisions

For contributors. The [README](../README.md) describes the product; this page explains how the code is
organised and why some choices were made, so they are not undone by accident.

## Commands

- `swift build`: must produce **zero warnings** (the only tolerated one is the toolchain's
  "x86_64 architecture is deprecated" during the universal build).
- `swift test`: all green; 4 diagnostic tests are skipped unless their environment variables are set.
- Offscreen PNG renders: `CLAUDE_NOTCH_SNAPSHOT_DIR=/some/dir swift test --filter SnapshotTests`.
- `scripts/build.sh` (universal app, ad hoc signed, in `build/`; `VERSION=x.y.z` sets the version),
  `scripts/make-dmg.sh` (DMG + SHA-256), `scripts/install.sh` (developer install).
- Release: push a `vX.Y.Z` tag; `.github/workflows/release.yml` builds the DMG and creates the release.
- Live diagnostics of the running app: `GET http://127.0.0.1:47823/state` (sessions, notch, tools, jobs).

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
- **Menu bar**: its icons are drawn above the notch window whatever its level, so the menu-bar-high band stays
  empty and the header sits below it. The collapsed ears still live in the menu bar.
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

## Conventions

- Code comments and commit messages are in French; conventional commits.
- Public repository: no personal data (paths, e-mail addresses, project names, real session identifiers).
- Prove before fixing: reproduce with a test, a command or `/state`.
