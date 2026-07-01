import Foundation
import SwiftData

struct TimetableRefreshResult {
    let adjustedWeek: Int?
    let sharedCourses: [SharedTimetableCourse]
}

struct TimetableRefreshUseCase {
    let repository: any SchoolTimetableRepository

    init(repository: any SchoolTimetableRepository = LiveSchoolTimetableRepository()) {
        self.repository = repository
    }

    func fetchHTML() async throws -> String {
        try await repository.fetchTimetableHTML()
    }

    static func parseRecords(html: String) async throws -> [ParsedCourseRecord] {
        try await Task.detached(priority: .userInitiated) {
            try HTMLParser.parseTimetableRecords(html: html)
        }.value
    }

    @MainActor
    func persist(
        records: [ParsedCourseRecord],
        existingCourses: [Course],
        modelContext: ModelContext
    ) {
        for course in existingCourses {
            modelContext.delete(course)
        }

        for course in records.map({ $0.makeCourse() }) {
            modelContext.insert(course)
        }

        try? modelContext.save()
    }

    static func nearestAvailableWeek(from parsedCourses: [ParsedCourseRecord], preferredWeek: Int) -> Int? {
        let weeks = Set(parsedCourses.flatMap(\.weeks)).sorted()
        guard !weeks.isEmpty else { return nil }
        if weeks.contains(preferredWeek) { return preferredWeek }

        return weeks.min { lhs, rhs in
            let leftDistance = abs(lhs - preferredWeek)
            let rightDistance = abs(rhs - preferredWeek)
            if leftDistance == rightDistance { return lhs < rhs }
            return leftDistance < rightDistance
        }
    }
}
