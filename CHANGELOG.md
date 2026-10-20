# Changelog

All notable changes to this project are documented in this file.
The format follows [Keep a Changelog](https://keepachangelog.com/en/1.1.0/) and the project uses
[Semantic Versioning](https://semver.org/).

## [1.2.0] - 2026-10-20

### Added

- Tabs in the expanded notch: **Claude**, **Player** (now playing and calendar), **Quick Settings**, **Shelf**,
  **Clipboard**, **Timer** and **Quick notes**. Click a tab or hover it briefly. The panel reopens on the last tab
  used, or on Claude when a session needs you. Tabs can be hidden, reordered and set as default in Settings.
- **Player**: artwork, title, artist and source app of the track playing, with progress (drag to seek),
  previous, play/pause and next. Artwork and an animated equalizer show in the collapsed notch's ears.
  A week view of Calendar, read only while the tab is on screen.
- **Quick Settings**: Wi-Fi, Bluetooth, Focus (through a Shortcuts shortcut), Low Power Mode, caffeine (1 h, 2 h
  or no limit), battery of the Mac and of AirPods, three scenes (Battery, Normal, Presentation), and an optional
  switch to Battery below a chosen charge level.
- **Shelf**: a holding area for files and folders. It keeps a reference to each item, never a copy. Drop files
  on the notch, even when collapsed; drag them out to Finder or another app (copy or alias). Multi-select,
  Quick Look, Share, AirDrop.
- **Clipboard**: history of text, links, images, files and colors, 25, 50 or 100 items, pinned items kept.
  Copies from password managers and items marked as confidential or transient are never recorded. Memory only
  unless you choose to keep text and links across restarts. Capture can be suspended.
- **Timer**: a countdown and a Pomodoro cycle (focus and break lengths in Settings). It keeps counting across
  sleep and restart, and sends a notification at the end.
- **Quick notes**: plain-text notes, pin or delete (with undo), search beyond 8 notes.
- **Reply from the notch** (Settings › Claude, off by default): allow or deny a permission, answer a question,
  approve a plan or ask for changes, and send a message to a session. The terminal stays usable; the first
  answer wins.
- Notch settings: visibility (always, while Claude is open, during an activity), temporary hiding (1 hour, until
  tomorrow, until turned back on), opening on hover or click, optional global shortcuts (open/close the panel,
  hide/show the notch), custom panel width, background color, shadow, animation speed, screen choice with a
  virtual notch on screens without one, and hiding the notch from screenshots and screen sharing. Reset to
  defaults.
- Full screen: when an app is full screen on the notch's screen, the expanded panel becomes compact (half
  width, running sessions only), stays normal, or the notch hides, as set in Settings.
- Settings window (**…** menu › **Settings…**, ⌘,): open at login, hover delays, haptic feedback, full-screen
  behavior, tabs, accent color, panel size, background opacity, ears, Claude, updates, about and licenses.
- `GET /state`: window level seen by the window server, Space, occlusion, screen, front app, full-screen state,
  tab and running modules.

### Changed

- Hooks: Claude Notch now also installs a synchronous `PermissionRequest` hook and a waiting `SessionStart` and
  `Stop` hook, used by replies from the notch. Hooks installed by a previous version are updated at launch, with
  the usual timestamped backup of `settings.json`.
- macOS permissions are asked only when the feature that needs them is used: Calendars, Automation (Calendar),
  Bluetooth, Notifications (timer), pasteboard access on macOS 15.4 and later (clipboard).
- No more one-second timer while there is no session.
- Release builds are signed with a fixed self-signed certificate instead of ad hoc, so macOS keeps the accesses
  granted to the app (calendar, Bluetooth, Automation, folders) from one update to the next. Moving to the first
  release signed this way asks for them one last time. Local builds stay ad hoc.
- Release workflow: the signing certificate comes from the `SIGNING_CERT_P12` and `SIGNING_CERT_PASSWORD`
  secrets (temporary keychain), the signature is checked before the DMG is made; a missing secret fails the job.

### Fixed

- The notch was drawn below the menu bar and disappeared behind full-screen apps: setting `isFloatingPanel`
  reset the window level to 3. It now sits above the menu bar (level 27).
- The hook script read the user's curl configuration (`~/.curlrc`) and proxy variables, which could break its
  output or redirect its requests. It now ignores both: it only talks to `127.0.0.1`.

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

[1.2.0]: https://github.com/Slybald/claude-notch/releases/tag/v1.2.0
[1.1.0]: https://github.com/Slybald/claude-notch/releases/tag/v1.1.0
[1.0.0]: https://github.com/Slybald/claude-notch/releases/tag/v1.0.0
