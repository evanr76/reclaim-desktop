import Foundation

/// A Reclaim time scheme (custom hours) from `GET /api/timeschemes`.
public struct TimeScheme: Codable, Identifiable, Hashable {
    public let id: String
    public let title: String?
    public let features: [String]?

    /// Only schemes that can host task assignments are offered for tasks.
    public var supportsTasks: Bool { features?.contains("TASK_ASSIGNMENT") ?? false }
    public var displayTitle: String { title ?? "Untitled" }
}
