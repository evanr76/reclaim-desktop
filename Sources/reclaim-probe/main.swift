import Foundation
import ReclaimKit

// A tiny command-line harness for exercising the Reclaim API with a live key,
// using the same client the app uses. The token is read from the environment
// (RECLAIM_TOKEN) so it never lands in a file or shell history.
//
// Usage:
//   RECLAIM_TOKEN=... swift run reclaim-probe whoami
//   RECLAIM_TOKEN=... swift run reclaim-probe list [active|overdue|completed|all]
//   RECLAIM_TOKEN=... swift run reclaim-probe dump-user
//   RECLAIM_TOKEN=... swift run reclaim-probe dump-tasks
//   RECLAIM_TOKEN=... swift run reclaim-probe raw /api/some/path
//
// Mutating commands require RECLAIM_PROBE_ALLOW_WRITES=1 to run:
//   ... reclaim-probe complete <id> [<id>...]
//   ... reclaim-probe priority <P1|P2|P3|P4> <id> [<id>...]
//   ... reclaim-probe delete <id> [<id>...]

let env = ProcessInfo.processInfo.environment
let args = Array(CommandLine.arguments.dropFirst())

func fail(_ message: String) -> Never {
    FileHandle.standardError.write(Data(("error: " + message + "\n").utf8))
    exit(1)
}

/// Token resolution: RECLAIM_TOKEN env var first, then a gitignored
/// `.reclaim-token` file in the current directory.
func resolveToken() -> String? {
    if let t = env["RECLAIM_TOKEN"], !t.isEmpty { return t }
    let path = FileManager.default.currentDirectoryPath + "/.reclaim-token"
    if let contents = try? String(contentsOfFile: path, encoding: .utf8) {
        let trimmed = contents.trimmingCharacters(in: .whitespacesAndNewlines)
        if !trimmed.isEmpty { return trimmed }
    }
    return nil
}

guard let token = resolveToken() else {
    fail("""
    No API key found. Provide it one of two ways:
      • export RECLAIM_TOKEN=...            (env var), or
      • echo 'your-key' > .reclaim-token    (gitignored file)
    """)
}

guard let command = args.first else {
    print("""
    reclaim-probe — test the Reclaim API with a live key.

    Commands:
      whoami                         Show the authenticated user
      list [active|overdue|completed|all]   List tasks (default: active)
      dump-user                      Raw JSON of /api/users/current
      dump-tasks                     Raw JSON of the task-list request
      raw <path>                     Raw GET of an arbitrary path
      complete <id> [<id>...]        Bulk complete (needs RECLAIM_PROBE_ALLOW_WRITES=1)
      priority <P#> <id> [<id>...]   Bulk set priority (needs writes flag)
      delete <id> [<id>...]          Bulk delete (needs writes flag)
    """)
    exit(0)
}

let client = ReclaimAPIClient(token: token)
let writesAllowed = env["RECLAIM_PROBE_ALLOW_WRITES"] == "1"

func requireWrites() {
    guard writesAllowed else {
        fail("This command mutates data. Re-run with RECLAIM_PROBE_ALLOW_WRITES=1 to confirm.")
    }
}

func parseIDs(_ slice: ArraySlice<String>) -> [Int] {
    let ids = slice.compactMap { Int($0) }
    if ids.count != slice.count {
        fail("All ids must be integers. Got: \(slice.joined(separator: " "))")
    }
    if ids.isEmpty { fail("Provide at least one task id.") }
    return ids
}

func prettyJSON(_ text: String) -> String {
    guard let data = text.data(using: .utf8),
          let obj = try? JSONSerialization.jsonObject(with: data),
          let pretty = try? JSONSerialization.data(withJSONObject: obj, options: [.prettyPrinted, .sortedKeys]),
          let out = String(data: pretty, encoding: .utf8)
    else { return text }
    return out
}

func fmtDate(_ date: Date?) -> String {
    guard let date else { return "—" }
    let f = DateFormatter()
    f.dateFormat = "yyyy-MM-dd HH:mm"
    return f.string(from: date)
}

func printTasks(_ tasks: [ReclaimTask]) {
    if tasks.isEmpty { print("(no tasks)"); return }
    print(String(format: "%-10@ %-4@ %-16@ %-7@ %@", "ID" as NSString, "PRI" as NSString,
                 "DUE" as NSString, "STATUS" as NSString, "TITLE" as NSString))
    for t in tasks.sorted(by: { ($0.due ?? .distantFuture) < ($1.due ?? .distantFuture) }) {
        let line = String(
            format: "%-10d %-4@ %-16@ %-7@ %@",
            t.id,
            (t.priorityEnum?.short ?? "—") as NSString,
            fmtDate(t.due) as NSString,
            (t.statusEnum?.rawValue ?? t.status ?? "—") as NSString,
            t.displayTitle
        )
        print(line)
    }
    print("\n\(tasks.count) task(s).")
}

do {
    switch command {
    case "whoami":
        let user = try await client.currentUser()
        print("id:    \(user.id)")
        print("name:  \(user.name ?? "—")")
        print("email: \(user.email ?? "—")")

    case "list":
        let filter = args.count > 1 ? args[1].lowercased() : "active"
        let user = try await client.currentUser()
        let all = try await client.fetchTasks(userId: user.id)
        let filtered: [ReclaimTask]
        switch filter {
        case "active": filtered = all.filter { !$0.isFinished }
        case "overdue": filtered = all.filter { $0.isOverdue }
        case "completed": filtered = all.filter { $0.isFinished }
        case "all": filtered = all
        default: fail("Unknown filter '\(filter)'. Use active|overdue|completed|all.")
        }
        printTasks(filtered)

    case "dump-user":
        let (status, body) = try await client.rawRequest(path: "/api/users/current")
        print("HTTP \(status)\n\(prettyJSON(body))")

    case "dump-tasks":
        let user = try await client.currentUser()
        let (status, body) = try await client.rawRequest(
            path: "/api/tasks",
            query: ReclaimAPIClient.taskListQuery(userId: user.id)
        )
        print("HTTP \(status)\n\(prettyJSON(body))")

    case "raw":
        guard args.count > 1 else { fail("Usage: raw <path>") }
        let (status, body) = try await client.rawRequest(path: args[1])
        print("HTTP \(status)\n\(prettyJSON(body))")

    case "req":
        guard args.count >= 3 else { fail("Usage: req <GET|POST|PATCH|DELETE> <path> [jsonBody]") }
        let method = args[1].uppercased()
        if method != "GET" { requireWrites() }
        let body = args.count > 3 ? args[3].data(using: .utf8) : nil
        let (status, resp) = try await client.rawRequest(method: method, path: args[2], query: nil, body: body)
        print("HTTP \(status)\n\(prettyJSON(resp))")

    case "complete":
        requireWrites()
        let ids = parseIDs(args.dropFirst())
        try await client.bulkComplete(ids: ids)
        print("Completed \(ids.count) task(s): \(ids.map(String.init).joined(separator: ", "))")

    case "priority":
        requireWrites()
        guard args.count > 2, let p = Priority(rawValue: args[1].uppercased()) else {
            fail("Usage: priority <P1|P2|P3|P4> <id> [<id>...]")
        }
        let ids = parseIDs(args.dropFirst(2))
        try await client.bulkReprioritize(ids: ids, to: p)
        print("Set \(ids.count) task(s) to \(p.short).")

    case "upnext":
        requireWrites()
        guard args.count > 2, ["on", "off"].contains(args[1].lowercased()) else {
            fail("Usage: upnext <on|off> <id> [<id>...]")
        }
        let on = args[1].lowercased() == "on"
        let ids = parseIDs(args.dropFirst(2))
        try await client.bulkSetUpNext(ids: ids, onDeck: on)
        print("Set onDeck=\(on) for \(ids.count) task(s).")

    case "delete":
        requireWrites()
        let ids = parseIDs(args.dropFirst())
        try await client.bulkDelete(ids: ids)
        print("Deleted \(ids.count) task(s).")

    default:
        fail("Unknown command '\(command)'. Run with no arguments for help.")
    }
} catch let e as ReclaimAPIError {
    fail(e.localizedDescription)
} catch {
    fail(String(describing: error))
}
