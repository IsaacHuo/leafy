import Foundation

@MainActor
struct WeeklyTimetableProjection {
    let selection: TimetableDaySelection
    let days: [Int]
    let weekCourses: [Course]
    let reminders: [TimetableCellReminder]
    let examProjections: [TimetableExamProjection]

    private let layoutsByDay: [Int: [DayCourseLayout]]
    private let courseNotesByKey: [String: String]
    private let occurrenceNotesByKey: [String: String]

    static func make(
        selection: TimetableDaySelection,
        courses: [Course],
        cellReminders: [TimetableCellReminder],
        exams: [ExamArrangement],
        courseNotes: [CourseNote],
        occurrenceNotes: [CourseOccurrenceNote],
        includesWeekends: Bool
    ) -> WeeklyTimetableProjection {
        let days = Array(1...(includesWeekends ? 7 : 5))
        let visibleDays = Set(days)
        let weekCourses = courses
            .filter { $0.weeks.contains(selection.week) && visibleDays.contains($0.dayOfWeek) }
            .sortedByStartPeriod()
        let layoutsByDay = Dictionary(uniqueKeysWithValues: days.map { day in
            (
                day,
                DayCourseLayoutBuilder.layouts(
                    for: weekCourses
                        .filter { $0.dayOfWeek == day }
                        .sortedByStartPeriod()
                )
            )
        })
        let reminders = cellReminders
            .filter { $0.week == selection.week && visibleDays.contains($0.dayOfWeek) }
            .sorted { lhs, rhs in
                if lhs.dayOfWeek != rhs.dayOfWeek { return lhs.dayOfWeek < rhs.dayOfWeek }
                return lhs.period < rhs.period
            }
        let examProjections = exams
            .compactMap(\.timetableProjection)
            .filter { $0.week == selection.week && visibleDays.contains($0.dayOfWeek) }
            .sorted { lhs, rhs in
                if lhs.dayOfWeek != rhs.dayOfWeek { return lhs.dayOfWeek < rhs.dayOfWeek }
                if lhs.period != rhs.period { return lhs.period < rhs.period }
                return lhs.startsAt < rhs.startsAt
            }

        return WeeklyTimetableProjection(
            selection: selection,
            days: days,
            weekCourses: weekCourses,
            reminders: reminders,
            examProjections: examProjections,
            layoutsByDay: layoutsByDay,
            courseNotesByKey: TimetableNoteResolver.courseNotesByKey(courseNotes),
            occurrenceNotesByKey: TimetableNoteResolver.occurrenceNotesByKey(occurrenceNotes)
        )
    }

    func layouts(for day: Int) -> [DayCourseLayout] {
        layoutsByDay[day] ?? []
    }

    func hasExam(on day: Int) -> Bool {
        examProjections.contains { $0.dayOfWeek == day }
    }

    func hasNote(for course: Course) -> Bool {
        note(for: course) != nil
    }

    func note(for course: Course) -> String? {
        TimetableNoteResolver.effectiveNote(
            for: course,
            week: selection.week,
            courseNotesByKey: courseNotesByKey,
            occurrenceNotesByKey: occurrenceNotesByKey
        )
    }
}
