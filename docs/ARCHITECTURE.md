# Architecture and design decisions

For contributors. The [README](../README.md) describes the product; this page explains how the code is
organised and why some choices were made, so they are not undone by accident.

## Commands

- `swift build`: must produce **zero warnings** (the only tolerated one is the toolchain's
  "x86_64 architecture is deprecated" during the universal build).
- `swift test`: all green; 7 diagnostic tests are skipped unless their environment variables are set.
- Offscreen PNG renders: `CLAUDE_NOTCH_SNAPSHOT_DIR=/some/dir swift test --filter SnapshotTests` (notch, tabs,
  compact mode, settings window, reply cards in `ClaudeSnapshotTests`). Known artifact: under the notch's
  `clipShape`, SF Symbols come out white in these renders (`layer.render` and `cacheDisplay` alike); a
  window-server capture of the same view shows them tinted, as on screen.
- Memory and CPU of the notch view: `CLAUDE_NOTCH_FOOTPRINT=1 swift test --filter FootprintTests`.
- `scripts/build.sh` (universal app in `build/`, ad hoc signed unless `SIGN_KEYCHAIN` and `SIGN_IDENTITY` are
  set; `VERSION=x.y.z` sets the version, `RELEASE_CHANNEL=1` marks a release build), `scripts/make-dmg.sh`
  (DMG + SHA-256), `scripts/install.sh` (developer install), `scripts/update-signing.swift` (Ed25519 key
  generation, signing, verification).
- Release: push a `vX.Y.Z` tag; `.github/workflows/release.yml` imports the signing certificate into a temporary
  keychain, builds the app with `RELEASE_CHANNEL=1`, checks its code signature, makes the DMG, signs it with the
  `UPDATE_SIGNING_KEY` secret and creates the release (DMG, `.sha256`, `.sig`).
- Live diagnostics of the running app: `GET http://127.0.0.1:47823/state` with the hook token
  (`curl -H @"$HOME/Library/Application Support/ClaudeNotch/hook-token" …`): sessions, notch, tools, jobs,
  version, updater, replies (counts only); `notch` gives the window level seen by the window server, the Space,
  occlusion, screen, front app, full-screen state, tab and running modules.

## Code map (`Sources/ClaudeNotch/`)

- `HookServer`: minimal HTTP server on 127.0.0.1:47823. It resolves the process context *before* replying,
  while the hook process is still alive. Exact `Host`, no `Origin`, token (`HookAccess`) on every route but
  `/health`; `/permission` and `/inbox` are long requests handed to `ReplyCenter`. `HookEvent`: tolerant JSON
  reading, every field optional.
- `ProcessInspector`: walks the ancestors of the hook's `$PPID` to find the Claude process, the host app
  (outermost `.app` bundle) and the source (CLI or Desktop). `ClaudeMonitor`: is Claude Desktop running,
  which `claude` processes are alive (2 s scan).
- `SessionStore`: per-session state machine, task lists (`~/.claude/tasks/<session_id>/`), Esc detection.
- `NotchController` (window, hover, visibility, full screen), `NotchViews` (root, ears, panel, tab bar,
  session cards), `ToolsViews` / `ToolsFeed` (tools section). `FullScreenDetector`: is the front app full screen
  on the notch's screen.
- `Modules/`: `NotchModule` (the contract), `ModuleRegistry` (order, activation, life cycle, ears), one folder
  per module: `Claude/` (sessions, compact summary, Claude settings; `ReplyCenter` and `ReplyViews` for
  replies from the notch), and the empty `Media/`,
  `QuickSettings/`, `Shelf/`, `Clipboard/`, `Timer/`, `Notes/`.
- `Preferences`: every setting (UserDefaults, observable, values clamped). `SettingsWindow`: the settings
  window (SwiftUI in an `NSWindow`, sidebar) and the main menu (⌘, ⌘W, editing).
- `HookInstaller` + `OrderedJSON`: add and remove the hooks in `~/.claude/settings.json`. `Onboarding`:
  first-launch window and menu items. `AppIdentity`: bundle identifier and migration from early builds.
- `ActivityLog`: `files.jsonl` / `permissions.jsonl`. `JobRunner`: optional companion tool jobs.
- `Localization`: the `L()` helper, with an optional table. `LaunchAgent`: open at login.
- `Updater`: automatic updates from GitHub releases (check, signature, install, relaunch) and its menu items.

## Modules (tabs)

The expanded notch is a row of tabs; each tab is a module. Adding a module means: a folder
`Sources/ClaudeNotch/Modules/<Name>/`, its string tables `Resources/{en,fr}.lproj/<Name>.strings`, and one line
in `ModuleRegistry.standardModules`. A module never edits `Info.plist` (the usage descriptions for calendars,
Apple Events and Bluetooth are already there) nor another module's files.

- **Contract** (`NotchModule`, an `ObservableObject`): stable `id` (the settings key: never change it), localized
  `title`, SF Symbol `symbol`, `makeView()`. Optional, with defaults: `makeCompactView()` (full-screen summary),
  `ears` (with a `priority`), `keepsRunningWhenCollapsed`, `makeSettingsView()` (a `SettingsPane`, listed in the
  settings sidebar), `licenseNotices` (About › Licenses), `makeTabIcon()`, `makeHeaderAccessory()`,
  `isEnabledByDefault`, `start()` / `stop()`.
- **Life cycle**: the registry calls `start()` when a module is enabled *and* useful (the panel is open, or the
  module returns `keepsRunningWhenCollapsed`, re-read after each of its `objectWillChange`), and `stop()` as soon
  as that is no longer true, including when it is disabled. Stopped, a module does no work at all: no timer, no
  observer, no file read. All enabled modules run while the panel is open, so tabs switch instantly and the
  compact mode has its summaries.
- **Views** are built on demand (shown tab, compact mode, settings) and thrown away: state that must survive a
  tab switch lives in the module (`@Published`). Content width and maximum height come from the environment
  (`\.notchContentWidth`, `\.notchContentMaxHeight`): the whole panel must stay under 460 pt.
- **Registry**: order and activation come from `Preferences` (`tabOrder`, `tabEnabled`); unknown ids are ignored,
  a new module appears at the end, enabled if `isEnabledByDefault`. The Claude module cannot be disabled.
- **Tab bar**: icons in the header row, below the menu bar band; the active tab shows its title in a capsule
  that slides (`matchedGeometryEffect`). Click, or hover for 0.2 s (passing over a tab does not switch). The panel
  opens on the last tab or the default one (settings), except when Claude needs the user: then on Claude.
- **Ears** (collapsed notch): Claude waiting for you > Claude working > Claude just finished (5 s) > the module
  ears with the highest priority (tab order breaks ties) > nothing. Only running modules count. "Show the ears"
  off: the collapsed notch is exactly the notch. Module ears also keep the notch window on screen.
- **Full screen**: detected on events only (Space change, plus 0.4 s later, app activation, screen change): a
  layer-0 window of the front app covers the notch's whole screen, menu bar included (a zoomed window does not).
  Window bounds need no screen-recording permission. Setting: compact (270 pt, no tabs, each module's compact
  summary; Claude shows its running sessions, state and one line each), normal, or hidden (the notch leaves the
  screen until the app leaves full screen). The collapsed ears do not change.
- **Settings** (`Preferences`): one `@Published` property per setting, stored in UserDefaults under a namespaced
  key (`hover.openDelay`, `tabs.order`, `appearance.accent`…), read back clamped. A module stores its own
  settings under `<id>.<name>`. The accent color is read through `Palette.accent`; the notch view is rebuilt
  when it changes. "Reply from the notch" (`claude.replyFromNotch`, off by default): off, the reply hooks get
  an immediate "no decision".
- **Localization per table**: `L("…", table: "Media")` or `Text("…", tableName: "Media")`; without a table,
  `Localizable`. `LocalizationTests` checks every table: each key used in the code is translated in its table, no
  unused keys, French identity, same format specifiers, same tables in `en.lproj` and `fr.lproj`.

## Decisions worth keeping

- **Facts measured on Claude Code 2.1.29x**: `PermissionRequest` carries no `tool_use_id` (it is matched to the
  last active tool with the same name); internal agents send `SubagentStop` with an empty `agent_type`
  (ignored); a background agent's result comes back as a `UserPromptSubmit` starting with
  `<task-notification>`; the hook's `$PPID` is the claude process; the native CLI process is named after its
  version (e.g. `2.1.296`) and is recognised by its path.
- **Reply from the notch, facts measured on Claude Code 2.1.304** (spike of 50 sessions, then replayed against
  the real server and script):
  - `PermissionRequest` hook run synchronously (timeout 600, **no `onFailure`**: a failure is fail-open, even
    exit 2 does not deny): the terminal dialog is shown at the same time and stays usable; the first answer
    wins. "No" in the terminal sends SIGTERM to the hook; "Yes" runs the tool and the hook's late answer is
    ignored. Parallel tool calls ask one permission at a time.
  - Output: `{"hookSpecificOutput":{"hookEventName":"PermissionRequest","decision":{"behavior":"allow"}}}`, or
    `deny` with a `message` that becomes the tool result (Claude goes on).
  - AskUserQuestion is answered through the same hook (not PreToolUse, which hides the question in the
    terminal): `allow` + `updatedInput` = original `tool_input` + `answers` {exact question text: label};
    multiple choice = labels joined by ", "; free text accepted.
  - ExitPlanMode: `allow` alone is **ignored**; approval = `allow` + `updatedInput` (original input) +
    `updatedPermissions` `[{"type":"setMode","mode":"acceptEdits","destination":"session"}]`; `deny` +
    `message` = keep planning.
  - Free message: `SessionStart` and `Stop` hooks with `asyncRewake: true` (timeout 86400) long-poll the app; the
    message goes to stderr with exit 2 and Claude starts a turn (~3 s); during a turn it is read after the
    current tool. It comes back as a `UserPromptSubmit` `<task-notification>` with our `rewakeSummary`.
  - Without a terminal (`-p`/`--print`, or `--input-format`/`--output-format` as passed by the SDK and the Code
    tab of Claude Desktop, without `-p`), Claude **waits for the `asyncRewake` hooks** before reading the prompt
    (`claude -p` never answered with a held waiter). `ReplyCenter.wait` reads the argv of `X-Claude-PPID`
    (`KERN_PROCARGS2`) and answers 204 at once; such sessions get no **Message** button. Checked with the real
    `claude -p` and stream-json against the real server: about 5 s, as without the hooks.
- **Reply design**: one long connection per request; the app answers on the first of: the user's decision; the
  `PostToolUse` (same tool and input), `Stop`, `UserPromptSubmit` or `SessionEnd` of the session; the connection
  closing; the deadline (4 s if the card was never on screen, 590 s once it was, under the hook's 600 s). No
  decision = 204. One waiter per session (a new one closes the old with 204), FIFO queue (10 messages), waiters
  closed when their claude PID exits (kqueue `DispatchSourceProcess`, no polling). No route lets a client
  decide: a decision only exists as the answer to a hook's request, after a click. Never "always allow".
- **Hook token**: 32 hex, new at each launch, written (0600, `O_EXCL` + `rename`) only once the listener is
  ready, so a second instance that cannot bind never overwrites it. The script passes it with `curl -H @file`
  (never in argv) and `-q --noproxy '*'` (no `~/.curlrc`, no proxy). `permission` and `inbox` modes run curl
  in the background and trap TERM to kill it: the app sees the connection close.
- **Proof of the app**: the token authenticates the script to the app, not the other way round. A second
  secret (`hook-proof`, 0600, written before the token, never sent by the script) comes back in the
  `X-Claude-Notch-Proof` header of a 200 from `/permission` or `/inbox`, only to an authenticated request. The
  script compares it with shell builtins (never in argv) and ignores any answer without it: a program bound to
  the port while the app is closed (any account can bind 47823) gets the request but decides nothing. While
  the app runs, nobody else can bind the port (checked, even with `SO_REUSEPORT`).
- **Notch keyboard**: the panel never activates the app; it becomes key only for a text field
  (`NotchKeyboard.take`) and gives the keyboard back with `orderOut` + `orderFrontRegardless` when the field
  closes or the panel collapses, otherwise the next keystrokes would be swallowed by the hidden panel.
- **Esc**: no hook fires. During a turn the transcript is read every second; only a `type: user` line whose
  text starts with `[Request interrupted by user` counts, not a mere quotation of that text.
- **~0 % CPU when collapsed**: no fast timer and no file reads while the panel is collapsed. The spinner and the
  pulsing hand are Core Animation animations (`AnimatedGlyphView`); a SwiftUI `TimelineView` re-ran the whole
  hosting view layout on every frame (~10 % CPU). Modules are stopped while collapsed unless they ask; the 1 s
  session timer only runs while there are sessions; the root view does not observe `ClaudeMonitor` (it changes
  on every app switch), only the Claude tab does.
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
- **Code signature**: release builds are signed with a self-signed certificate (CN `Claude Notch Self-Signed`,
  extended key usage `codeSigning`, 10 years), not ad hoc. The designated requirement of an ad hoc signature is
  the build's `cdhash`, which changes with every build, so macOS (TCC) sees each update as a new app and asks
  again for calendar, Bluetooth, Automation and protected folders. With the certificate the requirement is
  `identifier "<bundle id>" and certificate leaf = H"<SHA-1 of the certificate>"`, the same for every build
  signed with it, so the grants carry over from one version to the next.
  - `scripts/build.sh` signs with `codesign --sign "$SIGN_IDENTITY" --keychain "$SIGN_KEYCHAIN"` when both
    variables are set (the release workflow sets them), otherwise ad hoc (local builds, `scripts/install.sh`).
    Only one of the two is an error, so a release cannot silently fall back to ad hoc. No hardened runtime: it
    would require entitlements and block code loaded by third-party processes (mediaremote-adapter, loaded by
    perl).
  - The `.p12` and its password are the repository secrets `SIGNING_CERT_P12` (base64) and
    `SIGNING_CERT_PASSWORD`. The workflow imports them into a temporary keychain (`set-key-partition-list`, so
    `codesign` never prompts), builds, runs `codesign --verify --deep --strict` and requires a `certificate leaf
    = H"…"` requirement without `cdhash`, then deletes the keychain (`if: always()`). Missing secrets fail the
    job before the tests.
  - Backup: the maintainer's login keychain, generic passwords of service
    `io.github.slybald.claudenotch.code-signing`, accounts `p12-base64` and `p12-password` (the README shows how
    to put the secrets back). The certificate is made with `openssl req -x509` (RSA 2048, `-days 3650`) and
    exported with `openssl pkcs12 -export -certpbe PBE-SHA1-3DES -keypbe PBE-SHA1-3DES -macalg sha1`, the
    format `security import` reads on every macOS version.
  - Never replace the certificate lightly: another one has another `H"…"`, so every user is asked for the
    accesses again. It is also what happens when it expires (10 years): `codesign` then refuses to sign and
    the release fails.
  - Consequence for users: the first release signed this way has a different requirement from the ad hoc
    versions, so macOS asks one last time for the accesses already granted; after that, never again.
  - Not a notarization: there is still no Developer ID, so macOS blocks the first launch of a downloaded copy
    (Open Anyway or `xattr -dr com.apple.quarantine`).
  - Independent from the Ed25519 key above: that one protects the update download, this one gives the app a
    stable identity.
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
  `settings.json` is not touched. When our entries come from a previous version (`.outdated`), entries and
  script are reinstalled silently too (timestamped backup); the onboarding window only opens if that fails or
  if the hooks were never installed.

## Conventions

- Code comments and commit messages are in French; conventional commits.
- Public repository: no personal data (paths, e-mail addresses, project names, real session identifiers).
- Prove before fixing: reproduce with a test, a command or `/state`.
