import Foundation
@preconcurrency import UserNotifications

enum KopieNotifications {
    static func paused() { deliver(title: "Clipboard monitoring paused", body: "New copies will not be saved until you resume.") }
    static func resumed() { deliver(title: "Clipboard monitoring resumed", body: "New copies will be saved again.") }
    static func cleared() { deliver(title: "Clipboard history cleared", body: "All saved clipboard items were removed.") }
    static func show(title: String, message: String) { deliver(title: title, body: message) }

    private static func deliver(title: String, body: String) {
        // Headless/bare-binary runs have no bundle; UNUserNotificationCenter
        // would throw. Notifications only matter in the real app.
        guard Bundle.main.bundleIdentifier != nil else { return }
        let center = UNUserNotificationCenter.current()
        center.requestAuthorization(options: [.alert, .sound]) { _, _ in
            let content = UNMutableNotificationContent()
            content.title = title
            content.body = body
            content.sound = .default
            let request = UNNotificationRequest(identifier: UUID().uuidString, content: content, trigger: nil)
            center.add(request)
        }
    }
}
