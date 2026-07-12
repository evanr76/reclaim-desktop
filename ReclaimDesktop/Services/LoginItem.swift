import Foundation
import ServiceManagement

/// Thin wrapper over `SMAppService.mainApp` for the "Open at login" setting.
/// Registers the app itself as a login item (macOS 13+); no helper bundle,
/// no special entitlement required.
enum LoginItem {
    static var isEnabled: Bool { SMAppService.mainApp.status == .enabled }

    /// Register / unregister. Returns false if the system rejected the change
    /// (e.g. requires user approval in System Settings).
    @discardableResult
    static func setEnabled(_ enabled: Bool) -> Bool {
        do {
            if enabled {
                if SMAppService.mainApp.status != .enabled { try SMAppService.mainApp.register() }
            } else {
                if SMAppService.mainApp.status == .enabled { try SMAppService.mainApp.unregister() }
            }
            return true
        } catch {
            return false
        }
    }
}
