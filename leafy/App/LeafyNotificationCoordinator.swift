import Foundation
import UserNotifications

final class LeafyNotificationCoordinator: NSObject, UNUserNotificationCenterDelegate {
    static let shared = LeafyNotificationCoordinator()

    @MainActor private weak var appNavigation: AppNavigationCoordinator?

    private override init() {
        super.init()
    }

    @MainActor
    func configure(appNavigation: AppNavigationCoordinator) {
        self.appNavigation = appNavigation
        UNUserNotificationCenter.current().delegate = self
    }

    func userNotificationCenter(
        _ center: UNUserNotificationCenter,
        willPresent notification: UNNotification
    ) async -> UNNotificationPresentationOptions {
        [.banner, .list, .sound]
    }

    func userNotificationCenter(
        _ center: UNUserNotificationCenter,
        didReceive response: UNNotificationResponse
    ) async {
        guard let urlString = response.notification.request.content.userInfo["url"] as? String,
              let url = URL(string: urlString) else {
            return
        }

        await MainActor.run {
            appNavigation?.handle(url: url)
        }
    }
}
