import OSLog

nonisolated enum CommunityDiagnostics {
    static let log = Logger(subsystem: "com.isaachuo.leafy", category: "Community")
}

nonisolated enum CommunityDiagnosticsOptions {
    static let emptyShellArgument = "-LeafyCommunityEmptyShell"
    static let disableRootStartupArgument = "-LeafyCommunityDisableRootStartup"
    static let disableTermsArgument = "-LeafyCommunityDisableTerms"
    static let disableFeedArgument = "-LeafyCommunityDisableFeed"
    static let disableNotificationsArgument = "-LeafyCommunityDisableNotifications"
    static let disableNotificationRealtimeArgument = "-LeafyCommunityDisableNotificationRealtime"
    static let disableGlassArgument = "-LeafyCommunityDisableGlass"

    static var usesEmptyShell: Bool {
        hasArgument(emptyShellArgument)
    }

    static var disablesRootStartup: Bool {
        usesEmptyShell || hasArgument(disableRootStartupArgument)
    }

    static var disablesTermsGate: Bool {
        usesEmptyShell || hasArgument(disableTermsArgument)
    }

    static var disablesFeedLoad: Bool {
        usesEmptyShell || hasArgument(disableFeedArgument)
    }

    static var disablesNotifications: Bool {
        usesEmptyShell || hasArgument(disableNotificationsArgument)
    }

    static var disablesNotificationRealtime: Bool {
        disablesNotifications || hasArgument(disableNotificationRealtimeArgument)
    }

    static var disablesGlassEffects: Bool {
        usesEmptyShell || hasArgument(disableGlassArgument)
    }

    static var summary: String {
        [
            usesEmptyShell ? "empty-shell" : nil,
            disablesRootStartup ? "root-startup-off" : nil,
            disablesTermsGate ? "terms-off" : nil,
            disablesFeedLoad ? "feed-off" : nil,
            disablesNotifications ? "notifications-off" : nil,
            disablesNotificationRealtime && !disablesNotifications ? "notification-realtime-off" : nil,
            disablesGlassEffects ? "glass-off" : nil
        ]
            .compactMap { $0 }
            .joined(separator: ",")
    }

    private static func hasArgument(_ argument: String) -> Bool {
        ProcessInfo.processInfo.arguments.contains(argument)
    }
}
