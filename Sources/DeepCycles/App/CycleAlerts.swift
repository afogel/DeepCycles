import AppKit
import UserNotifications
import DeepCyclesCore

/// What happens when a cycle or a break ends: beep, bounce the Dock icon, and post a
/// notification. Notifications only work when running as a real .app bundle.
@MainActor
enum CycleAlerts {
    private static var notificationsReady = false

    static func deliver(_ alert: CycleAlert) {
        NSSound.beep()
        NSApp.requestUserAttention(.informationalRequest)
        notify(alert)
    }

    private static func notify(_ alert: CycleAlert) {
        guard Bundle.main.bundleIdentifier != nil else { return }
        let center = UNUserNotificationCenter.current()
        let send = {
            let content = UNMutableNotificationContent()
            content.title = alert.title
            content.body = alert.body
            content.sound = .default
            center.add(UNNotificationRequest(identifier: UUID().uuidString, content: content, trigger: nil))
        }
        if notificationsReady {
            send()
        } else {
            center.requestAuthorization(options: [.alert, .sound]) { ok, _ in
                Task { @MainActor in
                    notificationsReady = ok
                    if ok { send() }
                }
            }
        }
    }
}
