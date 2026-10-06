import Foundation

/// Which Reclaim task backend the client talks to.
/// - `v1`: the legacy `/api/tasks` surface (what this app shipped on).
/// - `v2`: the current `/api/reclaim-tasks` surface the website/scheduler use.
public enum ReclaimMode: String, Sendable, CaseIterable {
    case v1, v2
}

// MARK: - 2.0 (/api/reclaim-tasks) adapter

extension ReclaimAPIClient {

    // --- mapping helpers ---

    /// 2.0 timestamps use 9 fractional-second digits, which `ISO8601DateFormatter`
    /// rejects. Strip the fractional part, then parse.
    static func v2Date(_ any: Any?) -> Date? {
        guard let s = any as? String else { return nil }
        let cleaned = s.replacingOccurrences(of: #"\.\d+"#, with: "", options: .regularExpression)
        let f = ISO8601DateFormatter()
        f.formatOptions = [.withInternetDateTime]
        return f.date(from: cleaned)
    }

    static func dateOnly(_ date: Date) -> String {
        let f = DateFormatter()
        f.calendar = Calendar(identifier: .iso8601)
        f.locale = Locale(identifier: "en_US_POSIX")
        f.dateFormat = "yyyy-MM-dd"
        return f.string(from: date)
    }

    static func numericId(_ rid: String) -> Int? {
        Int(rid.split(separator: ":").last.map(String.init) ?? "")
    }

    /// Map a 2.0 task object onto the app's `ReclaimTask`. Up Next is the
    /// `PRIORITIZE` priority (so `onDeck` is derived and the P-level is nil);
    /// `start` stands in for snooze; `completed` maps to the ARCHIVED status.
    static func mapV2(_ o: [String: Any]) -> ReclaimTask? {
        guard let rid = o["id"] as? String, let num = numericId(rid) else { return nil }
        let pr = o["priority"] as? String
        let onDeck = (pr == "PRIORITIZE")
        let level = (pr == nil || pr == "PRIORITIZE" || pr == "DEFAULT") ? nil : pr
        let mins = o["estimateMinutes"] as? Int
        let completed = (o["completed"] as? Bool) ?? false
        let ext = o["extendedProperties"] as? [String: Any]
        let sort = o["sortOrder"] as? Double
        // Memberwise init (property-declaration order); fields with no 2.0 analogue are nil.
        return ReclaimTask(
            id: num,
            title: o["title"] as? String,
            notes: o["description"] as? String,
            priority: level,
            status: completed ? "ARCHIVED" : "NEW",
            eventCategory: ext?["eventType"] as? String,
            eventColor: nil,
            due: v2Date(o["due"]),
            snoozeUntil: v2Date(o["start"]),
            created: nil,
            updated: nil,
            finished: completed ? v2Date(o["due"]) : nil,
            timeChunksRequired: mins.map { Int((Double($0) / 15.0).rounded()) },
            timeChunksRemaining: nil,
            timeChunksSpent: nil,
            minChunkSize: nil,
            maxChunkSize: nil,
            onDeck: onDeck,
            atRisk: nil,
            deleted: nil,
            deferred: nil,
            alwaysPrivate: nil,
            index: sort,
            sortKey: sort,
            timeSchemeId: nil,
            type: "TASK"
        )
    }

    private func v2JSON(_ body: String) -> Any? {
        body.data(using: .utf8).flatMap { try? JSONSerialization.jsonObject(with: $0) }
    }

    private func v2Send(_ method: String, _ path: String, query: [URLQueryItem]? = nil, body: [String: Any]? = nil) async throws -> [String: Any] {
        let data = try body.map { try JSONSerialization.data(withJSONObject: $0) }
        let (status, resp) = try await rawRequest(method: method, path: path, query: query, body: data)
        guard (200...299).contains(status) else {
            if status == 401 || status == 403 { throw ReclaimAPIError.unauthorized }
            throw ReclaimAPIError.http(status: status, message: String(resp.prefix(200)))
        }
        return (v2JSON(resp) as? [String: Any]) ?? [:]
    }

    private func v2ForEach(_ ids: [Int], _ op: @escaping @Sendable (Int) async throws -> Void) async throws {
        try await withThrowingTaskGroup(of: Void.self) { group in
            for id in ids { group.addTask { try await op(id) } }
            try await group.waitForAll()
        }
    }

    // --- read ---

    func v2FetchTasks() async throws -> [ReclaimTask] {
        var out: [ReclaimTask] = []
        var after: String? = nil
        repeat {
            var q = [URLQueryItem(name: "count", value: "200")]
            if let after { q.append(URLQueryItem(name: "after", value: after)) }
            let obj = try await v2Send("GET", "/api/reclaim-tasks/page", query: q)
            let items = (obj["items"] as? [[String: Any]]) ?? []
            out.append(contentsOf: items.compactMap { Self.mapV2($0) })
            after = ((obj["hasNextPage"] as? Bool) ?? false) ? (obj["last"] as? String) : nil
        } while after != nil
        return out
    }

    // --- writes ---

    @discardableResult
    func v2Create(title: String, priority: Priority, durationHours: Double, due: Date?) async throws -> ReclaimTask {
        var body: [String: Any] = [
            "title": title,
            "priority": priority.rawValue,
            "estimateMinutes": max(1, Int((durationHours * 60).rounded())),
        ]
        if let due { body["dueDate"] = Self.dateOnly(due) }
        let o = try await v2Send("POST", "/api/reclaim-tasks", body: body)
        guard let t = Self.mapV2(o) else { throw ReclaimAPIError.decoding("2.0 create returned no task") }
        return t
    }

    func v2Patch(id: Int, body: [String: Any]) async throws {
        guard !body.isEmpty else { return }
        _ = try await v2Send("PATCH", "/api/reclaim-tasks/\(id)", body: body)
    }

    func v2DeleteOne(id: Int) async throws {
        _ = try await v2Send("DELETE", "/api/reclaim-tasks/\(id)")
    }

    func v2Complete(ids: [Int], completed: Bool) async throws {
        try await v2ForEach(ids) { try await self.v2Patch(id: $0, body: ["completed": completed]) }
    }
    func v2Delete(ids: [Int]) async throws {
        try await v2ForEach(ids) { try await self.v2DeleteOne(id: $0) }
    }
    func v2Reprioritize(ids: [Int], to priority: Priority) async throws {
        try await v2ForEach(ids) { try await self.v2Patch(id: $0, body: ["priority": priority.rawValue]) }
    }
    func v2SetUpNext(ids: [Int], onDeck: Bool) async throws {
        let value = onDeck ? "PRIORITIZE" : "DEFAULT"
        try await v2ForEach(ids) { try await self.v2Patch(id: $0, body: ["priority": value]) }
    }
    func v2Reschedule(ids: [Int], due: Date?) async throws {
        let value: Any = due.map { Self.dateOnly($0) } ?? NSNull()
        try await v2ForEach(ids) { try await self.v2Patch(id: $0, body: ["dueDate": value]) }
    }
    func v2Snooze(ids: [Int], until: Date?) async throws {
        let value: Any = until.map { Self.dateOnly($0) } ?? NSNull()
        try await v2ForEach(ids) { try await self.v2Patch(id: $0, body: ["startDate": value]) }
    }

    /// Translate a 1.0 `updateTask` patch (edit sheet) into a 2.0 body.
    func v2Update(id: Int, patch: [String: Any]) async throws {
        var out: [String: Any] = [:]
        for (k, v) in patch {
            switch k {
            case "title": out["title"] = v
            case "notes": out["description"] = v
            case "priority": out["priority"] = v
            case "due":
                if v is NSNull { out["dueDate"] = NSNull() }
                else if let s = v as? String { out["dueDate"] = String(s.prefix(10)) }
            case "snoozeUntil":
                if v is NSNull { out["startDate"] = NSNull() }
                else if let s = v as? String { out["startDate"] = String(s.prefix(10)) }
            case "onDeck":
                if let b = v as? Bool { out["priority"] = b ? "PRIORITIZE" : "DEFAULT" }
            case "timeChunksRequired":
                if let c = v as? Int { out["estimateMinutes"] = c * 15 }
            default:
                break   // eventCategory/eventColor/timeSchemeId/min-max chunks: no 2.0 equivalent
            }
        }
        try await v2Patch(id: id, body: out)
    }
}
