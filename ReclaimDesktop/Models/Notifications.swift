import Foundation
import UserNotifications

/// Which local notifications the user wants.
public struct NotificationPrefs: Sendable {
    public var atRisk: Bool
    public var blockStarting: Bool
    public var upNext: Bool
    public var digest: Bool
    public var digestHour: Int
    public var blockLeadMinutes: Int

    public init(atRisk: Bool = true, blockStarting: Bool = true, upNext: Bool = true,
                digest: Bool = true, digestHour: Int = 8, blockLeadMinutes: Int = 5) {
        self.atRisk = atRisk
        self.blockStarting = blockStarting
        self.upNext = upNext
        self.digest = digest
        self.digestHour = digestHour
        self.blockLeadMinutes = blockLeadMinutes
    }

    public var anyEnabled: Bool { atRisk || blockStarting || upNext || digest }
}

/// Shows notifications even while the app is in the foreground.
public final class NotificationDelegate: NSObject, UNUserNotificationCenterDelegate {
    public static let shared = NotificationDelegate()
    public func userNotificationCenter(_ center: UNUserNotificationCenter,
                                       willPresent notification: UNNotification) async
        -> UNNotificationPresentationOptions { [.banner, .sound] }
}

public enum NotificationScheduler {
    public static func configure() {
        UNUserNotificationCenter.current().delegate = NotificationDelegate.shared
    }

    @discardableResult
    public static func requestAuthorization() async -> Bool {
        (try? await UNUserNotificationCenter.current()
            .requestAuthorization(options: [.alert, .sound, .badge])) ?? false
    }

    /// Fire at-risk / up-next alerts for newly-changed tasks, and (re)schedule
    /// the next block reminder + daily digest. On the first call (`seed`), only
    /// the time-based ones are scheduled — no burst of alerts for existing state.
    @discardableResult
    public static func sync(tasks: [ReclaimTask], nextEvent: MomentEvent?, prefs: NotificationPrefs,
                            previousAtRisk: Set<Int>, previousUpNext: Set<Int>, seed: Bool) async
        -> (atRisk: Set<Int>, upNext: Set<Int>) {
        let center = UNUserNotificationCenter.current()
        let unfinished = tasks.filter { !$0.isFinished }
        let atRiskNow = Set(unfinished.filter { $0.atRisk == true }.map(\.id))
        let upNextNow = Set(unfinished.filter { $0.onDeck == true }.map(\.id))

        if !seed && prefs.atRisk {
            for t in unfinished where t.atRisk == true && !previousAtRisk.contains(t.id) {
                await add(id: "atrisk-\(t.id)", title: "Task at risk",
                          body: "“\(t.displayTitle)” may not be scheduled in time.", trigger: nil)
            }
        }
        if !seed && prefs.upNext {
            for t in unfinished where t.onDeck == true && !previousUpNext.contains(t.id) {
                await add(id: "upnext-\(t.id)", title: "Up Next",
                          body: "“\(t.displayTitle)” is up next.", trigger: nil)
            }
        }

        center.removePendingNotificationRequests(withIdentifiers: ["block-next"])
        if prefs.blockStarting, let ev = nextEvent, let start = ev.eventStart {
            let fire = start.addingTimeInterval(-Double(prefs.blockLeadMinutes) * 60)
            if fire > Date() {
                let comps = Calendar.current.dateComponents([.year, .month, .day, .hour, .minute], from: fire)
                await add(id: "block-next", title: "Starting soon",
                          body: "\(ev.displayTitle) begins shortly.",
                          trigger: UNCalendarNotificationTrigger(dateMatching: comps, repeats: false))
            }
        }

        center.removePendingNotificationRequests(withIdentifiers: ["digest"])
        if prefs.digest {
            let overdue = unfinished.filter(\.isOverdue).count
            let body = overdue > 0
                ? "\(unfinished.count) active tasks · \(overdue) overdue."
                : "\(unfinished.count) active tasks today."
            var comps = DateComponents(); comps.hour = prefs.digestHour; comps.minute = 0
            await add(id: "digest", title: "Good morning", body: body,
                      trigger: UNCalendarNotificationTrigger(dateMatching: comps, repeats: true))
        }

        return (atRiskNow, upNextNow)
    }

    private static func add(id: String, title: String, body: String, trigger: UNNotificationTrigger?) async {
        let content = UNMutableNotificationContent()
        content.title = title
        content.body = body
        content.sound = .default
        try? await UNUserNotificationCenter.current()
            .add(UNNotificationRequest(identifier: id, content: content, trigger: trigger))
    }
}
