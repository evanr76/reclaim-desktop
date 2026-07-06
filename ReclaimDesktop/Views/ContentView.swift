import SwiftUI

/// Root view: routes to onboarding when no token is configured, otherwise the
/// task list.
struct ContentView: View {
    @Bindable var vm: TaskListViewModel

    var body: some View {
        Group {
            if vm.isConfigured {
                TaskListView(vm: vm)
            } else {
                OnboardingView(vm: vm)
            }
        }
        .task {
            if vm.isConfigured && vm.allTasks.isEmpty {
                await vm.loadTasks()
            }
        }
    }
}
