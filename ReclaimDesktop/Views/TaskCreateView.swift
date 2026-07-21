import SwiftUI

/// Sheet for creating a new task.
struct TaskCreateView: View {
    @Bindable var vm: TaskListViewModel
    @Environment(\.dismiss) private var dismiss

    @State private var title = ""
    @State private var priority: Priority = .p3
    @State private var hasDue = false
    @State private var due = Date()
    @State private var durationHours: Double = 1

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            Text("New Task").font(.title2.bold()).padding()
            Divider()

            Form {
                TextField("Title", text: $title)
                Picker("Priority", selection: $priority) {
                    ForEach(Priority.allCases) { p in Text(p.label).tag(p) }
                }
                Toggle("Due date", isOn: $hasDue)
                if hasDue {
                    DatePicker("Due", selection: $due, displayedComponents: [.date, .hourAndMinute])
                }
                Stepper(value: $durationHours, in: 0.25...40, step: 0.25) {
                    HStack { Text("Duration"); Spacer(); Text(Fmt.duration(durationHours)).foregroundStyle(.secondary) }
                }
            }
            .formStyle(.grouped)

            Divider()
            HStack {
                Spacer()
                Button("Cancel") { dismiss() }.keyboardShortcut(.cancelAction)
                Button("Add") {
                    let t = title.trimmingCharacters(in: .whitespacesAndNewlines)
                    Task {
                        await vm.createTask(title: t, priority: priority, durationHours: durationHours, due: hasDue ? due : nil)
                        dismiss()
                    }
                }
                .keyboardShortcut(.defaultAction)
                .buttonStyle(.borderedProminent)
                .disabled(title.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty)
            }
            .padding()
        }
        .frame(width: 460, height: 420)
    }
}
