import Combine
import SwiftUI

/// Ce que `HookServer` demande au suivi Codex (routes `/codex/hook` et `/codex/permission`). Défini ici pour que le
/// serveur n'ait aucune dépendance sur le module.
protocol CodexRelay: AnyObject {
    /// Événement asynchrone (`/codex/hook`), contexte déjà résolu pendant que le hook était vivant. Tout thread.
    func codexEvent(_ event: HookEvent, context: CodexContext)
    /// Hook `PermissionRequest` synchrone : `reply` reçoit la sortie du hook (JSON) ou nil (204). Tout thread.
    func codexHold(_ event: HookEvent, context: CodexContext, id: UUID, reply: @escaping (Data?) -> Void)
    /// Le hook a fermé sa connexion (réponse donnée au terminal, hook tué). Tout thread.
    func codexConnectionClosed(_ id: UUID)
}

/// État des hooks Codex pour les réglages. Rien n'est lu avant `refresh()`.
final class CodexHookSetup: ObservableObject {
    static let shared = CodexHookSetup()

    @Published private(set) var status: CodexHookInstaller.Status = .notInstalled
    @Published private(set) var notes = CodexHookInstaller.ConfigNotes()
    /// Résultat de la dernière action : succès (sauvegarde comprise) ou raison de l'échec.
    @Published private(set) var message: String?
    @Published private(set) var messageIsError = false

    private let makeInstaller: () -> CodexHookInstaller

    init(installer: @escaping () -> CodexHookInstaller = { .standard }) {
        makeInstaller = installer
    }

    func refresh() {
        let installer = makeInstaller()
        status = installer.status()
        notes = installer.configNotes()
    }

    func install() {
        run { installer in
            let outcome = try installer.install()
            return outcome.backup.map { String(format: L("Hooks posés. Sauvegarde : %@", table: "Codex"), $0.lastPathComponent) }
                ?? L("Hooks posés.", table: "Codex")
        }
    }

    func uninstall() {
        run { installer in
            let outcome = try installer.uninstall()
            return outcome.fileChanged ? L("Hooks retirés.", table: "Codex") : L("Rien à retirer.", table: "Codex")
        }
    }

    private func run(_ action: (CodexHookInstaller) throws -> String) {
        do {
            message = try action(makeInstaller())
            messageIsError = false
        } catch {
            message = error.localizedDescription
            messageIsError = true
        }
        refresh()
    }
}

extension Preferences {
    /// Premier lancement avec cet onglet : activé seulement si Codex est sur ce Mac, puis jamais modifié tout seul
    /// (même règle que l'onglet Claude).
    func decideCodexTab(codexPresent: () -> Bool) {
        guard tabEnabled[ModuleRegistry.codexId] == nil else { return }
        tabEnabled[ModuleRegistry.codexId] = codexPresent()
    }
}

/// Onglet « Codex » : les sessions de l'agent de code d'OpenAI, suivies grâce aux hooks de Codex (`~/.codex/hooks.json`),
/// et ses demandes d'approbation, auxquelles on peut répondre depuis la notch. Optionnel comme l'onglet Claude : activé
/// d'office seulement si Codex est détecté, aucun travail de fond une fois désactivé.
final class CodexModule: NotchModule {
    static let replyKey = "codex.replyFromNotch"

    let id = ModuleRegistry.codexId
    let title = "Codex"
    let symbol = "chevron.left.forwardslash.chevron.right"

    let store: CodexStore
    let approvals: CodexApprovals
    let setup: CodexHookSetup
    private let defaults: UserDefaults

    /// « Approuver depuis la notch » : coupé par défaut ; coupé, les demandes sont rendues tout de suite à Codex.
    @Published var replyFromNotch: Bool {
        didSet {
            defaults.set(replyFromNotch, forKey: Self.replyKey)
            if !replyFromNotch { approvals.releaseAll() }
        }
    }

    /// Dernier événement de hook reçu (preuve que les hooks sont validés dans Codex).
    @Published private(set) var lastEventAt: Date?

    /// Posées par `NotchController` : ramener l'app hôte devant (et refermer le panneau), ouvrir les réglages.
    var openHost: (String?) -> Void = { _ in }
    var openSettings: () -> Void = {}

    private var cancellables = Set<AnyCancellable>()

    init(store: CodexStore = CodexStore(), approvals: CodexApprovals = CodexApprovals(), setup: CodexHookSetup = .shared,
         defaults: UserDefaults = .standard) {
        self.store = store
        self.approvals = approvals
        self.setup = setup
        self.defaults = defaults
        replyFromNotch = defaults.bool(forKey: Self.replyKey)
        approvals.isEnabled = { [weak self] in self?.replyFromNotch ?? false }
        store.objectWillChange.sink { [weak self] _ in self?.objectWillChange.send() }.store(in: &cancellables)
        approvals.objectWillChange.sink { [weak self] _ in self?.objectWillChange.send() }.store(in: &cancellables)
    }

    // MARK: - Contrat du module

    /// Décidé au premier lancement (`Preferences.decideCodexTab`) : activé seulement si Codex est détecté.
    var isEnabledByDefault: Bool { false }

    /// Sans activité, rien ne tourne panneau replié : seul le serveur de hooks écoute (port déjà ouvert).
    var keepsRunningWhenCollapsed: Bool { store.hasActivity }

    /// Alerte (approbation attendue) > travail en cours > « terminé » (5 s). Seul le module qui tourne en a.
    var ears: ModuleEars? {
        switch store.indicator {
        case .attention:
            let waiting = store.liveSessions.filter { $0.phase == .waitingApproval }.count
            return ModuleEars(symbol: "hand.raised.fill", text: "\(waiting)", priority: 9, alert: true)
        case .working:
            return ModuleEars(symbol: symbol, text: "\(store.activeCount)", priority: 6)
        case .done:
            return ModuleEars(symbol: "checkmark.circle.fill", text: "✓", priority: 6)
        case .none:
            return nil
        }
    }

    /// Une approbation attend l'utilisateur : le panneau s'ouvre sur cet onglet (si Claude n'a rien à dire).
    var needsAttention: Bool { store.indicator == .attention }

    func start() {
        // hooks.json et config.toml ont pu changer depuis (Codex, l'utilisateur).
        setup.refresh()
    }

    func makeView() -> AnyView {
        AnyView(CodexPanel(module: self, store: store, approvals: approvals, setup: setup))
    }

    func makeCompactView() -> AnyView? {
        AnyView(CodexCompactView(module: self, store: store, approvals: approvals))
    }

    func makeSettingsView() -> AnyView? {
        AnyView(CodexSettingsView(module: self, setup: setup))
    }

    func makeTabIcon() -> AnyView? {
        AnyView(CodexTabIcon(store: store))
    }

    // MARK: - Suivi (onglet activé ou non)

    /// Onglet activé : les événements sont suivis. Désactivé : sessions oubliées, minuterie et surveillance des
    /// processus arrêtées, demandes tenues rendues à Codex (le terminal pose sa question).
    func setTracking(_ isOn: Bool) {
        if isOn {
            store.start()
        } else {
            approvals.releaseAll()
            store.stop()
            lastEventAt = nil
        }
    }

    /// Clic dans une carte d'approbation : la décision part au hook.
    func decide(_ request: CodexApprovals.Request, _ decision: CodexApprovals.Decision) {
        guard approvals.decide(request, decision) else { return }
        if decision != .terminal { store.resolveApproval(request.sessionId) }
    }

    func activate(_ session: CodexSession) {
        openHost(session.hostBundleId)
    }

    var debugInfo: [String: Any] {
        let sessions: [[String: Any]] = store.sortedSessions.map { session in
            var item: [String: Any] = [
                "id": session.id,
                "project": session.projectName,
                "phase": String(describing: session.phase),
                "inTurn": session.inTurn,
                "toolCount": session.toolCount,
            ]
            item["host"] = session.hostName
            item["model"] = session.model
            item["pid"] = session.pid.map { Int($0) }
            return item
        }
        var info: [String: Any] = [
            "sessions": sessions,
            "indicator": String(describing: store.indicator),
            "timer": store.isTicking,
            "replyFromNotch": replyFromNotch,
            "approvals": approvals.debugInfo,
        ]
        info["lastEventAt"] = lastEventAt.map { ISO8601DateFormatter().string(from: $0) }
        return info
    }
}

extension CodexModule: CodexRelay {
    func codexEvent(_ event: HookEvent, context: CodexContext) {
        DispatchQueue.main.async { [weak self] in
            guard let self else { return }
            store.handle(event, context: context)
            approvals.observe(event)
            lastEventAt = Date()
        }
    }

    func codexHold(_ event: HookEvent, context: CodexContext, id: UUID, reply: @escaping (Data?) -> Void) {
        DispatchQueue.main.async { [weak self] in
            guard let self, let sessionId = event.sessionId, let name = event.toolName else { return reply(nil) }
            // La session attend une décision, dans la notch ou, sinon, dans le terminal.
            store.markWaiting(sessionId: sessionId, tool: CodexTools.describe(name: name, input: event.toolInput),
                              context: context, cwd: event.cwd)
            lastEventAt = Date()
            approvals.hold(event, id: id, reply: reply)
        }
    }

    func codexConnectionClosed(_ id: UUID) {
        DispatchQueue.main.async { [weak self] in self?.approvals.connectionClosed(id) }
    }
}
