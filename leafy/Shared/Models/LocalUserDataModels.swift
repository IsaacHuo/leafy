import Foundation
import SwiftData
import UniformTypeIdentifiers

@Model
final class CourseNote {
    var id: UUID
    var courseKey: String
    var text: String
    var updatedAt: Date

    init(id: UUID = UUID(), courseKey: String, text: String = "", updatedAt: Date = Date()) {
        self.id = id
        self.courseKey = courseKey
        self.text = text
        self.updatedAt = updatedAt
    }
}

@Model
final class CourseOccurrenceNote {
    var id: UUID
    var courseKey: String
    var occurrenceKey: String
    var week: Int
    var dayOfWeek: Int
    var text: String
    var updatedAt: Date

    init(
        id: UUID = UUID(),
        courseKey: String,
        occurrenceKey: String,
        week: Int,
        dayOfWeek: Int,
        text: String = "",
        updatedAt: Date = Date()
    ) {
        self.id = id
        self.courseKey = courseKey
        self.occurrenceKey = occurrenceKey
        self.week = week
        self.dayOfWeek = dayOfWeek
        self.text = text
        self.updatedAt = updatedAt
    }

    static func occurrenceKey(courseKey: String, week: Int) -> String {
        "\(courseKey)|week:\(week)"
    }
}

@Model
final class CourseReminderSetting {
    var id: UUID
    var courseKey: String
    var minutesBefore: Int
    var anchorPeriod: Int?
    var updatedAt: Date

    init(
        id: UUID = UUID(),
        courseKey: String,
        minutesBefore: Int = 0,
        anchorPeriod: Int? = nil,
        updatedAt: Date = Date()
    ) {
        self.id = id
        self.courseKey = courseKey
        self.minutesBefore = minutesBefore
        self.anchorPeriod = anchorPeriod
        self.updatedAt = updatedAt
    }
}

@Model
final class TimetableCellReminder {
    var id: UUID
    var cellKey: String
    var week: Int
    var dayOfWeek: Int
    var period: Int
    var endPeriod: Int?
    var title: String
    var location: String?
    var note: String?
    var startsAt: Date?
    var endsAt: Date?
    var minutesBefore: Int
    var updatedAt: Date

    init(
        id: UUID = UUID(),
        week: Int,
        dayOfWeek: Int,
        period: Int,
        endPeriod: Int? = nil,
        title: String,
        location: String = "",
        note: String = "",
        startsAt: Date? = nil,
        endsAt: Date? = nil,
        minutesBefore: Int = 0,
        updatedAt: Date = Date()
    ) {
        self.id = id
        self.cellKey = Self.cellKey(week: week, dayOfWeek: dayOfWeek, period: period)
        self.week = week
        self.dayOfWeek = dayOfWeek
        self.period = period
        self.endPeriod = endPeriod
        self.title = title
        self.location = Self.normalizedOptionalText(location)
        self.note = Self.normalizedOptionalText(note)
        self.startsAt = startsAt
        self.endsAt = endsAt
        self.minutesBefore = minutesBefore
        self.updatedAt = updatedAt
    }

    static func cellKey(week: Int, dayOfWeek: Int, period: Int) -> String {
        "\(week)-\(dayOfWeek)-\(period)"
    }

    static func normalizedOptionalText(_ text: String) -> String? {
        let trimmed = text.trimmingCharacters(in: .whitespacesAndNewlines)
        return trimmed.isEmpty ? nil : trimmed
    }

    var locationText: String {
        location?.trimmingCharacters(in: .whitespacesAndNewlines) ?? ""
    }

    var noteText: String {
        note?.trimmingCharacters(in: .whitespacesAndNewlines) ?? ""
    }

    var displayStartPeriod: Int {
        max(1, min(period, TimetablePeriodSchedule.slots.last?.period ?? period))
    }

    var displayEndPeriod: Int {
        max(displayStartPeriod, min(endPeriod ?? displayStartPeriod, TimetablePeriodSchedule.slots.last?.period ?? displayStartPeriod))
    }

    var displayPeriodRange: ClosedRange<Int> {
        displayStartPeriod...displayEndPeriod
    }

    var resolvedStartDate: Date? {
        startsAt ?? TimetablePeriodSchedule.startDate(week: week, dayOfWeek: dayOfWeek, period: displayStartPeriod)
    }

    var resolvedEndDate: Date? {
        if let startsAt, let endsAt, endsAt > startsAt {
            return endsAt
        }

        return TimetablePeriodSchedule.endDate(week: week, dayOfWeek: dayOfWeek, period: displayEndPeriod)
    }
}

@Model
final class FavoriteClassroom {
    var id: UUID
    var building: String
    var room: String
    var createdAt: Date

    init(id: UUID = UUID(), building: String, room: String, createdAt: Date = Date()) {
        self.id = id
        self.building = building
        self.room = room
        self.createdAt = createdAt
    }

    var displayName: String {
        "\(building) \(room)"
    }
}

@Model
final class FavoriteCampusLink {
    var id: UUID
    var title: String
    var urlString: String
    var createdAt: Date

    init(id: UUID = UUID(), title: String, urlString: String, createdAt: Date = Date()) {
        self.id = id
        self.title = title
        self.urlString = urlString
        self.createdAt = createdAt
    }
}

enum PostgraduateTargetState: String, CaseIterable, Identifiable {
    case active
    case focused
    case archived

    var id: String { rawValue }

    static func normalized(_ rawValue: String) -> PostgraduateTargetState {
        PostgraduateTargetState(rawValue: rawValue) ?? .active
    }
}

@Model
final class PostgraduateTarget {
    var id: UUID
    var school: String
    var unit: String
    var major: String
    var direction: String
    var examYear: Int
    var subjects: String
    var scoreAndPlanNote: String
    var personalNote: String
    var stateRawValue: String
    var createdAt: Date
    var updatedAt: Date

    init(
        id: UUID = UUID(),
        school: String,
        unit: String = "",
        major: String,
        direction: String = "",
        examYear: Int = Calendar.current.component(.year, from: Date()) + 1,
        subjects: String = "",
        scoreAndPlanNote: String = "",
        personalNote: String = "",
        stateRawValue: String = PostgraduateTargetState.active.rawValue,
        createdAt: Date = Date(),
        updatedAt: Date = Date()
    ) {
        self.id = id
        self.school = school
        self.unit = unit
        self.major = major
        self.direction = direction
        self.examYear = examYear
        self.subjects = subjects
        self.scoreAndPlanNote = scoreAndPlanNote
        self.personalNote = personalNote
        self.stateRawValue = stateRawValue
        self.createdAt = createdAt
        self.updatedAt = updatedAt
    }
}

@Model
final class StudyTimeRecord {
    var id: UUID
    var projectID: String
    var categoryRawValue: String
    var startedAt: Date
    var endedAt: Date
    var content: String
    var location: String
    var note: String
    var createdAt: Date
    var updatedAt: Date

    init(
        id: UUID = UUID(),
        projectID: String = "",
        categoryRawValue: String = LearningMaterialCategory.other.rawValue,
        startedAt: Date,
        endedAt: Date,
        content: String,
        location: String,
        note: String = "",
        createdAt: Date = Date(),
        updatedAt: Date = Date()
    ) {
        self.id = id
        self.projectID = projectID
        self.categoryRawValue = categoryRawValue
        self.startedAt = startedAt
        self.endedAt = endedAt
        self.content = content
        self.location = location
        self.note = note
        self.createdAt = createdAt
        self.updatedAt = updatedAt
    }
}

@Model
final class HonorRecord {
    var id: UUID
    var title: String
    var note: String
    var awardedAt: Date
    var importedAt: Date
    var updatedAt: Date
    var originalFilename: String
    var localFilename: String
    var contentTypeIdentifier: String

    init(
        id: UUID = UUID(),
        title: String,
        note: String = "",
        awardedAt: Date = Date(),
        importedAt: Date = Date(),
        updatedAt: Date = Date(),
        originalFilename: String,
        localFilename: String,
        contentTypeIdentifier: String
    ) {
        self.id = id
        self.title = title
        self.note = note
        self.awardedAt = awardedAt
        self.importedAt = importedAt
        self.updatedAt = updatedAt
        self.originalFilename = originalFilename
        self.localFilename = localFilename
        self.contentTypeIdentifier = contentTypeIdentifier
    }
}

@Model
final class LearningMaterialDocument {
    var id: UUID
    var projectID: String
    var title: String
    var note: String
    var categoryRawValue: String
    var courseName: String
    var importedAt: Date
    var updatedAt: Date
    var originalFilename: String
    var localFilename: String
    var contentTypeIdentifier: String

    init(
        id: UUID = UUID(),
        projectID: String = "",
        title: String,
        note: String = "",
        categoryRawValue: String = LearningMaterialCategory.other.rawValue,
        courseName: String = "",
        importedAt: Date = Date(),
        updatedAt: Date = Date(),
        originalFilename: String,
        localFilename: String,
        contentTypeIdentifier: String
    ) {
        self.id = id
        self.projectID = projectID
        self.title = title
        self.note = note
        self.categoryRawValue = categoryRawValue
        self.courseName = courseName
        self.importedAt = importedAt
        self.updatedAt = updatedAt
        self.originalFilename = originalFilename
        self.localFilename = localFilename
        self.contentTypeIdentifier = contentTypeIdentifier
    }
}

nonisolated enum LearningMaterialCategory: String, CaseIterable, Identifiable {
    case cet = "四六级"
    case exam = "考试资料"
    case courseware = "课件"
    case other = "其他"

    var id: String { rawValue }

    static let fixedSpaceOrder: [LearningMaterialCategory] = [.cet, .exam, .courseware, .other]

    static func normalized(_ rawValue: String) -> LearningMaterialCategory {
        LearningMaterialCategory(rawValue: rawValue) ?? .other
    }
}

enum LearningProjectKind: String, CaseIterable, Identifiable {
    case course
    case exam
    case certificate
    case general

    var id: String { rawValue }

    var title: String {
        switch self {
        case .course:
            return "课程"
        case .exam:
            return "考试"
        case .certificate:
            return "证书"
        case .general:
            return "通用"
        }
    }

    static func normalized(_ rawValue: String) -> LearningProjectKind {
        LearningProjectKind(rawValue: rawValue) ?? .general
    }
}

@Model
final class LearningProject {
    var id: UUID
    var title: String
    var kindRawValue: String
    var goal: String
    var createdAt: Date
    var updatedAt: Date
    var isArchived: Bool

    init(
        id: UUID = UUID(),
        title: String,
        kindRawValue: String = LearningProjectKind.general.rawValue,
        goal: String = "",
        createdAt: Date = Date(),
        updatedAt: Date = Date(),
        isArchived: Bool = false
    ) {
        self.id = id
        self.title = title
        self.kindRawValue = kindRawValue
        self.goal = goal
        self.createdAt = createdAt
        self.updatedAt = updatedAt
        self.isArchived = isArchived
    }
}

@Model
final class LearningProjectTask {
    var id: UUID
    var projectID: String
    var categoryRawValue: String
    var title: String
    var note: String
    var dueAt: Date?
    var isCompleted: Bool
    var createdAt: Date
    var updatedAt: Date

    init(
        id: UUID = UUID(),
        projectID: String = "",
        categoryRawValue: String = LearningMaterialCategory.other.rawValue,
        title: String,
        note: String = "",
        dueAt: Date? = nil,
        isCompleted: Bool = false,
        createdAt: Date = Date(),
        updatedAt: Date = Date()
    ) {
        self.id = id
        self.projectID = projectID
        self.categoryRawValue = categoryRawValue
        self.title = title
        self.note = note
        self.dueAt = dueAt
        self.isCompleted = isCompleted
        self.createdAt = createdAt
        self.updatedAt = updatedAt
    }
}

nonisolated enum LearningWorkspaceDestination: Hashable, Identifiable {
    case fixed(LearningMaterialCategory)
    case project(UUID)

    var id: String {
        switch self {
        case .fixed(let category):
            return "fixed-\(category.rawValue)"
        case .project(let id):
            return "project-\(id.uuidString)"
        }
    }

    var projectID: String {
        switch self {
        case .fixed:
            return ""
        case .project(let id):
            return id.uuidString
        }
    }

    var fixedCategory: LearningMaterialCategory? {
        switch self {
        case .fixed(let category):
            return category
        case .project:
            return nil
        }
    }
}

struct LearningWorkspaceSummary: Equatable {
    static let empty = LearningWorkspaceSummary(
        materialCount: 0,
        taskCount: 0,
        completedTaskCount: 0,
        recordCount: 0,
        totalDuration: 0,
        weekDuration: 0
    )

    let materialCount: Int
    let taskCount: Int
    let completedTaskCount: Int
    let recordCount: Int
    let totalDuration: TimeInterval
    let weekDuration: TimeInterval

    var pendingTaskCount: Int {
        taskCount - completedTaskCount
    }

    static func make(
        destination: LearningWorkspaceDestination,
        materials: [LearningMaterialDocument],
        tasks: [LearningProjectTask],
        records: [StudyTimeRecord],
        now: Date = Date(),
        calendar: Calendar = .current
    ) -> LearningWorkspaceSummary {
        let scopedMaterials = materials.filter { $0.belongs(to: destination) }
        let scopedTasks = tasks.filter { $0.belongs(to: destination) }
        let scopedRecords = records.filter { $0.belongs(to: destination) }
        let week = calendar.dateInterval(of: .weekOfYear, for: now)
        return LearningWorkspaceSummary(
            materialCount: scopedMaterials.count,
            taskCount: scopedTasks.count,
            completedTaskCount: scopedTasks.filter(\.isCompleted).count,
            recordCount: scopedRecords.count,
            totalDuration: scopedRecords.learningDuration,
            weekDuration: scopedRecords.filter { record in
                week?.contains(record.startedAt) == true
            }.learningDuration
        )
    }
}

enum LearningMaterialLocalFile {
    static func localFilename(originalExtension: String, uuid: UUID = UUID()) -> String {
        let cleanedExtension = originalExtension
            .trimmingCharacters(in: CharacterSet(charactersIn: ".").union(.whitespacesAndNewlines))
        guard !cleanedExtension.isEmpty else { return uuid.uuidString }
        return "\(uuid.uuidString).\(cleanedExtension)"
    }
}

enum LearningMaterialFileStore {
    struct StoredFile {
        let localFilename: String
        let contentTypeIdentifier: String
    }

    static let allowedContentTypes: [UTType] = [
        .pdf,
        .image,
        .plainText,
        .rtf,
        UTType(filenameExtension: "doc") ?? .data,
        UTType(filenameExtension: "docx") ?? .data,
        UTType(filenameExtension: "ppt") ?? .data,
        UTType(filenameExtension: "pptx") ?? .data,
        UTType(filenameExtension: "xls") ?? .data,
        UTType(filenameExtension: "xlsx") ?? .data,
        UTType(filenameExtension: "csv") ?? .data
    ]

    static func importFile(from sourceURL: URL) throws -> StoredFile {
        let didAccess = sourceURL.startAccessingSecurityScopedResource()
        defer {
            if didAccess {
                sourceURL.stopAccessingSecurityScopedResource()
            }
        }

        let fileManager = FileManager.default
        try fileManager.createDirectory(at: directoryURL, withIntermediateDirectories: true)

        let localFilename = LearningMaterialLocalFile.localFilename(originalExtension: sourceURL.pathExtension)
        let destinationURL = directoryURL.appendingPathComponent(localFilename)

        if fileManager.fileExists(atPath: destinationURL.path(percentEncoded: false)) {
            try fileManager.removeItem(at: destinationURL)
        }
        try fileManager.copyItem(at: sourceURL, to: destinationURL)

        let contentType = UTType(filenameExtension: sourceURL.pathExtension)
            ?? sourceURL.resourceContentType
            ?? .data
        return StoredFile(
            localFilename: localFilename,
            contentTypeIdentifier: contentType.identifier
        )
    }

    static func fileURL(for document: LearningMaterialDocument) -> URL? {
        let url = directoryURL.appendingPathComponent(document.localFilename)
        return FileManager.default.fileExists(atPath: url.path(percentEncoded: false)) ? url : nil
    }

    static func deleteFile(named filename: String) throws {
        let url = directoryURL.appendingPathComponent(filename)
        if FileManager.default.fileExists(atPath: url.path(percentEncoded: false)) {
            try FileManager.default.removeItem(at: url)
        }
    }

    private static var directoryURL: URL {
        let base = FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask).first
            ?? FileManager.default.temporaryDirectory
        return base.appendingPathComponent("LearningMaterials", isDirectory: true)
    }
}

extension LearningMaterialDocument {
    var category: LearningMaterialCategory {
        get { LearningMaterialCategory.normalized(categoryRawValue) }
        set { categoryRawValue = newValue.rawValue }
    }

    var contentType: UTType? {
        UTType(contentTypeIdentifier)
    }

    var displayType: String {
        Self.displayType(contentTypeIdentifier: contentTypeIdentifier, originalFilename: originalFilename)
    }

    static func displayType(contentTypeIdentifier: String, originalFilename: String) -> String {
        let contentType = UTType(contentTypeIdentifier)
        let lowercasedName = originalFilename.lowercased()
        let lowercasedIdentifier = contentTypeIdentifier.lowercased()

        if contentType?.conforms(to: .pdf) == true { return "PDF" }
        if contentType?.conforms(to: .image) == true { return "图片" }
        if contentType?.conforms(to: .plainText) == true { return "文本" }
        if contentType?.conforms(to: .rtf) == true || lowercasedName.hasSuffix(".rtf") { return "RTF" }
        if lowercasedName.hasSuffix(".doc") || lowercasedName.hasSuffix(".docx") || lowercasedIdentifier.contains("word") {
            return "Word"
        }
        if lowercasedName.hasSuffix(".ppt") || lowercasedName.hasSuffix(".pptx") || lowercasedIdentifier.contains("powerpoint") || lowercasedIdentifier.contains("presentation") {
            return "PPT"
        }
        if lowercasedName.hasSuffix(".xls") || lowercasedName.hasSuffix(".xlsx") || lowercasedName.hasSuffix(".csv") || lowercasedIdentifier.contains("excel") || lowercasedIdentifier.contains("spreadsheet") {
            return "表格"
        }
        return "文件"
    }
}

extension LearningProject {
    var kind: LearningProjectKind {
        get { LearningProjectKind.normalized(kindRawValue) }
        set { kindRawValue = newValue.rawValue }
    }
}

extension PostgraduateTarget {
    var state: PostgraduateTargetState {
        get { PostgraduateTargetState.normalized(stateRawValue) }
        set { stateRawValue = newValue.rawValue }
    }

    var isArchived: Bool {
        state == .archived
    }

    var displayTitle: String {
        [school, major]
            .map { $0.trimmingCharacters(in: .whitespacesAndNewlines) }
            .filter { !$0.isEmpty }
            .joined(separator: " · ")
    }

    var normalizedSchool: String {
        Self.normalizedText(school)
    }

    var normalizedMajor: String {
        Self.normalizedText(major)
    }

    static func normalizedText(_ value: String) -> String {
        value
            .trimmingCharacters(in: .whitespacesAndNewlines)
            .lowercased()
            .replacingOccurrences(of: "（", with: "(")
            .replacingOccurrences(of: "）", with: ")")
            .replacingOccurrences(of: " ", with: "")
    }
}

extension LearningProjectTask {
    var category: LearningMaterialCategory {
        get { LearningMaterialCategory.normalized(categoryRawValue) }
        set { categoryRawValue = newValue.rawValue }
    }

    func belongs(to destination: LearningWorkspaceDestination) -> Bool {
        switch destination {
        case .fixed(let category):
            return projectID.isEmpty && self.category == category
        case .project(let id):
            return projectID == id.uuidString
        }
    }
}

extension LearningMaterialDocument {
    func belongs(to destination: LearningWorkspaceDestination) -> Bool {
        switch destination {
        case .fixed(let category):
            return projectID.isEmpty && self.category == category
        case .project(let id):
            return projectID == id.uuidString
        }
    }
}

extension StudyTimeRecord {
    var category: LearningMaterialCategory {
        get { LearningMaterialCategory.normalized(categoryRawValue) }
        set { categoryRawValue = newValue.rawValue }
    }

    func belongs(to destination: LearningWorkspaceDestination) -> Bool {
        switch destination {
        case .fixed(let category):
            return projectID.isEmpty && self.category == category
        case .project(let id):
            return projectID == id.uuidString
        }
    }
}

extension Array where Element == StudyTimeRecord {
    var learningDuration: TimeInterval {
        reduce(0) { partialResult, record in
            partialResult + Swift.max(record.endedAt.timeIntervalSince(record.startedAt), 0)
        }
    }
}

@Model
final class CareerResumeDocument {
    var id: UUID
    var title: String
    var note: String
    var importedAt: Date
    var updatedAt: Date
    var originalFilename: String
    var localFilename: String
    var contentTypeIdentifier: String

    init(
        id: UUID = UUID(),
        title: String,
        note: String = "",
        importedAt: Date = Date(),
        updatedAt: Date = Date(),
        originalFilename: String,
        localFilename: String,
        contentTypeIdentifier: String
    ) {
        self.id = id
        self.title = title
        self.note = note
        self.importedAt = importedAt
        self.updatedAt = updatedAt
        self.originalFilename = originalFilename
        self.localFilename = localFilename
        self.contentTypeIdentifier = contentTypeIdentifier
    }
}

@Model
final class CareerTask {
    var id: UUID
    var title: String
    var note: String
    var dueAt: Date?
    var isCompleted: Bool
    var createdAt: Date
    var updatedAt: Date

    init(
        id: UUID = UUID(),
        title: String,
        note: String = "",
        dueAt: Date? = nil,
        isCompleted: Bool = false,
        createdAt: Date = Date(),
        updatedAt: Date = Date()
    ) {
        self.id = id
        self.title = title
        self.note = note
        self.dueAt = dueAt
        self.isCompleted = isCompleted
        self.createdAt = createdAt
        self.updatedAt = updatedAt
    }
}

@Model
final class CareerOpportunity {
    var id: UUID
    var title: String
    var organization: String
    var urlString: String
    var statusRawValue: String
    var note: String
    var createdAt: Date
    var updatedAt: Date

    init(
        id: UUID = UUID(),
        title: String,
        organization: String = "",
        urlString: String = "",
        statusRawValue: String = CareerOpportunityStatus.watching.rawValue,
        note: String = "",
        createdAt: Date = Date(),
        updatedAt: Date = Date()
    ) {
        self.id = id
        self.title = title
        self.organization = organization
        self.urlString = urlString
        self.statusRawValue = statusRawValue
        self.note = note
        self.createdAt = createdAt
        self.updatedAt = updatedAt
    }
}

@Model
final class FitnessTestRecord {
    var id: UUID
    var testedAt: Date
    var itemRawValue: String
    var value: Double
    var unitRawValue: String
    var note: String
    var createdAt: Date
    var updatedAt: Date

    init(
        id: UUID = UUID(),
        testedAt: Date = Date(),
        itemRawValue: String,
        value: Double,
        unitRawValue: String,
        note: String = "",
        createdAt: Date = Date(),
        updatedAt: Date = Date()
    ) {
        self.id = id
        self.testedAt = testedAt
        self.itemRawValue = itemRawValue
        self.value = value
        self.unitRawValue = unitRawValue
        self.note = note
        self.createdAt = createdAt
        self.updatedAt = updatedAt
    }
}

@Model
final class ComprehensiveQualityRecord {
    var id: UUID
    var collegeName: String
    var cohort: String
    var academicStandardScore: Double?
    var officialQualityScore: Double?
    var officialCompositeScore: Double?
    var note: String
    var createdAt: Date
    var updatedAt: Date

    init(
        id: UUID = UUID(),
        collegeName: String,
        cohort: String = "2026届",
        academicStandardScore: Double? = nil,
        officialQualityScore: Double? = nil,
        officialCompositeScore: Double? = nil,
        note: String = "",
        createdAt: Date = Date(),
        updatedAt: Date = Date()
    ) {
        self.id = id
        self.collegeName = collegeName
        self.cohort = cohort
        self.academicStandardScore = academicStandardScore
        self.officialQualityScore = officialQualityScore
        self.officialCompositeScore = officialCompositeScore
        self.note = note
        self.createdAt = createdAt
        self.updatedAt = updatedAt
    }
}

@Model
final class ComprehensiveQualityComponentEntry {
    var id: UUID
    var collegeName: String
    var cohort: String
    var componentRawValue: String
    var rawScore: Double?
    var peerMaxScore: Double?
    var officialStandardScore: Double?
    var materialReady: Bool
    var note: String
    var createdAt: Date
    var updatedAt: Date

    init(
        id: UUID = UUID(),
        collegeName: String,
        cohort: String = "2026届",
        componentRawValue: String,
        rawScore: Double? = nil,
        peerMaxScore: Double? = nil,
        officialStandardScore: Double? = nil,
        materialReady: Bool = false,
        note: String = "",
        createdAt: Date = Date(),
        updatedAt: Date = Date()
    ) {
        self.id = id
        self.collegeName = collegeName
        self.cohort = cohort
        self.componentRawValue = componentRawValue
        self.rawScore = rawScore
        self.peerMaxScore = peerMaxScore
        self.officialStandardScore = officialStandardScore
        self.materialReady = materialReady
        self.note = note
        self.createdAt = createdAt
        self.updatedAt = updatedAt
    }
}

@Model
final class ComprehensiveQualityEvidenceDocument {
    var id: UUID
    var collegeName: String
    var cohort: String
    var componentRawValue: String
    var title: String
    var note: String
    var originalFilename: String
    var localFilename: String
    var contentTypeIdentifier: String
    var importedAt: Date
    var updatedAt: Date

    init(
        id: UUID = UUID(),
        collegeName: String,
        cohort: String = "2026届",
        componentRawValue: String,
        title: String,
        note: String = "",
        originalFilename: String,
        localFilename: String,
        contentTypeIdentifier: String,
        importedAt: Date = Date(),
        updatedAt: Date = Date()
    ) {
        self.id = id
        self.collegeName = collegeName
        self.cohort = cohort
        self.componentRawValue = componentRawValue
        self.title = title
        self.note = note
        self.originalFilename = originalFilename
        self.localFilename = localFilename
        self.contentTypeIdentifier = contentTypeIdentifier
        self.importedAt = importedAt
        self.updatedAt = updatedAt
    }
}

@Model
final class CampusAIConversation {
    var id: UUID
    var title: String
    var summary: String
    var contextDigest: String
    var createdAt: Date
    var updatedAt: Date

    init(
        id: UUID = UUID(),
        title: String = "新的对话",
        summary: String = "",
        contextDigest: String = "",
        createdAt: Date = Date(),
        updatedAt: Date = Date()
    ) {
        self.id = id
        self.title = title
        self.summary = summary
        self.contextDigest = contextDigest
        self.createdAt = createdAt
        self.updatedAt = updatedAt
    }
}

@Model
final class CampusAIMessage {
    var id: UUID
    var conversationID: String
    var roleRawValue: String
    var text: String
    var reasoningText: String
    var createdAt: Date

    init(
        id: UUID = UUID(),
        conversationID: String,
        roleRawValue: String,
        text: String,
        reasoningText: String = "",
        createdAt: Date = Date()
    ) {
        self.id = id
        self.conversationID = conversationID
        self.roleRawValue = roleRawValue
        self.text = text
        self.reasoningText = reasoningText
        self.createdAt = createdAt
    }
}

@Model
final class CampusAIActionRecord {
    var id: UUID
    var conversationID: String
    var messageID: String
    var kindRawValue: String
    var title: String
    var detail: String
    var payloadJSON: String
    var statusRawValue: String
    var createdAt: Date
    var updatedAt: Date

    init(
        id: UUID = UUID(),
        conversationID: String,
        messageID: String,
        kindRawValue: String,
        title: String,
        detail: String,
        payloadJSON: String,
        statusRawValue: String,
        createdAt: Date = Date(),
        updatedAt: Date = Date()
    ) {
        self.id = id
        self.conversationID = conversationID
        self.messageID = messageID
        self.kindRawValue = kindRawValue
        self.title = title
        self.detail = detail
        self.payloadJSON = payloadJSON
        self.statusRawValue = statusRawValue
        self.createdAt = createdAt
        self.updatedAt = updatedAt
    }
}

@Model
final class MedicalLedgerEntry {
    var id: UUID
    var visitDate: Date
    var hospitalName: String
    var department: String
    var diagnosisNote: String
    var scenarioRawValue: String
    var totalExpense: Double
    var estimatedReimbursement: Double?
    var actualReimbursement: Double?
    var statusRawValue: String
    var reimbursementDeadline: Date?
    var materialChecklistRawValue: String
    var note: String
    var createdAt: Date
    var updatedAt: Date

    init(
        id: UUID = UUID(),
        visitDate: Date = Date(),
        hospitalName: String = "",
        department: String = "",
        diagnosisNote: String = "",
        scenarioRawValue: String = MedicalLedgerScenario.campusClinic.rawValue,
        totalExpense: Double = 0,
        estimatedReimbursement: Double? = nil,
        actualReimbursement: Double? = nil,
        statusRawValue: String = MedicalLedgerStatus.organizing.rawValue,
        reimbursementDeadline: Date? = nil,
        materialChecklistRawValue: String = "",
        note: String = "",
        createdAt: Date = Date(),
        updatedAt: Date = Date()
    ) {
        self.id = id
        self.visitDate = visitDate
        self.hospitalName = hospitalName
        self.department = department
        self.diagnosisNote = diagnosisNote
        self.scenarioRawValue = scenarioRawValue
        self.totalExpense = totalExpense
        self.estimatedReimbursement = estimatedReimbursement
        self.actualReimbursement = actualReimbursement
        self.statusRawValue = statusRawValue
        self.reimbursementDeadline = reimbursementDeadline
        self.materialChecklistRawValue = materialChecklistRawValue
        self.note = note
        self.createdAt = createdAt
        self.updatedAt = updatedAt
    }
}

@Model
final class MedicalLedgerPhoto {
    var id: UUID
    var entryID: String
    var originalFilename: String
    var localFilename: String
    var importedAt: Date
    var updatedAt: Date

    init(
        id: UUID = UUID(),
        entryID: String,
        originalFilename: String,
        localFilename: String,
        importedAt: Date = Date(),
        updatedAt: Date = Date()
    ) {
        self.id = id
        self.entryID = entryID
        self.originalFilename = originalFilename
        self.localFilename = localFilename
        self.importedAt = importedAt
        self.updatedAt = updatedAt
    }
}

enum FitnessTestItem: String, CaseIterable, Identifiable {
    case height = "身高"
    case weight = "体重"
    case vitalCapacity = "肺活量"
    case sprint50m = "50米"
    case sitAndReach = "坐位体前屈"
    case standingLongJump = "立定跳远"
    case pullUps = "引体向上"
    case sitUps = "仰卧起坐"
    case run800m = "800米"
    case run1000m = "1000米"
    case other = "其他"

    var id: String { rawValue }

    var defaultUnit: FitnessTestUnit {
        switch self {
        case .height, .sitAndReach, .standingLongJump:
            return .centimeter
        case .weight:
            return .kilogram
        case .vitalCapacity:
            return .milliliter
        case .sprint50m:
            return .second
        case .pullUps, .sitUps:
            return .count
        case .run800m, .run1000m:
            return .minuteSecond
        case .other:
            return .count
        }
    }

    static func normalized(_ rawValue: String) -> FitnessTestItem {
        FitnessTestItem(rawValue: rawValue) ?? .other
    }
}

enum FitnessTestUnit: String, CaseIterable, Identifiable {
    case centimeter = "cm"
    case kilogram = "kg"
    case milliliter = "ml"
    case second = "秒"
    case count = "次"
    case minuteSecond = "分秒"

    var id: String { rawValue }

    static func normalized(_ rawValue: String) -> FitnessTestUnit {
        FitnessTestUnit(rawValue: rawValue) ?? .count
    }
}

enum FitnessTestRecordFormatter {
    static func valueText(value: Double, unit: FitnessTestUnit) -> String {
        switch unit {
        case .minuteSecond:
            return minuteSecondText(seconds: value)
        case .centimeter, .kilogram, .second:
            return "\(decimalText(value)) \(unit.rawValue)"
        case .milliliter, .count:
            return "\(integerText(value)) \(unit.rawValue)"
        }
    }

    static func minuteSecondText(seconds: Double) -> String {
        let totalSeconds = Swift.max(Int(seconds.rounded()), 0)
        return "\(totalSeconds / 60)分\(totalSeconds % 60)秒"
    }

    static func sortedRecords(_ records: [FitnessTestRecord]) -> [FitnessTestRecord] {
        records.sorted {
            if $0.testedAt != $1.testedAt {
                return $0.testedAt > $1.testedAt
            }
            return $0.createdAt > $1.createdAt
        }
    }

    private static func decimalText(_ value: Double) -> String {
        let rounded = (value * 10).rounded() / 10
        if rounded.truncatingRemainder(dividingBy: 1) == 0 {
            return String(Int(rounded))
        }
        return String(format: "%.1f", rounded)
    }

    private static func integerText(_ value: Double) -> String {
        String(Int(value.rounded()))
    }
}

extension FitnessTestRecord {
    var item: FitnessTestItem {
        get { FitnessTestItem.normalized(itemRawValue) }
        set { itemRawValue = newValue.rawValue }
    }

    var unit: FitnessTestUnit {
        get { FitnessTestUnit.normalized(unitRawValue) }
        set { unitRawValue = newValue.rawValue }
    }

    var displayValue: String {
        FitnessTestRecordFormatter.valueText(value: value, unit: unit)
    }
}

enum CareerOpportunityStatus: String, CaseIterable, Identifiable {
    case watching = "关注中"
    case applied = "已投递"
    case interviewing = "面试中"
    case closed = "已结束"

    var id: String { rawValue }
}

private extension URL {
    var resourceContentType: UTType? {
        (try? resourceValues(forKeys: [.contentTypeKey]))?.contentType
    }
}

extension Course {
    var stableCourseKey: String {
        [
            courseName.normalizedCourseKeyComponent,
            teacher.normalizedCourseKeyComponent,
            "\(dayOfWeek)",
            duration.sorted().map(String.init).joined(separator: "-"),
            locationTextForKey.normalizedCourseKeyComponent
        ]
        .joined(separator: "|")
    }

    func occurrenceKey(week: Int) -> String {
        CourseOccurrenceNote.occurrenceKey(courseKey: stableCourseKey, week: week)
    }

    private var locationTextForKey: String {
        if !location.isEmpty { return location }
        if !room.isEmpty { return room }
        return ""
    }
}

private extension String {
    var normalizedCourseKeyComponent: String {
        trimmingCharacters(in: .whitespacesAndNewlines)
            .replacingOccurrences(of: "\\s+", with: " ", options: .regularExpression)
            .lowercased()
    }
}
