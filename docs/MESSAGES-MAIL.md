# Messages and Mail in the notch: feasibility and prototype

*Français plus bas.* Status: prototype, both tabs **off by default**. Checked on macOS 27.0.1 (build 26A434),
Apple Silicon. Nothing here contains real message or mail content.

## Verdict (English)

| Source | Possible? | How | Cost |
|---|---|---|---|
| **Messages** (iMessage, SMS) | Yes, with a heavy permission | No public API. Read `~/Library/Messages/chat.db` (SQLite, read only). Needs **Full Disk Access**, which macOS never asks for with a dialog: the user adds the app by hand in System Settings. | Unread badge: free (file events). |
| Messages, **quick reply** | Yes, not tested for real | AppleScript `send … to chat id <guid>` to Messages, after the **Automation** permission (asked by macOS at the first send). | Only when the user sends. |
| Messages, **contact names** | Yes | Contacts framework (`CNContactStore`), permission asked when the user clicks **Allow** in the tab. Without it, numbers are shown. | One pass over the contacts when the tab opens. |
| **Apple Mail** | Yes, if Mail is open | AppleScript: unread count, the 3 to 5 latest received emails (sender, subject, start of the text, age, read or not), open a message by `message://`. **Automation** permission. Mail is never launched by Oriel. | One cheap counter script per 2 minutes, only while Mail runs; the list (about 5 s the first time) only while the tab is open. |
| Mail, **reply** | Yes, compiled, not run for real | AppleScript `reply … opening window` then `send` (or the window left open for the user), after the same **Automation** permission. | Only when the user clicks **Send** (or presses Return). |
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
  `read status`, `message id`, `content`), `account`, and the commands `reply message [opening window] [reply to all]`
  (default: no window, sender only) and `send outgoing message` (returns a boolean). The scripts compile. With **Mail
  closed** the real script returns `NOTRUNNING` **without launching Mail and without any permission prompt** (checked,
  and covered by a test that runs it when Mail is closed).
- **Measured on a real mailbox later** (Mail open, one Gmail account, 5,316 messages in the inbox, nothing of their
  content kept): `messages of inbox whose …` is **too slow**: a filter on `date received` did not answer in 40 s, one
  on `read status` not in 30 s, `whose message id is …` took 9 s. That was the first version's unread list, which would
  have ended on "Mail is not responding" on this inbox. `messages 1 thru N of inbox` is fast (about 4 to 5 s cold, 1.4 s
  warm for 5 emails with their text; the counter alone 0.2 s) and returns the **newest first** (checked on 40
  messages, ages increasing). The script reads `4 × N` messages by position and sorts them by date itself, so it does
  not rely on that order being exact. `message id` comes **without angle brackets** here (the code accepts both).
  A property read on a *list* of messages (`date received of {…}`) fails with -1728: the script reads them one by one.
  Not observed: several accounts (does the unified inbox keep the newest first across accounts?), POP or Exchange
  accounts, the "no account" state.
- Mail **reply**: written from the dictionary and compiled; **never run**, because running it creates a reply (an
  outgoing message that Mail may save as a draft in the user's real mailbox). Unverified assumptions, to check by hand:
  the quoted text is already in `content` of the reply when the script reads it, a plain-text `content` keeps the
  signature, `send` returns `true`. The script puts the typed text before whatever `content` held, deletes the reply
  if a step fails, and treats only an explicit `false` from `send` as a failure.
- `AEDeterminePermissionToAutomateTarget(…, askUserIfNeeded: false)` reads the Automation state without any dialog:
  Messages open and never asked → `-1744` (would need consent); Mail closed → `-600` (cannot know without launching it).
- System Settings anchors `Privacy_AllFiles`, `Privacy_Automation`, `Privacy_Contacts` exist in macOS 27's
  Privacy extension. Not clicked.

### What the prototype does

- **Messages tab**: eight most recent conversations (name or number, one line of the last message, relative time,
  unread count), unread dot, click a row to open a reply field (send, or open the conversation in Messages). Empty and
  error states: Full Disk Access missing (button to the right System Settings pane), Messages not set up, format not
  recognized, no conversation. A banner offers contact names (Allow / Dismiss), and says when Contacts was denied.
- **Mail tab**: the count and the 3 to 5 latest received emails (Settings, 5 by default): sender, subject, start of the
  text on one or two lines, relative time, a dot when unread. Click a row to open the message in Mail. Hover a row: a
  **Reply** button opens a field under it (Return sends, Esc closes). **Send** (or Return) sends the reply to the
  sender, with Mail's "Re: …" and quotation; **Continue in Mail** opens Mail's reply window with the typed text. The
  message stays in the list while you write even if newer mail pushes it out. "Sent" confirms, then the field closes;
  an error keeps the text and says what to do. States: Mail closed ("Open Mail", never launched without that click),
  Automation not asked yet ("Allow" starts the macOS prompt), denied (button to System Settings), no account, no
  answer. **A reply is sent only by `MailModule.sendReply()`**: tests check that opening the field, typing, refreshing,
  collapsing and closing send nothing, that an empty text sends nothing, that a double Return sends once, and that
  a closed Mail runs no script at all.
- **Ears**: a badge with the unread count (`message.fill` / `envelope.fill`), priority 0 and -1 (below the timer
  and the player), so it joins the Claude / modules alternation. Compact mode: one line, count and sender, never the text.
- **Settings panes**: badge on/off, show text (or sender and subject) on/off, permission status with the right button.
- **At rest**: disabled tab = nothing. Enabled and collapsed = nothing until the tab has been opened once and a read
  worked; after that, Messages only listens to file events on `chat.db` and `chat.db-wal` (FSEvents, no timer) and
  Mail only runs a counter script every 2 minutes **while Mail is running** (launch and quit are events, no timer
  when Mail is closed); the list and the texts are read only while the tab is open and the text is not hidden in
  Settings. Views are only built when the panel is open.
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
3. Messages' **quick reply** and Mail's **reply** need a real test with a real account before a release (see below). Mail's list was read on a real inbox (one account).
4. Replying to a **group** works through the chat guid; opening a group conversation only opens the Messages app
   (there is no public link to a group).
5. Mail: the list reads `4 × N` messages by position (see "Measured on a real mailbox later"); it runs off the main
   thread with a 20 s limit, and only the cheap counter runs while collapsed. If the unified inbox of several accounts
   is not date-ordered, the list can miss the newest mail of a second account.
6. Mail reply: the text is plain; Mail's rich-text formatting of the quotation may be flattened. If Mail does not
   confirm within 60 s the notch says so and asks to check before trying again (the reply may have left).

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
4. **Reply to yourself** from the notch (never to someone else for the test): the "Re: …" subject, the quotation, the
   signature, **Send** (arrives), **Continue in Mail** (window opens with the typed text, nothing sent), then with Mail
   quit (button to open it, nothing launched).
5. With two accounts, check that the 5 latest emails are the newest across both.

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
- **Mail** : Apple Mail par AppleScript (non-lus, les 3 à 5 derniers mails reçus avec expéditeur, objet, début du
  texte, ouverture par `message://`). Mail n'est **jamais lancé** : le script répond `NOTRUNNING` quand Mail est
  fermé (vérifié, sans fenêtre d'autorisation).
- **Mail, mesuré ensuite sur une vraie boîte** (Mail ouvert, un compte Gmail, 5 316 messages, aucun contenu gardé) :
  `messages of inbox whose …` est **trop lent** (filtre sur la date : pas de réponse en 40 s ; sur le statut de
  lecture : pas en 30 s ; sur le `message id` : 9 s), donc la première liste de non-lus aurait fini en « Mail ne
  répond pas ». `messages 1 thru N of inbox` répond en 4 à 5 s à froid, 1,4 s ensuite (compteur seul : 0,2 s), du plus
  récent au plus ancien (vérifié sur 40 messages) : le script lit `4 × N` messages par rang et retrie par date. Le
  `message id` est **sans chevrons** ici (le code accepte les deux). Une lecture de propriété sur une *liste* de
  messages échoue (-1728) : lecture message par message. Non observé : plusieurs comptes, POP, Exchange.
- **Mail, répondre** : écrit d'après le dictionnaire (`reply … opening window`, puis `send`, ou la fenêtre laissée
  ouverte) et **compilé, jamais exécuté** : une exécution crée une réponse, donc peut déposer un brouillon dans la
  vraie boîte. À vérifier à la main : la citation est déjà dans `content` de la réponse, la signature, `send`
  rend `true`. La réponse ne part que sur le clic sur **Envoyer** (ou Entrée) ; **Continuer dans Mail** ouvre la
  fenêtre de réponse de Mail avec le texte déjà tapé. Mail fermé : un bouton pour l'ouvrir, aucun script, aucun
  lancement tout seul.
- **Gmail / Outlook par API** : hors prototype. Graph : 3 à 5 jours ; Gmail : 3 à 5 jours plus la vérification Google
  (portée restreinte : évaluation de sécurité, semaines, payante). Estimations non mesurées.
- **Notifications des autres apps** : pas proprement. Aucune API publique ; la base de `usernoted` est privée,
  protégée (accès refusé ici) et son emplacement a changé entre versions de macOS ; l'API d'accessibilité est fragile
  et demande une autre autorisation.
- **Au repos** : onglet désactivé = rien. Activé et replié = rien tant que l'onglet n'a pas été ouvert une fois avec
  succès ; ensuite Messages écoute les fichiers (FSEvents, pas de minuteur) et Mail lit un compteur toutes les 2 minutes
  **seulement quand Mail est ouvert** (la liste et les textes seulement onglet ouvert). Aucune autorisation au lancement ; rien n'est stocké ni envoyé hors du Mac.
- **À décider** : l'Accès complet au disque est une demande lourde pour le grand public ; la pastille compte les
  non-lus des 30 derniers jours (peut différer de Messages) ; tests à la main avant publication : vrai `chat.db`, envoi
  à soi-même, vraie boîte Mail, réponse à soi-même depuis la notch (objet « Re: … », citation, signature, Envoyer,
  Continuer dans Mail), plusieurs comptes (les 5 plus récents toutes boîtes confondues).
