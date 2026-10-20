import AppKit
import SwiftUI
import UniformTypeIdentifiers

// MARK: - Onglet

private struct ListHeightKey: PreferenceKey {
    static var defaultValue: CGFloat = 0
    static func reduce(value: inout CGFloat, nextValue: () -> CGFloat) { value = max(value, nextValue()) }
}

/// Recherche, puis la liste : épinglés d'abord, le plus récent en haut. Un clic recopie l'élément.
/// Le clavier (↑ ↓ Entrée Échap) n'agit que quand le champ de recherche a le focus.
struct ClipboardPanel: View {
    @ObservedObject var module: ClipboardModule
    @Environment(\.notchContentMaxHeight) private var contentMaxHeight

    @State private var query: String
    @State private var selection: UUID?
    @State private var searchFocused: Bool
    @State private var listHeight: CGFloat = 0
    /// Survol simulé d'une ligne (rendus de test).
    private let previewHover: UUID?

    private static let spacing: CGFloat = 8
    private static let searchHeight: CGFloat = 26
    private static let stripHeight: CGFloat = 30

    init(module: ClipboardModule, query: String = "", selection: UUID? = nil, searchFocused: Bool = false,
         hovered: UUID? = nil) {
        self.module = module
        _query = State(initialValue: query)
        _selection = State(initialValue: selection)
        _searchFocused = State(initialValue: searchFocused)
        previewHover = hovered
    }

    private var listMaxHeight: CGFloat {
        let fixed = Self.searchHeight + Self.spacing + (module.suspended ? Self.stripHeight + Self.spacing : 0)
        return max(120, contentMaxHeight - fixed)
    }

    var body: some View {
        let all = module.history.ordered
        let results = ClipboardHistory.filter(all, query: query)
        VStack(alignment: .leading, spacing: Self.spacing) {
            if module.suspended {
                SuspendedStrip { module.suspended = false }
                    .transition(.opacity)
            }
            if all.isEmpty {
                ClipboardEmptyState()
            } else {
                ClipboardSearchBar(query: $query, focused: $searchFocused, onMove: { move($0, in: results) },
                                   onSubmit: { submit(results) }, onCancel: leaveSearch)
                    .frame(height: Self.searchHeight)
                if results.isEmpty {
                    NoResults(query: query)
                } else {
                    list(results)
                }
            }
        }
        .animation(notchSpring, value: module.suspended)
        .onChange(of: query) { newValue in
            selection = newValue.isEmpty ? nil : ClipboardHistory.filter(module.history.ordered, query: newValue).first?.id
        }
        .onDisappear { if searchFocused { NotchKeyboard.release(force: true) } }
    }

    // MARK: Liste

    private func list(_ results: [ClipboardItem]) -> some View {
        let lastPinned = results.lastIndex { $0.pinned }
        let estimate = CGFloat(results.count) * 40
        return ScrollViewReader { proxy in
            ScrollView(.vertical, showsIndicators: false) {
                // Relu chaque minute : « il y a 3 min » reste juste tant que le panneau est ouvert.
                TimelineView(.everyMinute) { context in
                    VStack(spacing: 3) {
                        ForEach(Array(results.enumerated()), id: \.element.id) { index, item in
                            ClipboardRow(item: item, now: context.date, selected: selection == item.id,
                                         copied: module.copiedID == item.id, simulatedHover: previewHover == item.id,
                                         actions: actions(for: item))
                                .id(item.id)
                            if index == lastPinned, index < results.count - 1 {
                                Rectangle().fill(Color.white.opacity(0.08)).frame(height: 1).padding(.vertical, 2)
                            }
                        }
                    }
                    .background(GeometryReader { proxy in
                        Color.clear.preference(key: ListHeightKey.self, value: proxy.size.height)
                    })
                }
            }
            .frame(height: min(listHeight > 0 ? listHeight : estimate, listMaxHeight))
            .onPreferenceChange(ListHeightKey.self) { listHeight = $0 }
            .onChange(of: selection) { id in
                if let id { withAnimation(.easeOut(duration: 0.12)) { proxy.scrollTo(id) } }
            }
        }
    }

    private func actions(for item: ClipboardItem) -> ClipboardRow.Actions {
        ClipboardRow.Actions(
            copy: { copy(item.id, plainText: false) },
            copyPlain: { copy(item.id, plainText: true) },
            pin: { withAnimation(notchSpring) { module.togglePin(item.id) } },
            remove: { withAnimation(notchSpring) { module.remove(item.id) } })
    }

    // MARK: Clavier

    private func move(_ delta: Int, in results: [ClipboardItem]) {
        selection = Self.nextSelection(from: selection, delta: delta, in: results)
    }

    /// ↓ / ↑ : la ligne suivante ou précédente, sans boucler ; sans choix, la première (↓) ou la dernière (↑).
    static func nextSelection(from current: UUID?, delta: Int, in results: [ClipboardItem]) -> UUID? {
        guard !results.isEmpty else { return nil }
        let index = results.firstIndex { $0.id == current }
        let next = index.map { min(max($0 + delta, 0), results.count - 1) } ?? (delta > 0 ? 0 : results.count - 1)
        return results[next].id
    }

    /// Entrée : copie l'élément choisi, à défaut le premier résultat.
    private func submit(_ results: [ClipboardItem]) {
        guard let id = results.first(where: { $0.id == selection })?.id ?? results.first?.id else { return }
        copy(id, plainText: false)
    }

    /// Recopier rend le clavier à l'app de devant : c'est elle qui doit recevoir ⌘V.
    private func copy(_ id: UUID, plainText: Bool) {
        module.copy(id, plainText: plainText)
        leaveSearch()
    }

    private func leaveSearch() {
        searchFocused = false
        NotchKeyboard.release(force: true)
    }
}

// MARK: - Ligne

struct ClipboardRow: View {
    struct Actions {
        var copy: () -> Void
        var copyPlain: () -> Void
        var pin: () -> Void
        var remove: () -> Void
    }

    let item: ClipboardItem
    let now: Date
    let selected: Bool
    let copied: Bool
    var simulatedHover = false
    let actions: Actions

    @State private var hovering = false

    var body: some View {
        let active = hovering || simulatedHover
        HStack(spacing: 8) {
            ClipboardSourceIcon(source: item.source, content: item.content)
                .frame(width: 18)
            ClipboardPreview(item: item)
                .frame(maxWidth: .infinity, alignment: .leading)
            trailing(active)
        }
        .padding(.horizontal, 8)
        .padding(.vertical, 5)
        .frame(minHeight: 32)
        .background(RoundedRectangle(cornerRadius: 8, style: .continuous)
            .fill(selected ? Palette.accent.opacity(0.2) : Color.white.opacity(active ? 0.1 : 0.05)))
        .overlay(RoundedRectangle(cornerRadius: 8, style: .continuous)
            .stroke(Palette.accent.opacity(selected ? 0.7 : 0), lineWidth: 1))
        .contentShape(RoundedRectangle(cornerRadius: 8, style: .continuous))
        .onTapGesture(perform: actions.copy)
        .onHover { hovering = $0 }
        .animation(.easeOut(duration: 0.12), value: active)
        .animation(.easeOut(duration: 0.12), value: copied)
        .contextMenu {
            Button(action: actions.copy) { Text("Copier", tableName: "Clipboard") }
            if item.content.plainText != nil {
                Button(action: actions.copyPlain) { Text("Copier en texte brut", tableName: "Clipboard") }
            }
            Divider()
            Button(action: actions.pin) {
                Text(verbatim: item.pinned ? L("Désépingler", table: "Clipboard") : L("Épingler", table: "Clipboard"))
            }
            Button(action: actions.remove) { Text("Supprimer", tableName: "Clipboard") }
        }
        .accessibilityElement(children: .combine)
        .accessibilityAddTraits(.isButton)
    }

    /// Heure relative au repos ; épingle et corbeille au survol ; « Copié » un instant après un clic.
    @ViewBuilder
    private func trailing(_ active: Bool) -> some View {
        Group {
            if copied {
                HStack(spacing: 3) {
                    Image(systemName: "checkmark")
                    Text("Copié", tableName: "Clipboard")
                }
                .font(.system(size: 10.5, weight: .semibold))
                .foregroundColor(.white)
                .padding(.horizontal, 8)
                .padding(.vertical, 3)
                .background(Capsule().fill(Palette.accent))
                .transition(.opacity)
            } else if active {
                HStack(spacing: 2) {
                    ClipboardIconButton(symbol: item.pinned ? "pin.slash" : "pin",
                                        label: item.pinned ? L("Désépingler", table: "Clipboard")
                                            : L("Épingler", table: "Clipboard"), action: actions.pin)
                    ClipboardIconButton(symbol: "trash", label: L("Supprimer", table: "Clipboard"),
                                        action: actions.remove)
                }
            } else {
                HStack(spacing: 4) {
                    if item.truncated {
                        Image(systemName: "scissors")
                            .help(L("Texte coupé à 20 000 caractères", table: "Clipboard"))
                    }
                    if item.pinned {
                        Image(systemName: "pin.fill").foregroundColor(Palette.accent)
                    }
                    Text(verbatim: SessionCard.relative(now.timeIntervalSince(item.date)))
                }
                .font(.system(size: 10))
                .foregroundColor(Palette.secondary)
                .lineLimit(1)
            }
        }
        .frame(minWidth: 62, alignment: .trailing)
    }
}

/// Bouton d'action de ligne : symbole seul, halo au survol.
struct ClipboardIconButton: View {
    let symbol: String
    let label: String
    let action: () -> Void
    @State private var hovering = false

    var body: some View {
        Button(action: action) {
            Image(systemName: symbol)
                .font(.system(size: 11, weight: .semibold))
                .foregroundColor(.white.opacity(hovering ? 1 : 0.75))
                .frame(width: 26, height: 22)
                .background(Circle().fill(Color.white.opacity(hovering ? 0.14 : 0)))
                .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .onHover { hovering = $0 }
        .help(label)
        .accessibilityLabel(label)
    }
}

/// Icône de l'app source ; à défaut, un symbole selon le type de contenu.
struct ClipboardSourceIcon: View {
    let source: ClipboardSource?
    let content: ClipboardContent

    var body: some View {
        if let source, let icon = ClipboardAppIcons.icon(for: source.bundleID) {
            Image(nsImage: icon)
                .resizable()
                .frame(width: 16, height: 16)
                .help(source.name)
        } else {
            Image(systemName: fallbackSymbol)
                .font(.system(size: 12, weight: .medium))
                .foregroundColor(Palette.secondary)
        }
    }

    private var fallbackSymbol: String {
        switch content {
        case .text: return "text.alignleft"
        case .url: return "link"
        case .image: return "photo"
        case .files: return "doc"
        case .color: return "paintpalette"
        }
    }
}

// MARK: - Aperçus

struct ClipboardPreview: View {
    let item: ClipboardItem

    var body: some View {
        switch item.content {
        case .text(let text):
            Text(verbatim: Self.preview(text))
                .font(.system(size: 11.5))
                .foregroundColor(Palette.primary)
                .lineLimit(2)
                .multilineTextAlignment(.leading)
        case .url(let url):
            link(url)
        case .image(let image):
            HStack(spacing: 8) {
                Image(nsImage: image.thumbnail)
                    .resizable()
                    .aspectRatio(contentMode: .fit)
                    .frame(maxWidth: 52, maxHeight: 34)
                    .clipShape(RoundedRectangle(cornerRadius: 4, style: .continuous))
                VStack(alignment: .leading, spacing: 1) {
                    Text("Image", tableName: "Clipboard")
                        .font(.system(size: 11.5, weight: .medium))
                        .foregroundColor(Palette.primary)
                    Text(verbatim: Self.imageDetail(image))
                        .font(.system(size: 10))
                        .foregroundColor(Palette.secondary)
                }
            }
        case .files(let urls):
            HStack(spacing: 8) {
                Image(nsImage: ClipboardFileIcons.icon(for: urls[0]))
                    .resizable()
                    .frame(width: 22, height: 22)
                VStack(alignment: .leading, spacing: 1) {
                    Text(verbatim: urls[0].lastPathComponent)
                        .font(.system(size: 11.5, weight: .medium))
                        .foregroundColor(Palette.primary)
                        .lineLimit(1)
                        .truncationMode(.middle)
                    if urls.count > 1 {
                        Text(verbatim: String(format: L(urls.count - 1, one: "et %d autre fichier",
                                                        other: "et %d autres fichiers", table: "Clipboard"),
                                              urls.count - 1))
                            .font(.system(size: 10))
                            .foregroundColor(Palette.secondary)
                    }
                }
            }
        case .color(let hex):
            HStack(spacing: 8) {
                Circle()
                    .fill(Color(hex: hex) ?? .clear)
                    .overlay(Circle().stroke(Color.white.opacity(0.3), lineWidth: 1))
                    .frame(width: 16, height: 16)
                Text(verbatim: "#" + hex)
                    .font(.system(size: 11.5, weight: .medium, design: .monospaced))
                    .foregroundColor(Palette.primary)
            }
        }
    }

    /// Le début du texte seulement : inutile de mettre en page 20 000 caractères pour en montrer deux lignes.
    static func preview(_ text: String) -> String {
        String(text.prefix(300)).trimmingCharacters(in: .whitespacesAndNewlines)
    }

    /// Domaine en évidence, chemin en retrait.
    static func linkParts(_ url: URL) -> (host: String, rest: String) {
        var host = url.host ?? url.absoluteString
        if host.hasPrefix("www.") { host.removeFirst(4) }
        var rest = url.path
        if let query = url.query { rest += "?" + query }
        return (host, rest == "/" ? "" : rest)
    }

    static func imageDetail(_ image: ClipboardImage) -> String {
        let size = "\(Int(image.pixelSize.width)) × \(Int(image.pixelSize.height))"
        return size + " · " + ByteCountFormatter.string(fromByteCount: Int64(image.data.count), countStyle: .file)
    }

    private func link(_ url: URL) -> some View {
        let parts = Self.linkParts(url)
        return HStack(spacing: 6) {
            Image(systemName: "link")
                .font(.system(size: 10, weight: .semibold))
                .foregroundColor(Palette.accent)
            VStack(alignment: .leading, spacing: 0) {
                Text(verbatim: parts.host)
                    .font(.system(size: 12, weight: .semibold))
                    .foregroundColor(Palette.primary)
                    .lineLimit(1)
                if !parts.rest.isEmpty {
                    Text(verbatim: parts.rest)
                        .font(.system(size: 10))
                        .foregroundColor(Palette.secondary)
                        .lineLimit(1)
                        .truncationMode(.middle)
                }
            }
        }
    }
}

/// Icône d'un fichier d'après son extension : aucun accès au fichier (dossiers protégés).
enum ClipboardFileIcons {
    private static var cache: [String: NSImage] = [:]

    static func icon(for url: URL) -> NSImage {
        let key = url.hasDirectoryPath ? "/" : url.pathExtension.lowercased()
        if let cached = cache[key] { return cached }
        let type = key == "/" ? UTType.folder : (UTType(filenameExtension: key) ?? .data)
        let icon = NSWorkspace.shared.icon(for: type)
        cache[key] = icon
        return icon
    }
}

// MARK: - États

struct ClipboardEmptyState: View {
    var body: some View {
        VStack(spacing: 8) {
            Image(systemName: "doc.on.clipboard")
                .font(.system(size: 22, weight: .medium))
                .foregroundColor(Palette.accent)
            Text("Copie du texte, un lien ou une image : ils apparaîtront ici.", tableName: "Clipboard")
                .font(.system(size: 11.5))
                .foregroundColor(Palette.secondary)
                .multilineTextAlignment(.center)
        }
        .frame(maxWidth: .infinity)
        .padding(.vertical, 20)
    }
}

private struct NoResults: View {
    let query: String

    var body: some View {
        Text(verbatim: String(format: L("Aucun résultat pour « %@ »", table: "Clipboard"), query))
            .font(.system(size: 11.5))
            .foregroundColor(Palette.secondary)
            .lineLimit(1)
            .frame(maxWidth: .infinity)
            .padding(.vertical, 14)
    }
}

/// Bandeau « Capture suspendue » au-dessus de la liste.
struct SuspendedStrip: View {
    let resume: () -> Void

    var body: some View {
        HStack(spacing: 6) {
            Image(systemName: "pause.circle.fill")
                .foregroundColor(Palette.amber)
            Text("Capture suspendue", tableName: "Clipboard")
                .font(.system(size: 11.5, weight: .medium))
                .foregroundColor(Palette.primary)
            Spacer(minLength: 4)
            Button(action: resume) {
                Text("Reprendre", tableName: "Clipboard")
                    .font(.system(size: 11, weight: .semibold))
                    .foregroundColor(Palette.amber)
            }
            .buttonStyle(.plain)
        }
        .padding(.horizontal, 10)
        .frame(height: 30)
        .background(RoundedRectangle(cornerRadius: 8, style: .continuous).fill(Palette.amber.opacity(0.12)))
    }
}

// MARK: - En-tête

/// À droite des onglets : suspendre ou reprendre la capture.
struct ClipboardSuspendButton: View {
    @ObservedObject var module: ClipboardModule
    @State private var hovering = false

    private var label: String {
        module.suspended ? L("Reprendre la capture", table: "Clipboard") : L("Suspendre la capture", table: "Clipboard")
    }

    var body: some View {
        Button {
            module.suspended.toggle()
        } label: {
            if module.suspended {
                HStack(spacing: 4) {
                    Image(systemName: "play.fill").font(.system(size: 8, weight: .bold))
                    Text("Reprendre", tableName: "Clipboard")
                }
                .font(.system(size: 10.5, weight: .semibold))
                .foregroundColor(Palette.amber)
                .padding(.horizontal, 8)
                .padding(.vertical, 3)
                .background(Capsule().fill(Palette.amber.opacity(0.16)))
            } else {
                Image(systemName: "pause.circle")
                    .font(.system(size: 13, weight: .medium))
                    .foregroundColor(.white.opacity(hovering ? 1 : 0.65))
                    .frame(width: 22, height: 18)
            }
        }
        .buttonStyle(.plain)
        .onHover { hovering = $0 }
        .help(label)
        .accessibilityLabel(label)
        .animation(.easeOut(duration: 0.12), value: module.suspended)
    }
}

// MARK: - Recherche

/// Champ de recherche : loupe, champ, effacer, rappel des touches quand il a le focus.
struct ClipboardSearchBar: View {
    @Binding var query: String
    @Binding var focused: Bool
    let onMove: (Int) -> Void
    let onSubmit: () -> Void
    let onCancel: () -> Void

    var body: some View {
        HStack(spacing: 6) {
            Image(systemName: "magnifyingglass")
                .font(.system(size: 11, weight: .semibold))
                .foregroundColor(.white.opacity(0.45))
            ClipboardSearchField(text: $query, placeholder: L("Rechercher", table: "Clipboard"),
                                 onFocus: { focused = $0 }, onMove: onMove, onSubmit: onSubmit, onCancel: onCancel)
                .frame(maxWidth: .infinity)
                .frame(height: 18)
            if !query.isEmpty {
                Button { query = "" } label: {
                    Image(systemName: "xmark.circle.fill")
                        .font(.system(size: 11))
                        .foregroundColor(.white.opacity(0.45))
                }
                .buttonStyle(.plain)
                .help(L("Effacer la recherche", table: "Clipboard"))
            } else if focused {
                Text(verbatim: "↑↓  ⏎  esc")
                    .font(.system(size: 10, weight: .medium))
                    .foregroundColor(.white.opacity(0.35))
            }
        }
        .padding(.horizontal, 8)
        .background(RoundedRectangle(cornerRadius: 8, style: .continuous).fill(Color.white.opacity(0.08)))
        .overlay(RoundedRectangle(cornerRadius: 8, style: .continuous)
            .stroke(Palette.accent.opacity(focused ? 0.8 : 0), lineWidth: 1))
        .animation(.easeOut(duration: 0.12), value: focused)
    }
}

/// `NSTextField` plutôt que `TextField` : sous macOS 13, seul le délégué de l'éditeur de champ voit ↑ ↓ Entrée
/// Échap. Le panneau ne s'active jamais : le clavier est pris par `NotchKeyboard.take()` quand le champ reçoit le
/// focus, et rendu à l'app de devant quand il le perd.
struct ClipboardSearchField: NSViewRepresentable {
    @Binding var text: String
    let placeholder: String
    let onFocus: (Bool) -> Void
    let onMove: (Int) -> Void
    let onSubmit: () -> Void
    let onCancel: () -> Void

    final class Field: NSTextField {
        var gainedFocus: () -> Void = {}

        override func becomeFirstResponder() -> Bool {
            let accepted = super.becomeFirstResponder()
            if accepted {
                (currentEditor() as? NSTextView)?.insertionPointColor = .white
                gainedFocus()
            }
            return accepted
        }
    }

    final class Coordinator: NSObject, NSTextFieldDelegate {
        var parent: ClipboardSearchField
        var isFocused = false

        init(_ parent: ClipboardSearchField) { self.parent = parent }

        func focusGained() {
            isFocused = true
            NotchKeyboard.take()
            parent.onFocus(true)
        }

        func controlTextDidChange(_ note: Notification) {
            if let field = note.object as? NSTextField { parent.text = field.stringValue }
        }

        func controlTextDidEndEditing(_ note: Notification) {
            isFocused = false
            parent.onFocus(false)
            // Au tour suivant : pendant la notification l'éditeur de champ est encore le premier répondeur, et
            // `release()` ne rend le clavier que si plus aucun champ n'est en cours de saisie.
            DispatchQueue.main.async { NotchKeyboard.release() }
        }

        func control(_ control: NSControl, textView: NSTextView, doCommandBy selector: Selector) -> Bool {
            switch selector {
            case #selector(NSResponder.moveUp(_:)): parent.onMove(-1)
            case #selector(NSResponder.moveDown(_:)): parent.onMove(1)
            case #selector(NSResponder.insertNewline(_:)): parent.onSubmit()
            case #selector(NSResponder.cancelOperation(_:)):
                control.window?.makeFirstResponder(nil)
                parent.onCancel()
            default: return false
            }
            return true
        }
    }

    func makeCoordinator() -> Coordinator { Coordinator(self) }

    func makeNSView(context: Context) -> Field {
        let field = Field()
        field.isBordered = false
        field.drawsBackground = false
        field.focusRingType = .none
        field.font = .systemFont(ofSize: 12)
        field.textColor = .white
        field.appearance = NSAppearance(named: .darkAqua)
        field.cell?.usesSingleLineMode = true
        field.cell?.lineBreakMode = .byTruncatingTail
        field.placeholderAttributedString = NSAttributedString(
            string: placeholder,
            attributes: [.foregroundColor: NSColor.white.withAlphaComponent(0.4), .font: NSFont.systemFont(ofSize: 12)])
        field.delegate = context.coordinator
        field.gainedFocus = { [weak coordinator = context.coordinator] in coordinator?.focusGained() }
        return field
    }

    func updateNSView(_ field: Field, context: Context) {
        context.coordinator.parent = self
        if field.stringValue != text { field.stringValue = text }
    }

    static func dismantleNSView(_ field: Field, coordinator: Coordinator) {
        if coordinator.isFocused { NotchKeyboard.release(force: true) }
    }
}

// MARK: - Réglages

/// Réglages › Presse-papiers : capture, plafond, disque, confidentialité.
struct ClipboardSettingsView: View {
    @ObservedObject var module: ClipboardModule
    @State private var confirmingClear = false

    var body: some View {
        SettingsPane {
            Section {
                Toggle(isOn: $module.suspended) { Text("Suspendre la capture", tableName: "Clipboard") }
                Picker(selection: $module.limit) {
                    ForEach(ClipboardModule.limits, id: \.self) { Text(verbatim: "\($0)").tag($0) }
                } label: {
                    Text("Éléments gardés", tableName: "Clipboard")
                }
                SettingsNote(L("Les éléments épinglés s'ajoutent à ce nombre et ne sont jamais retirés. Les images de "
                    + "plus de 5 Mo ne sont pas gardées.", table: "Clipboard"))
                Toggle(isOn: $module.keepsHistory) {
                    Text("Garder l'historique après redémarrage", tableName: "Clipboard")
                }
                SettingsNote(L("Désactivé, l'historique reste en mémoire et disparaît à la fermeture de l'app. Activé, "
                    + "les textes et les liens sont écrits dans un fichier privé ; les images et les fichiers n'y "
                    + "sont jamais.", table: "Clipboard"))
                Button(role: .destructive) { confirmingClear = true } label: {
                    Text("Effacer l'historique", tableName: "Clipboard")
                }
                .disabled(module.history.items.isEmpty)
            } header: {
                Text("Historique", tableName: "Clipboard")
            }
            Section {
                ForEach(module.excludedApps, id: \.self) { id in
                    HStack(spacing: 8) {
                        appIcon(id)
                        Text(verbatim: ClipboardAppIcons.name(for: id))
                        Text(verbatim: id).font(.system(size: 11)).foregroundColor(.secondary).lineLimit(1)
                        Spacer(minLength: 0)
                        Button {
                            module.excludedApps.removeAll { $0 == id }
                        } label: {
                            Image(systemName: "minus.circle")
                        }
                        .buttonStyle(.borderless)
                        .help(L("Ne plus ignorer cette app", table: "Clipboard"))
                    }
                }
                HStack {
                    Button(action: chooseApp) { Text("Ajouter une app…", tableName: "Clipboard") }
                    Button(action: module.resetExcludedApps) { Text("Rétablir la liste par défaut", tableName: "Clipboard") }
                }
            } header: {
                Text("Apps ignorées", tableName: "Clipboard")
            } footer: {
                SettingsNote(L("Jamais enregistrés : ce que les gestionnaires de mots de passe marquent comme "
                    + "confidentiel ou temporaire, et tout ce qui est copié depuis une app de cette liste.",
                               table: "Clipboard"))
            }
        }
        .confirmationDialog(Text("Effacer l'historique ?", tableName: "Clipboard"), isPresented: $confirmingClear,
                            titleVisibility: .visible) {
            Button(role: .destructive) { module.clearHistory() } label: { Text("Effacer", tableName: "Clipboard") }
        } message: {
            Text("Tout est supprimé, y compris les éléments épinglés.", tableName: "Clipboard")
        }
    }

    @ViewBuilder
    private func appIcon(_ id: String) -> some View {
        if let icon = ClipboardAppIcons.icon(for: id) {
            Image(nsImage: icon).resizable().frame(width: 16, height: 16)
        } else {
            Image(systemName: "app.dashed").frame(width: 16, height: 16).foregroundColor(.secondary)
        }
    }

    private func chooseApp() {
        let panel = NSOpenPanel()
        panel.allowedContentTypes = [.application]
        panel.directoryURL = URL(fileURLWithPath: "/Applications")
        panel.allowsMultipleSelection = false
        panel.canChooseDirectories = false
        panel.message = L("Choisis l'app dont les copies ne doivent pas être enregistrées.", table: "Clipboard")
        guard panel.runModal() == .OK, let url = panel.url, let id = Bundle(url: url)?.bundleIdentifier else { return }
        module.exclude(id)
    }
}
