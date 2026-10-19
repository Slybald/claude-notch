import AppKit
import Combine
import SwiftUI

/// État partagé entre le contrôleur (AppKit) et la vue (SwiftUI).
final class NotchViewModel: ObservableObject {
    @Published var isExpanded = false
    @Published var notchSize = CGSize(width: 200, height: 32)
    @Published var hasNotch = false
    /// Taille réelle de la forme noire, mesurée par la vue. Sert aux zones de survol.
    var contentSize: CGSize = .zero
}

struct NotchActions {
    var activate: (Session) -> Void
    var openDesktop: () -> Void
    var clearEnded: () -> Void
    var quit: () -> Void
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
    static let expandedWidth: CGFloat = 540
    static let maxExpandedHeight: CGFloat = 420
    static let earWidth: CGFloat = 36
    private static let panelSize = CGSize(width: 640, height: 480)
    private static let fakeNotchWidth: CGFloat = 200
    private static let openDelay: TimeInterval = 0.08
    private static let closeDelay: TimeInterval = 0.25
    private static let hideDelay: TimeInterval = 3

    let model = NotchViewModel()

    private let store: SessionStore
    private let monitor: ClaudeMonitor
    private let prefs: Preferences
    private let panel: NotchPanel

    private var screenFrame = CGRect.zero
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

    init(store: SessionStore, monitor: ClaudeMonitor, prefs: Preferences) {
        self.store = store
        self.monitor = monitor
        self.prefs = prefs

        panel = NotchPanel(contentRect: NSRect(origin: .zero, size: Self.panelSize),
                           styleMask: [.borderless, .nonactivatingPanel],
                           backing: .buffered, defer: false)
        panel.isOpaque = false
        panel.backgroundColor = .clear
        panel.hasShadow = false
        panel.level = NSWindow.Level(rawValue: NSWindow.Level.mainMenu.rawValue + 3)
        panel.collectionBehavior = [.canJoinAllSpaces, .stationary, .fullScreenAuxiliary, .ignoresCycle]
        panel.becomesKeyOnlyIfNeeded = true
        panel.isFloatingPanel = true
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
            quit: { NSApp.terminate(nil) }
        )
        let root = NotchRootView(model: model, store: store, monitor: monitor, prefs: prefs, actions: actions)
        let hosting = FirstMouseHostingView(rootView: root)
        hosting.sizingOptions = []
        hosting.frame = NSRect(origin: .zero, size: Self.panelSize)
        hosting.autoresizingMask = [.width, .height]
        panel.contentView = hosting

        updateGeometry()
        installMouseMonitors()
        observeChanges()
        updateVisibility()
    }

    // MARK: - Géométrie

    private func updateGeometry() {
        guard let screen = NSScreen.screens.first(where: { $0.safeAreaInsets.top > 0 })
                ?? NSScreen.screens.first ?? NSScreen.main else { return }
        let frame = screen.frame
        screenFrame = frame

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
        if let global = NSEvent.addGlobalMonitorForEvents(matching: mask, handler: { [weak self] _ in
            self?.mouseMoved()
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
            width = max(size.width, Self.expandedWidth) + 8
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
                DispatchQueue.main.asyncAfter(deadline: .now() + Self.closeDelay, execute: work)
            }
        } else if inside, !suppressUntilExit {
            guard openWork == nil else { return }
            let work = DispatchWorkItem { [weak self] in
                guard let self else { return }
                self.openWork = nil
                if self.isShown, !self.suppressUntilExit, self.isInsideZone(NSEvent.mouseLocation) { self.expand() }
            }
            openWork = work
            DispatchQueue.main.asyncAfter(deadline: .now() + Self.openDelay, execute: work)
        } else {
            openWork?.cancel()
            openWork = nil
        }
    }

    private func expand() {
        guard !model.isExpanded else { return }
        panel.ignoresMouseEvents = false
        model.isExpanded = true
        NSHapticFeedbackManager.defaultPerformer.perform(.alignment, performanceTime: .now)
        startPolling()
    }

    private func collapse() {
        openWork?.cancel()
        openWork = nil
        closeWork?.cancel()
        closeWork = nil
        stopPolling()
        panel.ignoresMouseEvents = true
        if model.isExpanded { model.isExpanded = false }
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

    // MARK: - Actions

    private func activate(_ session: Session) {
        let bundleId = session.hostBundleId ?? (session.source == .desktop ? ProcessInspector.desktopBundleId : nil)
        if let bundleId { Self.bringToFront(bundleId: bundleId) }
        suppressUntilExit = true
        collapse()
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
        Publishers.Merge3(store.objectWillChange, monitor.objectWillChange, prefs.objectWillChange)
            .receive(on: DispatchQueue.main)
            .sink { [weak self] _ in self?.updateVisibility() }
            .store(in: &cancellables)

        let center = NotificationCenter.default
        observers.append((center, center.addObserver(forName: NSApplication.didChangeScreenParametersNotification,
                                                     object: nil, queue: .main) { [weak self] _ in
            self?.updateGeometry()
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
            guard let self, self.isShown else { return }
            self.updateGeometry()
            self.panel.orderFrontRegardless()
        }))
    }

    private var shouldShow: Bool {
        prefs.alwaysVisible || monitor.desktopRunning || !monitor.cliPids.isEmpty || store.hasLiveSessions
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
        } else if isShown, hideWork == nil {
            // Délai anti-clignotement.
            let work = DispatchWorkItem { [weak self] in
                guard let self else { return }
                self.hideWork = nil
                guard !self.shouldShow else { return }
                self.isShown = false
                self.collapse()
                self.panel.orderOut(nil)
            }
            hideWork = work
            DispatchQueue.main.asyncAfter(deadline: .now() + Self.hideDelay, execute: work)
        }
    }
}
