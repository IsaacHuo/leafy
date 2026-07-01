import SwiftUI
#if canImport(UIKit)
import UIKit
#elseif canImport(AppKit)
import AppKit
#endif

struct TimetableWeatherAdviceSheet: View {
    let currentWeek: Int
    let courses: [Course]
    let cellReminders: [TimetableCellReminder]
    let exams: [ExamArrangement]
    @Binding var weatherPreview: TimetableWeatherSnapshot?

    @Environment(\.dismiss) private var dismiss
    @Environment(\.leafyDependencies) private var dependencies
    @Environment(\.leafyControlScale) private var leafyControlScale
    @Environment(\.leafyLanguage) private var leafyLanguage
    @Environment(\.leafyThemeColorPreference) private var themeColorPreference
    @Environment(\.scenePhase) private var scenePhase
    @State private var loadState: TimetableWeatherAdviceLoadState = .idle

    var body: some View {
        NavigationStack {
            ScrollView {
                content
                    .padding(AppSpacing.page)
            }
            .background(LeafyPageBackground())
            .navigationTitle("天气建议")
            .leafyInlineNavigationTitle()
            .toolbar {
                ToolbarItem(placement: .leafyLeading) {
                    Button("关闭") {
                        dismiss()
                    }
                }

                if case .loaded = loadState {
                    ToolbarItem(placement: .leafyTrailing) {
                        Button("刷新") {
                            Task { await loadWeather(requestsPermissionIfNeeded: false) }
                        }
                    }
                }
            }
            .task {
                await loadInitialState()
            }
            .onChange(of: scenePhase) { _, newPhase in
                guard newPhase == .active else { return }
                Task { await loadInitialState() }
            }
        }
    }

    @ViewBuilder
    private var content: some View {
        switch loadState {
        case .idle, .loading:
            loadingCard
        case .permissionRequired:
            permissionCard(
                title: "开启当前位置天气",
                detail: "允许 MyLeafy 使用当前位置后，可以根据今天后续课程给出带伞、加衣或防晒建议。",
                primaryTitle: "允许定位"
            ) {
                Task { await loadWeather(requestsPermissionIfNeeded: true) }
            }
        case .permissionDenied:
            permissionCard(
                title: "定位权限未开启",
                detail: "请在系统设置中允许 MyLeafy 使用位置，然后回到这里刷新天气。",
                primaryTitle: "打开设置"
            ) {
                openAppSettings()
            }
        case .failed:
            failedCard
        case .loaded(let snapshot, let summary):
            loadedContent(snapshot: snapshot, summary: summary)
        }
    }

    private var loadingCard: some View {
        VStack(spacing: 14 * leafyControlScale) {
            ProgressView()
            Text("正在读取天气")
                .leafyHeadline()
                .foregroundStyle(AppTheme.primaryText)
        }
        .frame(maxWidth: .infinity)
        .padding(24 * leafyControlScale)
        .leafyCardStyle()
    }

    private func permissionCard(
        title: String,
        detail: String,
        primaryTitle: String,
        action: @escaping () -> Void
    ) -> some View {
        VStack(alignment: .leading, spacing: 16 * leafyControlScale) {
            HStack(alignment: .top, spacing: 12 * leafyControlScale) {
                LeafyIconBadge(systemName: "location")

                VStack(alignment: .leading, spacing: 5 * leafyControlScale) {
                    Text(title)
                        .leafyHeadline()
                        .foregroundStyle(AppTheme.primaryText)
                    Text(detail)
                        .leafyBody()
                        .foregroundStyle(AppTheme.secondaryText)
                }
            }

            Button(action: action) {
                Label(primaryTitle, systemImage: "location.fill")
                    .frame(maxWidth: .infinity)
            }
            .buttonStyle(.borderedProminent)
            .tint(AppTheme.accent(for: themeColorPreference))
        }
        .padding(18 * leafyControlScale)
        .leafyCardStyle()
    }

    private var failedCard: some View {
        VStack(alignment: .leading, spacing: 16 * leafyControlScale) {
            HStack(alignment: .top, spacing: 12 * leafyControlScale) {
                LeafyIconBadge(systemName: "cloud.slash", tint: AppTheme.tertiaryText)

                VStack(alignment: .leading, spacing: 5 * leafyControlScale) {
                    Text("天气暂不可用")
                        .leafyHeadline()
                        .foregroundStyle(AppTheme.primaryText)
                    Text("可以稍后重试。若刚启用 WeatherKit，请确认开发者后台已同时开启 capability 和 App Service。")
                        .leafyBody()
                        .foregroundStyle(AppTheme.secondaryText)
                }
            }

            Button {
                Task { await loadWeather(requestsPermissionIfNeeded: false) }
            } label: {
                Label("重试", systemImage: "arrow.clockwise")
                    .frame(maxWidth: .infinity)
            }
            .buttonStyle(.bordered)
            .tint(AppTheme.accent(for: themeColorPreference))
        }
        .padding(18 * leafyControlScale)
        .leafyCardStyle()
    }

    private func loadedContent(
        snapshot: TimetableWeatherSnapshot,
        summary: TimetableWeatherAdviceSummary
    ) -> some View {
        VStack(alignment: .leading, spacing: AppSpacing.card) {
            weatherHeader(snapshot)
            suggestionsSection(summary.suggestions)

            if !summary.scheduleItems.isEmpty {
                scheduleSection(summary.scheduleItems)
            }

            attributionFooter(snapshot.attribution)
        }
    }

    private func weatherHeader(_ snapshot: TimetableWeatherSnapshot) -> some View {
        HStack(alignment: .center, spacing: 14 * leafyControlScale) {
            LeafyIconBadge(
                systemName: snapshot.symbolName.isEmpty ? "cloud.sun" : snapshot.symbolName,
                tint: AppTheme.accent(for: themeColorPreference)
            )

            VStack(alignment: .leading, spacing: 4 * leafyControlScale) {
                Text(snapshot.displayText)
                    .title2()
                    .foregroundStyle(AppTheme.primaryText)
                Text("更新于 \(DateFormatters.headerWithTime.string(from: snapshot.observedAt))")
                    .microCaption()
                    .foregroundStyle(AppTheme.secondaryText)
            }

            Spacer(minLength: 0)
        }
        .padding(18 * leafyControlScale)
        .leafyCardStyle()
    }

    private func suggestionsSection(_ suggestions: [TimetableWeatherSuggestion]) -> some View {
        VStack(alignment: .leading, spacing: 12 * leafyControlScale) {
            Text("今天建议")
                .leafyHeadline()
                .foregroundStyle(AppTheme.primaryText)

            VStack(spacing: 10 * leafyControlScale) {
                ForEach(suggestions) { suggestion in
                    WeatherSuggestionRow(suggestion: suggestion)
                }
            }
        }
        .padding(18 * leafyControlScale)
        .leafyCardStyle()
    }

    private func scheduleSection(_ items: [TimetableWeatherScheduleItem]) -> some View {
        VStack(alignment: .leading, spacing: 12 * leafyControlScale) {
            Text("后续安排")
                .leafyHeadline()
                .foregroundStyle(AppTheme.primaryText)

            VStack(spacing: 8 * leafyControlScale) {
                ForEach(Array(items.prefix(4).enumerated()), id: \.offset) { _, item in
                    HStack(spacing: 10 * leafyControlScale) {
                        Image(systemName: iconName(for: item.kind))
                            .font(.system(size: 14 * leafyControlScale, weight: .semibold))
                            .foregroundStyle(AppTheme.accent(for: themeColorPreference))
                            .frame(width: 22 * leafyControlScale)

                        VStack(alignment: .leading, spacing: 2 * leafyControlScale) {
                            Text(item.displayTitle)
                                .leafySubheadline()
                                .foregroundStyle(AppTheme.primaryText)
                                .lineLimit(1)
                            Text(item.timeText)
                                .microCaption()
                                .foregroundStyle(AppTheme.secondaryText)
                        }

                        Spacer(minLength: 0)
                    }
                    .padding(.vertical, 4 * leafyControlScale)
                }
            }
        }
        .padding(18 * leafyControlScale)
        .leafyCardStyle()
    }

    private func attributionFooter(_ attribution: TimetableWeatherAttribution) -> some View {
        HStack(spacing: 6 * leafyControlScale) {
            Text("数据来源：\(attribution.serviceName)")
                .microCaption()
                .foregroundStyle(AppTheme.secondaryText)

            Link("法律信息", destination: attribution.legalPageURL)
                .microCaption()
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding(.horizontal, 4 * leafyControlScale)
    }

    @MainActor
    private func loadInitialState() async {
        switch dependencies.timetableWeatherService.authorizationState() {
        case .authorized:
            if let cached = dependencies.timetableWeatherService.cachedWeather(maxAge: 30 * 60) {
                apply(snapshot: cached)
            } else {
                await loadWeather(requestsPermissionIfNeeded: false)
            }
        case .notDetermined:
            loadState = .permissionRequired
        case .denied:
            loadState = .permissionDenied
        case .unavailable:
            loadState = .failed
        }
    }

    @MainActor
    private func loadWeather(requestsPermissionIfNeeded: Bool) async {
        loadState = .loading
        do {
            let snapshot = try await dependencies.timetableWeatherService.fetchCurrentWeather(
                requestsPermissionIfNeeded: requestsPermissionIfNeeded
            )
            apply(snapshot: snapshot)
        } catch TimetableWeatherServiceError.permissionRequired {
            loadState = .permissionRequired
        } catch TimetableWeatherServiceError.permissionDenied {
            loadState = .permissionDenied
        } catch {
            loadState = .failed
        }
    }

    @MainActor
    private func apply(snapshot: TimetableWeatherSnapshot) {
        let scheduleItems = TimetableWeatherAdviceBuilder.scheduleItems(
            courses: courses,
            cellReminders: cellReminders,
            exams: exams,
            currentWeek: currentWeek
        )
        let summary = TimetableWeatherAdviceBuilder.makeSummary(
            snapshot: snapshot,
            scheduleItems: scheduleItems
        )
        weatherPreview = snapshot
        loadState = .loaded(snapshot, summary)
    }

    private func iconName(for kind: TimetableWeatherScheduleItemKind) -> String {
        switch kind {
        case .course:
            return "book.closed"
        case .reminder:
            return "calendar.badge.clock"
        case .exam:
            return "pencil.and.list.clipboard"
        }
    }

    private func openAppSettings() {
        LeafySystemSettings.openApplicationSettings()
    }
}

private enum TimetableWeatherAdviceLoadState: Equatable {
    case idle
    case loading
    case permissionRequired
    case permissionDenied
    case failed
    case loaded(TimetableWeatherSnapshot, TimetableWeatherAdviceSummary)
}

private struct WeatherSuggestionRow: View {
    @Environment(\.leafyControlScale) private var leafyControlScale

    let suggestion: TimetableWeatherSuggestion

    var body: some View {
        HStack(alignment: .top, spacing: 11 * leafyControlScale) {
            Image(systemName: suggestion.systemImage)
                .font(.system(size: 16 * leafyControlScale, weight: .semibold))
                .foregroundStyle(AppTheme.accent)
                .frame(width: 24 * leafyControlScale, height: 24 * leafyControlScale)

            VStack(alignment: .leading, spacing: 3 * leafyControlScale) {
                Text(suggestion.title)
                    .leafySubheadline()
                    .foregroundStyle(AppTheme.primaryText)
                Text(suggestion.detail)
                    .leafyBody()
                    .foregroundStyle(AppTheme.secondaryText)
            }

            Spacer(minLength: 0)
        }
    }
}
