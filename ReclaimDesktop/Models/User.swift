import Foundation

/// Subset of `GET /api/users/current` we care about. The task-list endpoint
/// requires the numeric user id as a `user` query parameter.
public struct ReclaimUser: Codable {
    /// Reclaim account id — a UUID string (not numeric).
    public let id: String
    public let email: String?
    public let name: String?

    /// Best-effort display name for the settings screen.
    public var displayName: String {
        name ?? email ?? "User \(id)"
    }
}
