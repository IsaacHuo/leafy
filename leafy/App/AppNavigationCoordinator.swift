import Combine
import Foundation

enum ProfileRoute: Hashable {
    case timetableSharing
    case cacheSync
    case timetableBackground
}

enum RootTab: Hashable {
    case timetable
    case community
    case leafy
    case academics
    case profile
}

extension RootTab: CaseIterable, Identifiable {
    static var allCases: [RootTab] {
        [.leafy, .timetable, .community, .academics, .profile]
    }

    static func visibleCases(isCommunityEnabled: Bool) -> [RootTab] {
        allCases.filter { isCommunityEnabled || $0 != .community }
    }

    var id: RootTab { self }

    func title(language: AppLanguagePreference) -> String {
        switch self {
        case .timetable:
            return L10n.text("课表", language: language)
        case .community:
            return L10n.text("社区", language: language)
        case .leafy:
            return "Leafy"
        case .academics:
            return L10n.text("学业", language: language)
        case .profile:
            return L10n.text("我的", language: language)
        }
    }

    var systemImage: String {
        switch self {
        case .timetable: return "calendar"
        case .community: return "person.2"
        case .leafy: return "sparkles"
        case .academics: return "book.closed"
        case .profile: return "person"
        }
    }

    var selectedSystemImage: String {
        switch self {
        case .timetable: return "calendar"
        case .community: return "person.2.fill"
        case .leafy: return "sparkles"
        case .academics: return "book.closed.fill"
        case .profile: return "person.fill"
        }
    }
}

@MainActor
final class AppNavigationCoordinator: ObservableObject {
    @Published var selectedRootTab: RootTab = .timetable {
        didSet {
            if selectedRootTab != .leafy {
                lastNonLeafyRootTab = selectedRootTab
            }
        }
    }
    @Published private(set) var lastNonLeafyRootTab: RootTab = .timetable
    @Published var selectedAcademicTab: AcademicPrimaryTab = .cultivation
    @Published var requestedAcademicRoute: AcademicRoute?
    @Published var requestedAcademicDetailRoute: AcademicDetailRoute?
    @Published var requestedClassroomLookup: ClassroomLookupRequest?
    @Published var requestedProfileRoute: ProfileRoute?
    @Published var requestedTimetableInviteCode: String?
    @Published var requestedTimetableCourseID: UUID?
    @Published var requestedCommunityPostID: UUID?
    private var deferredRouteRequestTask: Task<Void, Never>?

    func leaveLeafyWorkspace() {
        selectedRootTab = lastNonLeafyRootTab == .leafy ? .timetable : lastNonLeafyRootTab
    }

    func openAcademic(tab: AcademicPrimaryTab) {
        selectedAcademicTab = tab
        selectedRootTab = .academics
    }

    func openAcademicRoute(_ route: AcademicRoute) {
        switch route {
        case .grades:
            selectedAcademicTab = .cultivation
        case .emptyClassroom:
            selectedAcademicTab = .classrooms
        case .scheduleReports:
            selectedAcademicTab = .schedule
        }
        selectedRootTab = .academics
        deferRouteRequest {
            self.requestedAcademicRoute = route
        }
    }

    func openAcademicDetailRoute(_ route: AcademicDetailRoute) {
        selectedAcademicTab = route.tab
        selectedRootTab = .academics
        deferRouteRequest {
            self.requestedAcademicDetailRoute = route
        }
    }

    func openTimetableProcessing() {
        selectedRootTab = .timetable
    }

    func openProfileRoute(_ route: ProfileRoute) {
        selectedRootTab = .profile
        deferRouteRequest {
            self.requestedProfileRoute = route
        }
    }

    func openTimetableSharing(inviteCode: String? = nil) {
        requestedTimetableInviteCode = inviteCode
        openProfileRoute(.timetableSharing)
    }

    func openClassroomLookup(building: String, room: String) {
        let request = ClassroomLookupRequest(building: building, room: room)
        selectedAcademicTab = .classrooms
        selectedRootTab = .academics
        deferRouteRequest {
            self.requestedClassroomLookup = request
        }
    }

    func openCommunityPost(id: UUID) {
        requestedCommunityPostID = id
        selectedRootTab = .community
    }

    func handle(url: URL) {
        if let postID = CommunityPostDeepLink(url: url)?.postID {
            openCommunityPost(id: postID)
            return
        }

        if let invite = TimetableInviteDeepLink(url: url) {
            openTimetableSharing(inviteCode: invite.code)
            return
        }

        guard let route = LeafyWidgetRoute(url: url) else { return }

        switch route {
        case .timetable:
            selectedRootTab = .timetable
        case .course(let id):
            requestedTimetableCourseID = id
            selectedRootTab = .timetable
        case .timetableSharing:
            openTimetableSharing()
        case .cacheSync:
            openProfileRoute(.cacheSync)
        case .scheduleReports:
            openAcademicRoute(.scheduleReports)
        }
    }

    private func deferRouteRequest(_ request: @escaping @MainActor () -> Void) {
        requestedAcademicRoute = nil
        requestedAcademicDetailRoute = nil
        requestedClassroomLookup = nil
        requestedProfileRoute = nil
        deferredRouteRequestTask?.cancel()
        deferredRouteRequestTask = Task { @MainActor in
            await Task.yield()
            guard !Task.isCancelled else { return }
            request()
        }
    }
}

nonisolated struct TimetableInviteDeepLink: Equatable {
    let code: String

    init?(url: URL) {
        if url.scheme == "leafy", url.host == "timetable-invite" {
            guard let codeValue = URLComponents(url: url, resolvingAgainstBaseURL: false)?
                .queryItems?
                .first(where: { $0.name == "code" })?
                .value
            else { return nil }
            let normalized = TimetableSharingService.normalizeInviteCode(codeValue)
            guard normalized.count == 12 else { return nil }
            code = normalized
            return
        }

        guard url.scheme == "https",
              url.host == "myleafy.space"
        else { return nil }

        let components = url.pathComponents.filter { $0 != "/" }
        guard components.count == 3,
              components[0] == "share",
              components[1] == "timetable"
        else { return nil }

        let normalized = TimetableSharingService.normalizeInviteCode(components[2])
        guard normalized.count == 12 else { return nil }
        code = normalized
    }
}

nonisolated struct CommunityPostDeepLink: Equatable {
    let postID: UUID

    init?(url: URL) {
        if url.scheme == "leafy", url.host == "community-post" {
            guard let idValue = URLComponents(url: url, resolvingAgainstBaseURL: false)?
                .queryItems?
                .first(where: { $0.name == "id" })?
                .value,
                  let postID = UUID(uuidString: idValue)
            else { return nil }
            self.postID = postID
            return
        }

        guard url.scheme == "https",
              url.host == "myleafy.space"
        else { return nil }

        let components = url.pathComponents.filter { $0 != "/" }
        guard components.count == 4,
              components[0] == "share",
              components[1] == "community",
              components[2] == "post",
              let postID = UUID(uuidString: components[3])
        else { return nil }

        self.postID = postID
    }
}
