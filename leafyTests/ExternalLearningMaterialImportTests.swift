import SwiftData
import UniformTypeIdentifiers
import XCTest
@testable import Leafy

final class ExternalLearningMaterialImportTests: XCTestCase {
    func testExternalImportSupportsOnlyCommonStudyDocumentTypes() {
        XCTAssertTrue(ExternalLearningMaterialImport.isSupported(filename: "资料.pdf"))
        XCTAssertTrue(ExternalLearningMaterialImport.isSupported(filename: "图片.heic", contentTypeIdentifier: UTType.heic.identifier))
        XCTAssertTrue(ExternalLearningMaterialImport.isSupported(filename: "课程.docx"))
        XCTAssertTrue(ExternalLearningMaterialImport.isSupported(filename: "答辩.pptx"))

        XCTAssertFalse(ExternalLearningMaterialImport.isSupported(filename: "成绩.xlsx"))
        XCTAssertFalse(ExternalLearningMaterialImport.isSupported(filename: "说明.txt"))
        XCTAssertFalse(ExternalLearningMaterialImport.isSupported(filename: "资料.zip"))
        XCTAssertFalse(ExternalLearningMaterialImport.isSupported(filename: "压缩包.rar"))
    }

    func testExternalImportManifestRoundTripsAndCleansStagingBatch() throws {
        let root = temporaryDirectory()
        let store = ExternalLearningMaterialImportStore(rootDirectory: root)
        let sourceURL = root.appendingPathComponent("source.pdf")
        try Data("pdf".utf8).write(to: sourceURL)
        let batchID = try XCTUnwrap(UUID(uuidString: "00000000-0000-0000-0000-000000000888"))

        let manifest = try store.makeBatch(from: [sourceURL], source: .shareExtension, id: batchID)

        XCTAssertEqual(manifest.id, batchID)
        XCTAssertEqual(manifest.source, .shareExtension)
        XCTAssertEqual(manifest.items.map(\.originalFilename), ["source.pdf"])
        XCTAssertEqual(try store.loadManifest(id: batchID), manifest)
        XCTAssertTrue(FileManager.default.fileExists(atPath: try store.stagedFileURL(for: manifest.items[0], in: manifest).path(percentEncoded: false)))

        try store.removeBatch(batchID)

        XCTAssertThrowsError(try store.loadManifest(id: batchID))
    }

    @MainActor
    func testCoordinatorImportsBatchToFixedAndProjectDestinations() throws {
        let root = temporaryDirectory()
        let store = ExternalLearningMaterialImportStore(rootDirectory: root)
        let sourceURL = root.appendingPathComponent("课件.pdf")
        try Data("pdf".utf8).write(to: sourceURL)
        let manifest = try store.makeBatch(from: [sourceURL], source: .openIn)
        let setup = AppModelContainerFactory.make()
        let coordinator = ExternalLearningMaterialImportCoordinator(store: store)
        let appNavigation = AppNavigationCoordinator()

        let fixedCount = try coordinator.importBatch(
            manifest,
            to: .fixed(.courseware),
            modelContext: setup.container.mainContext,
            appNavigation: appNavigation
        )

        XCTAssertEqual(fixedCount, 1)
        XCTAssertEqual(appNavigation.selectedRootTab, .academics)
        XCTAssertEqual(appNavigation.selectedAcademicTab, .learning)

        let fixedMaterials = try setup.container.mainContext.fetch(FetchDescriptor<LearningMaterialDocument>())
        XCTAssertEqual(fixedMaterials.count, 1)
        XCTAssertEqual(fixedMaterials[0].projectID, "")
        XCTAssertEqual(fixedMaterials[0].category, .courseware)
        XCTAssertEqual(fixedMaterials[0].originalFilename, "课件.pdf")
        XCTAssertEqual(fixedMaterials[0].contentTypeIdentifier, UTType.pdf.identifier)

        let projectID = try XCTUnwrap(UUID(uuidString: "00000000-0000-0000-0000-000000000889"))
        let projectSourceURL = root.appendingPathComponent("项目.pptx")
        try Data("ppt".utf8).write(to: projectSourceURL)
        let projectManifest = try store.makeBatch(from: [projectSourceURL], source: .openIn)

        _ = try coordinator.importBatch(
            projectManifest,
            to: .project(projectID),
            modelContext: setup.container.mainContext,
            appNavigation: appNavigation
        )

        let allMaterials = try setup.container.mainContext.fetch(FetchDescriptor<LearningMaterialDocument>())
        let projectMaterial = try XCTUnwrap(allMaterials.first { $0.originalFilename == "项目.pptx" })
        XCTAssertEqual(projectMaterial.projectID, projectID.uuidString)
        XCTAssertEqual(projectMaterial.category, .other)
    }

    func testLearningWorkspaceCallbackParsesBatchID() throws {
        let batchID = try XCTUnwrap(UUID(uuidString: "00000000-0000-0000-0000-000000000777"))
        let url = ExternalLearningMaterialImport.callbackURL(for: batchID)

        XCTAssertEqual(ExternalLearningMaterialImport.batchID(from: url), batchID)
        XCTAssertNil(ExternalLearningMaterialImport.batchID(from: URL(string: "leafy://community-post?id=\(batchID.uuidString)")!))
    }

    private func temporaryDirectory() -> URL {
        let url = FileManager.default.temporaryDirectory
            .appendingPathComponent("ExternalLearningMaterialImportTests", isDirectory: true)
            .appendingPathComponent(UUID().uuidString, isDirectory: true)
        try? FileManager.default.createDirectory(at: url, withIntermediateDirectories: true)
        addTeardownBlock {
            try? FileManager.default.removeItem(at: url)
        }
        return url
    }
}
