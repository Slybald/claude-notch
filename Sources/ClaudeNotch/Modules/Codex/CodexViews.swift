import SwiftUI

// Vues du module Codex : onglet (cartes de session, approbation), mode compact plein écran, réglages.
// Même gabarit que l'onglet Claude (`SessionCard`, `ModuleKit`) : cartes de 14 pt, boutons en capsule.

// MARK: - Présentation d'une session

extension CodexSession {
    /// Pour réutiliser l'icône de phase de l'onglet Claude.
    var iconPhase: Phase {
        switch phase {
        case .ready: return .ready
        case .working: return .thinking
        case .waitingApproval: return .waitingPermission
        case .done: return .done
        case .ended: return .ended
        }
    }

    var status: SessionStatus {
        switch phase {
        case .ready:
            return SessionStatus(label: L("Prête"), detail: lastMessage, isCode: false, color: Palette.secondary)
        case .working:
            if let tool = currentTool {
                return SessionStatus(label: tool.label, detail: tool.detail, isCode: tool.isCode, color: Palette.accent)
            }
            return SessionStatus(label: L("Réfléchit…"), detail: lastPrompt.map { String(format: L("« %@ »"), $0) },
                                 isCode: false, color: Palette.accent)
        case .waitingApproval:
            return SessionStatus(label: L("Attend ton approbation", table: "Codex"), detail: attention?.detail,
                                 isCode: attention?.isCode ?? false, color: Palette.amber)
        case .done:
            return SessionStatus(label: L("Terminé"), detail: lastMessage, isCode: false, color: Palette.green)
        case .ended:
            return SessionStatus(label: L("Session terminée"), detail: nil, isCode: false, color: Palette.secondary)
        }
    }
}

// MARK: - En-tête

/// Icône de l'onglet : spinner quand Codex travaille, main qui pulse quand il attend, symbole sinon.
struct CodexTabIcon: View {
    @ObservedObject var store: CodexStore

    var body: some View {
        switch store.indicator {
        case .working: GlyphSpinner(size: 13)
        case .attention: PulsingHand(size: 12)
        default:
            Image(systemName: "chevron.left.forwardslash.chevron.right")
                .font(.system(size: 12, weight: .bold))
                .foregroundColor(Palette.accent)
                .frame(width: 17, height: 17)
        }
    }
}

// MARK: - Onglet

struct CodexPanel: View {
    @ObservedObject var module: CodexModule
    @ObservedObject var store: CodexStore
    @ObservedObject var approvals: CodexApprovals
    @ObservedObject var setup: CodexHookSetup

    @Environment(\.notchContentMaxHeight) private var contentMaxHeight
    @State private var listHeight: CGFloat = 0

    private static let maxListHeight: CGFloat = 296

    var body: some View {
        let sessions = store.sortedSessions
        VStack(alignment: .leading, spacing: ExpandedPanel.spacing) {
            if sessions.isEmpty {
                emptyState
            } else {
                sessionList(sessions)
            }
        }
    }

    /// Ce qu'il reste à faire pour voir une session : poser les hooks, les valider dans Codex, lancer Codex.
    private var emptyState: some View {
        let installed = setup.status == .installed || setup.status == .scriptOutdated || setup.status == .outdated
        let detail: String
        var action: ModuleAction?
        if !installed {
            detail = L("Pose les hooks Codex dans les réglages pour suivre tes sessions.", table: "Codex")
            action = ModuleAction(title: L("Ouvrir les réglages", table: "Codex"), symbol: "gearshape", run: module.openSettings)
        } else if module.lastEventAt == nil, !setup.notes.reviewed {
            detail = L("Dans Codex, tape /hooks pour valider les hooks de Claude Notch.", table: "Codex")
        } else {
            detail = L("Lance `codex` dans un terminal ou ouvre l'app Codex.", table: "Codex")
        }
        return ModuleEmptyState(symbol: "chevron.left.forwardslash.chevron.right",
                                title: L("Aucune session Codex", table: "Codex"), detail: detail, action: action)
            .padding(.vertical, 12)
    }

    private func sessionList(_ sessions: [CodexSession]) -> some View {
        let estimate = CGFloat(sessions.count) * 72
        let cap = module.replyFromNotch && !approvals.requests.isEmpty ? contentMaxHeight : Self.maxListHeight
        let limit = min(cap, contentMaxHeight)
        return TimelineView(.periodic(from: .now, by: 1)) { context in
            ScrollView(.vertical, showsIndicators: false) {
                VStack(spacing: 8) {
                    ForEach(sessions) { session in
                        VStack(alignment: .leading, spacing: 5) {
                            CodexSessionCard(session: session, now: context.date, onTap: { module.activate(session) })
                            CodexApprovalArea(module: module, approvals: approvals, session: session, compact: false)
                        }
                        .animation(notchSpring, value: approvals.request(for: session.id)?.id)
                    }
                }
                .background(GeometryReader { proxy in
                    Color.clear.preference(key: CodexListHeightKey.self, value: proxy.size.height)
                })
            }
            .frame(height: min(listHeight > 0 ? listHeight : estimate, limit))
        }
        .onPreferenceChange(CodexListHeightKey.self) { listHeight = $0 }
    }
}

private struct CodexListHeightKey: PreferenceKey {
    static var defaultValue: CGFloat = 0
    static func reduce(value: inout CGFloat, nextValue: () -> CGFloat) { value = max(value, nextValue()) }
}

// MARK: - Carte de session

struct CodexSessionCard: View {
    let session: CodexSession
    let now: Date
    let onTap: () -> Void

    @State private var hovering = false

    var body: some View {
        VStack(alignment: .leading, spacing: 6) {
            HStack(spacing: 8) {
                PhaseIcon(phase: session.iconPhase)
                    .frame(width: 16, height: 16)
                Text(verbatim: session.projectName)
                    .font(.system(size: 13, weight: .semibold))
                    .foregroundColor(Palette.primary)
                    .lineLimit(1)
                SourcePill(text: session.sourceLabel)
                if let model = session.model {
                    Text(verbatim: model)
                        .font(.system(size: 11))
                        .foregroundColor(Palette.secondary)
                        .lineLimit(1)
                        .layoutPriority(-1)
                }
                Spacer(minLength: 8)
                Text(verbatim: timeText)
                    .font(.system(size: 11).monospacedDigit())
                    .foregroundColor(Palette.secondary)
            }
            activityLine
        }
        .padding(.horizontal, 12)
        .padding(.vertical, 10)
        .background(
            ModuleStyle.shape(14).fill(Color.white.opacity(hovering ? 0.08 : 0.05))
        )
        .overlay(
            ModuleStyle.shape(14).strokeBorder(Palette.amber.opacity(session.phase.needsAttention ? 0.9 : 0), lineWidth: 1)
        )
        .contentShape(ModuleStyle.shape(14))
        .onTapGesture(perform: onTap)
        .onHover { hovering = $0 }
        .help(session.cwd ?? "")
    }

    private var activityLine: some View {
        let status = session.status
        return HStack(spacing: 6) {
            Text(verbatim: status.label)
                .font(.system(size: 11.5, weight: .medium))
                .foregroundColor(status.color)
                .lineLimit(1)
                .layoutPriority(1)
            if let detail = status.detail {
                Text(verbatim: detail)
                    .font(.system(size: 11, design: status.isCode ? .monospaced : .default))
                    .foregroundColor(.white.opacity(0.75))
                    .lineLimit(1)
                    .truncationMode(.tail)
            }
        }
    }

    private var timeText: String {
        if session.inTurn, let start = session.turnStart { return SessionCard.duration(now.timeIntervalSince(start)) }
        return SessionCard.relative(now.timeIntervalSince(session.endedAt ?? session.lastActivity))
    }
}

// MARK: - Approbation

/// Sous la carte : la demande de Codex avec ses boutons, ou la consigne « Réponds dans … », et le dernier retour.
struct CodexApprovalArea: View {
    @ObservedObject var module: CodexModule
    @ObservedObject var approvals: CodexApprovals
    let session: CodexSession
    var compact: Bool

    var body: some View {
        VStack(alignment: .leading, spacing: 5) {
            if module.replyFromNotch, let request = approvals.request(for: session.id) {
                CodexApprovalCard(request: request, compact: compact, engage: { approvals.engage(request.id) },
                                  decide: { module.decide(request, $0) })
                    .transition(.opacity.combined(with: .move(edge: .top)))
            } else if session.phase.needsAttention {
                ReplyStatusLine(icon: "arrow.up.forward.app", color: Palette.secondary,
                                text: String(format: L("Réponds dans %@", table: "Codex"), session.sourceLabel))
            }
            if let notice = approvals.notices[session.id] {
                ReplyStatusLine(icon: notice.tone.icon, color: notice.tone.color, text: notice.text)
                    .transition(.opacity)
            }
        }
        .animation(.easeOut(duration: 0.15), value: approvals.notices[session.id])
    }

    static func hasContent(_ session: CodexSession, module: CodexModule, approvals: CodexApprovals) -> Bool {
        (module.replyFromNotch && approvals.request(for: session.id) != nil) || session.phase.needsAttention
            || approvals.notices[session.id] != nil
    }
}

extension CodexApprovals.Notice.Tone {
    var icon: String {
        switch self {
        case .done: return "checkmark.circle.fill"
        case .info: return "info.circle.fill"
        case .warning: return "exclamationmark.triangle.fill"
        }
    }

    var color: Color {
        switch self {
        case .done: return Palette.green
        case .info: return Palette.secondary
        case .warning: return Palette.amber
        }
    }
}

struct CodexApprovalCard: View {
    let request: CodexApprovals.Request
    var compact = false
    let engage: () -> Void
    let decide: (CodexApprovals.Decision) -> Void

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            HStack(spacing: 6) {
                Image(systemName: "hand.raised.fill")
                    .font(.system(size: 11, weight: .semibold))
                    .foregroundColor(Palette.amber)
                Text(verbatim: String(format: L("Autoriser %@ ?", table: "Codex"), request.tool.label))
                    .font(.system(size: 12, weight: .semibold))
                    .foregroundColor(Palette.primary)
                    .lineLimit(1)
                if let note = request.note {
                    Text(verbatim: note)
                        .font(.system(size: 11))
                        .foregroundColor(Palette.secondary)
                        .lineLimit(1)
                }
            }
            if let detail = request.tool.detail {
                Text(verbatim: detail)
                    .font(.system(size: 11, design: request.tool.isCode ? .monospaced : .default))
                    .foregroundColor(.white.opacity(0.88))
                    .lineLimit(6)
                    .fixedSize(horizontal: false, vertical: true)
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .padding(.horizontal, 8)
                    .padding(.vertical, 6)
                    .background(ModuleStyle.shape(ModuleStyle.itemRadius).fill(Color.black.opacity(0.35)))
                    .help(detail)
                if RequestCard.isLong(detail) || detail.hasSuffix("…") {
                    ReplyStatusLine(icon: "eye", color: Palette.amber,
                                    text: L("Texte coupé : lis-le en entier dans la session", table: "Codex"))
                }
            }
            ReplyStatusLine(icon: "clock", color: Palette.secondary,
                            text: String(format: L("Sans clic sous %d s, Codex te le redemande dans le terminal.", table: "Codex"),
                                         Int(CodexApprovals.engagedDelay)))
            HStack(spacing: 6) {
                Spacer(minLength: 0)
                ReplyButton(title: L("Dans le terminal", table: "Codex"), style: .secondary) { decide(.terminal) }
                ReplyButton(title: L("Refuser", table: "Codex"), style: .destructive) { decide(.deny) }
                ReplyButton(title: L("Autoriser", table: "Codex"), style: .primary) { decide(.allow) }
            }
        }
        .padding(10)
        .background(ModuleStyle.shape(ModuleStyle.cardRadius).fill(Color.white.opacity(0.07)))
        .overlay(ModuleStyle.shape(ModuleStyle.cardRadius).strokeBorder(Palette.amber.opacity(0.35), lineWidth: 1))
        // La carte est à l'écran : la notch garde la demande le temps qu'il faut (sinon 4 s).
        .onAppear(perform: engage)
    }
}

// MARK: - Plein écran compact

/// Sessions en cours : état et une ligne chacune. Un clic ramène l'app hôte devant. Avec « Approuver depuis la
/// notch », une demande en cours s'affiche dessous.
struct CodexCompactView: View {
    let module: CodexModule
    @ObservedObject var store: CodexStore
    @ObservedObject var approvals: CodexApprovals

    static let maxSessions = 4

    var body: some View {
        let live = store.sortedSessions.filter { $0.phase != .ended }
        VStack(alignment: .leading, spacing: 6) {
            if live.isEmpty {
                Text("Aucune session en cours")
                    .font(.system(size: 12, weight: .medium))
                    .foregroundColor(Palette.secondary)
                    .frame(maxWidth: .infinity)
                    .padding(.vertical, 6)
            }
            ForEach(live.prefix(Self.maxSessions)) { session in
                row(session)
                if CodexApprovalArea.hasContent(session, module: module, approvals: approvals) {
                    CodexApprovalArea(module: module, approvals: approvals, session: session, compact: true)
                }
            }
            if live.count > Self.maxSessions {
                let more = live.count - Self.maxSessions
                Text(String(format: L(more, one: "+ %d autre session", other: "+ %d autres sessions"), more))
                    .font(.system(size: 10.5))
                    .foregroundColor(Palette.secondary)
                    .padding(.leading, 26)
            }
        }
    }

    private func row(_ session: CodexSession) -> some View {
        let status = session.status
        return HStack(alignment: .top, spacing: 8) {
            PhaseIcon(phase: session.iconPhase)
                .frame(width: 16, height: 16)
            VStack(alignment: .leading, spacing: 1) {
                Text(verbatim: session.projectName)
                    .font(.system(size: 12, weight: .semibold))
                    .foregroundColor(Palette.primary)
                    .lineLimit(1)
                (Text(verbatim: status.label).foregroundColor(status.color)
                    + Text(verbatim: status.detail.map { " · \($0)" } ?? "").foregroundColor(.white.opacity(0.7)))
                    .font(.system(size: 11))
                    .lineLimit(1)
                    .truncationMode(.tail)
            }
            Spacer(minLength: 0)
        }
        .padding(.horizontal, 8)
        .padding(.vertical, 6)
        .background(ModuleStyle.shape(ModuleStyle.rowRadius).fill(Color.white.opacity(0.05)))
        .overlay(
            ModuleStyle.shape(ModuleStyle.rowRadius)
                .strokeBorder(Palette.amber.opacity(session.phase.needsAttention ? 0.9 : 0), lineWidth: 1)
        )
        .contentShape(ModuleStyle.shape(ModuleStyle.rowRadius))
        .onTapGesture { module.activate(session) }
    }
}

// MARK: - Réglages

/// Réglages › Codex : approbations depuis la notch, état des hooks.
struct CodexSettingsView: View {
    @ObservedObject var module: CodexModule
    @ObservedObject var setup: CodexHookSetup

    var body: some View {
        SettingsPane {
            Section {
                Toggle(isOn: $module.replyFromNotch) {
                    Text("Approuver depuis la notch", tableName: "Codex")
                }
            } header: {
                Text("Approbations", tableName: "Codex")
            } footer: {
                VStack(alignment: .leading, spacing: 2) {
                    SettingsNote(L("Les demandes d'approbation de Codex s'affichent dans la notch ; un clic décide.",
                                   table: "Codex"))
                    SettingsNote(String(format: L("Codex attend ce hook avant de poser sa question : sans clic sous %d s, ou avec « Dans le terminal », "
                                                  + "il te la pose dans le terminal. Jamais de « toujours autoriser ».",
                                                  table: "Codex"), Int(CodexApprovals.engagedDelay)))
                }
            }
            Section {
                LabeledContent("État") {
                    Text(verbatim: statusText)
                        .foregroundColor(setup.status == .installed ? Palette.green : Palette.amber)
                }
                if setup.notes.hooksDisabled {
                    warning(L("Les hooks sont coupés dans config.toml ([features] hooks = false).", table: "Codex"))
                }
                if setup.status == .installed, !setup.notes.reviewed, module.lastEventAt == nil {
                    warning(L("À valider dans Codex : tape /hooks, puis fais confiance aux hooks de Claude Notch.", table: "Codex"))
                }
                if let last = module.lastEventAt {
                    LabeledContent {
                        Text(verbatim: SessionCard.relative(Date().timeIntervalSince(last)))
                    } label: {
                        Text("Dernier événement", tableName: "Codex")
                    }
                }
                HStack {
                    Button(action: setup.install) { installLabel }
                    Spacer()
                    if setup.status != .notInstalled {
                        Button(action: setup.uninstall) { Text("Retirer les hooks", tableName: "Codex") }
                    }
                }
                if let message = setup.message {
                    Text(verbatim: message)
                        .font(.system(size: 11))
                        .foregroundColor(setup.messageIsError ? Palette.red : .secondary)
                        .fixedSize(horizontal: false, vertical: true)
                }
            } header: {
                Text("Hooks Codex", tableName: "Codex")
            } footer: {
                VStack(alignment: .leading, spacing: 2) {
                    SettingsNote(L("Les hooks relaient chaque événement de Codex à l'app, en local (127.0.0.1).", table: "Codex"))
                    SettingsNote(L("Seul ~/.codex/hooks.json est écrit (sauvegarde horodatée) : config.toml et ton notify ne sont pas touchés.",
                                   table: "Codex"))
                    if setup.notes.inlineHooks {
                        SettingsNote(L("config.toml contient aussi des hooks : Codex charge les deux fichiers.", table: "Codex"))
                    }
                }
            }
        }
        .onAppear { setup.refresh() }
    }

    @ViewBuilder
    private var installLabel: some View {
        switch setup.status {
        case .installed: Text("Réinstaller les hooks", tableName: "Codex")
        case .outdated, .scriptOutdated: Text("Mettre à jour les hooks", tableName: "Codex")
        case .notInstalled, .unreadable: Text("Installer les hooks Codex", tableName: "Codex")
        }
    }

    private var statusText: String {
        switch setup.status {
        case .installed: return L("Installés")
        case .outdated, .scriptOutdated: return L("À mettre à jour")
        case .notInstalled: return L("Non installés")
        case .unreadable(let message): return String(format: L("hooks.json illisible : %@", table: "Codex"), message)
        }
    }

    private func warning(_ text: String) -> some View {
        Label {
            Text(verbatim: text)
        } icon: {
            Image(systemName: "exclamationmark.triangle.fill")
        }
        .font(.system(size: 11))
        .foregroundColor(Palette.amber)
    }
}
