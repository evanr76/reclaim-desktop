import SwiftUI

@main
struct ReclaimDesktopApp: App {
    @State private var viewModel = TaskListViewModel()
    @AppStorage("showInMenuBar") private var showInMenuBar = true

    var body: some Scene {
        // Single, addressable main window (openable from the menu bar).
        Window("Reclaim Tasks", id: "main") {
            ContentView(vm: viewModel)
                .frame(minWidth: 720, minHeight: 420)
        }
        .defaultSize(width: 960, height: 640)
        .commands {
            CommandGroup(after: .sidebar) {
                Button("Refresh") {
                    Task { await viewModel.loadTasks() }
                }
                .keyboardShortcut("r", modifiers: .command)
                .disabled(!viewModel.isConfigured)
            }
        }

        Settings {
            SettingsView(vm: viewModel)
        }

        MenuBarExtra("Reclaim Tasks", systemImage: "checklist", isInserted: $showInMenuBar) {
            MenuBarView(vm: viewModel)
        }
        .menuBarExtraStyle(.window)
    }
}
