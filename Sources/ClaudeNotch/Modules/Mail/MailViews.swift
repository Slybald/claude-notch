import AppKit
import SwiftUI

// MARK: - Onglet

/// Les derniers messages non lus (expéditeur, objet, heure) ; un clic ouvre le message dans Mail. Chaque état où
/// Mail n'est pas lisible (fermé, pas autorisé, refusé, sans compte) dit quoi faire, avec le bon bouton.
struct MailPanel: View {
    @ObservedObject var module: MailModule

    var body: some View {
        Group {
            switch module.state {
            case .unknown:
                ModuleEmptyState(symbol: "envelope", title: L("Lecture de Mail…", table: "Mail"), progress: true)
                    .padding(.vertical, 22)
            case .notRunning:
                ModuleEmptyState(
                    symbol: "envelope", title: L("Mail n'est pas ouvert", table: "Mail"),
                    detail: L("Claude Notch ne lance jamais Mail tout seul. Ouvre-le pour voir tes messages non lus ici.", table: "Mail"),
                    action: ModuleAction(title: L("Ouvrir Mail", table: "Mail"), symbol: "arrow.up.forward.app", run: module.openMail))
                    .padding(.vertical, 12)
            case .needsPermission:
                ModuleEmptyState(
                    symbol: "lock", title: L("Autoriser l'accès à Mail", table: "Mail"),
                    detail: L("Claude Notch lit le nombre de messages non lus et les derniers expéditeurs avec AppleScript. macOS va te demander ton accord ; rien ne quitte ton Mac.", table: "Mail"),
                    action: ModuleAction(title: L("Autoriser", table: "Mail"), style: .prominent, run: module.authorize))
                    .padding(.vertical, 8)
            case .denied:
                ModuleEmptyState(
                    symbol: "lock.slash", tint: Palette.amber, title: L("Accès à Mail refusé", table: "Mail"),
                    detail: L("Autorise Claude Notch à contrôler Mail dans Réglages Système › Confidentialité et sécurité › Automatisation.", table: "Mail"),
                    action: ModuleAction(title: L("Ouvrir les Réglages", table: "Mail"), symbol: "gearshape", style: .prominent) {
                        module.openPrivacy(.automation)
                    })
                    .padding(.vertical, 8)
            case .noAccount:
                ModuleEmptyState(
                    symbol: "envelope.badge.shield.half.filled", title: L("Aucun compte dans Mail", table: "Mail"),
                    detail: L("Ajoute un compte (iCloud, Gmail, Outlook…) dans Mail, puis reviens ici.", table: "Mail"),
                    action: ModuleAction(title: L("Ouvrir Mail", table: "Mail"), symbol: "arrow.up.forward.app", run: module.openMail))
                    .padding(.vertical, 12)
            case .failed:
                ModuleEmptyState(
                    symbol: "exclamationmark.triangle", tint: Palette.amber, title: L("Mail ne répond pas", table: "Mail"),
                    detail: L("Il est peut-être occupé. Réessaie dans un instant.", table: "Mail"),
                    action: ModuleAction(title: L("Réessayer", table: "Mail")) { module.refresh() })
                    .padding(.vertical, 12)
            case .ready:
                ready
            }
        }
        .onAppear { module.tabAppeared() }
        .onDisappear { module.tabDisappeared() }
    }

    @ViewBuilder private var ready: some View {
        if module.unread == 0 {
            ModuleEmptyState(symbol: "checkmark.circle", title: L("Tout est lu", table: "Mail"),
                             detail: L("Aucun message non lu dans la boîte de réception.", table: "Mail"))
                .padding(.vertical, 18)
        } else if !module.showSubjects || module.messages.isEmpty {
            // Texte coupé, ou liste pas encore lue : le nombre suffit.
            ModuleEmptyState(symbol: "envelope.badge", title: Self.unreadText(module.unread),
                             action: ModuleAction(title: L("Ouvrir Mail", table: "Mail"), symbol: "arrow.up.forward.app", run: module.openMail))
                .padding(.vertical, 14)
        } else {
            VStack(spacing: 6) {
                // Relu chaque minute : « il y a 3 min » reste juste tant que le panneau est ouvert.
                TimelineView(.everyMinute) { context in
                    VStack(spacing: 3) {
                        ForEach(module.messages) { message in
                            MailRow(message: message, now: context.date) { module.openMessage(message) }
                        }
                    }
                }
                if module.unread > module.messages.count {
                    Text(verbatim: String(format: L("et %d autres non lus", table: "Mail"), module.unread - module.messages.count))
                        .font(.system(size: 10.5))
                        .foregroundColor(Palette.secondary)
                }
            }
        }
    }

    static func unreadText(_ count: Int) -> String {
        String(format: L(count, one: "%d message non lu", other: "%d messages non lus", table: "Mail"), count)
    }
}

// MARK: - Ligne

private struct MailRow: View {
    let message: MailMessage
    let now: Date
    let open: () -> Void

    @State private var hovering = false

    var body: some View {
        Button(action: open) {
            VStack(alignment: .leading, spacing: 1) {
                HStack(spacing: 6) {
                    Circle().fill(Palette.accent).frame(width: 7, height: 7)
                    Text(verbatim: message.sender)
                        .font(.system(size: 12.5, weight: .semibold))
                        .foregroundColor(Palette.primary)
                        .lineLimit(1)
                    Spacer(minLength: 6)
                    Text(verbatim: NotesFormat.relative(message.date, now: now))
                        .font(.system(size: 10.5))
                        .foregroundColor(Palette.secondary)
                        .lineLimit(1)
                }
                Text(verbatim: message.subject.isEmpty ? L("(sans objet)", table: "Mail") : message.subject)
                    .font(.system(size: 11.5))
                    .foregroundColor(Palette.secondary)
                    .lineLimit(1)
                    .padding(.leading, 13)
            }
            .padding(.horizontal, 8)
            .padding(.vertical, 6)
            .frame(maxWidth: .infinity, alignment: .leading)
            .background(ModuleStyle.shape(ModuleStyle.rowRadius).fill(Color.white.opacity(hovering ? 0.1 : 0.05)))
            .contentShape(ModuleStyle.shape(ModuleStyle.rowRadius))
        }
        .buttonStyle(.plain)
        .onHover { hovering = $0 }
        .animation(ModuleStyle.hover, value: hovering)
    }
}

// MARK: - En-tête, compact

/// À droite des onglets : relire Mail à la demande (la lecture automatique est lente à dessein).
struct MailRefreshButton: View {
    @ObservedObject var module: MailModule

    var body: some View {
        ModuleIconButton(symbol: "arrow.clockwise", label: L("Actualiser", table: "Mail")) { module.refresh() }
    }
}

/// Une ligne : le nombre de non-lus et l'expéditeur du plus récent (jamais l'objet : l'écran compact reste visible
/// en plein écran, en partage d'écran…).
struct MailCompactView: View {
    @ObservedObject var module: MailModule

    var body: some View {
        ModuleSummaryRow {
            ModuleSummaryIcon(symbol: "envelope.fill")
            Text(verbatim: MailPanel.unreadText(module.unread))
                .font(.system(size: 11.5, weight: .semibold))
                .foregroundColor(Palette.primary)
                .lineLimit(1)
            Spacer(minLength: 4)
            if module.showSubjects, let latest = module.messages.first {
                Text(verbatim: latest.sender)
                    .font(.system(size: 11))
                    .foregroundColor(Palette.secondary)
                    .lineLimit(1)
            }
        }
    }
}

// MARK: - Réglages

/// Réglages › Mail : pastille, objets, état de l'autorisation.
struct MailSettingsView: View {
    @ObservedObject var module: MailModule

    var body: some View {
        SettingsPane {
            Section {
                Toggle(isOn: $module.showBadge) {
                    Text("Pastille de non-lus dans la notch repliée", tableName: "Mail")
                }
                Toggle(isOn: $module.showSubjects) {
                    Text("Afficher les expéditeurs et les objets", tableName: "Mail")
                }
            } header: {
                Text("Mail", tableName: "Mail")
            } footer: {
                SettingsNote(L("Apple Mail seulement. Claude Notch ne lance jamais Mail, ne relit les compteurs que tant que Mail est ouvert, et n'enregistre ni n'envoie rien ailleurs. Gmail et Outlook ne sont pas lus directement : ajoute-les à Mail.", table: "Mail"))
            }
            Section {
                LabeledContent {
                    HStack(spacing: 8) {
                        Text(verbatim: Self.status(module.state)).foregroundColor(.secondary)
                        switch module.state {
                        case .needsPermission:
                            Button { module.authorize() } label: { Text("Autoriser", tableName: "Mail") }
                        case .denied:
                            Button { module.openPrivacy(.automation) } label: { Text("Ouvrir les Réglages", tableName: "Mail") }
                        default:
                            EmptyView()
                        }
                    }
                } label: {
                    Text("Accès à Mail (Automatisation)", tableName: "Mail")
                }
            } header: {
                Text("Autorisations", tableName: "Mail")
            }
        }
    }

    static func status(_ state: MailState) -> String {
        switch state {
        case .unknown: return L("Pas encore vérifié : ouvre l'onglet.", table: "Mail")
        case .notRunning: return L("Mail est fermé", table: "Mail")
        case .needsPermission: return L("Pas demandé", table: "Mail")
        case .denied: return L("Refusé", table: "Mail")
        case .noAccount: return L("Aucun compte dans Mail", table: "Mail")
        case .ready: return L("Autorisé", table: "Mail")
        case .failed: return L("Mail ne répond pas", table: "Mail")
        }
    }
}
