import AppKit
import Combine
import SwiftUI

/// État partagé entre le contrôleur (AppKit) et la vue (SwiftUI).
final class NotchViewModel: ObservableObject {
    @Published var isExpanded = false
    @Published var notchSize = CGSize(width: 200, height: 32)
    @Published var hasNotch = false
    /// Onglet affiché (identifiant de module).
    @Published var selectedTab = ModuleRegistry.claudeId
    /// Une app est en plein écran sur l'écran de la notch.
    @Published var isFullScreen = false
    /// « Réduire les animations » (Accessibilité) : fondu simple au lieu des ressorts.
    @Published var reduceMotion = false
    /// Taille réelle de la forme noire, mesurée par la vue. Sert aux zones de survol.
    var contentSize: CGSize = .zero
    /// La fenêtre est à l'écran (le contrôleur la masque : « Masquer la notch », plein écran « masquée »).
    @Published var isShown = true

    /// Intercalaire des oreilles repliées : monte d'un cran toutes les 4 s tant que `setEarsRotation(true)`.
    @Published private(set) var earsStep = 0
    /// Remplaçable dans les tests : une fausse minuterie, pas de 4 s réelles.
    var earsTimer = EarsTimer.system
    private var cancelEarsTimer: (() -> Void)?

    var isRotatingEars: Bool { cancelEarsTimer != nil }

    deinit { cancelEarsTimer?() }

    /// Un seul timer, créé quand il y a au moins deux contenus à alterner sous les yeux (voir
    /// `EarsRotation.shouldRotate`), annulé sinon. Chaque démarrage repart du premier contenu (Claude).
    func setEarsRotation(_ on: Bool) {
        guard on != isRotatingEars else { return }
        cancelEarsTimer?()
        cancelEarsTimer = nil
        if earsStep != 0 { earsStep = 0 }
        guard on else { return }
        cancelEarsTimer = earsTimer.every(EarsRotation.interval, EarsRotation.tolerance) { [weak self] in
            self?.earsStep &+= 1
        }
    }
}

struct NotchActions {
    var activate: (Session) -> Void = { _ in }
    var openDesktop: () -> Void = {}
    var clearEnded: () -> Void = {}
    var quit: () -> Void = {}
    /// Révèle un fichier (ou un dépôt) dans le Finder.
    var revealFile: (String) -> Void = { _ in }
    var openSettings: () -> Void = {}
}

final class NotchPanel: NSPanel {
    override var canBecomeKey: Bool { true }
    override var canBecomeMain: Bool { false }

    /// Pas de recadrage sous la barre de menus : le panneau doit coller au bord haut.
    override func constrainFrameRect(_ frameRect: NSRect, to screen: NSScreen?) -> NSRect { frameRect }
}

/// Les clics passent sans activer l'app (premier clic accepté).
final class FirstMouseHostingView<Content: View>: NSHostingView<Content> {
    override func acceptsFirstMouse(for event: NSEvent?) -> Bool { true }
}

/// Fenêtre de la notch : position, survol, ouverture/fermeture, visibilité.
final class NotchController {
    static let earWidth: CGFloat = 36
    /// Assez large pour la largeur libre maximale (720 pt), ses rayons et son ombre.
    static let panelSize = CGSize(width: 800, height: 480)
    private static let hideDelay: TimeInterval = 3
    /// Après un changement de Space, le temps que l'animation se termine.
    private static let spaceSettleDelay: TimeInterval = 0.4
    /// Au-dessus de la barre des menus (24) et de ses icônes (25).
    static let windowLevel = NSWindow.Level(rawValue: NSWindow.Level.mainMenu.rawValue + 3)

    let model = NotchViewModel()
    let registry: ModuleRegistry
    let panel: NotchPanel

    private let store: SessionStore
    private let monitor: ClaudeMonitor
    private let prefs: Preferences
    private let claude: ClaudeModule
    private let settings: SettingsWindow

    private var screenFrame = CGRect.zero
    /// Écran de la notch, pour la détection du plein écran.
    private var displayID: CGDirectDisplayID?
    private var notchRect = CGRect.zero
    private var eventMonitors: [Any] = []
    private var pollTimer: Timer?
    private var openWork: DispatchWorkItem?
    private var closeWork: DispatchWorkItem?
    private var hideWork: DispatchWorkItem?
    private var suppressUntilExit = false
    private var menuTracking = false
    private var isShown = false { didSet { model.isShown = isShown } }
    private var cancellables = Set<AnyCancellable>()
    private var observers: [(NotificationCenter, NSObjectProtocol)] = []
    /// Compteur du presse-papiers de glisser relevé au dernier clic dans une autre app (Étagère).
    private var fileDragBaseline: Int?
    /// Notch montrée seulement à la demande (dépôt sur l'Étagère, raccourci) : recachée au repli.
    private var shownOnDemand = false
    /// Panneau ouvert par le raccourci : il a le clavier et ne se ferme pas quand la souris est ailleurs.
    private var openedByKeyboard = false
    /// Fin du masquage temporaire (une seule échéance, jamais de scrutation).
    private var unhideTimer: Timer?
    /// Horloge du masquage temporaire.
    var now: () -> Date = Date.init
    /// Onglet d'avant qu'un glisser de fichiers montre l'Étagère ; nil dès qu'un dépôt a lieu.
    private var tabBeforeDrag: String?

    init(store: SessionStore, monitor: ClaudeMonitor, prefs: Preferences, tools: ToolsFeed) {
        self.store = store
        self.monitor = monitor
        self.prefs = prefs
        claude = ClaudeModule(store: store, monitor: monitor, tools: tools, prefs: prefs)
        registry = ModuleRegistry(modules: ModuleRegistry.standardModules(claude: claude), prefs: prefs)
        settings = SettingsWindow(prefs: prefs, registry: registry)

        panel = NotchPanel(contentRect: NSRect(origin: .zero, size: Self.panelSize),
                           styleMask: [.borderless, .nonactivatingPanel],
                           backing: .buffered, defer: false)
        panel.isOpaque = false
        panel.backgroundColor = .clear
        panel.hasShadow = false
        // Avant `level` : ce setter remet le niveau à `.floating` (3, mesuré), sous la barre des menus.
        panel.isFloatingPanel = true
        panel.level = Self.windowLevel
        panel.collectionBehavior = [.canJoinAllSpaces, .stationary, .fullScreenAuxiliary, .ignoresCycle]
        panel.becomesKeyOnlyIfNeeded = true
        panel.hidesOnDeactivate = false
        panel.isMovable = false
        panel.isReleasedWhenClosed = false
        panel.animationBehavior = .none
        panel.ignoresMouseEvents = true
        panel.acceptsMouseMovedEvents = true
        // Appliqué tout de suite et à chaque changement (le publieur donne la nouvelle valeur).
        prefs.$hideFromCapture
            .sink { [weak panel] hidden in panel?.sharingType = Self.sharingType(hiddenFromCapture: hidden) }
            .store(in: &cancellables)
    }

    /// `.none` : absente des captures d'écran, enregistrements et partages (selon l'app qui capture).
    static func sharingType(hiddenFromCapture: Bool) -> NSWindow.SharingType {
        hiddenFromCapture ? .none : .readOnly
    }

    func start() {
        let actions = NotchActions(
            activate: { [weak self] session in self?.activate(session) },
            openDesktop: { [weak self] in self?.openDesktop() },
            clearEnded: { [weak self] in self?.store.clearEnded() },
            quit: { NSApp.terminate(nil) },
            revealFile: { [weak self] path in self?.reveal(path) },
            openSettings: { [weak self] in self?.openSettings() }
        )
        claude.actions = actions
        let root = NotchRootView(model: model, store: store, registry: registry, prefs: prefs, actions: actions)
        let hosting = FirstMouseHostingView(rootView: root)
        hosting.sizingOptions = []
        hosting.frame = NSRect(origin: .zero, size: Self.panelSize)
        hosting.autoresizingMask = [.width, .height]
        // Étagère : une vue AppKit sous le contenu SwiftUI reçoit les fichiers glissés sur le panneau déplié.
        let drop = ShelfDropView(frame: hosting.frame)
        drop.autoresizingMask = [.width, .height]
        drop.addSubview(hosting)
        drop.shelf = shelf
        drop.accepts = { [weak self] point in
            guard let self else { return false }
            return self.model.isExpanded && self.registry.isEnabled(ShelfModule.moduleId) && self.isInsideZone(point)
        }
        drop.showShelf = { [weak self] in
            guard let self, self.model.selectedTab != ShelfModule.moduleId else { return }
            self.tabBeforeDrag = self.model.selectedTab
            self.model.selectedTab = ShelfModule.moduleId
        }
        drop.dropped = { [weak self] in self?.tabBeforeDrag = nil }
        panel.contentView = drop

        model.reduceMotion = NSWorkspace.shared.accessibilityDisplayShouldReduceMotion
        model.isShown = isShown
        updateGeometry()
        installMouseMonitors()
        observeChanges()
        observeShellSettings()
        updateFullScreen()
        updateVisibility()
    }

    /// Réglages… (menu « … », ⌘,).
    func openSettings() {
        suppressUntilExit = true
        collapse()
        settings.show()
    }

    var debugInfo: [String: Any] {
        var info: [String: Any] = [
            "shown": isShown,
            "expanded": model.isExpanded,
            "hasNotch": model.hasNotch,
            "notchRect": [notchRect.minX, notchRect.minY, notchRect.width, notchRect.height],
            "panelFrame": [panel.frame.minX, panel.frame.minY, panel.frame.width, panel.frame.height],
            "contentSize": [model.contentSize.width, model.contentSize.height],
            "ignoresMouse": panel.ignoresMouseEvents,
            "polling": pollTimer != nil,
            "level": panel.level.rawValue,
            "isOnActiveSpace": panel.isOnActiveSpace,
            "isVisible": panel.isVisible,
            "occlusionVisible": panel.occlusionState.contains(.visible),
            "fullScreen": model.isFullScreen,
            "fullScreenBehavior": prefs.fullScreenBehavior.rawValue,
            "selectedTab": model.selectedTab,
            "modules": registry.debugInfo,
            // Contenus des oreilles repliées (identifiants seulement) et alternance en cours.
            "earsSlots": registry.earsSlots(claude: store.indicator).map { $0.id },
            "earsRotating": model.isRotatingEars,
            "visibility": prefs.visibility.rawValue,
            "openTrigger": prefs.openTrigger.rawValue,
            "closeOnClickOutside": prefs.closeOnClickOutside,
            "openedByKeyboard": openedByKeyboard,
            "hotKeys": [prefs.toggleHotKey.rawValue, prefs.hideHotKey.rawValue],
            "hotKeysUnavailable": HotKeyCenter.shared.unavailable.map { $0.rawValue }.sorted(),
            "panelWidth": prefs.expandedWidth(compact: false),
            "background": prefs.panelBackground.rawValue,
            "reduceMotion": model.reduceMotion,
            "sharingType": panel.sharingType == .none ? "none" : "readOnly",
        ]
        // Choix de l'écran sans son nom (le nom de l'écran utilisé est déjà sous `screen`).
        let choices = [ScreenChoice.builtin, ScreenChoice.main, ScreenChoice.mouse]
        info["screenChoice"] = choices.contains(prefs.screenChoice) ? prefs.screenChoice : "named"
        if let until = prefs.hiddenUntil {
            info["hiddenUntil"] = until == .distantFuture ? "untilReactivated" : ISO8601DateFormatter().string(from: until)
        }
        // Niveau vu par le serveur de fenêtres : celui qui compte face à la barre des menus et au plein écran.
        info["windowServerLevel"] = Self.windowServerLevel(of: panel)
        if let screen = panel.screen {
            info["screen"] = [
                "name": screen.localizedName,
                "frame": [screen.frame.minX, screen.frame.minY, screen.frame.width, screen.frame.height],
            ]
        }
        info["frontmostApp"] = NSWorkspace.shared.frontmostApplication?.bundleIdentifier
        return info
    }

    /// Couche (`kCGWindowLayer`) de la fenêtre selon CGWindowList ; nil si elle n'est pas à l'écran.
    static func windowServerLevel(of window: NSWindow) -> Int? {
        guard window.windowNumber > 0,
              let list = CGWindowListCopyWindowInfo(.optionIncludingWindow, CGWindowID(window.windowNumber))
                as? [[String: Any]] else { return nil }
        return (list.first?[kCGWindowLayer as String] as? NSNumber)?.intValue
    }

    // MARK: - Géométrie

    /// Écran choisi dans les réglages (intégré, principal, sous la souris, ou par nom), relu à chaque appel.
    private func updateGeometry() {
        let screens = NSScreen.screens
        let candidates = screens.map(ScreenCandidate.init)
        guard let index = NotchScreenPicker.pick(prefs.screenChoice, among: candidates,
                                                 mouse: NSEvent.mouseLocation) else { return }
        let screen = screens[index]
        let frame = screen.frame
        screenFrame = frame

        let previousDisplay = displayID
        displayID = (screen.deviceDescription[NSDeviceDescriptionKey("NSScreenNumber")] as? NSNumber)?.uint32Value
        // Écran sans encoche (externe, capot fermé) : encoche virtuelle centrée, hauteur de la barre des menus.
        let notch = NotchScreenPicker.notchRect(on: candidates[index], menuBarThickness: NSStatusBar.system.thickness)
        notchRect = notch.rect
        if model.hasNotch != notch.hasNotch { model.hasNotch = notch.hasNotch }
        if model.notchSize != notchRect.size { model.notchSize = notchRect.size }
        if previousDisplay != nil, previousDisplay != displayID { updateFullScreen() }

        let size = Self.panelSize
        let origin = CGPoint(x: (notchRect.midX - size.width / 2).rounded(), y: frame.maxY - size.height)
        panel.setFrame(NSRect(origin: origin, size: size), display: true)
    }

    // MARK: - Survol

    private func installMouseMonitors() {
        let mask: NSEvent.EventTypeMask = [.mouseMoved, .leftMouseDragged]
        // Clic dans une autre app : arme la détection d'un glisser de fichiers vers l'Étagère (`openForFileDrag`),
        // ouvre le panneau en mode « au clic », ferme un panneau qui attend un clic à l'extérieur.
        // Clic droit sur la notch repliée : menu contextuel.
        let globalMask = mask.union([.leftMouseDown, .rightMouseDown])
        if let global = NSEvent.addGlobalMonitorForEvents(matching: globalMask, handler: { [weak self] event in
            guard let self else { return }
            switch event.type {
            case .leftMouseDown:
                self.mouseDown()
                self.armFileDrag()
            case .rightMouseDown:
                self.showContextMenu()
            case .leftMouseDragged where self.openForFileDrag():
                return
            default:
                self.mouseMoved()
            }
        }) {
            eventMonitors.append(global)
        }
        let localMask = mask.union(.leftMouseDown)
        if let local = NSEvent.addLocalMonitorForEvents(matching: localMask, handler: { [weak self] event in
            guard let self else { return event }
            if event.type != .leftMouseDown {
                self.mouseMoved()
            } else if event.window !== self.panel {
                // Clic dans une autre fenêtre de l'app (réglages) ; ceux du panneau restent aux vues.
                self.mouseDown()
            }
            return event
        }) {
            eventMonitors.append(local)
        }
        // Touches du panneau quand il a le clavier (ouvert par le raccourci) ; sinon l'événement suit son cours.
        if let keys = NSEvent.addLocalMonitorForEvents(matching: .keyDown, handler: { [weak self] event in
            guard let self, self.handleKey(event) else { return event }
            return nil
        }) {
            eventMonitors.append(keys)
        }
    }

    /// Zone de survol en coordonnées écran : la notch (et ses oreilles) repliée, le panneau déplié.
    private func hoverZone() -> CGRect {
        let size = model.contentSize
        let width: CGFloat
        let height: CGFloat
        if model.isExpanded {
            width = max(size.width, prefs.expandedWidth(compact: isCompact)) + 8
            height = max(size.height, notchRect.height + 40) + 8
        } else {
            width = max(size.width, notchRect.width) + 8
            height = notchRect.height + 2
        }
        return CGRect(x: notchRect.midX - width / 2, y: screenFrame.maxY - height, width: width, height: height)
    }

    /// Bords inclusifs : la souris peut être pile sur le bord haut de l'écran.
    private func isInsideZone(_ point: CGPoint) -> Bool {
        let zone = hoverZone()
        return point.x >= zone.minX && point.x <= zone.maxX && point.y >= zone.minY && point.y <= zone.maxY
    }

    private func mouseMoved() {
        followMouseScreen()
        guard isShown else { return }
        let inside = isInsideZone(NSEvent.mouseLocation)
        if !inside { suppressUntilExit = false }

        if model.isExpanded {
            if inside {
                closeWork?.cancel()
                closeWork = nil
            } else if closeWork == nil, !menuTracking, !staysOpenOutside {
                let work = DispatchWorkItem { [weak self] in
                    guard let self else { return }
                    self.closeWork = nil
                    if !self.menuTracking, !self.isInsideZone(NSEvent.mouseLocation) { self.collapse() }
                }
                closeWork = work
                DispatchQueue.main.asyncAfter(deadline: .now() + prefs.closeDelay, execute: work)
            }
        } else if inside, !suppressUntilExit, prefs.openTrigger == .hover {
            guard openWork == nil else { return }
            let work = DispatchWorkItem { [weak self] in
                guard let self else { return }
                self.openWork = nil
                if self.isShown, !self.suppressUntilExit, self.isInsideZone(NSEvent.mouseLocation) { self.expand() }
            }
            openWork = work
            DispatchQueue.main.asyncAfter(deadline: .now() + prefs.openDelay, execute: work)
        } else {
            openWork?.cancel()
            openWork = nil
        }
    }

    /// Fermé par un clic à l'extérieur (réglage, ou panneau ouvert au clavier), pas par la sortie de la souris.
    private var staysOpenOutside: Bool { prefs.closeOnClickOutside || openedByKeyboard }

    /// Mode « au clic » : clic sur la notch repliée. Panneau ouvert qui attend un clic à l'extérieur : il se ferme.
    private func mouseDown() {
        guard isShown else { return }
        let inside = isInsideZone(NSEvent.mouseLocation)
        if model.isExpanded {
            // Un clic dans un menu ouvert depuis le panneau (« … ») n'est pas un clic à l'extérieur.
            if !inside, staysOpenOutside, !menuTracking { collapse() }
        } else if inside, prefs.openTrigger == .click {
            openWork?.cancel()
            openWork = nil
            expand()
        }
    }

    /// Écran « sous la souris » : la notch suit la souris d'un écran à l'autre, repliée seulement. Événementiel
    /// (mouvements de souris déjà reçus) ; rien n'est recalculé tant que la souris reste sur le même écran.
    private func followMouseScreen() {
        guard prefs.screenChoice == ScreenChoice.mouse, !model.isExpanded,
              !NotchScreenPicker.contains(screenFrame, NSEvent.mouseLocation) else { return }
        updateGeometry()
    }

    private var isCompact: Bool { model.isFullScreen && prefs.fullScreenBehavior == .compact }

    private func expand(tab: String? = nil) {
        guard !model.isExpanded else { return }
        panel.ignoresMouseEvents = false
        model.selectedTab = tab ?? registry.initialTab(claudeNeedsAttention: store.indicator == .attention)
        model.isExpanded = true
        if prefs.hapticFeedback {
            NSHapticFeedbackManager.defaultPerformer.perform(.alignment, performanceTime: .now)
        }
        startPolling()
        registry.setPanelOpen(true)
    }

    private func collapse() {
        openWork?.cancel()
        openWork = nil
        closeWork?.cancel()
        closeWork = nil
        stopPolling()
        // Le clavier revient à l'app de devant (panneau ouvert au raccourci, ou champ resté actif).
        if panel.isKeyWindow { NotchKeyboard.release(force: true) }
        openedByKeyboard = false
        panel.ignoresMouseEvents = true
        if model.isExpanded {
            model.isExpanded = false
            let tab = Self.tabToRemember(selected: model.selectedTab, beforeDrag: tabBeforeDrag)
            if prefs.lastTab != tab { prefs.lastTab = tab }
        }
        tabBeforeDrag = nil
        registry.setPanelOpen(false)
        shownOnDemand = false
        // Dépliée, la notch restait affichée même sans activité : on relit la règle.
        if isShown { updateVisibility() }
    }

    /// 15 Hz, seulement déplié : rattrape les mouvements que les moniteurs ne voient pas.
    private func startPolling() {
        guard pollTimer == nil else { return }
        let timer = Timer(timeInterval: 1.0 / 15.0, repeats: true) { [weak self] _ in self?.mouseMoved() }
        RunLoop.main.add(timer, forMode: .common)
        pollTimer = timer
    }

    private func stopPolling() {
        pollTimer?.invalidate()
        pollTimer = nil
    }

    // MARK: - Glisser-déposer (Étagère)

    private var shelf: ShelfModule? { registry.module(ShelfModule.moduleId) as? ShelfModule }

    /// Pendant un glisser, plus de `mouseMoved` : seuls des `leftMouseDragged` arrivent, et la fenêtre repliée
    /// laisse passer la souris. Un nouveau contenu du presse-papiers de glisser depuis le clic = un glisser commencé.
    private func armFileDrag() {
        fileDragBaseline = registry.isEnabled(ShelfModule.moduleId) ? NSPasteboard(name: .drag).changeCount : nil
    }

    /// Glisser de fichiers au-dessus de la notch repliée : déplie tout de suite sur l'Étagère, puis `ShelfDropView`
    /// prend le relais (fenêtre qui accepte la souris). Une fois par glisser ; jamais en plein écran « masquée ».
    private func openForFileDrag() -> Bool {
        guard let baseline = fileDragBaseline, !model.isExpanded, !hiddenForFullScreen, !prefs.isHidden(at: now()),
              Self.dropZone(notch: notchRect, screen: screenFrame, contentWidth: model.contentSize.width)
                .contains(NSEvent.mouseLocation) else { return false }
        let pasteboard = NSPasteboard(name: .drag)
        guard pasteboard.changeCount != baseline else { return false }
        fileDragBaseline = nil
        guard ShelfDrop.hasFiles(pasteboard) else { return false }
        showOnDemand()
        tabBeforeDrag = prefs.lastTab
        expand(tab: ShelfModule.moduleId)
        shelf?.isDropTargeted = true
        return true
    }

    /// Notch repliée : la forme et la place des oreilles, élargies (le glisser arrive vite et de biais).
    static func dropZone(notch: CGRect, screen: CGRect, contentWidth: CGFloat) -> CGRect {
        let width = max(contentWidth, notch.width + 2 * earWidth) + 40
        let height = notch.height + 16
        // +1 : la souris peut être pile sur le bord haut de l'écran.
        return CGRect(x: notch.midX - width / 2, y: screen.maxY - height, width: width, height: height + 1)
    }

    /// Onglet mémorisé au repli : l'Étagère montrée par un glisser de fichiers resté sans dépôt ne compte pas.
    static func tabToRemember(selected: String, beforeDrag: String?) -> String {
        selected == ShelfModule.moduleId ? beforeDrag ?? selected : selected
    }

    // MARK: - Actions

    private func activate(_ session: Session) {
        if session.source == .desktop, let url = session.desktopSessionId.flatMap(Self.desktopSessionURL) {
            Self.openInDesktop(url)
        } else {
            let bundleId = session.hostBundleId ?? (session.source == .desktop ? ProcessInspector.desktopBundleId : nil)
            if let bundleId { Self.bringToFront(bundleId: bundleId) }
        }
        suppressUntilExit = true
        collapse()
    }

    /// Lien reconnu par Claude Desktop (gestionnaire `open-url`, hôte `code`, chemin `/continue`) :
    /// il ouvre la session locale dont l'identifiant est exactement `session`, sinon l'accueil de l'onglet Code.
    static func desktopSessionURL(_ sessionId: String) -> URL? {
        guard HookHeaders.isDesktopSessionId(sessionId) else { return nil }
        var components = URLComponents()
        components.scheme = "claude"
        components.host = "code"
        components.path = "/continue"
        components.queryItems = [URLQueryItem(name: "session", value: sessionId)]
        return components.url
    }

    /// Ouvre le lien avec Claude Desktop explicitement, pas avec une autre app qui revendiquerait `claude://`.
    private static func openInDesktop(_ url: URL) {
        guard let app = NSWorkspace.shared.urlForApplication(withBundleIdentifier: ProcessInspector.desktopBundleId) else {
            bringToFront(bundleId: ProcessInspector.desktopBundleId)
            return
        }
        let configuration = NSWorkspace.OpenConfiguration()
        configuration.activates = true
        NSWorkspace.shared.open([url], withApplicationAt: app, configuration: configuration) { _, _ in }
    }

    /// Sélectionne le fichier dans le Finder ; s'il a disparu, son plus proche dossier parent encore présent.
    private func reveal(_ path: String) {
        guard let target = Self.revealTarget(for: path) else { return }
        NSWorkspace.shared.activateFileViewerSelecting([target])
        Self.bringToFront(bundleId: "com.apple.finder")
        suppressUntilExit = true
        collapse()
    }

    static func revealTarget(for path: String, fileManager: FileManager = .default) -> URL? {
        var url = URL(fileURLWithPath: path).standardizedFileURL
        while !fileManager.fileExists(atPath: url.path) {
            let parent = url.deletingLastPathComponent()
            if parent.path == url.path { return nil }
            url = parent
        }
        return url
    }

    private func openDesktop() {
        Self.bringToFront(bundleId: ProcessInspector.desktopBundleId)
        suppressUntilExit = true
        collapse()
    }

    /// Passe par LaunchServices : une app en arrière-plan ne peut plus toujours en activer une autre directement.
    static func bringToFront(bundleId: String) {
        if let url = NSWorkspace.shared.urlForApplication(withBundleIdentifier: bundleId) {
            let configuration = NSWorkspace.OpenConfiguration()
            configuration.activates = true
            NSWorkspace.shared.openApplication(at: url, configuration: configuration) { _, _ in }
        } else {
            NSRunningApplication.runningApplications(withBundleIdentifier: bundleId).first?
                .activate(options: [.activateAllWindows])
        }
    }

    // MARK: - Visibilité

    private func observeChanges() {
        Publishers.Merge4(store.objectWillChange, monitor.objectWillChange, prefs.objectWillChange,
                          registry.objectWillChange)
            .receive(on: DispatchQueue.main)
            .sink { [weak self] _ in self?.updateVisibility() }
            .store(in: &cancellables)

        let center = NotificationCenter.default
        observers.append((center, center.addObserver(forName: NSApplication.didChangeScreenParametersNotification,
                                                     object: nil, queue: .main) { [weak self] _ in
            self?.updateGeometry()
            self?.updateFullScreen()
        }))
        observers.append((center, center.addObserver(forName: NSMenu.didBeginTrackingNotification,
                                                     object: nil, queue: .main) { [weak self] _ in
            self?.menuTracking = true
        }))
        observers.append((center, center.addObserver(forName: NSMenu.didEndTrackingNotification,
                                                     object: nil, queue: .main) { [weak self] _ in
            self?.menuTracking = false
            self?.mouseMoved()
        }))

        let workspace = NSWorkspace.shared.notificationCenter
        observers.append((workspace, workspace.addObserver(forName: NSWorkspace.activeSpaceDidChangeNotification,
                                                           object: nil, queue: .main) { [weak self] _ in
            self?.spaceDidChange()
        }))
        observers.append((workspace, workspace.addObserver(forName: NSWorkspace.didActivateApplicationNotification,
                                                           object: nil, queue: .main) { [weak self] _ in
            self?.followMouseScreen()
            self?.updateFullScreen()
        }))
    }

    private func spaceDidChange() {
        updateFullScreen()
        if isShown {
            updateGeometry()
            panel.orderFrontRegardless()
        }
        // L'animation de changement de Space peut repasser devant, et la fenêtre plein écran n'est pas encore
        // toujours listée : on vérifie de nouveau une fois l'animation finie.
        DispatchQueue.main.asyncAfter(deadline: .now() + Self.spaceSettleDelay) { [weak self] in
            guard let self else { return }
            self.updateFullScreen()
            if self.isShown { self.panel.orderFrontRegardless() }
        }
    }

    /// Événementiel (Space, app activée, écrans) : jamais de scrutation.
    private func updateFullScreen() {
        let fullScreen = displayID.map { FullScreenDetector.frontmostAppIsFullScreen(onDisplay: $0) } ?? false
        guard fullScreen != model.isFullScreen else { return }
        model.isFullScreen = fullScreen
        updateVisibility()
    }

    /// Plein écran avec le réglage « masquée ».
    private var hiddenForFullScreen: Bool { model.isFullScreen && prefs.fullScreenBehavior == .hidden }

    /// « Masquer la notch » en cours.
    private var hiddenByUser: Bool { prefs.isHidden(at: now()) }

    /// Sans l'onglet Claude, seules les oreilles des modules comptent (« Quand Claude est ouvert » vaut « Toujours »).
    private var shouldShow: Bool {
        let claude = registry.isClaudeEnabled
        let mode = prefs.visibility.effective(claudeEnabled: claude)
        return NotchVisibilityRule.shouldShow(mode, NotchVisibilityRule.Inputs(
            claudeOpen: claude && (monitor.desktopRunning || !monitor.cliPids.isEmpty || store.hasLiveSessions),
            claudeActive: claude && store.indicator != .none,
            moduleEars: registry.moduleEars != nil,
            onDemand: shownOnDemand,
            expanded: model.isExpanded,
            hiddenForFullScreen: hiddenForFullScreen,
            hiddenByUser: hiddenByUser))
    }

    private func updateVisibility() {
        // Masquage temporaire échu : on l'oublie (le rappel des réglages disparaît).
        if let until = prefs.hiddenUntil, until <= now() { prefs.hiddenUntil = nil }
        if shouldShow {
            hideWork?.cancel()
            hideWork = nil
            if !isShown {
                isShown = true
                updateGeometry()
                panel.orderFrontRegardless()
            }
        } else if isShown, hiddenForFullScreen || hiddenByUser {
            hide()
        } else if isShown, hideWork == nil {
            // Délai anti-clignotement.
            let work = DispatchWorkItem { [weak self] in
                guard let self else { return }
                self.hideWork = nil
                if !self.shouldShow { self.hide() }
            }
            hideWork = work
            DispatchQueue.main.asyncAfter(deadline: .now() + Self.hideDelay, execute: work)
        }
    }

    private func hide() {
        hideWork?.cancel()
        hideWork = nil
        isShown = false
        collapse()
        panel.orderOut(nil)
    }

    /// Montre la notch le temps d'un usage explicite (dépôt sur l'Étagère, raccourci), même hors de sa règle de
    /// visibilité ; `collapse()` la rend à sa règle.
    private func showOnDemand() {
        if !shouldShow {
            shownOnDemand = true
            hideWork?.cancel()
            hideWork = nil
        }
        if !isShown {
            isShown = true
            updateGeometry()
            panel.orderFrontRegardless()
        }
    }

    // MARK: - Réglages de la notch appliqués à chaud

    private func observeShellSettings() {
        // Le publieur donne la nouvelle valeur avant qu'elle ne soit rangée : on relit au tour suivant.
        prefs.$screenChoice.dropFirst().removeDuplicates()
            .receive(on: DispatchQueue.main)
            .sink { [weak self] _ in
                guard let self, !self.model.isExpanded else { return }
                self.updateGeometry()
            }
            .store(in: &cancellables)
        prefs.$hiddenUntil
            .receive(on: DispatchQueue.main)
            .sink { [weak self] _ in self?.scheduleUnhide() }
            .store(in: &cancellables)
        Publishers.Merge(prefs.$toggleHotKey.map { _ in () }, prefs.$hideHotKey.map { _ in () })
            .receive(on: DispatchQueue.main)
            .sink { [weak self] in self?.registerHotKeys() }
            .store(in: &cancellables)

        let workspace = NSWorkspace.shared.notificationCenter
        observers.append((workspace, workspace.addObserver(
            forName: NSWorkspace.accessibilityDisplayOptionsDidChangeNotification, object: nil, queue: .main
        ) { [weak self] _ in
            self?.model.reduceMotion = NSWorkspace.shared.accessibilityDisplayShouldReduceMotion
        }))
        // Un minuteur ne compte pas le temps de veille : au réveil, l'échéance est relue.
        observers.append((workspace, workspace.addObserver(forName: NSWorkspace.didWakeNotification,
                                                           object: nil, queue: .main) { [weak self] _ in
            self?.updateVisibility()
        }))
    }

    /// Une seule échéance pour la fin du masquage temporaire (rien pour « jusqu'à réactivation »).
    private func scheduleUnhide() {
        unhideTimer?.invalidate()
        unhideTimer = nil
        guard let until = prefs.hiddenUntil, until != .distantFuture, until > now() else { return }
        let timer = Timer(fire: until, interval: 0, repeats: false) { [weak self] _ in
            self?.unhideTimer = nil
            self?.updateVisibility()
        }
        timer.tolerance = 5
        RunLoop.main.add(timer, forMode: .common)
        unhideTimer = timer
    }

    // MARK: - Clavier

    /// Tout est retiré avant d'enregistrer : une combinaison qui passe d'une action à l'autre serait refusée.
    private func registerHotKeys() {
        let center = HotKeyCenter.shared
        center.set(.none, for: .togglePanel) {}
        center.set(.none, for: .toggleHidden) {}
        center.set(prefs.toggleHotKey, for: .togglePanel) { [weak self] in self?.togglePanelFromKeyboard() }
        center.set(prefs.hideHotKey, for: .toggleHidden) { [weak self] in self?.toggleHiddenFromKeyboard() }
    }

    /// Raccourci global : ouvre le panneau avec le clavier (même notch masquée), ou le ferme.
    func togglePanelFromKeyboard() {
        if model.isExpanded {
            suppressUntilExit = true
            collapse()
            return
        }
        showOnDemand()
        if prefs.screenChoice == ScreenChoice.mouse { updateGeometry() }
        expand()
        openedByKeyboard = true
        NotchKeyboard.take()
    }

    /// Raccourci global : masque la notch jusqu'à réactivation, ou la réaffiche.
    func toggleHiddenFromKeyboard() {
        if prefs.isHidden(at: now()) { prefs.showAgain() } else { prefs.hide(.untilReactivated, now: now()) }
    }

    /// Panneau ouvert au raccourci : ← → et ⌘1…⌘9 changent d'onglet, Échap ferme et rend le clavier (plein écran
    /// compact compris). Ouvert au survol ou au clic, rien ne change (les champs des modules gardent leurs touches).
    func handleKey(_ event: NSEvent) -> Bool {
        guard openedByKeyboard, model.isExpanded, panel.isKeyWindow,
              let command = NotchKeyCommand.parse(keyCode: event.keyCode, modifiers: event.modifierFlags,
                                                  editingText: panel.firstResponder is NSText) else { return false }
        if command == .close {
            suppressUntilExit = true
            collapse()
            return true
        }
        // Plein écran compact : pas d'onglets.
        guard !isCompact else { return false }
        let tabs = registry.enabled.map { $0.id }
        guard let index = command.target(current: tabs.firstIndex(of: model.selectedTab) ?? 0, count: tabs.count)
        else { return false }
        model.selectedTab = tabs[index]
        return true
    }

    // MARK: - Menu contextuel

    /// Clic droit sur la notch repliée (la forme seule, pas les oreilles posées sur la barre des menus).
    private func showContextMenu() {
        let mouse = NSEvent.mouseLocation
        guard isShown, !model.isExpanded,
              NotchScreenPicker.contains(notchRect.insetBy(dx: -2, dy: -2), mouse) else { return }
        let menu = NSMenu()
        let hide = NSMenuItem(title: L("Masquer la notch"), action: nil, keyEquivalent: "")
        let durations = NSMenu()
        for duration in HideDuration.allCases {
            durations.addItem(ClosureMenuItem(Self.title(duration)) { [weak self] in
                guard let self else { return }
                self.prefs.hide(duration, now: self.now())
            })
        }
        durations.addItem(.separator())
        let hint = NSMenuItem(title: HiddenNotice.howToShowAgain(hotKey: prefs.hideHotKey), action: nil, keyEquivalent: "")
        hint.isEnabled = false
        durations.addItem(hint)
        hide.submenu = durations
        menu.addItem(hide)
        menu.addItem(.separator())
        menu.addItem(ClosureMenuItem(L("Réglages…")) { [weak self] in self?.openSettings() })
        menu.popUp(positioning: nil, at: mouse, in: nil)
    }

    static func title(_ duration: HideDuration) -> String {
        switch duration {
        case .oneHour: return L("Pendant 1 heure")
        case .untilTomorrow: return L("Jusqu'à demain")
        case .untilReactivated: return L("Jusqu'à réactivation")
        }
    }
}
