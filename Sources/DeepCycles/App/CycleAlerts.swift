import AppKit
import UserNotifications
import DeepCyclesCore

/// What happens when work is wrapping up or a cycle or break ends: beep, bounce the Dock icon, and post a
/// notification. Notifications only work when running as a real .app bundle.
@MainActor
enum CycleAlerts {
    // The notification center holds its delegate weakly.
    private static let delegate = NotificationDelegate()

    static func configure() {
        guard Bundle.main.bundleIdentifier != nil else { return }
        let center = UNUserNotificationCenter.current()
        center.delegate = delegate
        center.requestAuthorization(options: [.alert, .sound]) { _, _ in }
    }

    static func deliver(_ alert: CycleAlert) {
        NSSound.beep()
        NSApp.requestUserAttention(.informationalRequest)
        notify(alert)
    }

    private static func notify(_ alert: CycleAlert) {
        guard Bundle.main.bundleIdentifier != nil else { return }
        let center = UNUserNotificationCenter.current()
        let content = UNMutableNotificationContent()
        content.title = alert.title
        content.body = alert.body
        content.sound = .default
        center.add(UNNotificationRequest(identifier: UUID().uuidString, content: content, trigger: nil))
    }
}

private final class NotificationDelegate: NSObject, UNUserNotificationCenterDelegate {
    func userNotificationCenter(
        _ center: UNUserNotificationCenter,
        willPresent notification: UNNotification,
        withCompletionHandler completionHandler: @escaping (UNNotificationPresentationOptions) -> Void
    ) {
        completionHandler([.banner, .list, .sound])
    }
}
