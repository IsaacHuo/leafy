import Observation

@MainActor
@Observable
final class RatingCatalogSectionStore {
    private(set) var hasStartedInitialLoad = false

    func beginInitialLoad() -> Bool {
        guard !hasStartedInitialLoad else { return false }
        hasStartedInitialLoad = true
        return true
    }
}

@MainActor
@Observable
final class RatingCatalogWorkspace {
    let teachers = RatingCatalogSectionStore()
    let courses = RatingCatalogSectionStore()
    let dishes = RatingCatalogSectionStore()
}
