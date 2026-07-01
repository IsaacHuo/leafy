import AppIntents
import SwiftUI
import WidgetKit

struct LeafyTimetableEntry: TimelineEntry {
    let date: Date
    let snapshot: LeafyWidgetSnapshot
    let selectedDayOffset: Int
    let temperatureText: String
}

struct LeafyTimetableProvider: TimelineProvider {
    func placeholder(in context: Context) -> LeafyTimetableEntry {
        LeafyTimetableEntry(
            date: Date(),
            snapshot: .placeholder,
            selectedDayOffset: 0,
            temperatureText: LeafyWidgetWeatherService.placeholderTemperatureText
        )
    }

    func getSnapshot(in context: Context, completion: @escaping (LeafyTimetableEntry) -> Void) {
        let selectedDayOffset = LeafyWidgetSnapshotStore.selectedDayOffset
        let snapshot = LeafyWidgetSnapshotStore.loadSelectedSnapshot() ?? .placeholder

        Task {
            let temperatureText = await LeafyWidgetWeatherService.currentTemperatureText()
            completion(
                LeafyTimetableEntry(
                    date: Date(),
                    snapshot: snapshot,
                    selectedDayOffset: selectedDayOffset,
                    temperatureText: temperatureText
                )
            )
        }
    }

    func getTimeline(in context: Context, completion: @escaping (Timeline<LeafyTimetableEntry>) -> Void) {
        let now = Date()
        let selectedDayOffset = LeafyWidgetSnapshotStore.selectedDayOffset
        let snapshot = LeafyWidgetSnapshotStore.loadSelectedSnapshot() ?? .empty

        Task {
            let temperatureText = await LeafyWidgetWeatherService.currentTemperatureText()
            let entry = LeafyTimetableEntry(
                date: now,
                snapshot: snapshot,
                selectedDayOffset: selectedDayOffset,
                temperatureText: temperatureText
            )
            let nextRefresh = Calendar.current.date(byAdding: .minute, value: 20, to: now) ?? now.addingTimeInterval(20 * 60)
            completion(Timeline(entries: [entry], policy: .after(nextRefresh)))
        }
    }
}

struct LeafyTimetableWidget: Widget {
    var body: some WidgetConfiguration {
        StaticConfiguration(
            kind: LeafyWidgetConstants.widgetKind,
            provider: LeafyTimetableProvider()
        ) { entry in
            LeafyWidgetEntryView(entry: entry)
        }
        .configurationDisplayName(LeafyWidgetL10n.text("MyLeafy 课表"))
        .description(LeafyWidgetL10n.text("查看今天课程、备注和课前提醒。"))
        .supportedFamilies([.systemSmall, .systemMedium])
        .contentMarginsDisabled()
    }
}

private struct LeafyWidgetEntryView: View {
    @Environment(\.widgetFamily) private var family

    let entry: LeafyTimetableEntry
    private let palette = LeafyWidgetPalette(theme: LeafyWidgetThemeStore.load())

    var body: some View {
        Group {
            switch family {
            case .systemSmall:
                LeafySmallWidgetView(
                    snapshot: entry.snapshot,
                    selectedDayOffset: entry.selectedDayOffset,
                    temperatureText: entry.temperatureText,
                    palette: palette
                )
            default:
                LeafyMediumWidgetView(snapshot: entry.snapshot, selectedDayOffset: entry.selectedDayOffset, palette: palette)
            }
        }
        .invalidatableContent()
        .containerBackground(for: .widget) {
            LeafyWidgetBackground(palette: palette)
        }
        .widgetURL(defaultURL)
    }

    private var defaultURL: URL {
        switch entry.snapshot.status {
        case .ready, .noCourses:
            return LeafyWidgetRoute.timetable.url
        case .needsLogin, .stale:
            return LeafyWidgetRoute.cacheSync.url
        }
    }
}

private struct LeafyMediumWidgetView: View {
    let snapshot: LeafyWidgetSnapshot
    let selectedDayOffset: Int
    let palette: LeafyWidgetPalette

    var body: some View {
        VStack(alignment: .leading, spacing: 6) {
            header

            switch snapshot.status {
            case .ready:
                mediumCourseList
            case .noCourses:
                quietState(icon: "leaf.fill", title: snapshot.headline, subtitle: snapshot.subtitle)
            case .needsLogin:
                quietState(icon: "person.crop.circle.badge.exclamationmark", title: snapshot.headline, subtitle: snapshot.subtitle)
            case .stale:
                quietState(icon: "arrow.triangle.2.circlepath", title: snapshot.headline, subtitle: snapshot.subtitle)
            }
        }
        .padding(.horizontal, 12)
        .padding(.vertical, 10)
    }

    private var header: some View {
        ZStack(alignment: .top) {
            Text(dayTitle)
                .font(.system(size: 15, weight: .bold))
                .foregroundStyle(palette.primary)
                .lineLimit(1)
                .frame(maxWidth: .infinity, alignment: .center)

            HStack(alignment: .top, spacing: 8) {
                VStack(alignment: .leading, spacing: 2) {
                    Text(snapshot.displayDate)
                        .font(.system(size: 11, weight: .semibold))
                        .foregroundStyle(palette.primary)
                        .lineLimit(1)

                    Text("\(snapshot.weekText) · \(snapshot.dayText)")
                        .font(.system(size: 9, weight: .medium))
                        .foregroundStyle(palette.secondary)
                        .lineLimit(1)
                }
                .padding(.leading, 4)

                Spacer(minLength: 8)

                LeafyWidgetDaySwitchControl(selectedDayOffset: selectedDayOffset, palette: palette)
            }
        }
        .frame(height: 34, alignment: .top)
    }

    private var mediumCourseList: some View {
        let courses = displayedCourses(maxItems: 4)
        let hiddenCount = hiddenCourseCount(displaying: courses)
        let itemCount = courses.count + (hiddenCount > 0 ? 1 : 0)

        return HStack(alignment: .center, spacing: mediumCourseSpacing(for: itemCount)) {
            ForEach(courses) { course in
                Link(destination: LeafyWidgetRoute.course(id: course.id).url) {
                    LeafyMediumCourseColumn(course: course, courseCount: itemCount, palette: palette)
                        .frame(maxWidth: .infinity, maxHeight: .infinity)
                }
                .frame(maxWidth: .infinity, maxHeight: .infinity)
            }

            if hiddenCount > 0 {
                Link(destination: LeafyWidgetRoute.timetable.url) {
                    LeafyMediumMoreColumn(hiddenCount: hiddenCount, itemCount: itemCount, palette: palette)
                        .frame(maxWidth: .infinity, maxHeight: .infinity)
                }
                .frame(maxWidth: .infinity, maxHeight: .infinity)
            }
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .center)
    }

    private func displayedCourses(maxItems: Int) -> [LeafyWidgetCourse] {
        if snapshot.courses.count > maxItems {
            return Array(snapshot.courses.prefix(max(maxItems - 1, 1)))
        }

        return Array(snapshot.courses.prefix(maxItems))
    }

    private func hiddenCourseCount(displaying courses: [LeafyWidgetCourse]) -> Int {
        max(snapshot.courses.count - courses.count, 0)
    }

    private func mediumCourseSpacing(for count: Int) -> CGFloat {
        count >= 4 ? 4 : 6
    }

    private func quietState(icon: String, title: String, subtitle: String) -> some View {
        Link(destination: snapshot.status == .noCourses ? LeafyWidgetRoute.timetable.url : LeafyWidgetRoute.cacheSync.url) {
            HStack(spacing: 10) {
                Image(systemName: icon)
                    .font(.system(size: 16, weight: .semibold))
                    .foregroundStyle(palette.brand)
                    .frame(width: 32, height: 32)
                    .background(palette.brandSoft, in: RoundedRectangle(cornerRadius: 8, style: .continuous))

                VStack(alignment: .leading, spacing: 4) {
                    Text(title)
                        .font(.system(size: 15, weight: .bold))
                        .foregroundStyle(palette.primary)
                        .lineLimit(1)
                    Text(subtitle)
                        .font(.system(size: 11, weight: .medium))
                        .foregroundStyle(palette.secondary)
                        .lineLimit(2)
                }
            }
            .frame(maxWidth: .infinity, alignment: .leading)
            .padding(.vertical, 6)
        }
    }

    private var dayTitle: String {
        LeafyWidgetSnapshotStore.normalizedDayOffset(selectedDayOffset) == 0
            ? LeafyWidgetL10n.text("今日课表")
            : LeafyWidgetL10n.text("明日课表")
    }
}

private struct LeafyWidgetDaySwitchControl: View {
    let selectedDayOffset: Int
    let palette: LeafyWidgetPalette
    var buttonWidth: CGFloat = 28
    var buttonHeight: CGFloat = 24
    var fontSize: CGFloat = 11

    var body: some View {
        HStack(spacing: 1) {
            dayButton(title: LeafyWidgetL10n.text("今"), dayOffset: 0)
            dayButton(title: LeafyWidgetL10n.text("明"), dayOffset: 1)
        }
        .padding(2)
        .background(Color.white.opacity(0.58), in: Capsule())
        .invalidatableContent()
    }

    private func dayButton(title: String, dayOffset: Int) -> some View {
        Button(intent: LeafySelectWidgetDayIntent(dayOffset: dayOffset)) {
            Text(title)
                .font(.system(size: fontSize, weight: .bold))
                .lineLimit(1)
                .frame(width: buttonWidth, height: buttonHeight)
                .foregroundStyle(isSelected(dayOffset) ? Color.white : palette.secondary)
                .background(
                    isSelected(dayOffset) ? palette.brand : Color.clear,
                    in: Capsule()
                )
        }
        .buttonStyle(.plain)
        .accessibilityLabel(dayOffset == 0 ? LeafyWidgetL10n.text("显示今天课表") : LeafyWidgetL10n.text("显示明天课表"))
    }

    private func isSelected(_ dayOffset: Int) -> Bool {
        LeafyWidgetSnapshotStore.normalizedDayOffset(selectedDayOffset) == dayOffset
    }
}

private struct LeafySmallWidgetView: View {
    let snapshot: LeafyWidgetSnapshot
    let selectedDayOffset: Int
    let temperatureText: String
    let palette: LeafyWidgetPalette

    var body: some View {
        VStack(alignment: .leading, spacing: 6) {
            ZStack(alignment: .leading) {
                HStack(spacing: 0) {
                    Text(temperatureText)
                        .font(.system(size: 12, weight: .semibold))
                        .foregroundStyle(palette.brand)
                        .lineLimit(1)
                        .minimumScaleFactor(0.75)
                        .fixedSize(horizontal: true, vertical: false)
                        .padding(.leading, 2)

                    Spacer(minLength: 4)

                    LeafyWidgetDaySwitchControl(
                        selectedDayOffset: selectedDayOffset,
                        palette: palette,
                        buttonWidth: 21,
                        buttonHeight: 22,
                        fontSize: 10
                    )
                }

                Text(compactDisplayDate)
                    .font(.system(size: 12, weight: .semibold))
                    .foregroundStyle(palette.secondary)
                    .lineLimit(1)
                    .minimumScaleFactor(0.72)
                    .fixedSize(horizontal: true, vertical: false)
                    .padding(.leading, 30)
                    .allowsHitTesting(false)
            }

            smallContent
        }
        .padding(.top, 10)
        .padding(.horizontal, 12)
        .padding(.bottom, 12)
    }

    @ViewBuilder
    private var smallContent: some View {
        let courses = displayedCourses(maxItems: 4)
        let hiddenCount = hiddenCourseCount(displaying: courses)
        let itemCount = courses.count + (hiddenCount > 0 ? 1 : 0)

        if snapshot.status == .ready, !courses.isEmpty {
            VStack(spacing: smallCourseSpacing(for: itemCount)) {
                ForEach(courses) { course in
                    LeafySmallCourseCard(course: course, courseCount: itemCount, palette: palette)
                }

                if hiddenCount > 0 {
                    Link(destination: LeafyWidgetRoute.timetable.url) {
                        LeafySmallMoreCard(hiddenCount: hiddenCount, itemCount: itemCount, palette: palette)
                    }
                }
            }
            .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .center)
        } else {
            VStack(alignment: .leading, spacing: 5) {
                Text(snapshot.headline)
                    .font(.system(size: 15, weight: .bold))
                    .foregroundStyle(palette.primary)
                    .lineLimit(2)
                    .minimumScaleFactor(0.75)

                Text(snapshot.subtitle)
                    .font(.system(size: 10, weight: .medium))
                    .foregroundStyle(palette.secondary)
                    .lineLimit(3)
            }
            .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .center)
        }
    }

    private func displayedCourses(maxItems: Int) -> [LeafyWidgetCourse] {
        if snapshot.courses.count > maxItems {
            return Array(snapshot.courses.prefix(max(maxItems - 1, 1)))
        }

        return Array(snapshot.courses.prefix(maxItems))
    }

    private func hiddenCourseCount(displaying courses: [LeafyWidgetCourse]) -> Int {
        max(snapshot.courses.count - courses.count, 0)
    }

    private func smallCourseSpacing(for count: Int) -> CGFloat {
        count >= 4 ? 3 : 5
    }

    private var compactDisplayDate: String {
        let displayDate = snapshot.displayDate.trimmingCharacters(in: .whitespacesAndNewlines)
        guard let monthRange = displayDate.range(of: "月") else {
            return displayDate
        }

        let dayText = displayDate[monthRange.upperBound...]
        return dayText.isEmpty ? displayDate : String(dayText)
    }
}

private struct LeafyMediumCourseColumn: View {
    let course: LeafyWidgetCourse
    let courseCount: Int
    let palette: LeafyWidgetPalette

    var body: some View {
        VStack(alignment: .leading, spacing: verticalSpacing) {
            RoundedRectangle(cornerRadius: 2, style: .continuous)
                .fill(accent)
                .frame(height: 4)

            Text(course.title)
                .font(.system(size: titleFontSize, weight: .bold))
                .foregroundStyle(palette.primary)
                .lineLimit(titleLineLimit)
                .minimumScaleFactor(0.68)

            Spacer(minLength: 1)

            Text(startTimeText)
                .font(.system(size: detailFontSize, weight: .semibold))
                .foregroundStyle(palette.secondary)
                .lineLimit(1)
                .minimumScaleFactor(0.8)

            Text(course.locationText)
                .font(.system(size: detailFontSize, weight: .medium))
                .foregroundStyle(palette.tertiary)
                .lineLimit(1)
                .minimumScaleFactor(0.72)
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
        .padding(.horizontal, horizontalPadding)
        .padding(.vertical, 6)
        .background(rowBackground, in: ContainerRelativeShape())
    }

    private var titleFontSize: CGFloat {
        switch courseCount {
        case 1: return 14
        case 2: return 12
        case 3: return 11
        default: return 10
        }
    }

    private var detailFontSize: CGFloat {
        courseCount >= 4 ? 8 : 9
    }

    private var titleLineLimit: Int {
        courseCount >= 4 ? 2 : 3
    }

    private var verticalSpacing: CGFloat {
        courseCount >= 4 ? 2 : 3
    }

    private var horizontalPadding: CGFloat {
        courseCount >= 4 ? 5 : 7
    }

    private var startTimeText: String {
        course.timeText.split(separator: "-").first.map(String.init) ?? course.timeText
    }

    private var accent: Color {
        palette.courseAccents[course.accentIndex % palette.courseAccents.count]
    }

    private var rowBackground: Color {
        course.isActive ? palette.brandSoft.opacity(0.95) : Color.white.opacity(0.58)
    }
}

private struct LeafyMediumMoreColumn: View {
    let hiddenCount: Int
    let itemCount: Int
    let palette: LeafyWidgetPalette

    var body: some View {
        VStack(alignment: .leading, spacing: 4) {
            Image(systemName: "ellipsis")
                .font(.system(size: 15, weight: .bold))
                .foregroundStyle(palette.brand)

            Spacer(minLength: 1)

            Text(LeafyWidgetL10n.text("还有 %d 节", hiddenCount))
                .font(.system(size: itemCount >= 4 ? 10 : 11, weight: .bold))
                .foregroundStyle(palette.primary)
                .lineLimit(1)
                .minimumScaleFactor(0.75)

            Text(LeafyWidgetL10n.text("打开课表"))
                .font(.system(size: 8, weight: .medium))
                .foregroundStyle(palette.secondary)
                .lineLimit(1)
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
        .padding(.horizontal, itemCount >= 4 ? 5 : 7)
        .padding(.vertical, 6)
        .background(palette.brandSoft.opacity(0.86), in: ContainerRelativeShape())
    }
}

private struct LeafySmallCourseCard: View {
    let course: LeafyWidgetCourse
    let courseCount: Int
    let palette: LeafyWidgetPalette

    var body: some View {
        HStack(spacing: 6) {
            RoundedRectangle(cornerRadius: 2, style: .continuous)
                .fill(accent)
                .frame(width: 3)

            if courseCount <= 2 {
                VStack(alignment: .leading, spacing: 1) {
                    Text(course.title)
                        .font(.system(size: titleFontSize, weight: .bold))
                        .foregroundStyle(palette.primary)
                        .lineLimit(courseCount == 1 ? 2 : 1)
                        .minimumScaleFactor(0.72)

                    Text("\(course.timeText) · \(course.locationText)")
                        .font(.system(size: subtitleFontSize, weight: .medium))
                        .foregroundStyle(palette.secondary)
                        .lineLimit(1)
                        .minimumScaleFactor(0.7)
                        .layoutPriority(1)
                }
                .frame(maxWidth: .infinity, alignment: .leading)
            } else {
                Text(course.title)
                    .font(.system(size: titleFontSize, weight: .semibold))
                    .foregroundStyle(palette.primary)
                    .lineLimit(1)
                    .minimumScaleFactor(0.7)

                Spacer(minLength: 4)

                Text(startTimeText)
                    .font(.system(size: 8, weight: .semibold))
                    .foregroundStyle(palette.secondary)
                    .lineLimit(1)
            }
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding(.horizontal, 7)
        .padding(.vertical, verticalPadding)
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .leading)
        .background(Color.white.opacity(0.58), in: ContainerRelativeShape())
    }

    private var titleFontSize: CGFloat {
        switch courseCount {
        case 1: return 15.5
        case 2: return 11.5
        case 3: return 9.5
        default: return 9
        }
    }

    private var subtitleFontSize: CGFloat {
        courseCount == 1 ? 10.5 : 8.5
    }

    private var verticalPadding: CGFloat {
        switch courseCount {
        case 1: return 9
        case 2: return 6
        case 3: return 5
        default: return 4
        }
    }

    private var startTimeText: String {
        course.timeText.split(separator: "-").first.map(String.init) ?? course.timeText
    }

    private var accent: Color {
        palette.courseAccents[course.accentIndex % palette.courseAccents.count]
    }
}

private struct LeafySmallMoreCard: View {
    let hiddenCount: Int
    let itemCount: Int
    let palette: LeafyWidgetPalette

    var body: some View {
        HStack(spacing: 6) {
            RoundedRectangle(cornerRadius: 2, style: .continuous)
                .fill(palette.brand)
                .frame(width: 3)

            Text(LeafyWidgetL10n.text("还有 %d 节", hiddenCount))
                .font(.system(size: itemCount >= 4 ? 9 : 10, weight: .semibold))
                .foregroundStyle(palette.primary)
                .lineLimit(1)
                .minimumScaleFactor(0.75)

            Spacer(minLength: 4)

            Image(systemName: "arrow.right")
                .font(.system(size: 8, weight: .semibold))
                .foregroundStyle(palette.secondary)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding(.horizontal, 7)
        .padding(.vertical, itemCount >= 4 ? 4 : 5)
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .leading)
        .background(palette.brandSoft.opacity(0.86), in: ContainerRelativeShape())
    }
}

private struct LeafyWidgetBackground: View {
    let palette: LeafyWidgetPalette

    var body: some View {
        ZStack {
            LinearGradient(
                colors: [
                    Color.white.opacity(0.98),
                    palette.brandSoft.opacity(0.88),
                    palette.backgroundMist
                ],
                startPoint: .topLeading,
                endPoint: .bottomTrailing
            )

            LinearGradient(
                colors: [
                    Color.white.opacity(0.58),
                    palette.brand.opacity(0.15)
                ],
                startPoint: .top,
                endPoint: .bottom
            )
        }
    }
}

private struct LeafyWidgetPalette {
    let brand: Color
    let brandSoft: Color
    let backgroundMist: Color
    let primary: Color
    let secondary: Color
    let tertiary: Color
    let courseAccents: [Color]

    init(theme: LeafyWidgetThemeSnapshot) {
        let base = LeafyWidgetThemePalette.baseColor(for: theme)
        let emphasis = LeafyWidgetThemePalette.emphasisColor(for: theme)
        let soft = LeafyWidgetThemePalette.softColor(for: theme)
        let textBase = Self.mix(base, with: .black, amount: 0.76)
        let secondaryText = Self.mix(base, with: .black, amount: 0.58)
        let tertiaryText = Self.mix(base, with: .black, amount: 0.44)

        brand = Self.color(emphasis)
        brandSoft = Self.color(soft)
        backgroundMist = Self.color(Self.mix(base, with: soft, amount: 0.56))
        primary = Self.color(textBase)
        secondary = Self.color(secondaryText)
        tertiary = Self.color(tertiaryText)
        courseAccents = LeafyWidgetThemePalette.courseAccentColors(for: theme).map(Self.color)
    }

    nonisolated private static func color(_ components: LeafyWidgetThemePalette.ColorComponents) -> Color {
        Color(
            red: components.normalizedRed,
            green: components.normalizedGreen,
            blue: components.normalizedBlue
        )
    }

    nonisolated private static func mix(
        _ base: LeafyWidgetThemePalette.ColorComponents,
        with target: LeafyWidgetThemePalette.ColorComponents,
        amount: Double
    ) -> LeafyWidgetThemePalette.ColorComponents {
        LeafyWidgetThemePalette.ColorComponents(
            red: base.red + (target.red - base.red) * amount,
            green: base.green + (target.green - base.green) * amount,
            blue: base.blue + (target.blue - base.blue) * amount
        )
    }
}

private extension LeafyWidgetThemePalette.ColorComponents {
    static let black = LeafyWidgetThemePalette.ColorComponents(red: 0, green: 0, blue: 0)
}

private enum LeafyWidgetWeatherService {
    static let placeholderTemperatureText = "23°"
    private static let cacheMaxAge: TimeInterval = 6 * 60 * 60

    static func currentTemperatureText() async -> String {
        do {
            let temperature = try await fetchCurrentTemperature()
            return "\(Int(temperature.rounded()))°"
        } catch {
            if let cached = cachedTemperature(maxAge: cacheMaxAge) {
                return "\(Int(cached.rounded()))°"
            }
            return "--°"
        }
    }

    private static func fetchCurrentTemperature() async throws -> Double {
        let config = try LeafyWidgetSupabaseWeatherConfig.load()
        var components = URLComponents(url: config.url.appending(path: "functions/v1/\(config.weatherFunctionName)"), resolvingAgainstBaseURL: false)
        components?.queryItems = [URLQueryItem(name: "forceFunctionRegion", value: config.edgeRegion)]
        guard let url = components?.url else {
            throw URLError(.badURL)
        }
        var request = URLRequest(url: url, timeoutInterval: 6)
        request.httpMethod = "GET"
        request.setValue(config.publishableKey, forHTTPHeaderField: "apikey")
        request.setValue("Bearer \(config.publishableKey)", forHTTPHeaderField: "Authorization")
        request.setValue(config.edgeRegion, forHTTPHeaderField: "x-region")

        let (data, response) = try await URLSession.shared.data(for: request)
        guard let httpResponse = response as? HTTPURLResponse,
              (200..<300).contains(httpResponse.statusCode) else {
            throw URLError(.badServerResponse)
        }

        let temperature = try JSONDecoder().decode(LeafyWidgetWeatherResponse.self, from: data).temperature
        saveTemperature(temperature)
        return temperature
    }

    private static func saveTemperature(_ temperature: Double) {
        let cached = LeafyWidgetCachedWeather(temperature: temperature, savedAt: Date())
        guard let data = try? JSONEncoder().encode(cached) else { return }
        UserDefaults.standard.set(data, forKey: "leafyWidget.weather.cache.v1")
    }

    private static func cachedTemperature(maxAge: TimeInterval) -> Double? {
        guard let data = UserDefaults.standard.data(forKey: "leafyWidget.weather.cache.v1"),
              let cached = try? JSONDecoder().decode(LeafyWidgetCachedWeather.self, from: data),
              Date().timeIntervalSince(cached.savedAt) <= maxAge else {
            return nil
        }

        return cached.temperature
    }
}

private struct LeafyWidgetWeatherResponse: Decodable {
    let temperature: Double
}

private struct LeafyWidgetCachedWeather: Codable {
    let temperature: Double
    let savedAt: Date
}

private struct LeafyWidgetSupabaseWeatherConfig {
    let url: URL
    let publishableKey: String
    let weatherFunctionName: String
    let edgeRegion: String

    static func load(bundle: Bundle = .main) throws -> LeafyWidgetSupabaseWeatherConfig {
        let rawURL = sanitizedBuildSetting(bundle.object(forInfoDictionaryKey: "SUPABASE_URL"))
        let rawKey = sanitizedBuildSetting(bundle.object(forInfoDictionaryKey: "SUPABASE_PUBLISHABLE_KEY"))
        let functionName = sanitizedBuildSetting(bundle.object(forInfoDictionaryKey: "SUPABASE_WEATHER_FUNCTION"))
        let edgeRegion = sanitizedBuildSetting(bundle.object(forInfoDictionaryKey: "SUPABASE_COMMUNITY_EDGE_REGION"))

        guard let url = URL(string: rawURL), !rawKey.isEmpty else {
            throw URLError(.badURL)
        }

        return LeafyWidgetSupabaseWeatherConfig(
            url: url,
            publishableKey: rawKey,
            weatherFunctionName: functionName.isEmpty ? "campus-weather" : functionName,
            edgeRegion: edgeRegion.isEmpty ? "ap-northeast-1" : edgeRegion
        )
    }

    private static func sanitizedBuildSetting(_ value: Any?) -> String {
        let raw = (value as? String)?.trimmingCharacters(in: .whitespacesAndNewlines) ?? ""
        let placeholders = [
            "https://your-project-ref.supabase.co",
            "sb_publishable_xxx"
        ]

        if raw.isEmpty || raw.hasPrefix("$(") || placeholders.contains(raw) {
            return ""
        }

        return raw
    }
}

#Preview(as: .systemMedium) {
    LeafyTimetableWidget()
} timeline: {
    LeafyTimetableEntry(
        date: Date(),
        snapshot: .placeholder,
        selectedDayOffset: 0,
        temperatureText: LeafyWidgetWeatherService.placeholderTemperatureText
    )
    LeafyTimetableEntry(
        date: Date(),
        snapshot: .empty,
        selectedDayOffset: 1,
        temperatureText: LeafyWidgetWeatherService.placeholderTemperatureText
    )
}

#Preview(as: .systemSmall) {
    LeafyTimetableWidget()
} timeline: {
    LeafyTimetableEntry(
        date: Date(),
        snapshot: .placeholder,
        selectedDayOffset: 0,
        temperatureText: LeafyWidgetWeatherService.placeholderTemperatureText
    )
}
