import SwiftUI

@main
struct ReclaimDesktopApp: App {
    @State private var viewModel = TaskListViewModel()

    var body: some Scene {
        WindowGroup {
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
    }
}
