import Combine
import Foundation

extension ModuleRegistry {
    /// Tous les onglets, dans l'ordre par défaut. Ajouter un module = une ligne ici.
    static func standardModules(claude: ClaudeModule) -> [any NotchModule] {
        [
            claude,
            MediaModule(),
            QuickSettingsModule(),
            ShelfModule(),
            ClipboardModule(),
            TimerModule(),
            NotesModule(),
        ]
    }
}

/// Les onglets de la notch : ordre et activation (lus dans les réglages), cycle de vie, oreilles des modules.
final class ModuleRegistry: ObservableObject {
    /// Le module Claude ne se désactive pas : c'est la raison d'être de l'app.
    static let claudeId = "claude"

    /// Tous les modules connus, dans l'ordre par défaut.
    let modules: [any NotchModule]
    /// Tous les modules dans l'ordre des réglages, activés ou non (fenêtre de réglages).
    @Published private(set) var ordered: [any NotchModule] = []
    /// Modules activés, dans l'ordre des onglets.
    @Published private(set) var enabled: [any NotchModule] = []
    /// Oreilles retenues parmi les modules qui tournent (avant la règle Claude, voir `EarsChoice`).
    @Published private(set) var moduleEars: ModuleEars?
    /// Modules démarrés.
    private(set) var running: Set<String> = []

    private let prefs: Preferences
    private var panelOpen = false
    private var cancellables = Set<AnyCancellable>()

    init(modules: [any NotchModule], prefs: Preferences) {
        precondition(Set(modules.map { $0.id }).count == modules.count, "identifiants de module en double")
        self.modules = modules
        self.prefs = prefs
        refreshOrder()
        // `objectWillChange` part avant le changement : on relit au tour de boucle suivant.
        prefs.objectWillChange
            .receive(on: DispatchQueue.main)
            .sink { [weak self] _ in
                self?.refreshOrder()
                self?.reconcile()
            }
            .store(in: &cancellables)
        for module in modules {
            module.objectWillChange
                .receive(on: DispatchQueue.main)
                .sink { [weak self] _ in self?.reconcile() }
                .store(in: &cancellables)
        }
    }

    func module(_ id: String) -> (any NotchModule)? {
        modules.first { $0.id == id }
    }

    func isEnabled(_ id: String) -> Bool {
        if id == Self.claudeId { return true }
        guard let module = module(id) else { return false }
        return prefs.tabEnabled[id] ?? module.isEnabledByDefault
    }

    func setEnabled(_ id: String, _ isOn: Bool) {
        guard id != Self.claudeId else { return }
        prefs.tabEnabled[id] = isOn
    }

    /// Glisser-déposer de la fenêtre de réglages (indices dans `ordered`).
    func move(from source: IndexSet, to destination: Int) {
        var ids = ordered.map { $0.id }
        ids.move(fromOffsets: source, toOffset: destination)
        prefs.tabOrder = ids
    }

    /// Le panneau s'ouvre ou se ferme : démarre ou arrête les modules concernés.
    func setPanelOpen(_ open: Bool) {
        guard open != panelOpen else { return }
        panelOpen = open
        reconcile()
    }

    /// Onglet affiché à l'ouverture : Claude s'il attend l'utilisateur (les oreilles montraient la main),
    /// sinon le dernier utilisé ou l'onglet par défaut des réglages, s'il est encore activé.
    func initialTab(claudeNeedsAttention: Bool) -> String {
        let ids = enabled.map { $0.id }
        if claudeNeedsAttention { return Self.claudeId }
        let wanted = prefs.defaultTab == Preferences.lastTabChoice ? prefs.lastTab : prefs.defaultTab
        return ids.contains(wanted) ? wanted : (ids.first ?? Self.claudeId)
    }

    /// Démarre les modules activés et utiles, arrête les autres, puis relit les oreilles.
    func reconcile() {
        for module in modules {
            let id = module.id
            let shouldRun = isEnabled(id) && (panelOpen || module.keepsRunningWhenCollapsed)
            if shouldRun, !running.contains(id) {
                running.insert(id)
                module.start()
            } else if !shouldRun, running.contains(id) {
                running.remove(id)
                module.stop()
            }
        }
        let ears = Self.pickEars(enabled.filter { running.contains($0.id) }.compactMap { $0.ears })
        if ears != moduleEars { moduleEars = ears }
    }

    /// Plus grande priorité ; à égalité, le premier dans l'ordre des onglets.
    static func pickEars(_ candidates: [ModuleEars]) -> ModuleEars? {
        candidates.reduce(nil) { best, next in
            guard let best else { return next }
            return next.priority > best.priority ? next : best
        }
    }

    /// Ordre des réglages : identifiants connus d'abord (sans doublon), puis les modules absents dans l'ordre
    /// par défaut (un nouveau module apparaît à la fin).
    static func order(_ modules: [any NotchModule], by saved: [String]) -> [any NotchModule] {
        var seen = Set<String>()
        var result: [any NotchModule] = []
        for id in saved where !seen.contains(id) {
            if let module = modules.first(where: { $0.id == id }) {
                result.append(module)
                seen.insert(id)
            }
        }
        result += modules.filter { !seen.contains($0.id) }
        return result
    }

    private func refreshOrder() {
        let all = Self.order(modules, by: prefs.tabOrder)
        let active = all.filter { isEnabled($0.id) }
        if all.map({ $0.id }) != ordered.map({ $0.id }) { ordered = all }
        if active.map({ $0.id }) != enabled.map({ $0.id }) { enabled = active }
    }

    var debugInfo: [String: Any] {
        var info: [String: Any] = [
            "tabs": enabled.map { $0.id },
            "running": running.sorted(),
        ]
        info["ears"] = moduleEars.map { "\($0.symbol) \($0.text)" }
        return info
    }
}

/// Ce que montrent les oreilles de la notch repliée.
enum EarsChoice: Equatable {
    case none
    case claude(NotchIndicator)
    case module(ModuleEars)

    /// Claude attend l'utilisateur > Claude travaille > Claude vient de finir (5 s) > module > rien.
    static func choose(claude: NotchIndicator, module: ModuleEars?, showEars: Bool) -> EarsChoice {
        guard showEars else { return .none }
        if claude != .none { return .claude(claude) }
        if let module { return .module(module) }
        return .none
    }
}
