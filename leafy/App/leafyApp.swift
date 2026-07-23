//
//  leafyApp.swift
//  leafy
//
//  Created by IsaacHuo on 2026/4/21.
//

import OSLog
import SwiftData
import SwiftUI
import StoreKit
import UIKit

@main
struct LeafyApp: App {
    private let logger = Logger(subsystem: "com.isaachuo.leafy", category: "SemesterRollover")
    @StateObject private var networkManager = ActiveCampusContext.networkManager
    @StateObject private var appNavigation = AppNavigationCoordinator()
    @StateObject private var communityNotificationBadgeViewModel = CommunityNotificationBadgeViewModel()
    @StateObject private var externalImportCoordinator = ExternalLearningMaterialImportCoordinator()
    @Environment(\.scenePhase) private var scenePhase
    @Environment(\.requestReview) private var requestReview
    @AppStorage("appFontSizePreference") private var appDisplaySizePreferenceRaw = AppDisplaySizePreference.standard.rawValue
    @AppStorage(AppThemeColorPreference.storageKey) private var appThemeColorPreferenceRaw = AppThemeColorPreference.green.rawValue
    @AppStorage(AppThemeColorPreference.customColorHexKey) private var appThemeCustomColorHex = AppThemeColorPreference.defaultCustomColorHex
    @AppStorage(LeafyAppIconAppearancePreference.storageKey) private var appIconAppearancePreferenceRaw = LeafyAppIconAppearancePreference.green.rawValue
    @AppStorage(AppAppearancePreference.storageKey) private var appAppearancePreferenceRaw = AppAppearancePreference.light.rawValue
    @State private var modelContainerSetup: AppModelContainerSetup
    @State private var modelContainerRevision = UUID()
    @State private var modelRecoveryMessage: String?
    @State private var authCallbackMessage: String?
    @State private var reviewRequestTask: Task<Void, Never>?
    @State private var semesterConfigRefreshTask: Task<Void, Never>?
    @State private var scheduleReportRefreshTask: Task<Void, Never>?

    private var sharedModelContainer: ModelContainer {
        modelContainerSetup.container
    }

    private var isAuthenticatedForExternalImport: Bool {
        networkManager.hasCachedIdentity || ReviewDemoMode.isEnabled
    }

    private var displaySizePreference: AppDisplaySizePreference {
        AppDisplaySizePreference(rawValue: appDisplaySizePreferenceRaw) ?? .standard
    }

    private var themeColorPreference: AppThemeColorPreference {
        AppThemeColorPreference.storedValue(appThemeColorPreferenceRaw)
    }

    private var appearancePreference: AppAppearancePreference {
        AppAppearancePreference.storedValue(appAppearancePreferenceRaw)
    }

    private var appearanceAnimation: Animation {
        .easeInOut(duration: 0.55)
    }

    init() {
        AppAppearancePreference.migrateStoredAppearanceIfNeeded()
        AppThemeColorPreference.migrateStoredThemeIfNeeded()
        let setup = AppModelContainerFactory.make()
        self._modelContainerSetup = State(initialValue: setup)
        self._modelRecoveryMessage = State(initialValue: setup.recoveryMessage)

        #if DEBUG
        DebugNetworkDiagnostics.runStartupProbe()
        #endif
    }

    var body: some Scene {
        WindowGroup {
            Group {
                if networkManager.hasCachedIdentity || ReviewDemoMode.isEnabled {
                    ContentView(
                        appNavigation: appNavigation,
                        communityNotificationBadgeViewModel: communityNotificationBadgeViewModel
                    )
                } else {
                    LoginView()
                }
            }
            .id(modelContainerRevision)
            .onOpenURL { url in
                if externalImportCoordinator.handle(url: url, isAuthenticated: isAuthenticatedForExternalImport) {
                    return
                }

                if CustomCampusAuthCallback.isCallback(url) {
                    Task { await handleCustomCampusAuthCallback(url) }
                    return
                }

                appNavigation.handle(url: url)
            }
            .sheet(item: $externalImportCoordinator.activeBatch) { batch in
                ExternalLearningMaterialImportSheet(
                    batch: batch,
                    coordinator: externalImportCoordinator,
                    appNavigation: appNavigation
                )
            }
            .alert(L10n.text("本地缓存已恢复", language: .zhHans), isPresented: Binding(
                get: { modelRecoveryMessage != nil },
                set: { if !$0 { modelRecoveryMessage = nil } }
            )) {
                Button(L10n.text("知道了", language: .zhHans), role: .cancel) {}
            } message: {
                Text(modelRecoveryMessage ?? "")
            }
            .alert(L10n.text("邮箱验证", language: .zhHans), isPresented: Binding(
                get: { authCallbackMessage != nil },
                set: { if !$0 { authCallbackMessage = nil } }
            )) {
                Button(L10n.text("知道了", language: .zhHans), role: .cancel) {}
            } message: {
                Text(authCallbackMessage ?? "")
            }
            .alert("无法导入学习资料", isPresented: Binding(
                get: { externalImportCoordinator.alertMessage != nil },
                set: { if !$0 { externalImportCoordinator.alertMessage = nil } }
            )) {
                Button("知道了", role: .cancel) {}
            } message: {
                Text(externalImportCoordinator.alertMessage ?? "")
            }
            .tint(themeColorPreference.swatchColor)
            .preferredColorScheme(appearancePreference.preferredColorScheme)
            .animation(appearanceAnimation, value: appAppearancePreferenceRaw)
            .animation(appearanceAnimation, value: appThemeCustomColorHex)
            .onAppear {
                AppAppearancePreference.migrateStoredAppearanceIfNeeded()
                AppThemeColorPreference.migrateStoredThemeIfNeeded()
                syncThemeAppearance()
                LeafyNotificationCoordinator.shared.configure(appNavigation: appNavigation)
                if ReviewDemoMode.isEnabled {
                    ReviewDemoDataSeeder.seedIfNeeded(using: sharedModelContainer.mainContext)
                }
                refreshSemesterRuntimeConfig(force: true, prefetchTrigger: .foreground)
                refreshWidgetSnapshot()
                refreshScheduleReportNotifications()
                externalImportCoordinator.presentPendingIfPossible(isAuthenticated: isAuthenticatedForExternalImport)
            }
            .onChange(of: networkManager.hasCachedIdentity) { _, _ in
                externalImportCoordinator.presentPendingIfPossible(isAuthenticated: isAuthenticatedForExternalImport)
            }
            .onChange(of: appThemeColorPreferenceRaw) { _, _ in
                syncThemeAppearance()
            }
            .onChange(of: appThemeCustomColorHex) { _, _ in
                syncThemeAppearance()
            }
            .onChange(of: appIconAppearancePreferenceRaw) { _, _ in
                syncThemeAppearance()
            }
            .onChange(of: scenePhase) { _, newPhase in
                AppLifecycleCoordinator.handleScenePhase(newPhase)
                if newPhase == .active || newPhase == .background {
                    refreshWidgetSnapshot()
                }
                if newPhase == .active {
                    refreshSemesterRuntimeConfig(prefetchTrigger: .foreground)
                    refreshScheduleReportNotifications()
                    externalImportCoordinator.presentPendingIfPossible(isAuthenticated: isAuthenticatedForExternalImport)
                }
                if newPhase != .active {
                    reviewRequestTask?.cancel()
                    reviewRequestTask = nil
                }
            }
            .onReceive(NotificationCenter.default.publisher(for: AppStoreReviewCoordinator.successfulSyncRecordedNotification)) { _ in
                scheduleReviewRequestIfEligible()
            }
        .onReceive(NotificationCenter.default.publisher(for: .campusIdentityDidChange)) { notification in
            guard !AppRuntimeEnvironment.isRunningUnitTests else { return }
            reloadModelContainerForCampusIdentity(
                prefetchTrigger: notification.object == nil ? .foreground : .login
            )
        }
            .onReceive(NotificationCenter.default.publisher(for: .schoolDataDidRefresh)) { _ in
                refreshScheduleReportNotifications()
            }
            .onReceive(NotificationCenter.default.publisher(for: .schoolExamScheduleDidChange)) { _ in
                refreshScheduleReportNotifications()
            }
            .onReceive(NotificationCenter.default.publisher(for: .customCountdownEventsDidChange)) { _ in
                refreshScheduleReportNotifications()
            }
            .onReceive(NotificationCenter.default.publisher(for: .semesterRuntimeConfigDidChange)) { _ in
                refreshScheduleReportNotifications()
            }
            .onReceive(NotificationCenter.default.publisher(for: .nationalCalendarRuntimeConfigDidChange)) { _ in
                refreshScheduleReportNotifications()
            }
        }
        .environment(\.dynamicTypeSize, displaySizePreference.dynamicTypeSize)
        .environment(\.leafyFontScale, displaySizePreference.fontScale)
        .environment(\.leafyControlScale, displaySizePreference.controlScale)
        .environment(\.leafyThemeColorPreference, themeColorPreference)
        .environment(\.leafyLanguage, .zhHans)
        .environment(\.locale, Locale(identifier: AppLanguagePreference.zhHans.localeIdentifier))
        .environment(\.defaultMinListRowHeight, displaySizePreference.listRowMinHeight)
        .modelContainer(sharedModelContainer)
    }

    @MainActor
    private func reloadModelContainerForCampusIdentity(
        prefetchTrigger: SchoolDataPrefetchTrigger
    ) {
        let setup = AppModelContainerFactory.make()
        modelContainerSetup = setup
        if let recoveryMessage = setup.recoveryMessage {
            modelRecoveryMessage = recoveryMessage
        }
        modelContainerRevision = UUID()
        refreshSemesterRuntimeConfig(force: true, prefetchTrigger: prefetchTrigger)
        refreshWidgetSnapshot()
        refreshScheduleReportNotifications()
    }

    @MainActor
    private func handleCustomCampusAuthCallback(_ url: URL) async {
        do {
            guard let session = try await CustomCampusAuthService().restoreSession(from: url) else {
                return
            }
            if networkManager.hasCachedIdentity, ActiveCampusContext.identity?.isCustom != true {
                authCallbackMessage = L10n.text(
                    "邮箱绑定请回到 App 输入邮件验证码完成。",
                    language: .zhHans
                )
                return
            }
            networkManager.persistCustomCampusAuthSession(session)
            externalImportCoordinator.presentPendingIfPossible(isAuthenticated: isAuthenticatedForExternalImport)
            authCallbackMessage = L10n.text(
                "邮箱验证已完成，已登录通用入口账号 %@。",
                language: .zhHans,
                session.email
            )
        } catch {
            authCallbackMessage = L10n.text(
                "邮箱验证链接无法自动完成。%@",
                language: .zhHans,
                error.localizedDescription
            )
        }
    }

    @MainActor
    private func refreshWidgetSnapshot() {
        let isAuthenticated = networkManager.hasCachedIdentity || ReviewDemoMode.isEnabled
        guard isAuthenticated else {
            LeafyWidgetSnapshotBuilder.publishNeedsLogin()
            return
        }

        LeafyWidgetSnapshotBuilder.publish(from: sharedModelContainer.mainContext, isAuthenticated: isAuthenticated)
    }

    @MainActor
    private func refreshScheduleReportNotifications() {
        let settings = ScheduleReportSettingsStore.load()
        guard settings.isEnabled else { return }

        scheduleReportRefreshTask?.cancel()
        scheduleReportRefreshTask = Task { @MainActor in
            do {
                try await ScheduleReportNotificationManager.refreshIfEnabled(
                    modelContext: sharedModelContainer.mainContext
                )
                guard !Task.isCancelled else { return }
            } catch {
                guard !Task.isCancelled else { return }
                logger.error("Schedule report notification refresh failed: \(error.localizedDescription, privacy: .public)")
            }
            scheduleReportRefreshTask = nil
        }
    }

    @MainActor
    private func refreshSemesterRuntimeConfig(
        force: Bool = false,
        prefetchTrigger: SchoolDataPrefetchTrigger? = nil
    ) {
        semesterConfigRefreshTask?.cancel()
        semesterConfigRefreshTask = Task { @MainActor in
            let previousConfig = SemesterConfig.current
            let refreshedConfig = await SemesterConfig.refreshRemoteIfAvailable(force: force)
            guard !Task.isCancelled else { return }
            let semesterChanged = previousConfig.semesterID != refreshedConfig.semesterID
            let cachedTimetableIsFromAnotherSemester = TimetableCacheMetadata.lastSyncedSemesterID
                .map { $0 != refreshedConfig.semesterID } ?? false
            let timetableNeedsSemesterRefresh = semesterChanged || cachedTimetableIsFromAnotherSemester
            if timetableNeedsSemesterRefresh {
                resetTimetableForSemesterTransition()
            }
            refreshWidgetSnapshot()
            if let prefetchTrigger {
                prefetchSchoolData(trigger: timetableNeedsSemesterRefresh ? .semesterChanged : prefetchTrigger)
            }
            semesterConfigRefreshTask = nil
        }
    }

    @MainActor
    private func resetTimetableForSemesterTransition() {
        guard !ReviewDemoMode.isEnabled,
              ActiveCampusContext.descriptor.id == .bjfu,
              ActiveCampusContext.identity?.isCustom != true else {
            return
        }

        let context = sharedModelContainer.mainContext
        do {
            let courses = try context.fetch(FetchDescriptor<Course>())
            for course in courses {
                context.delete(course)
            }
            try context.save()
            TimetableCacheMetadata.clear()
            SchoolDataRefreshNotifier.post(.timetable)
        } catch {
            logger.error("Failed to reset timetable during semester rollover: \(error.localizedDescription, privacy: .public)")
        }
    }

    @MainActor
    private func prefetchSchoolData(trigger: SchoolDataPrefetchTrigger) {
        guard !AppRuntimeEnvironment.isRunningUnitTests else { return }
        SchoolDataPrefetchCoordinator.shared.prefetchIfNeeded(
            modelContext: sharedModelContainer.mainContext,
            language: .zhHans,
            trigger: trigger
        )
    }

    @MainActor
    private func syncThemeAppearance() {
        LeafyAppIconManager.syncTheme(
            preferenceRaw: appThemeColorPreferenceRaw,
            customColorHex: appThemeCustomColorHex,
            iconPreferenceRaw: appIconAppearancePreferenceRaw
        )
    }

    @MainActor
    private func scheduleReviewRequestIfEligible() {
        reviewRequestTask?.cancel()

        guard networkManager.hasCachedIdentity,
              modelRecoveryMessage == nil,
              AppStoreReviewCoordinator.shouldRequestReview(
                now: Date(),
                appVersion: currentAppVersion,
                isDemoMode: ReviewDemoMode.isEnabled,
                isSceneActive: scenePhase == .active
              ) else {
            reviewRequestTask = nil
            return
        }

        reviewRequestTask = Task { @MainActor in
            try? await Task.sleep(nanoseconds: 1_000_000_000)
            guard !Task.isCancelled,
                  networkManager.hasCachedIdentity,
                  modelRecoveryMessage == nil,
                  AppStoreReviewCoordinator.shouldRequestReview(
                    now: Date(),
                    appVersion: currentAppVersion,
                    isDemoMode: ReviewDemoMode.isEnabled,
                    isSceneActive: scenePhase == .active
                  ) else {
                return
            }

            AppStoreReviewCoordinator.markReviewRequestAttempted(
                now: Date(),
                appVersion: currentAppVersion
            )
            requestReview()
            reviewRequestTask = nil
        }
    }

    private var currentAppVersion: String {
        Bundle.main.object(forInfoDictionaryKey: "CFBundleShortVersionString") as? String
            ?? Bundle.main.object(forInfoDictionaryKey: "CFBundleVersion") as? String
            ?? "unknown"
    }
}
