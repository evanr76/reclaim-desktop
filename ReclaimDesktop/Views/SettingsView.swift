import SwiftUI

/// Preferences window (⌘,): manage the stored API key and account.
struct SettingsView: View {
    @Bindable var vm: TaskListViewModel
    @State private var newToken: String = ""

    var body: some View {
        Form {
            Section("Account") {
                if let user = vm.user {
                    LabeledContent("Signed in as", value: user.displayName)
                    if let email = user.email {
                        LabeledContent("Email", value: email)
                    }
                } else {
                    Text("Not connected.").foregroundStyle(.secondary)
                }
            }

            Section("API Key") {
                SecureField("Replace API key", text: $newToken)
                HStack {
                    Button("Update Key") {
                        Task {
                            await vm.saveToken(newToken)
                            newToken = ""
                        }
                    }
                    .disabled(newToken.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty || vm.isBusy)

                    Button("Sign Out", role: .destructive) { vm.signOut() }
                        .disabled(!vm.isConfigured)
                }
                Text("The key is stored in the macOS Keychain and sent only to api.app.reclaim.ai.")
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }

            if let error = vm.errorMessage {
                Label(error, systemImage: "exclamationmark.triangle.fill")
                    .foregroundStyle(.red)
            }
        }
        .formStyle(.grouped)
        .frame(width: 460, height: 340)
    }
}
