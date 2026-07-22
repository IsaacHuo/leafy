import Foundation
import OSLog
import Security

nonisolated enum CommunityIdentityDeviceStore {
    private static let service = "com.myleafy.community-identity"
    private static let account = "active-school-scope"
    private static let logger = Logger(subsystem: "com.myleafy.leafy", category: "CommunityIdentity")

    static func loadScopeKey() -> String? {
        var query = baseQuery
        query[kSecReturnData as String] = true
        query[kSecMatchLimit as String] = kSecMatchLimitOne
        var result: CFTypeRef?
        let status = SecItemCopyMatching(query as CFDictionary, &result)
        guard status == errSecSuccess,
              let data = result as? Data,
              let value = String(data: data, encoding: .utf8),
              !value.isEmpty else {
            if status != errSecItemNotFound {
                logger.error("Community identity marker read failed status=\(status, privacy: .public)")
            }
            return nil
        }
        return value
    }

    @discardableResult
    static func saveScopeKey(_ scopeKey: String) -> Bool {
        guard !scopeKey.isEmpty else { return false }
        let data = Data(scopeKey.utf8)
        let updateStatus = SecItemUpdate(
            baseQuery as CFDictionary,
            [kSecValueData as String: data] as CFDictionary
        )
        if updateStatus == errSecSuccess { return true }
        guard updateStatus == errSecItemNotFound else {
            logger.error("Community identity marker update failed status=\(updateStatus, privacy: .public)")
            return false
        }

        var query = baseQuery
        query[kSecValueData as String] = data
        let status = SecItemAdd(query as CFDictionary, nil)
        guard status == errSecSuccess else {
            logger.error("Community identity marker add failed status=\(status, privacy: .public)")
            return false
        }
        return true
    }

    private static var baseQuery: [String: Any] {
        [
            kSecClass as String: kSecClassGenericPassword,
            kSecAttrService as String: service,
            kSecAttrAccount as String: account,
            kSecAttrAccessible as String: kSecAttrAccessibleWhenUnlockedThisDeviceOnly
        ]
    }
}
