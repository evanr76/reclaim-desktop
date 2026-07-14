import SwiftUI

/// Auto-refresh cadence options (minutes; 0 = off).
enum RefreshInterval: Int, CaseIterable, Identifiable {
    case off = 0, m15 = 15, m30 = 30, hourly = 60, h2 = 120

    var id: Int { rawValue }
    var label: String {
        switch self {
        case .off: return "Off"
        case .m15: return "Every 15 minutes"
        case .m30: return "Every 30 minutes"
        case .hourly: return "Hourly"
        case .h2: return "Every 2 hours"
        }
    }
}

/// Preferences window (⌘,): general options plus API key / account.
struct SettingsView: View {
    @Bindable var vm: TaskListViewModel
    @State private var newToken: String = ""

    @AppStorage("showInMenuBar") private var showInMenuBar = true
    @AppStorage("refreshIntervalMinutes") private var refreshIntervalMinutes = 60
    @AppStorage("appearance") private var appearanceRaw = AppAppearance.system.rawValue
    @AppStorage("notifyAtRisk") private var notifyAtRisk = true
    @AppStorage("notifyBlockStarting") private var notifyBlockStarting = true
    @AppStorage("notifyUpNext") private var notifyUpNext = true
    @AppStorage("notifyDigest") private var notifyDigest = true
    @AppStorage("digestHour") private var digestHour = 8
    @State private var openAtLogin = LoginItem.isEnabled

    var body: some View {
        Form {
            Section("General") {
                Picker("Appearance", selection: $appearanceRaw) {
                    ForEach(AppAppearance.allCases) { Text($0.label).tag($0.rawValue) }
                }
                Toggle("Open at login", isOn: $openAtLogin)
                    .onChange(of: openAtLogin) { _, wanted in
                        // Revert the toggle if the system rejected the change.
                        if !LoginItem.setEnabled(wanted) { openAtLogin = LoginItem.isEnabled }
                    }
                Toggle("Show in menu bar", isOn: $showInMenuBar)
                Picker("Refresh", selection: $refreshIntervalMinutes) {
                    ForEach(RefreshInterval.allCases) { Text($0.label).tag($0.rawValue) }
                }
                .onChange(of: refreshIntervalMinutes) { _, minutes in
                    vm.configureAutoRefresh(intervalMinutes: minutes)
                }
                Text("Auto-refresh runs only while online.")
                    .font(.caption).foregroundStyle(.secondary)
            }

            Section("Notifications") {
                Toggle("At-risk alerts", isOn: $notifyAtRisk)
                Toggle("Block starting soon", isOn: $notifyBlockStarting)
                Toggle("Up Next changes", isOn: $notifyUpNext)
                Toggle("Morning digest", isOn: $notifyDigest)
                if notifyDigest {
                    Picker("Digest time", selection: $digestHour) {
                        ForEach(5..<12) { Text("\($0):00").tag($0) }
                    }
                }
            }

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
        .preferredColorScheme(AppAppearance(rawValue: appearanceRaw)?.colorScheme)
        .frame(width: 460, height: 660)
    }
}
