import Foundation

nonisolated struct SharedTimetableCourse: Codable, Identifiable, Hashable, Sendable {
    let id: UUID
    let courseName: String
    let teacher: String
    let room: String
    let location: String
    let dayOfWeek: Int
    let weeks: [Int]
    let duration: [Int]

    init(
        id: UUID = UUID(),
        courseName: String,
        teacher: String,
        room: String,
        location: String,
        dayOfWeek: Int,
        weeks: [Int],
        duration: [Int]
    ) {
        self.id = id
        self.courseName = courseName
        self.teacher = teacher
        self.room = room
        self.location = location
        self.dayOfWeek = dayOfWeek
        self.weeks = weeks.sorted()
        self.duration = duration.sorted()
    }

    init(course: Course) {
        self.init(
            id: course.id,
            courseName: course.courseName,
            teacher: course.teacher,
            room: course.room,
            location: course.location,
            dayOfWeek: course.dayOfWeek,
            weeks: course.weeks,
            duration: course.duration
        )
    }

    var displayCourseName: String {
        let trimmed = courseName.trimmingCharacters(in: .whitespacesAndNewlines)
        return trimmed.isEmpty ? L10n.text("未命名课程") : trimmed
    }

    var locationText: String {
        let candidates = [location, room]
            .map { $0.trimmingCharacters(in: .whitespacesAndNewlines) }
        let cleanLocation = candidates[0]
        let cleanRoom = candidates[1]

        if cleanLocation.isEmpty {
            return cleanRoom.isEmpty ? L10n.text("地点待定") : cleanRoom
        }

        if cleanRoom.isEmpty {
            return cleanLocation
        }

        let compactLocation = cleanLocation.replacingOccurrences(of: "\\s+", with: "", options: .regularExpression)
        let compactRoom = cleanRoom.replacingOccurrences(of: "\\s+", with: "", options: .regularExpression)

        if compactLocation == compactRoom || compactLocation.hasSuffix(compactRoom) {
            return cleanLocation
        }

        if compactRoom.hasPrefix(compactLocation) {
            return cleanRoom
        }

        return "\(cleanLocation) \(cleanRoom)"
    }

    func dayTitle(language: AppLanguagePreference) -> String {
        switch dayOfWeek {
        case 1: return L10n.text("周一", language: language)
        case 2: return L10n.text("周二", language: language)
        case 3: return L10n.text("周三", language: language)
        case 4: return L10n.text("周四", language: language)
        case 5: return L10n.text("周五", language: language)
        case 6: return L10n.text("周六", language: language)
        case 7: return L10n.text("周日", language: language)
        default: return L10n.text("未知", language: language)
        }
    }

    func weeksText(language: AppLanguagePreference) -> String {
        let ranges = Self.consecutiveRanges(from: weeks)
        guard !ranges.isEmpty else {
            return L10n.text("周次待定", language: language)
        }

        let text = ranges.map { range in
            range.lowerBound == range.upperBound
                ? "\(range.lowerBound)"
                : "\(range.lowerBound)-\(range.upperBound)"
        }
        .joined(separator: ", ")
        return L10n.text("第 %@ 周", language: language, text)
    }

    func durationText(language: AppLanguagePreference) -> String {
        guard let first = duration.min(), let last = duration.max() else {
            return L10n.text("节次待定", language: language)
        }

        let periodText = first == last
            ? L10n.text("第 %d 节", language: language, first)
            : L10n.text("第 %d-%d 节", language: language, first, last)

        guard let startSlot = TimetablePeriodSchedule.slot(for: first),
              let endSlot = TimetablePeriodSchedule.slot(for: last) else {
            return periodText
        }

        return "\(periodText) \(startSlot.startText)-\(endSlot.endText)"
    }

    enum CodingKeys: String, CodingKey {
        case id
        case courseName = "course_name"
        case teacher
        case room
        case location
        case dayOfWeek = "day_of_week"
        case weeks
        case duration
    }

    private static func consecutiveRanges(from values: [Int]) -> [ClosedRange<Int>] {
        let sorted = Array(Set(values)).sorted()
        guard let first = sorted.first else { return [] }

        var ranges: [ClosedRange<Int>] = []
        var start = first
        var previous = first

        for value in sorted.dropFirst() {
            if value == previous + 1 {
                previous = value
            } else {
                ranges.append(start...previous)
                start = value
                previous = value
            }
        }

        ranges.append(start...previous)
        return ranges
    }
}

nonisolated struct SharedTimetableSnapshot: Codable, Identifiable, Hashable, Sendable {
    let id: UUID
    let ownerID: UUID
    let semesterID: String
    let courses: [SharedTimetableCourse]
    let courseCount: Int
    let publishedAt: String
    let createdAt: String
    let updatedAt: String
    let owner: CommunityProfile?

    var ownerDisplayName: String {
        owner?.limitedResolvedDisplayName ?? L10n.text(ActiveCampusContext.descriptor.defaultStudentDisplayName)
    }

    var publishedDate: Date? {
        CommunityTimestampFormatter.parse(publishedAt)
    }

    var publishedRelativeText: String {
        CommunityTimestampFormatter.displayText(from: publishedAt)
    }

    enum CodingKeys: String, CodingKey {
        case id
        case ownerID = "owner_id"
        case semesterID = "semester_id"
        case courses
        case courseCount = "course_count"
        case publishedAt = "published_at"
        case createdAt = "created_at"
        case updatedAt = "updated_at"
        case owner
    }
}

nonisolated struct TimetableShareMember: Codable, Identifiable, Hashable, Sendable {
    let id: UUID
    let ownerID: UUID
    let viewerID: UUID
    let createdAt: String
    let updatedAt: String
    let revokedAt: String?
    let viewer: CommunityProfile?

    var viewerDisplayName: String {
        viewer?.limitedResolvedDisplayName ?? L10n.text(ActiveCampusContext.descriptor.defaultStudentDisplayName)
    }

    enum CodingKeys: String, CodingKey {
        case id
        case ownerID = "owner_id"
        case viewerID = "viewer_id"
        case createdAt = "created_at"
        case updatedAt = "updated_at"
        case revokedAt = "revoked_at"
        case viewer
    }
}

nonisolated struct TimetableInvite: Codable, Identifiable, Hashable, Sendable {
    let id: UUID
    let ownerID: UUID
    let semesterID: String
    let code: String?
    let expiresAt: String
    let acceptedBy: UUID?
    let acceptedAt: String?
    let createdAt: String

    var expiresDate: Date? {
        CommunityTimestampFormatter.parse(expiresAt)
    }

    var shareURL: URL? {
        guard let code else { return nil }
        return URL(string: "https://myleafy.space/share/timetable/\(code)")
    }

    func shareText(ownerName: String, language: AppLanguagePreference = .current) -> String {
        guard let code else {
            return L10n.text("%@ 共享课表邀请码已生成。", language: language, AppBrand.displayName)
        }

        return [
            L10n.text("%@ 邀请你查看 TA 的 %@ 课表。", language: language, ownerName, AppBrand.displayName),
            L10n.text("邀请码：%@", language: language, code),
            L10n.text("打开 %@ -> 我的 -> 共享课表 -> +，粘贴邀请码接受。", language: language, AppBrand.displayName),
            "https://myleafy.space/share/timetable/\(code)"
        ].joined(separator: "\n")
    }

    enum CodingKeys: String, CodingKey {
        case id
        case ownerID = "owner_id"
        case semesterID = "semester_id"
        case code
        case expiresAt = "expires_at"
        case acceptedBy = "accepted_by"
        case acceptedAt = "accepted_at"
        case createdAt = "created_at"
    }
}
