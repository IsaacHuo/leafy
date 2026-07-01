import Foundation

protocol SchoolTimetableRepository: Sendable {
    func fetchTimetableHTML() async throws -> String
}

struct LiveSchoolTimetableRepository: SchoolTimetableRepository {
    nonisolated init() {}

    @MainActor
    func fetchTimetableHTML() async throws -> String {
        try await Self.activeManagerForRefresh().fetchTimetable()
    }

    @MainActor
    static func activeManagerForRefresh() -> SchoolNetworkManager {
        ActiveCampusContext.networkManager
    }
}
