import CryptoKit
import Foundation
#if canImport(UIKit)
import UIKit
#elseif canImport(AppKit)
import AppKit
#endif

nonisolated struct CampusID: RawRepresentable, Codable, Hashable, Sendable {
    let rawValue: String

    init(rawValue: String) {
        self.rawValue = rawValue.trimmingCharacters(in: .whitespacesAndNewlines).lowercased()
    }

    static let bjfu = CampusID(rawValue: "bjfu")
    static let custom = CampusID(rawValue: "custom")
}

nonisolated enum CampusCapability: String, Codable, CaseIterable, Hashable, Sendable {
    case authentication
    case timetable
    case grades
    case exams
    case teachingPlan
    case trainingProgram
    case classrooms
    case community
    case weather
    case sharedTimetable
    case medicalServices
}

nonisolated enum CampusConnectorKind: String, Codable, Hashable, Sendable {
    case bjfu
    case custom
}

nonisolated struct CampusCoordinate: Codable, Hashable, Sendable {
    let latitude: Double
    let longitude: Double
}

nonisolated struct CampusLink: Codable, Hashable, Identifiable, Sendable {
    let id: String
    let title: String
    let url: URL
}

nonisolated struct CampusFeatureFlags: Codable, Hashable, Sendable {
    let campusPickerEnabled: Bool
    let crossCampusCommunityEnabled: Bool
}

nonisolated struct CampusDescriptor: Codable, Hashable, Identifiable, Sendable {
    let id: CampusID
    let displayName: String
    let shortName: String
    let timeZoneIdentifier: String
    let connectorKind: CampusConnectorKind
    let capabilities: Set<CampusCapability>
    let networkHint: String
    let defaultStudentDisplayName: String
    let undergraduateBaseURL: URL
    let graduateBaseURL: URL
    let weatherCoordinate: CampusCoordinate
    let weatherCityCode: String
    let commonLinks: [CampusLink]
    let featureFlags: CampusFeatureFlags

    func supports(_ capability: CampusCapability) -> Bool {
        capabilities.contains(capability)
    }

    static let bjfu = CampusDescriptor(
        id: .bjfu,
        displayName: "北京林业大学",
        shortName: "北林",
        timeZoneIdentifier: "Asia/Shanghai",
        connectorKind: .bjfu,
        capabilities: Set(CampusCapability.allCases),
        networkHint: "连接 bjfu-wifi 后可访问教务系统。",
        defaultStudentDisplayName: "北林同学",
        undergraduateBaseURL: URL(string: "http://newjwxt.bjfu.edu.cn")!,
        graduateBaseURL: URL(string: "http://gradms.bjfu.edu.cn/gmis5")!,
        weatherCoordinate: CampusCoordinate(latitude: 40.006, longitude: 116.352),
        weatherCityCode: "110108",
        commonLinks: [
            CampusLink(id: "seat", title: "图书馆座位", url: URL(string: "https://seat.bjfu.edu.cn")!),
            CampusLink(id: "undergraduate", title: "本科教务", url: URL(string: "http://newjwxt.bjfu.edu.cn")!),
            CampusLink(id: "graduate", title: "研究生系统", url: URL(string: "http://gradms.bjfu.edu.cn/gmis5")!)
        ],
        featureFlags: CampusFeatureFlags(
            campusPickerEnabled: false,
            crossCampusCommunityEnabled: false
        )
    )

    static let custom = CampusDescriptor(
        id: .custom,
        displayName: "通用入口",
        shortName: "通用",
        timeZoneIdentifier: "Asia/Shanghai",
        connectorKind: .custom,
        capabilities: [
            .authentication,
            .timetable,
            .grades,
            .exams,
            .community
        ],
        networkHint: "通用入口使用本地导入数据，不连接学校教务系统。",
        defaultStudentDisplayName: "同学",
        undergraduateBaseURL: URL(string: "https://myleafy.space")!,
        graduateBaseURL: URL(string: "https://myleafy.space")!,
        weatherCoordinate: CampusCoordinate(latitude: 0, longitude: 0),
        weatherCityCode: "",
        commonLinks: [],
        featureFlags: CampusFeatureFlags(
            campusPickerEnabled: true,
            crossCampusCommunityEnabled: false
        )
    )
}

nonisolated enum CampusIdentityKind: String, Codable, Hashable, Sendable {
    case schoolPortal
    case customSupabase
}

nonisolated struct CampusIdentity: Codable, Equatable, Hashable, Sendable {
    let campusID: CampusID
    let eduID: String
    let displayName: String?
    let portal: SchoolPortal
    let kind: CampusIdentityKind

    init(
        campusID: CampusID,
        eduID: String,
        displayName: String?,
        portal: SchoolPortal,
        kind: CampusIdentityKind = .schoolPortal
    ) {
        self.campusID = campusID
        self.eduID = eduID.trimmingCharacters(in: .whitespacesAndNewlines)
        self.displayName = displayName?.trimmingCharacters(in: .whitespacesAndNewlines)
        self.portal = portal
        self.kind = kind
    }

    var isCustom: Bool {
        kind == .customSupabase || campusID == .custom
    }

    var scopeKey: String {
        let normalized: String
        if isCustom {
            normalized = "\(campusID.rawValue):\(kind.rawValue):\(eduID.lowercased())"
        } else {
            normalized = "\(campusID.rawValue):\(kind.rawValue):\(portal.rawValue):\(eduID.lowercased())"
        }
        let digest = SHA256.hash(data: Data(normalized.utf8))
        return digest.prefix(12).map { String(format: "%02x", $0) }.joined()
    }

    private enum CodingKeys: String, CodingKey {
        case campusID
        case eduID
        case displayName
        case portal
        case kind
    }

    init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        let campusID = try container.decode(CampusID.self, forKey: .campusID)
        let eduID = try container.decode(String.self, forKey: .eduID)
        let displayName = try container.decodeIfPresent(String.self, forKey: .displayName)
        let portal = try container.decodeIfPresent(SchoolPortal.self, forKey: .portal) ?? .undergraduate
        let kind = try container.decodeIfPresent(CampusIdentityKind.self, forKey: .kind)
            ?? (campusID == .custom ? .customSupabase : .schoolPortal)
        self.init(campusID: campusID, eduID: eduID, displayName: displayName, portal: portal, kind: kind)
    }
}

nonisolated enum CampusCatalog {
    static let builtIn: [CampusDescriptor] = [.bjfu, .custom]
    static let production: [CampusDescriptor] = [.bjfu, .custom]

    static var activeCampus: CampusDescriptor {
        let campusID = CampusIdentityStore.currentIdentity()?.campusID ?? .bjfu
        return builtIn.first(where: { $0.id == campusID }) ?? .bjfu
    }

    static var showsCampusPicker: Bool {
        production.count > 1 && production.contains(where: \.featureFlags.campusPickerEnabled)
    }

    static var showsCrossCampusCommunity: Bool {
        production.count > 1 && production.contains(where: \.featureFlags.crossCampusCommunityEnabled)
    }
}

nonisolated enum CampusIdentityStore {
    private static let activeIdentityKey = "leafy.activeCampusIdentity.v1"
    private static let legacyMigrationMarkerKey = "leafy.activeCampusIdentity.legacyMigrated.v1"

    static func currentIdentity(defaults: UserDefaults = .standard) -> CampusIdentity? {
        if let identity = storedIdentity(defaults: defaults) {
            return identity
        }

        guard !defaults.bool(forKey: legacyMigrationMarkerKey) else {
            return nil
        }

        guard let legacyEduID = defaults.string(forKey: "authenticatedEduID")?
            .trimmingCharacters(in: .whitespacesAndNewlines),
              !legacyEduID.isEmpty else {
            return nil
        }

        let identity = CampusIdentity(
            campusID: .bjfu,
            eduID: legacyEduID,
            displayName: defaults.string(forKey: "authenticatedDisplayName"),
            portal: SchoolPortal(rawValue: defaults.string(forKey: "schoolPortal") ?? "") ?? .undergraduate
        )
        activate(identity, defaults: defaults)
        return identity
    }

    private static func storedIdentity(defaults: UserDefaults) -> CampusIdentity? {
        guard let data = defaults.data(forKey: activeIdentityKey),
              let identity = try? JSONDecoder().decode(CampusIdentity.self, from: data),
              !identity.eduID.isEmpty else {
            return nil
        }
        return identity
    }

    static func activate(_ identity: CampusIdentity, defaults: UserDefaults = .standard) {
        guard !identity.eduID.isEmpty,
              let data = try? JSONEncoder().encode(identity) else {
            return
        }
        let previousScopeKey = storedIdentity(defaults: defaults)?.scopeKey
        defaults.set(data, forKey: activeIdentityKey)
        defaults.set(true, forKey: legacyMigrationMarkerKey)
        if previousScopeKey != identity.scopeKey {
            NotificationCenter.default.post(name: .campusIdentityDidChange, object: identity)
        }
    }

    static func clear(defaults: UserDefaults = .standard) {
        defaults.removeObject(forKey: activeIdentityKey)
        defaults.removeObject(forKey: "authenticatedEduID")
        defaults.removeObject(forKey: "authenticatedDisplayName")
        defaults.removeObject(forKey: "isLoggedIn")
        defaults.removeObject(forKey: "schoolSessionCookies")
        defaults.removeObject(forKey: "schoolPortal")
        defaults.removeObject(forKey: "lastLandingURL")
        NotificationCenter.default.post(name: .campusIdentityDidChange, object: nil)
    }
}

nonisolated enum CampusScopedDefaults {
    private static let migrationPrefix = "leafy.campus.defaultsMigration.v1"

    static func key(
        _ baseKey: String,
        identity: CampusIdentity? = nil,
        defaults: UserDefaults = .standard
    ) -> String {
        guard let identity = identity ?? CampusIdentityStore.currentIdentity(defaults: defaults) else {
            return baseKey
        }
        return "leafy.campus.\(identity.scopeKey).\(baseKey)"
    }

    static func migrateLegacyValuesIfNeeded(
        keys: [String],
        prefixes: [String] = [],
        migrationID: String,
        identity: CampusIdentity? = CampusIdentityStore.currentIdentity(),
        defaults: UserDefaults = .standard
    ) {
        guard let identity else { return }
        let marker = "\(migrationPrefix).\(migrationID).\(identity.scopeKey)"
        guard !defaults.bool(forKey: marker) else { return }

        let dynamicKeys = defaults.dictionaryRepresentation().keys.filter { candidate in
            prefixes.contains(where: { candidate.hasPrefix($0) })
        }
        for legacyKey in Set(keys + dynamicKeys) {
            let scopedKey = key(legacyKey, identity: identity, defaults: defaults)
            if defaults.object(forKey: scopedKey) == nil,
               let value = defaults.object(forKey: legacyKey) {
                defaults.set(value, forKey: scopedKey)
            }
        }
        defaults.set(true, forKey: marker)
    }
}

nonisolated enum ActiveCampusContext {
    static var descriptor: CampusDescriptor {
        CampusCatalog.activeCampus
    }

    static var identity: CampusIdentity? {
        CampusIdentityStore.currentIdentity()
    }

    @MainActor
    static var networkManager: SchoolNetworkManager {
        SchoolNetworkManager.shared
    }
}

extension Notification.Name {
    nonisolated static let campusIdentityDidChange = Notification.Name("CampusIdentityDidChange")
}

@MainActor
protocol CampusAuthenticationProviding: AnyObject {
    var isLoggedIn: Bool { get }
    var hasCachedIdentity: Bool { get }
    var currentPortal: SchoolPortal { get set }
    var authenticatedEduID: String? { get }
    var authenticatedDisplayName: String? { get }

    func fetchCaptcha(for portal: SchoolPortal) async throws -> (key: String, image: UIImage)
    func performLogin(account: String, password: String, captcha: String, key: String, portal: SchoolPortal) async throws -> Bool
    func clearSession()
}

@MainActor
protocol CampusTimetableProviding: AnyObject {
    func fetchTimetable() async throws -> String
    func fetchGrades() async throws -> String
}

@MainActor
protocol CampusAcademicProviding: AnyObject {
    func fetchExamSchedule() async throws -> String
    func fetchTeachingPlan() async throws -> String
    func fetchGraduationRequirements() async throws -> String
    func fetchGradeRankings() async throws -> String
}

@MainActor
protocol CampusClassroomProviding: AnyObject {
    func fetchEmptyClassrooms(date: Date, start: Int, end: Int) async throws -> String
    func fetchClassroomUsage(date: Date, building: String, room: String) async throws -> [ClassroomUsageSlot]
}

protocol CampusAcademicConnector:
    CampusAuthenticationProviding,
    CampusTimetableProviding,
    CampusAcademicProviding,
    CampusClassroomProviding
{
    var campusDescriptor: CampusDescriptor { get }
}

extension SchoolNetworkManager: CampusAcademicConnector {
    var campusDescriptor: CampusDescriptor {
        .bjfu
    }
}
