import SwiftUI
import Observation

/// Which slice of tasks to show.
enum TaskFilter: String, CaseIterable, Identifiable {
    case active = "Active"
    case overdue = "Overdue"
    case completed = "Completed"
    case all = "All"

    var id: String { rawValue }
    var systemImage: String {
        switch self {
        case .active: return "circle"
        case .overdue: return "exclamationmark.triangle"
        case .completed: return "checkmark.circle"
        case .all: return "tray.full"
        }
    }
}

/// Owns app state: auth/token, the task list, filters, and every mutating
/// operation. Views bind to this and call its async methods.
@MainActor
@Observable
final class TaskListViewModel {
    // Auth
    private(set) var isConfigured: Bool = false
    private(set) var user: ReclaimUser?
    private var client: ReclaimAPIClient?

    // Data
    private(set) var allTasks: [ReclaimTask] = []
    private(set) var lastRefreshed: Date?

    // UI state
    var filter: TaskFilter = .active
    var searchText: String = ""
    private(set) var isLoading = false
    private(set) var isBusy = false
    var errorMessage: String?
    var statusMessage: String?

    init() {
        if let token = KeychainStore.readToken() {
            client = ReclaimAPIClient(token: token)
            isConfigured = true
        }
        // Refresh when the Siri/Shortcuts/Spotlight intent adds a task in-process.
        NotificationCenter.default.addObserver(
            forName: .reclaimTaskCreated, object: nil, queue: .main
        ) { [weak self] _ in
            Task { @MainActor in await self?.loadTasks() }
        }
    }

    // MARK: - Derived list

    var filteredTasks: [ReclaimTask] {
        let base: [ReclaimTask]
        switch filter {
        case .active: base = allTasks.filter { !$0.isFinished }
        case .overdue: base = allTasks.filter { $0.isOverdue }
        case .completed: base = allTasks.filter { $0.isFinished }
        case .all: base = allTasks
        }

        let query = searchText.trimmingCharacters(in: .whitespacesAndNewlines).lowercased()
        let searched = query.isEmpty ? base : base.filter {
            $0.displayTitle.lowercased().contains(query)
                || ($0.notes?.lowercased().contains(query) ?? false)
        }

        return searched.sorted(by: Self.defaultSort)
    }

    /// Count badges for the filter picker.
    func count(for filter: TaskFilter) -> Int {
        switch filter {
        case .active: return allTasks.filter { !$0.isFinished }.count
        case .overdue: return allTasks.filter { $0.isOverdue }.count
        case .completed: return allTasks.filter { $0.isFinished }.count
        case .all: return allTasks.count
        }
    }

    /// Overdue first, then by due date (soonest first, undated last),
    /// then by priority.
    private static func defaultSort(_ a: ReclaimTask, _ b: ReclaimTask) -> Bool {
        switch (a.due, b.due) {
        case let (da?, db?) where da != db: return da < db
        case (nil, .some): return false
        case (.some, nil): return true
        default: break
        }
        let pa = a.priorityEnum ?? .p3
        let pb = b.priorityEnum ?? .p3
        if pa != pb { return pa < pb }
        return a.id < b.id
    }

    func task(withID id: Int) -> ReclaimTask? { allTasks.first { $0.id == id } }

    // MARK: - Auth lifecycle

    /// Save a token, verify it against the API, then load tasks.
    func saveToken(_ raw: String) async {
        let trimmed = raw.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else {
            errorMessage = "Please enter your Reclaim API key."
            return
        }
        let candidate = ReclaimAPIClient(token: trimmed)
        isBusy = true
        defer { isBusy = false }
        do {
            let me = try await candidate.currentUser()
            guard KeychainStore.saveToken(trimmed) else {
                errorMessage = "Could not save the key to the Keychain."
                return
            }
            client = candidate
            user = me
            isConfigured = true
            errorMessage = nil
            statusMessage = "Connected as \(me.displayName)."
            await loadTasks()
        } catch {
            errorMessage = (error as? ReclaimAPIError)?.localizedDescription ?? error.localizedDescription
        }
    }

    /// Forget the token and reset state.
    func signOut() {
        KeychainStore.deleteToken()
        client = nil
        user = nil
        isConfigured = false
        allTasks = []
        lastRefreshed = nil
        statusMessage = "Signed out."
    }

    // MARK: - Loading

    func loadTasks() async {
        guard let client else { isConfigured = false; return }
        isLoading = true
        defer { isLoading = false }
        do {
            if user == nil { user = try await client.currentUser() }
            guard let userId = user?.id else {
                errorMessage = "Could not determine the current user."
                return
            }
            allTasks = try await client.fetchTasks(userId: userId)
            lastRefreshed = Date()
            errorMessage = nil
        } catch let apiError as ReclaimAPIError {
            if case .unauthorized = apiError {
                // Bad/expired token: drop back to onboarding.
                signOut()
                errorMessage = apiError.localizedDescription
            } else {
                errorMessage = apiError.localizedDescription
            }
        } catch {
            errorMessage = error.localizedDescription
        }
    }

    // MARK: - Bulk mutations

    // Complete/delete apply their result locally and skip the immediate refetch:
    // Reclaim's archive/delete is eventually-consistent, so a refetch right after
    // would return stale rows and the tasks would visibly reappear.

    func bulkComplete(ids: [Int]) async {
        await mutate("Completed \(ids.count) task(s).",
                     optimistic: { self.applyArchived(ids: ids) },
                     reload: false) { try await $0.bulkComplete(ids: ids) }
    }

    func bulkDelete(ids: [Int]) async {
        await mutate("Deleted \(ids.count) task(s).",
                     optimistic: { self.removeTasks(ids: ids) },
                     reload: false) { try await $0.bulkDelete(ids: ids) }
    }

    func bulkReprioritize(ids: [Int], to priority: Priority) async {
        await mutate("Set \(ids.count) task(s) to \(priority.short).",
                     optimistic: { self.apply(ids: ids) { $0.priority = priority.rawValue } }) {
            try await $0.bulkReprioritize(ids: ids, to: priority)
        }
    }

    func bulkReschedule(ids: [Int], due: Date?) async {
        let verb = due == nil ? "Cleared due date on" : "Rescheduled"
        await mutate("\(verb) \(ids.count) task(s).",
                     optimistic: { self.apply(ids: ids) { $0.due = due } }) {
            try await $0.bulkReschedule(ids: ids, due: due)
        }
    }

    func bulkSnooze(ids: [Int], until: Date?) async {
        let verb = until == nil ? "Cleared snooze on" : "Snoozed"
        await mutate("\(verb) \(ids.count) task(s).",
                     optimistic: { self.apply(ids: ids) { $0.snoozeUntil = until } }) {
            try await $0.bulkSnooze(ids: ids, until: until)
        }
    }

    /// Move tasks into / out of "Up Next" (Reclaim's `onDeck` flag).
    func bulkSetUpNext(ids: [Int], onDeck: Bool) async {
        let verb = onDeck ? "Moved \(ids.count) task(s) to Up Next." : "Removed \(ids.count) task(s) from Up Next."
        await mutate(verb,
                     optimistic: { self.apply(ids: ids) { $0.onDeck = onDeck } }) {
            try await $0.bulkSetUpNext(ids: ids, onDeck: onDeck)
        }
    }

    // MARK: - Single-task mutations

    func markComplete(id: Int) async {
        await mutate("Completed task.",
                     optimistic: { self.applyArchived(ids: [id]) },
                     reload: false) { try await $0.markComplete(id: id) }
    }

    func markIncomplete(id: Int) async {
        await mutate("Reopened task.",
                     optimistic: { self.apply(ids: [id]) { $0.status = TaskStatus.scheduled.rawValue; $0.finished = nil } }) {
            try await $0.markIncomplete(id: id)
        }
    }

    /// Apply an edit sheet's field changes to a single task.
    func updateTask(id: Int, patch: [String: Any]) async {
        guard !patch.isEmpty else { return }
        await mutate("Saved changes.") { try await $0.updateTask(id: id, patch: patch) }
    }

    // MARK: - Optimistic local edits

    /// Mutate the matching tasks in `allTasks` in place.
    private func apply(ids: [Int], _ transform: (inout ReclaimTask) -> Void) {
        let set = Set(ids)
        for i in allTasks.indices where set.contains(allTasks[i].id) {
            transform(&allTasks[i])
        }
    }

    private func applyArchived(ids: [Int]) {
        apply(ids: ids) { $0.status = TaskStatus.archived.rawValue; $0.onDeck = false; $0.finished = Date() }
    }

    private func removeTasks(ids: [Int]) {
        let set = Set(ids)
        allTasks.removeAll { set.contains($0.id) }
    }

    /// Shared wrapper: optimistically update, run the call, optionally refetch,
    /// and revert on failure.
    private func mutate(
        _ successMessage: String,
        optimistic: (() -> Void)? = nil,
        reload: Bool = true,
        _ op: (ReclaimAPIClient) async throws -> Void
    ) async {
        guard let client else { errorMessage = ReclaimAPIError.noToken.localizedDescription; return }
        isBusy = true
        defer { isBusy = false }
        let snapshot = allTasks
        optimistic?()
        do {
            try await op(client)
            statusMessage = successMessage
            errorMessage = nil
            if reload { await loadTasks() }
        } catch let apiError as ReclaimAPIError {
            allTasks = snapshot
            errorMessage = apiError.localizedDescription
        } catch {
            allTasks = snapshot
            errorMessage = error.localizedDescription
        }
    }
}
