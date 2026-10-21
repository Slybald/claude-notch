import AppKit
import SwiftUI

// Éléments de style repris de l'app (Palette, NotchShape, ModuleStyle) : de quoi dessiner une maquette fidèle
// sans importer la cible exécutable. Les valeurs viennent de Sources/ClaudeNotch/NotchViews.swift et ModuleKit.swift.

enum Palette {
    static let claudeOrange = Color(red: 0xD9 / 255, green: 0x77 / 255, blue: 0x57 / 255)
    static let accent = claudeOrange
    static let amber = Color(red: 0xF5 / 255, green: 0xB8 / 255, blue: 0x3D / 255)
    static let green = Color(red: 0x4A / 255, green: 0xDE / 255, blue: 0x80 / 255)
    static let red = Color(red: 0xF8 / 255, green: 0x71 / 255, blue: 0x71 / 255)
    static let blue = Color(red: 0x4C / 255, green: 0x8D / 255, blue: 0xFF / 255)
    static let secondary = Color.white.opacity(0.6)
    static let card = Color.white.opacity(0.05)
    /// Fond de la planche : le gris clair des captures du README.
    static let board = Color(red: 0xD9 / 255, green: 0xD9 / 255, blue: 0xD9 / 255)
}

/// Bas arrondi et petits évasements concaves en haut, pour se fondre dans la vraie notch.
struct NotchShape: Shape {
    var topRadius: CGFloat
    var bottomRadius: CGFloat

    func path(in rect: CGRect) -> Path {
        let top = max(0, min(topRadius, rect.width / 4, rect.height / 2))
        let bottom = max(0, min(bottomRadius, (rect.width - 2 * top) / 2, rect.height - top))
        var path = Path()
        path.move(to: CGPoint(x: rect.minX, y: rect.minY))
        path.addQuadCurve(to: CGPoint(x: rect.minX + top, y: rect.minY + top),
                          control: CGPoint(x: rect.minX + top, y: rect.minY))
        path.addLine(to: CGPoint(x: rect.minX + top, y: rect.maxY - bottom))
        path.addQuadCurve(to: CGPoint(x: rect.minX + top + bottom, y: rect.maxY),
                          control: CGPoint(x: rect.minX + top, y: rect.maxY))
        path.addLine(to: CGPoint(x: rect.maxX - top - bottom, y: rect.maxY))
        path.addQuadCurve(to: CGPoint(x: rect.maxX - top, y: rect.maxY - bottom),
                          control: CGPoint(x: rect.maxX - top, y: rect.maxY))
        path.addLine(to: CGPoint(x: rect.maxX - top, y: rect.minY + top))
        path.addQuadCurve(to: CGPoint(x: rect.maxX, y: rect.minY),
                          control: CGPoint(x: rect.maxX - top, y: rect.minY))
        path.closeSubpath()
        return path
    }
}

enum Metrics {
    /// Hauteur de la bande de la barre des menus (la notch physique).
    static let notchHeight: CGFloat = 32
    static let notchWidth: CGFloat = 190
    /// Largeur « standard » du panneau déplié, plus les évasements du haut (12 pt de chaque côté).
    static let panelWidth: CGFloat = 540
    static let cardRadius: CGFloat = 12
    static let itemRadius: CGFloat = 8
}

func card(_ radius: CGFloat = Metrics.cardRadius) -> RoundedRectangle {
    RoundedRectangle(cornerRadius: radius, style: .continuous)
}

// MARK: - Panneau déplié

struct TabSpec: Identifiable {
    var id: String { symbol + (glyph ?? "") }
    var symbol: String
    var glyph: String? = nil
    var active = false
}

/// Icônes d'onglets de la barre : capsule claire sous l'onglet actif, titre à côté.
struct TabBarMock: View {
    var tabs: [TabSpec]

    var body: some View {
        HStack(spacing: 2) {
            ForEach(tabs) { tab in
                Group {
                    if let glyph = tab.glyph {
                        Text(verbatim: glyph).font(.system(size: 13, weight: .bold)).foregroundColor(Palette.accent)
                    } else {
                        Image(systemName: tab.symbol).font(.system(size: 12, weight: .medium))
                            .foregroundColor(tab.active ? .white : Palette.secondary)
                    }
                }
                .frame(width: 17, height: 17)
                .padding(.horizontal, 5)
                .frame(height: 22)
                .background { if tab.active { Capsule().fill(Color.white.opacity(0.12)) } }
            }
        }
    }
}

/// Panneau déplié : bande de la notch vide, ligne d'onglets, contenu.
struct ExpandedMock<Header: View, Content: View>: View {
    var width: CGFloat = Metrics.panelWidth
    var headerHeight: CGFloat = 24
    @ViewBuilder var header: Header
    @ViewBuilder var content: Content

    var body: some View {
        VStack(alignment: .leading, spacing: 10) {
            Color.clear.frame(height: Metrics.notchHeight)
            header.frame(height: headerHeight)
            content
        }
        .padding(.horizontal, 14)
        .padding(.bottom, 14)
        .frame(width: width, alignment: .top)
        .padding(.horizontal, 12)
        .background(Color.black)
        .clipShape(NotchShape(topRadius: 12, bottomRadius: 24))
        .shadow(color: .black.opacity(0.28), radius: 14, y: 6)
        .environment(\.colorScheme, .dark)
    }
}

func headerRow(tabs: [TabSpec], title: String, trailing: some View) -> some View {
    HStack(spacing: 8) {
        TabBarMock(tabs: tabs)
        Text(verbatim: title).font(.system(size: 15, weight: .semibold)).foregroundColor(.white)
        Spacer(minLength: 8)
        trailing
    }
}

struct Pill: View {
    var text: String
    var dot: Color? = nil
    var tint: Color = .white

    var body: some View {
        HStack(spacing: 5) {
            Text(verbatim: text).font(.system(size: 12, weight: .semibold))
            if let dot { Circle().fill(dot).frame(width: 6, height: 6) }
        }
        .foregroundColor(tint.opacity(0.9))
        .padding(.horizontal, 9)
        .frame(height: 24)
        .background(Capsule().fill(Color.white.opacity(0.1)))
    }
}

/// Touche de clavier : rappelle le raccourci à côté d'une action.
struct Keycap: View {
    var text: String
    var dark = false

    var body: some View {
        Text(verbatim: text)
            .font(.system(size: 11, weight: .semibold, design: .rounded))
            .foregroundColor(dark ? Color.black.opacity(0.7) : Color.white.opacity(0.75))
            .padding(.horizontal, 6)
            .frame(minWidth: 20, minHeight: 18)
            .background(RoundedRectangle(cornerRadius: 5, style: .continuous)
                .fill(dark ? Color.black.opacity(0.14) : Color.white.opacity(0.12)))
    }
}

// MARK: - Notch repliée

/// Notch repliée : le noir de la vraie notch, des oreilles de chaque côté (facultatives).
struct CollapsedMock<Left: View, Right: View>: View {
    var earWidth: CGFloat = 0
    @ViewBuilder var left: Left
    @ViewBuilder var right: Right

    var body: some View {
        HStack(spacing: 0) {
            left.frame(width: earWidth, alignment: .center)
            Color.clear.frame(width: Metrics.notchWidth)
            right.frame(width: earWidth, alignment: .center)
        }
        .frame(height: Metrics.notchHeight)
        .padding(.horizontal, 6)
        .background(Color.black)
        .clipShape(NotchShape(topRadius: 6, bottomRadius: earWidth > 0 ? 12 : 9))
    }
}

/// Intercalaire : petit onglet d'activité accolé à la notch, avec son liseré de couleur.
struct EarTabMock: View {
    var symbol: String
    var text: String
    var tint: Color
    var height: CGFloat = 28

    var body: some View {
        HStack(spacing: 5) {
            Image(systemName: symbol).font(.system(size: 12, weight: .semibold)).foregroundColor(tint)
            Text(verbatim: text).font(.system(size: 13, weight: .semibold).monospacedDigit())
                .foregroundColor(Color.white.opacity(0.9))
        }
        .padding(.horizontal, 12)
        .padding(.bottom, 3)
        .frame(height: height)
        .background(Color.black)
        .clipShape(NotchShape(topRadius: 0, bottomRadius: 9))
        .overlay(alignment: .bottom) {
            Capsule().fill(tint).frame(height: 2).padding(.horizontal, 8).padding(.bottom, 4)
        }
        .fixedSize()
    }
}

// MARK: - Planche

/// Fond gris, un titre discret et une légende sous chaque maquette.
struct Board<Content: View>: View {
    var width: CGFloat
    var height: CGFloat
    @ViewBuilder var content: Content

    var body: some View {
        content
            .frame(width: width, height: height, alignment: .top)
            .background(Palette.board)
    }
}

struct Caption: View {
    var number: String
    var text: String
    var width: CGFloat = 360

    var body: some View {
        HStack(alignment: .firstTextBaseline, spacing: 8) {
            Text(verbatim: number)
                .font(.system(size: 11, weight: .bold)).foregroundColor(.white)
                .frame(width: 18, height: 18).background(Circle().fill(Color.black.opacity(0.75)))
            Text(verbatim: text).font(.system(size: 13)).foregroundColor(Color.black.opacity(0.72))
                .fixedSize(horizontal: false, vertical: true)
        }
        .frame(width: width, alignment: .leading)
    }
}

/// Bande de la barre des menus, derrière une notch repliée : situe la maquette sur l'écran.
struct MenuBarStrip: View {
    var width: CGFloat

    var body: some View {
        Rectangle().fill(Color.white.opacity(0.42)).frame(width: width, height: Metrics.notchHeight)
    }
}
