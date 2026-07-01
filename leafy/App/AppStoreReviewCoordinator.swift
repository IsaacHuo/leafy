import Foundation

enum AppStoreReviewCoordinator {
    enum SyncKind: String, CaseIterable {
        case timetable
    }

    static let successfulSyncRecordedNotification = Notification.Name("leafy.appStoreReview.successfulSyncRecorded")

    private static let successfulSyncDaysKey = "appStoreReview.successfulSyncDays"
    private static let lastAttemptedAtKey = "appStoreReview.lastAttemptedAt"
    private static let lastAttemptedVersionKey = "appStoreReview.lastAttemptedVersion"
    private static let requiredSuccessfulSyncDays = 3
    private static let cooldownInterval: TimeInterval = 120 * 24 * 60 * 60

    static func recordSuccessfulSync(
        kind: SyncKind,
        date: Date,
        calendar: Calendar = .current,
        userDefaults: UserDefaults = .standard,
        notificationCenter: NotificationCenter = .default
    ) {
        guard let dayKey = Self.dayKey(for: date, calendar: calendar) else { return }

        var successfulSyncDays = Set(userDefaults.stringArray(forKey: successfulSyncDaysKey) ?? [])
        successfulSyncDays.insert(dayKey)
        userDefaults.set(successfulSyncDays.sorted(), forKey: successfulSyncDaysKey)

        let kindKey = successfulSyncDaysKey + ".\(kind.rawValue)"
        var kindSyncDays = Set(userDefaults.stringArray(forKey: kindKey) ?? [])
        kindSyncDays.insert(dayKey)
        userDefaults.set(kindSyncDays.sorted(), forKey: kindKey)

        notificationCenter.post(name: successfulSyncRecordedNotification, object: kind)
    }

    static func shouldRequestReview(
        now: Date,
        appVersion: String,
        isDemoMode: Bool,
        isSceneActive: Bool,
        userDefaults: UserDefaults = .standard
    ) -> Bool {
        guard !isDemoMode, isSceneActive else { return false }
        guard !appVersion.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty else { return false }

        let successfulSyncDays = userDefaults.stringArray(forKey: successfulSyncDaysKey) ?? []
        guard Set(successfulSyncDays).count >= requiredSuccessfulSyncDays else { return false }

        if userDefaults.string(forKey: lastAttemptedVersionKey) == appVersion {
            return false
        }

        if let lastAttemptedAt = userDefaults.object(forKey: lastAttemptedAtKey) as? Date,
           now.timeIntervalSince(lastAttemptedAt) < cooldownInterval {
            return false
        }

        return true
    }

    static func markReviewRequestAttempted(
        now: Date,
        appVersion: String,
        userDefaults: UserDefaults = .standard
    ) {
        userDefaults.set(now, forKey: lastAttemptedAtKey)
        userDefaults.set(appVersion, forKey: lastAttemptedVersionKey)
    }

    private static func dayKey(for date: Date, calendar: Calendar) -> String? {
        let components = calendar.dateComponents([.year, .month, .day], from: date)
        guard let year = components.year, let month = components.month, let day = components.day else {
            return nil
        }

        return String(format: "%04d-%02d-%02d", year, month, day)
    }
}
