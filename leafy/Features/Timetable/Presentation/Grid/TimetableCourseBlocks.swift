import SwiftData
import SwiftSoup
import SwiftUI
import UniformTypeIdentifiers
#if canImport(UIKit)
import UIKit
#elseif canImport(AppKit)
import AppKit
#endif

struct CourseBlockView: View {
    @Environment(\.leafyControlScale) private var leafyControlScale
    @Environment(\.colorScheme) private var colorScheme
    @Environment(\.leafyThemeColorPreference) private var themeColorPreference
    @AppStorage("appThemeColorPreference") private var appThemeColorPreferenceRaw = AppThemeColorPreference.green.rawValue
    @AppStorage("timetableHidesWeekends") private var timetableHidesWeekends = false

    let course: Course
    let hasNote: Bool
    var noteText: String? = nil
    let height: CGFloat
    let width: CGFloat
    let isCompact: Bool
    var isTodayCourse: Bool = false
    var backgroundPalette: [Color]? = nil
    var courseCardOpacity: Double? = nil
    var showsContextMenu = true

    var body: some View {
        VStack(alignment: .leading, spacing: contentSpacing) {
            Text(course.displayCourseName)
                .font(.system(size: courseNameFontSize, weight: isCompact ? .semibold : .regular))
                .lineSpacing(isCompact ? 0 : 2)
                .foregroundStyle(AppTheme.primaryText)
                .fixedSize(horizontal: false, vertical: true)
                .multilineTextAlignment(.leading)
                .lineLimit(isCompact ? compactCourseNameLineLimit : nil)
                .minimumScaleFactor(isCompact ? 0.82 : 1)
                .allowsTightening(isCompact)

            Text(course.timetableCardLocationText)
                .font(.system(size: locationFontSize, weight: isCompact ? .medium : .regular))
                .lineSpacing(isCompact ? 0 : 2)
                .foregroundStyle(AppTheme.secondaryText)
                .lineLimit(isCompact ? 1 : 2)
                .minimumScaleFactor(isCompact ? 0.5 : 0.82)
                .allowsTightening(true)

            if let noteDisplayText {
                Text(noteDisplayText)
                    .font(.system(size: noteFontSize, weight: .bold))
                    .foregroundStyle(noteColor)
                    .lineLimit(noteLineLimit)
                    .truncationMode(.tail)
                    .minimumScaleFactor(0.68)
                    .allowsTightening(true)
            }
        }
        .padding(.horizontal, horizontalPadding)
        .padding(.top, topPadding)
        .padding(.bottom, bottomPadding)
        .frame(width: width, height: height, alignment: .topLeading)
        .background(courseBackground)
        .overlay(
            RoundedRectangle(cornerRadius: cornerRadius, style: .continuous)
                .stroke(AppTheme.separator, lineWidth: 1)
        )
        .overlay(
            RoundedRectangle(cornerRadius: cornerRadius, style: .continuous)
                .stroke(todayCourseStrokeColor, lineWidth: todayCourseStrokeWidth)
        )
        .clipShape(RoundedRectangle(cornerRadius: cornerRadius, style: .continuous))
        .shadow(
            color: Color.black.opacity(isCompact ? 0.02 : 0.05),
            radius: isCompact ? 1 : 4,
            y: isCompact ? 0 : 2
        )
        .shadow(
            color: todayCourseGlowColor,
            radius: todayCourseGlowRadius,
            y: 0
        )
        .modifier(CourseBlockContextMenuModifier(course: course, isEnabled: showsContextMenu))
    }

    private var cornerRadius: CGFloat {
        isCompact ? AppRadius.small * 0.72 : AppRadius.small
    }

    private var contentSpacing: CGFloat {
        if usesExpandedCompactTypography {
            return 3.2 * compactSpacingScale * leafyControlScale
        }
        return (isCompact ? 2 * compactSpacingScale : 6) * leafyControlScale
    }

    private var courseNameFontSize: CGFloat {
        (isCompact ? 8 * compactTypographyScale : 11) * leafyControlScale
    }

    private var locationFontSize: CGFloat {
        (isCompact ? 6.8 * compactTypographyScale : 11) * leafyControlScale
    }

    private var noteFontSize: CGFloat {
        (isCompact ? 7.4 * compactTypographyScale : 12) * leafyControlScale
    }

    private var horizontalPadding: CGFloat {
        if usesExpandedCompactTypography {
            return min(max(width * 0.10, 5.5 * leafyControlScale), 8 * leafyControlScale)
        }
        return (isCompact ? 3.5 * compactPaddingScale : 10) * leafyControlScale
    }

    private var topPadding: CGFloat {
        if usesExpandedCompactTypography {
            return min(max(height * 0.11, 6 * leafyControlScale), 9 * leafyControlScale)
        }
        return (isCompact ? 5 * compactPaddingScale : 10) * leafyControlScale
    }

    private var bottomPadding: CGFloat {
        if usesExpandedCompactTypography {
            return min(max(height * 0.06, 3.5 * leafyControlScale), 6 * leafyControlScale)
        }
        return (isCompact ? 2.5 * compactPaddingScale : 10) * leafyControlScale
    }

    private var compactCourseNameLineLimit: Int {
        if height < 44 * leafyControlScale { return 1 }
        if height < 64 * leafyControlScale { return 2 }
        if height < 112 * leafyControlScale { return 3 }
        return 4
    }

    private var compactContentScale: CGFloat {
        guard isCompact else { return 1 }
        let baselineHeight = 82 * leafyControlScale
        guard height > baselineHeight else { return 1 }
        let progress = (height - baselineHeight) / max(44 * leafyControlScale, 1)
        return 1 + min(progress, 1) * 0.16
    }

    private var compactTypographyScale: CGFloat {
        guard isCompact else { return 1 }
        if timetableHidesWeekends {
            let verticalInsets = topPadding + bottomPadding
            let targetTextHeight = max(height * 0.74 - verticalInsets, 1)
            let targetScale = targetTextHeight / max(compactBaseTextHeight * leafyControlScale, 1)
            let minimumScale = compactContentScale * 1.4
            return min(max(targetScale, minimumScale), compactTypographyScaleCap)
        }
        return min(compactContentScale, 1.28)
    }

    private var compactSpacingScale: CGFloat {
        guard isCompact else { return 1 }
        let weekendBoost: CGFloat = timetableHidesWeekends ? 1.06 : 1
        return min(compactContentScale * weekendBoost, 1.2)
    }

    private var compactPaddingScale: CGFloat {
        min(compactContentScale, 1.12)
    }

    private var usesExpandedCompactTypography: Bool {
        isCompact && timetableHidesWeekends
    }

    private var compactBaseTextHeight: CGFloat {
        let noteHeight: CGFloat = trimmedNoteText == nil ? 0 : 7.4
        let noteGap: CGFloat = trimmedNoteText == nil ? 0 : 1.2
        return 8 + 6.8 + 3.2 + noteHeight + noteGap
    }

    private var compactTypographyScaleCap: CGFloat {
        if height < 48 * leafyControlScale { return 1.36 }
        if height < 70 * leafyControlScale { return 1.55 }
        return 1.72
    }

    private var noteColor: Color {
        AppTheme.danger.opacity(colorScheme == .dark ? 0.76 : 0.64)
    }

    private var trimmedNoteText: String? {
        let trimmed = noteText?.trimmingCharacters(in: .whitespacesAndNewlines) ?? ""
        return trimmed.isEmpty ? nil : trimmed
    }

    private var noteDisplayText: String? {
        guard let trimmed = trimmedNoteText else { return nil }
        guard isCompact else { return trimmed }
        let limit = compactNoteCharacterLimit
        guard trimmed.count > limit else { return trimmed }
        return "\(trimmed.prefix(limit))..."
    }

    private var noteLineLimit: Int? {
        isCompact ? compactNoteLineLimit : nil
    }

    private var compactNoteLineLimit: Int {
        guard isCompact else { return Int.max }
        if height >= 124 * leafyControlScale && width >= 58 * leafyControlScale { return 3 }
        if height >= 92 * leafyControlScale && width >= 46 * leafyControlScale { return 2 }
        return 1
    }

    private var compactNoteCharacterLimit: Int {
        let contentWidth = max(width - horizontalPadding * 2, 1)
        let charactersPerLine = max(Int(contentWidth / max(noteFontSize * 0.82, 1)), 2)
        return max(charactersPerLine * compactNoteLineLimit - 3, 1)
    }

    private var todayCourseStrokeColor: Color {
        guard isTodayCourse else { return .clear }
        return AppTheme.accentEmphasis(for: themeColorPreference).opacity(colorScheme == .dark ? 0.92 : 0.78)
    }

    private var todayCourseStrokeWidth: CGFloat {
        guard isTodayCourse else { return 0 }
        return max(1.5, (isCompact ? 1.7 : 2.0) * leafyControlScale)
    }

    private var todayCourseGlowColor: Color {
        guard isTodayCourse else { return .clear }
        return AppTheme.accent(for: themeColorPreference).opacity(colorScheme == .dark ? 0.24 : 0.16)
    }

    private var todayCourseGlowRadius: CGFloat {
        guard isTodayCourse else { return 0 }
        return (isCompact ? 4 : 7) * leafyControlScale
    }

    private var courseBackground: Color {
        if let backgroundPalette, !backgroundPalette.isEmpty {
            return AppTheme.courseCardColor(
                for: course.displayCourseName + course.teacher,
                colors: backgroundPalette
            )
            .opacity(courseCardOpacity ?? (isCompact ? 0.86 : 0.9))
        }

        if colorScheme == .dark {
            return AppTheme.accent(for: themeColorPreference).opacity(isCompact ? 0.26 : 0.3)
        }

        return AppTheme.courseCardColor(
            for: course.displayCourseName + course.teacher,
            themeColorPreferenceRaw: appThemeColorPreferenceRaw
        )
        .opacity(isCompact ? 0.82 : 0.9)
    }
}

private struct CourseBlockContextMenuModifier: ViewModifier {
    let course: Course
    let isEnabled: Bool

    @ViewBuilder
    func body(content: Content) -> some View {
        if isEnabled {
            content.contextMenu {
                Label(course.teacher.isEmpty ? L10n.text("未填写教师") : course.teacher, systemImage: "person")
                Label(course.locationText, systemImage: "mappin.and.ellipse")
                Label(course.weeksText, systemImage: "calendar")
            }
        } else {
            content
        }
    }
}

struct TimetableCellReminderBlockView: View {
    @Environment(\.leafyControlScale) private var leafyControlScale
    @Environment(\.colorScheme) private var colorScheme
    @Environment(\.leafyThemeColorPreference) private var themeColorPreference
    @AppStorage("appThemeColorPreference") private var appThemeColorPreferenceRaw = AppThemeColorPreference.green.rawValue

    let reminder: TimetableCellReminder
    let height: CGFloat
    let width: CGFloat

    var body: some View {
        VStack(alignment: .leading, spacing: 2.5 * leafyControlScale) {
            HStack(alignment: .firstTextBaseline, spacing: 4 * leafyControlScale) {
                Image(systemName: "bell.fill")
                    .font(.system(size: iconFontSize, weight: .semibold))
                    .foregroundStyle(AppTheme.accentEmphasis)

                Text(reminder.title)
                    .font(.system(size: titleFontSize, weight: .semibold))
                    .foregroundStyle(AppTheme.primaryText)
                    .lineLimit(titleLineLimit)
                    .minimumScaleFactor(0.72)
                    .allowsTightening(true)
            }

            if height > 34 * leafyControlScale {
                Text(subtitle)
                    .font(.system(size: captionFontSize, weight: .medium))
                    .foregroundStyle(AppTheme.secondaryText)
                    .lineLimit(1)
                    .minimumScaleFactor(0.72)
                    .allowsTightening(true)
            }
        }
        .padding(.horizontal, 4.5 * leafyControlScale)
        .padding(.vertical, 4 * leafyControlScale)
        .frame(width: width, height: height, alignment: .topLeading)
        .background(reminderBackground)
        .overlay(
            RoundedRectangle(cornerRadius: AppRadius.small * 0.72, style: .continuous)
                .stroke(AppTheme.accent.opacity(colorScheme == .dark ? 0.28 : 0.18), lineWidth: 1)
        )
        .clipShape(RoundedRectangle(cornerRadius: AppRadius.small * 0.72, style: .continuous))
        .shadow(color: Color.black.opacity(colorScheme == .dark ? 0 : 0.025), radius: 1, y: 0)
        .accessibilityLabel(accessibilityText)
    }

    private var titleFontSize: CGFloat {
        (height < 36 * leafyControlScale ? 9.2 : 10.4) * leafyControlScale
    }

    private var iconFontSize: CGFloat {
        (height < 36 * leafyControlScale ? 8.2 : 9.2) * leafyControlScale
    }

    private var captionFontSize: CGFloat {
        (height < 42 * leafyControlScale ? 7.4 : 8.2) * leafyControlScale
    }

    private var titleLineLimit: Int {
        height < 40 * leafyControlScale ? 1 : 2
    }

    private var reminderBackground: Color {
        if colorScheme == .dark {
            return AppTheme.accent(for: themeColorPreference).opacity(0.3)
        }

        return AppTheme.courseCardColor(
            for: reminder.cellKey + reminder.title,
            themeColorPreferenceRaw: appThemeColorPreferenceRaw
        )
        .opacity(0.9)
    }

    private var subtitle: String {
        let location = reminder.locationText
        return location.isEmpty ? "日程" : location
    }

    private var accessibilityText: String {
        let location = reminder.locationText
        return location.isEmpty ? reminder.title : "\(reminder.title)，\(location)"
    }
}

struct TimetableCountdownBlockView: View {
    @Environment(\.leafyControlScale) private var leafyControlScale
    @Environment(\.colorScheme) private var colorScheme

    let projection: TimetableCountdownProjection
    let height: CGFloat
    let width: CGFloat

    var body: some View {
        HStack(alignment: .center, spacing: 3 * leafyControlScale) {
            Image(systemName: "timer")
                .font(.system(size: 6.8 * leafyControlScale, weight: .bold))
                .foregroundStyle(AppTheme.warning)

            VStack(alignment: .leading, spacing: 0.5 * leafyControlScale) {
                Text(projection.title)
                    .font(.system(size: titleFontSize, weight: .semibold))
                    .foregroundStyle(AppTheme.primaryText)
                    .lineLimit(1)
                    .minimumScaleFactor(0.64)
                    .allowsTightening(true)

                if height > 22 * leafyControlScale {
                    Text(countdownText)
                        .font(.system(size: 5.8 * leafyControlScale, weight: .medium))
                        .foregroundStyle(AppTheme.secondaryText)
                        .lineLimit(1)
                        .minimumScaleFactor(0.62)
                        .allowsTightening(true)
                }
            }

            Spacer(minLength: 0)
        }
        .padding(.horizontal, 3.5 * leafyControlScale)
        .frame(width: width, height: height, alignment: .leading)
        .background(countdownBackground)
        .overlay(
            RoundedRectangle(cornerRadius: AppRadius.small * 0.68, style: .continuous)
                .stroke(AppTheme.warning.opacity(colorScheme == .dark ? 0.34 : 0.24), lineWidth: 1)
        )
        .clipShape(RoundedRectangle(cornerRadius: AppRadius.small * 0.68, style: .continuous))
        .shadow(color: Color.black.opacity(colorScheme == .dark ? 0 : 0.04), radius: 2, y: 1)
        .accessibilityLabel(L10n.text("重要日期 %@", language: AppLanguagePreference.current, projection.title))
    }

    private var titleFontSize: CGFloat {
        (height < 24 * leafyControlScale ? 6.8 : 7.6) * leafyControlScale
    }

    private var countdownBackground: Color {
        colorScheme == .dark ? AppTheme.warning.opacity(0.24) : AppTheme.warning.opacity(0.16)
    }

    private var countdownText: String {
        let now = Date()
        let calendar = Calendar.current
        let targetDay = calendar.startOfDay(for: projection.targetDate)
        let today = calendar.startOfDay(for: now)
        let days = calendar.dateComponents([.day], from: today, to: targetDay).day ?? 0

        if projection.targetDate < now {
            return "已到期"
        }
        if days == 0 {
            return "今天 \(DateFormatters.timeOnly.string(from: projection.targetDate))"
        }
        return "还有 \(days) 天"
    }
}

struct TimetableExamBlockView: View {
    @Environment(\.leafyControlScale) private var leafyControlScale
    @Environment(\.colorScheme) private var colorScheme

    let projection: TimetableExamProjection
    let height: CGFloat
    let width: CGFloat

    var body: some View {
        HStack(alignment: .center, spacing: 3 * leafyControlScale) {
            Image(systemName: "exclamationmark.triangle.fill")
                .font(.system(size: 6.9 * leafyControlScale, weight: .bold))
                .foregroundStyle(AppTheme.warning)

            VStack(alignment: .leading, spacing: 0.5 * leafyControlScale) {
                Text(projection.name)
                    .font(.system(size: titleFontSize, weight: .semibold))
                    .foregroundStyle(AppTheme.primaryText)
                    .lineLimit(1)
                    .minimumScaleFactor(0.62)
                    .allowsTightening(true)

                if height > 22 * leafyControlScale {
                    Text(detailText)
                        .font(.system(size: 5.8 * leafyControlScale, weight: .medium))
                        .foregroundStyle(AppTheme.secondaryText)
                        .lineLimit(1)
                        .minimumScaleFactor(0.62)
                        .allowsTightening(true)
                }
            }

            Spacer(minLength: 0)
        }
        .padding(.horizontal, 3.5 * leafyControlScale)
        .frame(width: width, height: height, alignment: .leading)
        .background(examBackground)
        .overlay(
            RoundedRectangle(cornerRadius: AppRadius.small * 0.68, style: .continuous)
                .stroke(AppTheme.warning.opacity(colorScheme == .dark ? 0.46 : 0.34), lineWidth: 1)
        )
        .clipShape(RoundedRectangle(cornerRadius: AppRadius.small * 0.68, style: .continuous))
        .shadow(color: Color.black.opacity(colorScheme == .dark ? 0 : 0.05), radius: 2, y: 1)
        .accessibilityLabel(L10n.text("考试 %@", language: AppLanguagePreference.current, projection.name))
    }

    private var titleFontSize: CGFloat {
        (height < 24 * leafyControlScale ? 6.8 : 7.6) * leafyControlScale
    }

    private var examBackground: Color {
        colorScheme == .dark ? AppTheme.warning.opacity(0.28) : AppTheme.warning.opacity(0.20)
    }

    private var detailText: String {
        projection.location.isEmpty
            ? projection.startText
            : "\(projection.startText) \(projection.location)"
    }
}

enum TimetableReminderOption: String, CaseIterable, Identifiable {
    case none
    case five
    case twenty
    case thirty
    case custom

    var id: String { rawValue }

    var title: String {
        switch self {
        case .none:
            return "不提醒"
        case .five:
            return "5"
        case .twenty:
            return "20"
        case .thirty:
            return "30"
        case .custom:
            return "自定义"
        }
    }

    func minutes(customMinutes: Int) -> Int {
        switch self {
        case .none:
            return 0
        case .five:
            return 5
        case .twenty:
            return 20
        case .thirty:
            return 30
        case .custom:
            return TimetableNotificationManager.normalizedReminderMinutes(customMinutes)
        }
    }

    static func option(for minutes: Int) -> TimetableReminderOption {
        switch TimetableNotificationManager.normalizedReminderMinutes(minutes) {
        case 0:
            return .none
        case 5:
            return .five
        case 20:
            return .twenty
        case 30:
            return .thirty
        default:
            return .custom
        }
    }

    static func customMinutes(for minutes: Int) -> Int {
        let normalized = TimetableNotificationManager.normalizedReminderMinutes(minutes)
        return normalized > 0 ? normalized : 20
    }
}

struct TimetableReminderOptionPicker: View {
    @Binding var selectedOption: TimetableReminderOption
    @Binding var customMinutes: Int

    var body: some View {
        VStack(alignment: .leading, spacing: 10) {
            Picker("提醒时间", selection: $selectedOption) {
                ForEach(TimetableReminderOption.allCases) { option in
                    Text(option.title).tag(option)
                }
            }
            .pickerStyle(.segmented)

            if selectedOption == .custom {
                Stepper(value: customMinutesBinding, in: TimetableNotificationManager.customReminderRange) {
                    Text("提前 \(customMinutesBinding.wrappedValue) 分钟")
                }
            }
        }
    }

    private var customMinutesBinding: Binding<Int> {
        Binding(
            get: {
                let normalized = TimetableNotificationManager.normalizedReminderMinutes(customMinutes)
                return normalized > 0 ? normalized : TimetableNotificationManager.customReminderRange.lowerBound
            },
            set: { newValue in
                customMinutes = TimetableNotificationManager.normalizedReminderMinutes(newValue)
            }
        )
    }
}

enum CustomScheduleEditorMode: String, CaseIterable, Identifiable {
    case timetable
    case importantDate

    var id: String { rawValue }

    var title: String {
        switch self {
        case .timetable:
            return "课表日程"
        case .importantDate:
            return "重要日期"
        }
    }

    var systemImage: String {
        switch self {
        case .timetable:
            return "calendar.badge.clock"
        case .importantDate:
            return "timer"
        }
    }
}

struct CustomScheduleEditorPresentation: Identifiable {
    let timetableContext: TimetableCellReminderContext
    let importantDateEvent: CustomScheduleEvent?
    let initialMode: CustomScheduleEditorMode
    let allowsModeSelection: Bool

    var id: String {
        [
            initialMode.rawValue,
            timetableContext.id,
            importantDateEvent?.id ?? "new",
            allowsModeSelection ? "switchable" : "locked"
        ].joined(separator: "-")
    }

    static func timetable(
        _ context: TimetableCellReminderContext,
        allowsModeSelection: Bool? = nil
    ) -> CustomScheduleEditorPresentation {
        CustomScheduleEditorPresentation(
            timetableContext: context,
            importantDateEvent: nil,
            initialMode: .timetable,
            allowsModeSelection: allowsModeSelection ?? (context.allowsDateSelection && context.reminder == nil)
        )
    }

    static func importantDate(
        _ event: CustomScheduleEvent?,
        defaultContext: TimetableCellReminderContext,
        allowsModeSelection: Bool? = nil
    ) -> CustomScheduleEditorPresentation {
        CustomScheduleEditorPresentation(
            timetableContext: defaultContext,
            importantDateEvent: event,
            initialMode: .importantDate,
            allowsModeSelection: allowsModeSelection ?? (event == nil && defaultContext.reminder == nil)
        )
    }
}

struct TimetableCellReminderSheet: View {
    let context: TimetableCellReminderContext

    var body: some View {
        CustomScheduleEditorSheet(presentation: .timetable(context))
    }
}

struct CustomScheduleEditorSheet: View {
    let presentation: CustomScheduleEditorPresentation

    @Environment(\.dismiss) private var dismiss
    @Environment(\.modelContext) private var modelContext
    @Environment(\.leafyLanguage) private var leafyLanguage
    @Query private var reminders: [TimetableCellReminder]

    @State private var selectedMode: CustomScheduleEditorMode
    @State private var title: String
    @State private var location: String
    @State private var noteText: String
    @State private var selectedReminderOption: TimetableReminderOption
    @State private var customReminderMinutes: Int
    @State private var scheduleDate: Date
    @State private var startTime: Date
    @State private var endTime: Date
    @State private var hasEndTime: Bool
    @State private var operationAlert: LeafyOperationAlert?

    init(presentation: CustomScheduleEditorPresentation) {
        self.presentation = presentation
        let context = presentation.timetableContext
        let event = presentation.importantDateEvent
        let initialMode = presentation.initialMode
        let initialTitle = initialMode == .importantDate
            ? event?.title ?? ""
            : context.reminder?.title ?? ""
        let initialLocation = initialMode == .importantDate
            ? event?.locationText ?? ""
            : context.reminder?.locationText ?? ""
        let initialNote = initialMode == .importantDate
            ? event?.noteText ?? ""
            : context.reminder?.noteText ?? ""
        let minutes = initialMode == .importantDate
            ? event?.minutesBefore ?? 0
            : context.reminder?.minutesBefore ?? 0
        let startDate = initialMode == .importantDate
            ? event?.startsAt ?? Date()
            : context.reminder?.resolvedStartDate
                ?? TimetablePeriodSchedule.startDate(week: context.week, dayOfWeek: context.day, period: context.period)
                ?? context.date
        let endDate = initialMode == .importantDate
            ? event?.endsAt ?? startDate.addingTimeInterval(45 * 60)
            : context.reminder?.resolvedEndDate
                ?? TimetablePeriodSchedule.endDate(week: context.week, dayOfWeek: context.day, period: context.period)
                ?? startDate.addingTimeInterval(45 * 60)
        _selectedMode = State(initialValue: initialMode)
        _title = State(initialValue: initialTitle)
        _location = State(initialValue: initialLocation)
        _noteText = State(initialValue: initialNote)
        _selectedReminderOption = State(initialValue: TimetableReminderOption.option(for: minutes))
        _customReminderMinutes = State(initialValue: TimetableReminderOption.customMinutes(for: minutes))
        _scheduleDate = State(initialValue: startDate)
        _startTime = State(initialValue: startDate)
        _endTime = State(initialValue: endDate)
        _hasEndTime = State(initialValue: initialMode == .timetable || event?.endsAt != nil)
    }

    var body: some View {
        NavigationStack {
            ScrollView {
                VStack(alignment: .leading, spacing: AppSpacing.card) {
                    VStack(alignment: .leading, spacing: 12) {
                        Text(navigationTitle)
                            .title1()

                        Text(sheetSubtitle)
                            .leafySubheadline()
                            .foregroundStyle(AppTheme.secondaryText)

                        if presentation.allowsModeSelection {
                            Picker("日程类型", selection: $selectedMode) {
                                ForEach(CustomScheduleEditorMode.allCases) { mode in
                                    Label(mode.title, systemImage: mode.systemImage)
                                        .tag(mode)
                                }
                            }
                            .pickerStyle(.segmented)
                        }
                    }
                    .padding(20)
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .leafyCardStyle()

                    VStack(alignment: .leading, spacing: 12) {
                        Text("日程时间")
                            .leafyHeadline()

                        if canSelectScheduleDate {
                            DatePicker("日期", selection: $scheduleDate, displayedComponents: .date)
                                .datePickerStyle(.compact)
                        } else {
                            scheduleInfoRow(title: "周次", value: weekText, icon: "calendar")
                        }

                        scheduleInfoRow(title: "日期", value: DateFormatters.header.string(from: scheduleDate), icon: "calendar.badge.clock")

                        DatePicker("开始时间", selection: $startTime, displayedComponents: .hourAndMinute)
                            .datePickerStyle(.compact)

                        if selectedMode == .importantDate {
                            Toggle("设置结束时间", isOn: $hasEndTime)
                        }

                        if selectedMode == .timetable || hasEndTime {
                            DatePicker("结束时间", selection: $endTime, displayedComponents: .hourAndMinute)
                                .datePickerStyle(.compact)
                        }

                        if selectedMode == .timetable {
                            scheduleInfoRow(title: "显示范围", value: periodText, icon: "clock")
                        }

                        if let validationMessage {
                            Text(validationMessage)
                                .microCaption()
                                .foregroundStyle(AppTheme.warning)
                                .fixedSize(horizontal: false, vertical: true)
                        }
                    }
                    .padding(18)
                    .leafyCardStyle()

                    VStack(alignment: .leading, spacing: 12) {
                        Text("日程信息")
                            .leafyHeadline()

                        TextField(titlePlaceholder, text: $title)
                            .leafyDisableAutocapitalization()
                            .padding(14)
                            .background(AppTheme.fill, in: RoundedRectangle(cornerRadius: AppRadius.medium, style: .continuous))

                        TextField("地点（可选）", text: $location)
                            .leafyDisableAutocapitalization()
                            .padding(14)
                            .background(AppTheme.fill, in: RoundedRectangle(cornerRadius: AppRadius.medium, style: .continuous))

                        TextField("备注（可选）", text: $noteText, axis: .vertical)
                            .lineLimit(3, reservesSpace: true)
                            .padding(14)
                            .background(AppTheme.fill, in: RoundedRectangle(cornerRadius: AppRadius.medium, style: .continuous))

                        TimetableReminderOptionPicker(
                            selectedOption: $selectedReminderOption,
                            customMinutes: $customReminderMinutes
                        )

                        Text("日程只保存在本机。开启提醒后，会按所选开始时间创建本地通知。")
                            .microCaption()
                            .foregroundStyle(AppTheme.secondaryText)
                    }
                    .padding(18)
                    .leafyCardStyle()

                    if canDelete {
                        Button(role: .destructive) {
                            deleteCurrentItem()
                        } label: {
                            Label(deleteTitle, systemImage: "trash")
                                .leafyBody()
                                .frame(maxWidth: .infinity)
                        }
                        .buttonStyle(.bordered)
                        .padding(18)
                        .leafyCardStyle()
                    }
                }
                .padding(AppSpacing.page)
            }
            .background(LeafyPageBackground())
            .navigationTitle(navigationTitle)
            .leafyInlineNavigationTitle()
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("取消") {
                        dismiss()
                    }
                }

                ToolbarItem(placement: .confirmationAction) {
                    Button("保存") {
                        Task { await saveCurrentItem() }
                    }
                    .disabled(isSaveDisabled)
                }
            }
            .onChange(of: selectedMode) { _, mode in
                if mode == .timetable {
                    hasEndTime = true
                }
            }
            .leafyOperationAlert($operationAlert)
        }
    }

    private var context: TimetableCellReminderContext {
        presentation.timetableContext
    }

    private var cellKey: String {
        guard let weekAndDay = selectedWeekAndDay,
              let periodRange = selectedPeriodRange else {
            return TimetableCellReminder.cellKey(week: context.week, dayOfWeek: context.day, period: context.period)
        }
        return TimetableCellReminder.cellKey(
            week: weekAndDay.week,
            dayOfWeek: weekAndDay.day,
            period: periodRange.lowerBound
        )
    }

    private var reminderRecord: TimetableCellReminder? {
        context.reminder ?? reminderRecord(for: cellKey)
    }

    private func reminderRecord(for key: String) -> TimetableCellReminder? {
        return reminders
            .filter { $0.cellKey == key }
            .max { $0.updatedAt < $1.updatedAt }
    }

    private var isSaveDisabled: Bool {
        if title.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
            return true
        }

        switch selectedMode {
        case .timetable:
            return selectedWeekAndDay == nil ||
                selectedPeriodRange == nil ||
                scheduleEndDate <= scheduleStartDate
        case .importantDate:
            return hasEndTime && scheduleEndDate <= scheduleStartDate
        }
    }

    private var navigationTitle: String {
        switch selectedMode {
        case .timetable:
            return reminderRecord == nil ? "添加日程" : "编辑日程"
        case .importantDate:
            return presentation.importantDateEvent == nil ? "添加重要日期" : "编辑重要日期"
        }
    }

    private var titlePlaceholder: String {
        switch selectedMode {
        case .timetable:
            return "日程标题"
        case .importantDate:
            return "重要日期标题"
        }
    }

    private var weekText: String {
        L10n.text("第 %d 周", language: leafyLanguage, selectedWeekAndDay?.week ?? context.week)
    }

    private var periodText: String {
        guard let selectedPeriodRange else {
            return L10n.text("不在课表节次内", language: leafyLanguage)
        }

        if selectedPeriodRange.lowerBound == selectedPeriodRange.upperBound {
            return L10n.text("第 %d 节", language: leafyLanguage, selectedPeriodRange.lowerBound)
        }
        return L10n.text("第 %d-%d 节", language: leafyLanguage, selectedPeriodRange.lowerBound, selectedPeriodRange.upperBound)
    }

    private var canSelectScheduleDate: Bool {
        selectedMode == .importantDate || context.allowsDateSelection
    }

    private var sheetSubtitle: String {
        switch selectedMode {
        case .timetable:
            return canSelectScheduleDate
                ? "选择日期和开始、结束时间，按需添加地点、备注和本地提醒。"
                : "基于当前课表格子添加日程，按需补充地点、备注和本地提醒。"
        case .importantDate:
            return "记录任意日期的重要事项；如果落在当前学期，会在课表日期摘要中轻量提示。"
        }
    }

    private var canDelete: Bool {
        switch selectedMode {
        case .timetable:
            return reminderRecord != nil
        case .importantDate:
            return presentation.importantDateEvent != nil
        }
    }

    private var deleteTitle: String {
        switch selectedMode {
        case .timetable:
            return "删除日程"
        case .importantDate:
            return "删除重要日期"
        }
    }

    private var scheduleStartDate: Date {
        combinedDate(date: scheduleDate, time: startTime)
    }

    private var scheduleEndDate: Date {
        combinedDate(date: scheduleDate, time: endTime)
    }

    private var selectedWeekAndDay: (week: Int, day: Int)? {
        semesterWeekAndDayIfSupported(for: scheduleDate)
    }

    private var selectedPeriodRange: ClosedRange<Int>? {
        TimetablePeriodSchedule.periodRange(overlapping: scheduleStartDate, endDate: scheduleEndDate)
    }

    private var validationMessage: String? {
        switch selectedMode {
        case .timetable:
            if selectedWeekAndDay == nil {
                return L10n.text("当前课表只能显示本学期范围内的日程。", language: leafyLanguage)
            }
            if scheduleEndDate <= scheduleStartDate {
                return L10n.text("结束时间需要晚于开始时间。", language: leafyLanguage)
            }
            if selectedPeriodRange == nil {
                return L10n.text("这个时间段没有覆盖课表节次，无法显示在课表里。", language: leafyLanguage)
            }
        case .importantDate:
            if hasEndTime && scheduleEndDate <= scheduleStartDate {
                return L10n.text("结束时间需要晚于开始时间。", language: leafyLanguage)
            }
        }
        return nil
    }

    @MainActor
    private func saveCurrentItem() async {
        switch selectedMode {
        case .timetable:
            await saveReminder()
        case .importantDate:
            await saveImportantDate()
        }
    }

    @MainActor
    private func saveReminder() async {
        let trimmed = title.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty,
              let weekAndDay = selectedWeekAndDay,
              let periodRange = selectedPeriodRange,
              scheduleEndDate > scheduleStartDate
        else { return }
        let trimmedLocation = location.trimmingCharacters(in: .whitespacesAndNewlines)
        let trimmedNote = noteText.trimmingCharacters(in: .whitespacesAndNewlines)
        let reminderMinutes = selectedReminderOption.minutes(customMinutes: customReminderMinutes)

        let record: TimetableCellReminder
        if let existing = reminderRecord {
            TimetableNotificationManager.cancelReminder(for: existing)
            existing.week = weekAndDay.week
            existing.dayOfWeek = weekAndDay.day
            existing.period = periodRange.lowerBound
            existing.endPeriod = periodRange.upperBound
            existing.cellKey = TimetableCellReminder.cellKey(
                week: weekAndDay.week,
                dayOfWeek: weekAndDay.day,
                period: periodRange.lowerBound
            )
            existing.title = trimmed
            existing.location = TimetableCellReminder.normalizedOptionalText(trimmedLocation)
            existing.note = TimetableCellReminder.normalizedOptionalText(trimmedNote)
            existing.startsAt = scheduleStartDate
            existing.endsAt = scheduleEndDate
            existing.minutesBefore = reminderMinutes
            existing.updatedAt = Date()
            record = existing
        } else {
            let newRecord = TimetableCellReminder(
                week: weekAndDay.week,
                dayOfWeek: weekAndDay.day,
                period: periodRange.lowerBound,
                endPeriod: periodRange.upperBound,
                title: trimmed,
                location: trimmedLocation,
                note: trimmedNote,
                startsAt: scheduleStartDate,
                endsAt: scheduleEndDate,
                minutesBefore: reminderMinutes
            )
            modelContext.insert(newRecord)
            record = newRecord
        }

        removeDuplicateReminders(keeping: record, cellKey: record.cellKey)

        do {
            try modelContext.save()
            let scheduledCount: Int
            do {
                scheduledCount = try await TimetableNotificationManager.applyReminder(for: record) ? 1 : 0
            } catch {
                operationAlert = .success(
                    L10n.text("日程已保存，但提醒未创建：%@", language: leafyLanguage, error.localizedDescription)
                )
                return
            }
            operationAlert = .success(
                saveSuccessMessage(reminderMinutes: reminderMinutes, scheduledCount: scheduledCount)
            )
        } catch {
            operationAlert = .failure(error.localizedDescription)
        }
    }

    @MainActor
    private func saveImportantDate() async {
        let trimmed = title.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty,
              !hasEndTime || scheduleEndDate > scheduleStartDate
        else { return }

        let reminderMinutes = selectedReminderOption.minutes(customMinutes: customReminderMinutes)
        var events = CustomScheduleStore.load()
        let event = CustomScheduleEvent(
            id: presentation.importantDateEvent?.id ?? UUID().uuidString,
            title: trimmed,
            startsAt: scheduleStartDate,
            endsAt: hasEndTime ? scheduleEndDate : nil,
            location: location,
            note: noteText,
            minutesBefore: reminderMinutes
        )

        if let index = events.firstIndex(where: { $0.id == event.id }) {
            TimetableNotificationManager.cancelReminder(for: events[index])
            events[index] = event
        } else {
            events.append(event)
        }
        events.sort { lhs, rhs in
            if lhs.startsAt != rhs.startsAt { return lhs.startsAt < rhs.startsAt }
            return lhs.title.localizedCompare(rhs.title) == .orderedAscending
        }
        CustomScheduleStore.save(events)

        let scheduledCount: Int
        do {
            scheduledCount = try await TimetableNotificationManager.applyReminder(for: event) ? 1 : 0
        } catch {
            operationAlert = .success(
                L10n.text("重要日期已保存，但提醒未创建：%@", language: leafyLanguage, error.localizedDescription)
            )
            return
        }

        operationAlert = .success(
            saveImportantDateSuccessMessage(reminderMinutes: reminderMinutes, scheduledCount: scheduledCount)
        )
    }

    @MainActor
    private func deleteCurrentItem() {
        switch selectedMode {
        case .timetable:
            deleteReminder()
        case .importantDate:
            deleteImportantDate()
        }
    }

    @MainActor
    private func deleteReminder() {
        let records = context.reminder.map { [$0] } ?? reminders.filter { $0.cellKey == cellKey }
        for record in records {
            TimetableNotificationManager.cancelReminder(for: record)
            modelContext.delete(record)
        }

        try? modelContext.save()
        operationAlert = .success(
            L10n.text("日程已删除！", language: leafyLanguage),
            action: { dismiss() }
        )
    }

    @MainActor
    private func deleteImportantDate() {
        guard let event = presentation.importantDateEvent else { return }
        var events = CustomScheduleStore.load()
        events.removeAll { $0.id == event.id }
        TimetableNotificationManager.cancelReminder(for: event)
        CustomScheduleStore.save(events)
        operationAlert = .success(
            L10n.text("重要日期已删除！", language: leafyLanguage),
            action: { dismiss() }
        )
    }

    @MainActor
    private func removeDuplicateReminders(keeping keptRecord: TimetableCellReminder, cellKey: String) {
        for record in reminders where record.cellKey == cellKey && record.id != keptRecord.id {
            TimetableNotificationManager.cancelReminder(for: record)
            modelContext.delete(record)
        }
    }

    private func saveSuccessMessage(reminderMinutes: Int, scheduledCount: Int) -> String {
        if reminderMinutes <= 0 {
            return L10n.text("日程已保存！", language: leafyLanguage)
        }

        return scheduledCount > 0
            ? L10n.text("日程和提醒已保存！", language: leafyLanguage)
            : L10n.text("日程已保存，但提醒时间已过，不会发送通知。", language: leafyLanguage)
    }

    private func saveImportantDateSuccessMessage(reminderMinutes: Int, scheduledCount: Int) -> String {
        if reminderMinutes <= 0 {
            return L10n.text("重要日期已保存！", language: leafyLanguage)
        }

        return scheduledCount > 0
            ? L10n.text("重要日期和提醒已保存！", language: leafyLanguage)
            : L10n.text("重要日期已保存，但提醒时间已过，不会发送通知。", language: leafyLanguage)
    }

    private func scheduleInfoRow(title: String, value: String, icon: String) -> some View {
        HStack(alignment: .top, spacing: 14) {
            LeafyIconBadge(systemName: icon)

            VStack(alignment: .leading, spacing: 4) {
                Text(L10n.text(title, language: leafyLanguage))
                    .microCaption()
                    .foregroundStyle(AppTheme.secondaryText)
                Text(value)
                    .leafyBody()
                    .foregroundStyle(AppTheme.primaryText)
            }

            Spacer()
        }
        .padding(.vertical, 4)
        .contentShape(Rectangle())
    }

    private func combinedDate(date: Date, time: Date) -> Date {
        let calendar = Calendar.current
        let dateComponents = calendar.dateComponents([.year, .month, .day], from: date)
        let timeComponents = calendar.dateComponents([.hour, .minute], from: time)
        return calendar.date(
            from: DateComponents(
                year: dateComponents.year,
                month: dateComponents.month,
                day: dateComponents.day,
                hour: timeComponents.hour,
                minute: timeComponents.minute
            )
        ) ?? date
    }

    private func semesterWeekAndDayIfSupported(for date: Date) -> (week: Int, day: Int)? {
        let calendar = Calendar.current
        let start = calendar.startOfDay(for: SemesterConfig.startOfSemesterDate)
        let current = calendar.startOfDay(for: date)
        let days = calendar.dateComponents([.day], from: start, to: current).day ?? 0
        guard days >= 0, days < SemesterConfig.supportedWeeks * 7 else { return nil }
        let weekday = calendar.component(.weekday, from: current)
        return (days / 7 + 1, ((weekday + 5) % 7) + 1)
    }
}

struct CourseDetailSheet: View {
    private enum NoteScope: String, CaseIterable, Identifiable {
        case occurrence
        case course

        var id: String { rawValue }

        var title: String {
            switch self {
            case .occurrence:
                return L10n.text("仅本次课")
            case .course:
                return L10n.text("所有这门课")
            }
        }
    }

    let context: SelectedCourseContext

    @Environment(\.leafyLanguage) private var leafyLanguage
    @Environment(\.modelContext) private var modelContext
    @Environment(\.leafyThemeColorPreference) private var themeColorPreference
    @Query private var allCourses: [Course]
    @Query private var notes: [CourseNote]
    @Query private var occurrenceNotes: [CourseOccurrenceNote]
    @Query private var reminderSettings: [CourseReminderSetting]

    @State private var noteText = ""
    @State private var selectedNoteScope: NoteScope = .occurrence
    @State private var selectedReminderOption: TimetableReminderOption = .none
    @State private var customReminderMinutes = 20
    @State private var selectedReminderAnchorPeriod: Int?
    @State private var operationAlert: LeafyOperationAlert?

    private var course: Course {
        context.course
    }

    var body: some View {
        NavigationStack {
            ScrollView {
                VStack(alignment: .leading, spacing: AppSpacing.card) {
                    VStack(alignment: .leading, spacing: 10) {
                        Text(course.displayCourseName)
                            .title1()

                        CourseOccurrenceProgressView(
                            occurrences: aggregateOccurrences,
                            selectedOccurrence: selectedCourseOccurrence
                        )
                    }
                    .padding(20)
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .leafyCardStyle()

                    CourseDetailRow(title: "教室", value: course.locationText, icon: "mappin.and.ellipse")
                    CourseDetailRow(title: "节次", value: course.durationTextWithTime, icon: "clock")
                    CourseDetailRow(title: "教师", value: course.teacher.isEmpty ? L10n.text("未填写") : course.teacher, icon: "person")
                    CourseDetailRow(title: "周次", value: course.weeksText, icon: "calendar")

                    VStack(alignment: .leading, spacing: 12) {
                        Text("课程备注")
                            .leafyHeadline()

                        Picker("备注范围", selection: $selectedNoteScope) {
                            ForEach(NoteScope.allCases) { scope in
                                Text(scope.title).tag(scope)
                            }
                        }
                        .pickerStyle(.segmented)
                        .onChange(of: selectedNoteScope) { _, _ in
                            syncNoteTextForSelectedScope()
                        }

                        TextField("作业、考试、分组或老师要求", text: $noteText, axis: .vertical)
                            .lineLimit(4, reservesSpace: true)
                            .padding(14)
                            .background(AppTheme.fill, in: RoundedRectangle(cornerRadius: AppRadius.medium, style: .continuous))

                        HStack(spacing: 12) {
                            Button {
                                saveNote()
                            } label: {
                                Label("保存备注", systemImage: "checkmark")
                                    .leafyBody()
                                    .frame(maxWidth: .infinity)
                            }
                            .buttonStyle(.borderedProminent)
                            .tint(AppTheme.accent(for: themeColorPreference))

                            if hasSelectedNote {
                                Button(role: .destructive) {
                                    deleteSelectedNote()
                                } label: {
                                    Label("删除备注", systemImage: "trash")
                                        .leafyBody()
                                        .frame(maxWidth: .infinity)
                                }
                                .buttonStyle(.bordered)
                            }
                        }

                        Text(selectedNoteScope == .occurrence ? "只会显示在本周这一次课上。" : "会显示在这门课的所有周次上。")
                            .microCaption()
                            .foregroundStyle(AppTheme.secondaryText)
                    }
                    .padding(18)
                    .leafyCardStyle()

                    VStack(alignment: .leading, spacing: 12) {
                        Text("课前提醒")
                            .leafyHeadline()

                        TimetableReminderOptionPicker(
                            selectedOption: $selectedReminderOption,
                            customMinutes: $customReminderMinutes
                        )

                        if selectedReminderOption != .none && reminderAnchorPeriods.count > 1 {
                            Picker("提醒锚点", selection: reminderAnchorBinding) {
                                ForEach(reminderAnchorPeriods, id: \.self) { period in
                                    Text("第 \(period) 节开始前").tag(period)
                                }
                            }
                            .pickerStyle(.menu)
                        }

                        Button {
                            Task { await saveReminder() }
                        } label: {
                            Label("应用提醒", systemImage: "bell")
                                .leafyBody()
                                .frame(maxWidth: .infinity)
                        }
                        .buttonStyle(.bordered)
                        .tint(AppTheme.accent(for: themeColorPreference))

                        Text("提醒只保存在本机，会为这门课尚未开始的周次创建本地通知。")
                            .microCaption()
                            .foregroundStyle(AppTheme.secondaryText)
                    }
                    .padding(18)
                    .leafyCardStyle()
                }
                .padding(AppSpacing.page)
            }
            .background(LeafyPageBackground())
            .navigationTitle("课程详情")
            .leafyInlineNavigationTitle()
            .task {
                syncLocalState()
            }
            .leafyOperationAlert($operationAlert)
        }
    }

    private var courseKey: String {
        course.stableCourseKey
    }

    private var occurrenceKey: String {
        course.occurrenceKey(week: context.week)
    }

    private var selectedCourseOccurrence: CourseProgressOccurrence {
        CourseProgressOccurrence(
            week: context.week,
            dayOfWeek: course.dayOfWeek,
            firstPeriod: course.firstPeriodForProgress
        )
    }

    private var aggregateOccurrences: [CourseProgressOccurrence] {
        let courseNameKey = course.normalizedCourseNameForProgress
        guard !courseNameKey.isEmpty else {
            return [selectedCourseOccurrence]
        }

        let occurrenceSet = Set(
            allCourses
                .filter { $0.normalizedCourseNameForProgress == courseNameKey }
                .flatMap { course in
                    course.weeks.map { week in
                        CourseProgressOccurrence(
                            week: week,
                            dayOfWeek: course.dayOfWeek,
                            firstPeriod: course.firstPeriodForProgress
                        )
                    }
                }
        )

        let sortedOccurrences = occurrenceSet.sorted()
        return sortedOccurrences.isEmpty ? [selectedCourseOccurrence] : sortedOccurrences
    }

    private var noteRecord: CourseNote? {
        notes.first { $0.courseKey == courseKey }
    }

    private var occurrenceNoteRecord: CourseOccurrenceNote? {
        occurrenceNotes.first { $0.occurrenceKey == occurrenceKey }
    }

    private var hasSelectedNote: Bool {
        switch selectedNoteScope {
        case .occurrence:
            return occurrenceNoteRecord != nil
        case .course:
            return noteRecord != nil
        }
    }

    private var reminderRecord: CourseReminderSetting? {
        reminderSettings.first { $0.courseKey == courseKey }
    }

    private var reminderAnchorPeriods: [Int] {
        Array(Set(course.duration)).sorted()
    }

    private var fallbackReminderAnchorPeriod: Int {
        reminderAnchorPeriods.first ?? 1
    }

    private var reminderAnchorBinding: Binding<Int> {
        Binding(
            get: {
                selectedReminderAnchorPeriod ?? fallbackReminderAnchorPeriod
            },
            set: { newValue in
                selectedReminderAnchorPeriod = newValue
            }
        )
    }

    private func syncLocalState() {
        if occurrenceNoteRecord != nil {
            selectedNoteScope = .occurrence
        } else if noteRecord != nil {
            selectedNoteScope = .course
        } else {
            selectedNoteScope = .occurrence
        }
        syncNoteTextForSelectedScope()
        let minutes = reminderRecord?.minutesBefore ?? 0
        selectedReminderOption = TimetableReminderOption.option(for: minutes)
        customReminderMinutes = TimetableReminderOption.customMinutes(for: minutes)
        selectedReminderAnchorPeriod = TimetableNotificationManager.resolvedAnchorPeriod(
            reminderRecord?.anchorPeriod,
            for: course
        )
    }

    private func syncNoteTextForSelectedScope() {
        switch selectedNoteScope {
        case .occurrence:
            noteText = occurrenceNoteRecord?.text ?? ""
        case .course:
            noteText = noteRecord?.text ?? ""
        }
    }

    private func saveNote() {
        let trimmed = noteText.trimmingCharacters(in: .whitespacesAndNewlines)
        switch selectedNoteScope {
        case .occurrence:
            saveOccurrenceNote(trimmed)
        case .course:
            saveCourseNote(trimmed)
        }

        try? modelContext.save()
        LeafyWidgetSnapshotBuilder.publish(from: modelContext, isAuthenticated: ActiveCampusContext.networkManager.hasCachedIdentity || ReviewDemoMode.isEnabled)
        operationAlert = .success(
            trimmed.isEmpty
                ? L10n.text("备注已清空！", language: leafyLanguage)
                : L10n.text("备注已保存！", language: leafyLanguage)
        )
    }

    private func deleteSelectedNote() {
        switch selectedNoteScope {
        case .occurrence:
            if let note = occurrenceNoteRecord {
                modelContext.delete(note)
            }
        case .course:
            if let note = noteRecord {
                modelContext.delete(note)
            }
        }

        noteText = ""
        try? modelContext.save()
        LeafyWidgetSnapshotBuilder.publish(from: modelContext, isAuthenticated: ActiveCampusContext.networkManager.hasCachedIdentity || ReviewDemoMode.isEnabled)
        operationAlert = .success(L10n.text("备注已删除！", language: leafyLanguage))
    }

    private func saveCourseNote(_ trimmed: String) {
        if let note = noteRecord {
            if trimmed.isEmpty {
                modelContext.delete(note)
            } else {
                note.text = trimmed
                note.updatedAt = Date()
            }
        } else if !trimmed.isEmpty {
            modelContext.insert(CourseNote(courseKey: courseKey, text: trimmed))
        }
    }

    private func saveOccurrenceNote(_ trimmed: String) {
        if let note = occurrenceNoteRecord {
            if trimmed.isEmpty {
                modelContext.delete(note)
            } else {
                note.text = trimmed
                note.updatedAt = Date()
            }
        } else if !trimmed.isEmpty {
            modelContext.insert(
                CourseOccurrenceNote(
                    courseKey: courseKey,
                    occurrenceKey: occurrenceKey,
                    week: context.week,
                    dayOfWeek: course.dayOfWeek,
                    text: trimmed
                )
            )
        }
    }

    @MainActor
    private func saveReminder() async {
        let reminderMinutes = selectedReminderOption.minutes(customMinutes: customReminderMinutes)
        let anchorPeriod = TimetableNotificationManager.resolvedAnchorPeriod(selectedReminderAnchorPeriod, for: course)

        if let setting = reminderRecord {
            setting.minutesBefore = reminderMinutes
            setting.anchorPeriod = anchorPeriod
            setting.updatedAt = Date()
        } else {
            modelContext.insert(
                CourseReminderSetting(
                    courseKey: courseKey,
                    minutesBefore: reminderMinutes,
                    anchorPeriod: anchorPeriod
                )
            )
        }

        do {
            try? modelContext.save()
            try await TimetableNotificationManager.applyReminder(
                minutesBefore: reminderMinutes,
                anchorPeriod: anchorPeriod,
                course: course
            )
            LeafyWidgetSnapshotBuilder.publish(from: modelContext, isAuthenticated: ActiveCampusContext.networkManager.hasCachedIdentity || ReviewDemoMode.isEnabled)
            operationAlert = .success(
                reminderMinutes == 0
                    ? L10n.text("已关闭这门课的提醒！", language: leafyLanguage)
                    : L10n.text("提醒已设置！", language: leafyLanguage)
            )
        } catch {
            operationAlert = .failure(error.localizedDescription)
        }
    }
}

struct CourseOccurrenceProgressView: View {
    @Environment(\.leafyThemeColorPreference) private var themeColorPreference

    let occurrences: [CourseProgressOccurrence]
    let selectedOccurrence: CourseProgressOccurrence

    private var sortedOccurrences: [CourseProgressOccurrence] {
        occurrences.sorted()
    }

    private var occurrenceIndex: Int? {
        sortedOccurrences.firstIndex(of: selectedOccurrence).map { $0 + 1 }
    }

    private var totalOccurrences: Int {
        sortedOccurrences.count
    }

    private var progress: Double {
        guard let occurrenceIndex, totalOccurrences > 0 else { return 0 }
        return Double(occurrenceIndex) / Double(totalOccurrences)
    }

    private var statusText: String {
        guard let occurrenceIndex, totalOccurrences > 0 else { return L10n.text("暂无课程进度") }
        return L10n.text("第 %d / %d 次课", occurrenceIndex, totalOccurrences)
    }

    private var progressText: String {
        "\(Int((progress * 100).rounded()))%"
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            HStack {
                Text(statusText)
                    .microCaption()
                    .foregroundStyle(AppTheme.secondaryText)
                Spacer()
                Text(progressText)
                    .microCaption()
                    .foregroundStyle(AppTheme.tertiaryText)
            }

            ProgressView(value: progress)
                .tint(AppTheme.accent(for: themeColorPreference))
                .progressViewStyle(.linear)
        }
        .padding(.top, 2)
    }
}

struct CourseDetailRow: View {
    @Environment(\.leafyLanguage) private var leafyLanguage

    let title: String
    let value: String
    let icon: String

    var body: some View {
        HStack(alignment: .top, spacing: 14) {
            LeafyIconBadge(systemName: icon)

            VStack(alignment: .leading, spacing: 4) {
                Text(L10n.text(title, language: leafyLanguage))
                    .microCaption()
                    .foregroundStyle(AppTheme.secondaryText)
                Text(value)
                    .leafyBody()
                    .foregroundStyle(AppTheme.primaryText)
            }

            Spacer()
        }
        .padding(18)
        .leafyCardStyle()
    }
}

extension Course {
    var displayCourseName: String {
        courseName
            .replacingOccurrences(of: "（必修）", with: "")
            .replacingOccurrences(of: "(必修)", with: "")
            .replacingOccurrences(of: "（辅修）", with: "")
            .replacingOccurrences(of: "(辅修)", with: "")
            .trimmingCharacters(in: .whitespacesAndNewlines)
    }

    var locationText: String {
        formattedLocationText
    }

    var timetableCardLocationText: String {
        let cleanLocation = location.trimmingCharacters(in: .whitespacesAndNewlines)
        let cleanRoom = room.trimmingCharacters(in: .whitespacesAndNewlines)

        guard !cleanLocation.isEmpty, !cleanRoom.isEmpty else {
            return locationText
        }

        let compactLocation = cleanLocation.replacingOccurrences(of: "\\s+", with: "", options: .regularExpression)
        let compactRoom = cleanRoom.replacingOccurrences(of: "\\s+", with: "", options: .regularExpression)

        if compactLocation == compactRoom || compactLocation.hasSuffix(compactRoom) {
            return cleanLocation
        }

        if compactRoom.hasPrefix(compactLocation) {
            return cleanRoom
        }

        if compactLocation.hasPrefix("学研"), compactLocation.hasSuffix("座") {
            let seatPrefix = String(compactLocation.dropLast())
            return "\(seatPrefix)\(compactRoom)"
        }

        return "\(compactLocation)\(compactRoom)"
    }

    var durationText: String {
        guard let start = duration.min(), let end = duration.max() else { return L10n.text("未填写") }
        if start == end { return L10n.text("第 %d 节", start) }
        return L10n.text("第 %d-%d 节", start, end)
    }

    var durationTextWithTime: String {
        let periodLines = duration
            .sorted()
            .compactMap { period -> String? in
                guard let slot = TimetablePeriodSchedule.slot(for: period) else {
                    return nil
                }
                return "\(L10n.text("第 %d 节", period)) \(slot.startText)-\(slot.endText)"
            }

        guard !periodLines.isEmpty else {
            return durationText
        }

        return periodLines.joined(separator: "\n")
    }

    var weeksText: String {
        let sortedWeeks = weeks.sorted()
        guard let first = sortedWeeks.first, let last = sortedWeeks.last else { return L10n.text("未填写") }
        if first == last { return L10n.text("第 %d 周", first) }
        return L10n.text("第 %d-%d 周", first, last)
    }
}
