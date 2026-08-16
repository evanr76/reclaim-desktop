import SwiftUI
import AppKit

/// Main window: filter/search toolbar, a multi-select table of tasks, and a
/// bulk-action bar that appears when rows are selected.
struct TaskListView: View {
    @Bindable var vm: TaskListViewModel
    @State private var selection = Set<Int>()
    @State private var editingTask: ReclaimTask?
    @State private var pendingDeleteIDs: [Int]?
    @State private var showReindexConfirm = false
    @State private var showCreate = false
    @State private var sortOrder: [KeyPathComparator<ReclaimTask>] = [KeyPathComparator(\.sortDue)]

    // Column show/hide/reorder state, persisted across launches.
    @State private var columnCustomization = TableColumnCustomization<ReclaimTask>()
    @AppStorage("taskColumnCustomization") private var columnCustomizationData = Data()

    // Inline (Finder-style) rename state.
    @State private var editingID: Int?
    @State private var editText = ""
    @FocusState private var renameFieldFocused: Bool
    // Pending inline rename, used to disambiguate a slow re-click (rename) from a
    // fast double-click (edit sheet) on the already-selected row.
    @State private var pendingRename: DispatchWorkItem?

    // Sort persistence.
    @AppStorage("sortColumn") private var sortColumnID = "due"
    @AppStorage("sortAscending") private var sortAscendingStored = true

    /// Forward comparator per sortable column id (order is applied separately).
    private static let sortComparators: [(id: String, comparator: KeyPathComparator<ReclaimTask>)] = [
        ("title", KeyPathComparator(\.displayTitle)),
        ("priority", KeyPathComparator(\.sortPriorityRank)),
        ("due", KeyPathComparator(\.sortDue)),
        ("duration", KeyPathComparator(\.sortDurationChunks)),
        ("created", KeyPathComparator(\.sortCreated)),
        ("status", KeyPathComparator(\.sortStatusLabel)),
    ]

    private func restoreSort() {
        guard var comp = Self.sortComparators.first(where: { $0.id == sortColumnID })?.comparator else { return }
        comp.order = sortAscendingStored ? .forward : .reverse
        sortOrder = [comp]
    }

    private func persistSort(_ order: [KeyPathComparator<ReclaimTask>]) {
        guard let first = order.first else { return }
        for entry in Self.sortComparators {
            var candidate = entry.comparator
            candidate.order = first.order
            if candidate == first {
                sortColumnID = entry.id
                sortAscendingStored = (first.order == .forward)
                return
            }
        }
    }

    /// Columns the user may hide (Task stays fixed).
    private let optionalColumns: [(id: String, title: String)] = [
        ("priority", "Priority"),
        ("due", "Due"),
        ("duration", "Duration"),
        ("created", "Created"),
        ("status", "Status"),
    ]

    private var selectedIDs: [Int] { Array(selection) }

    var body: some View {
        VStack(spacing: 0) {
            NowNextBanner(current: vm.currentEvent, next: vm.nextEvent)
            filterBar
            Divider()
            table
            if !selection.isEmpty {
                Divider()
                BulkActionBar(
                    vm: vm,
                    selectedIDs: selectedIDs,
                    onEditSingle: { if let id = selection.first { editingTask = vm.task(withID: id) } },
                    onClear: { selection.removeAll() }
                )
            }
            Divider()
            statusBar
        }
        .navigationTitle("Reclaim Tasks")
        .searchable(text: $vm.searchText, placement: .toolbar, prompt: "Search tasks")
        .toolbar { toolbarContent }
        .sheet(item: $editingTask) { task in
            TaskEditView(vm: vm, task: task)
        }
        .sheet(isPresented: $showCreate) {
            TaskCreateView(vm: vm)
        }
        .confirmationDialog(
            "Delete \(pendingDeleteIDs?.count ?? 0) task\((pendingDeleteIDs?.count ?? 0) == 1 ? "" : "s")?",
            isPresented: Binding(
                get: { pendingDeleteIDs != nil },
                set: { if !$0 { pendingDeleteIDs = nil } }
            ),
            titleVisibility: .visible
        ) {
            if let ids = pendingDeleteIDs {
                Button("Delete \(ids.count)", role: .destructive) {
                    advanceSelection(past: Set(ids))
                    Task { await vm.bulkDelete(ids: ids) }
                    pendingDeleteIDs = nil
                }
            }
            Button("Cancel", role: .cancel) { pendingDeleteIDs = nil }
        } message: {
            Text("This permanently deletes from Reclaim and cannot be undone.")
        }
        .confirmationDialog("Reprioritize all tasks by due date?", isPresented: $showReindexConfirm, titleVisibility: .visible) {
            Button("Auto-Prioritize") { Task { await vm.autoPrioritizeByDue() } }
            Button("Cancel", role: .cancel) {}
        } message: {
            Text("Reorders your whole task list so sooner due dates come first.")
        }
        .onAppear {
            if !columnCustomizationData.isEmpty,
               let saved = try? JSONDecoder().decode(
                   TableColumnCustomization<ReclaimTask>.self, from: columnCustomizationData) {
                columnCustomization = saved
            }
            restoreSort()
        }
        .onChange(of: columnCustomization) { _, newValue in
            columnCustomizationData = (try? JSONEncoder().encode(newValue)) ?? Data()
        }
        .onChange(of: sortOrder) { _, newValue in
            persistSort(newValue)
        }
        .task { if vm.allTasks.isEmpty { await vm.loadTasks() } }
    }

    // MARK: Column chooser helpers

    private func columnVisible(_ id: String) -> Binding<Bool> {
        Binding(
            get: { columnCustomization[visibility: id] != .hidden },
            set: { columnCustomization[visibility: id] = $0 ? .visible : .hidden }
        )
    }

    private func resetColumns() {
        columnCustomization = TableColumnCustomization<ReclaimTask>()
    }

    // MARK: Filter bar

    private var filterBar: some View {
        HStack {
            Picker("Filter", selection: $vm.filter) {
                ForEach(TaskFilter.allCases) { f in
                    Text("\(f.rawValue) (\(vm.count(for: f)))").tag(f)
                }
            }
            .pickerStyle(.segmented)
            .labelsHidden()
            .frame(maxWidth: 460)
            Spacer()
        }
        .padding(.horizontal)
        .padding(.vertical, 8)
    }

    // MARK: Table

    /// Tasks currently in "Up Next" (Reclaim's onDeck flag), shown grouped on top.
    private var upNextTasks: [ReclaimTask] {
        vm.filteredTasks.filter { $0.onDeck == true }.sorted(using: sortOrder)
    }
    private var otherTasks: [ReclaimTask] {
        vm.filteredTasks.filter { !($0.onDeck ?? false) }.sorted(using: sortOrder)
    }

    private var table: some View {
        Table(of: ReclaimTask.self,
              selection: $selection,
              sortOrder: $sortOrder,
              columnCustomization: $columnCustomization) {
            TableColumn("Task", value: \.displayTitle) { taskCell($0) }
                .width(min: 220, ideal: 340)
                .customizationID("task")
                .disabledCustomizationBehavior(.visibility)   // Task can't be hidden
            TableColumn("Priority", value: \.sortPriorityRank) { priorityCell($0) }
                .width(70)
                .customizationID("priority")
            TableColumn("Due", value: \.sortDue) { task in
                Text(Fmt.day(task.due)).foregroundStyle(task.isOverdue ? .red : .primary)
            }
            .width(min: 90, ideal: 120)
            .customizationID("due")
            TableColumn("Duration", value: \.sortDurationChunks) { task in
                Text(Fmt.duration(task.durationHours)).foregroundStyle(.secondary)
            }
            .width(80)
            .customizationID("duration")
            TableColumn("Created", value: \.sortCreated) { task in
                Text(Fmt.day(task.created)).foregroundStyle(.secondary)
            }
            .width(min: 90, ideal: 120)
            .customizationID("created")
            TableColumn("Status", value: \.sortStatusLabel) { task in
                Text(task.statusEnum?.label ?? (task.status ?? "—"))
                    .font(.caption).foregroundStyle(.secondary)
            }
            .width(min: 90, ideal: 110)
            .customizationID("status")
        } rows: {
            if upNextTasks.isEmpty {
                ForEach(otherTasks) { TableRow($0) }
            } else {
                Section("⚡︎ Up Next") {
                    ForEach(upNextTasks) { TableRow($0) }
                }
                Section("Tasks") {
                    ForEach(otherTasks) { TableRow($0) }
                }
            }
        }
        .contextMenu(forSelectionType: Int.self) { ids in
            rowContextMenu(for: ids)
        } primaryAction: { ids in
            pendingRename?.cancel()   // a double-click opens the sheet, not a rename
            if let id = ids.first { editingTask = vm.task(withID: id) }
        }
        .overlay {
            if vm.filteredTasks.isEmpty { emptyState }
        }
        // Focus-scoped shortcuts: only fire when the table has key focus, so
        // they don't hijack typing in the search field or a sheet.
        .onDeleteCommand {
            guard editingID == nil, !selection.isEmpty else { return }
            pendingDeleteIDs = Array(selection)   // routes through the confirm dialog
        }
        .onKeyPress(characters: CharacterSet(charactersIn: "eE"), phases: .down) { _ in
            guard editingID == nil, !selection.isEmpty else { return .ignored }
            let ids = Array(selection)
            advanceSelection(past: Set(ids))
            Task { await vm.bulkComplete(ids: ids) }
            return .handled
        }
        .onKeyPress(characters: CharacterSet(charactersIn: "uU"), phases: .down) { _ in
            guard editingID == nil else { return .ignored }
            let finishedIDs = selection.compactMap { vm.task(withID: $0) }
                .filter(\.isFinished).map(\.id)
            guard !finishedIDs.isEmpty else { return .ignored }
            Task { for id in finishedIDs { await vm.markIncomplete(id: id) } }
            return .handled
        }
    }

    @ViewBuilder
    private func taskCell(_ task: ReclaimTask) -> some View {
        VStack(alignment: .leading, spacing: 2) {
            HStack(spacing: 6) {
                if task.statusEnum == .inProgress {
                    Image(systemName: "record.circle")
                        .foregroundStyle(.green).font(.caption)
                }
                if task.onDeck == true {
                    Image(systemName: "bolt.fill")
                        .foregroundStyle(.yellow).font(.caption)
                }
                if task.isOverdue {
                    Image(systemName: "exclamationmark.triangle.fill")
                        .foregroundStyle(.red).font(.caption)
                }
                if task.atRisk == true && !task.isFinished {
                    Image(systemName: "exclamationmark.triangle.fill")
                        .foregroundStyle(.orange).font(.caption)
                }
                if task.isSnoozed {
                    Image(systemName: "moon.zzz.fill")
                        .foregroundStyle(.secondary).font(.caption)
                }
                if editingID == task.id {
                    TextField("Title", text: $editText)
                        .textFieldStyle(.plain)
                        .focused($renameFieldFocused)
                        .onSubmit { commitRename(task) }
                        .onExitCommand { editingID = nil }   // Esc cancels
                        .onChange(of: renameFieldFocused) { _, focused in
                            if !focused && editingID == task.id { commitRename(task) }
                        }
                        .onAppear { renameFieldFocused = true }
                } else {
                    let label = Text(task.displayTitle)
                        .lineLimit(1)
                        .strikethrough(task.isFinished, color: .secondary)
                        .foregroundStyle(task.isFinished ? .secondary : .primary)
                    // Only the already-selected single row carries the rename
                    // gesture; unselected rows stay gesture-free so normal table
                    // selection isn't blocked.
                    if selection == [task.id] {
                        label
                            .contentShape(Rectangle())
                            .simultaneousGesture(TapGesture().onEnded { scheduleRename(task) })
                    } else {
                        label
                    }
                }
            }
            if let notes = task.notes, !notes.isEmpty {
                Text(notes).font(.caption).foregroundStyle(.secondary).lineLimit(1)
            }
        }
    }

    // MARK: - Inline rename

    /// Finder-style: a click on the already-selected row begins an inline rename,
    /// but only after the double-click window passes — a fast double-click cancels
    /// this (via `primaryAction`) and opens the edit sheet instead.
    private func scheduleRename(_ task: ReclaimTask) {
        pendingRename?.cancel()
        let work = DispatchWorkItem {
            if editingID == nil { startRename(task) }
        }
        pendingRename = work
        DispatchQueue.main.asyncAfter(deadline: .now() + NSEvent.doubleClickInterval + 0.06, execute: work)
    }

    private func startRename(_ task: ReclaimTask) {
        pendingRename?.cancel()
        editText = task.title ?? ""
        editingID = task.id
    }

    private func commitRename(_ task: ReclaimTask) {
        let newTitle = editText.trimmingCharacters(in: .whitespacesAndNewlines)
        editingID = nil
        guard !newTitle.isEmpty, newTitle != (task.title ?? "") else { return }
        Task { await vm.updateTask(id: task.id, patch: ["title": newTitle]) }
    }

    // MARK: - Selection advancement

    /// After acting on `acted`, select the next surviving row (or the previous one
    /// if the acted rows were last), matching Finder/Mail behavior.
    private func advanceSelection(past acted: Set<Int>) {
        if let next = nextSelectionID(after: acted) {
            selection = [next]
        } else {
            selection.removeAll()
        }
    }

    private func nextSelectionID(after acted: Set<Int>) -> Int? {
        let displayed = upNextTasks + otherTasks
        let indices = displayed.indices.filter { acted.contains(displayed[$0].id) }
        guard let first = indices.first, let last = indices.last else { return nil }
        if let next = displayed[(last + 1)...].first(where: { !acted.contains($0.id) }) {
            return next.id
        }
        if let prev = displayed[..<first].last(where: { !acted.contains($0.id) }) {
            return prev.id
        }
        return nil
    }

    @ViewBuilder
    private func priorityCell(_ task: ReclaimTask) -> some View {
        if let p = task.priorityEnum {
            Text(p.short)
                .font(.caption.bold())
                .padding(.horizontal, 6).padding(.vertical, 2)
                .background(p.color.opacity(0.18), in: Capsule())
                .foregroundStyle(p.color)
        } else {
            Text("—").foregroundStyle(.secondary)
        }
    }

    @ViewBuilder
    private func rowContextMenu(for ids: Set<Int>) -> some View {
        let list = Array(ids)
        Button(ids.count == 1 ? "Copy Description" : "Copy \(ids.count) Descriptions") {
            copyDescriptions(for: ids)
        }
        .keyboardShortcut("c", modifiers: .command)
        Divider()
        if list.count == 1, let task = vm.task(withID: list[0]) {
            Button("Edit…") { editingTask = task }
            Button("Rename") { startRename(task) }
            if task.isFinished {
                Button("Reopen") { Task { await vm.markIncomplete(id: task.id) } }
            } else {
                Button("Mark Complete") {
                    advanceSelection(past: [task.id])
                    Task { await vm.markComplete(id: task.id) }
                }
                if task.statusEnum == .inProgress {
                    Button("Stop Working") { Task { await vm.stopTask(id: task.id) } }
                } else {
                    Button("Start Working") { Task { await vm.startTask(id: task.id) } }
                }
            }
            Divider()
        }
        Button("Mark \(list.count) Complete") {
            advanceSelection(past: Set(list))
            Task { await vm.bulkComplete(ids: list) }
        }
        Menu("Set Priority") {
            ForEach(Priority.allCases) { p in
                Button(p.label) { Task { await vm.bulkReprioritize(ids: list, to: p) } }
            }
        }
        let allUpNext = list.allSatisfy { vm.task(withID: $0)?.onDeck == true }
        if allUpNext {
            Button("Remove from Up Next") { Task { await vm.bulkSetUpNext(ids: list, onDeck: false) } }
        } else {
            Button("Move to Up Next") { Task { await vm.bulkSetUpNext(ids: list, onDeck: true) } }
        }
        Divider()
        Button("Delete \(list.count)…", role: .destructive) {
            pendingDeleteIDs = list
        }
    }

    /// Copy the selected tasks' descriptions (titles) to the clipboard, one per
    /// line, preserving the on-screen order.
    private func copyDescriptions(for ids: Set<Int>) {
        let ordered = (upNextTasks + otherTasks).filter { ids.contains($0.id) }
        let text = ordered.map(\.displayTitle).joined(separator: "\n")
        guard !text.isEmpty else { return }
        NSPasteboard.general.clearContents()
        NSPasteboard.general.setString(text, forType: .string)
    }

    private var emptyState: some View {
        ContentUnavailableView {
            Label(vm.isLoading ? "Loading…" : "No tasks", systemImage: vm.filter.systemImage)
        } description: {
            Text(vm.isLoading ? "Fetching your Reclaim tasks." : "Nothing matches the current filter.")
        }
    }

    // MARK: Status bar

    private var statusBar: some View {
        HStack(spacing: 12) {
            if vm.isLoading || vm.isBusy {
                ProgressView().controlSize(.small)
            }
            if let error = vm.errorMessage {
                Label(error, systemImage: "exclamationmark.triangle.fill")
                    .foregroundStyle(.red).lineLimit(1)
            } else if let status = vm.statusMessage {
                Text(status).foregroundStyle(.secondary)
            }
            Spacer()
            if !selection.isEmpty {
                Text("\(selection.count) selected").foregroundStyle(.secondary)
            }
            if let refreshed = vm.lastRefreshed {
                Text("Updated \(Fmt.relative(refreshed))").foregroundStyle(.tertiary)
            }
            Text("· \(BuildInfo.label)")
                .font(.caption2)
                .foregroundStyle(.tertiary)
                .help("Build identifier")
        }
        .font(.caption)
        .padding(.horizontal)
        .padding(.vertical, 6)
    }

    // MARK: Toolbar

    @ToolbarContentBuilder
    private var toolbarContent: some ToolbarContent {
        ToolbarItem(placement: .primaryAction) {
            Button { showCreate = true } label: { Image(systemName: "plus") }
                .keyboardShortcut("n", modifiers: .command)
                .help("New Task")
                .disabled(!vm.isConfigured)
        }
        ToolbarItem(placement: .primaryAction) {
            Menu {
                Section("Show Columns") {
                    ForEach(optionalColumns, id: \.id) { col in
                        Toggle(col.title, isOn: columnVisible(col.id))
                    }
                }
                Divider()
                Button("Reset to Defaults") { resetColumns() }
            } label: {
                Image(systemName: "slider.horizontal.3")
            }
            .help("Choose columns")
        }
        ToolbarItem(placement: .primaryAction) {
            Button {
                Task { await vm.loadTasks() }
            } label: {
                Image(systemName: "arrow.clockwise")
            }
            .help("Refresh")
            .disabled(vm.isLoading)
        }
        ToolbarItem(placement: .primaryAction) {
            Menu {
                if let user = vm.user {
                    Text(user.displayName)
                    Divider()
                }
                Button("Auto-Prioritize by Due…") { showReindexConfirm = true }
                Divider()
                SettingsLink {
                    Label("Settings…", systemImage: "gearshape")
                }
                Button("Sign Out", role: .destructive) { vm.signOut() }
            } label: {
                Image(systemName: "person.crop.circle")
            }
        }
    }
}
