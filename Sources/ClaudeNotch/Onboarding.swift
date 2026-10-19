import AppKit
import SwiftUI

/// État des hooks Claude Code, partagé par le menu « … » et la fenêtre de premier lancement.
final class HookSetup: ObservableObject {
    static let shared = HookSetup()

    /// Relu au lancement, à l'ouverture du panneau et après chaque action (jamais dans `init`).
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

    /// Au lancement : la fenêtre s'ouvre si les hooks manquent, sont anciens ou si settings.json est illisible.
    func showOnboardingIfNeeded() {
        refresh()
        if status != .installed { showOnboarding() }
    }

    // MARK: - Fenêtre de premier lancement

    func showOnboarding() {
        DispatchQueue.main.async { [self] in
            refresh()
            if let onboarding {
                onboarding.showWindow(nil)
                Self.activateApp()
                return
            }
            var error: String?
            if case .unreadable(let message) = status { error = message }
            let view = OnboardingView(
                mode: status == .outdated ? .update : .install,
                inApplications: isInApplications,
                launchAtLogin: status == .notInstalled || Preferences.shared.launchAtLogin,
                error: error,
                onInstall: { [weak self] launchAtLogin in self?.installFromWindow(launchAtLogin: launchAtLogin) },
                onClose: { [weak self] in self?.onboarding?.close() }
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
        // Hors Applications, le LaunchAgent pointerait vers le DMG ou une copie temporaire.
        if isInApplications, Preferences.shared.launchAtLogin != launchAtLogin {
            Preferences.shared.launchAtLogin = launchAtLogin
        }
        let controller = onboarding
        DispatchQueue.main.asyncAfter(deadline: .now() + 4) { controller?.close() }
        return nil
    }

    // MARK: - Menu « … »

    /// Hooks anciens : réinstallés directement (l'accord a déjà été donné à l'installation).
    func update() {
        DispatchQueue.main.async { [self] in
            do {
                try installer.install()
            } catch {
                Self.activateApp()
                Self.showError(error, title: "Mise à jour des hooks impossible")
            }
            refresh()
        }
    }

    /// Confirmation, puis retrait des hooks, du script de hook et du LaunchAgent, puis Quitter.
    func confirmAndUninstall() {
        DispatchQueue.main.async { [self] in
            Self.activateApp()
            let alert = NSAlert()
            alert.alertStyle = .warning
            alert.messageText = "Désinstaller Claude Notch ?"
            alert.informativeText = "Les hooks de Claude Notch seront retirés de ~/.claude/settings.json (sauvegarde "
                + "horodatée à côté, tes autres hooks restent en place), ainsi que ~/.claude/hooks/claude-notch-hook.sh "
                + "et le lancement à l'ouverture de session. L'app se fermera ensuite."
            alert.addButton(withTitle: "Désinstaller")
            alert.addButton(withTitle: "Annuler")
            alert.buttons.first?.hasDestructiveAction = true
            guard alert.runModal() == .alertFirstButtonReturn else { return }

            do {
                try installer.uninstall()
            } catch {
                refresh()
                Self.showError(error, title: "Désinstallation interrompue")
                return
            }
            LaunchAgent.setEnabled(false)

            let done = NSAlert()
            done.messageText = "Claude Notch est désinstallé"
            done.informativeText = "Il ne reste qu'à jeter Claude Notch à la Corbeille, depuis le dossier Applications. "
                + "Les sessions Claude Code déjà ouvertes l'oublieront à leur redémarrage."
            done.addButton(withTitle: "Afficher dans le Finder")
            done.addButton(withTitle: "Quitter")
            if done.runModal() == .alertFirstButtonReturn {
                NSWorkspace.shared.activateFileViewerSelecting([Bundle.main.bundleURL])
            }
            NSApp.terminate(nil)
        }
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
    enum Mode { case install, update }

    private enum Phase: Equatable {
        case idle
        case done
        case failed(String)
    }

    let mode: Mode
    let inApplications: Bool
    /// nil si tout s'est bien passé, sinon le message d'erreur.
    let onInstall: (_ launchAtLogin: Bool) -> String?
    let onClose: () -> Void

    @State private var launchAtLogin: Bool
    @State private var phase: Phase

    init(mode: Mode, inApplications: Bool, launchAtLogin: Bool, error: String? = nil,
         onInstall: @escaping (_ launchAtLogin: Bool) -> String?, onClose: @escaping () -> Void) {
        self.mode = mode
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
            changes
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
                        .fill(Palette.orange.opacity(0.16))
                    Image(systemName: "rectangle.topthird.inset.filled")
                        .font(.system(size: 22, weight: .medium))
                        .foregroundColor(Palette.orange)
                }
                .frame(width: 48, height: 48)
                VStack(alignment: .leading, spacing: 3) {
                    Text(mode == .update ? "Mettre à jour Claude Notch" : "Bienvenue dans Claude Notch")
                        .font(.system(size: 17, weight: .semibold))
                    Text("Tes sessions Claude Code, d'un coup d'œil.")
                        .font(.system(size: 12))
                        .foregroundColor(Palette.secondary)
                }
            }
            Text(mode == .update
                 ? "Les hooks installés viennent d'une version précédente de l'app. Mets-les à jour pour que la notch "
                    + "continue de suivre tes sessions."
                 : "Survole la notch : chaque session Claude Code (terminal, éditeur ou Claude Desktop) y affiche son "
                    + "état, l'outil en cours, ses tâches et les permissions qui t'attendent. Tout reste sur ton Mac.")
                .font(.system(size: 12.5))
                .foregroundColor(.white.opacity(0.85))
                .fixedSize(horizontal: false, vertical: true)
        }
    }

    private var applicationsWarning: some View {
        HStack(alignment: .top, spacing: 10) {
            Image(systemName: "exclamationmark.triangle.fill")
                .font(.system(size: 14))
                .foregroundColor(Palette.amber)
            VStack(alignment: .leading, spacing: 3) {
                Text("Glisse d'abord Claude Notch dans Applications")
                    .font(.system(size: 12.5, weight: .semibold))
                Text("L'app tourne depuis l'image disque ou une copie temporaire. Quitte-la, glisse-la dans le dossier "
                     + "Applications, puis rouvre-la depuis là.")
                    .font(.system(size: 11.5))
                    .foregroundColor(Palette.secondary)
                    .fixedSize(horizontal: false, vertical: true)
            }
        }
        .padding(12)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(RoundedRectangle(cornerRadius: 12, style: .continuous).fill(Palette.amber.opacity(0.12)))
    }

    private var changes: some View {
        VStack(alignment: .leading, spacing: 12) {
            Text("CE QUI SERA MODIFIÉ")
                .font(.system(size: 10.5, weight: .semibold))
                .tracking(0.6)
                .foregroundColor(Palette.secondary)
            ChangeRow(icon: "doc.text", path: "~/.claude/settings.json",
                      detail: "Ajout des hooks de Claude Notch. Tes hooks restent en place ; une sauvegarde horodatée "
                        + "est faite à côté.")
            ChangeRow(icon: "terminal", path: "~/.claude/hooks/claude-notch-hook.sh",
                      detail: "Petit script qui relaie chaque événement à l'app, en local (127.0.0.1).")
        }
        .padding(14)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(RoundedRectangle(cornerRadius: 14, style: .continuous).fill(Palette.card))
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
        (mode == .update ? "Hooks à jour." : "Hooks installés.")
            + " Les sessions déjà ouvertes apparaîtront à leur prochain message."
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
                Button("Fermer", action: onClose)
                    .keyboardShortcut(.defaultAction)
            } else {
                Button("Plus tard", action: onClose)
                    .keyboardShortcut(.cancelAction)
                Button(mode == .update ? "Mettre à jour les hooks" : "Installer les hooks Claude Code") {
                    if let error = onInstall(launchAtLogin) {
                        phase = .failed(error)
                    } else {
                        phase = .done
                    }
                }
                .keyboardShortcut(.defaultAction)
                .buttonStyle(.borderedProminent)
                .tint(Palette.orange)
            }
        }
        .controlSize(.large)
    }
}

private struct ChangeRow: View {
    let icon: String
    let path: String
    let detail: String

    var body: some View {
        HStack(alignment: .top, spacing: 10) {
            Image(systemName: icon)
                .font(.system(size: 13))
                .foregroundColor(Palette.orange)
                .frame(width: 18)
            VStack(alignment: .leading, spacing: 2) {
                Text(path)
                    .font(.system(size: 12, weight: .medium, design: .monospaced))
                Text(detail)
                    .font(.system(size: 11.5))
                    .foregroundColor(Palette.secondary)
                    .fixedSize(horizontal: false, vertical: true)
            }
        }
    }
}

// MARK: - Menu

/// Entrées du menu « … » du panneau : état des hooks et désinstallation.
struct HookMenuItems: View {
    @ObservedObject var setup: HookSetup

    var body: some View {
        switch setup.status {
        case .installed:
            Button("Hooks Claude Code installés ✓") {}
                .disabled(true)
        case .outdated:
            Button("Mettre à jour les hooks Claude Code", action: setup.update)
        case .notInstalled, .unreadable:
            Button("Installer les hooks Claude Code", action: setup.showOnboarding)
        }
        Button("Désinstaller Claude Notch…", action: setup.confirmAndUninstall)
    }
}
