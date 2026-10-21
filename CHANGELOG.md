# Changelog

All notable changes to this project are documented in this file.
The format follows [Keep a Changelog](https://keepachangelog.com/en/1.1.0/) and the project uses
[Semantic Versioning](https://semver.org/).

## [Unreleased]

### Added

- Talk to Claude from the notch: hover a session card and click **Chat** to see what Claude just said (and what
  your subagents reported), what you wrote, and a field to write to it. It works for the CLI and for the Code tab
  of Claude Desktop (checked with Claude Code 2.1.304: permissions, questions and messages that wake Claude).
- A card at the top of the Claude tab offers to turn on "Reply from the notch" (**Turn On** / **Later**) instead
  of leaving it in Settings › Claude. Nothing is decided without your click, and the terminal or Claude Desktop
  keep control.
- When the notch cannot write to a session (`claude -p`, the Agent SDK, an IDE, a session opened before the hook
  script was updated), the conversation says "Answer in *app*" with an **Open** button.

### Changed

- The hook script sends the Claude Desktop session ID with its waiting requests (`inbox`), so the Code tab of
  Claude Desktop is held at the end of a turn only. Held at the start of a session, the hook would delay the first
  prompt.

## [1.4.0] - 2026-10-21

### Added

- A setup assistant replaces the welcome window on first launch. In four short steps you pick the tabs you want
  (one card each; the Claude card only when Claude Code is found on the Mac, with the hooks as an option that is
  off by default), how the notch opens (hover or click, an optional keyboard shortcut, open at login), and see a
  preview of your notch. "Skip" is always there and changes nothing; nothing is written before "Apply". It asks
  for no macOS permission. It is shown once, and not after an update from a version that was already set up.
- **Settings › General › Run the Setup Assistant Again** goes through the steps again, starting from the current
  settings.

### Changed

- The hooks window (Settings › Claude, the **…** menu, a failed silent update) no longer carries the welcome
  content.

## [1.3.0] - 2026-10-21

### Added

- Edit the tabs in the notch, like apps on an iPhone: press and hold the tab bar, then drag the icons to reorder
  them, hide a tab with **−** (never the last one) or bring one back with **+**. **Done**, Esc or a click outside the
  bar ends it. Same settings as **Settings › Tabs**, which stays in sync.

## [1.2.3] - 2026-10-21

### Fixed

- Updates were checked every 6 hours of awake time only: after a night of sleep the app could go a whole morning
  without noticing a new version. It now also checks when the Mac wakes up, if the last check is older than
  6 hours.

## [1.2.2] - 2026-10-20

### Added

- The collapsed notch alternates Claude and the other tabs' ears (now playing, timer) every 4 seconds, like index
  tabs, while Claude is working or has just finished; when Claude is waiting for you it stays alone. Turn it off
  in **Settings › Appearance › Collapsed Notch** ("Alternate Claude and the Other Ears").

### Changed

- Low Power Mode: the first click on the tile asks for the password once and, in the same system prompt, adds the
  rule that lets later switches go through without it (the prompt says so). The note at the bottom of the tab is
  gone. "Remove the authorization" in Settings stops this automatic setup.

## [1.2.1] - 2026-10-20

### Added

- A welcome window on first launch: how to open the notch, its tabs, where the settings are. The Claude Code hooks
  are offered there only when Claude Code is found on the Mac (`~/.claude` or `$CLAUDE_CONFIG_DIR`), and can wait
  ("Later"); otherwise the window says where to turn on the Claude tab.

### Changed

- The Claude Code integration is optional. The Claude tab can be turned off in **Settings › Tabs** like any other
  tab. On first launch it is on only if Claude Code is found on the Mac; that choice is saved and does not change
  afterwards. With the tab off, nothing Claude-related runs: no process scan, no session tracking, hook events are
  ignored and permission and message requests go straight back to the terminal, no Claude ears, the panel never
  switches to Claude, and the **…** menu shows no session or hook items. Turning the tab back on restarts
  everything; open sessions show up at their next message.
- The notch is shown **Always** by default, for everyone. With the Claude tab off, **When Claude Is Open** is no
  longer offered and acts as **Always**, and **During Activity** only counts the tabs' ears.
- Hooks are still updated silently after an update, but only for people who already had them, with the Claude
  tab on. The window no longer asks for the hooks at every launch.

- Low Power Mode no longer asks for the administrator password at every switch. **Settings › Quick Settings**
  (or "Don't ask again" in the tab) adds, once, a system rule that only allows `pmset -a lowpowermode 0|1`
  (`/etc/sudoers.d/claude-notch-lowpower`, checked by `visudo` before it is installed, written by root only).
  Switches then go through `sudo -n`; if the rule stops working, the password is asked again and the app offers
  to set it back. "Remove the authorization" and uninstalling (app or script) remove it.

### Fixed

- 1.2.0 saved **When Claude Is Open** on its own for people who already had the hooks. It is set back to
  **Always**, once (someone who picked it on purpose during 1.2.0 gets **Always** once too).
- Tabs no longer shift under the pointer when hovering opens one (fixed-width tab bar, title shown beside it).

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
- Notch settings: show the notch always, while Claude is open or during activity; hide it for an hour, until
  tomorrow morning or until turned back on (also from a right click on the notch); open on hover or on click,
  close on a click outside; two optional global shortcuts (open the panel with the keyboard, hide the notch);
  screen choice (built-in, main, under the mouse or by name) with a virtual notch on screens without one; free
  panel width, background color, shadow, animation speed (simple fade with Reduce Motion); hide the notch from
  screenshots and screen sharing; reset to defaults. Opening the app again while it runs shows a hidden notch
  and the settings.
- Full screen: when an app is full screen on the notch's screen, the expanded panel becomes compact (half
  width, running sessions only), stays normal, or the notch hides, as set in Settings.
- Settings window (**…** menu › **Settings…**, ⌘,): open at login, visibility, hover delays, haptic feedback, full-screen
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
