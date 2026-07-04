import Foundation
import UniformTypeIdentifiers

enum ExternalLearningMaterialImportError: LocalizedError, Equatable {
    case appGroupUnavailable
    case unsupportedFile(String)
    case emptyBatch
    case missingBatch(UUID)
    case missingStagedFile(String)

    var errorDescription: String? {
        switch self {
        case .appGroupUnavailable:
            return "无法访问 MyLeafy 共享暂存目录。"
        case .unsupportedFile(let filename):
            return "暂不支持导入 \(filename)。请使用 PDF、图片、Word 或 PPT 文件。"
        case .emptyBatch:
            return "没有找到可导入的文件。请使用 PDF、图片、Word 或 PPT 文件。"
        case .missingBatch:
            return "这批外部文件暂存记录已失效，请重新从微信或 QQ 打开。"
        case .missingStagedFile(let filename):
            return "无法找到暂存文件 \(filename)，请重新导入。"
        }
    }
}

nonisolated enum ExternalLearningMaterialImportSource: String, Codable, Equatable, Sendable {
    case openIn
    case shareExtension
}

nonisolated struct ExternalLearningMaterialImportItem: Identifiable, Codable, Equatable, Sendable {
    let id: UUID
    let originalFilename: String
    let stagedFilename: String
    let contentTypeIdentifier: String
    let byteCount: Int64
}

nonisolated struct ExternalLearningMaterialImportManifest: Identifiable, Codable, Equatable, Sendable {
    let id: UUID
    let source: ExternalLearningMaterialImportSource
    let createdAt: Date
    var items: [ExternalLearningMaterialImportItem]

    init(
        id: UUID = UUID(),
        source: ExternalLearningMaterialImportSource,
        createdAt: Date = Date(),
        items: [ExternalLearningMaterialImportItem]
    ) {
        self.id = id
        self.source = source
        self.createdAt = createdAt
        self.items = items
    }
}

enum ExternalLearningMaterialImport {
    static let appGroupIdentifier = "group.com.isaachuo.leafy"
    static let callbackScheme = "leafy"
    static let callbackHost = "learning-material-import"
    static let stagingDirectoryName = "ExternalLearningMaterialImports"
    static let manifestFilename = "manifest.json"

    static let supportedContentTypes: [UTType] = [
        .pdf,
        .image,
        UTType(filenameExtension: "doc") ?? .data,
        UTType(filenameExtension: "docx") ?? .data,
        UTType(filenameExtension: "ppt") ?? .data,
        UTType(filenameExtension: "pptx") ?? .data
    ]

    static let supportedContentTypeIdentifiers: [String] = supportedContentTypes.map(\.identifier)

    static func callbackURL(for batchID: UUID) -> URL {
        var components = URLComponents()
        components.scheme = callbackScheme
        components.host = callbackHost
        components.queryItems = [
            URLQueryItem(name: "batch", value: batchID.uuidString)
        ]
        return components.url ?? URL(string: "\(callbackScheme)://\(callbackHost)?batch=\(batchID.uuidString)")!
    }

    static func batchID(from url: URL) -> UUID? {
        guard url.scheme == callbackScheme, url.host == callbackHost else { return nil }
        let batchValue = URLComponents(url: url, resolvingAgainstBaseURL: false)?
            .queryItems?
            .first(where: { $0.name == "batch" })?
            .value
        return batchValue.flatMap(UUID.init(uuidString:))
    }

    static func isSupported(filename: String, contentTypeIdentifier: String? = nil) -> Bool {
        let lowercasedFilename = filename.lowercased()
        if lowercasedFilename.hasSuffix(".doc") ||
            lowercasedFilename.hasSuffix(".docx") ||
            lowercasedFilename.hasSuffix(".ppt") ||
            lowercasedFilename.hasSuffix(".pptx") {
            return true
        }

        guard let contentType = contentType(filename: filename, contentTypeIdentifier: contentTypeIdentifier) else {
            return false
        }
        if contentType.conforms(to: .pdf) || contentType.conforms(to: .image) {
            return true
        }

        let identifier = contentType.identifier.lowercased()
        return identifier.contains("word") ||
            identifier.contains("powerpoint") ||
            identifier.contains("presentation")
    }

    static func contentType(filename: String, contentTypeIdentifier: String? = nil) -> UTType? {
        if let contentTypeIdentifier,
           let type = UTType(contentTypeIdentifier) {
            return type
        }
        let fileExtension = (filename as NSString).pathExtension
        guard !fileExtension.isEmpty else { return nil }
        return UTType(filenameExtension: fileExtension)
    }

    static func normalizedFilename(_ filename: String, fallback: String = "学习资料") -> String {
        let trimmed = filename.trimmingCharacters(in: .whitespacesAndNewlines)
        return trimmed.isEmpty ? fallback : trimmed
    }
}

struct ExternalLearningMaterialImportStore {
    let rootDirectory: URL
    let fileManager: FileManager

    init(rootDirectory: URL, fileManager: FileManager = .default) {
        self.rootDirectory = rootDirectory
        self.fileManager = fileManager
    }

    static func appGroupStore(fileManager: FileManager = .default) throws -> ExternalLearningMaterialImportStore {
        guard let container = fileManager.containerURL(
            forSecurityApplicationGroupIdentifier: ExternalLearningMaterialImport.appGroupIdentifier
        ) else {
            throw ExternalLearningMaterialImportError.appGroupUnavailable
        }
        return ExternalLearningMaterialImportStore(
            rootDirectory: container.appendingPathComponent(
                ExternalLearningMaterialImport.stagingDirectoryName,
                isDirectory: true
            ),
            fileManager: fileManager
        )
    }

    func makeBatch(
        from urls: [URL],
        source: ExternalLearningMaterialImportSource,
        id: UUID = UUID()
    ) throws -> ExternalLearningMaterialImportManifest {
        var items: [ExternalLearningMaterialImportItem] = []
        try prepareBatchDirectory(id)

        for url in urls {
            let item = try stageFile(from: url, batchID: id)
            items.append(item)
        }

        guard !items.isEmpty else {
            try? removeBatch(id)
            throw ExternalLearningMaterialImportError.emptyBatch
        }

        let manifest = ExternalLearningMaterialImportManifest(
            id: id,
            source: source,
            items: items
        )
        try writeManifest(manifest)
        return manifest
    }

    func prepareBatchDirectory(_ batchID: UUID) throws {
        try fileManager.createDirectory(
            at: batchDirectoryURL(for: batchID),
            withIntermediateDirectories: true
        )
    }

    func stageFile(
        from sourceURL: URL,
        batchID: UUID,
        sourceContentTypeIdentifier: String? = nil,
        originalFilename: String? = nil,
        itemID: UUID = UUID()
    ) throws -> ExternalLearningMaterialImportItem {
        let filename = ExternalLearningMaterialImport.normalizedFilename(
            originalFilename ?? sourceURL.lastPathComponent
        )
        let contentTypeIdentifier = sourceContentTypeIdentifier ??
            ExternalLearningMaterialImport.contentType(filename: filename)?.identifier ??
            sourceURL.resourceContentType?.identifier ??
            UTType.data.identifier

        guard ExternalLearningMaterialImport.isSupported(
            filename: filename,
            contentTypeIdentifier: contentTypeIdentifier
        ) else {
            throw ExternalLearningMaterialImportError.unsupportedFile(filename)
        }

        try prepareBatchDirectory(batchID)
        let stagedFilename = stagedFilename(for: itemID, originalFilename: filename)
        let destinationURL = batchDirectoryURL(for: batchID).appendingPathComponent(stagedFilename)

        let didAccess = sourceURL.startAccessingSecurityScopedResource()
        defer {
            if didAccess {
                sourceURL.stopAccessingSecurityScopedResource()
            }
        }

        if fileManager.fileExists(atPath: destinationURL.path(percentEncoded: false)) {
            try fileManager.removeItem(at: destinationURL)
        }
        try fileManager.copyItem(at: sourceURL, to: destinationURL)

        return ExternalLearningMaterialImportItem(
            id: itemID,
            originalFilename: filename,
            stagedFilename: stagedFilename,
            contentTypeIdentifier: contentTypeIdentifier,
            byteCount: byteCount(for: destinationURL)
        )
    }

    func stageData(
        _ data: Data,
        batchID: UUID,
        originalFilename: String,
        contentTypeIdentifier: String,
        itemID: UUID = UUID()
    ) throws -> ExternalLearningMaterialImportItem {
        let filename = ExternalLearningMaterialImport.normalizedFilename(originalFilename)
        guard ExternalLearningMaterialImport.isSupported(
            filename: filename,
            contentTypeIdentifier: contentTypeIdentifier
        ) else {
            throw ExternalLearningMaterialImportError.unsupportedFile(filename)
        }

        try prepareBatchDirectory(batchID)
        let stagedFilename = stagedFilename(for: itemID, originalFilename: filename)
        let destinationURL = batchDirectoryURL(for: batchID).appendingPathComponent(stagedFilename)
        try data.write(to: destinationURL, options: [.atomic])

        return ExternalLearningMaterialImportItem(
            id: itemID,
            originalFilename: filename,
            stagedFilename: stagedFilename,
            contentTypeIdentifier: contentTypeIdentifier,
            byteCount: Int64(data.count)
        )
    }

    func writeManifest(_ manifest: ExternalLearningMaterialImportManifest) throws {
        try prepareBatchDirectory(manifest.id)
        let encoder = JSONEncoder()
        encoder.dateEncodingStrategy = Self.preciseISO8601DateEncodingStrategy
        let data = try encoder.encode(manifest)
        try data.write(to: manifestURL(for: manifest.id), options: [.atomic])
    }

    func loadManifest(id: UUID) throws -> ExternalLearningMaterialImportManifest {
        let url = manifestURL(for: id)
        guard fileManager.fileExists(atPath: url.path(percentEncoded: false)) else {
            throw ExternalLearningMaterialImportError.missingBatch(id)
        }
        let decoder = JSONDecoder()
        decoder.dateDecodingStrategy = Self.preciseISO8601DateDecodingStrategy
        return try decoder.decode(
            ExternalLearningMaterialImportManifest.self,
            from: Data(contentsOf: url)
        )
    }

    func pendingManifests() -> [ExternalLearningMaterialImportManifest] {
        guard let batchDirectories = try? fileManager.contentsOfDirectory(
            at: rootDirectory,
            includingPropertiesForKeys: nil
        ) else { return [] }

        return batchDirectories.compactMap { directory in
            guard let batchID = UUID(uuidString: directory.lastPathComponent) else { return nil }
            return try? loadManifest(id: batchID)
        }
        .sorted { $0.createdAt > $1.createdAt }
    }

    func stagedFileURL(for item: ExternalLearningMaterialImportItem, in manifest: ExternalLearningMaterialImportManifest) throws -> URL {
        let url = batchDirectoryURL(for: manifest.id).appendingPathComponent(item.stagedFilename)
        guard fileManager.fileExists(atPath: url.path(percentEncoded: false)) else {
            throw ExternalLearningMaterialImportError.missingStagedFile(item.originalFilename)
        }
        return url
    }

    func removeBatch(_ id: UUID) throws {
        let url = batchDirectoryURL(for: id)
        if fileManager.fileExists(atPath: url.path(percentEncoded: false)) {
            try fileManager.removeItem(at: url)
        }
    }

    func batchDirectoryURL(for id: UUID) -> URL {
        rootDirectory.appendingPathComponent(id.uuidString, isDirectory: true)
    }

    private func manifestURL(for id: UUID) -> URL {
        batchDirectoryURL(for: id).appendingPathComponent(ExternalLearningMaterialImport.manifestFilename)
    }

    private func stagedFilename(for itemID: UUID, originalFilename: String) -> String {
        let fileExtension = (originalFilename as NSString).pathExtension
            .trimmingCharacters(in: CharacterSet(charactersIn: ".").union(.whitespacesAndNewlines))
        guard !fileExtension.isEmpty else { return itemID.uuidString }
        return "\(itemID.uuidString).\(fileExtension)"
    }

    private func byteCount(for url: URL) -> Int64 {
        let values = try? url.resourceValues(forKeys: [.fileSizeKey])
        return Int64(values?.fileSize ?? 0)
    }

    private static var preciseISO8601DateEncodingStrategy: JSONEncoder.DateEncodingStrategy {
        .custom { date, encoder in
            var container = encoder.singleValueContainer()
            try container.encode(date.timeIntervalSinceReferenceDate)
        }
    }

    private static var preciseISO8601DateDecodingStrategy: JSONDecoder.DateDecodingStrategy {
        .custom { decoder in
            let container = try decoder.singleValueContainer()
            if let timestamp = try? container.decode(Double.self) {
                return Date(timeIntervalSinceReferenceDate: timestamp)
            }

            let value = try container.decode(String.self)

            let preciseFormatter = ISO8601DateFormatter()
            preciseFormatter.formatOptions = [.withInternetDateTime, .withFractionalSeconds]
            if let date = preciseFormatter.date(from: value) {
                return date
            }

            let legacyFormatter = ISO8601DateFormatter()
            if let date = legacyFormatter.date(from: value) {
                return date
            }

            throw DecodingError.dataCorruptedError(
                in: container,
                debugDescription: "Invalid ISO8601 date: \(value)"
            )
        }
    }
}

private extension URL {
    var resourceContentType: UTType? {
        (try? resourceValues(forKeys: [.contentTypeKey]))?.contentType
    }
}
