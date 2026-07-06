import SwiftUI

/// Shared display formatting for dates and durations.
enum Fmt {
    private static let relative: RelativeDateTimeFormatter = {
        let f = RelativeDateTimeFormatter()
        f.unitsStyle = .abbreviated
        return f
    }()

    private static let dateTime: DateFormatter = {
        let f = DateFormatter()
        f.dateStyle = .medium
        f.timeStyle = .short
        return f
    }()

    private static let dayOnly: DateFormatter = {
        let f = DateFormatter()
        f.dateStyle = .medium
        f.timeStyle = .none
        return f
    }()

    /// e.g. "Nov 15, 2:30 PM". Returns em dash for nil.
    static func dateTime(_ date: Date?) -> String {
        guard let date else { return "—" }
        return dateTime.string(from: date)
    }

    static func day(_ date: Date?) -> String {
        guard let date else { return "—" }
        return dayOnly.string(from: date)
    }

    /// e.g. "in 2 days" / "3 hr ago".
    static func relative(_ date: Date?) -> String {
        guard let date else { return "—" }
        return relative.localizedString(for: date, relativeTo: Date())
    }

    /// Hours as a compact string: 0.25 → "15m", 1.5 → "1h 30m", 2 → "2h".
    static func duration(_ hours: Double?) -> String {
        guard let hours, hours > 0 else { return "—" }
        let totalMinutes = Int((hours * 60).rounded())
        let h = totalMinutes / 60
        let m = totalMinutes % 60
        switch (h, m) {
        case (0, _): return "\(m)m"
        case (_, 0): return "\(h)h"
        default: return "\(h)h \(m)m"
        }
    }
}
