import Foundation
import UniformTypeIdentifiers
import UIKit

final class ShareViewController: UIViewController {
    private let statusLabel = UILabel()
    private let doneButton = UIButton(type: .system)
    private var didStartImport = false

    override func viewDidLoad() {
        super.viewDidLoad()
        view.backgroundColor = .systemBackground

        statusLabel.text = "正在保存到 MyLeafy..."
        statusLabel.textAlignment = .center
        statusLabel.numberOfLines = 0
        statusLabel.font = .preferredFont(forTextStyle: .body)

        doneButton.setTitle("完成", for: .normal)
        doneButton.titleLabel?.font = .preferredFont(forTextStyle: .headline)
        doneButton.isHidden = true
        doneButton.addTarget(self, action: #selector(closeExtension), for: .touchUpInside)

        let stack = UIStackView(arrangedSubviews: [statusLabel, doneButton])
        stack.axis = .vertical
        stack.alignment = .center
        stack.spacing = 18
        stack.translatesAutoresizingMaskIntoConstraints = false
        view.addSubview(stack)

        NSLayoutConstraint.activate([
            stack.leadingAnchor.constraint(equalTo: view.layoutMarginsGuide.leadingAnchor),
            stack.trailingAnchor.constraint(equalTo: view.layoutMarginsGuide.trailingAnchor),
            stack.centerYAnchor.constraint(equalTo: view.centerYAnchor)
        ])
    }

    override func viewDidAppear(_ animated: Bool) {
        super.viewDidAppear(animated)
        guard !didStartImport else { return }
        didStartImport = true

        Task {
            await importSharedItems()
        }
    }

    private func importSharedItems() async {
        do {
            let providers = itemProviders()
            guard !providers.isEmpty else {
                throw ExternalLearningMaterialImportError.emptyBatch
            }

            let store = try ExternalLearningMaterialImportStore.appGroupStore()
            let batchID = UUID()
            try store.prepareBatchDirectory(batchID)

            var items: [ExternalLearningMaterialImportItem] = []
            for provider in providers {
                if let item = try await stageProvider(provider, store: store, batchID: batchID) {
                    items.append(item)
                }
            }

            guard !items.isEmpty else {
                try? store.removeBatch(batchID)
                throw ExternalLearningMaterialImportError.emptyBatch
            }

            let manifest = ExternalLearningMaterialImportManifest(
                id: batchID,
                source: .shareExtension,
                items: items
            )
            try store.writeManifest(manifest)
            await openContainingApp(batchID: batchID)
        } catch {
            showManualOpenMessage(error.localizedDescription)
        }
    }

    private func itemProviders() -> [NSItemProvider] {
        guard let extensionItems = extensionContext?.inputItems as? [NSExtensionItem] else {
            return []
        }
        return extensionItems.flatMap { $0.attachments ?? [] }
    }

    private func stageProvider(
        _ provider: NSItemProvider,
        store: ExternalLearningMaterialImportStore,
        batchID: UUID
    ) async throws -> ExternalLearningMaterialImportItem? {
        guard let typeIdentifier = supportedTypeIdentifier(for: provider) else {
            return nil
        }

        if typeIdentifier == UTType.fileURL.identifier {
            return try await stageFileURLProvider(provider, store: store, batchID: batchID)
        }

        if let item = try? await stageFileRepresentation(
            provider,
            typeIdentifier: typeIdentifier,
            store: store,
            batchID: batchID
        ) {
            return item
        }

        return try await stageDataRepresentation(
            provider,
            typeIdentifier: typeIdentifier,
            store: store,
            batchID: batchID
        )
    }

    private func stageFileRepresentation(
        _ provider: NSItemProvider,
        typeIdentifier: String,
        store: ExternalLearningMaterialImportStore,
        batchID: UUID
    ) async throws -> ExternalLearningMaterialImportItem {
        let suggestedName = provider.suggestedName
        return try await withCheckedThrowingContinuation { (continuation: CheckedContinuation<ExternalLearningMaterialImportItem, Error>) in
            provider.loadFileRepresentation(forTypeIdentifier: typeIdentifier) { url, error in
                if let error {
                    continuation.resume(throwing: error)
                    return
                }
                guard let url else {
                    continuation.resume(throwing: ExternalLearningMaterialImportError.emptyBatch)
                    return
                }

                do {
                    let item = try store.stageFile(
                        from: url,
                        batchID: batchID,
                        sourceContentTypeIdentifier: typeIdentifier,
                        originalFilename: Self.filename(suggestedName: suggestedName, typeIdentifier: typeIdentifier, fileURL: url)
                    )
                    continuation.resume(returning: item)
                } catch {
                    continuation.resume(throwing: error)
                }
            }
        }
    }

    private func stageDataRepresentation(
        _ provider: NSItemProvider,
        typeIdentifier: String,
        store: ExternalLearningMaterialImportStore,
        batchID: UUID
    ) async throws -> ExternalLearningMaterialImportItem? {
        let suggestedName = provider.suggestedName
        return try await withCheckedThrowingContinuation { (continuation: CheckedContinuation<ExternalLearningMaterialImportItem?, Error>) in
            provider.loadDataRepresentation(forTypeIdentifier: typeIdentifier) { data, error in
                if let error {
                    continuation.resume(throwing: error)
                    return
                }
                guard let data else {
                    continuation.resume(returning: nil)
                    return
                }

                do {
                    let item = try store.stageData(
                        data,
                        batchID: batchID,
                        originalFilename: Self.filename(suggestedName: suggestedName, typeIdentifier: typeIdentifier),
                        contentTypeIdentifier: typeIdentifier
                    )
                    continuation.resume(returning: item)
                } catch {
                    continuation.resume(throwing: error)
                }
            }
        }
    }

    private func stageFileURLProvider(
        _ provider: NSItemProvider,
        store: ExternalLearningMaterialImportStore,
        batchID: UUID
    ) async throws -> ExternalLearningMaterialImportItem? {
        try await withCheckedThrowingContinuation { (continuation: CheckedContinuation<ExternalLearningMaterialImportItem?, Error>) in
            provider.loadItem(forTypeIdentifier: UTType.fileURL.identifier, options: nil) { item, error in
                if let error {
                    continuation.resume(throwing: error)
                    return
                }

                let url: URL?
                if let fileURL = item as? URL {
                    url = fileURL
                } else if let data = item as? Data {
                    url = URL(dataRepresentation: data, relativeTo: nil)
                } else {
                    url = nil
                }

                guard let url else {
                    continuation.resume(returning: nil)
                    return
                }

                do {
                    let item = try store.stageFile(from: url, batchID: batchID)
                    continuation.resume(returning: item)
                } catch {
                    continuation.resume(throwing: error)
                }
            }
        }
    }

    private func supportedTypeIdentifier(for provider: NSItemProvider) -> String? {
        for identifier in ExternalLearningMaterialImport.supportedContentTypeIdentifiers
        where provider.hasItemConformingToTypeIdentifier(identifier) {
            return identifier
        }

        if provider.hasItemConformingToTypeIdentifier(UTType.fileURL.identifier) {
            return UTType.fileURL.identifier
        }

        return provider.registeredTypeIdentifiers.first { identifier in
            ExternalLearningMaterialImport.isSupported(
                filename: provider.suggestedName ?? "",
                contentTypeIdentifier: identifier
            )
        }
    }

    private static func filename(
        suggestedName: String?,
        typeIdentifier: String,
        fileURL: URL? = nil
    ) -> String {
        let candidate = fileURL?.lastPathComponent ?? suggestedName ?? "学习资料"
        let normalized = ExternalLearningMaterialImport.normalizedFilename(candidate)
        guard (normalized as NSString).pathExtension.isEmpty,
              let fileExtension = UTType(typeIdentifier)?.preferredFilenameExtension
        else {
            return normalized
        }
        return "\(normalized).\(fileExtension)"
    }

    @MainActor
    private func openContainingApp(batchID: UUID) async {
        statusLabel.text = "已暂存，正在打开 MyLeafy..."
        let callbackURL = ExternalLearningMaterialImport.callbackURL(for: batchID)
        let success = await extensionContext?.open(callbackURL) ?? false
        if success {
            extensionContext?.completeRequest(returningItems: nil)
        } else {
            showManualOpenMessage("文件已暂存，请手动打开 MyLeafy 完成保存。")
        }
    }

    @MainActor
    private func showManualOpenMessage(_ message: String) {
        statusLabel.text = message
        doneButton.isHidden = false
    }

    @objc
    private func closeExtension() {
        extensionContext?.completeRequest(returningItems: nil)
    }
}
