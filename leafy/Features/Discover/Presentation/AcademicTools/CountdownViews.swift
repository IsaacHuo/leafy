import SwiftData
import SwiftUI

struct CustomScheduleListView: View {
    @Environment(\.leafyLanguage) private var leafyLanguage
    @Environment(\.modelContext) private var modelContext
    @Query private var timetableEvents: [TimetableCellReminder]

    @State private var importantDateEvents: [CustomScheduleEvent] = []
    @State private var editorPresentation: CustomScheduleEditorPresentation?
    @State private var operationAlert: LeafyOperationAlert?

    private var sortedItems: [CustomScheduleListItem] {
        (timetableEvents.map(CustomScheduleListItem.timetable) + importantDateEvents.map(CustomScheduleListItem.importantDate))
            .sorted { lhs, rhs in
                if lhs.startDate != rhs.startDate { return lhs.startDate < rhs.startDate }
                return lhs.title.localizedCompare(rhs.title) == .orderedAscending
            }
    }

    var body: some View {
        AcademicDetailScrollContainer {
            if sortedItems.isEmpty {
                AcademicDetailCard {
                    ContentUnavailableView("暂无自定日程", systemImage: "calendar.badge.plus")
                }
            } else {
                ForEach(sortedItems) { item in
                    AcademicDetailCard {
                        CustomScheduleListRow(
                            item: item,
                            onEdit: { edit(item) },
                            onDelete: { delete(item) }
                        )
                    }
                }
            }

            AcademicDetailFooterText(text: "日程仅保存在当前设备。学期内自动显示在课表，学期外自动显示倒计时。")
        }
        .navigationTitle("自定日程")
        .leafyInlineNavigationTitle()
        .toolbar {
            ToolbarItem(placement: .leafyTrailing) {
                Button {
                    editorPresentation = .importantDate(nil, defaultContext: defaultTimetableContext(), allowsModeSelection: true)
                } label: {
                    Image(systemName: "plus")
                }
                .accessibilityLabel("添加自定日程")
            }
        }
        .sheet(item: $editorPresentation, onDismiss: reloadImportantDates) { presentation in
            CustomScheduleEditorSheet(presentation: presentation)
                .presentationDetents([.medium, .large])
        }
        .onAppear(perform: reloadImportantDates)
        .onReceive(NotificationCenter.default.publisher(for: .customScheduleEventsDidChange)) { _ in
            reloadImportantDates()
        }
        .leafyOperationAlert($operationAlert)
    }

    private func reloadImportantDates() {
        importantDateEvents = CustomScheduleStore.load()
    }

    private func edit(_ item: CustomScheduleListItem) {
        switch item {
        case .timetable(let reminder):
            editorPresentation = .timetable(context(for: reminder), allowsModeSelection: false)
        case .importantDate(let event):
            editorPresentation = .importantDate(event, defaultContext: defaultTimetableContext(for: event.startsAt), allowsModeSelection: false)
        }
    }

    @MainActor
    private func delete(_ item: CustomScheduleListItem) {
        switch item {
        case .timetable(let reminder):
            TimetableNotificationManager.cancelReminder(for: reminder)
            modelContext.delete(reminder)
            do {
                try modelContext.save()
                operationAlert = .success(L10n.text("日程已删除！", language: leafyLanguage))
            } catch {
                operationAlert = .failure(error.localizedDescription)
            }
        case .importantDate(let event):
            var events = CustomScheduleStore.load()
            events.removeAll { $0.id == event.id }
            TimetableNotificationManager.cancelReminder(for: event)
            CustomScheduleStore.save(events)
            importantDateEvents = events
            operationAlert = .success(L10n.text("日程已删除！", language: leafyLanguage))
        }
    }

    private func context(for reminder: TimetableCellReminder) -> TimetableCellReminderContext {
        TimetableCellReminderContext(
            week: reminder.week,
            day: reminder.dayOfWeek,
            period: reminder.displayStartPeriod,
            date: reminder.resolvedStartDate ?? defaultDate(week: reminder.week, day: reminder.dayOfWeek, period: reminder.displayStartPeriod),
            occupiedPeriods: [],
            totalPeriods: TimetablePeriodSchedule.slots.count,
            reminder: reminder,
            allowsDateSelection: true
        )
    }

    private func defaultTimetableContext(for date: Date = Date()) -> TimetableCellReminderContext {
        let weekAndDay = semesterWeekAndDayIfSupported(for: date)
            ?? (week: SemesterConfig.currentWeek(), day: defaultScheduleDay)
        let period = min(max(TimetablePeriodSchedule.defaultStudyPeriod(for: date), 1), TimetablePeriodSchedule.slots.count)
        return TimetableCellReminderContext(
            week: weekAndDay.week,
            day: weekAndDay.day,
            period: period,
            date: defaultDate(week: weekAndDay.week, day: weekAndDay.day, period: period),
            occupiedPeriods: [],
            totalPeriods: TimetablePeriodSchedule.slots.count,
            reminder: nil,
            allowsDateSelection: true
        )
    }

    private func defaultDate(week: Int, day: Int, period: Int) -> Date {
        TimetablePeriodSchedule.startDate(week: week, dayOfWeek: day, period: period)
            ?? Date()
    }

    private var defaultScheduleDay: Int {
        let weekday = Calendar.current.component(.weekday, from: Date())
        return weekday == 1 ? 7 : weekday - 1
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

struct CustomCountdownListView: View {
    var body: some View {
        CustomScheduleListView()
    }
}

private enum CustomScheduleListItem: Identifiable {
    case timetable(TimetableCellReminder)
    case importantDate(CustomScheduleEvent)

    var id: String {
        switch self {
        case .timetable(let reminder):
            return "timetable-\(reminder.id.uuidString)"
        case .importantDate(let event):
            return "important-\(event.id)"
        }
    }

    var title: String {
        switch self {
        case .timetable(let reminder):
            return reminder.title
        case .importantDate(let event):
            return event.title
        }
    }

    var badge: String {
        switch self {
        case .timetable:
            return "课表显示"
        case .importantDate(let event):
            return event.timetableProjection == nil ? "倒计时" : "课表显示"
        }
    }

    var startDate: Date {
        switch self {
        case .timetable(let reminder):
            return reminder.resolvedStartDate ?? .distantFuture
        case .importantDate(let event):
            return event.startsAt
        }
    }

    var endDate: Date? {
        switch self {
        case .timetable(let reminder):
            return reminder.resolvedEndDate
        case .importantDate(let event):
            return event.endsAt
        }
    }

    var location: String {
        switch self {
        case .timetable(let reminder):
            return reminder.locationText
        case .importantDate(let event):
            return event.locationText
        }
    }

    var note: String {
        switch self {
        case .timetable(let reminder):
            return reminder.noteText
        case .importantDate(let event):
            return event.noteText
        }
    }

    var minutesBefore: Int {
        switch self {
        case .timetable(let reminder):
            return reminder.minutesBefore
        case .importantDate(let event):
            return event.minutesBefore
        }
    }

    var systemImage: String {
        switch self {
        case .timetable:
            return "calendar.badge.clock"
        case .importantDate(let event):
            return event.timetableProjection == nil ? "timer" : "calendar.badge.clock"
        }
    }

    var tint: Color {
        switch self {
        case .timetable:
            return AppTheme.accent
        case .importantDate(let event):
            return event.timetableProjection == nil ? AppTheme.warning : AppTheme.accent
        }
    }
}

private struct CustomScheduleListRow: View {
    let item: CustomScheduleListItem
    let onEdit: () -> Void
    let onDelete: () -> Void

    var body: some View {
        HStack(alignment: .top, spacing: AppSpacing.compact) {
            LeafyIconBadge(systemName: item.systemImage, tint: item.tint)

            VStack(alignment: .leading, spacing: 8) {
                HStack(alignment: .firstTextBaseline) {
                    Text(item.title)
                        .font(.headline)
                        .foregroundStyle(AppTheme.primaryText)
                        .fixedSize(horizontal: false, vertical: true)

                    Spacer(minLength: AppSpacing.micro)

                    Text(item.badge)
                        .font(.caption.weight(.semibold))
                        .foregroundStyle(AppTheme.secondaryText)
                        .padding(.horizontal, 8)
                        .padding(.vertical, 4)
                        .background(AppTheme.softFill, in: Capsule())
                }

                HStack(alignment: .center, spacing: AppSpacing.micro) {
                    Text(timeText)
                        .font(.subheadline)
                        .foregroundStyle(AppTheme.secondaryText)

                    Spacer(minLength: AppSpacing.micro)

                    HStack(spacing: AppSpacing.micro) {
                        Button(action: onEdit) {
                            Image(systemName: "pencil")
                                .font(.system(size: 14, weight: .semibold))
                                .foregroundStyle(AppTheme.accentEmphasis)
                                .frame(width: 34, height: 34)
                                .background(AppTheme.softFill, in: Circle())
                        }
                        .buttonStyle(.plain)
                        .accessibilityLabel("编辑自定日程")

                        Button(role: .destructive, action: onDelete) {
                            Image(systemName: "trash")
                                .font(.system(size: 14, weight: .semibold))
                                .foregroundStyle(AppTheme.danger)
                                .frame(width: 34, height: 34)
                                .background(AppTheme.danger.opacity(0.1), in: Circle())
                        }
                        .buttonStyle(.plain)
                        .accessibilityLabel("删除自定日程")
                    }
                }

                if !detailText.isEmpty {
                    Text(detailText)
                        .font(.footnote)
                        .foregroundStyle(AppTheme.secondaryText)
                        .fixedSize(horizontal: false, vertical: true)
                }

                Text(CountdownEventRow.countdownDescription(for: item.startDate))
                    .font(.title3.weight(.bold))
                    .foregroundStyle(AppTheme.primaryText)
            }
        }
    }

    private var timeText: String {
        if let endDate = item.endDate, endDate > item.startDate {
            return "\(DateFormatters.headerWithTime.string(from: item.startDate)) - \(DateFormatters.timeOnly.string(from: endDate))"
        }
        return DateFormatters.headerWithTime.string(from: item.startDate)
    }

    private var detailText: String {
        var parts: [String] = []
        if !item.location.isEmpty {
            parts.append(item.location)
        }
        if item.minutesBefore > 0 {
            parts.append("提前 \(item.minutesBefore) 分钟提醒")
        }
        if !item.note.isEmpty {
            parts.append(item.note)
        }
        return parts.joined(separator: " · ")
    }
}

struct CountdownEventRow: View {
    let title: String
    let badge: String
    let targetDate: Date

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            HStack {
                Text(title)
                    .font(.headline)
                Spacer()
                Text(badge)
                    .font(.caption.weight(.semibold))
                    .padding(.horizontal, 8)
                    .padding(.vertical, 4)
                    .background(AppTheme.softFill, in: Capsule())
            }
            Text(DateFormatters.headerWithTime.string(from: targetDate))
                .font(.subheadline)
                .foregroundStyle(.secondary)
            Text(Self.countdownDescription(for: targetDate))
                .font(.title3.weight(.bold))
        }
        .padding(.vertical, 6)
    }

    static func countdownDescription(for targetDate: Date) -> String {
        let seconds = Int(targetDate.timeIntervalSinceNow)
        if seconds <= 0 { return "已开始" }
        let days = seconds / 86_400
        let hours = (seconds % 86_400) / 3_600
        if days > 0 {
            return "还有 \(days) 天 \(hours) 小时"
        }
        let minutes = (seconds % 3_600) / 60
        return "还有 \(hours) 小时 \(minutes) 分钟"
    }
}
