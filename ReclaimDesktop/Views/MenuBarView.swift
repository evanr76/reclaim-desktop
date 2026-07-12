import SwiftUI
import AppKit

/// Menu-bar glance: Up Next + highest-priority unfinished tasks (up to 5),
/// with quick-complete and a shortcut to the main window.
struct MenuBarView: View {
    @Bindable var vm: TaskListViewModel
    @Environment(\.openWindow) private var openWindow
    @AppStorage("appearance") private var appearanceRaw = AppAppearance.system.rawValue

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            HStack {
                Text("Reclaim Tasks").font(.headline)
                Spacer()
                if vm.isLoading || vm.isBusy { ProgressView().controlSize(.small) }
                Button {
                    Task { await vm.loadTasks() }
                } label: { Image(systemName: "arrow.clockwise") }
                    .buttonStyle(.borderless)
                    .help("Refresh")
                    .disabled(!vm.isConfigured)
            }

            Divider()

            if !vm.isConfigured {
                message("Not connected. Open the app to add your API key.")
            } else if vm.menuBarTasks.isEmpty {
                message("Nothing up next. 🎉")
            } else {
                ForEach(vm.menuBarTasks) { task in
                    MenuBarRow(task: task, vm: vm)
                }
            }

            Divider()

            HStack {
                Button("Open Reclaim Tasks") {
                    NSApp.activate(ignoringOtherApps: true)
                    openWindow(id: "main")
                }
                .buttonStyle(.borderless)
                Spacer()
                if let refreshed = vm.lastRefreshed {
                    Text(Fmt.relative(refreshed)).font(.caption2).foregroundStyle(.tertiary)
                }
            }
        }
        .padding(12)
        .frame(width: 320)
        .preferredColorScheme(AppAppearance(rawValue: appearanceRaw)?.colorScheme)
        .task { if vm.isConfigured && vm.allTasks.isEmpty { await vm.loadTasks() } }
    }

    private func message(_ text: String) -> some View {
        Text(text)
            .font(.callout)
            .foregroundStyle(.secondary)
            .frame(maxWidth: .infinity, alignment: .leading)
            .padding(.vertical, 4)
    }
}

private struct MenuBarRow: View {
    let task: ReclaimTask
    @Bindable var vm: TaskListViewModel

    var body: some View {
        HStack(spacing: 8) {
            Button {
                Task { await vm.markComplete(id: task.id) }
            } label: {
                Image(systemName: "circle")
            }
            .buttonStyle(.borderless)
            .help("Mark complete")

            VStack(alignment: .leading, spacing: 1) {
                HStack(spacing: 4) {
                    if task.onDeck == true {
                        Image(systemName: "bolt.fill").foregroundStyle(.yellow).font(.caption2)
                    }
                    Text(task.displayTitle).lineLimit(1)
                }
                HStack(spacing: 6) {
                    if let p = task.priorityEnum {
                        Text(p.short).font(.caption2.bold()).foregroundStyle(p.color)
                    }
                    if task.due != nil {
                        Text(Fmt.day(task.due))
                            .font(.caption2)
                            .foregroundStyle(task.isOverdue ? .red : .secondary)
                    }
                }
            }
            Spacer(minLength: 0)
        }
    }
}
