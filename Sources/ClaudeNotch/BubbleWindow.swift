import AppKit
import Combine
import SwiftUI

/// Fenêtre de la bulle (et de son panneau). Classe à part : `NotchKeyboard` la préfère à la notch tant qu'elle est là.
final class BubblePanel: NSPanel {
    override var canBecomeKey: Bool { true }
    override var canBecomeMain: Bool { false }
    override func constrainFrameRect(_ frameRect: NSRect, to screen: NSScreen?) -> NSRect { frameRect }
}

/// Fenêtre de la goutte : ne prend jamais la souris, et dépasse du haut de l'écran (le flou n'y ronge pas la forme).
final class GooPanel: NSPanel {
    override func constrainFrameRect(_ frameRect: NSRect, to screen: NSScreen?) -> NSRect { frameRect }
}

/// Molette et clic droit de la bulle : SwiftUI n'a pas d'API de molette avant macOS 14. Panneau ouvert, tout suit son
/// cours (listes qui défilent, menus des modules).
final class BubbleHostingView<Content: View>: NSHostingView<Content> {
    var onScroll: (NSEvent) -> Bool = { _ in false }
    var contextMenu: () -> NSMenu? = { nil }

    override func acceptsFirstMouse(for event: NSEvent?) -> Bool { true }

    override func scrollWheel(with event: NSEvent) {
        if !onScroll(event) { super.scrollWheel(with: event) }
    }

    override func menu(for event: NSEvent) -> NSMenu? { contextMenu() ?? super.menu(for: event) }
}

/// Notch détachée : la bulle, son panneau, la goutte du décollage et du rattachement. Rien ne tourne au repos : pas de
/// minuteur, la goutte n'est dessinée que pendant ses animations, la fenêtre de la bulle n'existe qu'une fois détachée.
final class BubbleController {
    static var bubbleWindowSize: CGSize {
        let side = BubbleGeometry.diameter + 2 * BubbleGeometry.windowMargin
        return CGSize(width: side, height: side)
    }

    /// La goutte dépasse du haut de l'écran de cette hauteur.
    private static let gooOverflow: CGFloat = 30
    /// Le panneau qui se referme en bulle : le temps de la transition avant de réduire la fenêtre.
    private static let shrinkDelay: TimeInterval = 0.45

    let bubble = BubbleModel()
    let window: BubblePanel
    private let model: NotchViewModel
    private let prefs: Preferences
    private let registry: ModuleRegistry
    private let store: SessionStore
    private var gooWindow: GooPanel?
    private var gooFrame = CGRect.zero
    /// Chaque goutte a son numéro : la fin différée d'une goutte n'efface pas la suivante.
    private var gooGeneration = 0
    /// Glisser de décollage : panneau, notch et poignée (coordonnées écran).
    private var pull: (panel: CGRect, notch: CGRect, handle: CGPoint)?
    /// Écart souris − centre pendant un déplacement de la bulle ; nil hors déplacement.
    private var moveOffset: CGPoint?
    private var scroll = RevolverScroll()
    private var closeWork: DispatchWorkItem?
    private var shrinkWork: DispatchWorkItem?
    private var openedByKeyboard = false
    /// « Masquer la notch » ou plein écran « masquée » : la bulle se cache aussi.
    private var isSuppressed = false
    private var cancellables = Set<AnyCancellable>()
    /// Centre de la bulle (coordonnées écran).
    private(set) var center = CGPoint.zero
    /// Hauteur du dernier panneau mesuré (fenêtre ajustée dès l'ouverture).
    private var panelHeight: CGFloat?

    /// Rectangle de la notch et fenêtre de la notch (la goutte passe sous elle), fournis par `NotchController`.
    var notchRect: () -> CGRect = { .zero }
    var notchWindow: () -> NSWindow? = { nil }
    /// La notch se replie sans animation (cachée sous la goutte).
    var collapseNotch: () -> Void = {}
    /// La bulle est rentrée dans la notch.
    var didAttach: () -> Void = {}
    var openSettings: () -> Void = {}
    var isMenuTracking: () -> Bool = { false }
    var mouseLocation: () -> CGPoint = { NSEvent.mouseLocation }

    init(model: NotchViewModel, prefs: Preferences, registry: ModuleRegistry, store: SessionStore) {
        self.model = model
        self.prefs = prefs
        self.registry = registry
        self.store = store
        window = BubblePanel(contentRect: NSRect(origin: .zero, size: Self.bubbleWindowSize),
                             styleMask: [.borderless, .nonactivatingPanel], backing: .buffered, defer: true)
        Self.configure(window)
        window.acceptsMouseMovedEvents = true
        prefs.$hideFromCapture
            .sink { [weak self] hidden in
                let type = NotchController.sharingType(hiddenFromCapture: hidden)
                self?.window.sharingType = type
                self?.gooWindow?.sharingType = type
            }
            .store(in: &cancellables)
        // Le barillet suit l'onglet actif, quel que soit celui qui le change (barre d'onglets du panneau, raccourci).
        // `@Published` publie avant d'écrire : on relit au tour suivant.
        Publishers.Merge(model.$selectedTab.map { _ in () }, registry.$enabled.map { _ in () })
            .receive(on: DispatchQueue.main)
            .sink { [weak self] in self?.syncTurn() }
            .store(in: &cancellables)
        prefs.$allowsDetach
            .removeDuplicates()
            .receive(on: DispatchQueue.main)
            .sink { [weak self] allowed in if !allowed { self?.reset() } }
            .store(in: &cancellables)
    }

    /// Même comportement que la notch : tous les Spaces, au-dessus des apps et du plein écran, jamais activante.
    static func configure(_ panel: NSPanel) {
        panel.isOpaque = false
        panel.backgroundColor = .clear
        panel.hasShadow = false
        // Avant `level` : ce setter remet le niveau à `.floating` (voir `NotchController`).
        panel.isFloatingPanel = true
        panel.level = NotchController.windowLevel
        panel.collectionBehavior = [.canJoinAllSpaces, .stationary, .fullScreenAuxiliary, .ignoresCycle]
        panel.becomesKeyOnlyIfNeeded = true
        panel.hidesOnDeactivate = false
        panel.isMovable = false
        panel.isReleasedWhenClosed = false
        panel.animationBehavior = .none
    }

    /// Contenu de la fenêtre ; `actions` sont celles du panneau de la bulle (menu « … » compris).
    func start(actions: NotchActions) {
        var actions = actions
        actions.detach = nil
        actions.reattach = { [weak self] in self?.reattach() }
        let input = BubbleInput(
            open: { [weak self] in self?.open() },
            rotate: { [weak self] in self?.rotate(by: $0) },
            reattach: { [weak self] in self?.reattach() },
            moveBegan: { [weak self] in self?.moveBegan() },
            moved: { [weak self] in self?.moved() },
            moveEnded: { [weak self] in self?.moveEnded() },
            panelSized: { [weak self] in self?.panelSized($0) }
        )
        let root = BubbleRootView(model: model, bubble: bubble, store: store, registry: registry, prefs: prefs,
                                  actions: actions, input: input)
        let hosting = BubbleHostingView(rootView: root)
        hosting.sizingOptions = []
        hosting.frame = NSRect(origin: .zero, size: Self.bubbleWindowSize)
        hosting.autoresizingMask = [.width, .height]
        hosting.onScroll = { [weak self] event in self?.scrollWheel(event) ?? false }
        hosting.contextMenu = { [weak self] in self?.contextMenu() }
        window.contentView = hosting
        syncTurn()
    }

    var debugInfo: [String: Any] {
        var info: [String: Any] = ["phase": model.bubble.rawValue, "visible": window.isVisible]
        if model.bubble.isDetached {
            info["center"] = [center.x, center.y]
            info["frame"] = [window.frame.minX, window.frame.minY, window.frame.width, window.frame.height]
        }
        return info
    }

    /// La souris est prise par la bulle (déplacement, décollage) : la notch ne réagit pas à son passage.
    var isInteracting: Bool { moveOffset != nil || model.bubble == .detaching }

    // MARK: - Lancement, réglages, écrans

    /// La bulle reprend sa place au lancement, sauf « Revenir à la notch au redémarrage ».
    func restore() {
        guard prefs.bubbleDetached else { return }
        guard prefs.allowsDetach, !prefs.bubbleReturnsOnRelaunch, let place = restoredCenter() else {
            prefs.bubbleDetached = false
            return
        }
        apply(.grab)
        apply(.release(detached: true))
        center = place
        showBubble()
    }

    /// Dernier écran utilisé s'il est branché, sinon celui de la notch ; sa position rangée, sinon sous la notch.
    private func restoredCenter() -> CGPoint? {
        let screens = NSScreen.screens
        let notch = notchRect()
        let notchScreen = screens.firstIndex { NotchScreenPicker.contains($0.frame, CGPoint(x: notch.midX, y: notch.maxY)) }
        return BubblePlacement.restore(screens: screens.map(ScreenCandidate.init), notchScreen: notchScreen ?? 0,
                                       notch: notch, lastScreen: prefs.bubbleScreen,
                                       saved: prefs.bubblePositions)?.center
    }

    /// Écrans branchés ou débranchés : la bulle reste dans un écran visible ; si le sien a disparu, elle reprend la
    /// place rangée sur l'écran de la notch.
    func screensChanged() {
        guard model.bubble == .bubble || model.bubble == .bubblePanel else { return }
        if model.bubble == .bubblePanel { close() }
        let frames = NSScreen.screens.map(\.frame)
        if !frames.contains(where: { NotchScreenPicker.contains($0, center) }), let place = restoredCenter() {
            center = place
        } else {
            center = BubbleGeometry.clamp(center, visibleFrames: NSScreen.screens.map(\.visibleFrame))
        }
        finishShrink()
        fitWindowToBubble()
    }

    /// Notch masquée par l'utilisateur ou par le plein écran : la bulle aussi.
    func setSuppressed(_ suppressed: Bool) {
        guard suppressed != isSuppressed else { return }
        isSuppressed = suppressed
        if suppressed {
            if model.bubble == .bubblePanel { close() }
            if model.bubble == .detaching { cancelPull() }
            window.orderOut(nil)
        } else if model.bubble == .bubble || model.bubble == .bubblePanel {
            window.orderFrontRegardless()
        }
    }

    /// Après un changement de Space, comme la notch.
    func orderFront() {
        if model.bubble.isDetached, !isSuppressed, window.isVisible { window.orderFrontRegardless() }
    }

    /// Retour immédiat dans la notch, sans animation (réglage coupé).
    func reset() {
        guard model.bubble != .attached else { return }
        let wasOpen = model.bubble == .bubblePanel
        closeWork?.cancel()
        closeWork = nil
        cancelShrink()
        if moveOffset != nil { NSCursor.pop() }
        moveOffset = nil
        pull = nil
        if window.isKeyWindow { NotchKeyboard.release(force: true) }
        window.orderOut(nil)
        endGoo(after: 0)
        apply(.reset)
        if wasOpen { registry.setPanelOpen(false) }
        didAttach()
    }

    // MARK: - États

    private func apply(_ event: BubblePhase.Event) {
        let next = model.bubble.next(event)
        guard next != model.bubble else { return }
        model.bubble = next
        // Rangé seulement aux états stables : une animation coupée par un arrêt de l'app retombe sur l'un d'eux.
        let detached = next == .bubble || next == .bubblePanel
        if next == .attached || detached, prefs.bubbleDetached != detached { prefs.bubbleDetached = detached }
    }

    private func haptic(_ pattern: NSHapticFeedbackManager.FeedbackPattern) {
        guard prefs.hapticFeedback else { return }
        NSHapticFeedbackManager.defaultPerformer.perform(pattern, performanceTime: .now)
    }

    // MARK: - Décollage

    /// Appui maintenu sur la poignée : la goutte suit la souris (`pullMoved`) jusqu'au relâchement (`pullEnded`).
    func beginPull(panel: CGRect) {
        guard model.bubble == .attached, prefs.allowsDetach else { return }
        let handle = mouseLocation()
        let notch = notchRect()
        pull = (panel, notch, handle)
        apply(.grab)
        haptic(.alignment)
        if model.reduceMotion {
            center = handle
            bubble.ghost = true
            showBubble()
            return
        }
        let reach = BubbleGeometry.detachDistance + BubbleGeometry.radius + 40
        showGoo(covering: panel.union(notch).union(CGRect(x: handle.x - reach, y: handle.y - reach,
                                                         width: 2 * reach, height: 2 * reach))) { local in
            GooState(panel: local.body(panel), notch: local.body(notch), handle: local.point(handle),
                     drop: local.point(handle))
        }
        model.gooActive = true
    }

    /// Souris glissée après l'appui : la goutte s'étire ; au seuil, elle se décolle et devient la bulle, que le même
    /// glisser continue de déplacer.
    func pullMoved() {
        let mouse = mouseLocation()
        switch model.bubble {
        case .detaching:
            guard let pull else { return }
            if model.reduceMotion {
                center = mouse
                moveWindow()
            } else {
                bubble.goo?.drop = GooCoordinates(gooFrame).point(mouse)
            }
            if hypot(mouse.x - pull.handle.x, mouse.y - pull.handle.y) >= BubbleGeometry.detachDistance {
                detach(at: mouse, dragging: true)
            }
        case .bubble:
            moved()
        default:
            break
        }
    }

    func pullEnded() {
        switch model.bubble {
        case .detaching: cancelPull()
        case .bubble: moveEnded()
        default: break
        }
        pull = nil
    }

    /// « Détacher la notch » (menu, VoiceOver) : la goutte se décolle seule et la bulle va à sa place rangée.
    /// `panel` : le panneau déplié, ou nil depuis la notch repliée.
    func detachAutomatically(panel: CGRect?) {
        guard model.bubble == .attached, prefs.allowsDetach else { return }
        let notch = notchRect()
        let body = panel ?? notch
        let handle = CGPoint(x: body.maxX - 20, y: body.minY + 6)
        let target = restoredCenter() ?? BubblePlacement.defaultCenter(notch: notch)
        pull = (body, notch, handle)
        apply(.grab)
        if model.reduceMotion {
            detach(at: target, dragging: false)
            return
        }
        let dx = target.x - handle.x, dy = target.y - handle.y
        let length = max(hypot(dx, dy), 1)
        let direction = length > 1 ? CGPoint(x: dx / length, y: dy / length) : CGPoint(x: 0, y: -1)
        let end = CGPoint(x: handle.x + direction.x * BubbleGeometry.detachDistance,
                          y: handle.y + direction.y * BubbleGeometry.detachDistance)
        let reach = BubbleGeometry.detachDistance + BubbleGeometry.radius + 40
        showGoo(covering: body.union(notch).union(CGRect(x: handle.x - reach, y: handle.y - reach,
                                                        width: 2 * reach, height: 2 * reach))) { local in
            GooState(panel: local.body(body), notch: local.body(notch), handle: local.point(handle),
                     drop: local.point(handle), mode: .autoPull(start: Date(), to: local.point(end)))
        }
        if panel != nil { model.gooActive = true }
        DispatchQueue.main.asyncAfter(deadline: .now() + Goo.autoPullDuration) { [weak self] in
            guard let self, self.model.bubble == .detaching else { return }
            self.detach(at: end, dragging: false)
            self.glide(to: target)
        }
    }

    /// Au seuil : la goutte devient la bulle (même taille, puis rebond), le col se résorbe, la notch se replie.
    private func detach(at point: CGPoint, dragging: Bool) {
        apply(.release(detached: true))
        center = BubbleGeometry.clamp(point, visibleFrames: NSScreen.screens.map(\.visibleFrame))
        if dragging {
            moveOffset = CGPoint(x: point.x - center.x, y: point.y - center.y)
            NSCursor.closedHand.push()
        }
        pull = nil
        collapseNotch()
        haptic(.levelChange)
        bubble.ghost = false
        if model.reduceMotion {
            showBubble()
            return
        }
        bubble.goo?.drop = GooCoordinates(gooFrame).point(point)
        bubble.goo?.mode = .snap(start: Date())
        bubble.scale = 0.72
        showBubble()
        withAnimation(.spring(response: 0.42, dampingFraction: 0.48)) { bubble.scale = 1 }
        endGoo(after: Goo.snapDuration)
    }

    /// Relâché avant le seuil : la goutte rentre, le panneau revient.
    private func cancelPull() {
        pull = nil
        apply(.release(detached: false))
        if model.reduceMotion {
            bubble.ghost = false
            window.orderOut(nil)
            return
        }
        guard var goo = bubble.goo else { return endGoo(after: 0) }
        goo.mode = .cancel(start: Date(), from: goo.drop, progress: goo.progress)
        bubble.goo = goo
        endGoo(after: Goo.cancelDuration)
    }

    // MARK: - Goutte

    /// Montre la goutte sous la notch, sur `rect` (coordonnées écran) prolongé jusqu'au-dessus de l'écran.
    private func showGoo(covering rect: CGRect, state: (GooCoordinates) -> GooState) {
        gooGeneration += 1
        let top = (NSScreen.screens.first { $0.frame.intersects(rect) }?.frame.maxY ?? rect.maxY) + Self.gooOverflow
        let frame = CGRect(x: rect.minX, y: rect.minY, width: rect.width, height: max(top, rect.maxY) - rect.minY)
            .integral
        let panel = gooWindow ?? makeGooWindow()
        // Couleur relue à chaque goutte : le fond des réglages a pu changer.
        (panel.contentView as? NSHostingView<GooView>)?.rootView = GooView(bubble: bubble, color: prefs.panelColor)
        panel.setFrame(frame, display: false)
        gooFrame = frame
        bubble.goo = state(GooCoordinates(frame))
        if let notch = notchWindow(), notch.isVisible {
            panel.order(.below, relativeTo: notch.windowNumber)
        } else {
            panel.orderFrontRegardless()
        }
    }

    private func makeGooWindow() -> GooPanel {
        let panel = GooPanel(contentRect: .zero, styleMask: [.borderless, .nonactivatingPanel], backing: .buffered,
                             defer: true)
        Self.configure(panel)
        panel.ignoresMouseEvents = true
        panel.sharingType = window.sharingType
        let hosting = NSHostingView(rootView: GooView(bubble: bubble, color: prefs.panelColor))
        hosting.sizingOptions = []
        hosting.autoresizingMask = [.width, .height]
        panel.contentView = hosting
        gooWindow = panel
        return panel
    }

    /// La notch réapparaît (fondu de 0,15 s par-dessus la goutte), puis la goutte s'efface : plus rien n'est dessiné.
    private func endGoo(after delay: TimeInterval) {
        let generation = gooGeneration
        DispatchQueue.main.asyncAfter(deadline: .now() + delay) { [weak self] in
            guard let self, self.gooGeneration == generation else { return }
            self.model.gooActive = false
            DispatchQueue.main.asyncAfter(deadline: .now() + 0.16) { [weak self] in
                guard let self, self.gooGeneration == generation else { return }
                self.gooWindow?.orderOut(nil)
                self.bubble.goo = nil
            }
        }
    }

    // MARK: - Bulle

    private func showBubble() {
        finishShrink()
        fitWindowToBubble()
        if !isSuppressed { window.orderFrontRegardless() }
    }

    /// Fenêtre ajustée à la bulle, centrée sur `center`.
    private func fitWindowToBubble() {
        let size = Self.bubbleWindowSize
        window.setFrame(NSRect(x: center.x - size.width / 2, y: center.y - size.height / 2, width: size.width,
                               height: size.height), display: true)
        bubble.layout(center: CGPoint(x: size.width / 2, y: size.height / 2), window: size)
    }

    private func moveWindow() {
        let size = Self.bubbleWindowSize
        window.setFrameOrigin(CGPoint(x: center.x - size.width / 2, y: center.y - size.height / 2))
    }

    /// Glisse la bulle vers `target` (fin du détachement par le menu) et range la position.
    private func glide(to target: CGPoint) {
        center = target
        let size = Self.bubbleWindowSize
        NSAnimationContext.runAnimationGroup { context in
            context.duration = 0.35
            context.timingFunction = CAMediaTimingFunction(name: .easeInEaseOut)
            window.animator().setFrame(NSRect(x: target.x - size.width / 2, y: target.y - size.height / 2,
                                              width: size.width, height: size.height), display: true)
        }
        savePosition()
    }

    func moveBegan() {
        guard model.bubble == .bubble else { return }
        finishShrink()
        let mouse = mouseLocation()
        moveOffset = CGPoint(x: mouse.x - center.x, y: mouse.y - center.y)
        NSCursor.closedHand.push()
    }

    /// La bulle suit la souris, dans les écrans visibles ; près de la notch, elle est aimantée.
    func moved() {
        guard let moveOffset, model.bubble == .bubble else { return }
        let mouse = mouseLocation()
        let wanted = BubbleGeometry.clamp(CGPoint(x: mouse.x - moveOffset.x, y: mouse.y - moveOffset.y),
                                          visibleFrames: NSScreen.screens.map(\.visibleFrame))
        let notch = notchRect()
        let near = BubbleGeometry.isNearNotch(center: wanted, notch: notch)
        if near != bubble.nearNotch {
            bubble.nearNotch = near
            if near { haptic(.alignment) }
        }
        center = BubbleGeometry.magnetized(center: wanted, notch: notch)
        moveWindow()
    }

    /// Lâchée près de la notch : elle s'y rattache ; ailleurs, sa position est rangée pour cet écran.
    func moveEnded() {
        guard moveOffset != nil else { return }
        moveOffset = nil
        NSCursor.pop()
        if bubble.nearNotch {
            reattach()
        } else {
            savePosition()
        }
    }

    private func savePosition() {
        guard let saved = BubblePlacement.save(center: center, screens: NSScreen.screens.map(ScreenCandidate.init))
        else { return }
        prefs.bubblePositions[saved.label] = saved.offset
        if prefs.bubbleScreen != saved.label { prefs.bubbleScreen = saved.label }
    }

    // MARK: - Barillet

    func rotate(by steps: Int) {
        let tabs = registry.enabled
        guard steps != 0, !tabs.isEmpty, model.bubble == .bubble else { return }
        var revolver = Revolver(count: tabs.count, turn: bubble.turn)
        revolver.rotate(by: steps)
        bubble.turn = revolver.turn
        model.selectedTab = tabs[revolver.activeIndex].id
        haptic(.generic)
    }

    /// L'onglet actif est toujours en haut du barillet (par le plus court chemin).
    private func syncTurn() {
        let ids = registry.enabled.map { $0.id }
        guard let index = ids.firstIndex(of: model.selectedTab) else { return }
        let steps = Revolver(count: ids.count, turn: bubble.turn).steps(toTop: index)
        if steps != 0 { bubble.turn += steps }
    }

    /// Molette : un cran par ligne, ou tous les 28 pt de trackpad ; l'inertie est ignorée.
    private func scrollWheel(_ event: NSEvent) -> Bool {
        guard model.bubble == .bubble else { return false }
        guard event.momentumPhase.isEmpty else { return true }
        if event.phase == .began { scroll.reset() }
        rotate(by: scroll.add(deltaX: event.scrollingDeltaX, deltaY: event.scrollingDeltaY,
                              precise: event.hasPreciseScrollingDeltas))
        return true
    }

    // MARK: - Panneau de la bulle

    /// La bulle s'ouvre en panneau sur l'onglet du haut (ou `tab`, clic sur un intercalaire).
    func open(tab: String? = nil, keyboard: Bool = false) {
        if let tab, registry.isEnabled(tab) { model.selectedTab = tab }
        guard model.bubble == .bubble else { return }
        if !registry.enabled.contains(where: { $0.id == model.selectedTab }), let first = registry.enabled.first {
            model.selectedTab = first.id
        }
        cancelShrink()
        openedByKeyboard = keyboard
        let margin = BubbleGeometry.panelMargin
        let size = CGSize(width: prefs.expandedWidth(compact: false) + 2 * margin,
                          height: (panelHeight ?? ExpandedPanel.maxPanelHeight) + 2 * margin)
        let visible = (NSScreen.screens.first { NotchScreenPicker.contains($0.frame, center) } ?? NSScreen.main)?
            .visibleFrame ?? CGRect(origin: .zero, size: size)
        let frame = BubbleGeometry.panelFrame(size: size, bubble: center, visible: visible)
        bubble.layout(center: CGPoint(x: center.x - frame.minX, y: frame.maxY - center.y), window: frame.size)
        window.setFrame(frame, display: true)
        apply(.open)
        registry.setPanelOpen(true)
        haptic(.alignment)
        window.orderFrontRegardless()
        if keyboard { NotchKeyboard.take() }
    }

    /// Le panneau se referme en bulle ; la fenêtre reprend la taille de la bulle une fois la transition finie.
    func close() {
        guard model.bubble == .bubblePanel else { return }
        closeWork?.cancel()
        closeWork = nil
        if window.isKeyWindow { NotchKeyboard.release(force: true) }
        openedByKeyboard = false
        model.isEditingTabs = false
        if prefs.lastTab != model.selectedTab { prefs.lastTab = model.selectedTab }
        apply(.close)
        registry.setPanelOpen(false)
        let work = DispatchWorkItem { [weak self] in self?.finishShrink() }
        shrinkWork = work
        DispatchQueue.main.asyncAfter(deadline: .now() + Self.shrinkDelay, execute: work)
    }

    func togglePanel() {
        if model.bubble == .bubblePanel { close() } else { open(keyboard: true) }
    }

    private func cancelShrink() {
        shrinkWork?.cancel()
        shrinkWork = nil
    }

    /// Réduction différée de la fenêtre faite tout de suite (avant de déplacer ou de réafficher la bulle).
    private func finishShrink() {
        guard shrinkWork != nil else { return }
        cancelShrink()
        guard model.bubble == .bubble || model.bubble == .reattaching else { return }
        fitWindowToBubble()
        if isSuppressed { window.orderOut(nil) }
    }

    /// Hauteur réelle du panneau : la fenêtre s'y ajuste, son haut ne bouge pas.
    private func panelSized(_ size: CGSize) {
        guard model.bubble == .bubblePanel, size.height > 0 else { return }
        panelHeight = size.height
        var frame = window.frame
        let height = size.height + 2 * BubbleGeometry.panelMargin
        guard abs(frame.height - height) > 0.5 else { return }
        frame.origin.y += frame.height - height
        frame.size.height = height
        bubble.layout(center: CGPoint(x: center.x - frame.minX, y: frame.maxY - center.y), window: frame.size)
        window.setFrame(frame, display: true)
    }

    private var panelRect: CGRect {
        window.frame.insetBy(dx: BubbleGeometry.panelMargin, dy: BubbleGeometry.panelMargin)
    }

    /// Souris hors du panneau ouvert : il se referme après le délai des réglages, comme celui de la notch (sauf « Fermer
    /// au clic à l'extérieur », ouverture au clavier, mode édition, menu ouvert).
    func mouseMoved(_ point: CGPoint) {
        guard model.bubble == .bubblePanel else { return }
        let stays = prefs.closeOnClickOutside || openedByKeyboard || model.isEditingTabs || isMenuTracking()
        if stays || NotchScreenPicker.contains(panelRect.insetBy(dx: -4, dy: -4), point) {
            closeWork?.cancel()
            closeWork = nil
            return
        }
        guard closeWork == nil else { return }
        let work = DispatchWorkItem { [weak self] in
            guard let self else { return }
            self.closeWork = nil
            if !self.isMenuTracking(), !self.model.isEditingTabs,
               !NotchScreenPicker.contains(self.panelRect.insetBy(dx: -4, dy: -4), self.mouseLocation()) {
                self.close()
            }
        }
        closeWork = work
        DispatchQueue.main.asyncAfter(deadline: .now() + prefs.closeDelay, execute: work)
    }

    /// Clic hors du panneau ouvert : il se referme (en mode édition, on sort seulement du mode).
    func mouseDown(at point: CGPoint) {
        guard model.bubble == .bubblePanel, !isMenuTracking(), !panelRect.contains(point) else { return }
        if model.isEditingTabs { model.isEditingTabs = false } else { close() }
    }

    /// Panneau de la bulle qui a le clavier : Échap le referme (ou sort du mode édition) ; ouvert au raccourci, ← → et
    /// ⌘1…9 changent d'onglet.
    func handleKey(_ event: NSEvent) -> Bool {
        guard model.bubble == .bubblePanel, window.isKeyWindow,
              let command = NotchKeyCommand.parse(keyCode: event.keyCode, modifiers: event.modifierFlags,
                                                  editingText: window.firstResponder is NSText) else { return false }
        if command == .close {
            if model.isEditingTabs { model.isEditingTabs = false } else { close() }
            return true
        }
        guard openedByKeyboard else { return false }
        let tabs = registry.enabled.map { $0.id }
        guard let index = command.target(current: tabs.firstIndex(of: model.selectedTab) ?? 0, count: tabs.count)
        else { return false }
        model.selectedTab = tabs[index]
        return true
    }

    // MARK: - Rattachement

    /// Retour dans la notch : la bulle glisse sous la notch si elle est loin, puis la goutte y remonte.
    func reattach() {
        guard model.bubble == .bubble || model.bubble == .bubblePanel else { return }
        let wasOpen = model.bubble == .bubblePanel
        closeWork?.cancel()
        closeWork = nil
        if window.isKeyWindow { NotchKeyboard.release(force: true) }
        model.isEditingTabs = false
        apply(.reattach)
        if wasOpen { registry.setPanelOpen(false) }
        cancelShrink()
        bubble.nearNotch = false
        fitWindowToBubble()
        if model.reduceMotion {
            NSAnimationContext.runAnimationGroup({ context in
                context.duration = 0.2
                window.animator().alphaValue = 0
            }, completionHandler: { [weak self] in self?.finishAttach() })
            return
        }
        let dock = BubbleGeometry.dockPoint(notch: notchRect())
        guard hypot(center.x - dock.x, center.y - dock.y) > 4 else { return merge() }
        center = dock
        let size = Self.bubbleWindowSize
        NSAnimationContext.runAnimationGroup({ context in
            context.duration = 0.28
            context.timingFunction = CAMediaTimingFunction(name: .easeIn)
            window.animator().setFrame(NSRect(x: dock.x - size.width / 2, y: dock.y - size.height / 2,
                                              width: size.width, height: size.height), display: true)
        }, completionHandler: { [weak self] in self?.merge() })
    }

    /// La goutte remonte dans la notch (effet inverse du décollage).
    private func merge() {
        guard model.bubble == .reattaching else { return }
        let notch = notchRect()
        let reach = BubbleGeometry.radius + 30
        showGoo(covering: notch.insetBy(dx: -40, dy: 0).union(CGRect(x: center.x - reach, y: center.y - reach,
                                                                     width: 2 * reach, height: 2 * reach))) { local in
            GooState(panel: local.body(notch), notch: local.body(notch), handle: local.point(center),
                     drop: local.point(center), mode: .merge(start: Date(), from: local.point(center)))
        }
        NSAnimationContext.runAnimationGroup { context in
            context.duration = 0.12
            window.animator().alphaValue = 0
        }
        DispatchQueue.main.asyncAfter(deadline: .now() + Goo.mergeDuration) { [weak self] in
            self?.finishAttach()
            self?.haptic(.levelChange)
        }
        endGoo(after: Goo.mergeDuration)
    }

    private func finishAttach() {
        guard model.bubble == .reattaching else { return }
        window.orderOut(nil)
        window.alphaValue = 1
        apply(.merged)
        didAttach()
    }

    // MARK: - Menu

    /// Clic droit sur la bulle.
    private func contextMenu() -> NSMenu? {
        guard model.bubble == .bubble else { return nil }
        let menu = NSMenu()
        menu.addItem(ClosureMenuItem(L("Ouvrir", table: "Bubble")) { [weak self] in self?.open() })
        menu.addItem(ClosureMenuItem(L("Rattacher à la notch", table: "Bubble")) { [weak self] in self?.reattach() })
        menu.addItem(.separator())
        menu.addItem(ClosureMenuItem(L("Réglages…")) { [weak self] in self?.openSettings() })
        return menu
    }
}

/// Coordonnées de la fenêtre de la goutte (y vers le bas) depuis l'écran (y vers le haut).
struct GooCoordinates {
    let frame: CGRect

    init(_ frame: CGRect) { self.frame = frame }

    func point(_ point: CGPoint) -> CGPoint { CGPoint(x: point.x - frame.minX, y: frame.maxY - point.y) }

    /// Forme collée en haut de l'écran : prolongée jusqu'au-dessus de la fenêtre, le flou n'en ronge pas le haut.
    func body(_ rect: CGRect) -> CGRect {
        let top = frame.maxY - rect.maxY
        return CGRect(x: rect.minX - frame.minX, y: -20, width: rect.width, height: top + rect.height + 20)
    }
}
