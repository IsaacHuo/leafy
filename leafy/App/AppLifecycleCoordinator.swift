import SwiftUI

@MainActor
enum AppLifecycleCoordinator {
    static func handleScenePhase(_ scenePhase: ScenePhase) {
        switch scenePhase {
        case .active, .inactive:
            break
        case .background:
            suspendInFlightWork()
        @unknown default:
            suspendInFlightWork()
        }
    }

    private static func suspendInFlightWork() {
        ActiveCampusContext.networkManager.cancelInFlightRequests()
        CommunitySessionManager.shared.cancelInFlightWork()
        Task {
            await CommunityService.shared.cancelInFlightWork()
        }
    }
}
