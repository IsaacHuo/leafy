import Combine
import OSLog
import QuickLook
import Supabase
import SwiftUI
import SwiftData
import UniformTypeIdentifiers
#if canImport(UIKit)
import UIKit
#elseif canImport(AppKit)
import AppKit
#endif

@MainActor
final class CommunityNotificationBadgeViewModel: ObservableObject {
    @Published private(set) var unreadCount = 0

    private let repository: any CommunityNotificationRepository
    private var profileID: UUID?
    private var subscriptionID: UUID?
    private var realtimeTask: Task<Void, Never>?
    private var scheduledRefreshTask: Task<Void, Never>?
    private var channel: RealtimeChannelV2?

    init(repository: any CommunityNotificationRepository = LiveCommunityRepository()) {
        self.repository = repository
    }

    func start(profileID: UUID) {
        guard !CommunityDiagnosticsOptions.disablesNotifications else {
            CommunityDiagnostics.log.info("Community notification badge start skipped by diagnostics")
            stop(reset: true)
            return
        }
        guard self.profileID != profileID else { return }

        CommunityDiagnostics.log.info("Community notification badge start for profile \(profileID.uuidString, privacy: .public)")
        stop(reset: false)
        self.profileID = profileID
        let subscriptionID = UUID()
        self.subscriptionID = subscriptionID
        scheduleRefresh()
        if CommunityDiagnosticsOptions.disablesNotificationRealtime {
            CommunityDiagnostics.log.info("Community notification realtime subscription skipped by diagnostics")
        } else {
            realtimeTask = Task { [weak self] in
                await self?.subscribeToNotificationChanges(profileID: profileID, subscriptionID: subscriptionID)
            }
        }
    }

    func stop(reset: Bool) {
        CommunityDiagnostics.log.debug("Community notification badge stop reset=\(reset, privacy: .public)")
        realtimeTask?.cancel()
        realtimeTask = nil
        scheduledRefreshTask?.cancel()
        scheduledRefreshTask = nil
        profileID = nil
        subscriptionID = nil

        if let channel {
            removeChannel(channel)
            self.channel = nil
        }

        if reset {
            unreadCount = 0
        }
    }

    func refresh() async {
        guard !CommunityDiagnosticsOptions.disablesNotifications else {
            unreadCount = 0
            return
        }
        guard profileID != nil else {
            unreadCount = 0
            return
        }

        do {
            CommunityDiagnostics.log.info("Community notification badge refresh started")
            unreadCount = try await CommunityTimeout.run(
                seconds: 6,
                message: "未读通知加载超时。"
            ) {
                try await self.repository.fetchUnreadNotificationCount()
            }
        } catch {
            guard !Task.isCancelled else { return }
            CommunityDiagnostics.log.error("Community notification badge refresh failed: \(error.localizedDescription, privacy: .public)")
            unreadCount = 0
        }
    }

    private func scheduleRefresh() {
        scheduledRefreshTask?.cancel()
        scheduledRefreshTask = Task { [weak self] in
            try? await Task.sleep(for: .milliseconds(250))
            guard !Task.isCancelled else { return }
            await self?.refresh()
        }
    }

    private func subscribeToNotificationChanges(profileID: UUID, subscriptionID: UUID) async {
        do {
            CommunityDiagnostics.log.info("Community notification realtime subscription starting")
            try await repository.ensureAnonymousSession()
            guard !Task.isCancelled else { return }
            guard self.subscriptionID == subscriptionID else { return }

            let client = try LeafySupabase.shared.requireClient()
            let channel = client.realtimeV2.channel("community-notifications-\(profileID.uuidString)-\(subscriptionID.uuidString)")
            self.channel = channel

            let filter = RealtimePostgresFilter.eq("recipient_id", value: profileID)
            let inserts = channel.postgresChange(
                InsertAction.self,
                table: "community_notifications",
                filter: filter
            )
            let updates = channel.postgresChange(
                UpdateAction.self,
                table: "community_notifications",
                filter: filter
            )

            let insertTask = Task { [weak self] in
                for await _ in inserts {
                    guard !Task.isCancelled else { return }
                    self?.handleRealtimeChange(profileID: profileID)
                }
            }
            let updateTask = Task { [weak self] in
                for await _ in updates {
                    guard !Task.isCancelled else { return }
                    self?.handleRealtimeChange(profileID: profileID)
                }
            }
            defer {
                insertTask.cancel()
                updateTask.cancel()
                removeChannel(channel)
                if self.subscriptionID == subscriptionID {
                    self.channel = nil
                }
            }

            try await channel.subscribeWithError()
            CommunityDiagnostics.log.info("Community notification realtime subscription active")

            while !Task.isCancelled && self.subscriptionID == subscriptionID {
                try await Task.sleep(for: .seconds(60))
            }
        } catch {
            guard !Task.isCancelled else { return }
            CommunityDiagnostics.log.error("Community notification realtime subscription failed: \(error.localizedDescription, privacy: .public)")
            await refresh()
        }
    }

    private func removeChannel(_ channel: RealtimeChannelV2) {
        Task {
            await LeafySupabase.shared.client?.realtimeV2.removeChannel(channel)
        }
    }

    private func handleRealtimeChange(profileID: UUID) {
        guard self.profileID == profileID else { return }
        scheduleRefresh()
    }
}

struct CommunityRootView: View {
    @Environment(\.leafyControlScale) private var leafyControlScale
    @Environment(\.leafyLanguage) private var leafyLanguage
    @Environment(\.leafyThemeColorPreference) private var themeColorPreference
    @Environment(\.leafyDependencies) private var dependencies
    @EnvironmentObject private var appNavigation: AppNavigationCoordinator
    @ObservedObject private var sessionManager = CommunitySessionManager.shared
    @State private var showingComposer = false
    @State private var showingCommunityProfileEditor = false
    @State private var showingCommunityTerms = false
    @State private var showingNotifications = false
    @State private var showingCommunitySearch = false
    @State private var selectedPost: CommunityPost?
    @State private var communityRefreshID = UUID()
    @State private var communityActionError: String?
    @State private var operationAlert: LeafyOperationAlert?
    @State private var isSubmittingSchoolRequest = false
    @State private var hasAcceptedCommunityTerms: Bool?
    @State private var isPreparingComposer = false
    @StateObject private var communityFeedViewModel = CommunityFeedViewModel()
    @ObservedObject var notificationBadgeViewModel: CommunityNotificationBadgeViewModel

    @State private var isTopicFilterPresented = false
    @State private var selectedCommunityCategory: String?
    @State private var isShowingHotPosts = false
    @State private var communityFeedContentFilter: CommunityFeedContentFilter = .all
    @State private var isCommunityFeedAtTop = true
    @State private var communityTopicFilterHeight: CGFloat = 0

    init(notificationBadgeViewModel: CommunityNotificationBadgeViewModel) {
        self.notificationBadgeViewModel = notificationBadgeViewModel
    }

    var body: some View {
        let _ = CommunityDiagnostics.log.debug("CommunityRootView body evaluated; feedVisible=\(shouldShowCommunityFeed, privacy: .public) options=\(CommunityDiagnosticsOptions.summary, privacy: .public)")
        NavigationStack {
            ZStack(alignment: .top) {
                if CommunityDiagnosticsOptions.usesEmptyShell {
                    CommunityDiagnosticsShellView()
                        .leafyAdaptiveContentWidth(maxWidth: 560, horizontalPadding: AppSpacing.page)
                        .padding(.top, 72)
                } else if shouldShowCommunityFeed {
                    RealCommunitySectionView(
                        selectedCategory: $selectedCommunityCategory,
                        isShowingHotPosts: $isShowingHotPosts,
                        contentFilter: $communityFeedContentFilter,
                        isFeedAtTop: $isCommunityFeedAtTop,
                        selectedPost: $selectedPost,
                        hasAcceptedTerms: $hasAcceptedCommunityTerms,
                        requestProfileCompletion: {
                            showingCommunityProfileEditor = true
                        },
                        refreshID: communityRefreshID,
                        viewModel: communityFeedViewModel,
                        topContentInset: communityHeaderContentInset
                    )
                    .leafyAdaptiveContentWidth(maxWidth: 760, horizontalPadding: AppSpacing.page)

                    communityHeader
                        .zIndex(1)
                } else {
                    CommunityCampusRequestGateView(
                        profile: sessionManager.profile,
                        isBootstrapping: sessionManager.isBootstrapping,
                        bootstrapError: sessionManager.bootstrapError,
                        isSubmitting: isSubmittingSchoolRequest,
                        onSelectCampus: { campus in
                            Task { await selectInitialCampus(campus) }
                        },
                        onSubmitNewSchool: { schoolName in
                            Task { await submitSchoolRequest(schoolName: schoolName) }
                        },
                        onRetry: {
                            Task { await sessionManager.bootstrapCommunityUser(force: true) }
                        }
                    )
                    .leafyAdaptiveContentWidth(maxWidth: 560, horizontalPadding: AppSpacing.page)
                    .padding(.top, 72)
                }
            }
            .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .top)
            .background(LeafyPageBackground())
            .tint(AppTheme.accent(for: themeColorPreference))
            .leafyNavigationBarHidden()
            .sheet(isPresented: $showingComposer) {
                CommunityComposerSheet { message in
                    communityRefreshID = UUID()
                    operationAlert = .success(message)
                }
                    .presentationDetents([.medium, .large])
            }
            .sheet(isPresented: $showingCommunityProfileEditor) {
                CommunityProfileEditorSheet()
                    .presentationDetents([.medium, .large])
            }
            .sheet(isPresented: $showingCommunityTerms) {
                CommunityTermsAgreementSheet {
                    hasAcceptedCommunityTerms = true
                    operationAlert = .success(L10n.text("设置已保存！", language: leafyLanguage))
                }
                    .presentationDetents([.large])
            }
            .sheet(isPresented: $showingCommunitySearch) {
                CommunitySearchSheet()
                    .presentationDetents([.medium, .large])
            }
            .sheet(isPresented: $showingNotifications) {
                CommunityNotificationsSheet(
                    onOpenPost: { post in
                        showingNotifications = false
                        Task { @MainActor in
                            try? await Task.sleep(for: .milliseconds(250))
                            selectedPost = post
                            await refreshUnreadNotificationCount()
                        }
                    },
                    onUnreadStateChanged: {
                        Task { @MainActor in
                            await refreshUnreadNotificationCount()
                        }
                    }
                )
                .presentationDetents([.medium, .large])
            }
            .sheet(item: $selectedPost) { post in
                RealCommunityPostDetailSheet(post: post) { _ in
                    communityRefreshID = UUID()
                } onPostRemoved: {
                    selectedPost = nil
                    communityRefreshID = UUID()
                }
                    .presentationDetents([.medium, .large])
            }
            .alert("社区操作失败", isPresented: Binding(
                get: { communityActionError != nil },
                set: { if !$0 { communityActionError = nil } }
            )) {
                Button("知道了", role: .cancel) {}
            } message: {
                Text(communityActionError ?? "")
            }
            .leafyOperationAlert($operationAlert)
            .task {
                CommunityDiagnostics.log.info("CommunityRootView startup task began; options=\(CommunityDiagnosticsOptions.summary, privacy: .public)")
                guard !CommunityDiagnosticsOptions.disablesRootStartup else {
                    CommunityDiagnostics.log.info("CommunityRootView startup task skipped by diagnostics")
                    return
                }
                sessionManager.startBootstrapIfNeeded()
                guard !CommunityDiagnosticsOptions.disablesNotifications else {
                    CommunityDiagnostics.log.info("CommunityRootView notification refresh skipped by diagnostics")
                    return
                }
                Task {
                    try? await Task.sleep(for: .milliseconds(800))
                    await refreshUnreadNotificationCount()
                }
            }
            .onChange(of: showingNotifications) { _, isShowing in
                if !isShowing, !CommunityDiagnosticsOptions.disablesNotifications {
                    Task { await refreshUnreadNotificationCount() }
                }
            }
            .onChange(of: appNavigation.requestedCommunityPostID) { _, postID in
                guard let postID else { return }
                Task { await openRequestedCommunityPost(id: postID) }
            }
            .onAppear {
                CommunityDiagnostics.log.info("CommunityRootView appeared")
                guard let postID = appNavigation.requestedCommunityPostID else { return }
                Task { await openRequestedCommunityPost(id: postID) }
            }
        }
    }

    private var shouldShowCommunityFeed: Bool {
        if ActiveCampusContext.descriptor.id == .bjfu && ActiveCampusContext.identity?.isCustom != true {
            return sessionManager.profile != nil
        }
        return sessionManager.hasApprovedCommunityAccess
    }

    private var communityHeaderContentInset: CGFloat {
        let baseInset = LeafyRootChromeMetrics.reservedHeight
        guard isTopicFilterPresented, isCommunityFeedAtTop else { return baseInset }
        return baseInset + communityTopicFilterHeight + LeafyRootChromeMetrics.contentSpacing
    }

    @MainActor
    private func selectInitialCampus(_ campus: CommunityCampusOption) async {
        guard !isSubmittingSchoolRequest else { return }
        isSubmittingSchoolRequest = true
        defer { isSubmittingSchoolRequest = false }

        do {
            _ = try await sessionManager.selectCommunityCampus(campusID: campus.id)
            operationAlert = .success("已加入 \(campus.displayName) 社区。之后如需更换学校，请在个人资料中提交审核。")
        } catch {
            communityActionError = error.localizedDescription
        }
    }

    @MainActor
    private func submitSchoolRequest(schoolName: String) async {
        guard !isSubmittingSchoolRequest else { return }
        isSubmittingSchoolRequest = true
        defer { isSubmittingSchoolRequest = false }

        do {
            _ = try await sessionManager.submitCampusMembershipRequest(schoolName: schoolName)
            operationAlert = .success("学校申请已提交，审核通过后会自动进入对应学校社区。")
        } catch {
            communityActionError = error.localizedDescription
        }
    }

    private var communityHeader: some View {
        CommunityNativeGlassGroup(spacing: 10 * leafyControlScale) {
            VStack(alignment: .leading, spacing: 8 * leafyControlScale) {
                HStack(spacing: AppSpacing.compact) {
                    communitySearchButton

                    CommunityNativeGlassGroup(spacing: 9 * leafyControlScale) {
                        HStack(spacing: 9) {
                            DiscoverLiquidGlassIconButton(
                                systemName: isTopicFilterPresented ? "line.3.horizontal.decrease.circle.fill" : "line.3.horizontal.decrease.circle",
                                accessibilityLabel: "筛选话题",
                                action: {
                                    withAnimation(.easeOut(duration: 0.18)) {
                                        isTopicFilterPresented.toggle()
                                    }
                                }
                            )

                            DiscoverLiquidGlassIconButton(
                                systemName: "bell",
                                showsBadge: notificationBadgeViewModel.unreadCount > 0,
                                accessibilityLabel: "通知",
                                action: {
                                    showingNotifications = true
                                }
                            )

                            DiscoverLiquidGlassIconButton(
                                systemName: "plus",
                                isLoading: isPreparingComposer,
                                accessibilityLabel: "发布",
                                action: handleComposerTapped
                            )
                        }
                    }
                }

                if isTopicFilterPresented {
                    CommunityTopicFilterBar(
                        selectedCategory: $selectedCommunityCategory,
                        isShowingHotPosts: $isShowingHotPosts,
                        contentFilter: $communityFeedContentFilter
                    )
                    .background {
                        GeometryReader { geometry in
                            Color.clear.preference(
                                key: CommunityTopicFilterHeightPreferenceKey.self,
                                value: geometry.size.height
                            )
                        }
                    }
                    .onPreferenceChange(CommunityTopicFilterHeightPreferenceKey.self) { height in
                        guard abs(communityTopicFilterHeight - height) > 0.5 else { return }
                        communityTopicFilterHeight = height
                    }
                    .transition(.move(edge: .top).combined(with: .opacity))
                }
            }
        }
        .frame(maxWidth: .infinity)
        .padding(.horizontal, LeafyRootChromeMetrics.horizontalInset)
        .animation(.easeOut(duration: 0.18), value: isTopicFilterPresented)
    }

    private var communitySearchButton: some View {
        let shape = RoundedRectangle(cornerRadius: AppRadius.medium, style: .continuous)

        return Button {
            showingCommunitySearch = true
        } label: {
            HStack(spacing: 8 * leafyControlScale) {
                Image(systemName: "magnifyingglass")
                    .foregroundStyle(AppTheme.tertiaryText)

                Text("搜索帖子")
                    .leafyBody()
                    .foregroundStyle(AppTheme.secondaryText)

                Spacer(minLength: 0)
            }
            .padding(.horizontal, 14 * leafyControlScale)
            .frame(maxWidth: .infinity)
            .frame(height: LeafyRootChromeMetrics.controlDiameter)
            .contentShape(shape)
        }
        .buttonStyle(.plain)
        .contentShape(shape)
        .communityNativeGlassSurface(in: shape, isInteractive: true)
        .accessibilityLabel("搜索帖子")
    }

    private var communityAccessGate: CommunityAccessGate {
        CommunityAccessGate(
            sessionManager: sessionManager,
            termsChecker: dependencies.communityRepository
        )
    }

    private var canPresentComposerImmediately: Bool {
        hasAcceptedCommunityTerms == true
            && sessionManager.currentUserID != nil
            && !sessionManager.requiresProfileCompletion
            && sessionManager.hasApprovedCommunityAccess
    }

    @MainActor
    private func handleComposerTapped() {
        guard !isPreparingComposer else { return }
        if canPresentComposerImmediately {
            showingComposer = true
            return
        }

        isPreparingComposer = true
        Task { await prepareComposer() }
    }

    @MainActor
    private func prepareComposer() async {
        defer { isPreparingComposer = false }
        switch await communityAccessGate.evaluate(.postCreation) {
        case .allowed:
            showingComposer = true
        case .requiresProfileCompletion:
            showingCommunityProfileEditor = true
        case .requiresTermsAcceptance:
            showingCommunityTerms = true
        case .failed(let message):
            communityActionError = message
        }
    }

    @MainActor
    private func refreshUnreadNotificationCount() async {
        guard !CommunityDiagnosticsOptions.disablesNotifications else {
            notificationBadgeViewModel.stop(reset: true)
            return
        }
        await notificationBadgeViewModel.refresh()
    }

    @MainActor
    private func openRequestedCommunityPost(id postID: UUID) async {
        do {
            try await dependencies.communityRepository.ensureAnonymousSession()
            guard let post = try await dependencies.communityRepository.fetchPost(postID: postID) else {
                appNavigation.requestedCommunityPostID = nil
                communityActionError = L10n.text("帖子已不存在或不可见。", language: leafyLanguage)
                return
            }
            appNavigation.requestedCommunityPostID = nil
            selectedPost = post
        } catch {
            appNavigation.requestedCommunityPostID = nil
            communityActionError = error.localizedDescription
        }
    }
}

private struct CommunityTopicFilterHeightPreferenceKey: PreferenceKey {
    static var defaultValue: CGFloat = 0

    static func reduce(value: inout CGFloat, nextValue: () -> CGFloat) {
        value = max(value, nextValue())
    }
}

private struct CommunityDiagnosticsShellView: View {
    var body: some View {
        VStack(alignment: .leading, spacing: AppSpacing.compact) {
            Image(systemName: "stethoscope")
                .font(.system(size: 28, weight: .semibold))
                .foregroundStyle(AppTheme.accent)
                .frame(width: 48, height: 48)
                .background(AppTheme.accentSoft, in: Circle())

            Text("社区诊断空壳")
                .leafyHeadline()
                .foregroundStyle(AppTheme.primaryText)

            Text("已跳过社区会话、条款、Feed 和通知启动链路。")
                .leafyBody()
                .foregroundStyle(AppTheme.secondaryText)
                .fixedSize(horizontal: false, vertical: true)
        }
        .padding(AppSpacing.section)
        .leafyCardStyle()
    }
}

private struct CommunityCampusRequestGateView: View {
    @Environment(\.leafyThemeColorPreference) private var themeColorPreference
    let profile: CommunityProfile?
    let isBootstrapping: Bool
    let bootstrapError: String?
    let isSubmitting: Bool
    let onSelectCampus: (CommunityCampusOption) -> Void
    let onSubmitNewSchool: (String) -> Void
    let onRetry: () -> Void

    private var status: CommunityAccessStatus {
        profile?.communityAccessStatus ?? .general
    }

    private var iconName: String {
        switch status {
        case .pending:
            return "hourglass"
        case .rejected:
            return "exclamationmark.triangle"
        case .approved:
            return "checkmark.seal"
        case .general:
            return "building.2"
        }
    }

    private var title: String {
        if isBootstrapping && profile == nil {
            return "正在同步社区身份"
        }
        if bootstrapError != nil && profile == nil {
            return "社区身份同步失败"
        }
        switch status {
        case .pending:
            return "学校申请审核中"
        case .rejected:
            return "当前为通用模式"
        case .approved:
            return "社区身份已通过"
        case .general:
            return "选择学校社区"
        }
    }

    private var detail: String {
        if let bootstrapError, profile == nil {
            return bootstrapError
        }
        switch status {
        case .pending:
            let school = profile?.communitySchoolName?.trimmingCharacters(in: .whitespacesAndNewlines) ?? ""
            return school.isEmpty
                ? "申请通过后会自动进入对应学校社区。"
                : "\(school) 的社区申请正在审核，审核通过后会自动进入学校社区。"
        case .rejected:
            return "您申请的学校不通过，您现在是处于通用的模式下，社区功能暂不开放。"
        case .approved:
            return "正在进入学校社区。"
        case .general:
            return "通用入口可以继续使用本地学业功能；首次选择已有学校社区会立即生效，之后更换学校需要审核。"
        }
    }

    var body: some View {
        VStack(alignment: .leading, spacing: AppSpacing.card) {
            Image(systemName: iconName)
                .font(.system(size: 34, weight: .semibold))
                .foregroundStyle(AppTheme.accent(for: themeColorPreference))
                .frame(width: 56, height: 56)
                .background(AppTheme.accent(for: themeColorPreference).opacity(0.12), in: Circle())

            VStack(alignment: .leading, spacing: AppSpacing.micro) {
                Text(title)
                    .font(.title3.weight(.semibold))
                    .foregroundStyle(AppTheme.primaryText)
                Text(detail)
                    .font(.callout)
                    .foregroundStyle(AppTheme.secondaryText)
                    .fixedSize(horizontal: false, vertical: true)
            }

            if status == .rejected,
               let reason = profile?.communityRejectionReason?.trimmingCharacters(in: .whitespacesAndNewlines),
               !reason.isEmpty {
                Text(reason)
                    .font(.footnote)
                    .foregroundStyle(AppTheme.secondaryText)
                    .padding(AppSpacing.compact)
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .background(.thinMaterial, in: RoundedRectangle(cornerRadius: AppRadius.small, style: .continuous))
            }

            if profile != nil && status != .pending {
                CommunityCampusSelectionPanel(
                    mode: .initial,
                    isSubmitting: isSubmitting,
                    onSelectCampus: onSelectCampus,
                    onSubmitNewSchool: onSubmitNewSchool
                )
            }

            if profile == nil, bootstrapError != nil {
                Button("重试同步") {
                    onRetry()
                }
                .buttonStyle(.borderedProminent)
                .disabled(isBootstrapping)
            }
        }
        .padding(AppSpacing.section)
        .leafyCardStyle()
    }
}

enum CommunityCampusSelectionMode: Equatable {
    case initial
    case change(currentSchoolName: String?)

    var searchPrompt: String {
        switch self {
        case .initial:
            return "搜索已有学校"
        case .change:
            return "搜索新的学校社区"
        }
    }

    var emptyResultMessage: String {
        switch self {
        case .initial:
            return "没找到学校时，可以申请新增学校社区。"
        case .change:
            return "当前只支持在已有学校社区之间提交更换申请。"
        }
    }

    var confirmationTitle: String {
        switch self {
        case .initial:
            return "确认加入这个学校社区？"
        case .change:
            return "提交更换学校申请？"
        }
    }

    func confirmationMessage(for campus: CommunityCampusOption) -> String {
        switch self {
        case .initial:
            return "你将加入“\(campus.displayName)”社区。之后如果要更换学校，需要在个人资料中提交审核。"
        case .change(let currentSchoolName):
            let current = currentSchoolName?.trimmingCharacters(in: .whitespacesAndNewlines)
            if let current, !current.isEmpty {
                return "你将申请从“\(current)”更换到“\(campus.displayName)”。审核通过前仍保留当前学校社区。"
            }
            return "你将申请更换到“\(campus.displayName)”。审核通过前不会改变当前学校社区。"
        }
    }
}

struct CommunityCampusSelectionPanel: View {
    @Environment(\.leafyThemeColorPreference) private var themeColorPreference
    @FocusState private var isSearchFocused: Bool
    @State private var searchText = ""
    @State private var campusOptions: [CommunityCampusOption] = []
    @State private var selectedCampus: CommunityCampusOption?
    @State private var isLoading = false
    @State private var errorMessage: String?
    @State private var pendingConfirmation: CommunityCampusOption?

    let mode: CommunityCampusSelectionMode
    let isSubmitting: Bool
    let onSelectCampus: (CommunityCampusOption) -> Void
    var onSubmitNewSchool: ((String) -> Void)?

    private var trimmedSearchText: String {
        searchText.trimmingCharacters(in: .whitespacesAndNewlines)
    }

    private var canSubmitNewSchool: Bool {
        onSubmitNewSchool != nil && !trimmedSearchText.isEmpty && !isSubmitting
    }

    var body: some View {
        VStack(alignment: .leading, spacing: AppSpacing.compact) {
            TextField(mode.searchPrompt, text: $searchText)
                .leafyDisableAutocapitalization()
                .disableAutocorrection(true)
                .textFieldStyle(.roundedBorder)
                .focused($isSearchFocused)
                .submitLabel(.search)
                .onSubmit {
                    Task { await loadCampuses() }
                }

            if let errorMessage {
                Text(errorMessage)
                    .microCaption()
                    .foregroundStyle(AppTheme.danger)
            }

            if isLoading {
                HStack(spacing: 8) {
                    ProgressView()
                    Text("正在搜索学校")
                        .microCaption()
                        .foregroundStyle(AppTheme.secondaryText)
                }
                .frame(maxWidth: .infinity, alignment: .leading)
            } else if campusOptions.isEmpty {
                Text(mode.emptyResultMessage)
                    .microCaption()
                    .foregroundStyle(AppTheme.secondaryText)
            } else {
                VStack(spacing: 8) {
                    ForEach(campusOptions) { campus in
                        Button {
                            selectedCampus = campus
                        } label: {
                            HStack(spacing: 10) {
                                VStack(alignment: .leading, spacing: 2) {
                                    Text(campus.displayName)
                                        .leafyBody()
                                        .foregroundStyle(AppTheme.primaryText)
                                    Text(campus.shortName)
                                        .microCaption()
                                        .foregroundStyle(AppTheme.secondaryText)
                                }
                                Spacer()
                                Image(systemName: selectedCampus?.id == campus.id ? "checkmark.circle.fill" : "circle")
                                    .foregroundStyle(selectedCampus?.id == campus.id ? AppTheme.accent(for: themeColorPreference) : AppTheme.tertiaryText)
                            }
                            .padding(12)
                            .background(AppTheme.fill, in: RoundedRectangle(cornerRadius: AppRadius.medium, style: .continuous))
                            .contentShape(RoundedRectangle(cornerRadius: AppRadius.medium, style: .continuous))
                        }
                        .buttonStyle(.plain)
                    }
                }
            }

            Button {
                if let selectedCampus {
                    pendingConfirmation = selectedCampus
                }
            } label: {
                HStack(spacing: 8) {
                    if isSubmitting {
                        ProgressView()
                    }
                    Text(primaryActionTitle)
                }
                .frame(maxWidth: .infinity)
            }
            .buttonStyle(.borderedProminent)
            .tint(AppTheme.accent(for: themeColorPreference))
            .disabled(selectedCampus == nil || isSubmitting)

            if let onSubmitNewSchool {
                Button {
                    onSubmitNewSchool(trimmedSearchText)
                } label: {
                    Text("找不到？申请新增“\(trimmedSearchText)”")
                        .frame(maxWidth: .infinity)
                }
                .buttonStyle(.bordered)
                .disabled(!canSubmitNewSchool)
            }
        }
        .task {
            await loadCampuses()
        }
        .onChange(of: searchText) { _, _ in
            selectedCampus = nil
            Task {
                try? await Task.sleep(for: .milliseconds(250))
                guard !Task.isCancelled else { return }
                await loadCampuses()
            }
        }
        .confirmationDialog(
            mode.confirmationTitle,
            isPresented: Binding(
                get: { pendingConfirmation != nil },
                set: { if !$0 { pendingConfirmation = nil } }
            ),
            titleVisibility: .visible,
            presenting: pendingConfirmation
        ) { campus in
            Button(primaryActionTitle) {
                pendingConfirmation = nil
                isSearchFocused = false
                onSelectCampus(campus)
            }
            Button("取消", role: .cancel) {
                pendingConfirmation = nil
            }
        } message: { campus in
            Text(mode.confirmationMessage(for: campus))
        }
        .toolbar {
            if isSearchFocused {
                ToolbarItemGroup(placement: .leafyKeyboard) {
                    Spacer()
                    Button("完成") {
                        isSearchFocused = false
                    }
                }
            }
        }
    }

    private var primaryActionTitle: String {
        switch mode {
        case .initial:
            return "确认加入学校社区"
        case .change:
            return "提交更换申请"
        }
    }

    @MainActor
    private func loadCampuses() async {
        guard !isLoading else { return }
        isLoading = true
        defer { isLoading = false }

        do {
            campusOptions = try await CommunitySessionManager.shared.searchCommunityCampuses(
                query: trimmedSearchText,
                limit: 12
            )
            errorMessage = nil
        } catch {
            campusOptions = []
            errorMessage = error.localizedDescription
        }
    }
}

private struct DiscoverLiquidGlassIconButton: View {
    @Environment(\.leafyControlScale) private var leafyControlScale
    @Environment(\.leafyThemeColorPreference) private var themeColorPreference

    let systemName: String
    var showsBadge = false
    var isLoading = false
    let accessibilityLabel: String
    let action: () -> Void

    var body: some View {
        Button(action: action) {
            label
                .communityNativeGlassSurface(in: Circle(), isInteractive: true)
        }
        .buttonStyle(.plain)
        .disabled(isLoading)
        .accessibilityLabel(accessibilityLabel)
    }

    private var label: some View {
        ZStack(alignment: .topTrailing) {
            Group {
                if isLoading {
                    ProgressView()
                        .controlSize(.small)
                } else {
                    Image(systemName: systemName)
                        .font(.system(size: 18 * leafyControlScale, weight: .semibold))
                }
            }
            .foregroundStyle(AppTheme.accentEmphasis(for: themeColorPreference))
            .frame(
                width: LeafyRootChromeMetrics.controlDiameter,
                height: LeafyRootChromeMetrics.controlDiameter
            )
            .contentShape(Circle())

            if showsBadge {
                Circle()
                    .fill(AppTheme.danger)
                    .frame(width: 9 * leafyControlScale, height: 9 * leafyControlScale)
                    .overlay(
                        Circle()
                            .stroke(Color(uiColor: .systemBackground), lineWidth: 1.5)
                    )
                    .offset(x: -4 * leafyControlScale, y: 4 * leafyControlScale)
            }
        }
    }
}

private struct CommunityNativeGlassGroup<Content: View>: View {
    let spacing: CGFloat
    @ViewBuilder let content: () -> Content

    init(spacing: CGFloat, @ViewBuilder content: @escaping () -> Content) {
        self.spacing = spacing
        self.content = content
    }

    var body: some View {
        #if os(iOS)
        if #available(iOS 26.0, *), !CommunityDiagnosticsOptions.disablesGlassEffects {
            GlassEffectContainer(spacing: spacing) {
                content()
            }
        } else {
            content()
        }
        #else
        content()
        #endif
    }
}

private extension View {
    @ViewBuilder
    func communityNativeGlassSurface<S: InsettableShape>(
        in shape: S,
        isInteractive: Bool
    ) -> some View {
        #if os(iOS)
        if #available(iOS 26.0, *), !CommunityDiagnosticsOptions.disablesGlassEffects {
            let glass = isInteractive ? Glass.regular.interactive() : Glass.regular
            self.glassEffect(glass, in: shape)
        } else {
            self
                .background(.ultraThinMaterial, in: shape)
                .overlay(
                    shape.stroke(AppTheme.separator.opacity(0.8), lineWidth: 1)
                )
        }
        #else
        self
            .background(.ultraThinMaterial, in: shape)
            .overlay(shape.stroke(AppTheme.separator.opacity(0.8), lineWidth: 1))
        #endif
    }
}

@MainActor
private enum NotificationOpenResult {
    case post(CommunityPost)
    case announcement(SiteAnnouncement)
}

@MainActor
private final class CommunityNotificationsViewModel: ObservableObject {
    @Published private(set) var items: [NotificationFeedItem] = []
    @Published private(set) var settings: CommunityNotificationSettings?
    @Published private(set) var isLoading = false
    @Published private(set) var activeItemID: String?
    @Published private(set) var isUpdatingSettings = false
    @Published private(set) var isMarkingAllRead = false
    @Published var errorMessage: String?

    private let service = CommunityService.shared

    var isMutedAll: Bool {
        settings?.mutedAll ?? false
    }

    var hasUnreadItems: Bool {
        items.contains { !$0.isRead }
    }

    func load() async {
        isLoading = true
        defer { isLoading = false }

        do {
            try await service.ensureAnonymousSession()
        } catch {
            items = []
            errorMessage = error.localizedDescription
            return
        }

        await CommunitySessionManager.shared.restoreProfileIfPossible()

        do {
            settings = try await service.fetchNotificationSettings()
            if settings?.mutedAll == true {
                items = []
                errorMessage = nil
                return
            }

            items = try await service.fetchNotificationFeed()
            errorMessage = nil
        } catch {
            items = []
            errorMessage = error.localizedDescription
        }
    }

    func setMutedAll(_ muted: Bool) async -> Bool {
        guard !isUpdatingSettings else { return false }
        isUpdatingSettings = true
        defer { isUpdatingSettings = false }

        do {
            settings = try await service.updateNotificationSettings(mutedAll: muted)
            if muted {
                items = []
            } else {
                items = try await service.fetchNotificationFeed()
            }
            errorMessage = nil
            return true
        } catch {
            errorMessage = error.localizedDescription
            return false
        }
    }

    func markAllRead() async -> Bool {
        guard !isMarkingAllRead, !isLoading, hasUnreadItems else { return false }
        isMarkingAllRead = true
        defer { isMarkingAllRead = false }

        do {
            try await service.markNotificationFeedRead()
            let readAt = ISO8601DateFormatter().string(from: Date())
            items = items.map { $0.markingRead(at: readAt) }
            errorMessage = nil
            return true
        } catch {
            errorMessage = error.localizedDescription
            return false
        }
    }

    func dismissItem(_ item: NotificationFeedItem) async -> Bool {
        guard activeItemID == nil else { return false }
        activeItemID = item.id
        defer { activeItemID = nil }

        do {
            try await service.dismissNotificationFeedItem(item)
            items.removeAll { $0.id == item.id }
            errorMessage = nil
            return true
        } catch {
            errorMessage = error.localizedDescription
            return false
        }
    }

    func openItem(_ item: NotificationFeedItem) async -> NotificationOpenResult? {
        guard activeItemID == nil else { return nil }
        activeItemID = item.id
        defer { activeItemID = nil }

        switch item {
        case .community(let notification):
            return await openCommunityNotification(notification, itemID: item.id)
        case .announcement(let announcement):
            return await openSiteAnnouncement(announcement, itemID: item.id)
        }
    }

    private func openCommunityNotification(_ notification: CommunityNotification, itemID: String) async -> NotificationOpenResult? {
        guard let postID = notification.postID else {
            errorMessage = "这条通知没有关联帖子。"
            return nil
        }

        do {
            if !notification.isRead {
                try await service.markNotificationRead(notificationID: notification.id)
                if let index = items.firstIndex(where: { $0.id == itemID }) {
                    items[index] = .community(notification.markingRead())
                }
            }

            guard let post = try await service.fetchPost(postID: postID) else {
                errorMessage = "关联帖子已不存在。"
                return nil
            }

            errorMessage = nil
            return .post(post)
        } catch {
            errorMessage = error.localizedDescription
            return nil
        }
    }

    private func openSiteAnnouncement(_ announcement: SiteAnnouncement, itemID: String) async -> NotificationOpenResult? {
        do {
            if !announcement.isRead {
                try await service.markSiteAnnouncementRead(announcementID: announcement.id)
                let readAt = ISO8601DateFormatter().string(from: Date())
                let updatedAnnouncement = announcement.markingRead(at: readAt)
                if let index = items.firstIndex(where: { $0.id == itemID }) {
                    items[index] = .announcement(updatedAnnouncement)
                }
                errorMessage = nil
                return .announcement(updatedAnnouncement)
            }

            errorMessage = nil
            return .announcement(announcement)
        } catch {
            errorMessage = error.localizedDescription
            return nil
        }
    }
}

private struct CommunityNotificationsSheet: View {
    let onOpenPost: (CommunityPost) -> Void
    let onUnreadStateChanged: () -> Void

    @Environment(\.dismiss) private var dismiss
    @Environment(\.leafyLanguage) private var leafyLanguage
    @StateObject private var viewModel = CommunityNotificationsViewModel()
    @State private var selectedAnnouncement: SiteAnnouncement?
    @State private var operationAlert: LeafyOperationAlert?

    var body: some View {
        NavigationStack {
            List {
                Section {
                    CommunityNotificationSettingsRow(
                        isMuted: Binding(
                            get: { viewModel.isMutedAll },
                            set: { muted in
                                Task { await setMutedAll(muted) }
                            }
                        ),
                        isUpdating: viewModel.isUpdatingSettings
                    )
                }
                .listRowBackground(Color.clear)
                .listRowSeparator(.hidden)
                .listRowInsets(EdgeInsets(top: AppSpacing.compact, leading: AppSpacing.page, bottom: AppSpacing.micro, trailing: AppSpacing.page))

                if viewModel.isLoading && viewModel.items.isEmpty && !viewModel.isMutedAll {
                    Section {
                        CommunityNotificationStateView(
                            title: "正在加载通知",
                            message: "稍等一下，正在同步最新通知。",
                            systemImage: "bell.badge",
                            showsProgress: true
                        )
                    }
                    .listRowBackground(Color.clear)
                    .listRowSeparator(.hidden)
                } else if viewModel.isMutedAll {
                    Section {
                        CommunityNotificationStateView(
                            title: "已关闭通知",
                            message: "重新打开后会继续接收新的评论和点赞通知。",
                            systemImage: "bell.slash"
                        )
                    }
                    .listRowBackground(Color.clear)
                    .listRowSeparator(.hidden)
                } else if let errorMessage = viewModel.errorMessage, viewModel.items.isEmpty {
                    Section {
                        CommunityNotificationErrorCard(message: errorMessage) {
                            Task { await viewModel.load() }
                        }
                    }
                    .listRowBackground(Color.clear)
                    .listRowSeparator(.hidden)
                } else if viewModel.items.isEmpty {
                    Section {
                        CommunityNotificationStateView(
                            title: "暂无通知",
                            message: "有全站通知、评论或点赞时会显示在这里。",
                            systemImage: "bell"
                        )
                    }
                    .listRowBackground(Color.clear)
                    .listRowSeparator(.hidden)
                } else {
                    Section {
                        if let errorMessage = viewModel.errorMessage {
                            Text(errorMessage)
                                .leafyBody()
                                .foregroundStyle(AppTheme.danger)
                                .padding(14)
                                .background(AppTheme.cardBackground, in: RoundedRectangle(cornerRadius: AppRadius.medium, style: .continuous))
                        }

                        ForEach(viewModel.items) { item in
                            Button {
                                Task {
                                    guard let result = await viewModel.openItem(item) else { return }
                                    if !item.isRead {
                                        onUnreadStateChanged()
                                    }
                                    switch result {
                                    case .post(let post):
                                        dismiss()
                                        onOpenPost(post)
                                    case .announcement(let announcement):
                                        selectedAnnouncement = announcement
                                    }
                                }
                            } label: {
                                CommunityNotificationCard(
                                    item: item,
                                    isLoading: viewModel.activeItemID == item.id
                                )
                            }
                            .buttonStyle(.plain)
                            .swipeActions(edge: .trailing, allowsFullSwipe: true) {
                                Button(role: .destructive) {
                                    Task { await dismiss(item) }
                                } label: {
                                    Label("删除", systemImage: "trash")
                                }
                            }
                            .listRowInsets(EdgeInsets(top: 4, leading: AppSpacing.page, bottom: 4, trailing: AppSpacing.page))
                            .listRowBackground(Color.clear)
                            .listRowSeparator(.hidden)
                        }
                    }
                }
            }
            .listStyle(.plain)
            .environment(\.defaultMinListRowHeight, 1)
            .scrollContentBackground(.hidden)
            .background(LeafyPageBackground())
            .navigationTitle("通知")
            .leafyInlineNavigationTitle()
            .toolbar {
                ToolbarItem(placement: .leafyTrailing) {
                    Button {
                        Task { await markAllRead() }
                    } label: {
                        if viewModel.isMarkingAllRead {
                            ProgressView()
                                .scaleEffect(0.78)
                        } else {
                            Label("全部已读", systemImage: "checkmark.circle")
                        }
                    }
                    .disabled(!canMarkAllRead)
                }
            }
            .task {
                await viewModel.load()
            }
            .refreshable {
                await viewModel.load()
            }
            .sheet(item: $selectedAnnouncement) { announcement in
                SiteAnnouncementDetailSheet(announcement: announcement)
                    .presentationDetents([.medium, .large])
            }
            .leafyOperationAlert($operationAlert)
        }
    }

    private var canMarkAllRead: Bool {
        viewModel.hasUnreadItems
            && !viewModel.isLoading
            && !viewModel.isMutedAll
            && !viewModel.isMarkingAllRead
    }

    @MainActor
    private func setMutedAll(_ muted: Bool) async {
        guard await viewModel.setMutedAll(muted) else { return }
        onUnreadStateChanged()
    }

    @MainActor
    private func markAllRead() async {
        guard await viewModel.markAllRead() else { return }
        onUnreadStateChanged()
        operationAlert = .success(L10n.text("已标记全部通知为已读。", language: leafyLanguage))
    }

    @MainActor
    private func dismiss(_ item: NotificationFeedItem) async {
        guard await viewModel.dismissItem(item) else { return }
        if !item.isRead {
            onUnreadStateChanged()
        }
        operationAlert = .success(L10n.text("通知已删除！", language: leafyLanguage))
    }
}

private struct CommunityNotificationSettingsRow: View {
    @Binding var isMuted: Bool
    let isUpdating: Bool

    var body: some View {
        HStack(spacing: 12) {
            Image(systemName: isMuted ? "bell.slash.fill" : "bell.badge.fill")
                .font(.system(size: 15, weight: .semibold))
                .foregroundStyle(isMuted ? AppTheme.tertiaryText : AppTheme.accentEmphasis)
                .frame(width: 30, height: 30)
                .background(AppTheme.softFill, in: RoundedRectangle(cornerRadius: AppRadius.small, style: .continuous))

            VStack(alignment: .leading, spacing: 2) {
                Text("关闭通知")
                    .leafyBody()
                    .foregroundStyle(AppTheme.primaryText)
                Text("关闭后评论和点赞不会再生成新通知。")
                    .microCaption()
                    .foregroundStyle(AppTheme.secondaryText)
                    .lineLimit(1)
            }

            Spacer(minLength: AppSpacing.compact)

            Toggle("", isOn: $isMuted)
                .labelsHidden()
                .disabled(isUpdating)
        }
        .padding(.horizontal, 14)
        .padding(.vertical, 10)
        .background(AppTheme.cardBackground, in: RoundedRectangle(cornerRadius: AppRadius.medium, style: .continuous))
        .overlay(
            RoundedRectangle(cornerRadius: AppRadius.medium, style: .continuous)
                .stroke(AppTheme.separator, lineWidth: 1)
        )
        .opacity(isUpdating ? 0.72 : 1)
    }
}

private struct CommunityNotificationStateView: View {
    let title: String
    let message: String
    let systemImage: String
    var showsProgress = false

    var body: some View {
        VStack(spacing: 10) {
            if showsProgress {
                ProgressView()
            } else {
                Image(systemName: systemImage)
                    .font(.system(size: 22, weight: .semibold))
                    .foregroundStyle(AppTheme.tertiaryText)
            }

            VStack(spacing: 3) {
                Text(title)
                    .leafyHeadline()
                    .foregroundStyle(AppTheme.primaryText)
                Text(message)
                    .microCaption()
                    .foregroundStyle(AppTheme.secondaryText)
                    .multilineTextAlignment(.center)
            }
        }
        .frame(maxWidth: .infinity)
        .padding(.vertical, 24)
    }
}

private struct CommunityNotificationCard: View {
    let item: NotificationFeedItem
    let isLoading: Bool

    var body: some View {
        HStack(alignment: .center, spacing: 10) {
            Image(systemName: item.systemImage)
                .font(.system(size: 13, weight: .semibold))
                .foregroundStyle(tint)
                .frame(width: 28, height: 28)
                .background(tint.opacity(0.14), in: RoundedRectangle(cornerRadius: AppRadius.small, style: .continuous))

            VStack(alignment: .leading, spacing: 4) {
                HStack(alignment: .firstTextBaseline, spacing: 6) {
                    Text(item.title)
                        .leafyHeadline()
                        .foregroundStyle(AppTheme.primaryText)
                        .lineLimit(1)
                        .frame(maxWidth: .infinity, alignment: .leading)

                    if !item.isRead {
                        Circle()
                            .fill(AppTheme.danger)
                            .frame(width: 7, height: 7)
                            .accessibilityLabel("未读")
                    }
                }

                if let body = item.body?.trimmingCharacters(in: .whitespacesAndNewlines), !body.isEmpty {
                    Text(body)
                        .leafySubheadline()
                        .foregroundStyle(AppTheme.secondaryText)
                        .lineLimit(1)
                }

                HStack(spacing: 8) {
                    Text(item.relativeTimestamp)
                        .microCaption()
                        .foregroundStyle(AppTheme.tertiaryText)

                    if isLoading {
                        ProgressView()
                            .scaleEffect(0.72)
                    }
                }
            }
        }
        .padding(.horizontal, 12)
        .padding(.vertical, 10)
        .background(AppTheme.cardBackground, in: RoundedRectangle(cornerRadius: AppRadius.medium, style: .continuous))
        .overlay(
            RoundedRectangle(cornerRadius: AppRadius.medium, style: .continuous)
                .stroke(item.isRead ? AppTheme.separator : tint.opacity(0.24), lineWidth: 1)
        )
        .contentShape(RoundedRectangle(cornerRadius: AppRadius.medium, style: .continuous))
        .opacity(item.isRead ? 0.78 : 1)
    }

    private var tint: Color {
        switch item {
        case .community(let notification):
            return notification.type == .like ? AppTheme.featureTints[1] : AppTheme.featureTints[0]
        case .announcement(let announcement):
            switch announcement.level {
            case .info:
                return AppTheme.accent
            case .warning:
                return AppTheme.warning
            case .urgent:
                return AppTheme.danger
            }
        }
    }
}

private struct SiteAnnouncementDetailSheet: View {
    let announcement: SiteAnnouncement

    @Environment(\.dismiss) private var dismiss

    var body: some View {
        NavigationStack {
            ScrollView {
                VStack(alignment: .leading, spacing: AppSpacing.card) {
                    LeafySectionTitle(announcement.title, subtitle: announcement.relativeTimestamp)

                    HStack(spacing: 8) {
                        LeafyIconBadge(systemName: announcement.systemImage, tint: tint)

                        Text(levelText)
                            .leafySubheadline()
                            .foregroundStyle(tint)
                            .padding(.horizontal, 10)
                            .padding(.vertical, 6)
                            .background(tint.opacity(0.12), in: Capsule())
                    }

                    Text(announcement.body)
                        .leafyBody()
                        .foregroundStyle(AppTheme.primaryText)
                        .lineSpacing(4)
                        .frame(maxWidth: .infinity, alignment: .leading)
                        .padding(18)
                        .leafyCardStyle()
                }
                .padding(AppSpacing.page)
            }
            .background(LeafyPageBackground())
            .navigationTitle("全站通知")
            .leafyInlineNavigationTitle()
            .toolbar {
                ToolbarItem(placement: .leafyTrailing) {
                    Button("完成") {
                        dismiss()
                    }
                }
            }
        }
    }

    private var tint: Color {
        switch announcement.level {
        case .info:
            return AppTheme.accent
        case .warning:
            return AppTheme.warning
        case .urgent:
            return AppTheme.danger
        }
    }

    private var levelText: String {
        switch announcement.level {
        case .info:
            return "普通公告"
        case .warning:
            return "重要公告"
        case .urgent:
            return "紧急公告"
        }
    }
}

private struct CommunityNotificationErrorCard: View {
    let message: String
    let retry: () -> Void

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            Text(message)
                .leafyBody()
                .foregroundStyle(AppTheme.secondaryText)

            Button("重试", action: retry)
                .foregroundStyle(AppTheme.accentEmphasis)
        }
        .padding(18)
        .leafyCardStyle()
    }
}
