import SwiftUI

/// First-run screen to capture the Reclaim API key.
struct OnboardingView: View {
    @Bindable var vm: TaskListViewModel
    @State private var token: String = ""

    var body: some View {
        VStack(spacing: 20) {
            Image(systemName: "calendar.badge.clock")
                .font(.system(size: 52))
                .foregroundStyle(.tint)

            Text("Connect to Reclaim.ai")
                .font(.title.bold())

            Text("Paste your Reclaim API key to get started. You can create one at reclaim.ai → Settings → Developer.")
                .font(.callout)
                .foregroundStyle(.secondary)
                .multilineTextAlignment(.center)
                .frame(maxWidth: 420)

            SecureField("Reclaim API key", text: $token)
                .textFieldStyle(.roundedBorder)
                .frame(maxWidth: 420)
                .onSubmit { connect() }

            if let error = vm.errorMessage {
                Label(error, systemImage: "exclamationmark.triangle.fill")
                    .font(.caption)
                    .foregroundStyle(.red)
                    .frame(maxWidth: 420)
            }

            Button(action: connect) {
                if vm.isBusy {
                    ProgressView().controlSize(.small)
                } else {
                    Text("Connect").frame(maxWidth: 120)
                }
            }
            .buttonStyle(.borderedProminent)
            .disabled(token.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty || vm.isBusy)

            Text("Your key is stored securely in the macOS Keychain.")
                .font(.caption2)
                .foregroundStyle(.tertiary)
        }
        .padding(40)
        .frame(maxWidth: .infinity, maxHeight: .infinity)
    }

    private func connect() {
        Task { await vm.saveToken(token) }
    }
}
