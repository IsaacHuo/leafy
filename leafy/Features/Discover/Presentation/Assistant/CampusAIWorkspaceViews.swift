import SwiftUI

struct CampusAIWorkspaceShell<Sidebar: View, Content: View>: View {
    @Environment(\.accessibilityReduceMotion) private var accessibilityReduceMotion
    @Environment(\.horizontalSizeClass) private var horizontalSizeClass
    @Binding private var isSidebarPresented: Bool
    @Binding private var columnVisibility: NavigationSplitViewVisibility
    @GestureState private var dragTranslation: CGFloat = 0

    private let sidebar: Sidebar
    private let content: Content

    init(
        isSidebarPresented: Binding<Bool>,
        columnVisibility: Binding<NavigationSplitViewVisibility>,
        @ViewBuilder sidebar: () -> Sidebar,
        @ViewBuilder content: () -> Content
    ) {
        _isSidebarPresented = isSidebarPresented
        _columnVisibility = columnVisibility
        self.sidebar = sidebar()
        self.content = content()
    }

    var body: some View {
        Group {
            if horizontalSizeClass == .regular {
                NavigationSplitView(columnVisibility: $columnVisibility) {
                    sidebar
                        .navigationSplitViewColumnWidth(min: 300, ideal: 340, max: 380)
                } detail: {
                    content
                }
                .navigationSplitViewStyle(.balanced)
            } else {
                compactWorkspace
            }
        }
    }

    private var compactWorkspace: some View {
        GeometryReader { proxy in
            let drawerWidth = min(380, proxy.size.width * 0.84)
            let progress = drawerProgress(drawerWidth: drawerWidth)

            ZStack(alignment: .leading) {
                AppTheme.cardElevated
                    .ignoresSafeArea()

                sidebar
                    .frame(width: drawerWidth)
                    .offset(x: -drawerWidth * (1 - progress))
                    .opacity(0.82 + (0.18 * progress))

                content
                    .clipShape(
                        RoundedRectangle(
                            cornerRadius: 30 * progress,
                            style: .continuous
                        )
                    )
                    .shadow(
                        color: Color.black.opacity(0.12 * progress),
                        radius: 22 * progress,
                        x: -4,
                        y: 0
                    )
                    .scaleEffect(1 - (accessibilityReduceMotion ? 0 : 0.035 * progress))
                    .offset(x: drawerWidth * progress)
                    .allowsHitTesting(!isSidebarPresented)
                    .accessibilityHidden(isSidebarPresented)
                    .overlay {
                        if isSidebarPresented {
                            Color.black.opacity(0.001)
                                .contentShape(Rectangle())
                                .onTapGesture(perform: closeSidebar)
                                .gesture(closeGesture(drawerWidth: drawerWidth))
                        }
                    }

                if !isSidebarPresented {
                    Color.clear
                        .contentShape(Rectangle())
                        .frame(width: 24)
                        .frame(maxHeight: .infinity)
                        .gesture(openGesture(drawerWidth: drawerWidth))
                        .accessibilityHidden(true)
                }
            }
            .clipped()
        }
    }

    private func drawerProgress(drawerWidth: CGFloat) -> CGFloat {
        let rawProgress: CGFloat
        if isSidebarPresented {
            rawProgress = 1 + min(0, dragTranslation) / drawerWidth
        } else {
            rawProgress = max(0, dragTranslation) / drawerWidth
        }
        return min(max(rawProgress, 0), 1)
    }

    private func openGesture(drawerWidth: CGFloat) -> some Gesture {
        DragGesture(minimumDistance: 10)
            .updating($dragTranslation) { value, state, _ in
                state = max(0, value.translation.width)
            }
            .onEnded { value in
                let projected = max(value.translation.width, value.predictedEndTranslation.width)
                if projected > drawerWidth * 0.24 {
                    openSidebar()
                }
            }
    }

    private func closeGesture(drawerWidth: CGFloat) -> some Gesture {
        DragGesture(minimumDistance: 10)
            .updating($dragTranslation) { value, state, _ in
                state = min(0, value.translation.width)
            }
            .onEnded { value in
                let projected = min(value.translation.width, value.predictedEndTranslation.width)
                if projected < -drawerWidth * 0.18 {
                    closeSidebar()
                }
            }
    }

    private func openSidebar() {
        withAnimation(sidebarAnimation) {
            isSidebarPresented = true
        }
    }

    private func closeSidebar() {
        withAnimation(sidebarAnimation) {
            isSidebarPresented = false
        }
    }

    private var sidebarAnimation: Animation {
        accessibilityReduceMotion
            ? .easeOut(duration: 0.16)
            : .spring(response: 0.34, dampingFraction: 0.88)
    }
}

struct CampusAIWorkspaceSidebar: View {
    let isActive: Bool
    let conversations: [CampusAIConversation]
    let selectedConversationID: UUID?
    let artifactCount: Int
    let search: () -> Void
    let startNewConversation: () -> Void
    let openArtifactLibrary: () -> Void
    let selectConversation: (CampusAIConversation) -> Void
    let deleteConversation: (CampusAIConversation) -> Void
    let openSettings: () -> Void
    let leaveWorkspace: () -> Void
    @AccessibilityFocusState private var isHeaderFocused: Bool

    var body: some View {
        VStack(spacing: 0) {
            header
            conversationList
            footer
        }
        .background(Color(uiColor: .systemBackground))
        .onAppear(perform: updateAccessibilityFocus)
        .onChange(of: isActive) { _, _ in
            updateAccessibilityFocus()
        }
    }

    private var header: some View {
        HStack(spacing: 12) {
            Text("Leafy")
                .font(.largeTitle.bold())
                .foregroundStyle(AppTheme.primaryText)
                .accessibilityAddTraits(.isHeader)
                .accessibilityFocused($isHeaderFocused)

            Spacer(minLength: 12)

            Button(action: search) {
                Image(systemName: "magnifyingglass")
                    .font(.system(size: 18, weight: .semibold))
                    .frame(width: 44, height: 44)
            }
            .buttonStyle(.borderless)
            .accessibilityLabel("搜索对话与成品")
        }
        .padding(.horizontal, 20)
        .padding(.top, 12)
        .padding(.bottom, 8)
    }

    private var conversationList: some View {
        List {
            Section {
                sidebarButton(
                    title: "新建对话",
                    systemImage: "square.and.pencil",
                    action: startNewConversation
                )
                sidebarButton(
                    title: "成品库",
                    systemImage: "books.vertical",
                    value: artifactCount == 0 ? nil : String(artifactCount),
                    action: openArtifactLibrary
                )
            }

            Section("最近") {
                if conversations.isEmpty {
                    Text("暂无对话")
                        .foregroundStyle(AppTheme.secondaryText)
                } else {
                    ForEach(conversations) { conversation in
                        Button {
                            selectConversation(conversation)
                        } label: {
                            HStack(spacing: 10) {
                                Text(conversation.title.nonEmptyTrimmed ?? "新的对话")
                                    .font(.body)
                                    .foregroundStyle(AppTheme.primaryText)
                                    .lineLimit(1)

                                Spacer(minLength: 8)

                                if selectedConversationID == conversation.id {
                                    Image(systemName: "checkmark")
                                        .font(.caption.weight(.semibold))
                                        .foregroundStyle(AppTheme.accent)
                                }
                            }
                            .contentShape(Rectangle())
                        }
                        .buttonStyle(.plain)
                        .swipeActions {
                            Button(role: .destructive) {
                                deleteConversation(conversation)
                            } label: {
                                Label("删除", systemImage: "trash")
                            }
                        }
                    }
                }
            }
        }
        .listStyle(.plain)
        .scrollContentBackground(.hidden)
    }

    private var footer: some View {
        VStack(spacing: 0) {
            Divider()
            sidebarButton(title: "设置", systemImage: "gearshape", action: openSettings)
            sidebarButton(
                title: "返回 MyLeafy",
                systemImage: "rectangle.portrait.and.arrow.right",
                action: leaveWorkspace
            )
        }
        .padding(.horizontal, 8)
        .padding(.vertical, 8)
    }

    private func sidebarButton(
        title: String,
        systemImage: String,
        value: String? = nil,
        action: @escaping () -> Void
    ) -> some View {
        Button(action: action) {
            HStack(spacing: 14) {
                Image(systemName: systemImage)
                    .font(.system(size: 18, weight: .medium))
                    .frame(width: 24)
                Text(title)
                    .font(.body.weight(.medium))
                Spacer(minLength: 8)
                if let value {
                    Text(value)
                        .font(.caption.weight(.semibold))
                        .foregroundStyle(AppTheme.secondaryText)
                }
            }
            .foregroundStyle(AppTheme.primaryText)
            .frame(minHeight: 44)
            .padding(.horizontal, 12)
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
    }

    private func updateAccessibilityFocus() {
        guard isActive else { return }
        Task { @MainActor in
            await Task.yield()
            isHeaderFocused = true
        }
    }
}

struct CampusAIArtifactLibraryView: View {
    let items: [CampusAIArtifactLibraryItem]
    let openArtifact: (CampusAIArtifactLibraryItem) -> Void

    var body: some View {
        Group {
            if items.isEmpty {
                ContentUnavailableView(
                    "暂无成品",
                    systemImage: "books.vertical",
                    description: Text("生成的计划、报告、清单和表格会集中显示在这里。")
                )
            } else {
                List(items) { item in
                    Button {
                        openArtifact(item)
                    } label: {
                        CampusAIArtifactLibraryRow(item: item)
                    }
                    .buttonStyle(.plain)
                }
                .listStyle(.plain)
            }
        }
        .navigationTitle("成品库")
        .navigationBarTitleDisplayMode(.inline)
    }
}

struct CampusAIWorkspaceSearchView: View {
    let conversations: [CampusAIConversation]
    let artifacts: [CampusAIArtifactLibraryItem]
    let selectConversation: (CampusAIConversation) -> Void
    let openArtifact: (CampusAIArtifactLibraryItem) -> Void
    @State private var query = ""

    private var conversationResults: [CampusAIConversation] {
        CampusAIWorkspaceSearch.conversations(conversations, query: query)
    }

    private var artifactResults: [CampusAIArtifactLibraryItem] {
        CampusAIWorkspaceSearch.artifacts(artifacts, query: query)
    }

    var body: some View {
        Group {
            if query.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
                ContentUnavailableView(
                    "搜索 Leafy",
                    systemImage: "magnifyingglass",
                    description: Text("按标题或摘要搜索本机对话与成品。")
                )
            } else if conversationResults.isEmpty, artifactResults.isEmpty {
                ContentUnavailableView.search(text: query)
            } else {
                List {
                    if !conversationResults.isEmpty {
                        Section("对话") {
                            ForEach(conversationResults) { conversation in
                                Button {
                                    selectConversation(conversation)
                                } label: {
                                    VStack(alignment: .leading, spacing: 4) {
                                        Text(conversation.title.nonEmptyTrimmed ?? "新的对话")
                                            .font(.body.weight(.medium))
                                            .foregroundStyle(AppTheme.primaryText)
                                        if let summary = conversation.summary.nonEmptyTrimmed {
                                            Text(summary)
                                                .font(.caption)
                                                .foregroundStyle(AppTheme.secondaryText)
                                                .lineLimit(2)
                                        }
                                    }
                                }
                                .buttonStyle(.plain)
                            }
                        }
                    }

                    if !artifactResults.isEmpty {
                        Section("成品") {
                            ForEach(artifactResults) { item in
                                Button {
                                    openArtifact(item)
                                } label: {
                                    CampusAIArtifactLibraryRow(item: item)
                                }
                                .buttonStyle(.plain)
                            }
                        }
                    }
                }
                .listStyle(.plain)
            }
        }
        .navigationTitle("搜索")
        .navigationBarTitleDisplayMode(.inline)
        .searchable(text: $query, placement: .navigationBarDrawer(displayMode: .always), prompt: "搜索对话与成品")
    }
}

private struct CampusAIArtifactLibraryRow: View {
    let item: CampusAIArtifactLibraryItem

    var body: some View {
        HStack(alignment: .top, spacing: 14) {
            Image(systemName: "doc.richtext")
                .font(.system(size: 17, weight: .semibold))
                .foregroundStyle(AppTheme.accent)
                .frame(width: 36, height: 36)
                .background(AppTheme.accent.opacity(0.10), in: RoundedRectangle(cornerRadius: 10))

            VStack(alignment: .leading, spacing: 5) {
                Text(item.deliverable.title)
                    .font(.body.weight(.semibold))
                    .foregroundStyle(AppTheme.primaryText)
                    .lineLimit(1)
                Text(item.deliverable.summary)
                    .font(.subheadline)
                    .foregroundStyle(AppTheme.secondaryText)
                    .lineLimit(2)
                Text("\(item.conversationTitle) · \(item.generatedAt.formatted(date: .abbreviated, time: .omitted))")
                    .font(.caption)
                    .foregroundStyle(AppTheme.tertiaryText)
                    .lineLimit(1)
            }

            Spacer(minLength: 6)
        }
        .padding(.vertical, 6)
        .contentShape(Rectangle())
    }
}

private extension String {
    var nonEmptyTrimmed: String? {
        let trimmed = trimmingCharacters(in: .whitespacesAndNewlines)
        return trimmed.isEmpty ? nil : trimmed
    }
}
