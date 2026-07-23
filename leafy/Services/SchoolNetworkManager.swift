import Foundation
import Combine

enum SchoolPortal: String, CaseIterable, Codable, Identifiable, Sendable {
    case undergraduate
    case graduate

    var id: String { rawValue }

    var title: String {
        switch self {
        case .undergraduate:
            return "本科生"
        case .graduate:
            return "研究生"
        }
    }

    var loginHint: String {
        switch self {
        case .undergraduate:
            return "使用强智教务账号登录。"
        case .graduate:
            return "使用研究生管理系统账号登录，当前先接入课表。"
        }
    }
}

enum SchoolNetworkError: LocalizedError {
    case loginFailed(String)
    case campusNetworkRequired
    case sessionExpired
    case featureUnavailable(String)
    case timetableQueryFormNotFound(String)
    case timetableDataUnavailable(String)
    case timetableSemesterMismatch(expected: String, actual: String)
    case classroomDataUnavailable(String)

    var errorDescription: String? {
        switch self {
        case .loginFailed(let message):
            return message
        case .campusNetworkRequired:
            return L10n.text("教务系统只能在校园网内访问。请连接 bjfu-wifi 后再更新；已缓存的数据仍可离线查看。")
        case .sessionExpired:
            return L10n.text("登录状态已失效，请连接校园网后重新登录")
        case .featureUnavailable(let message):
            return message
        case .timetableQueryFormNotFound(let detail):
            return L10n.text("未找到课表查询参数，服务端页面结构可能已变更。%@", detail)
        case .timetableDataUnavailable(let detail):
            return L10n.text("课表页面未返回可解析的数据。%@", detail)
        case .timetableSemesterMismatch(let expected, let actual):
            return L10n.text("教务返回的课表学期为 %@，与当前配置 %@ 不一致。请稍后重试。", actual, expected)
        case .classroomDataUnavailable(let detail):
            return L10n.text("空教室页面未返回可解析的数据。%@", detail)
        }
    }
}

@MainActor
final class SchoolNetworkManager: ObservableObject {
    static let shared = SchoolNetworkManager()
    private static let scopedStorageKeys = [
        "isLoggedIn",
        "schoolSessionCookies",
        "schoolPortal",
        "lastLandingURL",
        "authenticatedEduID",
        "authenticatedDisplayName"
    ]

    @Published var isLoggedIn: Bool {
        didSet {
            UserDefaults.standard.set(isLoggedIn, forKey: storageKey("isLoggedIn"))
            lastAuthenticatedSessionValidationAt = isLoggedIn ? Date() : nil
        }
    }

    var lastAuthenticatedSessionValidationAt: Date?

    var persistedCookieValues: [String: String] {
        didSet {
            _ = SchoolSessionCredentialStore.save(
                persistedCookieValues,
                identity: CampusIdentityStore.currentIdentity(),
                portal: currentPortal
            )
        }
    }

    @Published var currentPortal: SchoolPortal {
        didSet {
            UserDefaults.standard.set(currentPortal.rawValue, forKey: storageKey("schoolPortal"))
        }
    }

    var lastLandingURLString: String? {
        didSet {
            UserDefaults.standard.set(lastLandingURLString, forKey: storageKey("lastLandingURL"))
        }
    }

    @Published var authenticatedEduID: String? {
        didSet {
            if let authenticatedEduID {
                UserDefaults.standard.set(authenticatedEduID, forKey: storageKey("authenticatedEduID"))
            } else {
                UserDefaults.standard.removeObject(forKey: storageKey("authenticatedEduID"))
            }
        }
    }

    @Published var authenticatedDisplayName: String? {
        didSet {
            if let authenticatedDisplayName {
                UserDefaults.standard.set(authenticatedDisplayName, forKey: storageKey("authenticatedDisplayName"))
            } else {
                UserDefaults.standard.removeObject(forKey: storageKey("authenticatedDisplayName"))
            }
        }
    }

    var hasCachedIdentity: Bool {
        if ReviewDemoMode.isEnabled { return true }
        guard let authenticatedEduID else { return false }
        return !authenticatedEduID.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
    }

    let baseURL = CampusDescriptor.bjfu.undergraduateBaseURL.absoluteString
    let graduateBaseURL = CampusDescriptor.bjfu.graduateBaseURL.absoluteString
    let session: URLSession = {
        let config = URLSessionConfiguration.default
        config.httpCookieStorage = HTTPCookieStorage.shared
        config.httpCookieAcceptPolicy = .always
        config.httpShouldSetCookies = true
        config.requestCachePolicy = .reloadIgnoringLocalCacheData
        config.urlCache = nil
        config.timeoutIntervalForRequest = 8
        config.timeoutIntervalForResource = 18
        config.httpAdditionalHeaders = [
            "User-Agent": "Mozilla/5.0 (Macintosh; Intel Mac OS X 10_15_7) AppleWebKit/537.36 (KHTML, like Gecko) Chrome/121.0.0.0 Safari/537.36",
            "Referer": "http://newjwxt.bjfu.edu.cn/"
        ]
        return URLSession(configuration: config)
    }()

    init() {
        CampusScopedDefaults.migrateLegacyValuesIfNeeded(
            keys: Self.scopedStorageKeys,
            migrationID: "schoolSession"
        )
        let currentIdentity = CampusIdentityStore.currentIdentity()
        let portal = SchoolPortal(rawValue: UserDefaults.standard.string(forKey: CampusScopedDefaults.key("schoolPortal")) ?? "") ?? .undergraduate
        self.isLoggedIn = UserDefaults.standard.bool(forKey: CampusScopedDefaults.key("isLoggedIn"))
        self.persistedCookieValues = SchoolSessionCredentialStore.migrateLegacyCookiesIfNeeded(
            defaults: .standard,
            defaultsKey: CampusScopedDefaults.key("schoolSessionCookies"),
            identity: currentIdentity,
            portal: portal
        )
        self.currentPortal = portal
        self.lastLandingURLString = UserDefaults.standard.string(forKey: CampusScopedDefaults.key("lastLandingURL"))
        self.authenticatedEduID = UserDefaults.standard.string(forKey: CampusScopedDefaults.key("authenticatedEduID"))
        self.authenticatedDisplayName = UserDefaults.standard.string(forKey: CampusScopedDefaults.key("authenticatedDisplayName"))
        if ReviewDemoMode.isEnabled {
            self.isLoggedIn = true
            self.authenticatedEduID = "review-demo"
            self.authenticatedDisplayName = ReviewDemoDataSeeder.displayName
        }
    }

    private func storageKey(_ key: String) -> String {
        CampusScopedDefaults.key(key)
    }
}

extension SchoolNetworkManager {
    func requireUndergraduatePortal(for featureName: String) throws {
        guard currentPortal == .graduate else { return }
        throw SchoolNetworkError.featureUnavailable(
            L10n.text("研究生端暂未接入%@，当前先支持研究生登录和课表。", L10n.text(featureName))
        )
    }
}
