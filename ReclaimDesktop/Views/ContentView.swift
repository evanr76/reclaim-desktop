import SwiftUI

/// Root view: routes to onboarding when no token is configured, otherwise the
/// task list.
struct ContentView: View {
    @Bindable var vm: TaskListViewModel
    @AppStorage("appearance") private var appearanceRaw = AppAppearance.system.rawValue

    var body: some View {
        Group {
            if vm.isConfigured {
                TaskListView(vm: vm)
            } else {
                OnboardingView(vm: vm)
            }
        }
        .preferredColorScheme(AppAppearance(rawValue: appearanceRaw)?.colorScheme)
        .task {
            if vm.isConfigured && vm.allTasks.isEmpty {
                await vm.loadTasks()
            }
        }
    }
}
