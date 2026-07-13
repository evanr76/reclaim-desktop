import Foundation

/// Task priority. Mirrors Reclaim's `PriorityLevel` (P1 highest … P4 lowest).
public enum Priority: String, Codable, CaseIterable, Identifiable, Comparable {
    case p1 = "P1"
    case p2 = "P2"
    case p3 = "P3"
    case p4 = "P4"

    public var id: String { rawValue }

    /// Human label shown in menus.
    public var label: String {
        switch self {
        case .p1: return "P1 — Highest"
        case .p2: return "P2 — High"
        case .p3: return "P3 — Medium"
        case .p4: return "P4 — Low"
        }
    }

    public var short: String { rawValue }

    /// Lower number = more urgent, used for sorting.
    var rank: Int {
        switch self {
        case .p1: return 0
        case .p2: return 1
        case .p3: return 2
        case .p4: return 3
        }
    }

    public static func < (lhs: Priority, rhs: Priority) -> Bool { lhs.rank < rhs.rank }
}

/// Task lifecycle status. Mirrors Reclaim's `TaskStatus`.
public enum TaskStatus: String, Codable, CaseIterable {
    case new = "NEW"
    case scheduled = "SCHEDULED"
    case inProgress = "IN_PROGRESS"
    case complete = "COMPLETE"
    case cancelled = "CANCELLED"
    case archived = "ARCHIVED"

    public var label: String {
        switch self {
        case .new: return "New"
        case .scheduled: return "Scheduled"
        case .inProgress: return "In Progress"
        case .complete: return "Complete"
        case .cancelled: return "Cancelled"
        case .archived: return "Done"
        }
    }

    /// A task is "finished" (out of the active list) when archived or cancelled.
    public var isFinished: Bool { self == .archived || self == .cancelled }
}

/// Reclaim's `EventCategory`.
public enum EventCategory: String, Codable, CaseIterable, Identifiable {
    case work = "WORK"
    case personal = "PERSONAL"
    case both = "BOTH"

    public var id: String { rawValue }
    public var label: String { rawValue.capitalized }
}

/// Reclaim's `EventColor` palette.
public enum EventColor: String, Codable, CaseIterable, Identifiable {
    case none = "NONE", lavender = "LAVENDER", sage = "SAGE", grape = "GRAPE"
    case flamingo = "FLAMINGO", banana = "BANANA", tangerine = "TANGERINE"
    case peacock = "PEACOCK", graphite = "GRAPHITE", blueberry = "BLUEBERRY"
    case basil = "BASIL", tomato = "TOMATO"

    public var id: String { rawValue }
    public var label: String { self == .none ? "Default" : rawValue.capitalized }
}
