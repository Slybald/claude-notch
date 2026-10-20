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
    /// Taille réelle de la forme noire, mesurée par la vue. Sert aux zones de survol.
    var contentSize: CGSize = .zero
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
    /// Assez large pour le grand panneau (620 pt), ses rayons et son ombre.
    static let panelSize = CGSize(width: 700, height: 480)
    private static let fakeNotchWidth: CGFloat = 200
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
    private var isShown = false
    private var cancellables = Set<AnyCancellable>()
    private var observers: [(NotificationCenter, NSObjectProtocol)] = []
    /// Compteur du presse-papiers de glisser relevé au dernier clic dans une autre app (Étagère).
    private var fileDragBaseline: Int?
    /// Notch montrée seulement pour un dépôt (rien d'autre à afficher) : recachée au repli.
    private var shownForDrag = false

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
        drop.showShelf = { [weak self] in self?.model.selectedTab = ShelfModule.moduleId }
        panel.contentView = drop

        updateGeometry()
        installMouseMonitors()
        observeChanges()
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
        ]
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

    private func updateGeometry() {
        guard let screen = NSScreen.screens.first(where: { $0.safeAreaInsets.top > 0 })
                ?? NSScreen.screens.first ?? NSScreen.main else { return }
        let frame = screen.frame
        screenFrame = frame

        displayID = (screen.deviceDescription[NSDeviceDescriptionKey("NSScreenNumber")] as? NSNumber)?.uint32Value
        if screen.safeAreaInsets.top > 0,
           let left = screen.auxiliaryTopLeftArea, let right = screen.auxiliaryTopRightArea {
            let height = screen.safeAreaInsets.top
            let width = frame.width - left.width - right.width
            notchRect = CGRect(x: frame.minX + left.width, y: frame.maxY - height, width: width, height: height)
            model.hasNotch = true
        } else {
            // Écran sans notch (externe, capot fermé) : fausse notch centrée, hauteur de la barre de menus.
            let menuBar = max(frame.maxY - screen.visibleFrame.maxY, NSStatusBar.system.thickness)
            notchRect = CGRect(x: frame.midX - Self.fakeNotchWidth / 2, y: frame.maxY - menuBar,
                               width: Self.fakeNotchWidth, height: menuBar)
            model.hasNotch = false
        }
        if model.notchSize != notchRect.size { model.notchSize = notchRect.size }

        let size = Self.panelSize
        let origin = CGPoint(x: (notchRect.midX - size.width / 2).rounded(), y: frame.maxY - size.height)
        panel.setFrame(NSRect(origin: origin, size: size), display: true)
    }

    // MARK: - Survol

    private func installMouseMonitors() {
        let mask: NSEvent.EventTypeMask = [.mouseMoved, .leftMouseDragged]
        // Clic dans une autre app : arme la détection d'un glisser de fichiers vers l'Étagère (`openForFileDrag`).
        let globalMask = mask.union(.leftMouseDown)
        if let global = NSEvent.addGlobalMonitorForEvents(matching: globalMask, handler: { [weak self] event in
            guard let self else { return }
            if event.type == .leftMouseDown { return self.armFileDrag() }
            if event.type == .leftMouseDragged, self.openForFileDrag() { return }
            self.mouseMoved()
        }) {
            eventMonitors.append(global)
        }
        if let local = NSEvent.addLocalMonitorForEvents(matching: mask, handler: { [weak self] event in
            self?.mouseMoved()
            return event
        }) {
            eventMonitors.append(local)
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
        guard isShown else { return }
        let inside = isInsideZone(NSEvent.mouseLocation)
        if !inside { suppressUntilExit = false }

        if model.isExpanded {
            if inside {
                closeWork?.cancel()
                closeWork = nil
            } else if closeWork == nil, !menuTracking {
                let work = DispatchWorkItem { [weak self] in
                    guard let self else { return }
                    self.closeWork = nil
                    if !self.menuTracking, !self.isInsideZone(NSEvent.mouseLocation) { self.collapse() }
                }
                closeWork = work
                DispatchQueue.main.asyncAfter(deadline: .now() + prefs.closeDelay, execute: work)
            }
        } else if inside, !suppressUntilExit {
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
        panel.ignoresMouseEvents = true
        if model.isExpanded {
            model.isExpanded = false
            if prefs.lastTab != model.selectedTab { prefs.lastTab = model.selectedTab }
        }
        registry.setPanelOpen(false)
        if shownForDrag {
            shownForDrag = false
            updateVisibility()
        }
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
        guard let baseline = fileDragBaseline, !model.isExpanded, !hiddenForFullScreen,
              dropZone().contains(NSEvent.mouseLocation) else { return false }
        let pasteboard = NSPasteboard(name: .drag)
        guard pasteboard.changeCount != baseline else { return false }
        fileDragBaseline = nil
        guard ShelfDrop.hasFiles(pasteboard) else { return false }
        if !shouldShow {
            shownForDrag = true
            hideWork?.cancel()
            hideWork = nil
        }
        if !isShown {
            isShown = true
            updateGeometry()
            panel.orderFrontRegardless()
        }
        expand(tab: ShelfModule.moduleId)
        shelf?.isDropTargeted = true
        return true
    }

    /// Notch repliée : la forme et la place des oreilles, élargies (le glisser arrive vite et de biais).
    private func dropZone() -> CGRect {
        let width = max(model.contentSize.width, notchRect.width + 2 * Self.earWidth) + 40
        let height = notchRect.height + 16
        // +1 : la souris peut être pile sur le bord haut de l'écran.
        return CGRect(x: notchRect.midX - width / 2, y: screenFrame.maxY - height, width: width, height: height + 1)
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

    private var shouldShow: Bool {
        guard !hiddenForFullScreen else { return false }
        return prefs.alwaysVisible || monitor.desktopRunning || !monitor.cliPids.isEmpty || store.hasLiveSessions
            || registry.moduleEars != nil || shownForDrag
    }

    private func updateVisibility() {
        if shouldShow {
            hideWork?.cancel()
            hideWork = nil
            if !isShown {
                isShown = true
                updateGeometry()
                panel.orderFrontRegardless()
            }
        } else if isShown, hiddenForFullScreen {
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
}
