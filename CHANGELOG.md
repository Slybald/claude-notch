# Changelog

All notable changes to this project are documented in this file.
The format follows [Keep a Changelog](https://keepachangelog.com/en/1.1.0/) and the project uses
[Semantic Versioning](https://semver.org/).

## [Unreleased]

### Added

- Tabs: the expanded notch is a row of tabs (Claude, then Player, Quick Settings, Shelf, Clipboard, Timer and
  Notes, still empty). Click a tab or hover it briefly; the notch reopens on the last tab, or on Claude when a
  session needs you.
- Settings window (**…** menu › **Settings…**, ⌘,): open at login, always visible, hover delays, haptic
  feedback, full-screen behavior, tabs (on/off, order, default tab), accent color, panel size, background
  opacity, ears, Claude hooks, updates, about and licenses.
- Full screen: when an app is full screen on the notch's screen, the expanded panel becomes compact (half
  width, running sessions only), stays normal, or the notch hides, as set in Settings.
- `GET /state`: window level seen by the window server, Space, occlusion, screen, front app, full-screen state,
  tab and running modules.

### Fixed

- The notch was drawn below the menu bar and disappeared behind full-screen apps: setting `isFloatingPanel`
  reset the window level to 3. It now sits above the menu bar (level 27).

### Changed

- No more one-second timer while there is no session.
- Release builds are signed with a fixed self-signed certificate instead of ad hoc, so macOS keeps the accesses
  granted to the app (calendar, Bluetooth, Automation, folders) from one update to the next. Moving to the first
  release signed this way asks for them one last time. Local builds stay ad hoc.
- Release workflow: the signing certificate comes from the `SIGNING_CERT_P12` and `SIGNING_CERT_PASSWORD`
  secrets (temporary keychain), the signature is checked before the DMG is made; a missing secret fails the job.

## [1.1.0] - 2026-10-20

### Added

- Automatic updates from GitHub releases: check 60 s after launch, then every 6 hours; the DMG is installed only
  if its Ed25519 signature matches the public key built into the app; the app is swapped by renames with a
  rollback, then restarts by itself. A new version is installed at launch, or later when no session is running
  or waiting for you. Only apps built for a release update themselves.
- **…** menu: version line ("Updating to X…", "Updated to X"), **Automatic Updates** (on by default),
  **Check for Updates**, **Install** when automatic updates are off, or the release page when the app cannot
  replace itself (outside `/Applications` and `~/Applications`, or folder not writable).
- `GET /state`: `version` and `updater` keys.
- Release workflow: release builds (`RELEASE_CHANNEL=1`), signed DMG (`.dmg.sig` published next to the DMG and
  its SHA-256); a failed signature fails the job.

### Changed

- After an update, when only the bundled hook script changed, it is reinstalled silently at launch, without
  the first-launch window and without touching `settings.json`.
- The app now makes outgoing requests to GitHub (update check and download). Nothing about you or your
  sessions is sent.

## [1.0.0] - 2026-10-19

First public release.

### Added

- Notch panel that tracks Claude Code sessions from the CLI (terminals, editors) and from the Code tab of
  Claude Desktop, fed by async hooks relayed to a local server on `127.0.0.1:47823`.
- Session states: ready, thinking, running a tool, waiting for permission, waiting for an answer, plan to
  review, done, error, compacting; sessions that need you are listed first.
- Collapsed notch with two ears: overall state on the left, `sessions·subagents` (e.g. `1·6`) or task
  progress on the right.
- Permission details (command, file, question), task list progress, running subagents per session.
- Click on a card: brings the host app to the front, or opens the exact session in Claude Desktop.
- Optional tools section: recent files written by Claude, Git status, today's usage.
- Local logs of written files and permission requests in `~/Library/Application Support/ClaudeNotch/`.
- First-launch window that installs the hooks (backup of `settings.json`, existing hooks kept, key order
  preserved), and an uninstall command in the **…** menu (**Uninstall Claude Notch…**).
- Interface in English and French, following the system language.
- Migration from early builds (`local.claudenotch`): the new version replaces the running one and keeps
  the "open at login" setting.
- Universal app (Apple silicon and Intel), macOS 13 or later, distributed as a DMG built by GitHub Actions
  from version tags.

[1.1.0]: https://github.com/Slybald/claude-notch/releases/tag/v1.1.0
[1.0.0]: https://github.com/Slybald/claude-notch/releases/tag/v1.0.0
