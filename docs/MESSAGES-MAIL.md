# Messages and Mail in the notch: feasibility and prototype

*Français plus bas.* Status: prototype, both tabs **off by default**. Checked on macOS 27.0.1 (build 26A434),
Apple Silicon. Nothing here contains real message or mail content.

## Verdict (English)

| Source | Possible? | How | Cost |
|---|---|---|---|
| **Messages** (iMessage, SMS) | Yes, with a heavy permission | No public API. Read `~/Library/Messages/chat.db` (SQLite, read only). Needs **Full Disk Access**, which macOS never asks for with a dialog: the user adds the app by hand in System Settings. | Unread badge: free (file events). |
| Messages, **quick reply** | Yes, not tested for real | AppleScript `send … to chat id <guid>` to Messages, after the **Automation** permission (asked by macOS at the first send). | Only when the user sends. |
| Messages, **contact names** | Yes | Contacts framework (`CNContactStore`), permission asked when the user clicks **Allow** in the tab. Without it, numbers are shown. | One pass over the contacts when the tab opens. |
| **Apple Mail** | Yes, if Mail is open | AppleScript: unread count, latest unread (sender, subject, age), open a message by `message://`. **Automation** permission. Mail is never launched by Claude Notch. | One cheap script per 2 minutes, only while Mail runs. |
| **Gmail / Outlook** by API | Possible, out of the prototype | OAuth 2 + Gmail API / Microsoft Graph. See "Effort" below. | Large (see below). |
| **Notifications of other apps** | **Not cleanly** | See "Notifications". | n/a |

### Measured on this Mac

- `~/Library/Messages` is visible to `stat` but **`open()` fails with `EPERM`** for an app without Full Disk Access
  (SQLite then reports "authorization denied", code 23). A missing file gives `ENOENT`. The prototype tells the two
  apart: "Full Disk Access required" or "Messages is not set up".
- **Full Disk Access is not granted to the session that ran these checks**, so the real `chat.db` could not be read:
  its schema and the real `attributedBody` blobs are **not verified on this macOS**. The reader checks the columns it
  needs with `PRAGMA table_info` and reports "format not recognized" instead of failing.
- `attributedBody` (text is often NULL on recent macOS): an `NSAttributedString` archived by `NSArchiver`, i.e. a
  *typedstream*, not a plist. `NSArchiver` run on this macOS gives the layout the decoder reads:
  `04 0b "streamtyped" 81 e8 03 …  "NSString" 01 94 84 01 2b <length> <UTF-8>`; the class is `NSMutableString` when the
  string comes from an `NSMutableAttributedString`. Length is one byte, or `81`+2 bytes, or `82`+4 bytes. The
  decoder does not use `NSUnarchiver` (deprecated) and is tested on those archives (immutable, mutable, 200 characters,
  70 000 characters) and on truncated or hostile data.
- Messages: the scripting dictionary of macOS 27 has `send (text|file) to (participant|chat)`, and `chat.id` is "a guid
  identifier": the prototype sends to `chat id <chat.guid>` with the text passed as a script **argument** (never
  pasted in the script). The script **compiles**. **No message was sent**, by me or by the tests (a double records it).
- Mail: the dictionary has `inbox` (a mailbox with `unread count`), `message` (`sender`, `subject`, `date received`,
  `read status`, `message id`) and `account`. The script compiles. With **Mail closed** the real script returns
  `NOTRUNNING` **without launching Mail and without any permission prompt** (checked, and covered by a test that
  runs it when Mail is closed). Mail was closed on this Mac and was not opened: counts, order of messages, speed on a
  big inbox and the format of `message id` are **not verified against a real mailbox**. Mail also seems never to have been set up
  here (`defaults read com.apple.mail` finds no preferences, not confirmed), so the "no account" state is not observed either.
- `AEDeterminePermissionToAutomateTarget(…, askUserIfNeeded: false)` reads the Automation state without any dialog:
  Messages open and never asked → `-1744` (would need consent); Mail closed → `-600` (cannot know without launching it).
- System Settings anchors `Privacy_AllFiles`, `Privacy_Automation`, `Privacy_Contacts` exist in macOS 27's
  Privacy extension. Not clicked.

### What the prototype does

- **Messages tab**: eight most recent conversations (name or number, one line of the last message, relative time,
  unread count), unread dot, click a row to open a reply field (send, or open the conversation in Messages). Empty and
  error states: Full Disk Access missing (button to the right System Settings pane), Messages not set up, format not
  recognized, no conversation. A banner offers contact names (Allow / Dismiss), and says when Contacts was denied.
- **Mail tab**: count and the latest unread (sender, subject, age), click to open the message in Mail. States: Mail
  closed ("Open Mail"), Automation not asked yet ("Allow" starts the macOS prompt), denied (button to System
  Settings), no account, no answer.
- **Ears**: a badge with the unread count (`message.fill` / `envelope.fill`), priority 0 and -1 (below the timer
  and the player), so it joins the Claude / modules alternation. Compact mode: one line, count and sender, never the text.
- **Settings panes**: badge on/off, show text (or sender and subject) on/off, permission status with the right button.
- **At rest**: disabled tab = nothing. Enabled and collapsed = nothing until the tab has been opened once and a read
  worked; after that, Messages only listens to file events on `chat.db` and `chat.db-wal` (FSEvents, no timer) and
  Mail only runs a counter script every 2 minutes **while Mail is running** (launch and quit are events, no timer
  when Mail is closed). Views are only built when the panel is open.
- **Permissions**: none at launch. Full Disk Access is only explained. Contacts: on the **Allow** click. Automation:
  Mail on the **Allow** click, Messages at the first **send**. The panel must be open for any of this.
- **Data**: read in memory only. Nothing is written to disk (only the settings and a flag "a read already worked"),
  nothing leaves the Mac. Under XCTest the default accesses are inert (never the real messages).

### Limits and decisions left

1. **Full Disk Access is a big ask** for a general-public app, and it opens every protected folder to the app, not only
   Messages. The tab should stay off by default and say plainly what it grants. The grant survives updates of
   releases (stable self-signed certificate) but not an ad hoc build.
2. Messages shows **unread within 30 days** (older "unread" rows linger in `chat.db`), and not what Messages.app shows
   for filtered or muted conversations; the number can differ from the Dock badge.
3. Messages' **quick reply** and Mail's **list** need a real test with a real account before a release (see below).
4. Replying to a **group** works through the chat guid; opening a group conversation only opens the Messages app
   (there is no public link to a group).
5. Mail: one script call evaluates `messages of inbox whose read status is false`, which can take seconds on very large
   inboxes: it runs off the main thread with a 20 s limit, and only the cheap counter runs while collapsed.

### Notifications of other apps as a generic source

Not possible cleanly. There is no public API to read other apps' notifications (`UNUserNotificationCenter` only sees
your own). The alternatives: (1) the notification database of `usernoted`: private format, protected (access refused
here, `EPERM`), and its location **changed between macOS versions** (on this Mac the old location holds only stale
`db-shm` and `db-wal` files from an earlier version and no `db`); (2) reading Notification Center's window with the
Accessibility API: needs the Accessibility permission, breaks at every redesign, shows only what is on screen. Neither
is suitable for a general-public app, so the prototype does not use them.

### Effort for Gmail and Outlook (estimates, not measured)

- **Microsoft Graph** (Outlook, Microsoft 365): register an app, OAuth 2 with PKCE and a loopback redirect, `Mail.Read`
  delegated, refresh tokens in the Keychain, `GET /me/mailFolders/inbox` unread count and `messages?$filter=isRead eq false`.
  About 3 to 5 days; personal accounts need no review, organizations may require publisher verification.
- **Gmail API**: same flow, but `gmail.readonly` is a **restricted scope**: a public app needs Google's verification
  and a security assessment (weeks, usually paid, redone every year); in "testing" mode only 100 named users and tokens
  that expire after 7 days. About 3 to 5 days of code plus that process. Check Google's current rules before committing.
- Both need a client id shipped in the app and a Keychain entry per account: a privacy and support cost that Apple Mail
  (already configured by the user) avoids. Recommendation: Apple Mail only, as in the prototype; people who use Gmail in
  Mail get it.

### To verify by hand before shipping

1. Grant Full Disk Access to a dev build, open the tab: real schema, real `attributedBody`, unread count against Messages.
2. Send a reply to yourself from the tab (Automation prompt, `chat id` with the guid prefix used by this macOS).
3. Open Mail with an account, allow Automation, check the counters, the order and the speed of the list, `message://` opening.

---

## Verdict (Français)

Statut : prototype, les deux onglets sont **désactivés par défaut**. Vérifié sur macOS 27.0.1. Aucun contenu réel de
message ou de mail dans ce dépôt.

- **Messages** : pas d'API publique. Lecture seule de `~/Library/Messages/chat.db`, qui exige l'**Accès complet au
  disque** (macOS n'ouvre aucune fenêtre : l'utilisateur ajoute l'app à la main dans Réglages Système). Mesuré :
  `stat` réussit, `open()` échoue en `EPERM` (SQLite : « authorization denied »). Le texte est souvent dans
  `attributedBody` (typedstream d'`NSArchiver`) : décodé à la main, testé sur des archives produites par ce macOS.
  **Non vérifié** : le vrai `chat.db` (l'accès n'était pas accordé à la session de test), donc son schéma réel et les
  vrais blobs ; le lecteur contrôle ses colonnes et affiche « format non reconnu » plutôt que de planter.
- **Réponse rapide** : AppleScript `send … to chat id <guid>` (autorisation Automatisation au premier envoi). Le
  script se compile ; **aucun message n'a été envoyé** (un double enregistre l'appel dans les tests).
- **Noms des contacts** : Contacts, sur un clic sur **Autoriser** dans l'onglet ; sans, on voit les numéros.
- **Mail** : Apple Mail par AppleScript (non-lus, derniers expéditeurs et objets, ouverture par `message://`).
  Mail n'est **jamais lancé** : le script répond `NOTRUNNING` quand Mail est fermé (vérifié, sans fenêtre
  d'autorisation). **Non vérifié** sur une vraie boîte (Mail était fermé et n'a pas été ouvert) : compteurs, ordre,
  vitesse, format de `message id`.
- **Gmail / Outlook par API** : hors prototype. Graph : 3 à 5 jours ; Gmail : 3 à 5 jours plus la vérification Google
  (portée restreinte : évaluation de sécurité, semaines, payante). Estimations non mesurées.
- **Notifications des autres apps** : pas proprement. Aucune API publique ; la base de `usernoted` est privée,
  protégée (accès refusé ici) et son emplacement a changé entre versions de macOS ; l'API d'accessibilité est fragile
  et demande une autre autorisation.
- **Au repos** : onglet désactivé = rien. Activé et replié = rien tant que l'onglet n'a pas été ouvert une fois avec
  succès ; ensuite Messages écoute les fichiers (FSEvents, pas de minuteur) et Mail lit un compteur toutes les 2 minutes
  **seulement quand Mail est ouvert**. Aucune autorisation au lancement ; rien n'est stocké ni envoyé hors du Mac.
- **À décider** : l'Accès complet au disque est une demande lourde pour le grand public ; la pastille compte les
  non-lus des 30 derniers jours (peut différer de Messages) ; tests à la main avant publication : vrai `chat.db`, envoi
  à soi-même, vraie boîte Mail.
