import Foundation

/// A Reclaim task. Fields mirror the JSON returned by `GET /api/tasks`
/// (camelCase keys map 1:1 to these property names).
///
/// Enum-typed fields (priority/status/category) are stored as raw strings and
/// surfaced through computed accessors so an unexpected server value never
/// fails decoding of the whole list.
public struct ReclaimTask: Codable, Identifiable, Hashable {
    public let id: Int
    public var title: String?
    public var notes: String?

    public var priority: String?
    public var status: String?
    public var eventCategory: String?
    public var eventColor: String?

    public var due: Date?
    public var snoozeUntil: Date?
    public var created: Date?
    public var updated: Date?
    public var finished: Date?

    public var timeChunksRequired: Int?
    public var timeChunksRemaining: Int?
    public var timeChunksSpent: Int?
    public var minChunkSize: Int?
    public var maxChunkSize: Int?

    public var onDeck: Bool?
    public var atRisk: Bool?
    public var deleted: Bool?
    public var deferred: Bool?
    public var alwaysPrivate: Bool?

    public var index: Double?
    public var sortKey: Double?
    public var timeSchemeId: String?
    public var type: String?

    // MARK: - Derived values

    public var priorityEnum: Priority? { priority.flatMap(Priority.init(rawValue:)) }
    public var statusEnum: TaskStatus? { status.flatMap(TaskStatus.init(rawValue:)) }
    public var categoryEnum: EventCategory? { eventCategory.flatMap(EventCategory.init(rawValue:)) }
    public var colorEnum: EventColor? { eventColor.flatMap(EventColor.init(rawValue:)) }

    public var displayTitle: String {
        let t = title?.trimmingCharacters(in: .whitespacesAndNewlines) ?? ""
        return t.isEmpty ? "(untitled)" : t
    }

    /// Scheduled duration in hours (Reclaim stores 15-minute "chunks").
    public var durationHours: Double? {
        guard let chunks = timeChunksRequired else { return nil }
        return Double(chunks) / 4.0
    }

    /// Remaining work in hours.
    public var remainingHours: Double? {
        guard let chunks = timeChunksRemaining else { return nil }
        return Double(chunks) / 4.0
    }

    /// True once the task is out of the active workflow.
    public var isFinished: Bool { statusEnum?.isFinished ?? false }

    /// Past its due date and not yet finished.
    public var isOverdue: Bool {
        guard let due, !isFinished else { return false }
        return due < Date()
    }

    /// Currently snoozed / deferred to a future date.
    public var isSnoozed: Bool {
        guard let snoozeUntil else { return false }
        return snoozeUntil > Date()
    }

    /// Only real tasks (not daily habits) should appear in the list.
    public var isTask: Bool { (type ?? "TASK") == "TASK" }

    // MARK: - Non-optional sort keys (for Table column sorting)

    /// Undated tasks sort to the end.
    public var sortDue: Date { due ?? .distantFuture }
    /// Full creation timestamp for absolute sorting (column displays date only).
    public var sortCreated: Date { created ?? .distantPast }
    /// P1=0 … P4=3; unset sorts last.
    public var sortPriorityRank: Int { priorityEnum?.rank ?? 99 }
    /// Duration in chunks; unset sorts first (as -1).
    public var sortDurationChunks: Int { timeChunksRequired ?? -1 }
    public var sortStatusLabel: String { statusEnum?.label ?? status ?? "" }

    // MARK: - Hashable / Equatable by identity

    public static func == (lhs: ReclaimTask, rhs: ReclaimTask) -> Bool { lhs.id == rhs.id }
    public func hash(into hasher: inout Hasher) { hasher.combine(id) }
}
