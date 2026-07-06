import SwiftUI

/// Action bar shown while one or more tasks are selected. This is the heart of
/// the app: every control here operates on the whole selection at once.
struct BulkActionBar: View {
    @Bindable var vm: TaskListViewModel
    let selectedIDs: [Int]
    var onEditSingle: () -> Void
    var onClear: () -> Void

    @State private var showDeleteConfirm = false
    @State private var showReschedule = false
    @State private var showSnoozeCustom = false
    @State private var rescheduleDate = Date()
    @State private var snoozeDate = Date()

    private var count: Int { selectedIDs.count }

    var body: some View {
        HStack(spacing: 10) {
            Text("\(count) selected").font(.callout.weight(.medium))

            Divider().frame(height: 18)

            Button {
                run { await vm.bulkComplete(ids: selectedIDs) }
            } label: { Label("Complete", systemImage: "checkmark.circle") }

            Menu {
                ForEach(Priority.allCases) { p in
                    Button(p.label) { run { await vm.bulkReprioritize(ids: selectedIDs, to: p) } }
                }
            } label: { Label("Priority", systemImage: "flag") }
            .menuStyle(.borderlessButton)
            .fixedSize()

            Button {
                showReschedule = true
            } label: { Label("Reschedule", systemImage: "calendar") }
            .popover(isPresented: $showReschedule, arrowEdge: .bottom) {
                datePopover(
                    title: "Set due date",
                    selection: $rescheduleDate,
                    apply: { run { await vm.bulkReschedule(ids: selectedIDs, due: rescheduleDate) } },
                    clear: { run { await vm.bulkReschedule(ids: selectedIDs, due: nil) } },
                    clearLabel: "Clear due date"
                )
            }

            Menu {
                Button("Tomorrow morning") { snooze(to: Self.tomorrowMorning()) }
                Button("In 2 days") { snooze(to: Self.inDays(2)) }
                Button("Next week") { snooze(to: Self.nextMonday()) }
                Divider()
                Button("Custom…") { showSnoozeCustom = true }
                Button("Clear snooze") { run { await vm.bulkSnooze(ids: selectedIDs, until: nil) } }
            } label: { Label("Snooze", systemImage: "moon.zzz") }
            .menuStyle(.borderlessButton)
            .fixedSize()
            .popover(isPresented: $showSnoozeCustom, arrowEdge: .bottom) {
                datePopover(
                    title: "Snooze until",
                    selection: $snoozeDate,
                    apply: { run { await vm.bulkSnooze(ids: selectedIDs, until: snoozeDate) } },
                    clear: nil,
                    clearLabel: nil
                )
            }

            Menu {
                Button("Move to Up Next", systemImage: "bolt.fill") {
                    run { await vm.bulkSetUpNext(ids: selectedIDs, onDeck: true) }
                }
                Button("Remove from Up Next", systemImage: "bolt.slash") {
                    run { await vm.bulkSetUpNext(ids: selectedIDs, onDeck: false) }
                }
            } label: { Label("Up Next", systemImage: "bolt") }
            .menuStyle(.borderlessButton)
            .fixedSize()

            if count == 1 {
                Button {
                    onEditSingle()
                } label: { Label("Edit", systemImage: "pencil") }
            }

            Spacer()

            Button(role: .destructive) {
                showDeleteConfirm = true
            } label: { Label("Delete", systemImage: "trash") }
            .confirmationDialog(
                "Delete \(count) task\(count == 1 ? "" : "s")? This cannot be undone.",
                isPresented: $showDeleteConfirm,
                titleVisibility: .visible
            ) {
                Button("Delete \(count)", role: .destructive) {
                    run { await vm.bulkDelete(ids: selectedIDs) }
                }
                Button("Cancel", role: .cancel) {}
            }

            Button("Clear") { onClear() }
                .buttonStyle(.borderless)
        }
        .buttonStyle(.bordered)
        .padding(.horizontal)
        .padding(.vertical, 8)
        .disabled(vm.isBusy)
    }

    // MARK: Helpers

    private func datePopover(
        title: String,
        selection: Binding<Date>,
        apply: @escaping () -> Void,
        clear: (() -> Void)?,
        clearLabel: String?
    ) -> some View {
        VStack(alignment: .leading, spacing: 12) {
            Text(title).font(.headline)
            DatePicker("", selection: selection, displayedComponents: [.date, .hourAndMinute])
                .datePickerStyle(.graphical)
                .labelsHidden()
            HStack {
                if let clear, let clearLabel {
                    Button(clearLabel, role: .destructive) {
                        clear()
                        dismissPopovers()
                    }
                }
                Spacer()
                Button("Apply") {
                    apply()
                    dismissPopovers()
                }
                .keyboardShortcut(.defaultAction)
            }
        }
        .padding()
        .frame(width: 320)
    }

    private func snooze(to date: Date) {
        run { await vm.bulkSnooze(ids: selectedIDs, until: date) }
    }

    private func run(_ op: @escaping () async -> Void) {
        Task {
            await op()
            onClear()
        }
    }

    private func dismissPopovers() {
        showReschedule = false
        showSnoozeCustom = false
    }

    // MARK: Date presets

    private static func tomorrowMorning() -> Date {
        let cal = Calendar.current
        let tomorrow = cal.date(byAdding: .day, value: 1, to: Date()) ?? Date()
        return cal.date(bySettingHour: 9, minute: 0, second: 0, of: tomorrow) ?? tomorrow
    }

    private static func inDays(_ days: Int) -> Date {
        let cal = Calendar.current
        let d = cal.date(byAdding: .day, value: days, to: Date()) ?? Date()
        return cal.date(bySettingHour: 9, minute: 0, second: 0, of: d) ?? d
    }

    private static func nextMonday() -> Date {
        let cal = Calendar.current
        var date = Date()
        for _ in 0..<8 {
            date = cal.date(byAdding: .day, value: 1, to: date) ?? date
            if cal.component(.weekday, from: date) == 2 { break } // Monday
        }
        return cal.date(bySettingHour: 9, minute: 0, second: 0, of: date) ?? date
    }
}
