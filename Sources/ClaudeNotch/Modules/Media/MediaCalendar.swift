import AppKit
import EventKit
import SwiftUI

enum CalendarAccess: Equatable {
    case notDetermined
    case denied
    case granted
}

struct MediaEvent: Identifiable, Equatable {
    var id: String
    var title: String
    var start: Date
    var end: Date
    var isAllDay: Bool
    var color: Color
}

struct MediaCalendarInfo: Identifiable, Equatable {
    var id: String
    var title: String
    var source: String
    var color: Color
}

/// Accès aux calendriers : EventKit dans l'app, un double dans les tests. Résultats sur le main thread.
protocol CalendarSource: AnyObject {
    var access: CalendarAccess { get }
    func requestAccess(_ done: @escaping (CalendarAccess) -> Void)
    func calendars(_ done: @escaping ([MediaCalendarInfo]) -> Void)
    /// Événements qui chevauchent [start, end[, triés, sauf ceux des calendriers masqués.
    func events(from start: Date, to end: Date, hidden: Set<String>, _ done: @escaping ([MediaEvent]) -> Void)
    /// Base libérée (arrêt du module) ; recréée à la prochaine demande.
    func release()
}

/// EventKit. Toute la base passe par une file série : `events(matching:)` peut prendre un moment, la notch ne gèle pas.
final class EventKitCalendar: CalendarSource {
    private let queue = DispatchQueue(label: "claudenotch.media.calendar")
    private var store: EKEventStore?

    private func withStore(_ body: @escaping (EKEventStore) -> Void) {
        queue.async {
            let store = self.store ?? EKEventStore()
            self.store = store
            body(store)
        }
    }

    var access: CalendarAccess { Self.currentAccess }

    private static var currentAccess: CalendarAccess {
        let status = EKEventStore.authorizationStatus(for: .event)
        switch status {
        case .notDetermined: return .notDetermined
        case .restricted, .denied: return .denied
        default:
            // macOS 14 : « écriture seule » ne permet pas de lire.
            if #available(macOS 14, *) { return status == .fullAccess ? .granted : .denied }
            return .granted
        }
    }

    func requestAccess(_ done: @escaping (CalendarAccess) -> Void) {
        // L'app n'a pas d'icône dans le Dock : sans activation, la demande s'ouvrirait derrière les fenêtres.
        HookSetup.activateApp()
        withStore { store in
            let finish: (Bool, Error?) -> Void = { _, _ in
                DispatchQueue.main.async { done(Self.currentAccess) }
            }
            if #available(macOS 14, *) {
                store.requestFullAccessToEvents(completion: finish)
            } else {
                store.requestAccess(to: .event, completion: finish)
            }
        }
    }

    func calendars(_ done: @escaping ([MediaCalendarInfo]) -> Void) {
        guard access == .granted else { return done([]) }
        withStore { store in
            let list = store.calendars(for: .event)
                .map { MediaCalendarInfo(id: $0.calendarIdentifier, title: $0.title, source: $0.source?.title ?? "",
                                         color: Self.color($0)) }
                .sorted { ($0.source, $0.title) < ($1.source, $1.title) }
            DispatchQueue.main.async { done(list) }
        }
    }

    func events(from start: Date, to end: Date, hidden: Set<String>, _ done: @escaping ([MediaEvent]) -> Void) {
        guard access == .granted else { return done([]) }
        withStore { store in
            let calendars = store.calendars(for: .event).filter { !hidden.contains($0.calendarIdentifier) }
            var events: [MediaEvent] = []
            if !calendars.isEmpty {
                let predicate = store.predicateForEvents(withStart: start, end: end, calendars: calendars)
                events = store.events(matching: predicate).map {
                    MediaEvent(id: ($0.eventIdentifier ?? UUID().uuidString) + "\($0.startDate.timeIntervalSince1970)",
                               title: $0.title ?? "", start: $0.startDate, end: $0.endDate, isAllDay: $0.isAllDay,
                               color: $0.calendar.map(Self.color) ?? .gray)
                }
            }
            DispatchQueue.main.async { done(MediaCalendarMath.sorted(events)) }
        }
    }

    func release() {
        queue.async { self.store = nil }
    }

    private static func color(_ calendar: EKCalendar) -> Color {
        calendar.cgColor.map { Color(cgColor: $0) } ?? .gray
    }
}

/// Calculs de dates du calendrier (purs, testés).
enum MediaCalendarMath {
    /// Les 7 jours (début de journée) de la semaine qui contient `day`, selon le premier jour de la semaine local.
    static func week(containing day: Date, calendar: Calendar = .current) -> [Date] {
        let start = calendar.dateInterval(of: .weekOfYear, for: day)?.start ?? calendar.startOfDay(for: day)
        return (0..<7).compactMap { calendar.date(byAdding: .day, value: $0, to: start) }
    }

    /// Journée entière d'abord, puis par heure de début.
    static func sorted(_ events: [MediaEvent]) -> [MediaEvent] {
        events.sorted { ($0.isAllDay ? 0 : 1, $0.start, $0.title) < ($1.isAllDay ? 0 : 1, $1.start, $1.title) }
    }

    /// Événements qui touchent la journée de `day`.
    static func events(_ events: [MediaEvent], on day: Date, calendar: Calendar = .current) -> [MediaEvent] {
        let start = calendar.startOfDay(for: day)
        guard let end = calendar.date(byAdding: .day, value: 1, to: start) else { return [] }
        return events.filter { $0.start < end && ($0.end > start || ($0.end == $0.start && $0.start >= start)) }
    }

    /// Prochain événement à heure fixe pas encore terminé (en cours compris).
    static func next(_ events: [MediaEvent], after now: Date) -> MediaEvent? {
        events.filter { !$0.isAllDay && $0.end > now }.min { $0.start < $1.start }
    }
}

/// Ouvre Calendrier à une date : AppleScript « view calendar at » (autorisation Automatisation, demandée par
/// macOS au premier usage), sinon simplement l'app. osascript tourne hors du main thread : la fenêtre
/// d'autorisation ne fige pas la notch.
enum CalendarOpener {
    static let bundleIdentifier = "com.apple.iCal"

    /// Le jour est posé champ par champ : une date en texte dépendrait de la langue du Mac.
    static func script(for date: Date, calendar: Calendar = .current) -> String {
        let parts = calendar.dateComponents([.year, .month, .day], from: date)
        return """
        set d to current date
        set day of d to 1
        set year of d to \(parts.year ?? 2000)
        set month of d to \(parts.month ?? 1)
        set day of d to \(parts.day ?? 1)
        set time of d to 0
        tell application id "\(bundleIdentifier)"
            activate
            switch view to day view
            view calendar at d
        end tell
        """
    }

    static func open(at date: Date) {
        let process = Process()
        process.executableURL = URL(fileURLWithPath: "/usr/bin/osascript")
        process.arguments = ["-e", script(for: date)]
        process.standardOutput = FileHandle.nullDevice
        process.standardError = FileHandle.nullDevice
        process.terminationHandler = { process in
            guard process.terminationStatus != 0 else { return }
            DispatchQueue.main.async(execute: openApp)
        }
        do { try process.run() } catch { openApp() }
    }

    static func openApp() {
        guard let url = NSWorkspace.shared.urlForApplication(withBundleIdentifier: bundleIdentifier) else { return }
        NSWorkspace.shared.openApplication(at: url, configuration: NSWorkspace.OpenConfiguration())
    }
}
