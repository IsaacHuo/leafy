import Foundation

nonisolated enum LeafyWidgetConstants {
    static let appGroupIdentifier = "group.com.isaachuo.leafy"
    static let snapshotFilename = "leafy-widget-snapshot.json"
    static let snapshotArchiveFilename = "leafy-widget-snapshots.json"
    static let widgetKind = "LeafyTimetableWidget"
    static let selectedDayOffsetKey = "leafyWidget.selectedDayOffset"
    static let themeSnapshotKey = "leafyWidget.themeSnapshot"
    static let themePreferenceKey = "leafyWidget.themePreference"
    static let themeCustomColorHexKey = "leafyWidget.themeCustomColorHex"
    static let supportedDayOffsets = [0, 1]
}

nonisolated enum LeafyWidgetL10n {
    static func text(_ key: String) -> String {
        key
    }

    static func text(_ key: String, _ arguments: CVarArg...) -> String {
        String(format: key, locale: Locale(identifier: "zh-Hans"), arguments: arguments)
    }
}

nonisolated enum LeafyWidgetRoute: Equatable {
    case timetable
    case course(id: UUID)
    case timetableSharing
    case cacheSync
    case scheduleReports

    private static let scheme = "leafy"

    /// Non-optional fallback used when `URLComponents` fails to produce a URL.
    /// Built from compile-time constants and validated once here, so the hot path
    /// below never needs an inline force-unwrap.
    private static let fallbackURL: URL = {
        guard let url = URL(string: "\(scheme)://timetable") else {
            preconditionFailure("Invalid LeafyWidgetRoute fallback URL for scheme: \(scheme)")
        }
        return url
    }()

    var url: URL {
        var components = URLComponents()
        components.scheme = Self.scheme

        switch self {
        case .timetable:
            components.host = "timetable"
        case .course(let id):
            components.host = "course"
            components.queryItems = [
                URLQueryItem(name: "id", value: id.uuidString)
            ]
        case .timetableSharing:
            components.host = "timetable-sharing"
        case .cacheSync:
            components.host = "cache-sync"
        case .scheduleReports:
            components.host = "schedule-reports"
        }

        return components.url ?? Self.fallbackURL
    }

    init?(url: URL) {
        guard url.scheme == Self.scheme else { return nil }

        switch url.host {
        case "timetable":
            self = .timetable
        case "course":
            let idValue = URLComponents(url: url, resolvingAgainstBaseURL: false)?
                .queryItems?
                .first(where: { $0.name == "id" })?
                .value
            guard let idValue, let id = UUID(uuidString: idValue) else { return nil }
            self = .course(id: id)
        case "timetable-sharing":
            self = .timetableSharing
        case "cache-sync":
            self = .cacheSync
        case "schedule-reports":
            self = .scheduleReports
        default:
            return nil
        }
    }
}

nonisolated struct LeafyWidgetSnapshot: Codable, Hashable, Sendable {
    enum Status: String, Codable, Hashable, Sendable {
        case ready
        case noCourses
        case needsLogin
        case stale
    }

    var generatedAt: Date
    var status: Status
    var displayDate: String
    var weekText: String
    var dayText: String
    var headline: String
    var subtitle: String
    var syncText: String?
    var lastFailureText: String?
    var nextExamText: String?
    var courses: [LeafyWidgetCourse]

    static let placeholder = LeafyWidgetSnapshot(
        generatedAt: Date(),
        status: .ready,
        displayDate: "5月12日",
        weekText: "第 10 周",
        dayText: "周二",
        headline: "今日课表",
        subtitle: "下一节：数据结构",
        syncText: "最近同步：12:30",
        lastFailureText: nil,
        nextExamText: "考试：高等数学 A · 5月21日",
        courses: [
            LeafyWidgetCourse(
                id: UUID(),
                title: "数据结构",
                timeText: "08:00-09:35",
                periodText: "第 1-2 节",
                locationText: "二教 205",
                teacherText: "林青",
                noteText: "复习树和图",
                reminderText: "提前 10 分钟",
                accentIndex: 0,
                isActive: true
            ),
            LeafyWidgetCourse(
                id: UUID(),
                title: "大学英语",
                timeText: "11:30-12:15",
                periodText: "第 5 节",
                locationText: "学研中心 B203",
                teacherText: "叶岚",
                noteText: nil,
                reminderText: nil,
                accentIndex: 1,
                isActive: false
            )
        ]
    )

    static let empty = LeafyWidgetSnapshot(
        generatedAt: Date(),
        status: .noCourses,
        displayDate: "今天",
        weekText: "第 - 周",
        dayText: "",
        headline: "今天没有课程",
        subtitle: "留一点空白给自己。",
        syncText: nil,
        lastFailureText: nil,
        nextExamText: nil,
        courses: []
    )
}

nonisolated struct LeafyWidgetCourse: Codable, Identifiable, Hashable, Sendable {
    var id: UUID
    var title: String
    var timeText: String
    var periodText: String
    var locationText: String
    var teacherText: String?
    var noteText: String?
    var reminderText: String?
    var accentIndex: Int
    var isActive: Bool
}

nonisolated struct LeafyWidgetSnapshotArchive: Codable, Hashable, Sendable {
    var generatedAt: Date
    var snapshots: [LeafyWidgetDaySnapshot]

    func snapshot(for dayOffset: Int) -> LeafyWidgetSnapshot? {
        let normalizedOffset = LeafyWidgetSnapshotStore.normalizedDayOffset(dayOffset)
        return snapshots.first { $0.dayOffset == normalizedOffset }?.snapshot
    }
}

nonisolated struct LeafyWidgetDaySnapshot: Codable, Hashable, Sendable {
    var dayOffset: Int
    var snapshot: LeafyWidgetSnapshot
}

nonisolated enum LeafyWidgetSnapshotStore {
    static var selectedDayOffset: Int {
        normalizedDayOffset(appGroupDefaults.integer(forKey: LeafyWidgetConstants.selectedDayOffsetKey))
    }

    static func normalizedDayOffset(_ dayOffset: Int) -> Int {
        LeafyWidgetConstants.supportedDayOffsets.contains(dayOffset) ? dayOffset : 0
    }

    static func setSelectedDayOffset(_ dayOffset: Int) {
        appGroupDefaults.set(
            normalizedDayOffset(dayOffset),
            forKey: LeafyWidgetConstants.selectedDayOffsetKey
        )
    }

    static func alternateDayOffset(for dayOffset: Int) -> Int {
        normalizedDayOffset(dayOffset) == 0 ? 1 : 0
    }

    static func loadSelectedSnapshot() -> LeafyWidgetSnapshot? {
        load(dayOffset: selectedDayOffset)
    }

    static func load(dayOffset: Int) -> LeafyWidgetSnapshot? {
        if let archive = loadArchive() {
            return archive.snapshot(for: dayOffset) ?? archive.snapshots.first?.snapshot
        }

        return load()
    }

    static func load() -> LeafyWidgetSnapshot? {
        guard let data = try? Data(contentsOf: snapshotURL) else { return nil }
        return try? JSONDecoder.leafyWidget.decode(LeafyWidgetSnapshot.self, from: data)
    }

    static func loadArchive() -> LeafyWidgetSnapshotArchive? {
        guard let data = try? Data(contentsOf: snapshotArchiveURL),
              let archive = try? JSONDecoder.leafyWidget.decode(LeafyWidgetSnapshotArchive.self, from: data),
              !archive.snapshots.isEmpty
        else {
            return nil
        }

        return archive
    }

    @discardableResult
    static func save(_ snapshot: LeafyWidgetSnapshot) -> Bool {
        save(
            LeafyWidgetSnapshotArchive(
                generatedAt: snapshot.generatedAt,
                snapshots: [
                    LeafyWidgetDaySnapshot(dayOffset: 0, snapshot: snapshot)
                ]
            )
        )
    }

    @discardableResult
    static func save(_ archive: LeafyWidgetSnapshotArchive) -> Bool {
        do {
            let directory = snapshotArchiveURL.deletingLastPathComponent()
            try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
            let data = try JSONEncoder.leafyWidget.encode(archive)
            try data.write(to: snapshotArchiveURL, options: [.atomic])

            if let todaySnapshot = archive.snapshot(for: 0) ?? archive.snapshots.first?.snapshot {
                saveLegacySnapshot(todaySnapshot)
            }
            return true
        } catch {
            #if DEBUG
            print("Leafy widget snapshot archive save failed: \(error)")
            #endif
            return false
        }
    }

    private static func saveLegacySnapshot(_ snapshot: LeafyWidgetSnapshot) {
        do {
            let directory = snapshotURL.deletingLastPathComponent()
            try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
            let data = try JSONEncoder.leafyWidget.encode(snapshot)
            try data.write(to: snapshotURL, options: [.atomic])
        } catch {
            #if DEBUG
            print("Leafy widget snapshot save failed: \(error)")
            #endif
        }
    }

    static func clear() {
        try? FileManager.default.removeItem(at: snapshotURL)
        try? FileManager.default.removeItem(at: snapshotArchiveURL)
    }

    private static var snapshotArchiveURL: URL {
        containerURL.appendingPathComponent(LeafyWidgetConstants.snapshotArchiveFilename)
    }

    private static var snapshotURL: URL {
        containerURL.appendingPathComponent(LeafyWidgetConstants.snapshotFilename)
    }

    private static var containerURL: URL {
        if let container = FileManager.default.containerURL(
            forSecurityApplicationGroupIdentifier: LeafyWidgetConstants.appGroupIdentifier
        ) {
            return container
        }
        let base = FileManager.default.urls(for: .cachesDirectory, in: .userDomainMask).first
            ?? FileManager.default.temporaryDirectory
        return base.appendingPathComponent("LeafyWidget", isDirectory: true)
    }

    private static var appGroupDefaults: UserDefaults {
        UserDefaults(suiteName: LeafyWidgetConstants.appGroupIdentifier) ?? .standard
    }
}

nonisolated private extension JSONDecoder {
    static var leafyWidget: JSONDecoder {
        let decoder = JSONDecoder()
        decoder.dateDecodingStrategy = .iso8601
        return decoder
    }
}

nonisolated private extension JSONEncoder {
    static var leafyWidget: JSONEncoder {
        let encoder = JSONEncoder()
        encoder.dateEncodingStrategy = .iso8601
        return encoder
    }
}
