import Foundation

/// Errors surfaced to the UI. `LocalizedError` so `.localizedDescription`
/// reads well in alerts.
public enum ReclaimAPIError: LocalizedError {
    case noToken
    case unauthorized
    case http(status: Int, message: String)
    case network(String)
    case decoding(String)
    case invalidInput(String)

    public var errorDescription: String? {
        switch self {
        case .noToken:
            return "No API token configured. Add your Reclaim API key in Settings."
        case .unauthorized:
            return "Authentication failed. Check that your Reclaim API key is valid."
        case let .http(status, message):
            return "Reclaim API error (\(status)): \(message)"
        case let .network(msg):
            return "Network error: \(msg)"
        case let .decoding(msg):
            return "Could not read the response from Reclaim: \(msg)"
        case let .invalidInput(msg):
            return msg
        }
    }
}

/// Async client for the Reclaim.ai REST API.
///
/// All calls go to `https://api.app.reclaim.ai` with a Bearer token. Batch
/// endpoints power the bulk operations this app is built around.
public final class ReclaimAPIClient: Sendable {
    private let token: String
    private let baseURL = URL(string: "https://api.app.reclaim.ai")!
    private let session: URLSession

    public init(token: String, session: URLSession = .shared) {
        self.token = token
        self.session = session
    }

    // MARK: - Public API

    /// The authenticated user. Needed to supply the `user` query param on list.
    public func currentUser() async throws -> ReclaimUser {
        let data = try await request(method: "GET", path: "/api/users/current")
        return try decode(ReclaimUser.self, from: data)
    }

    /// All of the user's tasks (every status), filtered to real tasks.
    /// Filtering into active/completed/overdue happens client-side.
    public func fetchTasks(userId: String) async throws -> [ReclaimTask] {
        let data = try await request(method: "GET", path: "/api/tasks", query: Self.taskListQuery(userId: userId))
        let tasks = try decode([ReclaimTask].self, from: data)
        return tasks.filter { $0.isTask && !($0.deleted ?? false) }
    }

    /// Create a new task. `POST /api/tasks`. Returns the created task.
    @discardableResult
    public func createTask(
        title: String,
        priority: Priority = .p3,
        durationHours: Double = 1,
        due: Date? = nil,
        category: EventCategory = .work
    ) async throws -> ReclaimTask {
        guard durationHours.isFinite, durationHours > 0 else {
            throw ReclaimAPIError.invalidInput("Duration must be a positive, finite number of hours.")
        }
        let chunks = max(1, Int((durationHours * 4).rounded()))
        let minChunk = min(2, chunks)
        let maxChunk = max(chunks, minChunk)
        var body: [String: Any] = [
            "title": title,
            "eventCategory": category.rawValue,
            "priority": priority.rawValue,
            "status": TaskStatus.new.rawValue,
            "timeChunksRequired": chunks,
            "minChunkSize": minChunk,
            "maxChunkSize": maxChunk,
        ]
        if let due { body["due"] = Self.isoString(due) }
        let data = try await request(method: "POST", path: "/api/tasks",
                                     body: try JSONSerialization.data(withJSONObject: body))
        return try decode(ReclaimTask.self, from: data)
    }

    /// The block scheduled right now (may have no `event`). `GET /api/moment`.
    public func currentMoment() async throws -> Moment {
        let data = try await request(method: "GET", path: "/api/moment")
        return try decode(Moment.self, from: data)
    }

    /// The next upcoming block. `GET /api/moment/next`.
    public func nextMoment() async throws -> Moment {
        let data = try await request(method: "GET", path: "/api/moment/next")
        return try decode(Moment.self, from: data)
    }

    /// Available time schemes (custom hours). `GET /api/timeschemes`.
    public func fetchTimeSchemes() async throws -> [TimeScheme] {
        let data = try await request(method: "GET", path: "/api/timeschemes")
        return try decode([TimeScheme].self, from: data)
    }

    // MARK: Bulk operations

    /// Bulk mark complete → archives the tasks. `PATCH /api/tasks/batch/archive`.
    public func bulkComplete(ids: [Int]) async throws {
        try await batch(method: "PATCH", path: "/api/tasks/batch/archive", ids: ids, patch: nil)
    }

    /// Bulk permanent delete. `DELETE /api/tasks/batch`.
    public func bulkDelete(ids: [Int]) async throws {
        try await batch(method: "DELETE", path: "/api/tasks/batch", ids: ids, patch: nil)
    }

    /// Bulk apply an arbitrary field patch. `PATCH /api/tasks/batch`.
    public func bulkPatch(ids: [Int], patch: [String: Any]) async throws {
        try await batch(method: "PATCH", path: "/api/tasks/batch", ids: ids, patch: patch)
    }

    /// Bulk change priority (P1–P4).
    public func bulkReprioritize(ids: [Int], to priority: Priority) async throws {
        try await bulkPatch(ids: ids, patch: ["priority": priority.rawValue])
    }

    /// Bulk move tasks into / out of "Up Next" (Reclaim's `onDeck` flag).
    ///
    /// The `/api/tasks/batch` endpoint silently ignores `onDeck`, so this fans
    /// out single-task PATCHes (which do honor it) concurrently.
    public func bulkSetUpNext(ids: [Int], onDeck: Bool) async throws {
        try await withThrowingTaskGroup(of: Void.self) { group in
            for id in ids {
                group.addTask { try await self.updateTask(id: id, patch: ["onDeck": onDeck]) }
            }
            try await group.waitForAll()
        }
    }

    /// Bulk change due date. Pass `nil` to clear the due date.
    public func bulkReschedule(ids: [Int], due: Date?) async throws {
        try await bulkPatch(ids: ids, patch: ["due": due.map(Self.isoString) ?? NSNull()])
    }

    /// Bulk defer/snooze until a date. Pass `nil` to clear.
    public func bulkSnooze(ids: [Int], until: Date?) async throws {
        try await bulkPatch(ids: ids, patch: ["snoozeUntil": until.map(Self.isoString) ?? NSNull()])
    }

    // MARK: Single-task operations

    /// Patch a single task with the given fields. `PATCH /api/tasks/{id}`.
    public func updateTask(id: Int, patch: [String: Any]) async throws {
        let body = try JSONSerialization.data(withJSONObject: patch, options: [])
        _ = try await request(method: "PATCH", path: "/api/tasks/\(id)", body: body)
    }

    /// Mark a single task complete via the planner endpoint (nicer than batch
    /// for one task; keeps scheduling side-effects). `POST /api/planner/done/task/{id}`.
    public func markComplete(id: Int) async throws {
        _ = try await request(method: "POST", path: "/api/planner/done/task/\(id)")
    }

    /// Reopen a completed/archived task. `POST /api/planner/unarchive/task/{id}`.
    public func markIncomplete(id: Int) async throws {
        _ = try await request(method: "POST", path: "/api/planner/unarchive/task/\(id)")
    }

    /// Start a work session on a task. `POST /api/planner/start/task/{id}`.
    public func startTask(id: Int) async throws {
        _ = try await request(method: "POST", path: "/api/planner/start/task/\(id)")
    }

    /// Stop the active work session. `POST /api/planner/stop/task/{id}`.
    public func stopTask(id: Int) async throws {
        _ = try await request(method: "POST", path: "/api/planner/stop/task/\(id)")
    }

    /// Auto-prioritize all tasks by due date. `PATCH /api/tasks/reindex-by-due`.
    public func reindexByDue() async throws {
        _ = try await request(method: "PATCH", path: "/api/tasks/reindex-by-due")
    }

    // MARK: - Raw access (diagnostics)

    /// The query used by `fetchTasks`, exposed so the probe can hit the exact
    /// same URL the app does.
    public static func taskListQuery(userId: String) -> [URLQueryItem] {
        var query = [URLQueryItem(name: "user", value: userId)]
        for s in TaskStatus.allCases {
            query.append(URLQueryItem(name: "status", value: s.rawValue))
        }
        query.append(URLQueryItem(name: "instances", value: "false"))
        return query
    }

    /// Perform a request and return the status code and raw body **without**
    /// throwing on non-2xx — for inspecting exactly what the API returns.
    public func rawRequest(
        method: String = "GET",
        path: String,
        query: [URLQueryItem]? = nil,
        body: Data? = nil
    ) async throws -> (status: Int, body: String) {
        let (data, status) = try await send(method: method, path: path, query: query, body: body)
        let text = String(data: data, encoding: .utf8) ?? "<\(data.count) bytes, non-UTF8>"
        return (status, text)
    }

    // MARK: - Batch helper

    /// Builds the `[{taskId, patch}]` body shared by all batch endpoints and
    /// sends it with the given method. `patch` is `nil` for archive/delete.
    private func batch(method: String, path: String, ids: [Int], patch: [String: Any]?) async throws {
        guard !ids.isEmpty else { return }
        let items: [[String: Any]] = ids.map { id in
            ["taskId": id, "patch": patch ?? [:]]
        }
        let body = try JSONSerialization.data(withJSONObject: items, options: [])
        _ = try await request(method: method, path: path, body: body)
    }

    // MARK: - Request plumbing

    /// Low-level send. Returns raw data + status; never throws on HTTP status.
    private func send(
        method: String,
        path: String,
        query: [URLQueryItem]?,
        body: Data?
    ) async throws -> (Data, Int) {
        guard var components = URLComponents(url: baseURL.appendingPathComponent(path), resolvingAgainstBaseURL: false) else {
            throw ReclaimAPIError.network("Bad URL for \(path)")
        }
        if let query, !query.isEmpty { components.queryItems = query }
        guard let url = components.url else {
            throw ReclaimAPIError.network("Bad URL for \(path)")
        }

        var req = URLRequest(url: url)
        req.httpMethod = method
        req.setValue("Bearer \(token)", forHTTPHeaderField: "Authorization")
        req.setValue("application/json", forHTTPHeaderField: "Accept")
        if let body {
            req.httpBody = body
            req.setValue("application/json", forHTTPHeaderField: "Content-Type")
        }

        do {
            let (data, response) = try await session.data(for: req)
            guard let http = response as? HTTPURLResponse else {
                throw ReclaimAPIError.network("No HTTP response")
            }
            return (data, http.statusCode)
        } catch let e as ReclaimAPIError {
            throw e
        } catch {
            throw ReclaimAPIError.network(error.localizedDescription)
        }
    }

    /// Send and map non-2xx status codes to `ReclaimAPIError`.
    @discardableResult
    private func request(
        method: String,
        path: String,
        query: [URLQueryItem]? = nil,
        body: Data? = nil
    ) async throws -> Data {
        let (data, status) = try await send(method: method, path: path, query: query, body: body)
        switch status {
        case 200...299:
            return data
        case 401, 403:
            throw ReclaimAPIError.unauthorized
        default:
            throw ReclaimAPIError.http(status: status, message: Self.message(from: data))
        }
    }

    // MARK: - Encoding / decoding helpers

    /// ISO-8601 with a trailing `Z`, matching what the SDK sends.
    public static func isoString(_ date: Date) -> String {
        let f = ISO8601DateFormatter()
        f.formatOptions = [.withInternetDateTime]
        return f.string(from: date)
    }

    private static func message(from data: Data) -> String {
        guard !data.isEmpty else { return "no details" }
        if let obj = try? JSONSerialization.jsonObject(with: data) as? [String: Any] {
            if let m = obj["message"] as? String { return m }
            if let m = obj["error"] as? String { return m }
        }
        return String(data: data, encoding: .utf8) ?? "no details"
    }

    private func decode<T: Decodable>(_ type: T.Type, from data: Data) throws -> T {
        let decoder = JSONDecoder()
        decoder.dateDecodingStrategy = .custom { d in
            let container = try d.singleValueContainer()
            let raw = try container.decode(String.self)
            if let date = DateParsing.parse(raw) { return date }
            throw DecodingError.dataCorruptedError(in: container, debugDescription: "Unparseable date: \(raw)")
        }
        do {
            return try decoder.decode(T.self, from: data)
        } catch {
            throw ReclaimAPIError.decoding(String(describing: error))
        }
    }
}

/// Reclaim returns ISO-8601 timestamps, sometimes with fractional seconds and
/// sometimes without. Try both.
enum DateParsing {
    private static let withFraction: ISO8601DateFormatter = {
        let f = ISO8601DateFormatter()
        f.formatOptions = [.withInternetDateTime, .withFractionalSeconds]
        return f
    }()
    private static let plain: ISO8601DateFormatter = {
        let f = ISO8601DateFormatter()
        f.formatOptions = [.withInternetDateTime]
        return f
    }()
    private static let dateOnly: DateFormatter = {
        let f = DateFormatter()
        f.calendar = Calendar(identifier: .iso8601)
        f.locale = Locale(identifier: "en_US_POSIX")
        f.timeZone = TimeZone(identifier: "UTC")
        f.dateFormat = "yyyy-MM-dd"
        return f
    }()

    static func parse(_ raw: String) -> Date? {
        withFraction.date(from: raw) ?? plain.date(from: raw) ?? dateOnly.date(from: raw)
    }
}
