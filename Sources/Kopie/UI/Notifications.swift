import Foundation
@preconcurrency import UserNotifications

enum KopieNotifications {
    static func paused() { deliver(title: "Clipboard monitoring paused", body: "New copies will not be saved until you resume.") }
    static func resumed() { deliver(title: "Clipboard monitoring resumed", body: "New copies will be saved again.") }
    static func cleared() { deliver(title: "Clipboard history cleared", body: "All saved clipboard items were removed.") }

    private static func deliver(title: String, body: String) {
        let center = UNUserNotificationCenter.current()
        center.requestAuthorization(options: [.alert, .sound]) { _, _ in
            Task {
                let content = UNMutableNotificationContent()
                content.title = title
                content.body = body
                content.sound = .default
                let request = UNNotificationRequest(identifier: UUID().uuidString, content: content, trigger: nil)
                try? await center.add(request)
            }
        }
    }
}
