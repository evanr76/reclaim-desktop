import SwiftUI

/// Sheet for creating a new task.
struct TaskCreateView: View {
    @Bindable var vm: TaskListViewModel
    @Environment(\.dismiss) private var dismiss

    @State private var title = ""
    @State private var priority: Priority = .p3
    // Deliberately no due date by default — an unwanted due date defeats
    // Reclaim's own priority-based scheduling. The picker only pre-fills a
    // sensible value (next 6 PM) once the user explicitly turns the toggle on.
    @State private var hasDue = false
    @State private var due: Date = TaskCreateView.defaultDue
    @State private var durationHours: Double = 1

    /// Pre-fill value shown only after the user enables the Due toggle: next 6 PM.
    static var defaultDue: Date {
        let cal = Calendar.current
        let six = cal.date(bySettingHour: 18, minute: 0, second: 0, of: Date()) ?? Date()
        return six > Date() ? six : (cal.date(byAdding: .day, value: 1, to: six) ?? six)
    }

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
