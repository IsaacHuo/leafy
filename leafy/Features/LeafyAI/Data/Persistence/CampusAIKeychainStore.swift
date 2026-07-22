nonisolated enum CampusAIKeychainError: LocalizedError {
    case unexpectedStatus(OSStatus)
    case missingCampusIdentity

    var errorDescription: String? {
        switch self {
        case .unexpectedStatus(let status):
            return "API Key 保存失败（\(status)）。"
        case .missingCampusIdentity:
            return "请先登录教务账号，再保存 API Key。"
        }
    }
}

nonisolated private extension String {
    var nonEmptyTrimmed: String? {
        let trimmed = trimmingCharacters(in: .whitespacesAndNewlines)
        return trimmed.isEmpty ? nil : trimmed
    }
}

nonisolated enum CampusAIKeychainStore {
    private static let service = "com.myleafy.campus-ai"
    private static let legacyCleanupStorageKey = "campusAI.keychainLegacyCleanup.v2"
    static let legacyAccounts = ["zhipu-api-key", "customOpenAICompatible-api-key"]

    static func load(providerID: CampusAIProviderID = CampusAIProviderCatalog.defaultProvider.id) -> String? {
        try? removeLegacyKeysIfNeeded()
        guard let scopedAccount = account(for: providerID) else { return nil }
        if let value = load(account: scopedAccount) {
            return value
        }

        let legacyAccount = legacyAccount(for: providerID)
        guard let legacyValue = load(account: legacyAccount) else { return nil }
        try? saveData(Data(legacyValue.utf8), account: scopedAccount)
        SecItemDelete(baseQuery(account: legacyAccount) as CFDictionary)
        return legacyValue
    }

    static func save(
        _ apiKey: String,
        providerID: CampusAIProviderID = CampusAIProviderCatalog.defaultProvider.id
    ) throws {
        try removeLegacyKeysIfNeeded()
        guard let trimmed = apiKey.nonEmptyTrimmed else {
            try delete(providerID: providerID)
            return
        }
        guard let scopedAccount = account(for: providerID) else {
            throw CampusAIKeychainError.missingCampusIdentity
        }
        try saveData(Data(trimmed.utf8), account: scopedAccount)
    }

    static func delete(providerID: CampusAIProviderID = CampusAIProviderCatalog.defaultProvider.id) throws {
        try removeLegacyKeysIfNeeded()
        guard let scopedAccount = account(for: providerID) else { return }
        let status = SecItemDelete(baseQuery(account: scopedAccount) as CFDictionary)
        guard status == errSecSuccess || status == errSecItemNotFound else {
            throw CampusAIKeychainError.unexpectedStatus(status)
        }
    }

    static func hasAPIKey(providerID: CampusAIProviderID = CampusAIProviderCatalog.defaultProvider.id) -> Bool {
        load(providerID: providerID) != nil
    }

    static func configuredProviderIDs() -> Set<CampusAIProviderID> {
        Set(
            CampusAIProviderCatalog.all.compactMap { provider in
                hasAPIKey(providerID: provider.id) ? provider.id : nil
            }
        )
    }

    static func removeLegacyKeysIfNeeded(userDefaults: UserDefaults = .standard) throws {
        try removeLegacyKeysIfNeeded(userDefaults: userDefaults) { account in
            SecItemDelete(baseQuery(account: account) as CFDictionary)
        }
    }

    static func removeLegacyKeysIfNeeded(
        userDefaults: UserDefaults,
        deleteItem: (String) -> OSStatus
    ) throws {
        guard !userDefaults.bool(forKey: legacyCleanupStorageKey) else { return }
        for account in legacyAccounts {
            let status = deleteItem(account)
            guard status == errSecSuccess || status == errSecItemNotFound else {
                throw CampusAIKeychainError.unexpectedStatus(status)
            }
        }
        userDefaults.set(true, forKey: legacyCleanupStorageKey)
    }

    private static func load(account: String) -> String? {
        var query = baseQuery(account: account)
        query[kSecReturnData as String] = true
        query[kSecMatchLimit as String] = kSecMatchLimitOne

        var result: CFTypeRef?
        let status = SecItemCopyMatching(query as CFDictionary, &result)
        guard status == errSecSuccess,
              let data = result as? Data,
              let value = String(data: data, encoding: .utf8)
        else {
            return nil
        }
        return value.nonEmptyTrimmed
    }

    private static func account(for providerID: CampusAIProviderID) -> String? {
        guard let scopeKey = CampusIdentityStore.currentIdentity()?.scopeKey else { return nil }
        return "\(scopeKey):\(legacyAccount(for: providerID))"
    }

    private static func legacyAccount(for providerID: CampusAIProviderID) -> String {
        "\(providerID.rawValue)-api-key"
    }

    private static func saveData(_ data: Data, account: String) throws {
        let updateStatus = SecItemUpdate(
            baseQuery(account: account) as CFDictionary,
            [kSecValueData as String: data] as CFDictionary
        )
        if updateStatus == errSecSuccess { return }
        if updateStatus != errSecItemNotFound {
            throw CampusAIKeychainError.unexpectedStatus(updateStatus)
        }

        var addQuery = baseQuery(account: account)
        addQuery[kSecValueData as String] = data
        let addStatus = SecItemAdd(addQuery as CFDictionary, nil)
        guard addStatus == errSecSuccess else {
            throw CampusAIKeychainError.unexpectedStatus(addStatus)
        }
    }

    private static func baseQuery(account: String) -> [String: Any] {
        [
            kSecClass as String: kSecClassGenericPassword,
            kSecAttrService as String: service,
            kSecAttrAccount as String: account,
            kSecAttrAccessible as String: kSecAttrAccessibleWhenUnlockedThisDeviceOnly
        ]
    }
}

nonisolated struct CampusAIAPIKeyResolver {
    var userAPIKey: (CampusAIProviderID) -> String?

    init(
        userAPIKey: @escaping (CampusAIProviderID) -> String? = CampusAIKeychainStore.load(providerID:)
    ) {
        self.userAPIKey = userAPIKey
    }

    func resolve(for settings: CampusAIUserSettings) throws -> String {
        if let userKey = userAPIKey(settings.selectedProviderID)?.nonEmptyTrimmed {
            return userKey
        }
        throw CampusAIServiceError.missingAPIKey
    }
}
import Foundation
import Security
