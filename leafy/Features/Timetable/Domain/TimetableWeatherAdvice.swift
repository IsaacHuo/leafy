import Foundation

nonisolated enum TimetableWeatherScheduleItemKind: String, Sendable {
    case course
    case reminder
    case exam
}

nonisolated struct TimetableWeatherScheduleItem: Equatable, Sendable {
    let title: String
    let kind: TimetableWeatherScheduleItemKind
    let startsAt: Date
    let endsAt: Date

    var displayTitle: String {
        title.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty ? "日程" : title
    }

    var timeText: String {
        "\(Self.clockText(for: startsAt))-\(Self.clockText(for: endsAt))"
    }

    private static func clockText(for date: Date) -> String {
        let components = Calendar.current.dateComponents([.hour, .minute], from: date)
        return String(format: "%02d:%02d", components.hour ?? 0, components.minute ?? 0)
    }
}

nonisolated struct TimetableWeatherSuggestion: Identifiable, Equatable, Sendable {
    let id: String
    let systemImage: String
    let title: String
    let detail: String
}

nonisolated struct TimetableWeatherAdviceSummary: Equatable, Sendable {
    let suggestions: [TimetableWeatherSuggestion]
    let scheduleItems: [TimetableWeatherScheduleItem]
}

nonisolated enum TimetableWeatherAdviceBuilder {
    static func scheduleItems(
        courses: [Course],
        cellReminders: [TimetableCellReminder],
        exams: [ExamArrangement],
        currentWeek: Int,
        now: Date = Date(),
        calendar: Calendar = .current
    ) -> [TimetableWeatherScheduleItem] {
        let today = timetableDayOfWeek(for: now, calendar: calendar)
        var items: [TimetableWeatherScheduleItem] = []

        for course in courses where course.weeks.contains(currentWeek) && course.dayOfWeek == today {
            guard let startsAt = TimetablePeriodSchedule.startDate(for: course, week: currentWeek),
                  let endsAt = TimetablePeriodSchedule.endDate(for: course, week: currentWeek),
                  endsAt > now else {
                continue
            }
            items.append(
                TimetableWeatherScheduleItem(
                    title: course.courseName,
                    kind: .course,
                    startsAt: startsAt,
                    endsAt: endsAt
                )
            )
        }

        for reminder in cellReminders where reminder.week == currentWeek && reminder.dayOfWeek == today {
            guard let startsAt = reminder.resolvedStartDate,
                  let endsAt = reminder.resolvedEndDate,
                  endsAt > now else {
                continue
            }
            items.append(
                TimetableWeatherScheduleItem(
                    title: reminder.title,
                    kind: .reminder,
                    startsAt: startsAt,
                    endsAt: endsAt
                )
            )
        }

        for exam in exams {
            guard let startsAt = examDate(date: exam.date, time: exam.start),
                  let endsAt = examDate(date: exam.date, time: exam.end),
                  calendar.isDate(startsAt, inSameDayAs: now),
                  endsAt > now else {
                continue
            }
            items.append(
                TimetableWeatherScheduleItem(
                    title: exam.name,
                    kind: .exam,
                    startsAt: startsAt,
                    endsAt: endsAt
                )
            )
        }

        return items.sorted {
            if $0.startsAt != $1.startsAt {
                return $0.startsAt < $1.startsAt
            }
            return $0.displayTitle.localizedCompare($1.displayTitle) == .orderedAscending
        }
    }

    static func makeSummary(
        snapshot: TimetableWeatherSnapshot,
        scheduleItems: [TimetableWeatherScheduleItem],
        now: Date = Date(),
        calendar: Calendar = .current
    ) -> TimetableWeatherAdviceSummary {
        let scopedHours = weatherHoursForAdvice(
            snapshot: snapshot,
            scheduleItems: scheduleItems,
            now: now,
            calendar: calendar
        )
        var suggestions: [TimetableWeatherSuggestion] = []

        if let rainSuggestion = rainSuggestion(hours: scopedHours, scheduleItems: scheduleItems) {
            suggestions.append(rainSuggestion)
        }

        if let temperatureSuggestion = temperatureSuggestion(hours: scopedHours, scheduleItems: scheduleItems) {
            suggestions.append(temperatureSuggestion)
        }

        if let uvSuggestion = uvSuggestion(hours: scopedHours, scheduleItems: scheduleItems) {
            suggestions.append(uvSuggestion)
        }

        if suggestions.isEmpty {
            suggestions.append(defaultSuggestion(scheduleItems: scheduleItems))
        }

        return TimetableWeatherAdviceSummary(
            suggestions: Array(suggestions.prefix(3)),
            scheduleItems: scheduleItems
        )
    }

    private static func weatherHoursForAdvice(
        snapshot: TimetableWeatherSnapshot,
        scheduleItems: [TimetableWeatherScheduleItem],
        now: Date,
        calendar: Calendar
    ) -> [TimetableHourlyWeather] {
        let futureHours = snapshot.hourlyForecast.filter { hour in
            hour.date.addingTimeInterval(60 * 60) > now
                && calendar.isDate(hour.date, inSameDayAs: now)
        }

        guard !scheduleItems.isEmpty else {
            return Array(futureHours.prefix(12))
        }

        let matched = futureHours.filter { hour in
            scheduleItems.contains { overlaps(hour: hour, item: $0) }
        }
        return matched.isEmpty ? futureHours : matched
    }

    private static func rainSuggestion(
        hours: [TimetableHourlyWeather],
        scheduleItems: [TimetableWeatherScheduleItem]
    ) -> TimetableWeatherSuggestion? {
        guard let hour = hours.first(where: { isWetWeather($0) || $0.precipitationChance >= 0.35 }) else {
            return nil
        }

        let affectedItem = scheduleItems.first { overlaps(hour: hour, item: $0) }
        let target = affectedItem.map { "\($0.displayTitle)（\($0.timeText)）" } ?? "出门时段"
        let title = isSnow(hour) ? "留意雨雪" : "记得带伞"
        let detail = "\(target) 附近可能有\(hour.condition)，路上留点余量。"

        return TimetableWeatherSuggestion(
            id: "rain",
            systemImage: isSnow(hour) ? "snowflake" : "umbrella",
            title: title,
            detail: detail
        )
    }

    private static func temperatureSuggestion(
        hours: [TimetableHourlyWeather],
        scheduleItems: [TimetableWeatherScheduleItem]
    ) -> TimetableWeatherSuggestion? {
        guard let coldest = hours.min(by: { $0.temperature < $1.temperature }),
              let hottest = hours.max(by: { $0.temperature < $1.temperature }) else {
            return nil
        }

        if coldest.temperature <= 8 {
            let target = scheduleItems.first { overlaps(hour: coldest, item: $0) }?.displayTitle ?? "外出"
            return TimetableWeatherSuggestion(
                id: "cold",
                systemImage: "thermometer.low",
                title: "多穿一层",
                detail: "\(target) 前后约 \(Int(coldest.temperature.rounded()))°，别被早晚温差偷袭。"
            )
        }

        if hottest.temperature >= 30 {
            let target = scheduleItems.first { overlaps(hour: hottest, item: $0) }?.displayTitle ?? "外出"
            return TimetableWeatherSuggestion(
                id: "heat",
                systemImage: "drop",
                title: "补水避晒",
                detail: "\(target) 前后约 \(Int(hottest.temperature.rounded()))°，带水会舒服很多。"
            )
        }

        return nil
    }

    private static func uvSuggestion(
        hours: [TimetableHourlyWeather],
        scheduleItems: [TimetableWeatherScheduleItem]
    ) -> TimetableWeatherSuggestion? {
        guard !scheduleItems.isEmpty,
              let uvHour = hours.first(where: { $0.isDaylight && $0.uvIndex >= 6 }) else {
            return nil
        }

        let target = scheduleItems.first { overlaps(hour: uvHour, item: $0) }?.displayTitle ?? "白天课程"
        return TimetableWeatherSuggestion(
            id: "uv",
            systemImage: "sun.max",
            title: "注意防晒",
            detail: "\(target) 时段紫外线偏强，帽子或防晒会更稳。"
        )
    }

    private static func defaultSuggestion(
        scheduleItems: [TimetableWeatherScheduleItem]
    ) -> TimetableWeatherSuggestion {
        if scheduleItems.isEmpty {
            return TimetableWeatherSuggestion(
                id: "clear-empty",
                systemImage: "sparkles",
                title: "今天后续无课",
                detail: "出门前看一眼天气就好，今天不用按课表赶路。"
            )
        }

        return TimetableWeatherSuggestion(
            id: "clear",
            systemImage: "checkmark.circle",
            title: "天气平稳",
            detail: "按课表出门就好，不需要额外准备。"
        )
    }

    private static func overlaps(hour: TimetableHourlyWeather, item: TimetableWeatherScheduleItem) -> Bool {
        let hourEnd = hour.date.addingTimeInterval(60 * 60)
        return hour.date < item.endsAt && hourEnd > item.startsAt
    }

    private static func isWetWeather(_ hour: TimetableHourlyWeather) -> Bool {
        let text = "\(hour.condition) \(hour.symbolName)".lowercased()
        return text.contains("雨")
            || text.contains("雪")
            || text.contains("rain")
            || text.contains("snow")
            || text.contains("drizzle")
            || text.contains("thunder")
            || text.contains("storm")
    }

    private static func isSnow(_ hour: TimetableHourlyWeather) -> Bool {
        let text = "\(hour.condition) \(hour.symbolName)".lowercased()
        return text.contains("雪") || text.contains("snow") || text.contains("sleet")
    }

    private static func timetableDayOfWeek(for date: Date, calendar: Calendar) -> Int {
        let weekday = calendar.component(.weekday, from: date)
        return weekday == 1 ? 7 : weekday - 1
    }

    private static func examDate(date: String, time: String) -> Date? {
        let formatter = DateFormatter()
        formatter.locale = Locale(identifier: "zh_CN")
        formatter.timeZone = TimeZone.current
        formatter.dateFormat = "yyyy-MM-dd HH:mm"
        return formatter.date(from: "\(date) \(time)")
    }
}
