import Foundation

struct TimetableScheduleProjectionSnapshot {
    static let empty = TimetableScheduleProjectionSnapshot(
        signature: TimetableScheduleProjectionSignature(countdowns: [], exams: []),
        countdownsByDay: [:],
        examsByDay: [:]
    )

    let signature: TimetableScheduleProjectionSignature
    private let countdownsByDay: [TimetableScheduleProjectionDayKey: [TimetableCountdownProjection]]
    private let examsByDay: [TimetableScheduleProjectionDayKey: [TimetableExamProjection]]

    static func make(
        countdownEvents: [CustomScheduleEvent],
        exams: [ExamArrangement]
    ) -> TimetableScheduleProjectionSnapshot {
        let countdowns = countdownEvents
            .compactMap(\.timetableProjection)
            .sorted { lhs, rhs in
                if lhs.week != rhs.week { return lhs.week < rhs.week }
                if lhs.dayOfWeek != rhs.dayOfWeek { return lhs.dayOfWeek < rhs.dayOfWeek }
                if lhs.period != rhs.period { return lhs.period < rhs.period }
                return lhs.targetDate < rhs.targetDate
            }
        let exams = exams
            .compactMap(\.timetableProjection)
            .sorted { lhs, rhs in
                if lhs.week != rhs.week { return lhs.week < rhs.week }
                if lhs.dayOfWeek != rhs.dayOfWeek { return lhs.dayOfWeek < rhs.dayOfWeek }
                if lhs.period != rhs.period { return lhs.period < rhs.period }
                return lhs.startsAt < rhs.startsAt
            }

        return TimetableScheduleProjectionSnapshot(
            signature: TimetableScheduleProjectionSignature(
                countdowns: countdowns,
                exams: exams
            ),
            countdownsByDay: Dictionary(grouping: countdowns) {
                TimetableScheduleProjectionDayKey(week: $0.week, day: $0.dayOfWeek)
            },
            examsByDay: Dictionary(grouping: exams) {
                TimetableScheduleProjectionDayKey(week: $0.week, day: $0.dayOfWeek)
            }
        )
    }

    func countdowns(week: Int, day: Int) -> [TimetableCountdownProjection] {
        countdownsByDay[TimetableScheduleProjectionDayKey(week: week, day: day)] ?? []
    }

    func exams(week: Int, day: Int) -> [TimetableExamProjection] {
        examsByDay[TimetableScheduleProjectionDayKey(week: week, day: day)] ?? []
    }
}

struct TimetableScheduleProjectionSignature: Hashable {
    let countdowns: [TimetableCountdownProjection]
    let exams: [TimetableExamProjection]
}

struct TimetableScheduleProjectionDayKey: Hashable {
    let week: Int
    let day: Int
}
