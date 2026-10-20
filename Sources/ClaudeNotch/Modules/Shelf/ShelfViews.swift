import AppKit
import SwiftUI

// MARK: - Onglet

/// Grille de vignettes (icône tout de suite, vignette Quick Look ensuite), zone « Déposer ici » pendant un
/// glisser, état vide, et le bandeau « Annuler » ou le message du moment.
struct ShelfPanel: View {
    @ObservedObject var module: ShelfModule
    @Environment(\.notchContentWidth) private var width
    @Environment(\.notchContentMaxHeight) private var maxHeight

    static let spacing: CGFloat = 8
    static let minTileWidth: CGFloat = 76
    static let tileHeight: CGFloat = 88
    static let bannerHeight: CGFloat = 32

    private var columns: Int { max(1, Int((width + Self.spacing) / (Self.minTileWidth + Self.spacing))) }
    private var tileWidth: CGFloat { (width - CGFloat(columns - 1) * Self.spacing) / CGFloat(columns) }
    private var hasBanner: Bool { module.undoItems != nil || module.notice != nil }

    /// Toutes les rangées tant qu'elles tiennent, sinon la grille défile.
    private var gridHeight: CGFloat {
        let rows = (module.items.count + columns - 1) / columns
        let full = CGFloat(rows) * Self.tileHeight + CGFloat(max(0, rows - 1)) * Self.spacing
        return min(full, maxHeight - (hasBanner ? Self.bannerHeight + Self.spacing : 0))
    }

    var body: some View {
        VStack(alignment: .leading, spacing: Self.spacing) {
            if module.items.isEmpty {
                ShelfEmptyZone(targeted: module.isDropTargeted)
            } else {
                grid
            }
            if module.undoItems != nil {
                ShelfBanner(symbol: "trash", text: L("Étagère vidée", table: "Shelf"), color: Palette.secondary,
                            action: (L("Annuler", table: "Shelf"), module.undoClear))
                    .transition(.opacity)
            } else if let notice = module.notice {
                ShelfBanner(symbol: "exclamationmark.triangle.fill", text: notice, color: Palette.amber, action: nil)
                    .transition(.opacity)
            }
        }
        .animation(notchSpring, value: module.isDropTargeted)
        .animation(notchSpring, value: module.items.map { $0.id })
        .animation(notchSpring, value: hasBanner)
        .onAppear(perform: module.viewAppeared)
        .onDisappear(perform: module.viewDisappeared)
    }

    private var grid: some View {
        ScrollView(.vertical) {
            LazyVGrid(columns: Array(repeating: GridItem(.fixed(tileWidth), spacing: Self.spacing), count: columns),
                      alignment: .leading, spacing: Self.spacing) {
                ForEach(module.items) { item in
                    ShelfTile(module: module, item: item, width: tileWidth)
                }
            }
            // Clic dans le vide : plus de sélection.
            .background(Color.black.opacity(0.001).onTapGesture(perform: module.clearSelection))
        }
        .frame(height: gridHeight)
        .overlay {
            if module.isDropTargeted { ShelfDropOverlay().transition(.opacity) }
        }
    }
}

/// Une vignette : image, nom tronqué au milieu ; sélection en couleur d'accent ; « retirer » au survol ;
/// grisée avec « Introuvable » quand le fichier a disparu.
struct ShelfTile: View {
    @ObservedObject var module: ShelfModule
    let item: ShelfItem
    let width: CGFloat

    private var selected: Bool { module.selection.contains(item.id) }
    private var hovered: Bool { module.hovered == item.id }
    private var missing: Bool { module.missing.contains(item.id) }

    var body: some View {
        ZStack(alignment: .topTrailing) {
            // Sous le dessin : reçoit clics, menu, survol et glisser (le dessin laisse passer la souris).
            ShelfItemInteraction(id: item.id, name: item.name, module: module)
            content.allowsHitTesting(false)
            if hovered { removeButton.transition(.opacity) }
        }
        .frame(width: width, height: ShelfPanel.tileHeight)
        .animation(.easeOut(duration: 0.12), value: hovered)
        .accessibilityElement(children: .ignore)
        .accessibilityLabel(Text(verbatim: missing ? item.name + ", " + L("Introuvable", table: "Shelf") : item.name))
        .accessibilityAddTraits(selected ? .isSelected : [])
        .accessibilityAction { module.open([item.id]) }
        .accessibilityAction(named: Text("Retirer de l'étagère", tableName: "Shelf")) { module.remove([item.id]) }
    }

    private var content: some View {
        VStack(spacing: 5) {
            Image(nsImage: module.image(for: item))
                .resizable()
                .aspectRatio(contentMode: .fit)
                .frame(width: 44, height: 44)
                .opacity(missing ? 0.35 : 1)
                .overlay(alignment: .bottom) {
                    if missing {
                        Text("Introuvable", tableName: "Shelf")
                            .font(.system(size: 8.5, weight: .bold))
                            .foregroundColor(.black.opacity(0.85))
                            .lineLimit(1)
                            .fixedSize()
                            .padding(.horizontal, 5)
                            .padding(.vertical, 1.5)
                            .background(Capsule().fill(Palette.amber))
                    }
                }
            // Deux lignes, coupé au milieu comme dans le Finder : l'extension reste visible.
            Text(verbatim: item.name)
                .font(.system(size: 10.5, weight: .medium))
                .foregroundColor(missing ? Palette.secondary : Palette.primary)
                .multilineTextAlignment(.center)
                .lineLimit(2)
                .truncationMode(.middle)
                .frame(height: 28, alignment: .top)
        }
        .padding(.horizontal, 6)
        .padding(.top, 4)
        .frame(width: width, height: ShelfPanel.tileHeight)
        .background(
            RoundedRectangle(cornerRadius: 10, style: .continuous)
                .fill(selected ? Palette.accent.opacity(0.22) : Color.white.opacity(hovered ? 0.07 : 0))
        )
        .overlay(
            RoundedRectangle(cornerRadius: 10, style: .continuous)
                .strokeBorder(Palette.accent.opacity(selected ? 0.7 : 0), lineWidth: 1)
        )
    }

    private var removeButton: some View {
        Button {
            module.remove([item.id])
        } label: {
            Image(systemName: "xmark")
                .font(.system(size: 7.5, weight: .bold))
                .foregroundColor(.white.opacity(0.9))
                .frame(width: 16, height: 16)
                .background(Circle().fill(Color(white: 0.28)))
                .contentShape(Circle())
        }
        .buttonStyle(.plain)
        .padding(4)
        .help(L("Retirer de l'étagère", table: "Shelf"))
        .accessibilityLabel(Text("Retirer de l'étagère", tableName: "Shelf"))
    }
}

/// Étagère vide : ce qu'il faut faire ; pendant un glisser, la zone de dépôt.
struct ShelfEmptyZone: View {
    let targeted: Bool

    var body: some View {
        VStack(spacing: 6) {
            Image(systemName: targeted ? "tray.and.arrow.down.fill" : "tray.and.arrow.down")
                .font(.system(size: 22, weight: .medium))
                .foregroundColor(Palette.accent)
                .frame(height: 28)
            if targeted {
                Text("Déposer ici", tableName: "Shelf")
                    .font(.system(size: 13, weight: .semibold))
                    .foregroundColor(Palette.primary)
            } else {
                Text("Glisse des fichiers sur la notch", tableName: "Shelf")
                    .font(.system(size: 13, weight: .semibold))
                    .foregroundColor(Palette.primary)
                Text("Ils restent ici, sous la main. Rien n'est copié : l'étagère garde un lien vers chaque fichier.",
                     tableName: "Shelf")
                    .font(.system(size: 11))
                    .foregroundColor(Palette.secondary)
                    .multilineTextAlignment(.center)
                    .fixedSize(horizontal: false, vertical: true)
            }
        }
        .padding(.horizontal, 16)
        .frame(maxWidth: .infinity, minHeight: 112)
        .background(
            RoundedRectangle(cornerRadius: 14, style: .continuous)
                .fill(targeted ? Palette.accent.opacity(0.14) : Palette.card)
        )
        .overlay(
            RoundedRectangle(cornerRadius: 14, style: .continuous)
                .strokeBorder(targeted ? Palette.accent : Color.white.opacity(0.14),
                              style: StrokeStyle(lineWidth: 1.5, dash: [5, 4]))
        )
    }
}

/// Par-dessus la grille pendant un glisser : la zone de dépôt, bien visible.
struct ShelfDropOverlay: View {
    var body: some View {
        ZStack {
            RoundedRectangle(cornerRadius: 14, style: .continuous).fill(Color.black.opacity(0.6))
            RoundedRectangle(cornerRadius: 14, style: .continuous).fill(Palette.accent.opacity(0.14))
            RoundedRectangle(cornerRadius: 14, style: .continuous)
                .strokeBorder(Palette.accent, style: StrokeStyle(lineWidth: 1.5, dash: [5, 4]))
            HStack(spacing: 6) {
                Image(systemName: "tray.and.arrow.down.fill")
                Text("Déposer ici", tableName: "Shelf")
            }
            .font(.system(size: 13, weight: .semibold))
            .foregroundColor(Palette.primary)
            .padding(.horizontal, 12)
            .padding(.vertical, 6)
            .background(Capsule().fill(Palette.accent.opacity(0.35)))
        }
        .allowsHitTesting(false)
    }
}

/// Bandeau sous la grille : « Étagère vidée · Annuler », ou un message.
struct ShelfBanner: View {
    let symbol: String
    let text: String
    let color: Color
    let action: (String, () -> Void)?

    var body: some View {
        HStack(spacing: 8) {
            Image(systemName: symbol)
                .font(.system(size: 11, weight: .semibold))
                .foregroundColor(color)
            Text(verbatim: text)
                .font(.system(size: 11.5, weight: .medium))
                .foregroundColor(Palette.primary)
                .lineLimit(1)
            Spacer(minLength: 4)
            if let action {
                Button(action: action.1) {
                    Text(verbatim: action.0)
                        .font(.system(size: 11.5, weight: .semibold))
                        .foregroundColor(Palette.accent)
                        .padding(.horizontal, 8)
                        .padding(.vertical, 3)
                        .background(Capsule().fill(Palette.accent.opacity(0.14)))
                        .contentShape(Capsule())
                }
                .buttonStyle(.plain)
            }
        }
        .padding(.horizontal, 10)
        .frame(height: ShelfPanel.bannerHeight)
        .background(RoundedRectangle(cornerRadius: 10, style: .continuous).fill(Palette.card))
    }
}

// MARK: - En-tête

/// À droite des onglets quand l'étagère est affichée : le compte (ou la sélection), AirDrop, tout vider.
struct ShelfHeaderAccessory: View {
    @ObservedObject var module: ShelfModule

    var body: some View {
        if !module.items.isEmpty {
            HStack(spacing: 2) {
                Text(verbatim: module.summary)
                    .font(.system(size: 10.5, weight: .medium))
                    .foregroundColor(Palette.secondary)
                    .lineLimit(1)
                    .fixedSize()
                    .padding(.trailing, 4)
                ShelfIconButton(symbol: "dot.radiowaves.left.and.right",
                                help: L("AirDrop : la sélection, ou toute l'étagère", table: "Shelf")) {
                    module.airDrop(module.selectedOrAll)
                }
                ShelfIconButton(symbol: "trash", help: L("Tout vider", table: "Shelf"), action: module.clearAll)
            }
        }
    }
}

struct ShelfIconButton: View {
    let symbol: String
    let help: String
    let action: () -> Void
    @State private var hovering = false

    var body: some View {
        Button(action: action) {
            Image(systemName: symbol)
                .font(.system(size: 11, weight: .semibold))
                .foregroundColor(.white.opacity(hovering ? 0.95 : 0.6))
                .frame(width: 22, height: 20)
                .background(RoundedRectangle(cornerRadius: 6, style: .continuous)
                    .fill(Color.white.opacity(hovering ? 0.1 : 0)))
                .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .onHover { hovering = $0 }
        .help(help)
        .accessibilityLabel(Text(verbatim: help))
    }
}

// MARK: - Plein écran compact

/// Le nombre d'éléments et les premières icônes ; « Déposer ici » pendant un glisser ; rien si l'étagère est vide.
struct ShelfCompactView: View {
    @ObservedObject var module: ShelfModule

    var body: some View {
        if module.isDropTargeted || !module.items.isEmpty {
            HStack(spacing: 8) {
                Image(systemName: module.isDropTargeted ? "tray.and.arrow.down.fill" : "tray.full")
                    .font(.system(size: 12, weight: .semibold))
                    .foregroundColor(Palette.accent)
                    .frame(width: 20)
                Text(verbatim: module.isDropTargeted ? L("Déposer ici", table: "Shelf") : module.summary)
                    .font(.system(size: 11.5, weight: .medium))
                    .foregroundColor(Palette.primary)
                    .lineLimit(1)
                Spacer(minLength: 4)
                HStack(spacing: -5) {
                    ForEach(module.items.prefix(4)) { item in
                        Image(nsImage: module.image(for: item))
                            .resizable()
                            .aspectRatio(contentMode: .fit)
                            .frame(width: 18, height: 18)
                    }
                }
            }
            .frame(minHeight: 22)
            .padding(.horizontal, 8)
            .padding(.vertical, 5)
            .background(
                RoundedRectangle(cornerRadius: 10, style: .continuous)
                    .fill(module.isDropTargeted ? Palette.accent.opacity(0.16) : Palette.card)
            )
            .overlay(
                RoundedRectangle(cornerRadius: 10, style: .continuous)
                    .strokeBorder(Palette.accent.opacity(module.isDropTargeted ? 1 : 0),
                                  style: StrokeStyle(lineWidth: 1.2, dash: [4, 3]))
            )
        }
    }
}

// MARK: - Réglages

/// Réglages › Étagère.
struct ShelfSettingsView: View {
    @ObservedObject var module: ShelfModule

    var body: some View {
        SettingsPane {
            Section {
                Toggle(isOn: $module.removeAfterDrag) {
                    Text("Retirer un élément glissé vers une autre app", tableName: "Shelf")
                }
                Toggle(isOn: $module.clearOnQuit) {
                    Text("Vider l'étagère en quittant", tableName: "Shelf")
                }
                Picker(selection: $module.limit) {
                    ForEach(ShelfModule.limitChoices, id: \.self) { Text(verbatim: "\($0)").tag($0) }
                } label: {
                    Text("Nombre maximal d'éléments", tableName: "Shelf")
                }
            } header: {
                Text("Étagère", tableName: "Shelf")
            } footer: {
                SettingsNote(L("Glisse des fichiers ou des dossiers sur la notch, même repliée. L'étagère garde un "
                    + "lien vers chaque fichier (rien n'est copié) et le retrouve s'il est déplacé. Sans « Vider "
                    + "l'étagère en quittant », la liste est gardée d'un lancement à l'autre.", table: "Shelf"))
            }
        }
    }
}
