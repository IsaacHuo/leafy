import Foundation
import PhotosUI
import Photos
import SafariServices
import SwiftData
import SwiftUI
#if canImport(UIKit)
import UIKit
#elseif canImport(AppKit)
import AppKit
import UniformTypeIdentifiers
#endif

struct ProfileView: View {
    @Environment(\.modelContext) private var modelContext
    @Environment(\.openURL) private var openURL
    @Environment(\.leafyControlScale) private var leafyControlScale
    @Environment(\.leafyLanguage) private var leafyLanguage
    @EnvironmentObject private var appNavigation: AppNavigationCoordinator
    @AppStorage(AppThemeColorPreference.storageKey) private var appThemeColorPreferenceRaw = AppThemeColorPreference.green.rawValue
    @AppStorage(AppThemeColorPreference.customColorHexKey) private var appThemeCustomColorHex = AppThemeColorPreference.defaultCustomColorHex
    @AppStorage(AppAppearancePreference.storageKey) private var appAppearancePreferenceRaw = AppAppearancePreference.light.rawValue
    @AppStorage("timetableHidesWeekends") private var timetableHidesWeekends = false
    @AppStorage(TimetableBackgroundStore.isEnabledKey) private var timetableBackgroundIsEnabled = false
    @AppStorage(TimetableBackgroundStore.filenameKey) private var timetableBackgroundFilename = ""

    @ObservedObject private var sessionManager = CommunitySessionManager.shared
    @State private var showingLogoutAlert = false
    @State private var showingFeedbackSheet = false
    @State private var feedbackInitialIssueType = "问题反馈"
    @State private var feedbackInitialBody = ""
    @State private var isCheckingForUpdate = false
    @State private var isOpeningReviewPage = false
    @State private var updateCheckMessage: String?
    @State private var reviewPageMessage: String?
    @State private var navigationPath = NavigationPath()
    @State private var pendingTimetableInviteCode: String?
    @State private var browserItem: ProfileBrowserItem?

    private let profileRowIconSize: CGFloat = 34

    private var themeColorPreference: AppThemeColorPreference {
        AppThemeColorPreference.storedValue(appThemeColorPreferenceRaw)
    }

    private var isCommunityEnabled: Bool {
        ActiveCampusContext.descriptor.supports(.community)
    }

    private var isCustomCampus: Bool {
        ActiveCampusContext.identity?.isCustom == true
    }

    private var profileDisplayName: String {
        if !isCommunityEnabled {
            let displayName = ActiveCampusContext.identity?.displayName?
                .trimmingCharacters(in: .whitespacesAndNewlines) ?? ""
            return displayName.isEmpty ? L10n.text("自定义账号", language: leafyLanguage) : displayName
        }
        return sessionManager.profile?.limitedResolvedDisplayName ?? L10n.text("社区资料", language: leafyLanguage)
    }

    var body: some View {
        NavigationStack(path: $navigationPath) {
            profileSettingsList
            .background(LeafyPageBackground())
            .tint(themeColorPreference.swatchColor)
            .navigationDestination(for: ProfileRoute.self) { route in
                switch route {
                case .timetableSharing:
                    if isCommunityEnabled {
                        TimetableSharingView(initialInviteCode: pendingTimetableInviteCode)
                    } else {
                        ContentUnavailableView("当前入口暂不支持共享课表", systemImage: "person.2.slash")
                    }
                case .cacheSync:
                    CacheAndSyncView()
                case .timetableBackground:
                    TimetableBackgroundSettingsView()
                }
            }
            .onChange(of: appNavigation.requestedProfileRoute) { _, route in
                handleProfileRouteRequest(route)
            }
            .sheet(isPresented: $showingFeedbackSheet) {
                FeedbackSheetView(
                    initialIssueType: feedbackInitialIssueType,
                    initialBody: feedbackInitialBody
                )
                    .presentationDetents([.medium, .large])
            }
            .sheet(item: $browserItem) { item in
                ProfileSafariView(url: item.url)
            }
            .alert("确认退出？", isPresented: $showingLogoutAlert) {
                Button("退出", role: .destructive) {
                    AppSessionResetter.returnToLogin(modelContext: modelContext)
                }
                Button("取消", role: .cancel) {}
            } message: {
                Text("退出后需重新登录，本地缓存的课表和成绩数据将保留。")
            }
            .alert("检查更新", isPresented: Binding(
                get: { updateCheckMessage != nil },
                set: { if !$0 { updateCheckMessage = nil } }
            )) {
                Button("好", role: .cancel) {}
            } message: {
                Text(updateCheckMessage ?? "")
            }
            .alert("给 \(AppBrand.displayName) 评分", isPresented: Binding(
                get: { reviewPageMessage != nil },
                set: { if !$0 { reviewPageMessage = nil } }
            )) {
                Button("好", role: .cancel) {}
            } message: {
                Text(reviewPageMessage ?? "")
            }
            .task {
                if isCommunityEnabled {
                    sessionManager.startBootstrapIfNeeded()
                } else {
                    sessionManager.cancelInFlightWork()
                }
            }
            .onAppear {
                handleProfileRouteRequest(appNavigation.requestedProfileRoute)
            }
        }
    }

    private var profileSettingsList: some View {
        List {
            Section {
                profileHeaderRow
            } header: {
                Text("资料")
            }
            .listRowBackground(AppTheme.cardBackground)

            Section {
                settingsRows
            } header: {
                Text("功能")
            }

            Section("支持") {
                supportRows
            }
            .listRowBackground(AppTheme.cardBackground)

            Section {
                logoutButton
            }
            .listRowBackground(AppTheme.cardBackground)
        }
        .leafyInsetGroupedListStyle()
        .scrollContentBackground(.hidden)
        .safeAreaPadding(.bottom, AppSpacing.compact)
        .frame(maxWidth: 760, alignment: .top)
        .frame(maxWidth: .infinity, alignment: .top)
    }

    @ViewBuilder
    private var settingsRows: some View {
        NavigationLink {
            CacheAndSyncView()
        } label: {
            profileRow(
                icon: "arrow.triangle.2.circlepath",
                title: "重新同步",
                detail: isCustomCampus ? "检查本地数据状态" : "重新同步教务数据"
            )
        }

        if isCommunityEnabled {
            NavigationLink {
                TimetableSharingView()
            } label: {
                profileRow(icon: "person.2.fill", title: "共享课表", detail: "邀请同学查看")
            }
        }

        NavigationLink {
            PersonalizationSettingsView()
        } label: {
            profileRow(icon: "paintpalette.fill", title: "个性化", detail: personalizationDetail)
        }

        NavigationLink {
            TimetableBackgroundSettingsView()
        } label: {
            profileRow(icon: "photo.on.rectangle.angled", title: "课表底图", detail: timetableBackgroundDetail)
        }

        if !isCustomCampus {
            NavigationLink {
                CampusLinksView()
            } label: {
                profileRow(icon: "link", title: "常用链接", detail: "教务系统等网站")
            }
        }

        Toggle(isOn: $timetableHidesWeekends) {
            HStack(spacing: 12) {
                LeafyCompactProfileIconBadge(systemName: "calendar.badge.minus", size: profileRowIconSize)

                VStack(alignment: .leading, spacing: 2) {
                    Text("隐藏周末")
                        .leafyBody()
                        .foregroundStyle(AppTheme.primaryText)
                    Text("课表页仅显示周一至周五")
                        .microCaption()
                        .foregroundStyle(AppTheme.tertiaryText)
                }
            }
        }
        .tint(AppTheme.accent)
    }

    @ViewBuilder
    private var supportRows: some View {
        NavigationLink {
            LeafyGuideAndDataSecurityView()
        } label: {
            profileRow(icon: "book.closed.fill", title: "说明与安全", detail: "使用手册")
        }

        if isCommunityEnabled, !isCustomCampus, ActiveCampusContext.descriptor.id == .bjfu {
            NavigationLink {
                ProfileEmailBindingView()
            } label: {
                profileRow(icon: "envelope.badge.fill", title: "绑定邮箱", detail: "接收服务通知")
            }
        }

        Button {
            feedbackInitialIssueType = "问题反馈"
            feedbackInitialBody = ""
            showingFeedbackSheet = true
        } label: {
            profileRow(icon: "bubble.left.and.bubble.right.fill", title: "举报与反馈", detail: "建议和问题反馈")
        }

        Button {
            Task { await openReviewPage() }
        } label: {
            profileRow(
                icon: "star.bubble.fill",
                title: "给 \(AppBrand.displayName) 评分",
                detail: isOpeningReviewPage ? "打开中" : "前往 App Store"
            )
        }
        .disabled(isOpeningReviewPage)

        Button {
            Task { await checkForUpdate() }
        } label: {
            profileRow(
                icon: "arrow.down.circle.fill",
                title: "检查更新",
                detail: isCheckingForUpdate ? "检查中" : "跳转到 App Store"
            )
        }
        .disabled(isCheckingForUpdate)

        Button {
            browserItem = ProfileBrowserItem(url: LeafyExternalLinks.authorBlog)
        } label: {
            profileRow(icon: "safari.fill", title: "项目介绍", detail: "此项目的开源页面")
        }
    }

    private var logoutButton: some View {
        Button {
            showingLogoutAlert = true
        } label: {
            Text("退出登录")
                .leafyTitle3()
                .foregroundStyle(AppTheme.danger)
                .frame(maxWidth: .infinity, alignment: .center)
        }
    }

    private func handleProfileRouteRequest(_ route: ProfileRoute?) {
        guard let route else { return }
        if route == .timetableSharing, !isCommunityEnabled {
            appNavigation.requestedProfileRoute = nil
            appNavigation.requestedTimetableInviteCode = nil
            return
        }
        if route == .timetableSharing {
            pendingTimetableInviteCode = appNavigation.requestedTimetableInviteCode
            appNavigation.requestedTimetableInviteCode = nil
        }
        navigationPath.append(route)
        appNavigation.requestedProfileRoute = nil
    }

    private var personalizationDetail: String {
        let themeTitle = themeColorPreference.title(language: leafyLanguage)
        let appearanceTitle = AppAppearancePreference.storedValue(appAppearancePreferenceRaw).title(language: leafyLanguage)
        return "\(themeTitle) · \(appearanceTitle)"
    }

    private var timetableBackgroundDetail: String {
        guard !timetableBackgroundFilename.isEmpty else { return L10n.text("未设置", language: leafyLanguage) }
        return timetableBackgroundIsEnabled ? L10n.text("已开启", language: leafyLanguage) : L10n.text("已暂停", language: leafyLanguage)
    }

    private var profileSubtitle: String {
        profileSubtitleLines.joined(separator: "\n")
    }

    private var profileSubtitleLines: [String] {
        guard isCommunityEnabled else {
            return [L10n.text("当前入口账号。学校相关数据保存在本机。", language: leafyLanguage)]
        }

        if let bootstrapError = sessionManager.bootstrapError, sessionManager.profile == nil {
            return [bootstrapError]
        }

        guard let profile = sessionManager.profile else {
            return [L10n.text("社区资料会和教务学号绑定，首次发帖或点赞前需要先完善昵称。头像、学院和年级可选。", language: leafyLanguage)]
        }

        if sessionManager.requiresProfileCompletion {
            return [L10n.text("学号 %@ 已绑定，请先补全昵称。头像、学院和年级可选，未设置头像会使用默认头像。", language: leafyLanguage, profile.eduID)]
        }

        let parts = [profile.grade, profile.major]
            .compactMap { $0?.trimmingCharacters(in: .whitespacesAndNewlines) }
            .filter { !$0.isEmpty }
        let firstLine = parts.isEmpty
            ? L10n.text("已与教务绑定", language: leafyLanguage)
            : parts.joined(separator: " · ")
        return [
            firstLine,
            L10n.text("学号 %@", language: leafyLanguage, profile.eduID)
        ]
    }

    @ViewBuilder
    private var profileHeaderRow: some View {
        if isCommunityEnabled {
            NavigationLink {
                CommunityUserProfileView(
                    profileID: sessionManager.currentUserID,
                    initialProfile: sessionManager.profile,
                    allowsEditing: true
                )
            } label: {
                HStack(spacing: 16) {
                    CommunityAvatarView(profile: sessionManager.profile, size: 80 * leafyControlScale)
                    profileHeaderText
                    Spacer()
                }
                .padding(.vertical, 6 * leafyControlScale)
            }
            .buttonStyle(.plain)
        } else {
            HStack(spacing: 16) {
                ZStack {
                    Circle()
                        .fill(AppTheme.softFill)
                    Image(systemName: "person.crop.circle.fill")
                        .font(.system(size: 48 * leafyControlScale, weight: .semibold))
                        .foregroundStyle(AppTheme.accent)
                }
                .frame(width: 80 * leafyControlScale, height: 80 * leafyControlScale)

                profileHeaderText
                Spacer()
            }
            .padding(.vertical, 6 * leafyControlScale)
        }
    }

    private var profileHeaderText: some View {
        VStack(alignment: .leading, spacing: 6) {
            Text(profileDisplayName)
                .title2()
                .foregroundStyle(AppTheme.primaryText)

            VStack(alignment: .leading, spacing: 1) {
                ForEach(Array(profileSubtitleLines.enumerated()), id: \.offset) { _, line in
                    Text(line)
                        .leafyBody()
                        .foregroundStyle(AppTheme.secondaryText)
                        .lineLimit(1)
                }
            }
        }
    }

    @ViewBuilder
    private func profileRow(icon: String, title: String, detail: String, tint: Color = AppTheme.accent) -> some View {
        HStack(alignment: .center, spacing: 11) {
            LeafyCompactProfileIconBadge(systemName: icon, tint: tint, size: profileRowIconSize)

            VStack(alignment: .leading, spacing: 1) {
                Text(L10n.text(title, language: leafyLanguage))
                    .leafyBody()
                    .foregroundStyle(AppTheme.primaryText)
                    .lineLimit(1)
                    .minimumScaleFactor(0.82)

                Text(L10n.text(detail, language: leafyLanguage))
                    .microCaption()
                    .foregroundStyle(AppTheme.secondaryText)
                    .lineLimit(2)
                    .minimumScaleFactor(0.78)
            }
            .frame(maxWidth: .infinity, alignment: .leading)
        }
        .padding(.vertical, 1)
    }

    @MainActor
    private func checkForUpdate() async {
        guard !isCheckingForUpdate else { return }
        guard let bundleIdentifier = Bundle.main.bundleIdentifier, !bundleIdentifier.isEmpty else {
            updateCheckMessage = L10n.text("暂未找到 App Store 页面，请稍后再试。", language: leafyLanguage)
            return
        }

        isCheckingForUpdate = true
        defer { isCheckingForUpdate = false }

        do {
            guard let appStoreURL = try await AppStoreUpdateLookup.appStoreURL(bundleIdentifier: bundleIdentifier) else {
                updateCheckMessage = L10n.text("暂未找到 App Store 页面，请稍后再试。", language: leafyLanguage)
                return
            }

            openURL(appStoreURL)
        } catch {
            updateCheckMessage = L10n.text("暂未找到 App Store 页面，请稍后再试。", language: leafyLanguage)
        }
    }

    @MainActor
    private func openReviewPage() async {
        guard !isOpeningReviewPage else { return }
        guard let bundleIdentifier = Bundle.main.bundleIdentifier, !bundleIdentifier.isEmpty else {
            reviewPageMessage = L10n.text("暂未找到 App Store 评分页面，请稍后再试。", language: leafyLanguage)
            return
        }

        isOpeningReviewPage = true
        defer { isOpeningReviewPage = false }

        do {
            guard let appStoreURL = try await AppStoreUpdateLookup.appStoreURL(bundleIdentifier: bundleIdentifier) else {
                reviewPageMessage = L10n.text("暂未找到 App Store 评分页面，请稍后再试。", language: leafyLanguage)
                return
            }

            openURL(AppStoreUpdateLookup.reviewURL(from: appStoreURL))
        } catch {
            reviewPageMessage = L10n.text("暂未找到 App Store 评分页面，请稍后再试。", language: leafyLanguage)
        }
    }
}

#if canImport(UIKit)
private struct ProfileSafariView: UIViewControllerRepresentable {
    let url: URL

    func makeUIViewController(context: Context) -> SFSafariViewController {
        SFSafariViewController(url: url)
    }

    func updateUIViewController(_ uiViewController: SFSafariViewController, context: Context) {}
}
#else
private typealias ProfileSafariView = LeafyExternalBrowserView
#endif

private struct ProfileBrowserItem: Identifiable {
    let id = UUID()
    let url: URL
}

private struct ThemeColorSwatch: View {
    let option: AppThemeColorPreference
    let size: CGFloat

    var body: some View {
        Circle()
            .fill(option.swatchColor)
            .frame(width: size, height: size)
            .overlay(
                Circle()
                    .stroke(AppTheme.separator, lineWidth: 1)
            )
    }
}

private struct LeafyCompactProfileIconBadge: View {
    let systemName: String
    var tint: Color = AppTheme.accent
    let size: CGFloat

    var body: some View {
        ZStack {
            Circle()
                .fill(tint.opacity(0.72))

            Image(systemName: systemName)
                .font(.system(size: size * 0.42, weight: .semibold))
                .foregroundStyle(.white)
                .symbolRenderingMode(.hierarchical)
        }
        .frame(width: size, height: size)
    }
}

private struct IconAppearanceSwatch: View {
    let option: LeafyAppIconAppearancePreference
    let size: CGFloat

    var body: some View {
        RoundedRectangle(cornerRadius: size * 0.22, style: .continuous)
            .fill(
                LinearGradient(
                    colors: [
                        baseColor.opacity(0.38),
                        baseColor
                    ],
                    startPoint: .topLeading,
                    endPoint: .bottomTrailing
                )
            )
            .frame(width: size, height: size)
            .overlay(alignment: .center) {
                Image(systemName: "leaf.fill")
                    .font(.system(size: size * 0.52, weight: .semibold))
                    .foregroundStyle(.white.opacity(0.94))
                    .rotationEffect(.degrees(-16))
            }
            .overlay(
                RoundedRectangle(cornerRadius: size * 0.22, style: .continuous)
                    .stroke(AppTheme.separator, lineWidth: 1)
            )
    }

    private var baseColor: Color {
        switch option {
        case .green:
            return AppTheme.accent(for: .green)
        case .tiffanyBlue:
            return AppTheme.accent(for: .tiffanyBlue)
        case .candyPink:
            return AppTheme.accent(for: .candyPink)
        }
    }
}

private struct PersonalizationSettingsView: View {
    @Environment(\.leafyLanguage) private var leafyLanguage
    @AppStorage(AppThemeColorPreference.storageKey) private var appThemeColorPreferenceRaw = AppThemeColorPreference.green.rawValue
    @AppStorage(AppThemeColorPreference.customColorHexKey) private var appThemeCustomColorHex = AppThemeColorPreference.defaultCustomColorHex
    @AppStorage(LeafyAppIconAppearancePreference.storageKey) private var appIconAppearancePreferenceRaw = LeafyAppIconAppearancePreference.green.rawValue
    @AppStorage("appFontSizePreference") private var appDisplaySizePreferenceRaw = AppDisplaySizePreference.standard.rawValue
    @AppStorage(AppAppearancePreference.storageKey) private var appAppearancePreferenceRaw = AppAppearancePreference.light.rawValue
    @State private var showingCustomThemeColorPicker = false

    private var themeColorPreference: AppThemeColorPreference {
        AppThemeColorPreference.storedValue(appThemeColorPreferenceRaw)
    }

    private var iconAppearancePreference: LeafyAppIconAppearancePreference {
        LeafyAppIconAppearancePreference.storedValue(appIconAppearancePreferenceRaw)
    }

    private var displaySizePreference: AppDisplaySizePreference {
        AppDisplaySizePreference(rawValue: appDisplaySizePreferenceRaw) ?? .standard
    }

    private var appearancePreference: AppAppearancePreference {
        AppAppearancePreference.storedValue(appAppearancePreferenceRaw)
    }

    var body: some View {
        List {
            Section {
                ForEach(AppThemeColorPreference.allCases) { option in
                    Button {
                        selectThemeColor(option)
                    } label: {
                        selectionRow(
                            title: option.title(language: leafyLanguage),
                            isSelected: option == themeColorPreference
                        ) {
                            ThemeColorSwatch(option: option, size: 28)
                        }
                    }
                    .buttonStyle(.plain)
                }
            } header: {
                Text("主题色")
            } footer: {
                Text("主题色会用于 App 强调色、课程卡片和小组件外观。")
            }
            .listRowBackground(AppTheme.cardBackground)

            Section {
                ForEach(AppDisplaySizePreference.allCases) { option in
                    Button {
                        appDisplaySizePreferenceRaw = option.rawValue
                    } label: {
                        selectionRow(
                            title: option.title(language: leafyLanguage),
                            isSelected: option == displaySizePreference
                        ) {
                            FontSizeSwatch(option: option)
                        }
                    }
                    .buttonStyle(.plain)
                }
            } header: {
                Text("字号")
            } footer: {
                Text("字号会影响全局文本、课表卡片和常用控件尺寸。")
            }
            .listRowBackground(AppTheme.cardBackground)

            Section {
                ForEach(LeafyAppIconAppearancePreference.allCases) { option in
                    Button {
                        appIconAppearancePreferenceRaw = option.rawValue
                    } label: {
                        selectionRow(
                            title: option.title(language: leafyLanguage),
                            isSelected: option == iconAppearancePreference
                        ) {
                            IconAppearanceSwatch(option: option, size: 30)
                        }
                    }
                    .buttonStyle(.plain)
                }
            } header: {
                Text("App 外观")
            }
            .listRowBackground(AppTheme.cardBackground)

            Section {
                ForEach(AppAppearancePreference.allCases) { option in
                    Button {
                        withAnimation(.easeInOut(duration: 0.55)) {
                            appAppearancePreferenceRaw = option.rawValue
                        }
                    } label: {
                        selectionRow(
                            title: option.title(language: leafyLanguage),
                            detail: option.detail(language: leafyLanguage),
                            isSelected: option == appearancePreference
                        ) {
                            LeafyIconBadge(systemName: option.systemImage)
                        }
                    }
                    .buttonStyle(.plain)
                }
            } header: {
                Text("外观")
            } footer: {
                Text("默认使用浅色外观，也可以跟随系统或固定深色。")
            }
            .listRowBackground(AppTheme.cardBackground)
        }
        .leafyInsetGroupedListStyle()
        .scrollContentBackground(.hidden)
        .background(LeafyPageBackground())
        .navigationTitle("个性化")
        .leafyInlineNavigationTitle()
        .sheet(isPresented: $showingCustomThemeColorPicker) {
            CustomThemeColorPickerSheet(color: customThemeColorBinding)
                .presentationDetents([.medium])
        }
    }

    private var customThemeColorBinding: Binding<Color> {
        Binding(
            get: { AppThemeColorPreference.color(fromHex: appThemeCustomColorHex) },
            set: { newValue in
                appThemeCustomColorHex = AppThemeColorPreference.hexString(from: newValue)
                appThemeColorPreferenceRaw = AppThemeColorPreference.custom.rawValue
            }
        )
    }

    private func selectThemeColor(_ option: AppThemeColorPreference) {
        appThemeColorPreferenceRaw = option.rawValue
        if option == .custom {
            showingCustomThemeColorPicker = true
        }
    }

    private func selectionRow<Accessory: View>(
        title: String,
        detail: String? = nil,
        isSelected: Bool,
        @ViewBuilder accessory: () -> Accessory
    ) -> some View {
        HStack(spacing: 12) {
            accessory()

            VStack(alignment: .leading, spacing: 2) {
                Text(title)
                    .leafyBody()
                    .foregroundStyle(AppTheme.primaryText)

                if let detail {
                    Text(detail)
                        .microCaption()
                        .foregroundStyle(AppTheme.tertiaryText)
                }
            }

            Spacer()

            Image(systemName: isSelected ? "checkmark.circle.fill" : "circle")
                .font(.system(size: 18, weight: .semibold))
                .foregroundStyle(isSelected ? AppTheme.accent : AppTheme.tertiaryText)
        }
        .contentShape(Rectangle())
    }
}

private struct FontSizeSwatch: View {
    let option: AppDisplaySizePreference

    var body: some View {
        ZStack {
            Circle()
                .fill(AppTheme.softFill)
                .frame(width: 30, height: 30)

            Text("A")
                .font(.system(size: glyphSize, weight: .bold))
                .foregroundStyle(AppTheme.accentEmphasis)
        }
    }

    private var glyphSize: CGFloat {
        switch option {
        case .compact:
            return 12
        case .standard:
            return 14
        case .comfortable:
            return 16
        case .spacious:
            return 18
        }
    }
}

private struct CustomThemeColorPickerSheet: View {
    @Environment(\.dismiss) private var dismiss

    @Binding var color: Color

    var body: some View {
        NavigationStack {
            Form {
                Section {
                    ColorPicker("自定义主题色", selection: $color, supportsOpacity: false)

                    HStack(spacing: 12) {
                        Circle()
                            .fill(color)
                            .frame(width: 36, height: 36)
                            .overlay(
                                Circle()
                                    .stroke(AppTheme.separator, lineWidth: 1)
                            )

                        VStack(alignment: .leading, spacing: 2) {
                            Text("当前颜色")
                                .leafyBody()
                            Text(AppThemeColorPreference.hexString(from: color))
                                .microCaption()
                                .foregroundStyle(AppTheme.secondaryText)
                        }
                    }
                } footer: {
                    Text("自定义主题色会用于按钮、课程卡片和页面强调色。")
                }
            }
            .navigationTitle("自定义主题色")
            .leafyInlineNavigationTitle()
            .toolbar {
                ToolbarItem(placement: .confirmationAction) {
                    Button("完成") {
                        dismiss()
                    }
                }
            }
        }
    }
}

private struct FeedbackSheetView: View {
    @Environment(\.dismiss) private var dismiss
    @Environment(\.leafyLanguage) private var leafyLanguage
    @Environment(\.leafyDependencies) private var dependencies
    @State private var isSubmitting = false
    @State private var operationAlert: LeafyOperationAlert?
    @State private var issueType: String
    @State private var feedbackBody: String
    @State private var contact = ""
    @State private var showingContactSheet = false

    private var isCommunityEnabled: Bool {
        ActiveCampusContext.descriptor.supports(.community)
    }

    private var issueTypes: [String] {
        var items = ["问题反馈", "功能建议", "数据异常", "界面体验"]
        if isCommunityEnabled {
            items.append("社区安全")
        }
        return items
    }

    init(initialIssueType: String = "问题反馈", initialBody: String = "") {
        _issueType = State(initialValue: initialIssueType)
        _feedbackBody = State(initialValue: initialBody)
    }

    var body: some View {
        NavigationStack {
            ScrollView {
                VStack(spacing: AppSpacing.card) {
                    VStack(alignment: .leading, spacing: 14) {
                        Text("举报与反馈内容")
                            .leafyHeadline()

                        Picker("类型", selection: $issueType) {
                            ForEach(issueTypes, id: \.self) { type in
                                Text(L10n.text(type, language: leafyLanguage)).tag(type)
                            }
                        }
                        .pickerStyle(.segmented)

                        TextField("请描述你遇到的问题、建议或不当活动", text: $feedbackBody, axis: .vertical)
                            .lineLimit(5, reservesSpace: true)
                            .padding(14)
                            .background(AppTheme.fill, in: RoundedRectangle(cornerRadius: AppRadius.medium, style: .continuous))

                        TextField("联系方式（可选）", text: $contact)
                            .leafyDisableAutocapitalization()
                            .padding(14)
                            .background(AppTheme.fill, in: RoundedRectangle(cornerRadius: AppRadius.medium, style: .continuous))

                        Text(isCommunityEnabled
                            ? "社区安全或不当活动也可邮件联系：\(CommunityTerms.supportEmail)"
                            : "当前入口的问题和建议也可以通过这里反馈。")
                            .microCaption()
                            .foregroundStyle(AppTheme.secondaryText)
                    }
                    .padding(18)
                    .leafyCardStyle()

                    Button {
                        showingContactSheet = true
                    } label: {
                        HStack(spacing: 11) {
                            LeafyCompactProfileIconBadge(systemName: "person.2.wave.2.fill", size: 34)

                            VStack(alignment: .leading, spacing: 1) {
                                Text("联系我们")
                                    .leafyBody()
                                    .foregroundStyle(AppTheme.primaryText)
                                Text("QQ群反馈群")
                                    .microCaption()
                                    .foregroundStyle(AppTheme.tertiaryText)
                            }

                            Spacer()

                            Image(systemName: "chevron.right")
                                .font(.footnote.weight(.semibold))
                                .foregroundStyle(AppTheme.tertiaryText)
                        }
                        .padding(18)
                        .leafyCardStyle()
                    }
                    .buttonStyle(.plain)
                }
                .padding(AppSpacing.page)
            }
            .background(LeafyPageBackground())
            .navigationTitle("举报与反馈")
            .leafyInlineNavigationTitle()
            .toolbar {
                ToolbarItem(placement: .leafyLeading) {
                    Button("关闭") {
                        dismiss()
                    }
                }

                ToolbarItem(placement: .leafyTrailing) {
                    Button(isSubmitting ? "提交中" : "提交") {
                        Task { await submit() }
                    }
                    .disabled(isSubmitting || feedbackBody.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty)
                }
            }
            .leafyOperationAlert($operationAlert)
            .sheet(isPresented: $showingContactSheet) {
                ContactUsSheetView()
                    .presentationDetents([.medium, .large])
            }
        }
    }

    @MainActor
    private func submit() async {
        let trimmedBody = feedbackBody.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmedBody.isEmpty else {
            operationAlert = .failure(L10n.text("请先填写反馈内容。", language: leafyLanguage))
            return
        }

        isSubmitting = true
        defer { isSubmitting = false }

        do {
            try await dependencies.communityActivityRepository.submitFeedback(
                issueType: issueType,
                body: trimmedBody,
                contact: contact,
                deviceInfo: feedbackDeviceInfo()
            )
            feedbackBody = ""
            contact = ""
            operationAlert = .success(
                L10n.text("反馈已提交！", language: leafyLanguage),
                action: { dismiss() }
            )
        } catch {
            operationAlert = .failure(error.localizedDescription)
        }
    }

    private func feedbackDeviceInfo() -> [String: String] {
        let appVersion = Bundle.main.infoDictionary?["CFBundleShortVersionString"] as? String ?? L10n.text("未知", language: leafyLanguage)
        let build = Bundle.main.infoDictionary?["CFBundleVersion"] as? String ?? L10n.text("未知", language: leafyLanguage)
        let isCustomCampus = ActiveCampusContext.identity?.isCustom == true
        let loggedIn = isCustomCampus
            ? L10n.text("本地学校账号", language: leafyLanguage)
            : (ActiveCampusContext.networkManager.isLoggedIn ? L10n.text("BJFU 教务已登录", language: leafyLanguage) : L10n.text("BJFU 教务未登录", language: leafyLanguage))
        let lastSync = TimetableCacheMetadata.lastSyncAt.map { DateFormatters.headerWithTime.string(from: $0) } ?? L10n.text("无", language: leafyLanguage)
        return [
            "device": LeafyDeviceInfo.model,
            "system": LeafyDeviceInfo.systemDescription,
            "app": "\(appVersion) (\(build))",
            "loginStatus": loggedIn,
            "lastTimetableSync": lastSync
        ]
    }
}

private struct CommunityTermsPreferenceSheet: View {
    @Environment(\.dismiss) private var dismiss
    @Environment(\.leafyLanguage) private var leafyLanguage
    @Environment(\.leafyDependencies) private var dependencies
    @State private var isAccepted = false
    @State private var originalAccepted: Bool?
    @State private var isLoading = true
    @State private var isSaving = false
    @State private var errorMessage: String?
    @State private var operationAlert: LeafyOperationAlert?

    private var hasChanges: Bool {
        guard let originalAccepted else { return false }
        return originalAccepted != isAccepted
    }

    var body: some View {
        NavigationStack {
            ScrollView {
                VStack(alignment: .leading, spacing: AppSpacing.card) {
                    VStack(alignment: .leading, spacing: 14) {
                        Text("\(AppBrand.displayName) 社区条约")
                            .title2()
                            .foregroundStyle(AppTheme.primaryText)

                        Text("你可以在这里查看社区规则，并重新选择是否同意。不同意后将不能进入社区、发帖或评论。")
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

                    VStack(alignment: .leading, spacing: 12) {
                        if isLoading {
                            ProgressView()
                                .frame(maxWidth: .infinity)
                                .padding(.vertical, 8)
                        } else {
                            Toggle(isOn: $isAccepted) {
                                VStack(alignment: .leading, spacing: 4) {
                                    Text("我同意社区条约")
                                        .leafyBody()
                                        .foregroundStyle(AppTheme.primaryText)
                                    Text(isAccepted ? "同意后可继续使用社区功能。" : "不同意时社区内容和互动会被条款门禁拦截。")
                                        .microCaption()
                                        .foregroundStyle(AppTheme.secondaryText)
                                }
                            }
                            .tint(AppTheme.accent)
                        }
                    }
                    .padding(18)
                    .leafyCardStyle()

                    if let errorMessage {
                        Text(errorMessage)
                            .microCaption()
                            .foregroundStyle(AppTheme.danger)
                            .padding(14)
                            .frame(maxWidth: .infinity, alignment: .leading)
                            .background(AppTheme.cardBackground, in: RoundedRectangle(cornerRadius: AppRadius.medium, style: .continuous))
                    }
                }
                .padding(AppSpacing.page)
            }
            .background(LeafyPageBackground())
            .navigationTitle("社区条约")
            .leafyInlineNavigationTitle()
            .toolbar {
                ToolbarItem(placement: .leafyLeading) {
                    Button("关闭") {
                        dismiss()
                    }
                }

                ToolbarItem(placement: .leafyTrailing) {
                    Button(isSaving ? "保存中" : "保存") {
                        Task { await save() }
                    }
                    .disabled(isLoading || isSaving || !hasChanges)
                }
            }
            .task {
                await loadCurrentChoice()
            }
            .leafyOperationAlert($operationAlert)
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
    private func loadCurrentChoice() async {
        isLoading = true
        errorMessage = nil
        defer { isLoading = false }

        do {
            let accepted = try await dependencies.communityActivityRepository.hasAcceptedCurrentTerms()
            isAccepted = accepted
            originalAccepted = accepted
        } catch {
            errorMessage = error.localizedDescription
            originalAccepted = false
            isAccepted = false
        }
    }

    @MainActor
    private func save() async {
        guard hasChanges else { return }
        isSaving = true
        errorMessage = nil
        defer { isSaving = false }

        do {
            if isAccepted {
                try await dependencies.communityActivityRepository.acceptCurrentTerms()
            } else {
                try await dependencies.communityActivityRepository.revokeCurrentTerms()
            }
            originalAccepted = isAccepted
            operationAlert = .success(L10n.text("设置已保存！", language: leafyLanguage))
        } catch {
            errorMessage = error.localizedDescription
        }
    }
}

private struct ContactUsSheetView: View {
    @Environment(\.dismiss) private var dismiss
    @Environment(\.leafyLanguage) private var leafyLanguage
    @State private var isSaving = false
    @State private var saveResultMessage: String?

    private var feedbackImage: UIImage? {
        FeedbackImageAsset.load()
    }

    var body: some View {
        NavigationStack {
            ScrollView {
                VStack(alignment: .leading, spacing: AppSpacing.card) {
                    VStack(alignment: .leading, spacing: 10) {
                        Text("社区安全与技术支持")
                            .leafyHeadline()
                            .foregroundStyle(AppTheme.primaryText)
                        Text("如需举报不当活动、违规内容或滥用用户，可以在“举报与反馈”中选择“社区安全”，也可以发送邮件到 \(CommunityTerms.supportEmail)。")
                            .leafyBody()
                            .foregroundStyle(AppTheme.secondaryText)
                    }
                    .padding(18)
                    .leafyCardStyle()

                    if let feedbackImage {
                        Image(uiImage: feedbackImage)
                            .resizable()
                            .scaledToFit()
                            .clipShape(RoundedRectangle(cornerRadius: AppRadius.medium, style: .continuous))
                            .overlay(
                                RoundedRectangle(cornerRadius: AppRadius.medium, style: .continuous)
                                    .stroke(AppTheme.separator, lineWidth: 1)
                            )
                    } else {
                        ContentUnavailableView(
                            "未找到反馈图片",
                            systemImage: "photo",
                            description: Text("请确认 feedback.JPG 已包含在 App 资源中。")
                        )
                    }
                }
                .padding(AppSpacing.page)
            }
            .background(LeafyPageBackground())
            .navigationTitle("联系我们")
            .leafyInlineNavigationTitle()
            .toolbar {
                ToolbarItem(placement: .leafyLeading) {
                    Button("关闭") {
                        dismiss()
                    }
                }
                ToolbarItem(placement: .leafyTrailing) {
                    Button {
                        if let feedbackImage {
                            Task { await save(image: feedbackImage) }
                        }
                    } label: {
                        Image(systemName: "square.and.arrow.down")
                            .offset(y: -1.5)
                    }
                    .disabled(isSaving || feedbackImage == nil)
                }
            }
            .alert("保存结果", isPresented: Binding(
                get: { saveResultMessage != nil },
                set: { if !$0 { saveResultMessage = nil } }
            )) {
                Button("好", role: .cancel) {}
            } message: {
                Text(saveResultMessage ?? "")
            }
        }
    }

    @MainActor
    private func save(image: UIImage) async {
        isSaving = true
        defer { isSaving = false }

        do {
            try await FeedbackImageSaver.save(image)
#if os(macOS)
            saveResultMessage = L10n.text("已保存到所选文件。", language: leafyLanguage)
#else
            saveResultMessage = L10n.text("已保存到系统相册。", language: leafyLanguage)
#endif
        } catch {
            saveResultMessage = error.localizedDescription
        }
    }
}

private enum FeedbackImageAsset {
    static func load() -> UIImage? {
        if let image = UIImage(named: "feedback") {
            return image
        }

        let url = Bundle.main.url(forResource: "feedback", withExtension: "JPG")
            ?? Bundle.main.url(forResource: "feedback", withExtension: "jpg")

        guard let url else { return nil }
        return UIImage(contentsOfFile: url.path)
    }
}

private enum FeedbackImageSaver {
    static func save(_ image: UIImage) async throws {
#if os(macOS)
        guard let data = image.jpegData(compressionQuality: 0.92) else {
            throw FeedbackImageSaveError.saveFailed
        }

        let panel = NSSavePanel()
        panel.allowedContentTypes = [.jpeg]
        panel.canCreateDirectories = true
        panel.nameFieldStringValue = "MyLeafy-feedback.jpg"

        guard panel.runModal() == .OK, let url = panel.url else {
            throw FeedbackImageSaveError.cancelled
        }
        try data.write(to: url, options: .atomic)
#else
        let status = PHPhotoLibrary.authorizationStatus(for: .addOnly)

        switch status {
        case .authorized, .limited:
            break
        case .notDetermined:
            let requestedStatus = await requestAuthorization()
            guard requestedStatus == .authorized || requestedStatus == .limited else {
                throw FeedbackImageSaveError.permissionDenied
            }
        default:
            throw FeedbackImageSaveError.permissionDenied
        }

        let _: Void = try await withCheckedThrowingContinuation { continuation in
            PHPhotoLibrary.shared().performChanges {
                PHAssetChangeRequest.creationRequestForAsset(from: image)
            } completionHandler: { success, error in
                if let error {
                    continuation.resume(throwing: error)
                } else if success {
                    continuation.resume(returning: ())
                } else {
                    continuation.resume(throwing: FeedbackImageSaveError.saveFailed)
                }
            }
        }
#endif
    }

#if !os(macOS)
    private static func requestAuthorization() async -> PHAuthorizationStatus {
        await withCheckedContinuation { continuation in
            PHPhotoLibrary.requestAuthorization(for: .addOnly) { status in
                continuation.resume(returning: status)
            }
        }
    }
#endif
}

private enum FeedbackImageSaveError: LocalizedError {
    case cancelled
    case permissionDenied
    case saveFailed

    var errorDescription: String? {
        switch self {
        case .cancelled:
            return L10n.text("已取消保存。")
        case .permissionDenied:
            return L10n.text("没有相册保存权限，请在系统设置中允许 %@ 添加照片。", AppBrand.displayName)
        case .saveFailed:
            return L10n.text("保存失败，请稍后重试。")
        }
    }
}


private struct LeafyGuideAndDataSecurityView: View {
    @State private var showingCommunityTermsSheet = false

    private var isCommunityEnabled: Bool {
        ActiveCampusContext.descriptor.supports(.community)
    }

    private let chapters = [
        ManualChapter(
            icon: "leaf.fill",
            title: "开始使用",
            detail: "定位、边界和入口",
            intro: "\(AppBrand.displayName) 当前面向北京林业大学的校园日常使用。它把课表、成绩、考试、培养方案、自习室、社区和反馈集中在一个入口里，适合每天快速查看和处理校园事务。",
            rows: [
                ManualInfo(title: "为什么会有 \(AppBrand.displayName)", body: "北林学生常用的课表、成绩、考试、自习室、校历、评教、社区和反馈入口分散在不同系统里。\(AppBrand.displayName) 的目标是把这些高频事务整理成一个安静、清楚、可离线兜底的学生端工具。"),
                ManualInfo(title: "它不替代什么", body: "\(AppBrand.displayName) 不是北京林业大学官方教务系统，也不会绕过学校的登录、验证码、校园网、VPN 或权限限制。涉及成绩、培养方案、考试安排等正式结果时，仍以学校系统为准。"),
                ManualInfo(title: "主要入口怎么用", body: "课表用于查看当天和当前周安排；Leafy AI 用于基于本机学业数据提问；社区用于同学交流、公告和反馈；校园收纳成绩、考试、教学培养、自习室、校历和评教；我的用于管理资料、同步、个性化、支持和安全设置。"),
                ManualInfo(title: "什么时候需要同步", body: "选课、调课、成绩发布、考试安排更新、培养方案或空教室查询结果变化后，可以连接能访问北林教务的网络重新同步。同步失败时，App 会优先保留最近一次成功缓存。")
            ],
            steps: [
                ManualStep(title: "先从课表确认日常安排", body: "打开课表页看当前周和今天的课程，确认是否需要刷新或调整显示设置。"),
                ManualStep(title: "再进入校园查看教务结果", body: "成绩、考试、培养方案、自习室、校历、评教、学习资料和体育记录都在校园里。"),
                ManualStep(title: "最后到我的处理账号和安全", body: "登录状态、同步缓存、共享课表、反馈、联系和本手册都在我的页面集中管理。")
            ]
        ),
        ManualChapter(
            icon: "wifi",
            title: "数据来源",
            detail: "教务同步与本地维护",
            intro: "北京林业大学教务数据来自学校强智教务系统。\(AppBrand.displayName) 代表你发起查询并解析结果，本机缓存用于离线查看和失败兜底。",
            rows: [
                ManualInfo(title: "为什么要连接校园网", body: "北林强智教务系统通常要求校园网、校内网络或学校认可的 VPN 环境。\(AppBrand.displayName) 不能突破学校系统的网络边界；如果浏览器也打不开教务系统，App 通常也无法同步。"),
                ManualInfo(title: "教务数据来自哪里", body: "课表、成绩、考试安排、教学计划、培养方案、空教室和教室占用来自北林教务页面。App 会按功能保存解析后的结果，用于展示、检索和离线查看。"),
                ManualInfo(title: "本机数据来自哪里", body: "课程备注、课表提醒、收藏、自定日程、学习资料、学习空间、任务、专注记录和体测记录，是你在当前设备上创建、导入或维护的数据。"),
                ManualInfo(title: "保持登录状态的用途", body: "学校登录态用于减少重复输入学号、密码和验证码；会话失效、换网或学校页面变化时，部分教务功能会要求重新认证。"),
                ManualInfo(title: "遇到问题先看什么", body: "同步失败先确认网络能访问北林教务，再看是否需要重新登录；如果只有某个页面长期异常，通常需要反馈页面名称、错误提示和发生时间。")
            ],
            steps: [
                ManualStep(title: "先确认网络", body: "连接 bjfu-wifi、校园网或学校 VPN，并确认浏览器可以访问北林教务系统。"),
                ManualStep(title: "再重新登录", body: "如果 App 提示会话失效或登录态异常，先完成重新认证，再回到原页面刷新。"),
                ManualStep(title: "仍失败再反馈", body: "保留页面名称、错误提示、发生时间，以及浏览器能否打开学校系统，再提交反馈。")
            ]
        ),
        ManualChapter(
            icon: "arrow.triangle.2.circlepath",
            title: "同步与缓存",
            detail: "本地缓存和重试顺序",
            intro: "\(AppBrand.displayName) 会把最近一次成功同步的教务数据保存在本机。网络不稳定、学校系统暂时不可用或登录态失效时，你仍然可以查看旧数据。",
            rows: [
                ManualInfo(title: "缓存保存什么", body: "课表、成绩、考试安排、教学计划、培养方案、空教室查询结果、学习资料和体育记录会按功能保存在本机，用于离线查看和失败兜底。"),
                ManualInfo(title: "本地数据是什么", body: "课程备注、课表提醒、收藏、自定日程、学习资料、学习空间、任务、专注记录和体测记录等，是你在当前设备上创建或导入的数据。"),
                ManualInfo(title: "旧数据为什么还在", body: "同步或导入失败不会立刻删除旧数据。这样在网络不可用、学校系统维护或文件格式错误时，课表和成绩仍然可以临时查看。成功更新后，新数据会替换对应缓存。"),
                ManualInfo(title: "清除缓存会怎样", body: "清除缓存会删除本地身份、教务登录态、教务缓存，以及本机保存的备注、提醒、收藏、学习资料、学习空间、任务、学习记录、体测记录等内容。"),
                ManualInfo(title: "什么时候适合清缓存", body: "账号切换、身份异常、旧缓存明显不一致，或需要彻底移除本机数据时再清除。普通同步失败通常先重试或重新登录，不需要马上清缓存。")
            ],
            steps: [
                ManualStep(title: "先确认网络", body: "连接 bjfu-wifi、校园网或其它能访问北林教务的网络，并确认学校页面本身可打开。"),
                ManualStep(title: "再重新同步", body: "回到对应页面刷新，或在我的页使用重新同步入口集中更新教务数据。"),
                ManualStep(title: "再管理本地数据", body: "进入“重新同步”，查看缓存状态并决定是否清理。"),
                ManualStep(title: "仍失败再反馈", body: "如果同一功能多次失败，记录页面名称、入口类型、错误提示和发生时间，再提交反馈。")
            ]
        ),
        ManualChapter(
            icon: "person.2.fill",
            title: "社区、反馈与共享课表",
            detail: "主动发布才进入服务",
            intro: "社区能力由 \(AppBrand.displayName) 社区服务承接，和北林教务系统不是同一个系统。学校身份用于确认校园归属，社区资料用于展示、互动、通知和安全处理。",
            rows: [
                ManualInfo(title: "社区会保存什么", body: "昵称、头像、学院、年级、帖子、评论、点赞、收藏、通知、举报、反馈、评教，以及你主动发布的共享课表数据会保存到 \(AppBrand.displayName) 社区服务。"),
                ManualInfo(title: "不会自动上传什么", body: "成绩、考试安排、课程备注、提醒、收藏、自定日程、学习资料文件、学习空间、任务、专注记录和体测记录不会因为你打开社区而自动上传。"),
                ManualInfo(title: "共享课表包含什么", body: "共享课表只包含课程安排，用来让被授权的人查看；它不包含成绩、考试、课程备注、提醒、收藏或学习资料。你可以撤销查看权限。"),
                ManualInfo(title: "反馈会附带什么", body: "举报与反馈会提交你的文字说明。必要时会附带设备型号、iOS 版本、App 版本、登录状态和最近同步时间，方便定位同步失败、登录异常、学校页面解析变化或社区问题。"),
                ManualInfo(title: "社区安全怎么处理", body: "遇到不当内容、骚扰、冒充、刷屏、恶意评分、泄露隐私或其它滥用行为，可以在“举报与反馈”选择“社区安全”，也可以通过联系我们里的邮箱或反馈群说明。")
            ],
            steps: [
                ManualStep(title: "发布前确认内容", body: "帖子、评论、评分和共享课表属于主动发布内容，提交前确认没有个人隐私、他人隐私或不适合公开的信息。"),
                ManualStep(title: "发现问题先举报", body: "看到不当内容时优先使用举报入口，说明问题类型和位置，方便后续处理。"),
                ManualStep(title: "需要撤回就到对应入口处理", body: "共享课表权限可以撤销；帖子、评论或资料相关问题可以通过反馈说明需要处理的内容。")
            ]
        ),
        ManualChapter(
            icon: "lock.shield.fill",
            title: "数据安全边界",
            detail: "本机、学校和社区服务",
            intro: "理解哪些数据留在本机、哪些请求发往学校系统、哪些内容进入社区服务，可以更清楚地判断什么时候适合清缓存、反馈、退出登录或撤销共享。",
            rows: [
                ManualInfo(title: "教务账号和密码", body: "教务账号和密码只用于向北林强智教务系统发起登录请求，不用于 \(AppBrand.displayName) 社区资料，也不会作为帖子、评论、反馈或共享课表内容保存。"),
                ManualInfo(title: "学校教务数据", body: "课表、成绩、考试、教学计划和培养方案等个人教务数据优先保存在本机，用来支持离线查看。\(AppBrand.displayName) 社区服务不替代学校教务系统。"),
                ManualInfo(title: "本机私有数据", body: "学习资料文件、简历文件、课程备注、提醒、学习空间、任务、专注记录、体测记录和常用收藏保存在当前 App 的本机空间。卸载 App、清缓存或更换设备前，请先确认是否需要导出。"),
                ManualInfo(title: "社区服务数据", body: "你主动参与社区、反馈、评教或共享课表时，相关内容会进入 \(AppBrand.displayName) 社区服务，以便展示、通知、审核、处理反馈和维护社区安全。"),
                ManualInfo(title: "退出登录和清缓存区别", body: "退出登录会清理当前学校会话和社区会话；清除缓存会进一步删除本机保存的数据。只想重新登录时不一定需要清缓存，想移除本机数据时再清除缓存。"),
                ManualInfo(title: "设备权限", body: "相册、文件、通知等权限只在对应功能需要时使用。导入资料会把文件放进 App 私有目录；通知用于课程提醒和本机提醒；拒绝权限通常只影响对应功能。")
            ],
            steps: [
                ManualStep(title: "判断数据来源", body: "学校教务结果看学校系统，本地记录看当前设备，社区内容看你主动发布或反馈的内容。"),
                ManualStep(title: "处理账号问题", body: "登录异常先退出并重新登录；身份错乱或换号使用时，再考虑清除缓存。"),
                ManualStep(title: "处理设备迁移", body: "更换设备、卸载 App 或清理本机文件前，先导出仍需要保留的资料。")
            ]
        ),
        ManualChapter(
            icon: "questionmark.circle.fill",
            title: "常见问题",
            detail: "从网络到反馈的排查顺序",
            intro: "大多数问题来自网络不可达、教务会话过期、验证码失败、学校页面变化、本地缓存旧数据或社区服务暂时不可用。可以按下面顺序排查。",
            rows: [
                ManualInfo(title: "课表或成绩刷新失败", body: "先检查是否连接了能访问北林教务的网络。如果 App 提示需要重新登录，就先完成教务登录，再回到功能页刷新。若浏览器也打不开学校教务，通常是网络或学校服务问题。"),
                ManualInfo(title: "登录一直失败", body: "确认账号密码、验证码、网络环境和学校页面状态。验证码过期时刷新后再试；刚切换网络或从后台回来时，重新打开登录页通常比连续提交更可靠。"),
                ManualInfo(title: "旧数据还在是不是异常", body: "不是。\(AppBrand.displayName) 会保留最近一次成功同步的数据，避免你在校园网不可用时完全看不到课表或成绩。刷新成功后会用新数据替换旧缓存。"),
                ManualInfo(title: "空教室或培养计划不准", body: "学校页面结构、教室目录、周次节次和实时占用状态都可能变化。先重新同步，再确认查询条件；如果同一页面长期异常，可以反馈页面名称和时间。"),
                ManualInfo(title: "社区功能不能用", body: "先确认教务身份仍然有效，并完成社区资料。若社区服务异常，可以稍后重试；如果是内容、举报、评分或共享课表问题，通过“举报与反馈”提交更容易定位。"),
                ManualInfo(title: "仍然解决不了", body: "在反馈里写清楚发生在哪个页面、你当时是否连接校园网、是否刚重新登录过、看到的错误提示、发生时间，以及是否能在浏览器打开学校系统。这样比只写“打不开”更容易定位。")
            ],
            steps: [
                ManualStep(title: "判断是哪类入口", body: "教务数据先查校园网和登录；社区功能先查社区身份和网络；本地资料先查当前设备和文件权限。"),
                ManualStep(title: "保留错误提示", body: "反馈前尽量保留错误文字、页面名称和发生时间，不要只描述“不能用”。"),
                ManualStep(title: "带着上下文反馈", body: "说明是否连接校园网、是否刚重新登录、是否清过缓存、浏览器能否打开学校页面。")
            ]
        )
    ]

    var body: some View {
        List {
            Section {
                ManualIntroBlock()
                    .listRowInsets(EdgeInsets(top: 0, leading: 18, bottom: 0, trailing: 18))
                    .listRowBackground(Color.clear)
            }

            if isCommunityEnabled {
                Section("社区") {
                    Button {
                        showingCommunityTermsSheet = true
                    } label: {
                        ManualActionRow(
                            icon: "checkmark.shield.fill",
                            title: "社区条约",
                            detail: "查看或更新同意状态"
                        )
                    }
                    .buttonStyle(.plain)
                }
                .listRowBackground(AppTheme.cardBackground)
            }

            Section(header: Text("目录"), footer: Text("点进每一项，可以查看对应章节的详细说明。")) {
                ForEach(chapters) { chapter in
                    NavigationLink {
                        ManualChapterDetailView(chapter: chapter)
                    } label: {
                        ManualDirectoryRow(chapter: chapter)
                    }
                }
            }
        }
        .leafyInsetGroupedListStyle()
        .leafyCompactListSectionSpacing()
        .contentMargins(.top, 0, for: .scrollContent)
        .scrollContentBackground(.hidden)
        .background(LeafyPageBackground())
        .navigationTitle("说明与安全")
        .leafyInlineNavigationTitle()
        .sheet(isPresented: $showingCommunityTermsSheet) {
            CommunityTermsPreferenceSheet()
                .presentationDetents([.large])
        }
    }
}

private struct ManualInfo: Identifiable {
    var id: String { title }
    let title: String
    let body: String
}

private struct ManualStep: Identifiable {
    var id: String { title }
    let title: String
    let body: String
}

private struct ManualChapter: Identifiable {
    var id: String { title }
    let icon: String
    let title: String
    let detail: String
    let intro: String
    let rows: [ManualInfo]
    let steps: [ManualStep]
}

private struct ManualIntroBlock: View {
    var body: some View {
        VStack(alignment: .leading, spacing: 10) {
            HStack(spacing: 10) {
                Image(systemName: "book.closed.fill")
                    .font(.system(size: 15, weight: .semibold))
                    .foregroundStyle(AppTheme.accent)
                    .frame(width: 20, height: 20)

                VStack(alignment: .leading, spacing: 4) {
                    Text("\(AppBrand.displayName) 使用说明与安全手册")
                        .leafyHeadline()
                        .foregroundStyle(AppTheme.primaryText)

                    Text("校园工具 / 教务同步 / 数据边界")
                        .microCaption()
                        .foregroundStyle(AppTheme.tertiaryText)
                }
            }

            Text("这里集中说明 \(AppBrand.displayName) 的定位、校园网和教务登录要求、同步缓存逻辑、社区与共享课表的数据边界，以及遇到登录或同步失败时可以先按什么顺序自行排查。")
                .leafySubheadline()
                .foregroundStyle(AppTheme.secondaryText)
                .fixedSize(horizontal: false, vertical: true)
        }
        .padding(.vertical, 0)
    }
}

private struct ManualDirectoryRow: View {
    let chapter: ManualChapter

    var body: some View {
        HStack(alignment: .center, spacing: 12) {
            Image(systemName: chapter.icon)
                .font(.system(size: 16, weight: .semibold))
                .foregroundStyle(AppTheme.accent)
                .frame(width: 24, height: 24)

            VStack(alignment: .leading, spacing: 3) {
                Text(chapter.title)
                    .leafyBody()
                    .foregroundStyle(AppTheme.primaryText)
                    .lineLimit(1)

                Text(chapter.detail)
                    .microCaption()
                    .foregroundStyle(AppTheme.tertiaryText)
                    .lineLimit(2)
            }

            Spacer(minLength: 0)
        }
        .padding(.vertical, 4)
    }
}

private struct ManualActionRow: View {
    let icon: String
    let title: String
    let detail: String

    var body: some View {
        HStack(alignment: .center, spacing: 12) {
            Image(systemName: icon)
                .font(.system(size: 16, weight: .semibold))
                .foregroundStyle(AppTheme.accent)
                .frame(width: 24, height: 24)

            VStack(alignment: .leading, spacing: 3) {
                Text(title)
                    .leafyBody()
                    .foregroundStyle(AppTheme.primaryText)
                    .lineLimit(1)

                Text(detail)
                    .microCaption()
                    .foregroundStyle(AppTheme.tertiaryText)
                    .lineLimit(2)
            }

            Spacer(minLength: 0)

            Image(systemName: "chevron.right")
                .font(.system(size: 12, weight: .semibold))
                .foregroundStyle(AppTheme.tertiaryText)
        }
        .padding(.vertical, 4)
    }
}

private struct ManualChapterDetailView: View {
    let chapter: ManualChapter

    var body: some View {
        ScrollView(showsIndicators: false) {
            ManualChapterCard(chapter: chapter)
                .padding(.horizontal, AppSpacing.page)
                .padding(.top, AppSpacing.page)
                .padding(.bottom, AppSpacing.section)
        }
        .background(LeafyPageBackground())
        .navigationTitle(chapter.title)
        .leafyInlineNavigationTitle()
    }
}

private struct ManualChapterCard: View {
    let chapter: ManualChapter

    var body: some View {
        VStack(alignment: .leading, spacing: 16) {
            HStack(alignment: .top, spacing: 12) {
                LeafyIconBadge(systemName: chapter.icon)

                VStack(alignment: .leading, spacing: 5) {
                    Text(chapter.title)
                        .leafyHeadline()
                        .foregroundStyle(AppTheme.primaryText)

                    Text(chapter.intro)
                        .leafyBody()
                        .foregroundStyle(AppTheme.secondaryText)
                        .fixedSize(horizontal: false, vertical: true)
                }
            }

            VStack(alignment: .leading, spacing: 12) {
                ForEach(chapter.rows) { row in
                    ManualInfoRow(info: row)
                }
            }

            if !chapter.steps.isEmpty {
                Divider()
                    .overlay(AppTheme.separator)

                VStack(alignment: .leading, spacing: 12) {
                    Text("建议步骤")
                        .leafySubheadline()
                        .foregroundStyle(AppTheme.primaryText)

                    ForEach(chapter.steps.indices, id: \.self) { index in
                        ManualStepRow(number: index + 1, step: chapter.steps[index])
                    }
                }
            }
        }
        .padding(18)
        .leafyCardStyle()
    }
}

private struct ManualInfoRow: View {
    let info: ManualInfo

    var body: some View {
        VStack(alignment: .leading, spacing: 5) {
            Text(info.title)
                .leafySubheadline()
                .foregroundStyle(AppTheme.primaryText)

            Text(info.body)
                .leafyBody()
                .foregroundStyle(AppTheme.secondaryText)
                .fixedSize(horizontal: false, vertical: true)
        }
        .padding(.leading, 12)
        .overlay(alignment: .leading) {
            RoundedRectangle(cornerRadius: 2, style: .continuous)
                .fill(AppTheme.accent.opacity(0.38))
                .frame(width: 3)
        }
    }
}

private struct ManualStepRow: View {
    let number: Int
    let step: ManualStep

    var body: some View {
        HStack(alignment: .top, spacing: 12) {
            Text("\(number)")
                .microCaption()
                .foregroundStyle(.white)
                .frame(width: 24, height: 24)
                .background(AppTheme.accent, in: Circle())

            VStack(alignment: .leading, spacing: 4) {
                Text(step.title)
                    .leafySubheadline()
                    .foregroundStyle(AppTheme.primaryText)

                Text(step.body)
                    .leafyBody()
                    .foregroundStyle(AppTheme.secondaryText)
                    .fixedSize(horizontal: false, vertical: true)
            }
        }
    }
}

private struct CacheAndSyncView: View {
    @Environment(\.leafyLanguage) private var leafyLanguage
    @Environment(\.modelContext) private var modelContext
    @Query private var courses: [Course]
    @Query private var grades: [Grade]
    @Query private var notes: [CourseNote]
    @Query private var occurrenceNotes: [CourseOccurrenceNote]
    @Query private var reminders: [CourseReminderSetting]
    @Query private var cellReminders: [TimetableCellReminder]
    @Query private var favoriteClassrooms: [FavoriteClassroom]
    @Query private var favoriteLinks: [FavoriteCampusLink]
    @Query private var postgraduateTargets: [PostgraduateTarget]
    @Query private var careerResumes: [CareerResumeDocument]
    @Query private var careerTasks: [CareerTask]
    @Query private var careerOpportunities: [CareerOpportunity]
    @Query private var learningMaterials: [LearningMaterialDocument]
    @Query private var learningProjects: [LearningProject]
    @Query private var learningTasks: [LearningProjectTask]
    @Query private var studyTimeRecords: [StudyTimeRecord]
    @Query private var fitnessTestRecords: [FitnessTestRecord]
    @Query private var medicalLedgerEntries: [MedicalLedgerEntry]
    @Query private var medicalLedgerPhotos: [MedicalLedgerPhoto]

    @State private var isSyncing = false
    @State private var isClearing = false
    @State private var message: String?
    @State private var cacheSummary = ProfileCacheSummary.empty
    @State private var showingAcademicCacheClearConfirmation = false
    @State private var showingClearConfirmation = false
    @State private var networkManager = ActiveCampusContext.networkManager
    @State private var reauthenticationRequest: SchoolReauthenticationRequest?
    @State private var operationAlert: LeafyOperationAlert?

    private var isCustomCampus: Bool {
        ActiveCampusContext.identity?.isCustom == true
    }

    var body: some View {
        List {
            Section {
                Button {
                    Task { await syncAll() }
                } label: {
                    HStack {
                        Text(syncButtonTitle)
                        Spacer()
                        if isSyncing { ProgressView() }
                    }
                }
                .disabled(isSyncing || isClearing)

                Button(role: .destructive) {
                    showingAcademicCacheClearConfirmation = true
                } label: {
                    Text(L10n.text("清除教务缓存", language: leafyLanguage))
                }
                .disabled(isSyncing || isClearing)

                Button(role: .destructive) {
                    showingClearConfirmation = true
                } label: {
                    Text(isClearing ? L10n.text("清理中", language: leafyLanguage) : L10n.text("清除本地缓存", language: leafyLanguage))
                }
                .disabled(isSyncing || isClearing)

                if !isCustomCampus {
                    NavigationLink {
                        CampusNetworkConnectionGuideView()
                    } label: {
                        Label("校园网连接说明", systemImage: "wifi")
                    }
                    .disabled(isSyncing || isClearing)
                }
            } footer: {
                Text(cacheFooterText)
            }

            Section("缓存状态") {
                ForEach(cacheSummary.rows) { row in
                    cacheRow(row)
                }
            }

            if let message {
                Section {
                    Text(message)
                        .foregroundStyle(message.contains(L10n.text("失败", language: leafyLanguage)) ? AppTheme.danger : AppTheme.secondaryText)
                }
            }
        }
        .navigationTitle(isCustomCampus ? "管理本地数据" : "缓存与同步")
        .confirmationDialog("确认清除教务缓存？", isPresented: $showingAcademicCacheClearConfirmation, titleVisibility: .visible) {
            Button("清除教务缓存", role: .destructive) {
                clearAcademicCaches()
            }
            Button("取消", role: .cancel) {}
        } message: {
            Text(academicCacheClearConfirmationText)
        }
        .confirmationDialog("确认清除本地缓存？", isPresented: $showingClearConfirmation, titleVisibility: .visible) {
            Button("清除缓存", role: .destructive) {
                clearAllCaches()
            }
            Button("取消", role: .cancel) {}
        } message: {
            Text(clearConfirmationText)
        }
        .schoolReauthenticationSheet(
            request: $reauthenticationRequest,
            networkManager: networkManager
        ) { _ in
            Task { await syncAll() }
        }
        .leafyOperationAlert($operationAlert)
        .onAppear(perform: refreshCacheSummary)
        .onReceive(NotificationCenter.default.publisher(for: .schoolDataDidRefresh)) { _ in
            refreshCacheSummary()
        }
        .onChange(of: leafyLanguage) { _, _ in
            refreshCacheSummary()
        }
    }

    private var syncButtonTitle: String {
        if isSyncing {
            return L10n.text(isCustomCampus ? "检查中" : "同步中", language: leafyLanguage)
        }
        return L10n.text(isCustomCampus ? "检查本地数据状态" : "重新同步教务数据", language: leafyLanguage)
    }

    private var cacheFooterText: String {
        if isCustomCampus {
            return "“清除教务缓存”只删除课表、成绩、考试安排和同步记录，保留账号登录状态和本机保存的内容；“清除本地缓存”会一并删除本地身份、备注、提醒、收藏、简历、职业规划、学习数据和体测记录等内容，需要重新登录当前账号。"
        }
        return "“清除教务缓存”只删除课表、成绩、考试安排、教学计划和空教室等教务数据，保留登录状态和本机保存的内容；“清除本地缓存”会一并删除本地身份、教务登录态、备注、提醒、收藏、简历、职业规划和学习数据等内容，需要连接校园网重新登录。"
    }

    private var academicCacheClearConfirmationText: String {
        isCustomCampus
            ? "这个操作只会清除课表、成绩、考试安排等学校数据和同步记录。本地身份、账号登录状态、备注、提醒、收藏和学习数据会保留。"
            : "这个操作只会清除课表、成绩、考试安排、教学计划、培养方案和空教室等教务缓存。本地身份、教务登录状态、备注、提醒、收藏和学习数据会保留。"
    }

    private var clearConfirmationText: String {
        isCustomCampus
            ? "这个操作会清除本地身份、简历、职业规划和本机保存的数据。清除后需要重新登录当前账号。"
            : "这个操作会清除本地身份、教务登录态、简历、职业规划和本机保存的数据。清除后需要连接校园网重新登录。"
    }

    private func cacheRow(_ row: ProfileCacheSummaryRow) -> some View {
        HStack {
            VStack(alignment: .leading, spacing: 4) {
                Text(L10n.text(row.title, language: leafyLanguage))
                    .leafyBody()
                Text(row.detail)
                    .microCaption()
                    .foregroundStyle(AppTheme.secondaryText)
            }
            Spacer()
            Text(row.value)
                .leafySubheadline()
                .foregroundStyle(AppTheme.secondaryText)
        }
    }

    private func refreshCacheSummary() {
        cacheSummary = ProfileCacheSummary.makeLive(
            language: leafyLanguage,
            courseCount: courses.count,
            gradeCount: grades.count,
            noteCount: notes.count + occurrenceNotes.count,
            reminderCount: reminders.count,
            cellReminderCount: cellReminders.count,
            favoriteClassroomCount: favoriteClassrooms.count,
            postgraduateTargetCount: postgraduateTargets.count,
            learningMaterialCount: learningMaterials.count,
            learningProjectCount: learningProjects.count,
            learningTaskCount: learningTasks.count,
            studyTimeRecordCount: studyTimeRecords.count,
            fitnessTestRecordCount: fitnessTestRecords.count
        )
    }

    @MainActor
    private func syncAll() async {
        guard !isSyncing else { return }

        if !isCustomCampus,
           !ReviewDemoMode.isEnabled,
           let request = await SchoolReauthentication.preflightRequest(
               networkManager: networkManager,
               context: .schoolDataSync
           ) {
            reauthenticationRequest = request
            return
        }

        isSyncing = true
        defer {
            isSyncing = false
            refreshCacheSummary()
        }

        switch await SchoolDataSyncService.syncAll(
            modelContext: modelContext,
            language: leafyLanguage,
            userInitiated: true
        ) {
        case .success(let syncMessage):
            message = syncMessage
        case .needsLogin:
            operationAlert = .failure(L10n.text("请先连接校园网登录教务系统。", language: leafyLanguage))
        case .needsReauthentication(let context):
            reauthenticationRequest = SchoolReauthenticationRequest(context: context)
        }
    }

    @MainActor
    private func clearAcademicCaches() {
        isClearing = true

        for course in courses { modelContext.delete(course) }
        for grade in grades { modelContext.delete(grade) }
        SchoolDataCache.clearDiscoverCaches()
        TimetableCacheMetadata.clear()
        try? modelContext.save()

        LeafyWidgetSnapshotBuilder.publish(
            from: modelContext,
            isAuthenticated: networkManager.hasCachedIdentity || isCustomCampus || ReviewDemoMode.isEnabled
        )
        SchoolDataRefreshNotifier.post(.all)

        isClearing = false
        message = L10n.text("教务缓存已清除，本地数据与登录状态已保留。", language: leafyLanguage)
        refreshCacheSummary()
        operationAlert = .success(L10n.text("教务缓存已清除！", language: leafyLanguage))
    }

    @MainActor
    private func clearAllCaches() {
        isClearing = true

        do {
            try CareerDocumentFileStore.deleteAllFiles()
        } catch {
            isClearing = false
            operationAlert = .failure("简历文件清除失败：\(error.localizedDescription)")
            return
        }

        TimetableNotificationManager.cancelAllCourseReminders(courses: courses)
        TimetableNotificationManager.cancelAllCellReminders(cellReminders)
        ScheduleReportNotificationManager.clearScheduledNotifications()

        for course in courses { modelContext.delete(course) }
        for grade in grades { modelContext.delete(grade) }
        for note in notes { modelContext.delete(note) }
        for note in occurrenceNotes { modelContext.delete(note) }
        for reminder in reminders { modelContext.delete(reminder) }
        for reminder in cellReminders { modelContext.delete(reminder) }
        for favorite in favoriteClassrooms { modelContext.delete(favorite) }
        for favorite in favoriteLinks { modelContext.delete(favorite) }
        for target in postgraduateTargets { modelContext.delete(target) }
        for resume in careerResumes { modelContext.delete(resume) }
        for task in careerTasks { modelContext.delete(task) }
        for opportunity in careerOpportunities { modelContext.delete(opportunity) }
        for project in learningProjects { modelContext.delete(project) }
        for task in learningTasks { modelContext.delete(task) }
        for record in studyTimeRecords { modelContext.delete(record) }
        for material in learningMaterials {
            try? LearningMaterialFileStore.deleteFile(named: material.localFilename)
            modelContext.delete(material)
        }
        for record in fitnessTestRecords { modelContext.delete(record) }
        for photo in medicalLedgerPhotos {
            try? MedicalLedgerPhotoStore.deleteFile(named: photo.localFilename)
            modelContext.delete(photo)
        }
        for entry in medicalLedgerEntries { modelContext.delete(entry) }
        MedicalLedgerPhotoStore.deleteAllFiles()

        SchoolDataCache.clearDiscoverCaches()
        TimetableCacheMetadata.clear()
        CustomScheduleStore.clear()
        let sunshineRunSettings = SunshineRunStore.loadReminderSettings()
        SunshineRunNotificationManager.cancelScheduledNotifications(settings: sunshineRunSettings)
        SunshineRunStore.clear()
        ScheduleReportSettingsStore.clear()
        AppSessionResetter.returnToLogin(modelContext: modelContext)
        try? modelContext.save()

        isClearing = false
        message = L10n.text("本地缓存和本地身份已清除。", language: leafyLanguage)
        refreshCacheSummary()
        operationAlert = .success(L10n.text("本地缓存已清除！", language: leafyLanguage))
    }
}

private struct CampusNetworkConnectionGuideView: View {
    @Environment(\.openURL) private var openURL

    private let easyConnectURL = URL(string: "https://apps.apple.com/cn/app/easyconnect/id440460214")!

    var body: some View {
        List {
            Section("在校内") {
                Label("连接 bjfu-wifi", systemImage: "wifi")
                    .leafyHeadline()

                Text("连接后回到 Leafy，即可登录教务并同步课表、成绩、考试安排或查询空教室。")
                    .leafyBody()
                    .foregroundStyle(AppTheme.secondaryText)
            }

            Section("在校外") {
                Label("通过北林 VPN 连接", systemImage: "network.badge.shield.half.filled")
                    .leafyHeadline()

                Text("先安装 EasyConnect，并按学校提供的方式连接北林 VPN。连接成功后，回到 Leafy 即可使用需要校园网的教务功能。")
                    .leafyBody()
                    .foregroundStyle(AppTheme.secondaryText)

                Button {
                    openURL(easyConnectURL)
                } label: {
                    Label("前往 App Store 下载 EasyConnect", systemImage: "arrow.down.app.fill")
                }
            }

            Section {
                Text("如果重新登录页暂时无法加载验证码，请先确认校园网或北林 VPN 已连接，再点击验证码区域重试。")
                    .leafyBody()
                    .foregroundStyle(AppTheme.secondaryText)
            }
        }
        .leafyInsetGroupedListStyle()
        .navigationTitle("校园网连接说明")
        .leafyInlineNavigationTitle()
    }
}

private enum CampusLinkCatalog {
    struct LinkItem {
        let title: String
        let url: URL
    }

    struct LinkGroup {
        let title: String
        let links: [LinkItem]
    }

    static let serviceLinks: [LinkItem] = [
        ("官方网站", URL(string: "http://www.bjfu.edu.cn/")!),
        ("北林VPN", URL(string: "http://vpn1.bjfu.edu.cn/")!),
        ("数字北林", URL(string: "http://cas.bjfu.edu.cn/")!),
        ("教务系统", URL(string: "http://newjwxt.bjfu.edu.cn/")!),
        ("教务处", URL(string: "http://jwc.bjfu.edu.cn/")!),
        ("学生处", URL(string: "http://xsc.bjfu.edu.cn/")!),
        ("学工系统", URL(string: "http://xgxt.bjfu.edu.cn/")!),
        ("网络计费系统（内网）", URL(string: "http://e.bjfu.edu.cn/")!),
        ("图书馆", URL(string: "http://lib.bjfu.edu.cn/")!),
        ("邮件服务系统", URL(string: "http://mail.bjfu.edu.cn/")!),
        ("校医院", URL(string: "http://xyy.bjfu.edu.cn/")!),
        ("青桥网", URL(string: "http://qq.bjfu.edu.cn/")!),
        ("心桥网", URL(string: "http://xinqiao.bjfu.edu.cn/")!),
        ("可信电子成绩单", URL(string: "http://transcript.bjfu.edu.cn/login")!),
        ("教学平台", URL(string: "http://jxpt.bjfu.edu.cn")!),
        ("本科招生网", URL(string: "http://zsb.bjfu.edu.cn/")!),
        ("实验室与实践教学管理平台", URL(string: "http://sjjx.bjfu.edu.cn")!),
        ("保卫处", URL(string: "http://bwc.bjfu.edu.cn/")!),
        ("中国大学MOOC", URL(string: "https://www.icourse163.org/")!),
        ("学堂在线", URL(string: "https://www.xuetangx.com/")!)
    ]
    .map { LinkItem(title: $0.0, url: $0.1) }

    static let collegeLinks: [LinkItem] = [
        ("林学院", URL(string: "http://lxy.bjfu.edu.cn/")!),
        ("水土保持学院", URL(string: "http://shuibao.bjfu.edu.cn/")!),
        ("生物科学与技术学院", URL(string: "http://biology.bjfu.edu.cn/")!),
        ("园林学院", URL(string: "http://sola.bjfu.edu.cn/")!),
        ("经济管理学院", URL(string: "http://em.bjfu.edu.cn/")!),
        ("工学院", URL(string: "http://gxy.bjfu.edu.cn/")!),
        ("材料科学与技术学院", URL(string: "http://clxy.bjfu.edu.cn/")!),
        ("人文社会科学学院", URL(string: "http://renwen.bjfu.edu.cn/")!),
        ("外语学院", URL(string: "http://waiyu.bjfu.edu.cn/")!),
        ("信息学院", URL(string: "http://it.bjfu.edu.cn/")!),
        ("理学院", URL(string: "http://cos.bjfu.edu.cn/")!),
        ("生态与自然保护学院", URL(string: "https://styzrbh.bjfu.edu.cn")!),
        ("环境科学与工程学院", URL(string: "http://hjxy.bjfu.edu.cn/")!),
        ("艺术设计学院", URL(string: "http://ad.bjfu.edu.cn/")!),
        ("马克思主义学院", URL(string: "http://marxism.bjfu.edu.cn/")!),
        ("草业与草原学院", URL(string: "http://cxy.bjfu.edu.cn/")!),
        ("继续教育学院", URL(string: "http://jxjy.bjfu.edu.cn/")!),
        ("国际学院", URL(string: "http://ic.bjfu.edu.cn/")!)
    ]
    .map { LinkItem(title: $0.0, url: $0.1) }

    static let linkGroups: [LinkGroup] = [
        LinkGroup(title: "校园服务", links: serviceLinks),
        LinkGroup(title: "学院官网", links: collegeLinks)
    ]

    static var defaultLinks: [LinkItem] {
        linkGroups.flatMap(\.links)
    }
}

private struct CampusLinksView: View {
    @State private var isCollegeLinksExpanded = false
    @State private var browserItem: ProfileBrowserItem?

    private let serviceLinks = CampusLinkCatalog.serviceLinks
    private let collegeLinks = CampusLinkCatalog.collegeLinks

    var body: some View {
        List {
            Section("校园服务") {
                ForEach(serviceLinks, id: \.title) { link in
                    linkRow(link)
                }
            }

            Section {
                DisclosureGroup(isExpanded: $isCollegeLinksExpanded) {
                    ForEach(collegeLinks, id: \.title) { link in
                        linkRow(link)
                    }
                } label: {
                    HStack {
                        Text("学院官网")
                        Spacer()
                        Text("\(collegeLinks.count)")
                            .microCaption()
                            .foregroundStyle(AppTheme.tertiaryText)
                    }
                }
            }
        }
        .navigationTitle("常用链接")
        .sheet(item: $browserItem) { item in
            ProfileSafariView(url: item.url)
        }
    }

    private func linkRow(_ link: CampusLinkCatalog.LinkItem) -> some View {
        Button {
            browserItem = ProfileBrowserItem(url: link.url)
        } label: {
            HStack {
                Text(link.title)
                Spacer()
                Image(systemName: "safari")
                    .foregroundStyle(AppTheme.tertiaryText)
            }
        }
        .buttonStyle(.plain)
    }
}

#Preview {
    ProfileView()
        .environmentObject(AppNavigationCoordinator())
}
