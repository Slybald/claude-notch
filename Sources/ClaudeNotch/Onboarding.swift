import AppKit
import SwiftUI

/// État des hooks Claude Code, partagé par le menu « … », Réglages › Claude et la fenêtre de bienvenue.
final class HookSetup: ObservableObject {
    static let shared = HookSetup()

    /// Fenêtre ouverte au lancement.
    enum LaunchWindow: Equatable {
        case none
        /// Hooks d'une version précédente que la mise à jour silencieuse n'a pas pu remplacer.
        case update
        /// Premier lancement : la notch présentée, avec la section Claude Code ou non.
        case welcome(claude: Bool)
    }

    /// Relu au lancement (onglet Claude activé), à l'ouverture du panneau et après chaque action (jamais dans `init`).
    @Published private(set) var status: HookInstaller.Status = .notInstalled
    let installer: HookInstaller
    private var onboarding: OnboardingWindowController?

    init(installer: HookInstaller = .standard) {
        self.installer = installer
    }

    func refresh() {
        let current = installer.status()
        if current != status { status = current }
    }

    var isInApplications: Bool { AppIdentity.isInApplicationsFolder(Bundle.main.bundlePath) }

    /// Au lancement. Onglet Claude activé : des hooks déjà posés par une version précédente (entrées ou script) sont
    /// mis à jour sans rien demander, l'accord a été donné à l'installation (sauvegarde horodatée de settings.json,
    /// comme toujours). Onglet désactivé : `~/.claude` n'est même pas lu. Puis la fenêtre éventuelle.
    func showOnboardingIfNeeded(claudeEnabled: Bool, prefs: Preferences) {
        if claudeEnabled {
            refresh()
            silentUpdate()
        }
        let window = Self.launchWindow(claudeEnabled: claudeEnabled, status: status, welcomeShown: prefs.welcomeShown)
        // La bienvenue ne vient qu'une fois ; une mise à jour ratée la repousse au lancement suivant.
        if window != .update { prefs.welcomeShown = true }
        switch window {
        case .none: break
        case .update: showOnboarding()
        case .welcome(let claude): present(welcome: true, hooks: claude)
        }
    }

    /// Mise à jour silencieuse ratée : on la propose. Sinon, la bienvenue au premier lancement, sauf après une mise à
    /// jour depuis une version qui avait posé les hooks (ce n'est pas un premier lancement).
    static func launchWindow(claudeEnabled: Bool, status: HookInstaller.Status, welcomeShown: Bool) -> LaunchWindow {
        if claudeEnabled, status == .outdated || status == .scriptOutdated { return .update }
        if welcomeShown || (claudeEnabled && status == .installed) { return .none }
        return .welcome(claude: claudeEnabled)
    }

    /// Ce qu'il faut faire des hooks pour que les réponses marchent.
    enum Repair { case none, update, install }

    static func repairNeeded(for status: HookInstaller.Status) -> Repair {
        switch status {
        case .installed: return .none
        case .outdated, .scriptOutdated: return .update
        case .notInstalled, .unreadable: return .install
        }
    }

    /// `.scriptOutdated` : seul le script est réécrit. `.outdated` : entrées et script.
    func silentUpdate() {
        do {
            switch status {
            case .scriptOutdated: try installer.updateScript()
            case .outdated: try installer.install()
            default: return
            }
        } catch {
            NSLog("ClaudeNotch : mise à jour des hooks impossible (%@).", error.localizedDescription)
        }
        refresh()
    }

    // MARK: - Fenêtre

    /// Installer ou mettre à jour les hooks (Réglages › Claude, menu « … », mise à jour ratée).
    func showOnboarding() {
        present(welcome: false, hooks: true)
    }

    /// `hooks` : section des hooks Claude Code (sinon, seulement où activer l'onglet Claude).
    private func present(welcome: Bool, hooks: Bool) {
        DispatchQueue.main.async { [self] in
            if hooks { refresh() }
            if let onboarding {
                onboarding.showWindow(nil)
                Self.activateApp()
                return
            }
            var error: String?
            if hooks, case .unreadable(let message) = status { error = message }
            let mode: OnboardingView.Mode = welcome ? .welcome
                : status == .outdated || status == .scriptOutdated ? .update : .install
            let view = OnboardingView(
                mode: mode,
                showsHooks: hooks,
                inApplications: isInApplications,
                launchAtLogin: status == .notInstalled || Preferences.shared.launchAtLogin,
                error: error,
                onInstall: { [weak self] launchAtLogin in self?.installFromWindow(launchAtLogin: launchAtLogin) },
                onClose: { [weak self] launchAtLogin in
                    // La bienvenue applique la case quel que soit le bouton ; ailleurs, seule l'installation compte.
                    if welcome { self?.applyLaunchAtLogin(launchAtLogin) }
                    self?.onboarding?.close()
                }
            )
            let controller = OnboardingWindowController(rootView: view)
            controller.onClose = { [weak self] in self?.onboarding = nil }
            onboarding = controller
            controller.window?.center()
            controller.showWindow(nil)
            Self.activateApp()
        }
    }

    /// nil si tout s'est bien passé, sinon le message d'erreur. Fenêtre refermée seule peu après un succès.
    private func installFromWindow(launchAtLogin: Bool) -> String? {
        defer { refresh() }
        do {
            try installer.install()
        } catch {
            return error.localizedDescription
        }
        applyLaunchAtLogin(launchAtLogin)
        let controller = onboarding
        DispatchQueue.main.asyncAfter(deadline: .now() + 4) { controller?.close() }
        return nil
    }

    /// Hors Applications, le LaunchAgent pointerait vers le DMG ou une copie temporaire.
    private func applyLaunchAtLogin(_ isOn: Bool) {
        if isInApplications, Preferences.shared.launchAtLogin != isOn { Preferences.shared.launchAtLogin = isOn }
    }

    // MARK: - Menu « … »

    /// Hooks anciens : réinstallés directement (l'accord a déjà été donné à l'installation).
    func update() {
        DispatchQueue.main.async { [self] in
            do {
                try installer.install()
            } catch {
                Self.activateApp()
                Self.showError(error, title: L("Mise à jour des hooks impossible"))
            }
            refresh()
        }
    }

    /// Confirmation, puis retrait des hooks, du script de hook et du LaunchAgent, puis Quitter. Sans hooks, le texte
    /// ne parle pas de Claude Code.
    func confirmAndUninstall() {
        DispatchQueue.main.async { [self] in
            Self.activateApp()
            refresh()
            let hooks = status != .notInstalled
            let alert = NSAlert()
            alert.alertStyle = .warning
            alert.messageText = L("Désinstaller Claude Notch ?")
            alert.informativeText = hooks
                ? L("Les hooks de Claude Notch seront retirés de ~/.claude/settings.json (sauvegarde "
                    + "horodatée à côté, tes autres hooks restent en place), ainsi que ~/.claude/hooks/claude-notch-hook.sh "
                    + "et le lancement à l'ouverture de session. L'app se fermera ensuite.")
                : L("Le lancement à l'ouverture de session sera retiré. L'app se fermera ensuite.")
            alert.addButton(withTitle: L("Désinstaller"))
            alert.addButton(withTitle: L("Annuler"))
            alert.buttons.first?.hasDestructiveAction = true
            guard alert.runModal() == .alertFirstButtonReturn else { return }

            do {
                try installer.uninstall()
            } catch {
                refresh()
                Self.showError(error, title: L("Désinstallation interrompue"))
                return
            }
            LaunchAgent.setEnabled(false)
            // Règle « économie d'énergie sans mot de passe » (Réglages rapides) : retirée aussi ; sans règle, rien
            // n'est demandé.
            LowPowerAuthorization.remove { result in
                if case .failure = result, LowPowerAuthorization.isInstalled {
                    let alert = NSAlert()
                    alert.alertStyle = .warning
                    alert.messageText = L("La règle d'économie d'énergie reste en place")
                    alert.informativeText = L("Pour la retirer : sudo rm /etc/sudoers.d/claude-notch-lowpower")
                    alert.runModal()
                }
                Self.finishUninstall(hooks: hooks)
            }
        }
    }

    private static func finishUninstall(hooks: Bool) {
        let done = NSAlert()
        done.messageText = L("Claude Notch est désinstallé")
        done.informativeText = hooks
            ? L("Il ne reste qu'à jeter Claude Notch à la Corbeille, depuis le dossier Applications. "
                + "Les sessions Claude Code déjà ouvertes l'oublieront à leur redémarrage.")
            : L("Il ne reste qu'à jeter Claude Notch à la Corbeille, depuis le dossier Applications.")
        done.addButton(withTitle: L("Afficher dans le Finder"))
        done.addButton(withTitle: L("Quitter"))
        if done.runModal() == .alertFirstButtonReturn {
            NSWorkspace.shared.activateFileViewerSelecting([Bundle.main.bundleURL])
        }
        NSApp.terminate(nil)
    }

    // MARK: - Outils

    /// L'app reste `.accessory` (pas d'icône dans le Dock) : on l'active pour montrer une fenêtre ou une alerte.
    static func activateApp() {
        if #available(macOS 14, *) {
            NSApp.activate()
        } else {
            NSApp.activate(ignoringOtherApps: true)
        }
    }

    private static func showError(_ error: Error, title: String) {
        let alert = NSAlert()
        alert.alertStyle = .warning
        alert.messageText = title
        alert.informativeText = error.localizedDescription
        alert.runModal()
    }
}

/// Fenêtre classique (titre transparent, fond noir) qui héberge la vue SwiftUI.
/// Le contrôleur SwiftUI ajuste la taille de la fenêtre quand un message apparaît.
final class OnboardingWindowController: NSWindowController, NSWindowDelegate {
    var onClose: (() -> Void)?

    init<Content: View>(rootView: Content) {
        let hosting = NSHostingController(rootView: rootView)
        hosting.sizingOptions = [.preferredContentSize]
        let window = NSWindow(contentViewController: hosting)
        window.styleMask = [.titled, .closable, .fullSizeContentView]
        window.title = "Claude Notch"
        window.titleVisibility = .hidden
        window.titlebarAppearsTransparent = true
        window.isMovableByWindowBackground = true
        window.appearance = NSAppearance(named: .darkAqua)
        window.backgroundColor = .black
        window.isReleasedWhenClosed = false
        super.init(window: window)
        window.delegate = self
    }

    @available(*, unavailable)
    required init?(coder: NSCoder) { nil }

    func windowWillClose(_ notification: Notification) {
        onClose?()
    }
}

// MARK: - Vue

struct OnboardingView: View {
    /// `welcome` : premier lancement (présentation, hooks proposés seulement si Claude Code est là). `install` et
    /// `update` : hooks seuls, depuis les réglages ou après une mise à jour ratée.
    enum Mode { case welcome, install, update }

    private enum Phase: Equatable {
        case idle
        case done
        case failed(String)
    }

    let mode: Mode
    /// Section des hooks Claude Code ; sans elle, une ligne dit où activer l'onglet Claude.
    let showsHooks: Bool
    let inApplications: Bool
    /// nil si tout s'est bien passé, sinon le message d'erreur.
    let onInstall: (_ launchAtLogin: Bool) -> String?
    /// Reçoit l'état de la case « Lancer à l'ouverture de session ».
    let onClose: (_ launchAtLogin: Bool) -> Void

    @State private var launchAtLogin: Bool
    @State private var phase: Phase

    init(mode: Mode, showsHooks: Bool = true, inApplications: Bool, launchAtLogin: Bool, error: String? = nil,
         onInstall: @escaping (_ launchAtLogin: Bool) -> String?, onClose: @escaping (_ launchAtLogin: Bool) -> Void) {
        self.mode = mode
        self.showsHooks = showsHooks
        self.inApplications = inApplications
        self.onInstall = onInstall
        self.onClose = onClose
        _launchAtLogin = State(initialValue: inApplications && launchAtLogin)
        _phase = State(initialValue: error.map(Phase.failed) ?? .idle)
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 18) {
            header
            if !inApplications { applicationsWarning }
            if mode == .welcome { tour }
            if showsHooks { changes } else { claudeHint }
            loginToggle
            switch phase {
            case .idle: EmptyView()
            case .done: message(success, icon: "checkmark.circle.fill", color: Palette.green)
            case .failed(let text): message(text, icon: "xmark.octagon.fill", color: Palette.red)
            }
            buttons
        }
        // Le haut est sous la barre de titre transparente (zone sûre) : 6 pt suffisent.
        .padding(.horizontal, 26)
        .padding(.top, 6)
        .padding(.bottom, 22)
        .frame(width: 470, alignment: .leading)
        .fixedSize(horizontal: false, vertical: true)
        .background(Color.black.ignoresSafeArea())
        .foregroundColor(Palette.primary)
        .environment(\.colorScheme, .dark)
    }

    private var header: some View {
        VStack(alignment: .leading, spacing: 14) {
            HStack(spacing: 14) {
                ZStack {
                    RoundedRectangle(cornerRadius: 12, style: .continuous)
                        .fill(Palette.accent.opacity(0.16))
                    Image(systemName: "rectangle.topthird.inset.filled")
                        .font(.system(size: 22, weight: .medium))
                        .foregroundColor(Palette.accent)
                }
                .frame(width: 48, height: 48)
                VStack(alignment: .leading, spacing: 3) {
                    Text(mode == .update ? L("Mettre à jour Claude Notch") : L("Bienvenue dans Claude Notch"))
                        .font(.system(size: 17, weight: .semibold))
                    Text(mode == .welcome ? L("Des onglets utiles, dans la notch.")
                         : L("Tes sessions Claude Code, d'un coup d'œil."))
                        .font(.system(size: 12))
                        .foregroundColor(Palette.secondary)
                }
            }
            if mode != .welcome {
                Text(mode == .update
                     ? L("Les hooks installés viennent d'une version précédente de l'app. Mets-les à jour pour que la notch "
                        + "continue de suivre tes sessions.")
                     : L("Survole la notch : chaque session Claude Code (terminal, éditeur ou Claude Desktop) y affiche son "
                        + "état, l'outil en cours, ses tâches et les permissions qui t'attendent. Tout reste sur ton Mac."))
                    .font(.system(size: 12.5))
                    .foregroundColor(.white.opacity(0.85))
                    .fixedSize(horizontal: false, vertical: true)
            }
        }
    }

    /// Bienvenue : comment ouvrir la notch, ses onglets, ses réglages.
    private var tour: some View {
        VStack(alignment: .leading, spacing: 12) {
            InfoRow(icon: "cursorarrow.rays", title: L("Ouvrir la notch"),
                    detail: L("Survole-la. Ouverture au clic et raccourci clavier se règlent dans les réglages."))
            InfoRow(icon: "rectangle.split.3x1", title: L("Onglets"),
                    detail: L("Lecteur et calendrier, réglages rapides, étagère, presse-papiers, minuteur et notes. "
                        + "Choisis-les et range-les dans Réglages › Onglets."))
            InfoRow(icon: "gearshape", title: L("Réglages"),
                    detail: L("Menu « … » du panneau, ou rouvre Claude Notch. Clic droit sur la notch pour la masquer."))
        }
        .padding(14)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(RoundedRectangle(cornerRadius: 14, style: .continuous).fill(Palette.card))
    }

    private var applicationsWarning: some View {
        HStack(alignment: .top, spacing: 10) {
            Image(systemName: "exclamationmark.triangle.fill")
                .font(.system(size: 14))
                .foregroundColor(Palette.amber)
            VStack(alignment: .leading, spacing: 3) {
                Text("Glisse d'abord Claude Notch dans Applications")
                    .font(.system(size: 12.5, weight: .semibold))
                Text(L("L'app tourne depuis l'image disque ou une copie temporaire. Quitte-la, glisse-la dans le dossier "
                       + "Applications, puis rouvre-la depuis là."))
                    .font(.system(size: 11.5))
                    .foregroundColor(Palette.secondary)
                    .fixedSize(horizontal: false, vertical: true)
            }
        }
        .padding(12)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(RoundedRectangle(cornerRadius: 12, style: .continuous).fill(Palette.amber.opacity(0.12)))
    }

    /// Hooks : ce qui sera modifié. Dans la bienvenue, présentés comme l'intégration Claude Code, en option.
    private var changes: some View {
        VStack(alignment: .leading, spacing: 12) {
            Text(mode == .welcome ? L("INTÉGRATION CLAUDE CODE") : L("CE QUI SERA MODIFIÉ"))
                .font(.system(size: 10.5, weight: .semibold))
                .tracking(0.6)
                .foregroundColor(Palette.secondary)
            if mode == .welcome {
                Text(L("Claude Code est installé sur ce Mac. Avec ses hooks, l'onglet Claude suit tes sessions : état, "
                       + "outil en cours, tâches, permissions."))
                    .font(.system(size: 12))
                    .foregroundColor(.white.opacity(0.85))
                    .fixedSize(horizontal: false, vertical: true)
            }
            InfoRow(icon: "doc.text", title: "~/.claude/settings.json", monospaced: true,
                    detail: L("Ajout des hooks de Claude Notch. Tes hooks restent en place ; une sauvegarde horodatée "
                        + "est faite à côté."))
            InfoRow(icon: "terminal", title: "~/.claude/hooks/claude-notch-hook.sh", monospaced: true,
                    detail: L("Petit script qui relaie chaque événement à l'app, en local (127.0.0.1)."))
        }
        .padding(14)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(RoundedRectangle(cornerRadius: 14, style: .continuous).fill(Palette.card))
    }

    /// Bienvenue sans Claude Code : rien n'est proposé, seulement où trouver l'onglet.
    private var claudeHint: some View {
        HStack(alignment: .top, spacing: 10) {
            Text(verbatim: "✻")
                .font(.system(size: 13, weight: .bold))
                .foregroundColor(Palette.accent)
            Text("Tu utilises Claude Code ? Active l'onglet Claude dans Réglages › Onglets.")
                .font(.system(size: 12))
                .foregroundColor(Palette.secondary)
                .fixedSize(horizontal: false, vertical: true)
        }
    }

    private var loginToggle: some View {
        VStack(alignment: .leading, spacing: 3) {
            Toggle("Lancer à l'ouverture de session", isOn: $launchAtLogin)
                .toggleStyle(.checkbox)
                .font(.system(size: 12.5))
                .disabled(!inApplications || phase == .done)
            if !inApplications {
                Text("Disponible une fois l'app dans Applications.")
                    .font(.system(size: 11))
                    .foregroundColor(Palette.secondary)
                    .padding(.leading, 20)
            }
        }
    }

    private var success: String {
        mode == .update
            ? L("Hooks à jour. Les sessions déjà ouvertes apparaîtront à leur prochain message.")
            : L("Hooks installés. Les sessions déjà ouvertes apparaîtront à leur prochain message.")
    }

    private var installTitle: String {
        switch mode {
        case .welcome: return L("Installer les hooks")
        case .install: return L("Installer les hooks Claude Code")
        case .update: return L("Mettre à jour les hooks")
        }
    }

    private func message(_ text: String, icon: String, color: Color) -> some View {
        HStack(alignment: .top, spacing: 8) {
            Image(systemName: icon)
                .foregroundColor(color)
            Text(text)
                .font(.system(size: 12))
                .foregroundColor(.white.opacity(0.9))
                .fixedSize(horizontal: false, vertical: true)
                .textSelection(.enabled)
        }
    }

    private var buttons: some View {
        HStack(spacing: 10) {
            Spacer()
            if phase == .done {
                Button("Fermer") { onClose(launchAtLogin) }
                    .keyboardShortcut(.defaultAction)
            } else if !showsHooks {
                Button("Commencer") { onClose(launchAtLogin) }
                    .keyboardShortcut(.defaultAction)
                    .buttonStyle(.borderedProminent)
                    .tint(Palette.accent)
            } else {
                Button("Plus tard") { onClose(launchAtLogin) }
                    .keyboardShortcut(.cancelAction)
                Button(installTitle) {
                    if let error = onInstall(launchAtLogin) {
                        phase = .failed(error)
                    } else {
                        phase = .done
                    }
                }
                .keyboardShortcut(.defaultAction)
                .buttonStyle(.borderedProminent)
                .tint(Palette.accent)
            }
        }
        .controlSize(.large)
    }
}

/// Ligne icône + titre + détail (présentation des onglets, fichiers modifiés par les hooks).
private struct InfoRow: View {
    let icon: String
    let title: String
    var monospaced = false
    let detail: String

    var body: some View {
        HStack(alignment: .top, spacing: 10) {
            Image(systemName: icon)
                .font(.system(size: 13))
                .foregroundColor(Palette.accent)
                .frame(width: 18)
            VStack(alignment: .leading, spacing: 2) {
                Text(title)
                    .font(.system(size: 12, weight: .medium, design: monospaced ? .monospaced : .default))
                Text(detail)
                    .font(.system(size: 11.5))
                    .foregroundColor(Palette.secondary)
                    .fixedSize(horizontal: false, vertical: true)
            }
        }
    }
}

// MARK: - Menu

/// Entrées du menu « … » du panneau : état des hooks (onglet Claude activé seulement) et désinstallation.
struct HookMenuItems: View {
    @ObservedObject var setup: HookSetup
    let claudeEnabled: Bool

    var body: some View {
        if claudeEnabled {
            switch setup.status {
            case .installed:
                Button("Hooks Claude Code installés ✓") {}
                    .disabled(true)
            case .outdated, .scriptOutdated:
                Button("Mettre à jour les hooks Claude Code", action: setup.update)
            case .notInstalled, .unreadable:
                Button("Installer les hooks Claude Code", action: setup.showOnboarding)
            }
        }
        Button("Désinstaller Claude Notch…", action: setup.confirmAndUninstall)
    }
}
