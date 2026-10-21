import SwiftUI

// Idée « Barre de commande » : un champ dans la notch, ouvert par un raccourci, qui lance une action de n'importe
// quel onglet sans avoir à le chercher.

private struct Row: Identifiable {
    var id = UUID()
    var symbol: String
    var title: String
    var detail: String
    var tint: Color = Palette.accent
    var hint: String? = nil
    var selected = false
}

private struct CommandRow: View {
    var row: Row

    var body: some View {
        HStack(spacing: 10) {
            Image(systemName: row.symbol).font(.system(size: 13, weight: .semibold))
                .foregroundColor(row.tint).frame(width: 26, height: 26)
                .background(card(7).fill(row.tint.opacity(0.16)))
            VStack(alignment: .leading, spacing: 1) {
                Text(verbatim: row.title).font(.system(size: 13.5, weight: .semibold)).foregroundColor(.white)
                Text(verbatim: row.detail).font(.system(size: 11.5)).foregroundColor(Palette.secondary).lineLimit(1)
            }
            Spacer(minLength: 6)
            if let hint = row.hint { Keycap(text: hint) }
        }
        .padding(.horizontal, 8).frame(height: 40)
        .background(card(Metrics.itemRadius).fill(row.selected ? Palette.accent.opacity(0.16) : .clear))
        .overlay(card(Metrics.itemRadius).stroke(row.selected ? Palette.accent.opacity(0.5) : .clear, lineWidth: 1))
    }
}

private struct Field: View {
    var prefix: String? = nil
    var text: String
    var placeholder: String? = nil

    var body: some View {
        HStack(spacing: 8) {
            Image(systemName: "chevron.right.circle.fill").font(.system(size: 15)).foregroundColor(Palette.accent)
            if let prefix {
                Text(verbatim: prefix).font(.system(size: 13, weight: .bold, design: .monospaced))
                    .foregroundColor(Palette.accent)
                    .padding(.horizontal, 6).frame(height: 20).background(Capsule().fill(Palette.accent.opacity(0.18)))
            }
            HStack(spacing: 1) {
                if text.isEmpty, let placeholder {
                    Text(verbatim: placeholder).font(.system(size: 15)).foregroundColor(Palette.secondary.opacity(0.7))
                } else {
                    Text(verbatim: text).font(.system(size: 15, weight: .medium)).foregroundColor(.white)
                }
                Rectangle().fill(Palette.accent).frame(width: 1.5, height: 17)
            }
            Spacer(minLength: 6)
            Keycap(text: "esc")
        }
        .padding(.horizontal, 12).frame(height: 40)
        .background(card(10).fill(Color.white.opacity(0.08)))
    }
}

private struct PrefixChips: View {
    var items: [(String, String)]

    var body: some View {
        HStack(spacing: 6) {
            ForEach(items.indices, id: \.self) { i in
                HStack(spacing: 4) {
                    Text(verbatim: items[i].0).font(.system(size: 11, weight: .bold, design: .monospaced))
                        .foregroundColor(Palette.accent)
                    Text(verbatim: items[i].1).font(.system(size: 11)).foregroundColor(Palette.secondary)
                }
                .padding(.horizontal, 7).frame(height: 20).background(Capsule().fill(Color.white.opacity(0.07)))
            }
        }
    }
}

private func panel(field: Field, rows: [Row], chips: [(String, String)], footer: String) -> some View {
    ExpandedMock(headerHeight: 40, header: { field }, content: {
        VStack(spacing: 2) { ForEach(rows) { CommandRow(row: $0) } }
        PrefixChips(items: chips)
        HStack(spacing: 14) {
            Text(verbatim: footer).font(.system(size: 11)).foregroundColor(Palette.secondary.opacity(0.8))
            Spacer()
            HStack(spacing: 4) { Keycap(text: "↑↓"); Text(verbatim: "choisir").font(.system(size: 11)).foregroundColor(Palette.secondary) }
            HStack(spacing: 4) { Keycap(text: "⏎"); Text(verbatim: "lancer").font(.system(size: 11)).foregroundColor(Palette.secondary) }
        }
    })
}

@MainActor func commandeBoard() -> some View {
    let chips = [("t", "minuteur"), ("n", "note"), ("c", "copies"), ("s", "scène"), (">", "Claude")]
    let timer = panel(
        field: Field(prefix: "t", text: "25"),
        rows: [
            Row(symbol: "timer", title: "Minuteur de 25 min", detail: "Se lance tout de suite, sonne à 14:32", hint: "⏎", selected: true),
            Row(symbol: "arrow.triangle.2.circlepath", title: "Pomodoro 25 / 5", detail: "4 cycles, pause longue de 15 min", tint: Palette.green),
            Row(symbol: "moon.fill", title: "Séance de concentration", detail: "Minuteur + Ne pas déranger + Mac éveillé", tint: Palette.blue),
        ],
        chips: chips, footer: "⌃Espace ouvre la barre")
    let claude = panel(
        field: Field(prefix: ">", text: "relance les tests du parseur"),
        rows: [
            Row(symbol: "sparkle", title: "Envoyer à « mon-app »", detail: "Claude · session en cours, lit le message après l'action", hint: "⏎", selected: true),
            Row(symbol: "sparkle", title: "Envoyer à « api »", detail: "Claude · attend ta permission", tint: Palette.amber),
            Row(symbol: "arrow.up.forward.app", title: "Ouvrir « mon-app »", detail: "Met le terminal de la session au premier plan", tint: Palette.secondary),
        ],
        chips: chips, footer: "Rien n'est envoyé sans ⏎")
    return Board(width: 1230, height: 345) {
        VStack(spacing: 14) {
            HStack(alignment: .top, spacing: 30) {
                VStack(spacing: 14) { timer; Caption(number: "1", text: "« t 25 » lance un minuteur : une frappe, un ⏎.", width: 500) }
                VStack(spacing: 14) { claude; Caption(number: "2", text: "« > » parle à une session Claude sans ouvrir son onglet.", width: 500) }
            }
        }
        .padding(.top, 0)
    }
}
