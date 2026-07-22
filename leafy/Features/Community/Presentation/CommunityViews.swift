import Combine
import OSLog
import PhotosUI
import SwiftUI
import UniformTypeIdentifiers

private struct CommunityDraftImage: Identifiable, Hashable {
    let id: UUID
    let image: UIImage
    let upload: CommunityImageUpload
}

private struct CommunityFeedTaskID: Hashable {
    let refreshID: UUID
    let query: CommunityFeedQuery
}

private let communityCategories = [
    "学习交流",
    "校园生活",
    "活动社团",
    "问答互助",
    "闲聊吹水",
    "二手交易"
]

private let communityReportReasons = [
    "辱骂骚扰",
    "色情低俗",
    "隐私泄露",
    "暴力威胁",
    "其他违规"
]

private enum CommunityModerationTarget: Identifiable, Equatable {
    case post(CommunityPost)
    case comment(CommunityComment)

    var id: String {
        switch self {
        case .post(let post):
            return "post-\(post.id.uuidString)"
        case .comment(let comment):
            return "comment-\(comment.id.uuidString)"
        }
    }
}

@MainActor
final class CommunityPostDetailViewModel: ObservableObject {
    @Published private(set) var post: CommunityPost
    @Published private(set) var comments: [CommunityComment] = []
    @Published private(set) var isLoading = false
    @Published private(set) var isLikeLoading = false
    @Published private(set) var isFavoriteLoading = false
    @Published private(set) var isSubmitting = false
    @Published var errorMessage: String?

    private let postID: UUID
    private let repository: any CommunityPostDetailRepository

    init(post: CommunityPost, repository: any CommunityPostDetailRepository = LiveCommunityRepository()) {
        self.post = post
        postID = post.id
        self.repository = repository
    }

    func load() async {
        isLoading = true
        defer { isLoading = false }

        do {
            if let refreshedPost = try await repository.fetchPost(postID: postID) {
                post = refreshedPost
            }
            comments = try await repository.fetchComments(postID: postID)
            errorMessage = nil
        } catch {
            errorMessage = error.localizedDescription
        }
    }

    func submitComment(body: String) async -> Bool {
        guard !isSubmitting else { return false }

        let trimmed = body.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else {
            errorMessage = L10n.text("评论内容不能为空。")
            return false
        }

        isSubmitting = true
        defer { isSubmitting = false }

        do {
            let comment = try await repository.createComment(postID: postID, body: trimmed)
            comments.append(comment)
            errorMessage = nil
            return true
        } catch {
            errorMessage = error.localizedDescription
            return false
        }
    }

    func toggleLike() async -> CommunityPost? {
        guard !isLikeLoading else { return nil }
        isLikeLoading = true
        defer { isLikeLoading = false }

        do {
            let updatedPost = try await repository.togglePostLike(postID: postID)
            post = updatedPost
            errorMessage = nil
            return updatedPost
        } catch {
            errorMessage = error.localizedDescription
            return nil
        }
    }

    func toggleFavorite() async -> CommunityPost? {
        guard !isFavoriteLoading else { return nil }
        isFavoriteLoading = true
        defer { isFavoriteLoading = false }

        do {
            let updatedPost = try await repository.togglePostFavorite(postID: postID)
            post = updatedPost
            errorMessage = nil
            return updatedPost
        } catch {
            errorMessage = error.localizedDescription
            return nil
        }
    }

    func reportPost(reason: String) async -> Bool {
        do {
            try await repository.reportPost(postID: postID, reason: reason)
            errorMessage = nil
            return true
        } catch {
            errorMessage = error.localizedDescription
            return false
        }
    }

    func deletePost() async -> Bool {
        do {
            try await repository.deletePost(postID: postID)
            errorMessage = nil
            return true
        } catch {
            errorMessage = error.localizedDescription
            return false
        }
    }

    func blockPostAuthor() async -> Bool {
        do {
            try await repository.blockUser(userID: post.authorID, reason: "用户主动屏蔽")
            errorMessage = nil
            return true
        } catch {
            errorMessage = error.localizedDescription
            return false
        }
    }

    func reportComment(_ comment: CommunityComment, reason: String) async {
        do {
            try await repository.reportComment(commentID: comment.id, reason: reason)
            comments.removeAll { $0.id == comment.id }
            errorMessage = nil
        } catch {
            errorMessage = error.localizedDescription
        }
    }

    func blockCommentAuthor(_ comment: CommunityComment) async {
        do {
            try await repository.blockUser(userID: comment.authorID, reason: "用户主动屏蔽")
            comments.removeAll { $0.authorID == comment.authorID }
            errorMessage = nil
        } catch {
            errorMessage = error.localizedDescription
        }
    }
}

struct RealCommunitySectionView: View {
    @Environment(\.leafyControlScale) private var leafyControlScale
    @Environment(\.leafyLanguage) private var leafyLanguage
    @Environment(\.leafyDependencies) private var dependencies
    @Binding var selectedCategory: String?
    @Binding var isShowingHotPosts: Bool
    @Binding var contentFilter: CommunityFeedContentFilter
    @Binding var isFeedAtTop: Bool
    @Binding var selectedPost: CommunityPost?
    @Binding var hasAcceptedTerms: Bool?
    let requestProfileCompletion: () -> Void
    let refreshID: UUID

    @ObservedObject var viewModel: CommunityFeedViewModel
    var topContentInset: CGFloat = 0
    @ObservedObject private var sessionManager = CommunitySessionManager.shared
    @State private var showingTermsSheet = false
    @State private var hasPresentedTermsGate = false
    @State private var selectedPoll: CommunityPoll?
    @State private var reportTarget: CommunityModerationTarget?
    @State private var blockTargetPost: CommunityPost?
    @State private var deleteTargetPost: CommunityPost?
    @State private var operationAlert: LeafyOperationAlert?

    private var feedQuery: CommunityFeedQuery {
        if isShowingHotPosts {
            return .hot
        }
        return CommunityFeedQuery(
            category: selectedCategory,
            contentFilter: contentFilter
        )
    }

    private var feedTaskID: CommunityFeedTaskID {
        CommunityFeedTaskID(refreshID: refreshID, query: feedQuery)
    }

    private var communityAccessGate: CommunityAccessGate {
        CommunityAccessGate(
            sessionManager: sessionManager,
            termsChecker: dependencies.communityRepository
        )
    }

    var body: some View {
        VStack(alignment: .leading, spacing: AppSpacing.card) {
            if hasAcceptedTerms == false {
                CommunityTermsPromptCard {
                    showingTermsSheet = true
                }
            } else {
                ScrollView(showsIndicators: false) {
                    VStack(spacing: 0) {
                        GeometryReader { geometry in
                            Color.clear.preference(
                                key: CommunityFeedTopPreferenceKey.self,
                                value: geometry.frame(in: .named("community-feed-scroll")).minY
                            )
                        }
                        .frame(height: 0)

                        LazyVStack(alignment: .leading, spacing: AppSpacing.card) {
                            feedContent
                        }
                        .padding(.top, topContentInset + 10 * leafyControlScale)
                        .padding(.bottom, 40)
                    }
                }
                .coordinateSpace(name: "community-feed-scroll")
                .onPreferenceChange(CommunityFeedTopPreferenceKey.self) { minY in
                    let newValue = minY >= -(8 * leafyControlScale)
                    guard isFeedAtTop != newValue else { return }
                    withAnimation(.easeOut(duration: 0.18)) {
                        isFeedAtTop = newValue
                    }
                }
                .refreshable {
                    guard !CommunityDiagnosticsOptions.disablesFeedLoad else {
                        CommunityDiagnostics.log.info("Community feed refresh skipped by diagnostics")
                        return
                    }
                    await viewModel.load(mode: .refresh, query: feedQuery)
                }
            }
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .top)
        .task(id: refreshID) {
            CommunityDiagnostics.log.info("Community terms task began")
            await refreshTermsState()
        }
        .task(id: feedTaskID) {
            CommunityDiagnostics.log.info("Community feed task began for query \(feedQuery.cacheKey, privacy: .public)")
            await loadFeedForCurrentQuery()
        }
        .sheet(isPresented: $showingTermsSheet) {
            CommunityTermsAgreementSheet {
                hasAcceptedTerms = true
                operationAlert = .success(L10n.text("设置已保存！", language: leafyLanguage))
            }
            .presentationDetents([.large])
        }
        .sheet(item: $selectedPoll) { poll in
            CommunityPollDetailSheet(
                poll: poll,
                isLoading: viewModel.activePollIDs.contains(poll.id),
                canDelete: false,
                onVote: { option in
                    await vote(poll: poll, option: option)
                },
                onDelete: {}
            )
            .presentationDetents([.medium, .large])
        }
        .leafyOperationAlert($operationAlert)
        .confirmationDialog("举报内容", isPresented: Binding(
            get: { reportTarget != nil },
            set: { if !$0 { reportTarget = nil } }
        ), titleVisibility: .visible) {
            ForEach(communityReportReasons, id: \.self) { reason in
                Button(reason) {
                    submitReport(reason: reason)
                }
            }
            Button("取消", role: .cancel) {
                reportTarget = nil
            }
        } message: {
            Text("举报后该内容会立即从你的页面移除，并进入 24 小时审核队列。")
        }
        .confirmationDialog("屏蔽该用户？", isPresented: Binding(
            get: { blockTargetPost != nil },
            set: { if !$0 { blockTargetPost = nil } }
        ), titleVisibility: .visible) {
            Button("屏蔽", role: .destructive) {
                blockSelectedPostAuthor()
            }
            Button("取消", role: .cancel) {
                blockTargetPost = nil
            }
        } message: {
            Text("屏蔽后将不再看到该用户的帖子、评论和通知。")
        }
        .confirmationDialog("删除这条帖子？", isPresented: Binding(
            get: { deleteTargetPost != nil },
            set: { if !$0 { deleteTargetPost = nil } }
        ), titleVisibility: .visible) {
            Button("删除", role: .destructive) {
                deleteSelectedPost()
            }
            Button("取消", role: .cancel) {
                deleteTargetPost = nil
            }
        }
    }

    @ViewBuilder
    private var feedContent: some View {
        if viewModel.isLoading && viewModel.items.isEmpty {
            ProgressView()
                .frame(maxWidth: .infinity)
                .padding(.vertical, 24)
        } else if let errorMessage = viewModel.errorMessage, viewModel.items.isEmpty {
            CommunityErrorCard(message: errorMessage) {
                Task { await viewModel.load(mode: .refresh, query: feedQuery) }
            }
        } else if viewModel.items.isEmpty && feedQuery.contentFilter == .polls {
            ContentUnavailableView("暂无投票", systemImage: "chart.bar.xaxis", description: Text("有同学发起新投票后会显示在这里。"))
                .frame(maxWidth: .infinity)
                .padding(.vertical, 16)
        } else if viewModel.items.isEmpty && feedQuery.category == nil && !feedQuery.hasSearch {
            if feedQuery.mode.isHot {
                ContentUnavailableView("暂无热门帖子", systemImage: "flame", description: Text("近 30 天有新互动后会显示在这里。"))
                    .frame(maxWidth: .infinity)
                    .padding(.vertical, 16)
            } else {
                ContentUnavailableView("请下拉刷新", systemImage: "text.bubble", description: Text("以获取社区最新内容"))
                    .frame(maxWidth: .infinity)
                    .padding(.vertical, 16)
            }
        } else if viewModel.items.isEmpty {
            ContentUnavailableView("没有匹配的帖子", systemImage: "magnifyingglass", description: Text("换个分类或关键词试试。"))
                .frame(maxWidth: .infinity)
                .padding(.vertical, 16)
        } else {
            if feedQuery.mode.isHot {
                VStack(alignment: .leading, spacing: 4) {
                    Text("近 30 天热门")
                        .leafyHeadline()
                        .foregroundStyle(AppTheme.primaryText)
                    Text("按评论和点赞互动热度排序")
                        .microCaption()
                        .foregroundStyle(AppTheme.secondaryText)
                }
                .frame(maxWidth: .infinity, alignment: .leading)
            }

            CommunityMasonryGrid(items: viewModel.items, spacing: 10) { item in
                masonryItem(item)
            }

            loadMoreFooter
        }
    }

    @ViewBuilder
    private func masonryItem(_ item: CommunityFeedItem) -> some View {
        switch item {
        case .post(let post):
            CommunityMasonryPostCard(
                post: post,
                isFavoriteLoading: viewModel.activeFavoritePostIDs.contains(post.id),
                onOpen: {
                    selectedPost = post
                },
                onToggleFavorite: {
                    await toggleFavorite(post)
                }
            )
            .contextMenu {
                ShareLink(item: post.shareURL, subject: Text(post.title), message: Text(post.shareText)) {
                    Label("分享", systemImage: "square.and.arrow.up")
                }

                Button {
                    LeafyClipboard.string = post.title
                } label: {
                    Label("复制标题", systemImage: "doc.on.doc")
                }

                Button(role: .destructive) {
                    reportTarget = .post(post)
                } label: {
                    Label("举报", systemImage: "exclamationmark.bubble")
                }

                if post.authorID != sessionManager.currentUserID {
                    Button(role: .destructive) {
                        blockTargetPost = post
                    } label: {
                        Label("屏蔽该用户", systemImage: "person.crop.circle.badge.xmark")
                    }
                }

                if post.authorID == sessionManager.currentUserID {
                    Button(role: .destructive) {
                        deleteTargetPost = post
                    } label: {
                        Label("删除", systemImage: "trash")
                    }
                }
            }
        case .poll(let poll):
            CommunityMasonryPollCard(poll: poll) {
                selectedPoll = poll
            }
        }
    }

    @ViewBuilder
    private var loadMoreFooter: some View {
        if viewModel.isLoadingMore {
            HStack(spacing: 8) {
                ProgressView()
                    .controlSize(.small)
                Text("正在加载更多")
                    .microCaption()
                    .foregroundStyle(AppTheme.secondaryText)
            }
            .frame(maxWidth: .infinity)
            .padding(.vertical, 10)
        } else if viewModel.hasMoreItems {
            HStack(spacing: 6) {
                Image(systemName: "arrow.down.circle")
                    .font(.system(size: 13, weight: .medium))
                Text("继续滑动加载更多")
                    .microCaption()
            }
            .foregroundStyle(AppTheme.tertiaryText)
            .frame(maxWidth: .infinity)
            .padding(.vertical, 10)
            .onAppear {
                Task {
                    await viewModel.loadMoreIfNeeded()
                }
            }
        } else if !feedQuery.mode.isHot {
            Text("已经到底了")
                .microCaption()
                .foregroundStyle(AppTheme.tertiaryText)
                .frame(maxWidth: .infinity)
                .padding(.vertical, 10)
        }
    }

    @MainActor
    private func refreshTermsState() async {
        guard !CommunityDiagnosticsOptions.disablesTermsGate else {
            CommunityDiagnostics.log.info("Community terms task skipped by diagnostics")
            hasAcceptedTerms = true
            return
        }
        switch await communityAccessGate.evaluate(.communityEntry) {
        case .allowed:
            hasAcceptedTerms = true
        case .requiresTermsAcceptance:
            hasAcceptedTerms = false
            if !hasPresentedTermsGate {
                hasPresentedTermsGate = true
                showingTermsSheet = true
            }
        case .requiresProfileCompletion, .failed:
            hasAcceptedTerms = nil
        }
    }

    private func loadFeedForCurrentQuery() async {
        guard !CommunityDiagnosticsOptions.disablesFeedLoad else {
            CommunityDiagnostics.log.info("Community feed load skipped by diagnostics")
            return
        }
        guard await CommunityFeedSearchDebounce.waitIfNeeded(for: feedQuery) else { return }
        await viewModel.load(query: feedQuery)
    }

    private func submitReport(reason: String) {
        guard let target = reportTarget else { return }
        reportTarget = nil
        Task {
            switch target {
            case .post(let post):
                if let error = await viewModel.report(post: post, reason: reason) {
                    viewModel.errorMessage = error
                } else {
                    operationAlert = .success(L10n.text("举报已提交！", language: leafyLanguage))
                }
            case .comment:
                break
            }
        }
    }

    private func blockSelectedPostAuthor() {
        guard let post = blockTargetPost else { return }
        blockTargetPost = nil
        Task {
            if let error = await viewModel.blockAuthor(of: post) {
                viewModel.errorMessage = error
            } else {
                operationAlert = .success(L10n.text("已屏蔽该用户！", language: leafyLanguage))
            }
        }
    }

    private func deleteSelectedPost() {
        guard let post = deleteTargetPost else { return }
        deleteTargetPost = nil
        Task {
            if let error = await viewModel.delete(post: post) {
                viewModel.errorMessage = error
            } else {
                operationAlert = .success(L10n.text("帖子已删除！", language: leafyLanguage))
            }
        }
    }

    @MainActor
    private func toggleFavorite(_ post: CommunityPost) async {
        switch await communityAccessGate.evaluate(.profileInteraction, forceBootstrap: true) {
        case .allowed:
            break
        case .requiresProfileCompletion:
            viewModel.errorMessage = L10n.text("收藏前需要先完善社区资料。", language: leafyLanguage)
            requestProfileCompletion()
            return
        case .requiresTermsAcceptance:
            showingTermsSheet = true
            return
        case .failed(let message):
            viewModel.errorMessage = message
            return
        }

        if let error = await viewModel.toggleFavorite(postID: post.id) {
            viewModel.errorMessage = error
        } else {
            let message = post.viewerHasFavorited
                ? L10n.text("已取消收藏！", language: leafyLanguage)
                : L10n.text("已添加收藏！", language: leafyLanguage)
            operationAlert = .success(message)
        }
    }

    @MainActor
    private func vote(poll: CommunityPoll, option: CommunityPollOption) async {
        switch await communityAccessGate.evaluate(.postCreation, forceBootstrap: true) {
        case .allowed:
            break
        case .requiresProfileCompletion:
            selectedPoll = nil
            viewModel.errorMessage = L10n.text("投票前需要先完善社区资料。", language: leafyLanguage)
            requestProfileCompletion()
            return
        case .requiresTermsAcceptance:
            selectedPoll = nil
            showingTermsSheet = true
            viewModel.errorMessage = L10n.text("投票前需要先同意社区条款。", language: leafyLanguage)
            return
        case .failed(let message):
            viewModel.errorMessage = message
            return
        }

        if let updatedPoll = await viewModel.votePoll(pollID: poll.id, optionID: option.id) {
            selectedPoll = updatedPoll
            operationAlert = .success(L10n.text("已记录你的选择！", language: leafyLanguage))
        }
    }
}

private struct CommunityPollFeedCard: View {
    @AppStorage("appThemeColorPreference") private var appThemeColorPreferenceRaw = AppThemeColorPreference.green.rawValue

    let poll: CommunityPoll
    let onOpen: () -> Void

    var body: some View {
        Button(action: onOpen) {
            HStack(alignment: .top, spacing: 12) {
                ZStack {
                    RoundedRectangle(cornerRadius: 10, style: .continuous)
                        .fill(themeColor.opacity(0.14))
                    Image(systemName: "chart.bar.xaxis")
                        .font(.system(size: 18, weight: .semibold))
                        .foregroundStyle(AppTheme.accentEmphasis)
                }
                .frame(width: 42, height: 42)

                VStack(alignment: .leading, spacing: 8) {
                    HStack(spacing: 8) {
                        Text("投票")
                            .microCaption()
                            .fontWeight(.semibold)
                            .foregroundStyle(AppTheme.accentEmphasis)
                            .padding(.horizontal, 8)
                            .padding(.vertical, 4)
                            .background(AppTheme.accentSoft, in: Capsule())

                        Spacer(minLength: 8)
                        Image(systemName: "chevron.right")
                            .font(.footnote.weight(.semibold))
                            .foregroundStyle(AppTheme.secondaryText)
                    }

                    Text(poll.question)
                        .leafyHeadline()
                        .foregroundStyle(AppTheme.primaryText)
                        .multilineTextAlignment(.leading)
                        .lineLimit(3)
                        .fixedSize(horizontal: false, vertical: true)

                    HStack(spacing: 10) {
                        Label(poll.statusText, systemImage: poll.isClosed ? "clock" : "chart.bar.xaxis")
                        Label("\(poll.totalVoteCount) 人参与", systemImage: "person.2")
                        if let closesAtText = poll.closesAtText {
                            Label(poll.isClosed ? "已截止" : "\(closesAtText) 截止", systemImage: "calendar")
                        }
                        if poll.isDeletionPending {
                            Label("删除审核中", systemImage: "hourglass")
                        }
                    }
                    .microCaption()
                    .foregroundStyle(AppTheme.secondaryText)
                    .lineLimit(1)
                    .minimumScaleFactor(0.85)
                }
            }
            .padding(18)
            .frame(maxWidth: .infinity, alignment: .leading)
            .contentShape(RoundedRectangle(cornerRadius: AppRadius.medium, style: .continuous))
        }
        .buttonStyle(.plain)
        .leafyCardStyle()
    }

    private var themeColor: Color {
        AppThemeColorPreference.storedValue(appThemeColorPreferenceRaw).swatchColor
    }
}

struct CommunityPollDetailSheet: View {
    @Environment(\.dismiss) private var dismiss

    let poll: CommunityPoll
    let isLoading: Bool
    let canDelete: Bool
    let onVote: (CommunityPollOption) async -> Void
    let onDelete: () -> Void

    var body: some View {
        NavigationStack {
            ScrollView(showsIndicators: false) {
                CommunityPollCard(
                    poll: poll,
                    isLoading: isLoading,
                    canDelete: canDelete,
                    onVote: onVote,
                    onDelete: onDelete
                )
                .padding(AppSpacing.page)
            }
            .background(LeafyPageBackground())
            .navigationTitle("投票")
            .leafyInlineNavigationTitle()
            .toolbar {
                ToolbarItem(placement: .leafyLeading) {
                    Button("关闭") {
                        dismiss()
                    }
                }
            }
        }
    }
}

struct CommunityTopicFilterBar: View {
    @Binding var selectedCategory: String?
    @Binding var isShowingHotPosts: Bool
    @Binding var contentFilter: CommunityFeedContentFilter

    var body: some View {
        ScrollView(.horizontal, showsIndicators: false) {
            HStack(spacing: 8) {
                CommunityCategoryPill(
                    title: "热门",
                    isSelected: isShowingHotPosts
                ) {
                    selectHot()
                }

                CommunityCategoryPill(
                    title: "全部帖子",
                    isSelected: selectedCategory == nil && !isShowingHotPosts && contentFilter == .all
                ) {
                    selectCategory(nil)
                }

                CommunityCategoryPill(
                    title: "投票",
                    isSelected: contentFilter == .polls
                ) {
                    selectPolls()
                }

                ForEach(communityCategories, id: \.self) { category in
                    CommunityCategoryPill(
                        title: category,
                        isSelected: selectedCategory == category && !isShowingHotPosts
                    ) {
                        selectCategory(category)
                    }
                }
            }
            .padding(.vertical, 2)
        }
        .leafyTransparentHorizontalScrollRail()
    }

    private func selectCategory(_ category: String?) {
        withAnimation(.snappy) {
            isShowingHotPosts = false
            selectedCategory = category
            contentFilter = category == nil ? .all : .posts
        }
    }

    private func selectHot() {
        withAnimation(.snappy) {
            selectedCategory = nil
            isShowingHotPosts = true
            contentFilter = .posts
        }
    }

    private func selectPolls() {
        withAnimation(.snappy) {
            selectedCategory = nil
            isShowingHotPosts = false
            contentFilter = .polls
        }
    }
}

private struct CommunityFeedTopPreferenceKey: PreferenceKey {
    static var defaultValue: CGFloat = 0

    static func reduce(value: inout CGFloat, nextValue: () -> CGFloat) {
        value = nextValue()
    }
}

struct CommunitySearchSheet: View {
    @Environment(\.dismiss) private var dismiss
    @Environment(\.leafyLanguage) private var leafyLanguage
    @StateObject private var viewModel = CommunityFeedViewModel()
    @State private var searchText = ""
    @State private var searchRefreshID = UUID()
    @State private var selectedPost: CommunityPost?

    private var searchQuery: CommunityFeedQuery {
        CommunityFeedQuery(search: searchText)
    }

    private var searchTaskID: CommunityFeedTaskID {
        CommunityFeedTaskID(refreshID: searchRefreshID, query: searchQuery)
    }

    var body: some View {
        NavigationStack {
            VStack(alignment: .leading, spacing: AppSpacing.card) {
                searchField
                    .padding(.horizontal, AppSpacing.page)

                ScrollView(showsIndicators: false) {
                    VStack(alignment: .leading, spacing: AppSpacing.card) {
                        searchContent
                    }
                    .padding(.horizontal, AppSpacing.page)
                    .padding(.bottom, AppSpacing.page)
                }
                .refreshable {
                    guard searchQuery.hasSearch else { return }
                    await viewModel.load(mode: .refresh, query: searchQuery)
                }
            }
            .padding(.top, AppSpacing.micro)
            .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .top)
            .background(LeafyPageBackground())
            .navigationTitle("搜索帖子")
            .leafyInlineNavigationTitle()
            .toolbar {
                ToolbarItem(placement: .leafyLeading) {
                    Button("关闭") {
                        dismiss()
                    }
                }
            }
            .task(id: searchTaskID) {
                await loadSearchResults()
            }
            .sheet(item: $selectedPost) { post in
                RealCommunityPostDetailSheet(post: post) { _ in
                    searchRefreshID = UUID()
                } onPostRemoved: {
                    selectedPost = nil
                    searchRefreshID = UUID()
                }
                    .presentationDetents([.medium, .large])
            }
        }
    }

    private var searchField: some View {
        HStack(spacing: 8) {
            Image(systemName: "magnifyingglass")
                .foregroundStyle(AppTheme.tertiaryText)

            TextField("搜索帖子", text: $searchText)
                .leafyDisableAutocapitalization()
                .autocorrectionDisabled()
                .leafyBody()

            if !searchText.isEmpty {
                Button {
                    searchText = ""
                } label: {
                    Image(systemName: "xmark.circle.fill")
                        .foregroundStyle(AppTheme.tertiaryText)
                }
                .buttonStyle(.plain)
                .accessibilityLabel("清空搜索")
            }
        }
        .padding(.horizontal, 14)
        .frame(height: 44)
        .leafyGlassSurface(
            in: RoundedRectangle(cornerRadius: AppRadius.medium, style: .continuous),
            isInteractive: true
        )
    }

    @ViewBuilder
    private var searchContent: some View {
        if !searchQuery.hasSearch {
            ContentUnavailableView("搜索社区帖子", systemImage: "magnifyingglass", description: Text("输入关键词查找标题、正文或话题。"))
                .frame(maxWidth: .infinity)
                .padding(.vertical, 28)
        } else if viewModel.isLoading && viewModel.posts.isEmpty {
            ProgressView()
                .frame(maxWidth: .infinity)
                .padding(.vertical, 24)
        } else if let errorMessage = viewModel.errorMessage, viewModel.posts.isEmpty {
            CommunityErrorCard(message: errorMessage) {
                searchRefreshID = UUID()
            }
        } else if viewModel.posts.isEmpty {
            ContentUnavailableView("没有匹配的帖子", systemImage: "magnifyingglass", description: Text("换个关键词试试。"))
                .frame(maxWidth: .infinity)
                .padding(.vertical, 16)
        } else {
            ForEach(viewModel.posts) { post in
                RealCommunityPostCard(
                    post: post,
                    allowsImagePreview: false,
                    onOpen: {
                        selectedPost = post
                    }
                )
            }
        }
    }

    private func loadSearchResults() async {
        guard searchQuery.hasSearch else { return }
        guard await CommunityFeedSearchDebounce.waitIfNeeded(for: searchQuery) else { return }
        await viewModel.load(query: searchQuery)
    }
}

struct CommunityPollsSheet: View {
    @Environment(\.dismiss) private var dismiss
    @Environment(\.leafyLanguage) private var leafyLanguage
    @Environment(\.leafyDependencies) private var dependencies
    @ObservedObject private var sessionManager = CommunitySessionManager.shared
    @StateObject private var viewModel = CommunityPollsViewModel()
    @State private var showingComposer = false
    @State private var showingProfileEditor = false
    @State private var showingTermsSheet = false
    @State private var deletionTarget: CommunityPoll?
    @State private var operationAlert: LeafyOperationAlert?

    private var communityAccessGate: CommunityAccessGate {
        CommunityAccessGate(
            sessionManager: sessionManager,
            termsChecker: dependencies.communityRepository
        )
    }

    var body: some View {
        NavigationStack {
            ScrollView(showsIndicators: false) {
                LazyVStack(alignment: .leading, spacing: AppSpacing.card) {
                    pollsContent
                }
                .padding(AppSpacing.page)
            }
            .background(LeafyPageBackground())
            .navigationTitle("投票")
            .leafyInlineNavigationTitle()
            .toolbar {
                ToolbarItem(placement: .leafyLeading) {
                    Button("关闭") {
                        dismiss()
                    }
                }
                ToolbarItem(placement: .leafyTrailing) {
                    Button {
                        Task { await handleComposerTapped() }
                    } label: {
                        Image(systemName: "plus")
                    }
                    .accessibilityLabel("发布投票")
                }
            }
            .refreshable {
                await viewModel.load()
            }
            .task {
                await viewModel.load()
            }
            .sheet(isPresented: $showingComposer) {
                CommunityPollComposerSheet(viewModel: viewModel) {
                    operationAlert = .success(L10n.text("投票已提交审核！", language: leafyLanguage))
                }
                    .presentationDetents([.medium, .large])
            }
            .sheet(isPresented: $showingProfileEditor) {
                CommunityProfileEditorSheet()
                    .presentationDetents([.medium, .large])
            }
            .sheet(isPresented: $showingTermsSheet) {
                CommunityTermsAgreementSheet {
                    operationAlert = .success(L10n.text("设置已保存！", language: leafyLanguage))
                }
                    .presentationDetents([.large])
            }
            .confirmationDialog("申请删除这个投票？", isPresented: Binding(
                get: { deletionTarget != nil },
                set: { if !$0 { deletionTarget = nil } }
            ), titleVisibility: .visible) {
                Button("提交申请", role: .destructive) {
                    requestSelectedPollDeletion()
                }
                Button("取消", role: .cancel) {
                    deletionTarget = nil
                }
            } message: {
                Text("提交后需后台审核。审核前投票会继续公开展示。")
            }
            .leafyOperationAlert($operationAlert)
        }
    }

    @ViewBuilder
    private var pollsContent: some View {
        if viewModel.isLoading && viewModel.polls.isEmpty {
            ProgressView()
                .frame(maxWidth: .infinity)
                .padding(.vertical, 28)
        } else if let errorMessage = viewModel.errorMessage, viewModel.polls.isEmpty {
            CommunityErrorCard(message: errorMessage) {
                Task { await viewModel.load() }
            }
        } else if viewModel.polls.isEmpty {
            ContentUnavailableView("暂无投票", systemImage: "chart.bar.xaxis", description: Text("发布一个单选投票，大家投完后就能看到统计。"))
                .frame(maxWidth: .infinity)
                .padding(.vertical, 24)
        } else {
            ForEach(viewModel.polls) { poll in
                CommunityPollCard(
                    poll: poll,
                    isLoading: viewModel.activePollIDs.contains(poll.id),
                    canDelete: poll.authorID == sessionManager.currentUserID && poll.canRequestDeletion,
                    onVote: { option in
                        await vote(poll: poll, option: option)
                    },
                    onDelete: {
                        deletionTarget = poll
                    }
                )
            }
        }
    }

    @MainActor
    private func handleComposerTapped() async {
        switch await communityAccessGate.evaluate(.postCreation, forceBootstrap: true) {
        case .allowed:
            showingComposer = true
        case .requiresProfileCompletion:
            showingProfileEditor = true
            viewModel.errorMessage = L10n.text("发布投票前需要先完善社区资料。", language: leafyLanguage)
        case .requiresTermsAcceptance:
            showingTermsSheet = true
            viewModel.errorMessage = L10n.text("发布投票前需要先同意社区条款。", language: leafyLanguage)
        case .failed(let message):
            viewModel.errorMessage = message
        }
    }

    @MainActor
    private func vote(poll: CommunityPoll, option: CommunityPollOption) async {
        switch await communityAccessGate.evaluate(.postCreation, forceBootstrap: true) {
        case .allowed:
            break
        case .requiresProfileCompletion:
            showingProfileEditor = true
            viewModel.errorMessage = L10n.text("投票前需要先完善社区资料。", language: leafyLanguage)
            return
        case .requiresTermsAcceptance:
            showingTermsSheet = true
            viewModel.errorMessage = L10n.text("投票前需要先同意社区条款。", language: leafyLanguage)
            return
        case .failed(let message):
            viewModel.errorMessage = message
            return
        }

        if await viewModel.vote(pollID: poll.id, optionID: option.id) {
            operationAlert = .success(L10n.text("已记录你的选择！", language: leafyLanguage))
        }
    }

    private func requestSelectedPollDeletion() {
        guard let poll = deletionTarget else { return }
        deletionTarget = nil
        Task {
            if await viewModel.requestDeletion(poll: poll, reason: nil) {
                operationAlert = .success(L10n.text("删除申请已提交！", language: leafyLanguage))
            }
        }
    }
}

private struct CommunityPollCard: View {
    let poll: CommunityPoll
    let isLoading: Bool
    let canDelete: Bool
    let onVote: (CommunityPollOption) async -> Void
    let onDelete: () -> Void

    var body: some View {
        VStack(alignment: .leading, spacing: 14) {
            header

            VStack(alignment: .leading, spacing: 8) {
                Text(poll.question)
                    .leafyHeadline()
                    .foregroundStyle(AppTheme.primaryText)
                    .fixedSize(horizontal: false, vertical: true)

                if let detail = poll.detail?.trimmingCharacters(in: .whitespacesAndNewlines), !detail.isEmpty {
                    Text(detail)
                        .leafyBody()
                        .foregroundStyle(AppTheme.secondaryText)
                        .fixedSize(horizontal: false, vertical: true)
                }
            }

            VStack(spacing: 10) {
                ForEach(poll.options) { option in
                    optionRow(option)
                }
            }

            footer
        }
        .padding(18)
        .leafyCardStyle()
    }

    private var header: some View {
        HStack(spacing: 9) {
            CommunityAvatarView(profile: poll.author, size: 34)

            VStack(alignment: .leading, spacing: 2) {
                Text(poll.displayAuthorName)
                    .leafySubheadline()
                    .fontWeight(.semibold)
                    .foregroundStyle(AppTheme.primaryText)
                    .lineLimit(1)
                    .minimumScaleFactor(0.85)
                Text(poll.relativeTimestamp)
                    .microCaption()
                    .foregroundStyle(AppTheme.secondaryText)
            }

            Spacer()

            Text(poll.statusText)
                .microCaption()
                .foregroundStyle(poll.isClosed ? AppTheme.secondaryText : AppTheme.accentEmphasis)
                .padding(.horizontal, 8)
                .padding(.vertical, 5)
                .background(poll.isClosed ? AppTheme.softFill : AppTheme.accentSoft, in: Capsule())

            if canDelete {
                Menu {
                    Button(role: .destructive, action: onDelete) {
                        Label("申请删除", systemImage: "trash")
                    }
                } label: {
                    Image(systemName: "ellipsis.circle")
                        .font(.system(size: 18, weight: .semibold))
                        .foregroundStyle(AppTheme.secondaryText)
                        .frame(width: 30, height: 30)
                }
                .buttonStyle(.plain)
            }
        }
    }

    private var footer: some View {
        HStack(spacing: 8) {
            Label("\(poll.totalVoteCount) 票", systemImage: "person.2")
            if poll.isPendingReview {
                Text("·")
                Label("通过审核后公开", systemImage: "hourglass")
            }
            if poll.isDeletionPending {
                Text("·")
                Label("删除申请审核中", systemImage: "hourglass")
            }
            if let closesAtText = poll.closesAtText {
                Text("·")
                Label(poll.isClosed ? "截止于 \(closesAtText)" : "\(closesAtText) 截止", systemImage: "clock")
            }
        }
        .microCaption()
        .foregroundStyle(AppTheme.secondaryText)
    }

    private func optionRow(_ option: CommunityPollOption) -> some View {
        let isSelected = poll.viewerOptionID == option.id
        let share = poll.shouldRevealResults ? option.voteShare(totalVotes: poll.totalVoteCount) : 0

        return Button {
            guard poll.canVote, !isLoading else { return }
            Task { await onVote(option) }
        } label: {
            VStack(alignment: .leading, spacing: 8) {
                HStack(spacing: 10) {
                    Image(systemName: isSelected ? "checkmark.circle.fill" : "circle")
                        .font(.system(size: 17, weight: .semibold))
                        .foregroundStyle(isSelected ? AppTheme.accentEmphasis : AppTheme.tertiaryText)
                        .frame(width: 22)

                    Text(option.text)
                        .leafySubheadline()
                        .foregroundStyle(AppTheme.primaryText)
                        .multilineTextAlignment(.leading)
                        .frame(maxWidth: .infinity, alignment: .leading)

                    if isLoading && isSelected {
                        ProgressView()
                            .controlSize(.small)
                    } else if poll.shouldRevealResults {
                        Text(option.percentageText(totalVotes: poll.totalVoteCount))
                            .microCaption()
                            .foregroundStyle(AppTheme.secondaryText)
                            .monospacedDigit()
                    } else {
                        Text("投票后可见")
                            .microCaption()
                            .foregroundStyle(AppTheme.tertiaryText)
                    }
                }

                GeometryReader { geometry in
                    ZStack(alignment: .leading) {
                        Capsule()
                            .fill(AppTheme.fill)
                        Capsule()
                            .fill(isSelected ? AppTheme.accentSoft : AppTheme.separator)
                            .frame(width: max(6, geometry.size.width * share))
                    }
                }
                .frame(height: 6)
            }
            .padding(12)
            .background(
                isSelected ? AppTheme.accentSoft.opacity(0.72) : AppTheme.softFill,
                in: RoundedRectangle(cornerRadius: AppRadius.medium, style: .continuous)
            )
            .overlay(
                RoundedRectangle(cornerRadius: AppRadius.medium, style: .continuous)
                    .stroke(isSelected ? AppTheme.accent.opacity(0.32) : AppTheme.separator, lineWidth: 1)
            )
            .contentShape(RoundedRectangle(cornerRadius: AppRadius.medium, style: .continuous))
        }
        .buttonStyle(.plain)
        .disabled(!poll.canVote || isLoading)
    }
}

struct CommunityPollComposerSheet: View {
    @Environment(\.dismiss) private var dismiss
    @Environment(\.leafyLanguage) private var leafyLanguage
    @ObservedObject var viewModel: CommunityPollsViewModel
    let onPosted: () -> Void

    @State private var question = ""
    @State private var detail = ""
    @State private var options = ["", ""]
    @State private var hasDeadline = false
    @State private var closesAt = Calendar.current.date(byAdding: .day, value: 3, to: Date()) ?? Date()
    @State private var isSubmitting = false

    private var input: CreatePollInput {
        CreatePollInput(
            question: question,
            detail: detail,
            options: options,
            closesAt: hasDeadline ? ISO8601DateFormatter().string(from: closesAt) : nil
        )
    }

    var body: some View {
        NavigationStack {
            ScrollView {
                VStack(alignment: .leading, spacing: AppSpacing.card) {
                    LeafySectionTitle("发布投票", subtitle: "每人只能选择一个选项，提交后可以在截止前改票。")

                    if let errorMessage = viewModel.errorMessage {
                        CommunityInlineError(message: errorMessage)
                    }

                    CommunityPollDraftFields(
                        question: $question,
                        detail: $detail,
                        options: $options,
                        hasDeadline: $hasDeadline,
                        closesAt: $closesAt
                    )
                }
                .padding(AppSpacing.page)
            }
            .background(LeafyPageBackground())
            .navigationTitle("发布投票")
            .leafyInlineNavigationTitle()
            .toolbar {
                ToolbarItem(placement: .leafyLeading) {
                    Button("取消") {
                        dismiss()
                    }
                }
                ToolbarItem(placement: .leafyTrailing) {
                    Button(isSubmitting ? L10n.text("发布中", language: leafyLanguage) : L10n.text("发布", language: leafyLanguage)) {
                        Task { await submit() }
                    }
                    .disabled(isSubmitting || input.validationError != nil)
                }
            }
        }
    }

    private func submit() async {
        isSubmitting = true
        defer { isSubmitting = false }

        if await viewModel.createPoll(input: input) {
            onPosted()
            dismiss()
        }
    }
}

private struct CommunityPollDraftFields: View {
    @Binding var question: String
    @Binding var detail: String
    @Binding var options: [String]
    @Binding var hasDeadline: Bool
    @Binding var closesAt: Date

    private var input: CreatePollInput {
        CreatePollInput(
            question: question,
            detail: detail,
            options: options,
            closesAt: hasDeadline ? ISO8601DateFormatter().string(from: closesAt) : nil
        )
    }

    var body: some View {
        pollFields
        optionsFields
        deadlineFields
    }

    private var pollFields: some View {
        VStack(alignment: .leading, spacing: 14) {
            Text("问题")
                .leafyHeadline()
            TextField("例如：期末周图书馆开放到几点更合适？", text: $question, axis: .vertical)
                .lineLimit(3, reservesSpace: true)
                .leafyDisableAutocapitalization()
                .autocorrectionDisabled()
                .padding(14)
                .background(AppTheme.fill, in: RoundedRectangle(cornerRadius: AppRadius.medium, style: .continuous))
                .onChange(of: question) { _, newValue in
                    if newValue.count > CommunityPollRules.maxQuestionLength {
                        question = String(newValue.prefix(CommunityPollRules.maxQuestionLength))
                    }
                }

            Text("补充说明")
                .leafyHeadline()
            TextField("可选：说明投票背景或限制条件。", text: $detail, axis: .vertical)
                .lineLimit(5, reservesSpace: true)
                .padding(14)
                .background(AppTheme.fill, in: RoundedRectangle(cornerRadius: AppRadius.medium, style: .continuous))
                .onChange(of: detail) { _, newValue in
                    if newValue.count > CommunityPollRules.maxDetailLength {
                        detail = String(newValue.prefix(CommunityPollRules.maxDetailLength))
                    }
                }
        }
        .padding(18)
        .leafyCardStyle()
    }

    private var optionsFields: some View {
        VStack(alignment: .leading, spacing: 14) {
            HStack {
                Text("选项")
                    .leafyHeadline()
                Spacer()
                Text("\(input.normalizedOptions.count)/\(CommunityPollRules.maxOptions)")
                    .microCaption()
                    .foregroundStyle(AppTheme.tertiaryText)
            }

            ForEach(options.indices, id: \.self) { index in
                HStack(spacing: 10) {
                    TextField("选项 \(index + 1)", text: optionBinding(at: index))
                        .leafyDisableAutocapitalization()
                        .autocorrectionDisabled()
                        .padding(14)
                        .background(AppTheme.fill, in: RoundedRectangle(cornerRadius: AppRadius.medium, style: .continuous))

                    if options.count > CommunityPollRules.minOptions {
                        Button {
                            options.remove(at: index)
                        } label: {
                            Image(systemName: "minus.circle.fill")
                                .font(.system(size: 20, weight: .semibold))
                                .foregroundStyle(AppTheme.danger)
                        }
                        .buttonStyle(.plain)
                        .accessibilityLabel("删除选项")
                    }
                }
            }

            if options.count < CommunityPollRules.maxOptions {
                Button {
                    options.append("")
                } label: {
                    Label("添加选项", systemImage: "plus.circle")
                        .leafyBody()
                }
                .buttonStyle(.plain)
                .foregroundStyle(AppTheme.accentEmphasis)
            }
        }
        .padding(18)
        .leafyCardStyle()
    }

    private var deadlineFields: some View {
        VStack(alignment: .leading, spacing: 14) {
            Toggle("设置截止时间", isOn: $hasDeadline)
                .tint(AppTheme.accent)

            if hasDeadline {
                DatePicker(
                    "截止时间",
                    selection: $closesAt,
                    in: Date().addingTimeInterval(60 * 5)...,
                    displayedComponents: [.date, .hourAndMinute]
                )
            }
        }
        .padding(18)
        .leafyCardStyle()
    }

    private func optionBinding(at index: Int) -> Binding<String> {
        Binding(
            get: { options[index] },
            set: { newValue in
                options[index] = String(newValue.prefix(CommunityPollRules.maxOptionLength))
            }
        )
    }
}

private struct CommunityCategoryPill: View {
    @Environment(\.leafyLanguage) private var leafyLanguage
    @Environment(\.leafyThemeColorPreference) private var themeColorPreference

    let title: String
    let isSelected: Bool
    let action: () -> Void

    var body: some View {
        Button(action: action) {
            Text(L10n.text(title, language: leafyLanguage))
                .leafyBody()
                .foregroundStyle(isSelected ? AppTheme.accentEmphasis(for: themeColorPreference) : AppTheme.primaryText)
                .padding(.horizontal, 14)
                .padding(.vertical, 9)
                .communityTopicGlassSurface(isSelected: isSelected, themeColorPreference: themeColorPreference)
        }
        .buttonStyle(.plain)
    }
}

private extension View {
    @ViewBuilder
    func communityTopicGlassSurface(
        isSelected: Bool,
        themeColorPreference: AppThemeColorPreference
    ) -> some View {
        let shape = Capsule()

#if os(iOS)
        if #available(iOS 26.0, *) {
            let base = isSelected
                ? Glass.regular.tint(AppTheme.accent(for: themeColorPreference).opacity(0.18))
                : Glass.regular
            self.glassEffect(base.interactive(), in: shape)
        } else {
            communityTopicFallbackSurface(
                isSelected: isSelected,
                themeColorPreference: themeColorPreference,
                shape: shape
            )
        }
#else
        communityTopicFallbackSurface(
            isSelected: isSelected,
            themeColorPreference: themeColorPreference,
            shape: shape
        )
#endif
    }

    private func communityTopicFallbackSurface(
        isSelected: Bool,
        themeColorPreference: AppThemeColorPreference,
        shape: Capsule
    ) -> some View {
        background(
            isSelected
                ? AppTheme.accent(for: themeColorPreference).opacity(0.16)
                : Color(uiColor: .systemBackground).opacity(0.12),
            in: shape
        )
        .overlay(
            shape.stroke(
                isSelected
                    ? AppTheme.accent(for: themeColorPreference).opacity(0.35)
                    : AppTheme.separator.opacity(0.75),
                lineWidth: 1
            )
        )
    }
}

private struct CommunityPinBadge: View {
    let pin: CommunityPostPin

    var body: some View {
        HStack(spacing: 4) {
            Image(systemName: "pin.fill")
                .font(.system(size: 9, weight: .bold))
            Text(pin.labelText)
                .microCaption()
                .lineLimit(1)
        }
        .foregroundStyle(AppTheme.warning)
        .padding(.horizontal, 8)
        .padding(.vertical, 5)
        .background(AppTheme.warning.opacity(0.12), in: Capsule())
        .accessibilityLabel(pin.labelText)
    }
}

private enum CommunityComposerMode: String, CaseIterable, Identifiable, Hashable {
    case post
    case poll

    var id: Self { self }

    var title: String {
        switch self {
        case .post: return "帖子"
        case .poll: return "投票"
        }
    }

    var sectionTitle: String {
        switch self {
        case .post: return "发布帖子"
        case .poll: return "发布投票"
        }
    }

    var subtitle: String {
        switch self {
        case .post:
            return "会自动使用当前教务账号建立社区身份。"
        case .poll:
            return "每人只能选择一个选项，提交后可以在截止前改票。"
        }
    }
}

struct CommunityComposerSheet: View {
    let onPosted: (String) -> Void

    @Environment(\.dismiss) private var dismiss
    @Environment(\.leafyLanguage) private var leafyLanguage
    @Environment(\.leafyDependencies) private var dependencies
    @ObservedObject private var sessionManager = CommunitySessionManager.shared

    @State private var composerMode: CommunityComposerMode = .post
    @State private var title = ""
    @State private var postBody = ""
    @State private var category = communityCategories[0]
    @State private var isAnonymous = false
    @State private var pollQuestion = ""
    @State private var pollDetail = ""
    @State private var pollOptions = ["", ""]
    @State private var pollHasDeadline = false
    @State private var pollClosesAt = Calendar.current.date(byAdding: .day, value: 3, to: Date()) ?? Date()
    @State private var isSubmitting = false
    @State private var selectedItems: [PhotosPickerItem] = []
    @State private var draftImages: [CommunityDraftImage] = []
    @State private var errorMessage: String?
    @State private var showingProfileEditor = false
    @State private var showingTermsSheet = false
    @State private var operationAlert: LeafyOperationAlert?
    @StateObject private var pollViewModel = CommunityPollsViewModel()

    private var communityAccessGate: CommunityAccessGate {
        CommunityAccessGate(
            sessionManager: sessionManager,
            termsChecker: dependencies.communityRepository
        )
    }

    private var pollInput: CreatePollInput {
        CreatePollInput(
            question: pollQuestion,
            detail: pollDetail,
            options: pollOptions,
            closesAt: pollHasDeadline ? ISO8601DateFormatter().string(from: pollClosesAt) : nil
        )
    }

    private var isSubmitDisabled: Bool {
        if isSubmitting { return true }

        switch composerMode {
        case .post:
            return title.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
                || postBody.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
        case .poll:
            return pollInput.validationError != nil
        }
    }

    var body: some View {
        NavigationStack {
            ScrollView {
                VStack(alignment: .leading, spacing: AppSpacing.card) {
                    LeafySectionTitle(composerMode.sectionTitle, subtitle: composerMode.subtitle)

                    Picker("发布类型", selection: $composerMode) {
                        ForEach(CommunityComposerMode.allCases) { mode in
                            Text(mode.title).tag(mode)
                        }
                    }
                    .pickerStyle(.segmented)
                    .accessibilityLabel("发布类型")

                    if let errorMessage {
                        CommunityInlineError(message: errorMessage)
                    }

                    composerFields
                }
                .padding(AppSpacing.page)
            }
            .background(LeafyPageBackground())
            .navigationTitle("发布")
            .leafyInlineNavigationTitle()
            .toolbar {
                ToolbarItem(placement: .leafyLeading) {
                    Button("取消") {
                        dismiss()
                    }
                }
                ToolbarItem(placement: .leafyTrailing) {
                    Button(isSubmitting ? L10n.text("发布中", language: leafyLanguage) : L10n.text("发布", language: leafyLanguage)) {
                        Task { await submitCurrentMode() }
                    }
                    .disabled(isSubmitDisabled)
                }
            }
            .task {
                await sessionManager.restoreProfileIfPossible()
            }
            .onChange(of: selectedItems) { _, newValue in
                Task {
                    await loadSelectedImages(from: newValue)
                }
            }
            .onChange(of: composerMode) { _, _ in
                errorMessage = nil
            }
            .sheet(isPresented: $showingProfileEditor) {
                CommunityProfileEditorSheet()
                    .presentationDetents([.medium, .large])
            }
            .sheet(isPresented: $showingTermsSheet) {
                CommunityTermsAgreementSheet {
                    operationAlert = .success(L10n.text("设置已保存！", language: leafyLanguage))
                }
                    .presentationDetents([.large])
            }
            .leafyOperationAlert($operationAlert)
        }
    }

    @ViewBuilder
    private var composerFields: some View {
        switch composerMode {
        case .post:
            postFields
            imageFields
        case .poll:
            CommunityPollDraftFields(
                question: $pollQuestion,
                detail: $pollDetail,
                options: $pollOptions,
                hasDeadline: $pollHasDeadline,
                closesAt: $pollClosesAt
            )
        }
    }

    private var postFields: some View {
        VStack(alignment: .leading, spacing: 14) {
            Text("标题")
                .leafyHeadline()
            TextField("例如：图书馆晚上哪里更安静？", text: $title)
                .leafyDisableAutocapitalization()
                .padding(14)
                .background(AppTheme.fill, in: RoundedRectangle(cornerRadius: AppRadius.medium, style: .continuous))

            Text("正文")
                .leafyHeadline()
            TextField("把问题或经验写清楚一点，别人更容易回复你。", text: $postBody, axis: .vertical)
                .lineLimit(8, reservesSpace: true)
                .padding(14)
                .background(AppTheme.fill, in: RoundedRectangle(cornerRadius: AppRadius.medium, style: .continuous))

            Text("分类")
                .leafyHeadline()
            ScrollView(.horizontal, showsIndicators: false) {
                HStack(spacing: 10) {
                    ForEach(communityCategories, id: \.self) { option in
                        CommunityCategoryPill(
                            title: option,
                            isSelected: category == option
                        ) {
                            category = option
                        }
                    }
                }
            }

            Toggle("匿名发布", isOn: $isAnonymous)
                .tint(AppTheme.accent)
        }
        .padding(18)
        .leafyCardStyle()
    }

    private var imageFields: some View {
        VStack(alignment: .leading, spacing: 14) {
            HStack {
                Text("图片")
                    .leafyHeadline()
                Spacer()
                Text("\(draftImages.count)/\(CommunityImageUpload.postImageLimit)")
                    .microCaption()
                    .foregroundStyle(AppTheme.tertiaryText)
            }

            PhotosPicker(
                selection: $selectedItems,
                maxSelectionCount: CommunityImageUpload.postImageLimit,
                matching: .images
            ) {
                HStack(spacing: 10) {
                    Image(systemName: "photo.on.rectangle.angled")
                    Text("选择图片")
                        .leafyBody()
                }
                .foregroundStyle(AppTheme.accentEmphasis)
                .padding(.horizontal, 14)
                .padding(.vertical, 12)
                .background(AppTheme.softFill, in: Capsule())
            }

            if !draftImages.isEmpty {
                ScrollView(.horizontal, showsIndicators: false) {
                    HStack(spacing: 12) {
                        ForEach(draftImages) { draft in
                            ZStack(alignment: .topTrailing) {
                                Image(uiImage: draft.image)
                                    .resizable()
                                    .scaledToFill()
                                    .frame(width: 92, height: 92)
                                    .clipShape(RoundedRectangle(cornerRadius: AppRadius.medium, style: .continuous))

                                Button {
                                    removeDraftImage(draft.id)
                                } label: {
                                    Image(systemName: "xmark.circle.fill")
                                        .font(.system(size: 18))
                                        .foregroundStyle(.white, .black.opacity(0.5))
                                }
                                .offset(x: 6, y: -6)
                            }
                        }
                    }
                }
            }
        }
        .padding(18)
        .leafyCardStyle()
    }

    private func submitCurrentMode() async {
        switch composerMode {
        case .post:
            await submitPost()
        case .poll:
            await submitPoll()
        }
    }

    private func submitPost() async {
        isSubmitting = true
        defer { isSubmitting = false }

        switch await communityAccessGate.evaluate(.postCreation, forceBootstrap: true) {
        case .allowed:
            break
        case .requiresProfileCompletion:
            showingProfileEditor = true
            errorMessage = L10n.text("第一次发帖前需要先完善社区资料。", language: leafyLanguage)
            return
        case .requiresTermsAcceptance:
            showingTermsSheet = true
            errorMessage = L10n.text("发布前需要先同意社区条款。", language: leafyLanguage)
            return
        case .failed(let message):
            errorMessage = message
            return
        }

        do {
            let createdPost = try await dependencies.communityRepository.createPost(
                input: CreatePostInput(
                    title: title,
                    body: postBody,
                    category: category,
                    isAnonymous: isAnonymous
                ),
                images: draftImages.map(\.upload)
            )
            let message = createdPost.status == "pending_review"
                ? L10n.text("含图片帖子已提交审核，审核通过后会进入公开社区。", language: leafyLanguage)
                : L10n.text("发布成功！", language: leafyLanguage)
            onPosted(message)
            dismiss()
        } catch {
            if error.localizedDescription == CommunityServiceError.profileCompletionRequired.localizedDescription {
                showingProfileEditor = true
            } else if error.localizedDescription == CommunityServiceError.termsAcceptanceRequired.localizedDescription {
                showingTermsSheet = true
            }
            errorMessage = error.localizedDescription
        }
    }

    private func submitPoll() async {
        isSubmitting = true
        defer { isSubmitting = false }

        switch await communityAccessGate.evaluate(.postCreation, forceBootstrap: true) {
        case .allowed:
            break
        case .requiresProfileCompletion:
            showingProfileEditor = true
            errorMessage = L10n.text("发布投票前需要先完善社区资料。", language: leafyLanguage)
            return
        case .requiresTermsAcceptance:
            showingTermsSheet = true
            errorMessage = L10n.text("发布投票前需要先同意社区条款。", language: leafyLanguage)
            return
        case .failed(let message):
            errorMessage = message
            return
        }

        if await pollViewModel.createPoll(input: pollInput) {
            onPosted(L10n.text("投票已提交审核！", language: leafyLanguage))
            dismiss()
        } else {
            errorMessage = pollViewModel.errorMessage
        }
    }

    private func loadSelectedImages(from items: [PhotosPickerItem]) async {
        errorMessage = nil
        var loaded: [CommunityDraftImage] = []
        if items.count > CommunityImageUpload.postImageLimit {
            errorMessage = L10n.text("单条帖子最多上传 %d 张图片。", language: leafyLanguage, CommunityImageUpload.postImageLimit)
        }

        for item in items.prefix(CommunityImageUpload.postImageLimit) {
            do {
                guard let data = try await item.loadTransferable(type: Data.self) else {
                    continue
                }

                let result = try await dependencies.communityImageProcessor.compressedJPEG(
                    from: data,
                    maxPixelDimension: CommunityImageUpload.postImageMaxPixelDimension,
                    maxBytes: CommunityImageUpload.postImageMaxBytes
                )
                guard let preview = ImageDataDecoder.decodedImage(
                    from: result.previewData,
                    targetSize: CGSize(width: 420, height: 420)
                ) else {
                    continue
                }

                loaded.append(CommunityDraftImage(id: result.upload.id, image: preview, upload: result.upload))
            } catch {
                errorMessage = L10n.text("加载图片失败：%@", language: leafyLanguage, error.localizedDescription)
            }
        }

        draftImages = loaded
    }

    private func removeDraftImage(_ id: UUID) {
        draftImages.removeAll { $0.id == id }
    }
}

struct RealCommunityPostDetailSheet: View {
    let post: CommunityPost
    let onPostChanged: (CommunityPost) -> Void
    let onPostRemoved: () -> Void

    @Environment(\.leafyLanguage) private var leafyLanguage
    @Environment(\.dismiss) private var dismiss
    @Environment(\.leafyDependencies) private var dependencies
    @StateObject private var viewModel: CommunityPostDetailViewModel
    @ObservedObject private var sessionManager = CommunitySessionManager.shared
    @State private var commentBody = ""
    @State private var showingProfileEditor = false
    @State private var showingTermsSheet = false
    @State private var reportTarget: CommunityModerationTarget?
    @State private var blockTarget: CommunityModerationTarget?
    @State private var showingDeletePostConfirmation = false
    @State private var operationAlert: LeafyOperationAlert?
    @State private var isCommentSubmitInFlight = false

    private var communityAccessGate: CommunityAccessGate {
        CommunityAccessGate(
            sessionManager: sessionManager,
            termsChecker: dependencies.communityRepository
        )
    }

    init(
        post: CommunityPost,
        onPostChanged: @escaping (CommunityPost) -> Void = { _ in },
        onPostRemoved: @escaping () -> Void = {}
    ) {
        self.post = post
        self.onPostChanged = onPostChanged
        self.onPostRemoved = onPostRemoved
        _viewModel = StateObject(wrappedValue: CommunityPostDetailViewModel(post: post))
    }

    var body: some View {
        NavigationStack {
            ScrollView {
                VStack(alignment: .leading, spacing: AppSpacing.card) {
                    RealCommunityPostCard(
                        post: viewModel.post,
                        showsImageStrip: true,
                        showsBody: true,
                        isLikeLoading: viewModel.isLikeLoading,
                        isFavoriteLoading: viewModel.isFavoriteLoading,
                        isLikeDisabled: viewModel.post.authorID == sessionManager.currentUserID,
                        canDelete: viewModel.post.authorID == sessionManager.currentUserID,
                        onReport: {
                            reportTarget = .post(viewModel.post)
                        },
                        onBlock: {
                            blockTarget = .post(viewModel.post)
                        },
                        onDelete: {
                            showingDeletePostConfirmation = true
                        },
                        onToggleLike: {
                            switch await communityAccessGate.evaluate(.profileInteraction, forceBootstrap: true) {
                            case .allowed:
                                break
                            case .requiresProfileCompletion:
                                viewModel.errorMessage = L10n.text("点赞前需要先完善社区资料。", language: leafyLanguage)
                                showingProfileEditor = true
                                return
                            case .requiresTermsAcceptance:
                                showingTermsSheet = true
                                return
                            case .failed(let message):
                                viewModel.errorMessage = message
                                return
                            }

                            if let updatedPost = await viewModel.toggleLike() {
                                onPostChanged(updatedPost)
                            }
                        },
                        onToggleFavorite: {
                            switch await communityAccessGate.evaluate(.profileInteraction, forceBootstrap: true) {
                            case .allowed:
                                break
                            case .requiresProfileCompletion:
                                viewModel.errorMessage = L10n.text("收藏前需要先完善社区资料。", language: leafyLanguage)
                                showingProfileEditor = true
                                return
                            case .requiresTermsAcceptance:
                                showingTermsSheet = true
                                return
                            case .failed(let message):
                                viewModel.errorMessage = message
                                return
                            }

                            if let updatedPost = await viewModel.toggleFavorite() {
                                onPostChanged(updatedPost)
                                operationAlert = .success(
                                    updatedPost.viewerHasFavorited
                                        ? L10n.text("已添加收藏！", language: leafyLanguage)
                                        : L10n.text("已取消收藏！", language: leafyLanguage)
                                )
                            }
                        }
                    )

                    VStack(alignment: .leading, spacing: 12) {
                        Text("评论区")
                            .leafyHeadline()

                        if viewModel.isLoading && viewModel.comments.isEmpty {
                            ProgressView()
                                .frame(maxWidth: .infinity)
                                .padding(.vertical, 16)
                        } else if let errorMessage = viewModel.errorMessage, viewModel.comments.isEmpty {
                            CommunityErrorCard(message: errorMessage) {
                                Task { await viewModel.load() }
                            }
                        } else if viewModel.comments.isEmpty {
                            Text("还没有评论，先来第一条。")
                                .leafyBody()
                                .foregroundStyle(AppTheme.secondaryText)
                                .padding(14)
                                .frame(maxWidth: .infinity, alignment: .leading)
                                .leafyCardStyle()
                        } else {
                            ForEach(viewModel.comments) { comment in
                                CommunityCommentCard(
                                    comment: comment,
                                    canDelete: comment.authorID == sessionManager.currentUserID,
                                    onReport: {
                                        reportTarget = .comment(comment)
                                    },
                                    onBlock: {
                                        blockTarget = .comment(comment)
                                    },
                                    onDelete: {
                                        Task { await deleteComment(comment) }
                                    }
                                )
                            }
                        }
                    }
                }
                .padding(.horizontal, AppSpacing.page)
                .padding(.top, 8)
                .padding(.bottom, AppSpacing.page)
            }
            .background(LeafyPageBackground())
            .navigationTitle("帖子详情")
            .leafyInlineNavigationTitle()
            .safeAreaInset(edge: .bottom) {
                VStack(spacing: 10) {
                    if let errorMessage = viewModel.errorMessage, !errorMessage.isEmpty {
                        CommunityInlineError(message: errorMessage)
                            .padding(.horizontal, AppSpacing.page)
                    }

                    LeafyGlassGroup(spacing: 12) {
                        HStack(alignment: .bottom, spacing: 12) {
                            commentField
                            sendButton
                        }
                    }
                    .padding(.horizontal, AppSpacing.page)
                    .padding(.top, 8)
                    .padding(.bottom, 4)
                    .background(AppTheme.topBarMaterial)
                }
            }
            .task {
                await viewModel.load()
            }
            .sheet(isPresented: $showingProfileEditor) {
                CommunityProfileEditorSheet()
                    .presentationDetents([.medium, .large])
            }
            .sheet(isPresented: $showingTermsSheet) {
                CommunityTermsAgreementSheet {
                    operationAlert = .success(L10n.text("设置已保存！", language: leafyLanguage))
                }
                    .presentationDetents([.large])
            }
            .leafyOperationAlert($operationAlert)
            .confirmationDialog("举报内容", isPresented: Binding(
                get: { reportTarget != nil },
                set: { if !$0 { reportTarget = nil } }
            ), titleVisibility: .visible) {
                ForEach(communityReportReasons, id: \.self) { reason in
                    Button(reason) {
                        submitReport(reason: reason)
                    }
                }
                Button("取消", role: .cancel) {
                    reportTarget = nil
                }
            } message: {
                Text("举报后该内容会立即从你的页面移除，并进入 24 小时审核队列。")
            }
            .confirmationDialog("屏蔽该用户？", isPresented: Binding(
                get: { blockTarget != nil },
                set: { if !$0 { blockTarget = nil } }
            ), titleVisibility: .visible) {
                Button("屏蔽", role: .destructive) {
                    blockSelectedAuthor()
                }
                Button("取消", role: .cancel) {
                    blockTarget = nil
                }
            } message: {
                Text("屏蔽后将不再看到该用户的帖子、评论和通知。")
            }
            .confirmationDialog("删除这条帖子？", isPresented: $showingDeletePostConfirmation, titleVisibility: .visible) {
                Button("删除", role: .destructive) {
                    Task { await deleteCurrentPost() }
                }
                Button("取消", role: .cancel) {}
            }
        }
    }

    private var isSubmitDisabled: Bool {
        isCommentSubmitInFlight || viewModel.isSubmitting || commentBody.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
    }

    @ViewBuilder
    private var commentField: some View {
        let field = TextField("写评论…", text: $commentBody, axis: .vertical)
            .lineLimit(1...3)
            .leafyBody()
            .padding(.horizontal, 14)
            .padding(.vertical, 10)
            .frame(minHeight: 44, alignment: .center)

        field
            .leafyGlassSurface(
                in: RoundedRectangle(cornerRadius: AppRadius.medium, style: .continuous),
                isInteractive: true
            )
    }

    @ViewBuilder
    private var sendButton: some View {
#if os(iOS)
        if #available(iOS 26.0, *) {
            Button {
                Task { await submitComment() }
            } label: {
                Text(isCommentSubmitInFlight ? L10n.text("发送中", language: leafyLanguage) : L10n.text("发送", language: leafyLanguage))
                    .font(.system(size: 17, weight: .semibold))
                    .frame(minWidth: 54, minHeight: 30)
            }
            .buttonStyle(.glassProminent)
            .controlSize(.regular)
            .tint(AppTheme.accent)
            .disabled(isSubmitDisabled)
        } else {
            standardSendButton
        }
#else
        standardSendButton
#endif
    }

    private var standardSendButton: some View {
        Button {
            Task { await submitComment() }
        } label: {
            Text(isCommentSubmitInFlight ? L10n.text("发送中", language: leafyLanguage) : L10n.text("发送", language: leafyLanguage))
                .font(.system(size: 17, weight: .semibold))
                .foregroundStyle(AppTheme.textOnAccent)
                .frame(width: 64, height: 44)
                .background(
                    RoundedRectangle(cornerRadius: AppRadius.medium, style: .continuous)
                        .fill(isSubmitDisabled ? AppTheme.accent.opacity(0.45) : AppTheme.accent)
                )
        }
        .buttonStyle(.plain)
        .disabled(isSubmitDisabled)
    }

    @MainActor
    private func submitComment() async {
        guard !isCommentSubmitInFlight else { return }
        let pendingBody = commentBody
        guard !pendingBody.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty else { return }

        isCommentSubmitInFlight = true
        defer { isCommentSubmitInFlight = false }

        switch await communityAccessGate.evaluate(.commentCreation, forceBootstrap: true) {
        case .allowed:
            break
        case .requiresProfileCompletion:
            viewModel.errorMessage = L10n.text("评论前需要先完善社区资料。", language: leafyLanguage)
            showingProfileEditor = true
            return
        case .requiresTermsAcceptance:
            viewModel.errorMessage = L10n.text("评论前需要先同意社区条款。", language: leafyLanguage)
            showingTermsSheet = true
            return
        case .failed(let message):
            viewModel.errorMessage = message
            return
        }

        let didSucceed = await viewModel.submitComment(body: pendingBody)
        if didSucceed {
            commentBody = ""
            operationAlert = .success(L10n.text("评论发布成功！", language: leafyLanguage))
        }
    }

    @MainActor
    private func submitReport(reason: String) {
        guard let target = reportTarget else { return }
        reportTarget = nil
        Task {
            switch target {
            case .post:
                if await viewModel.reportPost(reason: reason) {
                    operationAlert = .success(
                        L10n.text("举报已提交！", language: leafyLanguage),
                        action: {
                            onPostRemoved()
                            dismiss()
                        }
                    )
                }
            case .comment(let comment):
                await viewModel.reportComment(comment, reason: reason)
                if viewModel.errorMessage == nil {
                    operationAlert = .success(L10n.text("举报已提交！", language: leafyLanguage))
                }
            }
        }
    }

    @MainActor
    private func blockSelectedAuthor() {
        guard let target = blockTarget else { return }
        blockTarget = nil
        Task {
            switch target {
            case .post:
                if await viewModel.blockPostAuthor() {
                    operationAlert = .success(
                        L10n.text("已屏蔽该用户！", language: leafyLanguage),
                        action: {
                            onPostRemoved()
                            dismiss()
                        }
                    )
                }
            case .comment(let comment):
                await viewModel.blockCommentAuthor(comment)
                if viewModel.errorMessage == nil {
                    operationAlert = .success(L10n.text("已屏蔽该用户！", language: leafyLanguage))
                }
            }
        }
    }

    @MainActor
    private func deleteCurrentPost() async {
        if await viewModel.deletePost() {
            operationAlert = .success(
                L10n.text("帖子已删除！", language: leafyLanguage),
                action: {
                    onPostRemoved()
                    dismiss()
                }
            )
        }
    }

    @MainActor
    private func deleteComment(_ comment: CommunityComment) async {
        do {
            try await dependencies.communityRepository.deleteComment(commentID: comment.id)
            await viewModel.load()
            operationAlert = .success(L10n.text("评论已删除！", language: leafyLanguage))
        } catch {
            viewModel.errorMessage = error.localizedDescription
        }
    }
}

struct RealCommunityPostCard: View {
    @Environment(\.leafyLanguage) private var leafyLanguage

    let post: CommunityPost
    var showsImageStrip = true
    var showsBody = false
    var isLikeLoading = false
    var isFavoriteLoading = false
    var isLikeDisabled = false
    var allowsImagePreview = true
    var canDelete = false
    var onOpen: (() -> Void)? = nil
    var onReport: (() -> Void)? = nil
    var onBlock: (() -> Void)? = nil
    var onDelete: (() -> Void)? = nil
    var onToggleLike: (() async -> Void)? = nil
    var onToggleFavorite: (() async -> Void)? = nil

    @State private var selectedImagePreviewIndex: Int?

    var body: some View {
        VStack(alignment: .leading, spacing: 14) {
            postSummary
                .contentShape(Rectangle())
                .onTapGesture {
                    onOpen?()
                }

            if showsImageStrip, !post.images.isEmpty {
                CommunityRemoteImageStrip(
                    images: post.images,
                    allowsSelection: allowsImagePreview,
                    onTapStrip: onOpen
                ) { index in
                    selectedImagePreviewIndex = index
                }
            }

            HStack(spacing: 16) {
                CommunityMetric(icon: "bubble.left", value: "\(post.commentCount)")
                if let onToggleLike {
                    CommunityLikeButton(
                        isLiked: post.viewerHasLiked,
                        value: "\(post.likeCount)",
                        isLoading: isLikeLoading,
                        isDisabled: isLikeDisabled,
                        action: onToggleLike
                    )
                } else {
                    CommunityMetric(icon: post.viewerHasLiked ? "heart.fill" : "heart", value: "\(post.likeCount)")
                }
                if let onToggleFavorite {
                    CommunityFavoriteButton(
                        isFavorited: post.viewerHasFavorited,
                        isLoading: isFavoriteLoading,
                        action: onToggleFavorite
                    )
                }
            }
        }
        .padding(18)
        .leafyCardStyle()
        .overlay {
            if post.pin != nil {
                RoundedRectangle(cornerRadius: AppRadius.large, style: .continuous)
                    .strokeBorder(AppTheme.warning.opacity(0.42), lineWidth: 1.5)
            }
        }
        .contentShape(Rectangle())
        .onTapGesture {
            onOpen?()
        }
        .leafyFullScreenCover(isPresented: Binding(
            get: { selectedImagePreviewIndex != nil },
            set: { if !$0 { selectedImagePreviewIndex = nil } }
        )) {
            if let selectedImagePreviewIndex {
                CommunityRemoteImagePreview(
                    images: post.images,
                    initialIndex: selectedImagePreviewIndex
                )
            }
        }
    }

    private var postSummary: some View {
        VStack(alignment: .leading, spacing: 12) {
            HStack(spacing: 9) {
                authorIdentity

                Spacer()

                if let pin = post.pin {
                    CommunityPinBadge(pin: pin)
                }

                if let moderationStatusLabel = post.moderationStatusLabel {
                    Text(moderationStatusLabel)
                        .microCaption()
                        .foregroundStyle(AppTheme.warning)
                        .padding(.horizontal, 8)
                        .padding(.vertical, 5)
                        .background(AppTheme.warning.opacity(0.12), in: Capsule())
                } else {
                    Text(post.categoryLabel)
                        .microCaption()
                        .foregroundStyle(AppTheme.accentEmphasis)
                        .padding(.horizontal, 8)
                        .padding(.vertical, 5)
                        .background(AppTheme.softFill, in: Capsule())
                }

                if hasModerationActions {
                    moderationMenu
                }
            }

            postTitleText

            if showsBody, !post.body.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
                CommunityLinkedText(post.body)
            }
        }
    }

    @ViewBuilder
    private var authorIdentity: some View {
        if let author = post.isAnonymous ? nil : post.author {
            NavigationLink {
                CommunityUserProfileView(profile: author)
            } label: {
                authorIdentityContent(profile: author)
            }
            .buttonStyle(.plain)
        } else {
            authorIdentityContent(profile: nil)
        }
    }

    private func authorIdentityContent(profile: CommunityProfile?) -> some View {
        HStack(spacing: 9) {
            CommunityAvatarView(profile: profile, size: 34)

            VStack(alignment: .leading, spacing: 2) {
                Text(post.displayAuthorName)
                    .leafySubheadline()
                    .fontWeight(.semibold)
                    .foregroundStyle(AppTheme.primaryText)
                    .lineLimit(1)
                    .minimumScaleFactor(0.85)
                Text(post.relativeTimestamp)
                    .microCaption()
                    .foregroundStyle(AppTheme.secondaryText)
            }
        }
        .contentShape(Rectangle())
    }

    @ViewBuilder
    private var postTitleText: some View {
        if showsBody {
            Text(post.title)
                .leafyHeadline()
                .foregroundStyle(AppTheme.primaryText)
                .textSelection(.enabled)
        } else {
            Text(post.title)
                .leafyHeadline()
                .foregroundStyle(AppTheme.primaryText)
        }
    }
    private var hasModerationActions: Bool {
        true
    }

    private var moderationMenu: some View {
        Menu {
            ShareLink(item: post.shareURL, subject: Text(post.title), message: Text(post.shareText)) {
                Label("分享", systemImage: "square.and.arrow.up")
            }

            Button {
                LeafyClipboard.string = post.title
            } label: {
                Label("复制标题", systemImage: "doc.on.doc")
            }

            if !post.body.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
                Button {
                    LeafyClipboard.string = post.body
                } label: {
                    Label("复制正文", systemImage: "text.quote")
                }
            }

            if let onReport {
                Button(role: .destructive) {
                    onReport()
                } label: {
                    Label("举报", systemImage: "exclamationmark.bubble")
                }
            }

            if let onBlock, post.authorID != CommunitySessionManager.shared.currentUserID {
                Button(role: .destructive) {
                    onBlock()
                } label: {
                    Label("屏蔽该用户", systemImage: "person.crop.circle.badge.xmark")
                }
            }

            if canDelete, let onDelete {
                Button(role: .destructive) {
                    onDelete()
                } label: {
                    Label("删除", systemImage: "trash")
                }
            }
        } label: {
            Image(systemName: "ellipsis.circle")
                .font(.system(size: 18, weight: .semibold))
                .foregroundStyle(AppTheme.secondaryText)
                .frame(width: 30, height: 30)
        }
        .buttonStyle(.plain)
        .accessibilityLabel("更多操作")
    }
}

private struct CommunityLinkedText: View {
    let text: String

    init(_ text: String) {
        self.text = text
    }

    var body: some View {
        Text(LeafyLinkedTextBuilder.attributedString(from: text))
            .leafyBody()
            .foregroundStyle(AppTheme.secondaryText)
            .tint(AppTheme.accent)
            .textSelection(.enabled)
    }
}

private struct CommunityRemoteImageStrip: View {
    let images: [CommunityPostImage]
    var allowsSelection = true
    var onTapStrip: (() -> Void)? = nil
    let onSelectImage: (Int) -> Void

    var body: some View {
        ScrollView(.horizontal, showsIndicators: false) {
            HStack(spacing: 10) {
                ForEach(Array(images.enumerated()), id: \.element.id) { index, image in
                    if allowsSelection {
                        Button {
                            onSelectImage(index)
                        } label: {
                            imageCell(image)
                        }
                        .buttonStyle(.plain)
                    } else {
                        imageCell(image)
                    }
                }
            }
        }
        .contentShape(Rectangle())
        .onTapGesture {
            if !allowsSelection {
                onTapStrip?()
            }
        }
    }

    @ViewBuilder
    private func imageCell(_ image: CommunityPostImage) -> some View {
        if let thumbnailURL = image.resolvedThumbnailURL {
            AsyncImage(url: thumbnailURL) { phase in
                switch phase {
                case .empty:
                    RoundedRectangle(cornerRadius: AppRadius.medium, style: .continuous)
                        .fill(AppTheme.fill)
                        .overlay(ProgressView())
                case .success(let loadedImage):
                    loadedImage
                        .resizable()
                        .scaledToFill()
                case .failure:
                    RoundedRectangle(cornerRadius: AppRadius.medium, style: .continuous)
                        .fill(AppTheme.fill)
                        .overlay(Image(systemName: "photo").foregroundStyle(AppTheme.secondaryText))
                @unknown default:
                    EmptyView()
                }
            }
            .frame(width: 120, height: 120)
            .clipShape(RoundedRectangle(cornerRadius: AppRadius.medium, style: .continuous))
        }
    }
}

private struct CommunityRemoteImagePreview: View {
    let images: [CommunityPostImage]
    let initialIndex: Int

    @Environment(\.colorScheme) private var colorScheme
    @Environment(\.dismiss) private var dismiss
    @State private var selectedIndex = 0

    var body: some View {
        NavigationStack {
            ZStack {
                AppTheme.imagePreviewBackground(for: colorScheme)
                    .ignoresSafeArea()

                TabView(selection: $selectedIndex) {
                    ForEach(Array(images.enumerated()), id: \.element.id) { index, image in
                        if let fullURL = image.resolvedFullURL {
                            ZoomableRemotePreviewImage(url: fullURL)
                                .padding(.horizontal, 20)
                                .padding(.vertical, 32)
                                .tag(index)
                        } else {
                            ContentUnavailableView("图片无法加载", systemImage: "photo")
                                .tag(index)
                        }
                    }
                }
                .leafyImagePreviewTabStyle(showsIndex: images.count > 1)
                .background(AppTheme.imagePreviewBackground(for: colorScheme))

                VStack {
                    Spacer()
                    if images.count > 1 {
                        Text("\(selectedIndex + 1) / \(images.count)")
                            .font(.headline)
                            .foregroundStyle(.white)
                            .padding(.horizontal, 14)
                            .padding(.vertical, 8)
                            .background(.black.opacity(0.45), in: Capsule())
                            .padding(.bottom, 22)
                    }
                }
            }
            .onAppear {
                selectedIndex = min(max(initialIndex, 0), max(images.count - 1, 0))
            }
            .toolbar {
                ToolbarItem(placement: .leafyLeading) {
                    Button("关闭") {
                        dismiss()
                    }
                    .foregroundStyle(AppTheme.danger)
                }
            }
            .leafyNavigationToolbarBackgroundHidden()
        }
    }
}

private struct ZoomableRemotePreviewImage: View {
    let url: URL

    @State private var scale: CGFloat = 1
    @State private var baseScale: CGFloat = 1
    @State private var offset: CGSize = .zero
    @State private var baseOffset: CGSize = .zero

    var body: some View {
        GeometryReader { geometry in
            AsyncImage(url: url) { phase in
                switch phase {
                case .empty:
                    ProgressView()
                        .frame(width: geometry.size.width, height: geometry.size.height)
                case .success(let image):
                    image
                        .resizable()
                        .scaledToFit()
                        .frame(width: geometry.size.width, height: geometry.size.height)
                        .scaleEffect(scale)
                        .offset(offset)
                        .simultaneousGesture(magnificationGesture)
                        .modifier(ZoomedRemoteImageDragModifier(
                            isEnabled: scale > 1.02,
                            offset: $offset,
                            baseOffset: $baseOffset
                        ))
                        .animation(.spring(response: 0.22, dampingFraction: 0.88), value: scale)
                        .animation(.spring(response: 0.22, dampingFraction: 0.88), value: offset)
                case .failure:
                    ContentUnavailableView("图片无法加载", systemImage: "photo")
                        .frame(width: geometry.size.width, height: geometry.size.height)
                @unknown default:
                    EmptyView()
                }
            }
        }
    }

    private var magnificationGesture: some Gesture {
        MagnifyGesture()
            .onChanged { value in
                scale = min(max(baseScale * value.magnification, 1), 5)
                if scale <= 1.02 {
                    offset = .zero
                    baseOffset = .zero
                }
            }
            .onEnded { _ in
                scale = min(max(scale, 1), 5)
                baseScale = scale
                if scale <= 1.02 {
                    scale = 1
                    baseScale = 1
                    offset = .zero
                    baseOffset = .zero
                }
            }
    }

}

private struct ZoomedRemoteImageDragModifier: ViewModifier {
    let isEnabled: Bool
    @Binding var offset: CGSize
    @Binding var baseOffset: CGSize

    func body(content: Content) -> some View {
        if isEnabled {
            content.simultaneousGesture(dragGesture)
        } else {
            content
        }
    }

    private var dragGesture: some Gesture {
        DragGesture()
            .onChanged { value in
                offset = CGSize(
                    width: baseOffset.width + value.translation.width,
                    height: baseOffset.height + value.translation.height
                )
            }
            .onEnded { _ in
                baseOffset = offset
            }
    }
}

private struct CommunityCommentCard: View {
    let comment: CommunityComment
    var canDelete = false
    var onReport: (() -> Void)? = nil
    var onBlock: (() -> Void)? = nil
    var onDelete: (() -> Void)? = nil

    var body: some View {
        VStack(alignment: .leading, spacing: 10) {
            HStack(spacing: 10) {
                authorIdentity

                Spacer()

                if hasModerationActions {
                    moderationMenu
                }
            }

            Text(comment.body)
                .leafyBody()
                .foregroundStyle(AppTheme.secondaryText)
        }
        .padding(16)
        .leafyCardStyle()
    }

    @ViewBuilder
    private var authorIdentity: some View {
        if let author = comment.isAnonymous ? nil : comment.author {
            NavigationLink {
                CommunityUserProfileView(profile: author)
            } label: {
                authorIdentityContent(profile: author)
            }
            .buttonStyle(.plain)
        } else {
            authorIdentityContent(profile: nil)
        }
    }

    private func authorIdentityContent(profile: CommunityProfile?) -> some View {
        HStack(spacing: 10) {
            CommunityAvatarView(profile: profile, size: 32)

            VStack(alignment: .leading, spacing: 2) {
                Text(comment.displayAuthorName)
                    .leafyHeadline()
                    .foregroundStyle(AppTheme.primaryText)
                Text(comment.relativeTimestamp)
                    .microCaption()
                    .foregroundStyle(AppTheme.tertiaryText)
            }
        }
        .contentShape(Rectangle())
    }

    private var hasModerationActions: Bool {
        onReport != nil || onBlock != nil || (canDelete && onDelete != nil)
    }

    private var moderationMenu: some View {
        Menu {
            if let onReport {
                Button(role: .destructive) {
                    onReport()
                } label: {
                    Label("举报", systemImage: "exclamationmark.bubble")
                }
            }

            if let onBlock, comment.authorID != CommunitySessionManager.shared.currentUserID {
                Button(role: .destructive) {
                    onBlock()
                } label: {
                    Label("屏蔽该用户", systemImage: "person.crop.circle.badge.xmark")
                }
            }

            if canDelete, let onDelete {
                Button(role: .destructive) {
                    onDelete()
                } label: {
                    Label("删除", systemImage: "trash")
                }
            }
        } label: {
            Image(systemName: "ellipsis.circle")
                .font(.system(size: 18, weight: .semibold))
                .foregroundStyle(AppTheme.secondaryText)
                .frame(width: 30, height: 30)
        }
        .buttonStyle(.plain)
        .accessibilityLabel("评论操作")
    }
}

private struct CommunityProfileBanner: View {
    let profile: CommunityProfile

    var body: some View {
        HStack(spacing: 14) {
            CommunityAvatarView(profile: profile, size: 52)

            VStack(alignment: .leading, spacing: 4) {
                Text(profile.limitedResolvedDisplayName)
                    .leafyHeadline()
                    .foregroundStyle(AppTheme.primaryText)
                Text(profile.subtitleText)
                    .microCaption()
                    .foregroundStyle(AppTheme.secondaryText)
            }

            Spacer()
        }
        .padding(16)
        .leafyCardStyle()
    }
}

private struct CommunityMetric: View {
    let icon: String
    let value: String

    var body: some View {
        HStack(spacing: 6) {
            Image(systemName: icon)
            Text(value)
                .lineLimit(1)
        }
        .font(.caption.weight(.semibold))
        .foregroundStyle(AppTheme.secondaryText)
    }
}

private struct CommunityLikeButton: View {
    let isLiked: Bool
    let value: String
    let isLoading: Bool
    let isDisabled: Bool
    let action: (() async -> Void)?

    var body: some View {
        Button {
            guard !isDisabled else { return }
            guard let action else { return }
            Task {
                await action()
            }
        } label: {
            HStack(spacing: 6) {
                if isLoading {
                    ProgressView()
                        .scaleEffect(0.7)
                } else {
                    Image(systemName: isDisabled ? "heart.slash" : (isLiked ? "heart.fill" : "heart"))
                }

                Text(value)
                    .lineLimit(1)
            }
            .font(.caption.weight(.semibold))
            .foregroundStyle(isDisabled ? AppTheme.tertiaryText : (isLiked ? AppTheme.accentEmphasis : AppTheme.secondaryText))
        }
        .buttonStyle(.plain)
        .disabled(isDisabled || action == nil)
        .accessibilityHint(isDisabled ? L10n.text("不能点赞自己的帖子") : "")
    }
}

private struct CommunityFavoriteButton: View {
    let isFavorited: Bool
    let isLoading: Bool
    let action: (() async -> Void)?

    var body: some View {
        Button {
            guard let action else { return }
            Task {
                await action()
            }
        } label: {
            Group {
                if isLoading {
                    ProgressView()
                        .scaleEffect(0.7)
                } else {
                    Image(systemName: isFavorited ? "bookmark.fill" : "bookmark")
                }
            }
            .font(.caption.weight(.semibold))
            .foregroundStyle(isFavorited ? AppTheme.accentEmphasis : AppTheme.secondaryText)
            .frame(width: 28, height: 24)
            .offset(x: -5)
        }
        .buttonStyle(.plain)
        .disabled(action == nil || isLoading)
        .accessibilityLabel(isFavorited ? L10n.text("取消收藏") : L10n.text("收藏"))
    }
}

private struct CommunityErrorCard: View {
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

private struct CommunityInlineError: View {
    let message: String

    var body: some View {
        Text(message)
            .leafyBody()
            .foregroundStyle(AppTheme.danger)
            .padding(14)
            .frame(maxWidth: .infinity, alignment: .leading)
            .background(AppTheme.cardBackground, in: RoundedRectangle(cornerRadius: AppRadius.medium, style: .continuous))
    }
}

private struct CommunityTermsPromptCard: View {
    let action: () -> Void

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            HStack(spacing: 10) {
                Image(systemName: "checkmark.shield.fill")
                    .foregroundStyle(AppTheme.accentEmphasis)
                Text("社区条款")
                    .leafyHeadline()
                    .foregroundStyle(AppTheme.primaryText)
            }

            Text("进入社区前请确认已阅读并同意 \(AppBrand.displayName) 社区条款。社区对违规内容和滥用用户零容忍。")
                .leafyBody()
                .foregroundStyle(AppTheme.secondaryText)

            Button("阅读并同意") {
                action()
            }
            .foregroundStyle(AppTheme.accentEmphasis)
        }
        .padding(18)
        .leafyCardStyle()
    }
}

struct CommunityTermsAgreementSheet: View {
    let onAccepted: () -> Void

    @Environment(\.dismiss) private var dismiss
    @Environment(\.leafyDependencies) private var dependencies
    @State private var isAccepted = false
    @State private var isSubmitting = false
    @State private var errorMessage: String?

    init(onAccepted: @escaping () -> Void = {}) {
        self.onAccepted = onAccepted
    }

    var body: some View {
        NavigationStack {
            ScrollView {
                VStack(alignment: .leading, spacing: AppSpacing.card) {
                    VStack(alignment: .leading, spacing: 14) {
                        Text("\(AppBrand.displayName) 社区条款")
                            .title2()
                            .foregroundStyle(AppTheme.primaryText)

                        Text("使用社区代表你同意遵守以下规则。\(AppBrand.displayName) 对违规内容和滥用用户采取零容忍政策。")
                            .leafyBody()
                            .foregroundStyle(AppTheme.secondaryText)
                    }
                    .padding(18)
                    .leafyCardStyle()

                    VStack(alignment: .leading, spacing: 12) {
                        termsLine("不得发布辱骂、骚扰、歧视、威胁、色情低俗、违法、侵权、侵犯隐私或其他令人反感的内容。")
                        termsLine("不得滥用匿名发布、冒充他人、刷屏、恶意引战或规避审核。")
                        termsLine("\(AppBrand.displayName) 会过滤违规内容；用户可以举报内容、屏蔽用户，并可删除自己发布的帖子和评论。")
                        termsLine("开发者会在 24 小时内处理违规举报，必要时移除内容并禁言或移除违规用户。")
                        termsLine("社区安全联系邮箱：\(CommunityTerms.supportEmail)。")
                    }
                    .padding(18)
                    .leafyCardStyle()

                    Toggle(isOn: $isAccepted) {
                        Text("我已阅读并同意社区条款")
                            .leafyBody()
                            .foregroundStyle(AppTheme.primaryText)
                    }
                    .tint(AppTheme.accent)
                    .padding(18)
                    .leafyCardStyle()

                    if let errorMessage {
                        CommunityInlineError(message: errorMessage)
                    }
                }
                .padding(AppSpacing.page)
            }
            .background(LeafyPageBackground())
            .navigationTitle("社区条款")
            .leafyInlineNavigationTitle()
            .toolbar {
                ToolbarItem(placement: .leafyLeading) {
                    Button("关闭") {
                        dismiss()
                    }
                }

                ToolbarItem(placement: .leafyTrailing) {
                    Button(isSubmitting ? "保存中" : "同意") {
                        Task { await accept() }
                    }
                    .disabled(!isAccepted || isSubmitting)
                }
            }
        }
    }

    private func termsLine(_ text: String) -> some View {
        HStack(alignment: .top, spacing: 10) {
            Image(systemName: "checkmark.circle.fill")
                .foregroundStyle(AppTheme.accentEmphasis)
                .padding(.top, 2)
            Text(text)
                .leafyBody()
                .foregroundStyle(AppTheme.secondaryText)
                .fixedSize(horizontal: false, vertical: true)
        }
    }

    @MainActor
    private func accept() async {
        guard isAccepted else { return }
        isSubmitting = true
        defer { isSubmitting = false }

        do {
            try await dependencies.communityActivityRepository.acceptCurrentTerms()
            onAccepted()
            dismiss()
        } catch {
            errorMessage = error.localizedDescription
        }
    }
}
