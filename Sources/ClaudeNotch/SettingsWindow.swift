import AppKit
import SwiftUI

/// Fenêtre de réglages : créée à l'ouverture, libérée à la fermeture (rien en mémoire le reste du temps).
final class SettingsWindow: NSObject, NSWindowDelegate {
    static let size = CGSize(width: 720, height: 500)

    private let prefs: Preferences
    private let registry: ModuleRegistry
    private var window: NSWindow?

    init(prefs: Preferences, registry: ModuleRegistry) {
        self.prefs = prefs
        self.registry = registry
    }

    func show() {
        if window == nil {
            let view = SettingsView(prefs: prefs, registry: registry, updater: .shared)
            let window = NSWindow(contentRect: NSRect(origin: .zero, size: Self.size),
                                  styleMask: [.titled, .closable, .miniaturizable, .fullSizeContentView],
                                  backing: .buffered, defer: false)
            window.contentView = NSHostingView(rootView: view)
            window.title = L("Réglages de Claude Notch")
            window.titleVisibility = .hidden
            window.titlebarAppearsTransparent = true
            window.isReleasedWhenClosed = false
            // Sur le Space courant, pas sur celui où la fenêtre a été ouverte la première fois.
            window.collectionBehavior = [.moveToActiveSpace]
            window.delegate = self
            window.center()
            self.window = window
        }
        window?.makeKeyAndOrderFront(nil)
        HookSetup.activateApp()
    }

    func windowWillClose(_ notification: Notification) {
        // Le contenu SwiftUI part avec la fenêtre : aucune vue de réglages ne reste en mémoire.
        window?.contentView = nil
        window = nil
    }
}

// MARK: - Menu principal

/// Menu principal (invisible pour une app sans icône dans le Dock) : ses raccourcis marchent dès qu'une fenêtre
/// de l'app est devant. ⌘, ouvre les réglages, ⌘W ferme la fenêtre, ⌘C / ⌘V dans les champs de texte.
enum MainMenu {
    private final class Target: NSObject {
        let action: () -> Void
        init(_ action: @escaping () -> Void) { self.action = action }
        @objc func perform(_ sender: Any?) { action() }
    }

    /// La cible d'un NSMenuItem est faible : on la garde ici.
    private static var settingsTarget: Target?

    static func install(openSettings: @escaping () -> Void) {
        let target = Target(openSettings)
        settingsTarget = target

        let appMenu = NSMenu()
        let settings = NSMenuItem(title: L("Réglages…"), action: #selector(Target.perform(_:)), keyEquivalent: ",")
        settings.target = target
        appMenu.addItem(settings)
        appMenu.addItem(.separator())
        appMenu.addItem(withTitle: L("Quitter Claude Notch"), action: #selector(NSApplication.terminate(_:)),
                        keyEquivalent: "q")

        let editMenu = NSMenu(title: L("Édition"))
        editMenu.addItem(withTitle: L("Annuler"), action: Selector(("undo:")), keyEquivalent: "z")
        editMenu.addItem(withTitle: L("Rétablir"), action: Selector(("redo:")), keyEquivalent: "Z")
        editMenu.addItem(.separator())
        editMenu.addItem(withTitle: L("Couper"), action: #selector(NSText.cut(_:)), keyEquivalent: "x")
        editMenu.addItem(withTitle: L("Copier"), action: #selector(NSText.copy(_:)), keyEquivalent: "c")
        editMenu.addItem(withTitle: L("Coller"), action: #selector(NSText.paste(_:)), keyEquivalent: "v")
        editMenu.addItem(withTitle: L("Tout sélectionner"), action: #selector(NSText.selectAll(_:)), keyEquivalent: "a")

        let windowMenu = NSMenu(title: L("Fenêtre"))
        windowMenu.addItem(withTitle: L("Fermer"), action: #selector(NSWindow.performClose(_:)), keyEquivalent: "w")

        let main = NSMenu()
        for menu in [appMenu, editMenu, windowMenu] {
            let item = NSMenuItem()
            item.submenu = menu
            main.addItem(item)
        }
        NSApp.mainMenu = main
    }
}

// MARK: - Vue

enum SettingsSection: Hashable {
    case general
    case tabs
    case appearance
    case module(String)
    case updates
    case about
}

struct SettingsView: View {
    @ObservedObject var prefs: Preferences
    @ObservedObject var registry: ModuleRegistry
    @ObservedObject var updater: Updater
    @State var selection: SettingsSection? = .general

    static let sidebarWidth: CGFloat = 190

    private struct ModuleEntry: Identifiable {
        let id: String
        let title: String
        let symbol: String
    }

    /// Modules activés qui ont un volet de réglages, dans l'ordre des onglets (Claude d'abord par défaut).
    private var moduleSections: [ModuleEntry] {
        registry.enabled.compactMap { module in
            module.makeSettingsView() == nil ? nil : ModuleEntry(id: module.id, title: module.title, symbol: module.symbol)
        }
    }

    var body: some View {
        HStack(spacing: 0) {
            sidebar
                .frame(width: Self.sidebarWidth)
            Divider()
            detail
                .frame(maxWidth: .infinity, maxHeight: .infinity)
        }
        .frame(width: SettingsWindow.size.width, height: SettingsWindow.size.height)
        .tint(Palette.accent)
    }

    private var sidebar: some View {
        List(selection: $selection) {
            Label("Général", systemImage: "gearshape").tag(SettingsSection.general)
            Label("Onglets", systemImage: "rectangle.split.3x1").tag(SettingsSection.tabs)
            Label("Apparence", systemImage: "paintpalette").tag(SettingsSection.appearance)
            ForEach(moduleSections) { section in
                Label(section.title, systemImage: section.symbol).tag(SettingsSection.module(section.id))
            }
            Label("Mises à jour", systemImage: "arrow.down.circle").tag(SettingsSection.updates)
            Label("À propos", systemImage: "info.circle").tag(SettingsSection.about)
        }
        .listStyle(.sidebar)
        // Sous la barre de titre transparente.
        .padding(.top, 28)
    }

    @ViewBuilder
    private var detail: some View {
        switch selection ?? .general {
        case .general: GeneralSettings(prefs: prefs)
        case .tabs: TabsSettings(prefs: prefs, registry: registry)
        case .appearance: AppearanceSettings(prefs: prefs)
        case .module(let id): registry.module(id)?.makeSettingsView()
        case .updates: UpdateSettings(updater: updater, prefs: prefs)
        case .about: AboutSettings(registry: registry, updater: updater)
        }
    }
}

/// Volet de réglages : formulaire groupé. Les modules s'en servent pour leur propre volet.
struct SettingsPane<Content: View>: View {
    @ViewBuilder let content: Content

    var body: some View {
        Form { content }
            .formStyle(.grouped)
    }
}

/// Petit texte explicatif sous un réglage.
struct SettingsNote: View {
    let text: String

    init(_ text: String) { self.text = text }

    var body: some View {
        Text(text)
            .font(.system(size: 11))
            .foregroundColor(.secondary)
            .fixedSize(horizontal: false, vertical: true)
    }
}

// MARK: - Général

private struct GeneralSettings: View {
    @ObservedObject var prefs: Preferences

    var body: some View {
        SettingsPane {
            Section {
                Toggle("Lancer à l'ouverture de session", isOn: $prefs.launchAtLogin)
                Toggle("Toujours visible", isOn: $prefs.alwaysVisible)
                SettingsNote(L("Sinon, la notch ne s'ouvre que lorsque Claude tourne (CLI ou Claude Desktop)."))
            }
            Section("Survol") {
                delaySlider(L("Délai d'ouverture"), value: $prefs.openDelay, range: Preferences.openDelayRange)
                delaySlider(L("Délai de fermeture"), value: $prefs.closeDelay, range: Preferences.closeDelayRange)
                Toggle("Retour haptique à l'ouverture", isOn: $prefs.hapticFeedback)
            }
            Section("Plein écran") {
                Picker("Quand une app est en plein écran", selection: $prefs.fullScreenBehavior) {
                    Text("Panneau compact").tag(FullScreenBehavior.compact)
                    Text("Panneau normal").tag(FullScreenBehavior.normal)
                    Text("Notch masquée").tag(FullScreenBehavior.hidden)
                }
                SettingsNote(L("Compact : demi-largeur, seulement l'essentiel (sessions Claude en cours, résumé de "
                    + "chaque onglet). Les oreilles restent les mêmes."))
            }
        }
    }

    private func delaySlider(_ title: String, value: Binding<Double>, range: ClosedRange<Double>) -> some View {
        LabeledContent {
            HStack(spacing: 10) {
                Slider(value: value, in: range, step: 0.01)
                    .frame(width: 200)
                Text(String(format: L("%d ms"), Int((value.wrappedValue * 1000).rounded())))
                    .monospacedDigit()
                    .foregroundColor(.secondary)
                    .frame(width: 56, alignment: .trailing)
            }
        } label: {
            Text(title)
        }
    }
}

// MARK: - Onglets

private struct TabsSettings: View {
    @ObservedObject var prefs: Preferences
    @ObservedObject var registry: ModuleRegistry

    var body: some View {
        SettingsPane {
            Section {
                ForEach(registry.ordered.map { $0.id }, id: \.self) { id in
                    if let module = registry.module(id) {
                        row(module)
                    }
                }
                .onMove { source, destination in registry.move(from: source, to: destination) }
            } header: {
                Text("Onglets")
            } footer: {
                SettingsNote(L("Glisse les onglets pour changer leur ordre. Un onglet désactivé ne fait rien, "
                    + "même en arrière-plan. Claude reste toujours actif."))
            }
            Section {
                Picker("Onglet à l'ouverture", selection: $prefs.defaultTab) {
                    Text("Dernier utilisé").tag(Preferences.lastTabChoice)
                    ForEach(registry.enabled.map { $0.id }, id: \.self) { id in
                        Text(registry.module(id)?.title ?? id).tag(id)
                    }
                }
                SettingsNote(L("Quand Claude attend ta réponse, la notch s'ouvre toujours sur Claude."))
            }
        }
    }

    private func row(_ module: any NotchModule) -> some View {
        let id = module.id
        return HStack(spacing: 10) {
            Image(systemName: "line.3.horizontal")
                .foregroundColor(.secondary)
            Image(systemName: module.symbol)
                .frame(width: 20)
                .foregroundColor(Palette.accent)
            Text(module.title)
            Spacer()
            Toggle("Activé", isOn: Binding(get: { registry.isEnabled(id) },
                                           set: { registry.setEnabled(id, $0) }))
                .labelsHidden()
                .toggleStyle(.switch)
                .disabled(id == ModuleRegistry.claudeId)
        }
    }
}

// MARK: - Apparence

private struct AppearanceSettings: View {
    @ObservedObject var prefs: Preferences

    private var customColor: Binding<Color> {
        Binding(get: { prefs.accent },
                set: { color in if let hex = color.hexString { prefs.accentHex = hex } })
    }

    var body: some View {
        SettingsPane {
            Section("Couleur d'accent") {
                HStack(spacing: 10) {
                    ForEach(Preferences.accentPresets, id: \.self) { hex in
                        swatch(hex)
                    }
                    Divider().frame(height: 22)
                    ColorPicker(selection: customColor, supportsOpacity: false) {
                        Text("Couleur libre")
                    }
                    .labelsHidden()
                    Spacer()
                }
                .padding(.vertical, 2)
            }
            Section("Panneau") {
                Picker("Taille du panneau", selection: $prefs.panelSize) {
                    Text("Compacte").tag(PanelSize.compact)
                    Text("Standard").tag(PanelSize.standard)
                    Text("Large").tag(PanelSize.large)
                }
                .pickerStyle(.segmented)
                LabeledContent {
                    HStack(spacing: 10) {
                        Slider(value: $prefs.backgroundOpacity, in: Preferences.opacityRange, step: 0.01)
                            .frame(width: 200)
                        Text(verbatim: "\(Int((prefs.backgroundOpacity * 100).rounded())) %")
                            .monospacedDigit()
                            .foregroundColor(.secondary)
                            .frame(width: 44, alignment: .trailing)
                    }
                } label: {
                    Text("Opacité du fond")
                }
            }
            Section("Notch repliée") {
                Toggle("Afficher les oreilles", isOn: $prefs.showEars)
                SettingsNote(L("De part et d'autre de la notch : l'état de Claude (main levée, spinner, coche) et "
                    + "le nombre de sessions, ou ce qu'un onglet signale (minuteur, lecture en cours)."))
            }
        }
    }

    private func swatch(_ hex: String) -> some View {
        let selected = prefs.accentHex.uppercased() == hex
        return Button {
            prefs.accentHex = hex
        } label: {
            Circle()
                .fill(Color(hex: hex) ?? Palette.claudeOrange)
                .frame(width: 22, height: 22)
                .overlay(Circle().strokeBorder(Color.primary.opacity(selected ? 0.9 : 0), lineWidth: 2)
                    .padding(-4))
        }
        .buttonStyle(.plain)
        .padding(4)
    }
}

// MARK: - Mises à jour

private struct UpdateSettings: View {
    @ObservedObject var updater: Updater
    @ObservedObject var prefs: Preferences

    var body: some View {
        SettingsPane {
            Section {
                Text(updater.versionLine)
                if updater.isReleaseBuild {
                    switch updater.status {
                    case .available(let version, _):
                        LabeledContent(String(format: L("Version %@ disponible"), version)) {
                            if updater.canInstall {
                                Button("Installer", action: updater.installNow)
                            } else {
                                Button("Ouvrir la page de la release", action: updater.openReleasePage)
                            }
                        }
                    case .failed(let message):
                        Text(message).foregroundColor(Palette.amber)
                    case .idle, .checking, .installing:
                        EmptyView()
                    }
                    Toggle("Mises à jour automatiques", isOn: $prefs.autoUpdate)
                    HStack {
                        Spacer()
                        Button("Rechercher les mises à jour", action: updater.checkNow)
                            .disabled(updater.isWorking)
                    }
                } else {
                    Text("Build de développement : mises à jour désactivées")
                        .foregroundColor(.secondary)
                }
            } footer: {
                SettingsNote(L("Les nouvelles versions viennent des releases GitHub et ne sont installées que si "
                    + "leur signature est valide."))
            }
        }
    }
}

// MARK: - À propos

private struct AboutSettings: View {
    @ObservedObject var registry: ModuleRegistry
    @ObservedObject var updater: Updater

    static let repository = URL(string: "https://github.com/Slybald/claude-notch")!

    private var notices: [LicenseNotice] { registry.modules.flatMap { $0.licenseNotices } }

    var body: some View {
        SettingsPane {
            Section {
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
                        Text(verbatim: "Claude Notch")
                            .font(.system(size: 15, weight: .semibold))
                        Text(updater.versionLine)
                            .foregroundColor(.secondary)
                    }
                }
                .padding(.vertical, 4)
                Text("Tes sessions Claude Code, d'un coup d'œil.")
                Link(destination: Self.repository) {
                    Text(verbatim: "github.com/Slybald/claude-notch")
                }
                SettingsNote(L("Projet indépendant, ni affilié ni approuvé par Anthropic. Claude est une marque "
                    + "d'Anthropic."))
            }
            Section("Licences") {
                LabeledContent {
                    Text(verbatim: "MIT")
                } label: {
                    Text(verbatim: "Claude Notch")
                }
                if notices.isEmpty {
                    SettingsNote(L("Aucun composant tiers."))
                }
                ForEach(notices) { notice in
                    VStack(alignment: .leading, spacing: 4) {
                        Text(notice.name).font(.system(size: 12, weight: .semibold))
                        Text(notice.text)
                            .font(.system(size: 11, design: .monospaced))
                            .foregroundColor(.secondary)
                            .textSelection(.enabled)
                            .fixedSize(horizontal: false, vertical: true)
                    }
                }
            }
        }
    }
}
