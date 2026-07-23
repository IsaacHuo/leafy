import Foundation

nonisolated struct LiveClassroomLookupService: ClassroomLookupServicing {
    private let fetchEmptyClassroomsHTML: @Sendable (Date, Int, Int) async throws -> String
    private let fetchClassroomUsage: @Sendable (Date, String, String) async throws -> [ClassroomUsageSlot]
    private let parseEmptyClassrooms: @Sendable (String) throws -> [EmptyClassroom]
    private let isDemoModeEnabled: @Sendable () async -> Bool
    private let demoEmptyClassrooms: @Sendable (Date, Int, Int) async -> [EmptyClassroom]
    private let demoClassroomUsage: @Sendable (Date, String, String) async -> [ClassroomUsageSlot]
    private let requiresReauthentication: @Sendable (Error) -> Bool
    private let cache: any ClassroomLookupCaching

    init(
        fetchEmptyClassroomsHTML: @escaping @Sendable (Date, Int, Int) async throws -> String = { date, start, end in
            try await ActiveCampusContext.networkManager.fetchEmptyClassrooms(date: date, start: start, end: end)
        },
        fetchClassroomUsage: @escaping @Sendable (Date, String, String) async throws -> [ClassroomUsageSlot] = { date, building, room in
            try await ActiveCampusContext.networkManager.fetchClassroomUsage(date: date, building: building, room: room)
        },
        parseEmptyClassrooms: @escaping @Sendable (String) throws -> [EmptyClassroom] = { html in
            try HTMLParser.parseEmptyClassrooms(html: html)
        },
        isDemoModeEnabled: @escaping @Sendable () async -> Bool = {
            await MainActor.run { ReviewDemoMode.isEnabled }
        },
        demoEmptyClassrooms: @escaping @Sendable (Date, Int, Int) async -> [EmptyClassroom] = { date, start, end in
            await MainActor.run {
                ReviewDemoDataSeeder.emptyClassrooms(for: date, start: start, end: end)
            }
        },
        demoClassroomUsage: @escaping @Sendable (Date, String, String) async -> [ClassroomUsageSlot] = { date, building, room in
            await MainActor.run {
                ReviewDemoDataSeeder.classroomUsage(for: date, building: building, room: room)
            }
        },
        requiresReauthentication: @escaping @Sendable (Error) -> Bool = { error in
            ClassroomLookupReauthentication.requiresReauthentication(error)
        },
        cache: any ClassroomLookupCaching = SchoolDataClassroomLookupCache()
    ) {
        self.fetchEmptyClassroomsHTML = fetchEmptyClassroomsHTML
        self.fetchClassroomUsage = fetchClassroomUsage
        self.parseEmptyClassrooms = parseEmptyClassrooms
        self.isDemoModeEnabled = isDemoModeEnabled
        self.demoEmptyClassrooms = demoEmptyClassrooms
        self.demoClassroomUsage = demoClassroomUsage
        self.requiresReauthentication = requiresReauthentication
        self.cache = cache
    }

    func lookup(_ request: ClassroomLookupRequest, userInitiated: Bool) async -> ClassroomLookupOutcome {
        if await isDemoModeEnabled() {
            return .success(await demoData(for: request))
        }

        do {
            switch request.mode {
            case .byPeriod:
                let html = try await fetchEmptyClassroomsHTML(request.date, request.startPeriod, request.endPeriod)
                let rooms = try parseEmptyClassrooms(html)
                await cache.saveEmptyClassrooms(rooms, date: request.date, start: request.startPeriod, end: request.endPeriod)
                return .success(ClassroomLookupData(rooms: rooms))
            case .byRoom:
                let usage = try await fetchClassroomUsage(request.date, request.building, request.room)
                await cache.saveClassroomUsage(usage, date: request.date, building: request.building, room: request.room)
                return .success(ClassroomLookupData(usage: usage))
            }
        } catch {
            let reauthenticationNeeded = userInitiated && requiresReauthentication(error)
            let message = reauthenticationNeeded
                ? "登录状态已失效，请连接校园网后重新登录并继续查询。"
                : "查询失败：\(error.localizedDescription)"

            return .fallback(
                data: await cachedData(for: request),
                errorMessage: message,
                requiresReauthentication: reauthenticationNeeded
            )
        }
    }

    private func demoData(for request: ClassroomLookupRequest) async -> ClassroomLookupData {
        switch request.mode {
        case .byPeriod:
            let rooms = await demoEmptyClassrooms(request.date, request.startPeriod, request.endPeriod)
            return ClassroomLookupData(rooms: rooms)
        case .byRoom:
            let usage = await demoClassroomUsage(request.date, request.building, request.room)
            return ClassroomLookupData(usage: usage)
        }
    }

    private func cachedData(for request: ClassroomLookupRequest) async -> ClassroomLookupData {
        switch request.mode {
        case .byPeriod:
            let rooms = await cache.loadEmptyClassrooms(
                date: request.date,
                start: request.startPeriod,
                end: request.endPeriod
            )
            return ClassroomLookupData(rooms: rooms)
        case .byRoom:
            let usage = await cache.loadClassroomUsage(
                date: request.date,
                building: request.building,
                room: request.room
            )
            return ClassroomLookupData(usage: usage)
        }
    }
}

nonisolated enum ClassroomLookupReauthentication {
    static func requiresReauthentication(_ error: Error) -> Bool {
        if SchoolReauthentication.shouldPromptForUserInitiatedAccess(error) {
            return true
        }

        if case SchoolNetworkError.loginFailed(let message) = error {
            return message.contains("登录页")
        }

        return false
    }
}

nonisolated struct SchoolDataClassroomLookupCache: ClassroomLookupCaching {
    func loadEmptyClassrooms(date: Date, start: Int, end: Int) async -> [EmptyClassroom] {
        await MainActor.run {
            SchoolDataCache.loadEmptyClassrooms(date: date, start: start, end: end)
        }
    }

    func saveEmptyClassrooms(_ rooms: [EmptyClassroom], date: Date, start: Int, end: Int) async {
        await MainActor.run {
            SchoolDataCache.saveEmptyClassrooms(rooms, date: date, start: start, end: end)
        }
    }

    func loadClassroomUsage(date: Date, building: String, room: String) async -> [ClassroomUsageSlot] {
        await MainActor.run {
            SchoolDataCache.loadClassroomUsage(date: date, building: building, room: room)
        }
    }

    func saveClassroomUsage(_ usage: [ClassroomUsageSlot], date: Date, building: String, room: String) async {
        await MainActor.run {
            SchoolDataCache.saveClassroomUsage(usage, date: date, building: building, room: room)
        }
    }
}
