//
//  ContentView.swift
//  leafy
//
//  Created by IsaacHuo on 2026/4/21.
//

import Foundation
import SwiftUI

struct ContentView: View {
    @Environment(\.leafyControlScale) private var leafyControlScale
    @Environment(\.leafyLanguage) private var leafyLanguage
    @Environment(\.leafyThemeColorPreference) private var themeColorPreference
    @Environment(\.scenePhase) private var scenePhase
    @ObservedObject var appNavigation: AppNavigationCoordinator
    @ObservedObject var communityNotificationBadgeViewModel: CommunityNotificationBadgeViewModel
    @ObservedObject private var communitySessionManager = CommunitySessionManager.shared
    @State private var isTimeScopePresented = false

    init(
        appNavigation: AppNavigationCoordinator,
        communityNotificationBadgeViewModel: CommunityNotificationBadgeViewModel
    ) {
        self.appNavigation = appNavigation
        self.communityNotificationBadgeViewModel = communityNotificationBadgeViewModel
    }

    private var isCommunityEnabled: Bool {
        ActiveCampusContext.descriptor.supports(.community)
    }

    var body: some View {
        rootShell
            .tint(AppTheme.accent(for: themeColorPreference))
            .environmentObject(appNavigation)
            .onAppear {
                sanitizeUnavailableRootTab()
            }
            .onChange(of: appNavigation.selectedRootTab) { _, newTab in
                handleRootTabChange(to: newTab)
            }
            .onChange(of: isTimeScopePresented) { _, isPresented in
                handleTimeScopePresentationChange(isPresented)
            }
            .task {
                if isCommunityEnabled {
                    await restoreCommunityNotificationBadge()
                }
            }
            .onChange(of: scenePhase) { _, newPhase in
                switch newPhase {
                case .active:
                    if isCommunityEnabled {
                        Task { await restoreCommunityNotificationBadge() }
                    }
                case .background:
                    communityNotificationBadgeViewModel.stop(reset: false)
                default:
                    break
                }
            }
            .onChange(of: communitySessionManager.currentUserID) { _, currentUserID in
                syncCommunityNotificationBadgeSubscription(profileID: currentUserID)
            }
    }

    @ViewBuilder
    private var rootShell: some View {
        if #available(iOS 26.0, *) {
            nativeTabShell
        } else {
            legacyFloatingTabShell
        }
    }

    @available(iOS 26.0, *)
    private var nativeTabShell: some View {
        nativeTabView
            .nativeRootTabBarBehavior()
    }

    @available(iOS 26.0, *)
    private var nativeTabView: some View {
        TabView(selection: nativeRootTabSelection) {
            Tab(
                RootTab.timetable.title(language: leafyLanguage),
                systemImage: RootTab.timetable.systemImage,
                value: RootTab.timetable
            ) {
                TimetableView(isTimeScopePresented: $isTimeScopePresented)
            }

            if isCommunityEnabled {
                Tab(
                    RootTab.community.title(language: leafyLanguage),
                    systemImage: RootTab.community.systemImage,
                    value: RootTab.community
                ) {
                    CommunityRootView(
                        notificationBadgeViewModel: communityNotificationBadgeViewModel
                    )
                }
                .badge(communityNotificationBadgeViewModel.unreadCount)
            }

            Tab(
                RootTab.leafy.title(language: leafyLanguage),
                systemImage: RootTab.leafy.systemImage,
                value: RootTab.leafy
            ) {
                CampusAIAssistantView()
            }

            Tab(
                RootTab.academics.title(language: leafyLanguage),
                systemImage: RootTab.academics.systemImage,
                value: RootTab.academics
            ) {
                AcademicHubView(selectedTab: $appNavigation.selectedAcademicTab)
                    .onAppear {
                        appNavigation.selectedRootTab = .academics
                    }
            }

            Tab(
                RootTab.profile.title(language: leafyLanguage),
                systemImage: RootTab.profile.systemImage,
                value: RootTab.profile
            ) {
                ProfileView()
            }
        }
    }

    private var nativeRootTabSelection: Binding<RootTab> {
        Binding(
            get: { appNavigation.selectedRootTab },
            set: { newTab in
                appNavigation.selectedRootTab = newTab
            }
        )
    }

    private var legacyFloatingTabShell: some View {
        TabView(selection: $appNavigation.selectedRootTab) {
            TimetableView(isTimeScopePresented: $isTimeScopePresented)
                .toolbar(.hidden, for: .tabBar)
                .tabItem {
                    Label(RootTab.timetable.title(language: leafyLanguage), systemImage: "calendar")
                }
                .tag(RootTab.timetable)

            if isCommunityEnabled {
                CommunityRootView(
                    notificationBadgeViewModel: communityNotificationBadgeViewModel
                )
                    .toolbar(.hidden, for: .tabBar)
                    .tabItem {
                        Label(RootTab.community.title(language: leafyLanguage), systemImage: "person.2")
                    }
                    .badge(communityNotificationBadgeViewModel.unreadCount)
                    .tag(RootTab.community)
            }

            CampusAIAssistantView()
                .toolbar(.hidden, for: .tabBar)
                .tabItem {
                    Label(RootTab.leafy.title(language: leafyLanguage), systemImage: RootTab.leafy.systemImage)
                }
                .tag(RootTab.leafy)

            AcademicHubView(selectedTab: $appNavigation.selectedAcademicTab)
                .toolbar(.hidden, for: .tabBar)
                .tabItem {
                    Label(RootTab.academics.title(language: leafyLanguage), systemImage: "book.closed")
                }
                .tag(RootTab.academics)

            ProfileView()
                .toolbar(.hidden, for: .tabBar)
                .tabItem {
                    Label(RootTab.profile.title(language: leafyLanguage), systemImage: "person")
                }
                .tag(RootTab.profile)
        }
        .toolbar(.hidden, for: .tabBar)
        .tint(AppTheme.accent(for: themeColorPreference))
        .safeAreaInset(edge: .bottom, spacing: 0) {
            Color.clear
                .frame(height: RootFloatingTabBar.reservedHeight(controlScale: leafyControlScale))
        }
        .overlay(alignment: .bottom) {
            RootFloatingTabBar(
                selectedTab: $appNavigation.selectedRootTab,
                communityUnreadCount: communityNotificationBadgeViewModel.unreadCount,
                isCommunityEnabled: isCommunityEnabled
            )
        }
    }

    private func handleRootTabChange(to newTab: RootTab) {
        if newTab == .community, !isCommunityEnabled {
            appNavigation.selectedRootTab = .timetable
        }
    }

    private func handleTimeScopePresentationChange(_ isPresented: Bool) {
        guard !isPresented else { return }
        appNavigation.selectedRootTab = .timetable
    }

    @MainActor
    private func restoreCommunityNotificationBadge() async {
        guard isCommunityEnabled else {
            communityNotificationBadgeViewModel.stop(reset: true)
            return
        }
        communitySessionManager.startBootstrapIfNeeded()
        await communitySessionManager.restoreProfileIfPossible()
        syncCommunityNotificationBadgeSubscription(profileID: communitySessionManager.currentUserID)
        await communityNotificationBadgeViewModel.refresh()
    }

    @MainActor
    private func syncCommunityNotificationBadgeSubscription(profileID: UUID?) {
        guard isCommunityEnabled else {
            communityNotificationBadgeViewModel.stop(reset: true)
            return
        }
        if let profileID {
            communityNotificationBadgeViewModel.start(profileID: profileID)
        } else {
            communityNotificationBadgeViewModel.stop(reset: true)
        }
    }

    @MainActor
    private func sanitizeUnavailableRootTab() {
        let isCustomCampus = ActiveCampusContext.identity?.isCustom == true
        if !isCommunityEnabled, appNavigation.selectedRootTab == .community {
            appNavigation.selectedRootTab = .timetable
        }
        if !appNavigation.selectedAcademicTab.isVisible(
            isCustomCampus: isCustomCampus,
            isCommunityEnabled: isCommunityEnabled,
            campusID: ActiveCampusContext.descriptor.id
        ) {
            appNavigation.selectedAcademicTab = .cultivation
        }
        if !isCommunityEnabled {
            communityNotificationBadgeViewModel.stop(reset: true)
        }
    }
}

private extension View {
    @ViewBuilder
    func nativeRootTabBarBehavior() -> some View {
        if #available(iOS 26.0, *) {
            self.tabBarMinimizeBehavior(.never)
        } else {
            self
        }
    }
}

#Preview {
    PreviewRoot()
}

private struct PreviewRoot: View {
    @StateObject private var networkManager = ActiveCampusContext.networkManager
    @StateObject private var appNavigation = AppNavigationCoordinator()
    @StateObject private var communityNotificationBadgeViewModel = CommunityNotificationBadgeViewModel()

    var body: some View {
        if networkManager.hasCachedIdentity {
            ContentView(
                appNavigation: appNavigation,
                communityNotificationBadgeViewModel: communityNotificationBadgeViewModel
            )
        } else {
            LoginView()
        }
    }
}
