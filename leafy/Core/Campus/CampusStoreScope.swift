import Foundation
import SwiftData

enum CampusStoreScope {
    private static let migrationPrefix = "leafy.campus.storeMigration.v1"

    static func configuration(
        schema: Schema,
        legacyConfiguration: ModelConfiguration,
        identity: CampusIdentity? = CampusIdentityStore.currentIdentity(),
        defaults: UserDefaults = .standard
    ) -> ModelConfiguration {
        guard let identity,
              let scopedURL = scopedStoreURL(for: identity) else {
            return legacyConfiguration
        }

        guard migrateLegacyStoreIfNeeded(
            from: legacyConfiguration.url,
            to: scopedURL,
            identity: identity,
            defaults: defaults
        ) else {
            return legacyConfiguration
        }

        return ModelConfiguration(
            "Leafy-\(identity.scopeKey)",
            schema: schema,
            url: scopedURL
        )
    }

    static func scopedStoreURL(for identity: CampusIdentity) -> URL? {
        guard let applicationSupport = FileManager.default.urls(
            for: .applicationSupportDirectory,
            in: .userDomainMask
        ).first else {
            return nil
        }

        return applicationSupport
            .appendingPathComponent("CampusStores", isDirectory: true)
            .appendingPathComponent(identity.scopeKey, isDirectory: true)
            .appendingPathComponent("Leafy.store")
    }

    private static func migrateLegacyStoreIfNeeded(
        from legacyURL: URL,
        to scopedURL: URL,
        identity: CampusIdentity,
        defaults: UserDefaults
    ) -> Bool {
        let marker = "\(migrationPrefix).\(identity.scopeKey)"
        let fileManager = FileManager.default

        if defaults.bool(forKey: marker) || fileManager.fileExists(atPath: scopedURL.path(percentEncoded: false)) {
            defaults.set(true, forKey: marker)
            return true
        }

        do {
            try fileManager.createDirectory(
                at: scopedURL.deletingLastPathComponent(),
                withIntermediateDirectories: true
            )

            if fileManager.fileExists(atPath: legacyURL.path(percentEncoded: false)) {
                try copyStoreFiles(from: legacyURL, to: scopedURL, fileManager: fileManager)
            }

            defaults.set(true, forKey: marker)
            return true
        } catch {
            removeStoreFiles(at: scopedURL, fileManager: fileManager)
            return false
        }
    }

    private static func copyStoreFiles(from source: URL, to destination: URL, fileManager: FileManager) throws {
        for suffix in ["", "-shm", "-wal"] {
            let sourceURL = URL(fileURLWithPath: source.path(percentEncoded: false) + suffix)
            guard fileManager.fileExists(atPath: sourceURL.path(percentEncoded: false)) else { continue }
            let destinationURL = URL(fileURLWithPath: destination.path(percentEncoded: false) + suffix)
            if fileManager.fileExists(atPath: destinationURL.path(percentEncoded: false)) {
                try fileManager.removeItem(at: destinationURL)
            }
            try fileManager.copyItem(at: sourceURL, to: destinationURL)
        }
    }

    private static func removeStoreFiles(at url: URL, fileManager: FileManager) {
        for suffix in ["", "-shm", "-wal"] {
            let candidate = URL(fileURLWithPath: url.path(percentEncoded: false) + suffix)
            try? fileManager.removeItem(at: candidate)
        }
    }
}
