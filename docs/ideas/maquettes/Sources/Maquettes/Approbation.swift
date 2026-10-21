import SwiftUI

// Idée « Approuver au clavier » : la notch s'ouvre en tiroir sur la demande en attente (Claude ou Codex), avec les
// raccourcis pour l'accepter ou la refuser sans ouvrir le panneau ni changer d'onglet.

private struct Action: View {
    var title: String
    var keys: String
    var primary = false

    var body: some View {
        HStack(spacing: 7) {
            Text(verbatim: title).font(.system(size: 13, weight: .bold))
            Keycap(text: keys, dark: primary)
        }
        .foregroundColor(primary ? Color.black.opacity(0.85) : .white)
        .padding(.horizontal, 12).frame(height: 30)
        .background(Capsule().fill(primary ? Palette.accent : Color.white.opacity(0.12)))
        .fixedSize()
    }
}

private struct QueueDots: View {
    var total: Int
    var current: Int

    var body: some View {
        HStack(spacing: 4) {
            ForEach(0..<total, id: \.self) { i in
                Circle().fill(i == current ? Palette.amber : Color.white.opacity(0.25)).frame(width: 6, height: 6)
            }
            Text(verbatim: "\(current + 1) sur \(total)").font(.system(size: 11, weight: .medium).monospacedDigit())
                .foregroundColor(Palette.secondary).padding(.leading, 3)
        }
    }
}

/// La demande, dans la carte à liseré ambre que l'onglet Claude utilise déjà pour « attend ta permission ».
private struct RequestCard: View {
    var body: some View {
        VStack(alignment: .leading, spacing: 9) {
            HStack(spacing: 8) {
                Text(verbatim: "✻").font(.system(size: 13, weight: .bold)).foregroundColor(Palette.accent)
                Text(verbatim: "api").font(.system(size: 14, weight: .bold)).foregroundColor(.white)
                Text(verbatim: "iTerm2").font(.system(size: 11, weight: .semibold)).foregroundColor(Palette.secondary)
                    .padding(.horizontal, 7).frame(height: 18).background(Capsule().fill(Color.white.opacity(0.1)))
                Spacer()
                QueueDots(total: 3, current: 0)
            }
            Text(verbatim: "Attend ta permission").font(.system(size: 12, weight: .bold)).foregroundColor(Palette.amber)
            Text(verbatim: "Terminal · rm -rf build")
                .font(.system(size: 13, weight: .medium, design: .monospaced)).foregroundColor(.white)
                .padding(.horizontal, 10).frame(maxWidth: .infinity, minHeight: 30, alignment: .leading)
                .background(card(8).fill(Color.white.opacity(0.07)))
            HStack(spacing: 8) {
                Action(title: "Autoriser", keys: "⌃⌥Y", primary: true)
                Action(title: "Refuser", keys: "⌃⌥N")
                Spacer(minLength: 0)
            }
        }
        .padding(12)
        .background(card().fill(Palette.card))
        .overlay(card().stroke(Palette.amber.opacity(0.8), lineWidth: 1))
    }
}

/// Tiroir : la forme du panneau déplié, avec les oreilles dans la bande de la notch.
private struct DrawerMock<Left: View, Right: View, Content: View>: View {
    var width: CGFloat = 440
    @ViewBuilder var left: Left
    @ViewBuilder var right: Right
    @ViewBuilder var content: Content

    var body: some View {
        VStack(alignment: .leading, spacing: 10) {
            HStack(spacing: 0) {
                left.frame(width: 56)
                Spacer(minLength: 0)
                Color.clear.frame(width: Metrics.notchWidth)
                Spacer(minLength: 0)
                right.frame(width: 56)
            }
            .frame(height: Metrics.notchHeight)
            content
        }
        .padding(.horizontal, 14).padding(.bottom, 14)
        .frame(width: width, alignment: .top)
        .padding(.horizontal, 12)
        .background(Color.black)
        .clipShape(NotchShape(topRadius: 12, bottomRadius: 24))
        .shadow(color: .black.opacity(0.28), radius: 14, y: 6)
        .environment(\.colorScheme, .dark)
    }
}

@MainActor func approbationBoard() -> some View {
    let hand = Image(systemName: "hand.raised.fill").font(.system(size: 15)).foregroundColor(Palette.amber)
    let count = Text(verbatim: "3").font(.system(size: 14, weight: .bold)).foregroundColor(Palette.amber)
    let check = Image(systemName: "checkmark.circle.fill").font(.system(size: 15)).foregroundColor(Palette.green)
    let two = Text(verbatim: "2").font(.system(size: 14, weight: .bold)).foregroundColor(Palette.amber)
    return Board(width: 1130, height: 310) {
        HStack(alignment: .top, spacing: 40) {
            VStack(spacing: 14) {
                DrawerMock(left: { hand }, right: { count }, content: {
                    RequestCard()
                    HStack(spacing: 6) {
                        Image(systemName: "chevron.left.forwardslash.chevron.right").font(.system(size: 10))
                        Text(verbatim: "Ensuite : Codex · patch sur 2 fichiers, puis mon-app · git push").font(.system(size: 11))
                    }
                    .foregroundColor(Palette.secondary.opacity(0.9)).padding(.horizontal, 4)
                })
                Caption(number: "1", text: "Une demande arrive : la notch s'ouvre en tiroir, sans prendre le focus ni changer d'onglet. Une seule fois, jamais « toujours autoriser ».", width: 440)
            }
            VStack(spacing: 14) {
                CollapsedMock(earWidth: 56, left: { check }, right: { two })
                Caption(number: "2", text: "⌃⌥Y : le tiroir se replie sur « autorisé » et passe à la demande suivante. Rien ne part si le tiroir est visible depuis moins d'une seconde.", width: 440)
            }
        }
    }
}
