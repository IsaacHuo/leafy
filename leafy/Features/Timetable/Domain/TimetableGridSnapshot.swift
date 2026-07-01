import Foundation
import os

@MainActor
struct TimetableGridInputSignature: Equatable, Hashable {
    let hidesWeekends: Bool
    let courseSignatures: [CourseSignature]
    let noteSignatures: [NoteSignature]
    let occurrenceNoteSignatures: [OccurrenceNoteSignature]
    let cellReminderSignatures: [CellReminderSignature]

    init(
        courses: [Course],
        notes: [CourseNote],
        occurrenceNotes: [CourseOccurrenceNote],
        cellReminders: [TimetableCellReminder],
        hidesWeekends: Bool
    ) {
        self.hidesWeekends = hidesWeekends
        courseSignatures = courses
            .map(CourseSignature.init(course:))
            .sorted { $0.id.uuidString < $1.id.uuidString }
        noteSignatures = notes
            .map(NoteSignature.init(note:))
            .sorted { $0.id.uuidString < $1.id.uuidString }
        occurrenceNoteSignatures = occurrenceNotes
            .map(OccurrenceNoteSignature.init(note:))
            .sorted { $0.id.uuidString < $1.id.uuidString }
        cellReminderSignatures = cellReminders
            .map(CellReminderSignature.init(reminder:))
            .sorted { $0.id.uuidString < $1.id.uuidString }
    }

    struct CourseSignature: Equatable, Hashable {
        let id: UUID
        let name: String
        let teacher: String
        let location: String
        let room: String
        let dayOfWeek: Int
        let weeks: [Int]
        let duration: [Int]

        init(course: Course) {
            id = course.id
            name = course.courseName
            teacher = course.teacher
            location = course.location
            room = course.room
            dayOfWeek = course.dayOfWeek
            weeks = course.weeks.sorted()
            duration = course.duration.sorted()
        }
    }

    struct NoteSignature: Equatable, Hashable {
        let id: UUID
        let courseKey: String
        let text: String
        let updatedAt: Date

        init(note: CourseNote) {
            id = note.id
            courseKey = note.courseKey
            text = note.text
            updatedAt = note.updatedAt
        }
    }

    struct OccurrenceNoteSignature: Equatable, Hashable {
        let id: UUID
        let courseKey: String
        let occurrenceKey: String
        let week: Int
        let dayOfWeek: Int
        let text: String
        let updatedAt: Date

        init(note: CourseOccurrenceNote) {
            id = note.id
            courseKey = note.courseKey
            occurrenceKey = note.occurrenceKey
            week = note.week
            dayOfWeek = note.dayOfWeek
            text = note.text
            updatedAt = note.updatedAt
        }
    }

    struct CellReminderSignature: Equatable, Hashable {
        let id: UUID
        let cellKey: String
        let title: String
        let location: String
        let note: String
        let endPeriod: Int
        let startsAt: Date?
        let endsAt: Date?
        let minutesBefore: Int
        let updatedAt: Date

        init(reminder: TimetableCellReminder) {
            id = reminder.id
            cellKey = reminder.cellKey
            title = reminder.title
            location = reminder.locationText
            note = reminder.noteText
            endPeriod = reminder.displayEndPeriod
            startsAt = reminder.startsAt
            endsAt = reminder.endsAt
            minutesBefore = reminder.minutesBefore
            updatedAt = reminder.updatedAt
        }
    }
}

@MainActor
struct TimetableGridSnapshot {
    let signature: TimetableGridInputSignature
    let totalWeeks: Int
    let visibleDays: [Int]
    let courseNoteKeys: Set<String>
    let occurrenceNoteKeys: Set<String>

    private let layoutsByDay: [TimetableGridDayKey: [DayCourseLayout]]
    private let occupiedPeriodsByDay: [TimetableGridDayKey: Set<Int>]
    private let latestCellReminderByKey: [String: TimetableCellReminder]
    private let courseNotesByKey: [String: String]
    private let occurrenceNotesByKey: [String: String]

    static func make(
        courses: [Course],
        notes: [CourseNote],
        occurrenceNotes: [CourseOccurrenceNote],
        cellReminders: [TimetableCellReminder],
        hidesWeekends: Bool,
        totalWeeks: Int,
        signature providedSignature: TimetableGridInputSignature? = nil
    ) -> TimetableGridSnapshot {
        let state = LeafyPerformanceSignposter.timetable.beginInterval("grid-snapshot")
        defer { LeafyPerformanceSignposter.timetable.endInterval("grid-snapshot", state) }

        let signature = providedSignature ?? TimetableGridInputSignature(
            courses: courses,
            notes: notes,
            occurrenceNotes: occurrenceNotes,
            cellReminders: cellReminders,
            hidesWeekends: hidesWeekends
        )
        let visibleDays = hidesWeekends ? Array(1...5) : Array(1...7)
        let courseNotesByKey = TimetableNoteResolver.courseNotesByKey(notes)
        let occurrenceNotesByKey = TimetableNoteResolver.occurrenceNotesByKey(occurrenceNotes)
        let courseNoteKeys = Set(courseNotesByKey.keys)
        let occurrenceNoteKeys = Set(occurrenceNotesByKey.keys)

        let coursesByDay = Dictionary(grouping: courses) { course in
            TimetableGridDayKey(week: 0, day: course.dayOfWeek)
        }
        var layoutsByDay: [TimetableGridDayKey: [DayCourseLayout]] = [:]
        var occupiedPeriodsByDay: [TimetableGridDayKey: Set<Int>] = [:]

        for week in 1...totalWeeks {
            for day in visibleDays {
                let key = TimetableGridDayKey(week: week, day: day)
                let dayCourses = (coursesByDay[TimetableGridDayKey(week: 0, day: day)] ?? [])
                    .filter { $0.weeks.contains(week) }
                    .sortedByStartPeriod()
                let layouts = DayCourseLayoutBuilder.layouts(for: dayCourses)
                layoutsByDay[key] = layouts
                occupiedPeriodsByDay[key] = Set(layouts.flatMap(\.course.duration))
            }
        }

        let latestCellReminderByKey = Dictionary(
            cellReminders
                .sorted { $0.updatedAt > $1.updatedAt }
                .map { ($0.cellKey, $0) },
            uniquingKeysWith: { first, _ in first }
        )

        return TimetableGridSnapshot(
            signature: signature,
            totalWeeks: totalWeeks,
            visibleDays: visibleDays,
            courseNoteKeys: courseNoteKeys,
            occurrenceNoteKeys: occurrenceNoteKeys,
            layoutsByDay: layoutsByDay,
            occupiedPeriodsByDay: occupiedPeriodsByDay,
            latestCellReminderByKey: latestCellReminderByKey,
            courseNotesByKey: courseNotesByKey,
            occurrenceNotesByKey: occurrenceNotesByKey
        )
    }

    func layouts(day: Int, week: Int) -> [DayCourseLayout] {
        layoutsByDay[TimetableGridDayKey(week: week, day: day)] ?? []
    }

    func occupiedPeriods(day: Int, week: Int) -> Set<Int> {
        occupiedPeriodsByDay[TimetableGridDayKey(week: week, day: day)] ?? []
    }

    func cellReminder(week: Int, day: Int, period: Int) -> TimetableCellReminder? {
        latestCellReminderByKey[TimetableCellReminder.cellKey(week: week, dayOfWeek: day, period: period)]
    }

    func cellReminders(week: Int, day: Int) -> [TimetableCellReminder] {
        latestCellReminderByKey.values
            .filter { $0.week == week && $0.dayOfWeek == day }
            .sorted { lhs, rhs in
                if lhs.displayStartPeriod != rhs.displayStartPeriod {
                    return lhs.displayStartPeriod < rhs.displayStartPeriod
                }
                return lhs.title.localizedCompare(rhs.title) == .orderedAscending
            }
    }

    func hasNote(for course: Course, week: Int) -> Bool {
        note(for: course, week: week) != nil
    }

    func note(for course: Course, week: Int) -> String? {
        TimetableNoteResolver.effectiveNote(
            for: course,
            week: week,
            courseNotesByKey: courseNotesByKey,
            occurrenceNotesByKey: occurrenceNotesByKey
        )
    }
}

@MainActor
final class TimetableGridSnapshotCache {
    private var cachedSnapshot: TimetableGridSnapshot?
    private(set) var buildCount = 0

    func snapshot(
        courses: [Course],
        notes: [CourseNote],
        occurrenceNotes: [CourseOccurrenceNote],
        cellReminders: [TimetableCellReminder],
        hidesWeekends: Bool,
        totalWeeks: Int
    ) -> TimetableGridSnapshot {
        let signature = TimetableGridInputSignature(
            courses: courses,
            notes: notes,
            occurrenceNotes: occurrenceNotes,
            cellReminders: cellReminders,
            hidesWeekends: hidesWeekends
        )

        if let cachedSnapshot,
           cachedSnapshot.signature == signature,
           cachedSnapshot.totalWeeks == totalWeeks {
            return cachedSnapshot
        }

        let snapshot = TimetableGridSnapshot.make(
            courses: courses,
            notes: notes,
            occurrenceNotes: occurrenceNotes,
            cellReminders: cellReminders,
            hidesWeekends: hidesWeekends,
            totalWeeks: totalWeeks,
            signature: signature
        )
        cachedSnapshot = snapshot
        buildCount += 1
        return snapshot
    }

    func invalidate() {
        cachedSnapshot = nil
    }
}

struct TimetableGridDayKey: Hashable {
    let week: Int
    let day: Int
}

@MainActor
struct DayCourseLayout: Identifiable {
    let course: Course
    let laneIndex: Int
    let laneCount: Int

    var id: UUID { course.id }
}

@MainActor
enum DayCourseLayoutBuilder {
    static func layouts(for courses: [Course]) -> [DayCourseLayout] {
        guard !courses.isEmpty else { return [] }

        var result: [DayCourseLayout] = []
        var cluster: [Course] = []
        var clusterMaxEnd = 0

        func flushCluster() {
            guard !cluster.isEmpty else { return }
            result.append(contentsOf: layoutsForCluster(cluster))
            cluster.removeAll()
            clusterMaxEnd = 0
        }

        for course in courses {
            let start = course.duration.min() ?? 0
            let end = course.duration.max() ?? 0

            if cluster.isEmpty {
                cluster = [course]
                clusterMaxEnd = end
                continue
            }

            if start <= clusterMaxEnd {
                cluster.append(course)
                clusterMaxEnd = max(clusterMaxEnd, end)
            } else {
                flushCluster()
                cluster = [course]
                clusterMaxEnd = end
            }
        }

        flushCluster()
        return result
    }

    private static func layoutsForCluster(_ cluster: [Course]) -> [DayCourseLayout] {
        var laneEndings: [Int] = []
        var placements: [(Course, Int)] = []

        for course in cluster {
            let start = course.duration.min() ?? 0
            let end = course.duration.max() ?? 0

            if let reusableLane = laneEndings.firstIndex(where: { $0 < start }) {
                laneEndings[reusableLane] = end
                placements.append((course, reusableLane))
            } else {
                laneEndings.append(end)
                placements.append((course, laneEndings.count - 1))
            }
        }

        return placements.map { course, laneIndex in
            DayCourseLayout(course: course, laneIndex: laneIndex, laneCount: max(1, laneEndings.count))
        }
    }
}
