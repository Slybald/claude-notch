import SwiftUI

// Idée « Agenda vivant » : la prochaine réunion devient un intercalaire qui se rapproche, avec un bouton Rejoindre.

private struct Event: Identifiable {
    var id = UUID()
    var time: String
    var title: String
    var place: String
    var tint: Color
    var past = false
}

private struct EventRow: View {
    var event: Event

    var body: some View {
        HStack(spacing: 10) {
            Text(verbatim: event.time).font(.system(size: 12, weight: .medium).monospacedDigit())
                .foregroundColor(Palette.secondary).frame(width: 40, alignment: .trailing)
            Capsule().fill(event.tint).frame(width: 3, height: 26)
            VStack(alignment: .leading, spacing: 1) {
                Text(verbatim: event.title).font(.system(size: 13, weight: .semibold)).foregroundColor(.white)
                Text(verbatim: event.place).font(.system(size: 11.5)).foregroundColor(Palette.secondary)
            }
            Spacer()
        }
        .opacity(event.past ? 0.4 : 1)
    }
}

private struct NextCard: View {
    var body: some View {
        VStack(alignment: .leading, spacing: 10) {
            HStack(alignment: .firstTextBaseline) {
                Text(verbatim: "Prochain").font(.system(size: 11, weight: .bold)).foregroundColor(Palette.amber)
                Spacer()
                Text(verbatim: "dans 4 min").font(.system(size: 12, weight: .semibold).monospacedDigit()).foregroundColor(Palette.amber)
            }
            Text(verbatim: "Point produit").font(.system(size: 18, weight: .bold)).foregroundColor(.white)
            HStack(spacing: 8) {
                Label { Text(verbatim: "10:30 – 11:00").font(.system(size: 12.5)) } icon: { Image(systemName: "clock") }
                Label { Text(verbatim: "Visioconférence").font(.system(size: 12.5)) } icon: { Image(systemName: "video") }
            }
            .foregroundColor(Palette.secondary).labelStyle(.titleAndIcon)
            HStack(spacing: 8) {
                HStack(spacing: 6) {
                    Image(systemName: "video.fill").font(.system(size: 12, weight: .bold))
                    Text(verbatim: "Rejoindre").font(.system(size: 13.5, weight: .bold))
                    Keycap(text: "⏎", dark: true)
                }
                .foregroundColor(Color.black.opacity(0.85)).padding(.horizontal, 14).frame(height: 32)
                .background(Capsule().fill(Palette.accent))
                Text(verbatim: "Ouvre le lien du rendez-vous").font(.system(size: 11.5)).foregroundColor(Palette.secondary)
                Spacer()
                Text(verbatim: "Voir dans Calendrier").font(.system(size: 11.5, weight: .medium)).foregroundColor(Palette.secondary)
            }
        }
        .padding(14)
        .background(card().fill(Palette.card))
        .overlay(card().stroke(Palette.amber.opacity(0.7), lineWidth: 1))
    }
}

private struct DayBar: View {
    var body: some View {
        HStack(spacing: 6) {
            ForEach(["lun 19", "mar 20", "mer 21", "jeu 22", "ven 23"].indices, id: \.self) { i in
                let label = ["lun 19", "mar 20", "mer 21", "jeu 22", "ven 23"][i]
                Text(verbatim: label).font(.system(size: 11.5, weight: i == 2 ? .bold : .medium))
                    .foregroundColor(i == 2 ? .white : Palette.secondary)
                    .padding(.horizontal, 10).frame(height: 24)
                    .background(Capsule().fill(i == 2 ? Color.white.opacity(0.14) : .clear))
            }
            Spacer()
        }
    }
}

@MainActor private func expanded() -> some View {
    let events = [
        Event(time: "09:00", title: "Cours : Algorithmique", place: "Amphi 3", tint: Palette.blue, past: true),
        Event(time: "11:30", title: "Revue de code", place: "Salle B", tint: Palette.green),
        Event(time: "14:00", title: "Atelier maquettes", place: "Studio", tint: Palette.accent),
        Event(time: "18:30", title: "Yoga", place: "Club", tint: Palette.amber),
    ]
    return ExpandedMock(header: {
        headerRow(tabs: [TabSpec(symbol: "", glyph: "✻"), TabSpec(symbol: "play.circle"),
                         TabSpec(symbol: "calendar", active: true), TabSpec(symbol: "timer"), TabSpec(symbol: "note.text")],
                  title: "Agenda", trailing: Pill(text: "Aujourd'hui"))
    }, content: {
        DayBar()
        NextCard()
        VStack(spacing: 8) { ForEach(events) { EventRow(event: $0) } }
            .padding(.horizontal, 6).padding(.top, 2)
    })
}

@MainActor private func collapsed(_ symbol: String, _ text: String, _ tint: Color) -> some View {
    ZStack(alignment: .top) {
        MenuBarStrip(width: 460)
        CollapsedMock(earWidth: 0, left: { EmptyView() }, right: { EmptyView() })
            .overlay(alignment: .topTrailing) {
                // Le bord gauche de l'intercalaire touche le bord droit de la notch, un peu rentré sous son coin.
                EarTabMock(symbol: symbol, text: text, tint: tint)
                    .alignmentGuide(.trailing) { $0[.leading] + 8 }
            }
    }
    .frame(width: 460, height: Metrics.notchHeight, alignment: .top)
}

@MainActor func agendaBoard() -> some View {
    Board(width: 1130, height: 470) {
        HStack(alignment: .top, spacing: 36) {
            VStack(spacing: 14) {
                expanded()
                Caption(number: "4", text: "Onglet Agenda : le prochain rendez-vous en grand, le reste de la journée dessous.", width: 540)
            }
            VStack(alignment: .leading, spacing: 44) {
                VStack(alignment: .leading, spacing: 10) {
                    collapsed("calendar", "14 min", Palette.secondary)
                    Caption(number: "1", text: "Loin : un intercalaire discret, le temps qui reste.", width: 460)
                }
                VStack(alignment: .leading, spacing: 10) {
                    collapsed("video.fill", "4 min", Palette.amber)
                    Caption(number: "2", text: "À 5 min : il passe à l'ambre. Un clic ouvre le lien de la réunion.", width: 460)
                }
                VStack(alignment: .leading, spacing: 10) {
                    collapsed("video.fill", "en cours", Palette.green)
                    Caption(number: "3", text: "Pendant la réunion : « en cours », et il disparaît à la fin.", width: 460)
                }
            }
            .padding(.top, 24)
        }
    }
}
