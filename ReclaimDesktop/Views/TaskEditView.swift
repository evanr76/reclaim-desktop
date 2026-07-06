import SwiftUI

/// Sheet for editing a single task's core fields. Builds a minimal patch and
/// sends it via `PATCH /api/tasks/{id}`.
struct TaskEditView: View {
    @Bindable var vm: TaskListViewModel
    let task: ReclaimTask
    @Environment(\.dismiss) private var dismiss

    @State private var title: String
    @State private var notes: String
    @State private var priority: Priority
    @State private var hasDue: Bool
    @State private var due: Date
    @State private var durationHours: Double

    init(vm: TaskListViewModel, task: ReclaimTask) {
        self.vm = vm
        self.task = task
        _title = State(initialValue: task.title ?? "")
        _notes = State(initialValue: task.notes ?? "")
        _priority = State(initialValue: task.priorityEnum ?? .p3)
        _hasDue = State(initialValue: task.due != nil)
        _due = State(initialValue: task.due ?? Date())
        _durationHours = State(initialValue: task.durationHours ?? 1)
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            Text("Edit Task").font(.title2.bold()).padding()
            Divider()

            Form {
                TextField("Title", text: $title)

                Section("Notes") {
                    TextEditor(text: $notes)
                        .frame(minHeight: 70)
                        .font(.body)
                }

                Picker("Priority", selection: $priority) {
                    ForEach(Priority.allCases) { p in Text(p.label).tag(p) }
                }

                Toggle("Due date", isOn: $hasDue)
                if hasDue {
                    DatePicker("Due", selection: $due, displayedComponents: [.date, .hourAndMinute])
                }

                Stepper(value: $durationHours, in: 0.25...40, step: 0.25) {
                    HStack {
                        Text("Duration")
                        Spacer()
                        Text(Fmt.duration(durationHours)).foregroundStyle(.secondary)
                    }
                }
            }
            .formStyle(.grouped)

            Divider()
            HStack {
                Spacer()
                Button("Cancel") { dismiss() }.keyboardShortcut(.cancelAction)
                Button("Save") { save() }
                    .keyboardShortcut(.defaultAction)
                    .buttonStyle(.borderedProminent)
                    .disabled(title.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty)
            }
            .padding()
        }
        .frame(width: 460, height: 520)
    }

    private func save() {
        var patch: [String: Any] = [
            "title": title.trimmingCharacters(in: .whitespacesAndNewlines),
            "notes": notes,
            "priority": priority.rawValue,
            "timeChunksRequired": Int((durationHours * 4).rounded()),
        ]
        patch["due"] = hasDue ? ReclaimAPIClient.isoString(due) : NSNull()

        Task {
            await vm.updateTask(id: task.id, patch: patch)
            dismiss()
        }
    }
}
