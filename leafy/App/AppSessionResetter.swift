import Foundation
import SwiftData

@MainActor
enum AppSessionResetter {
    static func returnToLogin(modelContext: ModelContext? = nil) {
        if ReviewDemoMode.isEnabled {
            ReviewDemoDataSeeder.exit(using: modelContext)
        }
        ActiveCampusContext.networkManager.clearSession()
        LeafyWidgetSnapshotBuilder.publishNeedsLogin()
        Task {
            await CommunitySessionManager.shared.signOut()
        }
    }
}
