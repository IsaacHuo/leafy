import Foundation
import SwiftData

struct AppModelContainerSetup {
    let container: ModelContainer
    let recoveryMessage: String?
}

nonisolated enum AppRuntimeEnvironment {
    static let isRunningUnitTests = ProcessInfo.processInfo.environment["XCTestConfigurationFilePath"] != nil
}

enum AppModelContainerFactory {
    static func make() -> AppModelContainerSetup {
        let schema = Schema([
            Course.self, Grade.self,
            CourseNote.self, CourseOccurrenceNote.self, CourseReminderSetting.self, TimetableCellReminder.self,
            FavoriteClassroom.self, FavoriteCampusLink.self, PostgraduateTarget.self, StudyTimeRecord.self, HonorRecord.self,
            LearningMaterialDocument.self, LearningProject.self, LearningProjectTask.self,
            CareerResumeDocument.self, CareerTask.self, CareerOpportunity.self,
            FitnessTestRecord.self,
            ComprehensiveQualityRecord.self, ComprehensiveQualityComponentEntry.self, ComprehensiveQualityEvidenceDocument.self,
            CampusAIConversation.self, CampusAIMessage.self, CampusAIActionRecord.self,
            MedicalLedgerEntry.self, MedicalLedgerPhoto.self,
        ])
        let modelConfiguration: ModelConfiguration
        if AppRuntimeEnvironment.isRunningUnitTests {
            modelConfiguration = ModelConfiguration(schema: schema, isStoredInMemoryOnly: true)
        } else {
            let legacyConfiguration = ModelConfiguration(schema: schema, isStoredInMemoryOnly: false)
            modelConfiguration = CampusStoreScope.configuration(
                schema: schema,
                legacyConfiguration: legacyConfiguration
            )
        }

        do {
            let container = try ModelContainer(for: schema, configurations: [modelConfiguration])
            return AppModelContainerSetup(container: container, recoveryMessage: nil)
        } catch {
            let backupURL = backupModelStore(at: modelConfiguration.url)

            do {
                let container = try ModelContainer(for: schema, configurations: [modelConfiguration])
                let backupText = backupURL
                    .map { L10n.text("旧缓存已备份到 %@。", $0.lastPathComponent) }
                    ?? L10n.text("未发现可备份的旧缓存文件。")
                return AppModelContainerSetup(
                    container: container,
                    recoveryMessage: L10n.text("本地课表和成绩缓存无法直接打开，已自动重建缓存。%@", backupText)
                )
            } catch let rebuildError {
                let memoryConfiguration = ModelConfiguration(schema: schema, isStoredInMemoryOnly: true)

                do {
                    let container = try ModelContainer(for: schema, configurations: [memoryConfiguration])
                    let backupText = backupURL
                        .map { L10n.text("旧缓存已备份到 %@。", $0.lastPathComponent) }
                        ?? L10n.text("未发现可备份的旧缓存文件。")
                    return AppModelContainerSetup(
                        container: container,
                        recoveryMessage: L10n.text("本地缓存暂时无法重建，已使用临时空缓存启动。%@ 原始错误：%@", backupText, rebuildError.localizedDescription)
                    )
                } catch {
                    preconditionFailure("Could not create in-memory ModelContainer: \(error)")
                }
            }
        }
    }

    private static func backupModelStore(at url: URL) -> URL? {
        let fileManager = FileManager.default
        let timestamp = ISO8601DateFormatter()
            .string(from: Date())
            .replacingOccurrences(of: ":", with: "-")
        let backupDirectory = url
            .deletingLastPathComponent()
            .appendingPathComponent("LeafyStoreBackups", isDirectory: true)
            .appendingPathComponent(timestamp, isDirectory: true)

        do {
            try fileManager.createDirectory(at: backupDirectory, withIntermediateDirectories: true)
        } catch {
            return nil
        }

        let storePath = url.path(percentEncoded: false)
        let candidates = [
            url,
            URL(fileURLWithPath: storePath + "-shm"),
            URL(fileURLWithPath: storePath + "-wal")
        ]

        var didMoveFile = false
        for fileURL in candidates where fileManager.fileExists(atPath: fileURL.path(percentEncoded: false)) {
            let destination = backupDirectory.appendingPathComponent(fileURL.lastPathComponent)
            do {
                try fileManager.moveItem(at: fileURL, to: destination)
                didMoveFile = true
            } catch {
                try? fileManager.copyItem(at: fileURL, to: destination)
                try? fileManager.removeItem(at: fileURL)
                didMoveFile = true
            }
        }

        return didMoveFile ? backupDirectory : nil
    }
}
