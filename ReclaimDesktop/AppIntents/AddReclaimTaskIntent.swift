import AppIntents
import Foundation

extension Notification.Name {
    /// Posted (in-process) after the App Intent creates a task, so a running
    /// window can refresh its list.
    static let reclaimTaskCreated = Notification.Name("ReclaimTaskCreated")
}

/// Priority as an `AppEnum` so it can be a picker in Shortcuts / a spoken choice.
enum TaskPriorityAppEnum: String, AppEnum {
    case highest, high, normal, low

    static let typeDisplayRepresentation: TypeDisplayRepresentation = "Priority"
    static let caseDisplayRepresentations: [TaskPriorityAppEnum: DisplayRepresentation] = [
        .highest: "P1 — Highest",
        .high: "P2 — High",
        .normal: "P3 — Medium",
        .low: "P4 — Low",
    ]

    var toPriority: Priority {
        switch self {
        case .highest: return .p1
        case .high: return .p2
        case .normal: return .p3
        case .low: return .p4
        }
    }
}

/// Errors the intent can speak back through Siri.
enum ReclaimIntentError: Error, CustomLocalizedStringResourceConvertible {
    case notConfigured

    var localizedStringResource: LocalizedStringResource {
        switch self {
        case .notConfigured:
            return "Open Reclaim Desktop and add your API key before adding tasks by voice."
        }
    }
}

/// Creates a Reclaim task. Exposed to Siri, Spotlight, and the Shortcuts app.
struct AddReclaimTaskIntent: AppIntent {
    static let title: LocalizedStringResource = "Add Reclaim Task"
    static let description = IntentDescription("Create a new task in Reclaim.")

    /// Open the app to service the intent. Ad-hoc-signed apps can't reliably run
    /// intents in the background ("could not communicate with the app"); opening
    /// the app runs `perform()` in the foreground process, which works.
    static let openAppWhenRun = true

    @Parameter(title: "Task", requestValueDialog: "What's the task?")
    var taskTitle: String

    @Parameter(title: "Priority", default: .normal)
    var priority: TaskPriorityAppEnum

    @Parameter(title: "Duration (hours)", default: 1.0,
               inclusiveRange: (0.25, 40.0))
    var durationHours: Double

    @Parameter(title: "Due Date")
    var due: Date?

    static var parameterSummary: some ParameterSummary {
        Summary("Add \(\.$taskTitle) to Reclaim") {
            \.$priority
            \.$durationHours
            \.$due
        }
    }

    @MainActor
    func perform() async throws -> some IntentResult & ProvidesDialog {
        guard let token = KeychainStore.readToken() else {
            throw ReclaimIntentError.notConfigured
        }
        let client = ReclaimAPIClient(token: token)
        let created = try await client.createTask(
            title: taskTitle,
            priority: priority.toPriority,
            durationHours: durationHours,
            due: due
        )
        NotificationCenter.default.post(name: .reclaimTaskCreated, object: nil)
        return .result(dialog: "Added “\(created.displayTitle)” to Reclaim.")
    }
}

/// Registers the spoken phrases with Siri and Spotlight.
struct ReclaimShortcuts: AppShortcutsProvider {
    static var appShortcuts: [AppShortcut] {
        AppShortcut(
            intent: AddReclaimTaskIntent(),
            phrases: [
                "Add a task to \(.applicationName)",
                "Add a \(.applicationName) task",
                "Create a \(.applicationName) task",
                "New task in \(.applicationName)",
            ],
            shortTitle: "Add Task",
            systemImageName: "plus.circle.fill"
        )
    }
}
