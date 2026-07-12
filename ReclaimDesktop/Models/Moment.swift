import Foundation

/// A scheduled calendar block from Reclaim's "moment" endpoints. The personal
/// API key can't read the full calendar (403), but `/api/moment` (now) and
/// `/api/moment/next` return the current and next blocks.
public struct MomentEvent: Codable, Identifiable, Hashable {
    public let eventId: String?
    public let title: String?
    public let eventStart: Date?
    public let eventEnd: Date?
    public let priority: String?
    public let type: String?
    public let onlineMeetingUrl: String?
    public let free: Bool?
    public let reclaimManaged: Bool?

    public var id: String { eventId ?? "\(title ?? "")-\(eventStart?.timeIntervalSince1970 ?? 0)" }
    public var priorityEnum: Priority? { priority.flatMap(Priority.init(rawValue:)) }
    public var displayTitle: String {
        let t = title?.trimmingCharacters(in: .whitespacesAndNewlines) ?? ""
        return t.isEmpty ? "Busy" : t
    }
    /// True while `now` falls within the block.
    public func isActive(asOf now: Date = Date()) -> Bool {
        guard let s = eventStart, let e = eventEnd else { return false }
        return s <= now && now < e
    }
}

/// Response shape of `/api/moment` and `/api/moment/next`.
public struct Moment: Codable {
    public let event: MomentEvent?
    public let additionalEvents: [MomentEvent]?
    public let now: Date?
}
