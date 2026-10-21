import AppKit
import SwiftUI

/// Onglet « Mail » : le nombre de messages non lus d'Apple Mail et les derniers non-lus (expéditeur, objet, heure).
/// Désactivé par défaut. Textes dans Resources/{en,fr}.lproj/Mail.strings ; réglages dans UserDefaults sous
/// « mail.… ». Voir docs/MESSAGES-MAIL.md.
///
/// - Mail n'a pas d'API de lecture hors AppleScript (autorisation « Automatisation », demandée par macOS au premier
///   script). Claude Notch ne lance JAMAIS Mail : le script vérifie d'abord que Mail tourne, et le module ne lance
///   rien non plus quand Mail est fermé.
/// - Au repos : rien tant que l'onglet est désactivé. Activé et replié (après une première lecture réussie,
///   `armed`) : un observateur de lancement / arrêt de Mail, et seulement tant que Mail tourne un script de
///   compteur toutes les 2 minutes ; la liste n'est lue que panneau ouvert. Mail fermé : aucun minuteur.
/// - Aucune autorisation n'est demandée avant l'ouverture de l'onglet, et alors sur un clic de « Autoriser ».
///   Rien n'est enregistré ni envoyé hors du Mac.
final class MailModule: NotchModule {
    let id = "mail"
    let symbol = "envelope"
    var title: String { L("Mail", table: "Mail") }
    var isEnabledByDefault: Bool { false }

    /// Sous Messages (0) : une pastille de plus ne doit pas passer avant une conversation.
    static let earsPriority = -1
    static let pollInterval: TimeInterval = 120
    /// Non-lus détaillés quand l'onglet est ouvert (on en montre `maxShown`) : l'ordre des messages de Mail n'est
    /// pas garanti, on trie ici.
    static let fetchLimit = 12
    static let maxShown = 8

    // MARK: État

    @Published private(set) var state: MailState = .unknown
    @Published private(set) var unread = 0
    @Published private(set) var messages: [MailMessage] = []

    // MARK: Réglages

    @Published var showBadge: Bool { didSet { defaults.set(showBadge, forKey: Key.badge) } }
    /// Expéditeur et objet dans la liste ; coupé, seul le nombre reste (écran partagé).
    @Published var showSubjects: Bool { didSet { defaults.set(showSubjects, forKey: Key.subjects) } }

    private enum Key {
        static let badge = "mail.showBadge"
        static let subjects = "mail.showSubjects"
        static let armed = "mail.armed"
    }

    private let defaults: UserDefaults
    private let runner: AppleScriptRunner
    private let probe: AutomationProbe
    private let isMailRunning: () -> Bool
    private let workspace: NotificationCenter
    private let scheduler: ModuleScheduler
    private let clock: () -> Date
    private let openURL: (URL) -> Void

    private var isStarted = false
    /// Vues de l'onglet à l'écran : la liste n'est lue que si le panneau est ouvert.
    private var openViews = 0
    private var generation = 0
    private var observers: [NSObjectProtocol] = []
    private var cancelPoll: (() -> Void)?

    init(defaults: UserDefaults = .standard,
         runner: AppleScriptRunner = ModuleEnvironment.isTesting ? InertAppleScriptRunner() : OsascriptRunner(),
         probe: AutomationProbe = SystemAutomationProbe(),
         isMailRunning: @escaping () -> Bool = {
             !ModuleEnvironment.isTesting
                 && !NSRunningApplication.runningApplications(withBundleIdentifier: MailScript.bundleIdentifier).isEmpty
         },
         workspace: NotificationCenter = NSWorkspace.shared.notificationCenter, scheduler: ModuleScheduler = .system,
         clock: @escaping () -> Date = Date.init, openURL: @escaping (URL) -> Void = { _ = NSWorkspace.shared.open($0) }) {
        self.defaults = defaults
        self.runner = runner
        self.probe = probe
        self.isMailRunning = isMailRunning
        self.workspace = workspace
        self.scheduler = scheduler
        self.clock = clock
        self.openURL = openURL
        showBadge = defaults.object(forKey: Key.badge) as? Bool ?? true
        showSubjects = defaults.object(forKey: Key.subjects) as? Bool ?? true
    }

    deinit {
        cancelPoll?()
        observers.forEach(workspace.removeObserver)
    }

    /// Un script a déjà réussi : seulement alors le module tourne replié et peut interroger Mail sans demander.
    private var armed: Bool {
        get { defaults.bool(forKey: Key.armed) }
        set { defaults.set(newValue, forKey: Key.armed) }
    }

    // MARK: Contrat

    var keepsRunningWhenCollapsed: Bool { showBadge && armed }

    var ears: ModuleEars? {
        guard showBadge, state == .ready, unread > 0 else { return nil }
        return ModuleEars(symbol: "envelope.fill", text: unread > 99 ? "99+" : String(unread), priority: Self.earsPriority)
    }

    func start() {
        guard !isStarted else { return }
        isStarted = true
        observeMail()
        refresh()
    }

    func stop() {
        isStarted = false
        generation += 1
        openViews = 0
        cancelPoll?()
        cancelPoll = nil
        observers.forEach(workspace.removeObserver)
        observers = []
        messages = []
    }

    func makeView() -> AnyView { AnyView(MailPanel(module: self)) }
    func makeCompactView() -> AnyView? { state == .ready && unread > 0 ? AnyView(MailCompactView(module: self)) : nil }
    func makeSettingsView() -> AnyView? { AnyView(MailSettingsView(module: self)) }
    func makeHeaderAccessory() -> AnyView? { AnyView(MailRefreshButton(module: self)) }

    // MARK: Lecture

    /// Mail se lance ou se ferme : on relit tout de suite (et seulement alors, hors du rythme de 2 minutes).
    private func observeMail() {
        guard observers.isEmpty else { return }
        func isMail(_ note: Notification) -> Bool {
            (note.userInfo?[NSWorkspace.applicationUserInfoKey] as? NSRunningApplication)?.bundleIdentifier
                == MailScript.bundleIdentifier
        }
        observers.append(workspace.addObserver(forName: NSWorkspace.didLaunchApplicationNotification, object: nil,
                                               queue: .main) { [weak self] note in
            // Mail vient d'apparaître : on lui laisse le temps de répondre aux événements.
            if isMail(note) { _ = self?.scheduler.after(2) { self?.refresh() } }
        })
        observers.append(workspace.addObserver(forName: NSWorkspace.didTerminateApplicationNotification, object: nil,
                                               queue: .main) { [weak self] note in
            if isMail(note) { self?.refresh() }
        })
    }

    /// `interactive` : un clic de l'utilisateur, la seule situation où macOS peut poser sa question d'autorisation.
    func refresh(interactive: Bool = false) {
        guard isStarted else { return }
        generation += 1
        cancelPoll?()
        cancelPoll = nil
        guard isMailRunning() else {
            unread = 0
            messages = []
            state = .notRunning
            return
        }
        switch probe.status(of: MailScript.bundleIdentifier) {
        case .denied:
            armed = false
            state = .denied
            return
        case .notDetermined where !interactive && !armed:
            state = .needsPermission
            return
        default:
            break
        }
        let wantsList = openViews > 0
        let current = generation
        runner.run(MailScript.source, arguments: [String(wantsList ? Self.fetchLimit : 0)],
                   timeout: interactive ? 60 : 20) { [weak self] result in
            guard let self, isStarted, current == generation else { return }
            apply(result, wantsList: wantsList)
        }
    }

    private func apply(_ result: Result<String, AppleScriptFailure>, wantsList: Bool) {
        switch result {
        case .success(let output):
            switch MailScript.parse(output, now: clock()) {
            case .notRunning?:
                unread = 0
                messages = []
                state = .notRunning
            case .reading(let reading)?:
                unread = reading.unread
                if wantsList || reading.unread == 0 { messages = Array(reading.messages.prefix(Self.maxShown)) }
                armed = true
                state = reading.accounts == 0 ? .noAccount : .ready
            case nil:
                state = .failed
            }
        case .failure(.notAuthorized):
            armed = false
            state = .denied
        case .failure:
            state = .failed
        }
        schedulePoll()
    }

    /// Un seul rendez-vous à la fois, et seulement tant que Mail tourne et répond.
    private func schedulePoll() {
        cancelPoll?()
        cancelPoll = nil
        guard isStarted, state == .ready else { return }
        cancelPoll = scheduler.after(Self.pollInterval) { [weak self] in
            self?.cancelPoll = nil
            self?.refresh()
        }
    }

    // MARK: Vues

    func tabAppeared() {
        openViews += 1
        refresh()
    }

    func tabDisappeared() {
        openViews = max(0, openViews - 1)
    }

    // MARK: Actions

    /// Clic sur « Autoriser » : le premier script fait poser la question par macOS.
    func authorize() { refresh(interactive: true) }
    func openMessage(_ message: MailMessage) { openURL(message.openURL ?? MailScript.appURL) }
    func openMail() { openURL(MailScript.appURL) }
    func openPrivacy(_ pane: PrivacyPane) { openURL(pane.url) }
}
