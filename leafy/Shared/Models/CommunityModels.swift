import Foundation
#if canImport(UIKit)
import UIKit
#elseif canImport(AppKit)
import AppKit
#endif

nonisolated enum CommunityNickname {
    static let maxLength = 8

    static func limited(_ value: String) -> String {
        String(value.prefix(maxLength))
    }

    static func normalized(_ value: String) -> String {
        limited(value.trimmingCharacters(in: .whitespacesAndNewlines))
    }
}

nonisolated enum CommunityProfileBio {
    static let maxLength = 80

    static func limited(_ value: String) -> String {
        String(value.prefix(maxLength))
    }

    static func normalized(_ value: String?) -> String? {
        let trimmed = (value ?? "").trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else { return nil }
        return limited(trimmed)
    }
}

nonisolated enum CommunityProfileTitleName {
    static func title(publicPostCount: Int, receivedLikeCount: Int) -> String {
        title(activityScore: max(publicPostCount, 0) * 3 + max(receivedLikeCount, 0))
    }

    static func title(activityScore: Int) -> String {
        switch max(activityScore, 0) {
        case 150...:
            return "山水知己"
        case 60...:
            return "松下常客"
        case 20...:
            return "绿野熟人"
        case 5...:
            return "林下伙伴"
        default:
            return "初入林园"
        }
    }
}

nonisolated enum CommunityPostCategory {
    static let maxLength = 8

    static func limited(_ value: String) -> String {
        String(value.prefix(maxLength))
    }

    static func normalized(_ value: String?) -> String? {
        let trimmed = (value ?? "").trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else { return nil }
        return limited(trimmed)
    }
}

nonisolated enum CommunityTerms {
    static let currentVersion = "leafy-community-eula-2026-05-08"
    static let supportEmail = AppBrand.supportEmail
}

nonisolated enum CommunityCatalogOptions {
    static let units = [
        "人文社会科学学院",
        "体育教学部",
        "信息学院",
        "园林学院",
        "外语学院",
        "工学院",
        "材料科学与技术学院",
        "林学院",
        "水土保持学院",
        "环境科学与工程学院",
        "理学院",
        "生态与自然保护学院",
        "生物科学与技术学院",
        "经济管理学院",
        "艺术设计学院",
        "草业与草原学院",
        "马克思主义学院"
    ]
}

nonisolated enum CommunityReportTargetType: String, Codable, Hashable, Sendable {
    case post
    case comment
    case user
}

nonisolated struct CommunityProfileStats: Codable, Hashable, Sendable {
    let profileID: UUID
    let publicPostCount: Int
    let receivedLikeCount: Int
    let activityScore: Int
    let title: String
    let firstPostAt: String?
    let latestPostAt: String?

    enum CodingKeys: String, CodingKey {
        case profileID = "profile_id"
        case publicPostCount = "public_post_count"
        case receivedLikeCount = "received_like_count"
        case activityScore = "activity_score"
        case title
        case firstPostAt = "first_post_at"
        case latestPostAt = "latest_post_at"
    }
}

nonisolated enum CommunityAccessStatus: String, Codable, Hashable, Sendable {
    case general
    case pending
    case approved
    case rejected
}

nonisolated struct CommunityProfile: Codable, Identifiable, Hashable, Sendable {
    let id: UUID
    let eduID: String
    let campusID: String
    let communityCampusID: String?
    let communityAccessStatusRaw: String?
    let communitySchoolName: String?
    let communityRejectionReason: String?
    let nickname: String
    let displayName: String?
    let avatarPath: String?
    let coverPath: String?
    let bio: String?
    let major: String?
    let grade: String?
    let boundEmail: String?
    let pendingBoundEmail: String?
    let emailVerificationSentAt: String?
    let profileEditedAt: String?
    let isProfileComplete: Bool
    let createdAt: String
    let updatedAt: String
    let signedAvatarURL: URL?
    let avatarURL: URL?
    let signedCoverURL: URL?
    let coverURL: URL?
    let showsEduVerificationBadge: Bool

    var communityAccessStatus: CommunityAccessStatus {
        if let status = communityAccessStatusRaw.flatMap(CommunityAccessStatus.init(rawValue:)) {
            return status
        }
        return campusID == CampusID.bjfu.rawValue ? .approved : .general
    }

    var hasApprovedCommunityAccess: Bool {
        guard communityAccessStatus == .approved else { return false }
        if campusID == CampusID.bjfu.rawValue {
            return true
        }
        return !(communityCampusID?.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty ?? true)
    }

    var communitySchoolDisplayName: String? {
        let explicitName = communitySchoolName?.trimmingCharacters(in: .whitespacesAndNewlines) ?? ""
        if !explicitName.isEmpty {
            return explicitName
        }
        if campusID == CampusID.bjfu.rawValue {
            return "北京林业大学"
        }
        let fallback = communityCampusID?.trimmingCharacters(in: .whitespacesAndNewlines) ?? ""
        return fallback.isEmpty ? nil : fallback
    }

    var resolvedDisplayName: String {
        let fallback = ActiveCampusContext.descriptor.defaultStudentDisplayName
        let candidates = [nickname, displayName, fallback].compactMap { $0 }
        return candidates.first(where: { !$0.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty }) ?? fallback
    }

    var limitedResolvedDisplayName: String {
        CommunityNickname.normalized(resolvedDisplayName)
    }

    var shortName: String {
        String(resolvedDisplayName.prefix(1))
    }

    var hasCustomAvatar: Bool {
        resolvedAvatarURL != nil || !(avatarPath?.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty ?? true)
    }

    var resolvedAvatarURL: URL? {
        avatarURL ?? signedAvatarURL
    }

    var resolvedCoverURL: URL? {
        coverURL ?? signedCoverURL
    }

    var trimmedBio: String? {
        CommunityProfileBio.normalized(bio)
    }

    var boundEmailText: String {
        let trimmed = boundEmail?.trimmingCharacters(in: .whitespacesAndNewlines) ?? ""
        return trimmed.isEmpty ? L10n.text("未绑定") : trimmed
    }

    var subtitleText: String {
        subtitleText(language: .current)
    }

    func subtitleText(language: AppLanguagePreference) -> String {
        let parts = [grade, major]
            .compactMap { $0?.trimmingCharacters(in: .whitespacesAndNewlines) }
            .filter { !$0.isEmpty }

        if hasApprovedCommunityAccess,
           campusID != CampusID.bjfu.rawValue,
           let schoolName = communitySchoolDisplayName {
            if parts.isEmpty {
                return L10n.text("%@ 社区", language: language, schoolName)
            }
            return L10n.text("%@ · %@", language: language, schoolName, parts.joined(separator: " · "))
        }

        if parts.isEmpty {
            if ActiveCampusContext.identity?.isCustom == true {
                return L10n.text("通用入口账号 %@", language: language, eduID)
            }
            return L10n.text("已与教务学号 %@ 绑定", language: language, eduID)
        }

        return L10n.text("%@ · 学号 %@", language: language, parts.joined(separator: " · "), eduID)
    }

    enum CodingKeys: String, CodingKey {
        case id
        case eduID = "edu_id"
        case campusID = "campus_id"
        case communityCampusID = "community_campus_id"
        case communityAccessStatusRaw = "community_access_status"
        case communitySchoolName = "community_school_name"
        case communityRejectionReason = "community_rejection_reason"
        case nickname
        case displayName = "display_name"
        case avatarPath = "avatar_path"
        case coverPath = "cover_path"
        case bio
        case major
        case grade
        case boundEmail = "bound_email"
        case pendingBoundEmail = "pending_bound_email"
        case emailVerificationSentAt = "email_verification_sent_at"
        case profileEditedAt = "profile_edited_at"
        case isProfileComplete = "is_profile_complete"
        case createdAt = "created_at"
        case updatedAt = "updated_at"
        case signedAvatarURL = "signed_avatar_url"
        case avatarURL = "avatar_url"
        case signedCoverURL = "signed_cover_url"
        case coverURL = "cover_url"
        case showsEduVerificationBadge = "shows_edu_verification_badge"
    }

    init(
        id: UUID,
        eduID: String,
        campusID: String = CampusID.bjfu.rawValue,
        communityCampusID: String? = nil,
        communityAccessStatusRaw: String? = nil,
        communitySchoolName: String? = nil,
        communityRejectionReason: String? = nil,
        nickname: String,
        displayName: String?,
        avatarPath: String?,
        coverPath: String? = nil,
        bio: String? = nil,
        major: String?,
        grade: String?,
        boundEmail: String?,
        pendingBoundEmail: String?,
        emailVerificationSentAt: String?,
        profileEditedAt: String?,
        isProfileComplete: Bool,
        createdAt: String,
        updatedAt: String,
        signedAvatarURL: URL?,
        avatarURL: URL?,
        signedCoverURL: URL? = nil,
        coverURL: URL? = nil,
        showsEduVerificationBadge: Bool = false
    ) {
        self.id = id
        self.eduID = eduID
        self.campusID = campusID
        self.communityCampusID = communityCampusID
        self.communityAccessStatusRaw = communityAccessStatusRaw
        self.communitySchoolName = communitySchoolName
        self.communityRejectionReason = communityRejectionReason
        self.nickname = nickname
        self.displayName = displayName
        self.avatarPath = avatarPath
        self.coverPath = coverPath
        self.bio = bio
        self.major = major
        self.grade = grade
        self.boundEmail = boundEmail
        self.pendingBoundEmail = pendingBoundEmail
        self.emailVerificationSentAt = emailVerificationSentAt
        self.profileEditedAt = profileEditedAt
        self.isProfileComplete = isProfileComplete
        self.createdAt = createdAt
        self.updatedAt = updatedAt
        self.signedAvatarURL = signedAvatarURL
        self.avatarURL = avatarURL
        self.signedCoverURL = signedCoverURL
        self.coverURL = coverURL
        self.showsEduVerificationBadge = showsEduVerificationBadge
    }

    init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        id = try container.decode(UUID.self, forKey: .id)
        eduID = try container.decode(String.self, forKey: .eduID)
        campusID = try container.decodeIfPresent(String.self, forKey: .campusID) ?? CampusID.bjfu.rawValue
        communityCampusID = try container.decodeIfPresent(String.self, forKey: .communityCampusID)
        communityAccessStatusRaw = try container.decodeIfPresent(String.self, forKey: .communityAccessStatusRaw)
        communitySchoolName = try container.decodeIfPresent(String.self, forKey: .communitySchoolName)
        communityRejectionReason = try container.decodeIfPresent(String.self, forKey: .communityRejectionReason)
        nickname = try container.decode(String.self, forKey: .nickname)
        displayName = try container.decodeIfPresent(String.self, forKey: .displayName)
        avatarPath = try container.decodeIfPresent(String.self, forKey: .avatarPath)
        coverPath = try container.decodeIfPresent(String.self, forKey: .coverPath)
        bio = try container.decodeIfPresent(String.self, forKey: .bio)
        major = try container.decodeIfPresent(String.self, forKey: .major)
        grade = try container.decodeIfPresent(String.self, forKey: .grade)
        boundEmail = try container.decodeIfPresent(String.self, forKey: .boundEmail)
        pendingBoundEmail = try container.decodeIfPresent(String.self, forKey: .pendingBoundEmail)
        emailVerificationSentAt = try container.decodeIfPresent(String.self, forKey: .emailVerificationSentAt)
        profileEditedAt = try container.decodeIfPresent(String.self, forKey: .profileEditedAt)
        isProfileComplete = try container.decodeIfPresent(Bool.self, forKey: .isProfileComplete) ?? false
        createdAt = try container.decode(String.self, forKey: .createdAt)
        updatedAt = try container.decode(String.self, forKey: .updatedAt)
        signedAvatarURL = try container.decodeIfPresent(URL.self, forKey: .signedAvatarURL)
        avatarURL = try container.decodeIfPresent(URL.self, forKey: .avatarURL)
        signedCoverURL = try container.decodeIfPresent(URL.self, forKey: .signedCoverURL)
        coverURL = try container.decodeIfPresent(URL.self, forKey: .coverURL)
        showsEduVerificationBadge = try container.decodeIfPresent(Bool.self, forKey: .showsEduVerificationBadge) ?? false
    }
}

nonisolated struct CommunityCampusOption: Codable, Identifiable, Hashable, Sendable {
    let id: String
    let displayName: String
    let shortName: String

    enum CodingKeys: String, CodingKey {
        case id
        case displayName = "display_name"
        case shortName = "short_name"
    }
}

nonisolated enum CommunityCampusMembershipRequestType: String, Codable, Hashable, Sendable {
    case initialNewSchool = "initial_new_school"
    case schoolChange = "school_change"
}

nonisolated struct CommunityCampusMembershipRequest: Codable, Identifiable, Hashable, Sendable {
    let id: UUID
    let requesterProfileID: UUID
    let schoolName: String
    let normalizedSchoolName: String?
    let status: String
    let approvedCampusID: String?
    let requestTypeRaw: String?
    let requestedCampusID: String?
    let fromCampusID: String?
    let adminNote: String?
    let createdAt: String
    let updatedAt: String

    var requestType: CommunityCampusMembershipRequestType {
        requestTypeRaw.flatMap(CommunityCampusMembershipRequestType.init(rawValue:)) ?? .initialNewSchool
    }

    var isPending: Bool {
        status == "pending"
    }

    enum CodingKeys: String, CodingKey {
        case id
        case requesterProfileID = "requester_profile_id"
        case schoolName = "school_name"
        case normalizedSchoolName = "normalized_school_name"
        case status
        case approvedCampusID = "approved_campus_id"
        case requestTypeRaw = "request_type"
        case requestedCampusID = "requested_campus_id"
        case fromCampusID = "from_campus_id"
        case adminNote = "admin_note"
        case createdAt = "created_at"
        case updatedAt = "updated_at"
    }
}

nonisolated struct CommunityPostImage: Codable, Identifiable, Hashable, Sendable {
    let id: UUID
    let postID: UUID
    let path: String
    let thumbnailPath: String?
    let sortOrder: Int
    let width: Int?
    let height: Int?
    let thumbnailWidth: Int?
    let thumbnailHeight: Int?
    let fullWidth: Int?
    let fullHeight: Int?
    let createdAt: String
    let signedURL: URL?
    let thumbnailURL: URL?
    let fullURL: URL?

    var resolvedThumbnailURL: URL? {
        thumbnailURL ?? fullURL ?? signedURL
    }

    var resolvedFullURL: URL? {
        fullURL ?? signedURL ?? thumbnailURL
    }

    enum CodingKeys: String, CodingKey {
        case id
        case postID = "post_id"
        case path
        case thumbnailPath = "thumbnail_path"
        case sortOrder = "sort_order"
        case width
        case height
        case thumbnailWidth = "thumbnail_width"
        case thumbnailHeight = "thumbnail_height"
        case fullWidth = "full_width"
        case fullHeight = "full_height"
        case createdAt = "created_at"
        case signedURL
        case thumbnailURL = "thumbnail_url"
        case fullURL = "full_url"
    }
}

nonisolated enum CommunityFeedMode: Codable, Hashable, Sendable {
    case latest
    case hot(days: Int)

    static let defaultHotDays = 30
    static let hotLimit = 10

    var isHot: Bool {
        if case .hot = self { return true }
        return false
    }

    var normalized: CommunityFeedMode {
        switch self {
        case .latest:
            return .latest
        case .hot(let days):
            return .hot(days: max(1, min(days, 90)))
        }
    }

    var cacheKey: String {
        switch normalized {
        case .latest:
            return "latest"
        case .hot(let days):
            return "hot-\(days)"
        }
    }
}

nonisolated enum CommunityFeedContentFilter: String, Codable, Hashable, Sendable {
    case all
    case posts
    case polls
}

nonisolated struct CommunityFeedQuery: Hashable, Sendable {
    static let `default` = CommunityFeedQuery()
    static let hot = CommunityFeedQuery(mode: .hot(days: CommunityFeedMode.defaultHotDays))

    let category: String?
    let search: String?
    let limit: Int
    let mode: CommunityFeedMode
    let contentFilter: CommunityFeedContentFilter

    init(
        category: String? = nil,
        search: String? = nil,
        limit: Int = 20,
        mode: CommunityFeedMode = .latest,
        contentFilter: CommunityFeedContentFilter = .all
    ) {
        let normalizedMode = mode.normalized
        self.mode = normalizedMode
        if normalizedMode.isHot {
            self.category = nil
            self.search = nil
            self.limit = CommunityFeedMode.hotLimit
            self.contentFilter = .posts
        } else {
            self.category = Self.normalized(category)
            self.search = Self.normalized(search)
            self.limit = max(1, min(limit, 50))
            self.contentFilter = self.category == nil && self.search == nil
                ? contentFilter
                : .posts
        }
    }

    var cacheKey: String {
        [
            mode.cacheKey,
            contentFilter.rawValue,
            category ?? "all",
            search ?? "",
            String(limit)
        ].joined(separator: "|")
    }

    var hasSearch: Bool {
        !(search ?? "").isEmpty
    }

    var includesPollsInFeed: Bool {
        !mode.isHot && category == nil && !hasSearch && contentFilter != .posts
    }

    var includesPostsInFeed: Bool {
        contentFilter != .polls
    }

    var hotDays: Int {
        if case .hot(let days) = mode.normalized {
            return days
        }
        return CommunityFeedMode.defaultHotDays
    }

    private static func normalized(_ value: String?) -> String? {
        let trimmed = value?.trimmingCharacters(in: .whitespacesAndNewlines) ?? ""
        return trimmed.isEmpty ? nil : trimmed
    }
}

nonisolated enum CommunityPostPinScope: String, Codable, Hashable, Sendable {
    case global
    case category
}

nonisolated struct CommunityPostPin: Codable, Identifiable, Hashable, Sendable {
    let id: UUID
    let postID: UUID
    let scope: CommunityPostPinScope
    let category: String?
    let priority: Int
    let startsAt: String
    let endsAt: String?
    let status: String
    let reason: String?
    let createdAt: String

    var labelText: String {
        switch scope {
        case .global:
            return L10n.text("置顶")
        case .category:
            return L10n.text("分类置顶")
        }
    }

    var isCurrentlyActive: Bool {
        guard status == "active" else { return false }
        let now = Date()
        if let start = CommunityTimestampFormatter.parse(startsAt), start > now {
            return false
        }
        if let end = endsAt.flatMap(CommunityTimestampFormatter.parse), end <= now {
            return false
        }
        return true
    }

    enum CodingKeys: String, CodingKey {
        case id
        case postID = "post_id"
        case scope
        case category
        case priority
        case startsAt = "starts_at"
        case endsAt = "ends_at"
        case status
        case reason
        case createdAt = "created_at"
    }
}

nonisolated struct CommunityPost: Codable, Identifiable, Hashable, Sendable {
    let id: UUID
    let authorID: UUID
    let title: String
    let body: String
    let category: String?
    let isAnonymous: Bool
    let commentCount: Int
    let likeCount: Int
    let status: String
    let createdAt: String
    let updatedAt: String
    let viewerHasLiked: Bool
    let viewerHasFavorited: Bool
    let pin: CommunityPostPin?
    let author: CommunityProfile?
    let images: [CommunityPostImage]

    init(
        id: UUID,
        authorID: UUID,
        title: String,
        body: String,
        category: String?,
        isAnonymous: Bool,
        commentCount: Int,
        likeCount: Int,
        status: String,
        createdAt: String,
        updatedAt: String,
        viewerHasLiked: Bool,
        viewerHasFavorited: Bool = false,
        pin: CommunityPostPin? = nil,
        author: CommunityProfile?,
        images: [CommunityPostImage]
    ) {
        self.id = id
        self.authorID = authorID
        self.title = title
        self.body = body
        self.category = category
        self.isAnonymous = isAnonymous
        self.commentCount = commentCount
        self.likeCount = likeCount
        self.status = status
        self.createdAt = createdAt
        self.updatedAt = updatedAt
        self.viewerHasLiked = viewerHasLiked
        self.viewerHasFavorited = viewerHasFavorited
        self.pin = pin
        self.author = author
        self.images = images
    }

    init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        id = try container.decode(UUID.self, forKey: .id)
        authorID = try container.decode(UUID.self, forKey: .authorID)
        title = try container.decode(String.self, forKey: .title)
        body = try container.decode(String.self, forKey: .body)
        category = try container.decodeIfPresent(String.self, forKey: .category)
        isAnonymous = try container.decode(Bool.self, forKey: .isAnonymous)
        commentCount = try container.decode(Int.self, forKey: .commentCount)
        likeCount = try container.decode(Int.self, forKey: .likeCount)
        status = try container.decode(String.self, forKey: .status)
        createdAt = try container.decode(String.self, forKey: .createdAt)
        updatedAt = try container.decode(String.self, forKey: .updatedAt)
        viewerHasLiked = try container.decodeIfPresent(Bool.self, forKey: .viewerHasLiked) ?? false
        viewerHasFavorited = try container.decodeIfPresent(Bool.self, forKey: .viewerHasFavorited) ?? false
        pin = try container.decodeIfPresent(CommunityPostPin.self, forKey: .pin)
        author = try container.decodeIfPresent(CommunityProfile.self, forKey: .author)
        images = try container.decodeIfPresent([CommunityPostImage].self, forKey: .images) ?? []
    }

    var displayAuthorName: String {
        if isAnonymous { return L10n.text("匿名同学") }
        return author?.limitedResolvedDisplayName ?? L10n.text(ActiveCampusContext.descriptor.defaultStudentDisplayName)
    }

    var relativeTimestamp: String {
        CommunityTimestampFormatter.displayText(from: createdAt)
    }

    var categoryLabel: String {
        let trimmed = category?.trimmingCharacters(in: .whitespacesAndNewlines) ?? ""
        return trimmed.isEmpty ? L10n.text("社区") : L10n.text(trimmed)
    }

    var pinnedPriority: Int {
        pin?.priority ?? Int.min
    }

    var moderationStatusLabel: String? {
        switch status {
        case "pending_review":
            return L10n.text("待审核")
        case "hidden":
            return L10n.text("已隐藏")
        case "deleted":
            return L10n.text("已删除")
        default:
            return nil
        }
    }

    var shareURL: URL {
        URL(string: "https://myleafy.space/share/community/post/\(id.uuidString)")!
    }

    func replacingPin(_ newPin: CommunityPostPin?) -> CommunityPost {
        CommunityPost(
            id: id,
            authorID: authorID,
            title: title,
            body: body,
            category: category,
            isAnonymous: isAnonymous,
            commentCount: commentCount,
            likeCount: likeCount,
            status: status,
            createdAt: createdAt,
            updatedAt: updatedAt,
            viewerHasLiked: viewerHasLiked,
            viewerHasFavorited: viewerHasFavorited,
            pin: newPin,
            author: author,
            images: images
        )
    }

    var shareText: String {
        let trimmedBody = body.trimmingCharacters(in: .whitespacesAndNewlines)
        let bodyPreview = trimmedBody.isEmpty ? "" : String(trimmedBody.prefix(120))
        return [
            L10n.text("%@ 社区帖子：%@ ", AppBrand.displayName, title).trimmingCharacters(in: .whitespacesAndNewlines),
            bodyPreview,
            shareURL.absoluteString
        ]
            .filter { !$0.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty }
            .joined(separator: "\n")
    }

    enum CodingKeys: String, CodingKey {
        case id
        case authorID = "author_id"
        case title
        case body
        case category
        case isAnonymous = "is_anonymous"
        case commentCount = "comment_count"
        case likeCount = "like_count"
        case status
        case createdAt = "created_at"
        case updatedAt = "updated_at"
        case viewerHasLiked = "viewer_has_liked"
        case viewerHasFavorited = "viewer_has_favorited"
        case pin
        case author
        case images
    }
}

nonisolated enum LeafyLinkedTextBuilder {
    static func attributedString(from text: String) -> AttributedString {
        var attributedText = AttributedString(text)
        guard let detector = try? NSDataDetector(types: NSTextCheckingResult.CheckingType.link.rawValue) else {
            return attributedText
        }

        let nsText = text as NSString
        let matches = detector.matches(
            in: text,
            options: [],
            range: NSRange(location: 0, length: nsText.length)
        )

        for match in matches {
            guard let url = match.url,
                  let stringRange = Range(match.range, in: text),
                  let lowerBound = AttributedString.Index(stringRange.lowerBound, within: attributedText),
                  let upperBound = AttributedString.Index(stringRange.upperBound, within: attributedText)
            else { continue }

            attributedText[lowerBound..<upperBound].link = url
        }

        return attributedText
    }
}

nonisolated enum CommunityFeedItem: Identifiable, Hashable, Sendable {
    case post(CommunityPost)
    case poll(CommunityPoll)

    var id: String {
        switch self {
        case .post(let post):
            return "post-\(post.id.uuidString)"
        case .poll(let poll):
            return "poll-\(poll.id.uuidString)"
        }
    }

    var createdAt: String {
        switch self {
        case .post(let post):
            return post.createdAt
        case .poll(let poll):
            return poll.createdAt
        }
    }

    fileprivate var activePin: CommunityPostPin? {
        guard case .post(let post) = self, post.pin?.isCurrentlyActive == true else {
            return nil
        }
        return post.pin
    }
}

nonisolated enum CommunityFeedItemOrdering {
    static func ordered(
        posts: [CommunityPost],
        polls: [CommunityPoll],
        matching query: CommunityFeedQuery
    ) -> [CommunityFeedItem] {
        let postItems = CommunityFeedOrdering.ordered(posts, matching: query).map(CommunityFeedItem.post)
        guard query.includesPollsInFeed else { return postItems }

        let pollItems = polls
            .filter { $0.status == "published" }
            .map(CommunityFeedItem.poll)

        return Array(sorted(postItems + pollItems).prefix(query.limit))
    }

    static func sorted(_ items: [CommunityFeedItem]) -> [CommunityFeedItem] {
        items.sorted { lhs, rhs in
            switch (lhs.activePin, rhs.activePin) {
            case let (leftPin?, rightPin?):
                if leftPin.priority != rightPin.priority {
                    return leftPin.priority > rightPin.priority
                }
                let leftStart = CommunityTimestampFormatter.parse(leftPin.startsAt) ?? .distantPast
                let rightStart = CommunityTimestampFormatter.parse(rightPin.startsAt) ?? .distantPast
                if leftStart != rightStart {
                    return leftStart > rightStart
                }
            case (.some, .none):
                return true
            case (.none, .some):
                return false
            case (.none, .none):
                break
            }

            let leftCreated = CommunityTimestampFormatter.parse(lhs.createdAt) ?? .distantPast
            let rightCreated = CommunityTimestampFormatter.parse(rhs.createdAt) ?? .distantPast
            return leftCreated > rightCreated
        }
    }
}

nonisolated enum CommunityFeedOrdering {
    static func ordered(_ posts: [CommunityPost], matching query: CommunityFeedQuery) -> [CommunityPost] {
        if query.mode.isHot {
            return hot(posts, days: query.hotDays, limit: query.limit)
        }

        return sorted(filtered(posts, matching: query))
    }

    static func hot(
        _ posts: [CommunityPost],
        days: Int = CommunityFeedMode.defaultHotDays,
        limit: Int = CommunityFeedMode.hotLimit,
        now: Date = Date()
    ) -> [CommunityPost] {
        let safeDays = max(1, min(days, 90))
        let cutoff = Calendar(identifier: .gregorian).date(byAdding: .day, value: -safeDays, to: now) ?? now
        return posts
            .filter { post in
                guard post.status == "published" else { return false }
                guard let createdAt = CommunityTimestampFormatter.parse(post.createdAt) else { return false }
                return createdAt >= cutoff
            }
            .sorted { lhs, rhs in
                let leftScore = hotScore(lhs)
                let rightScore = hotScore(rhs)
                if leftScore != rightScore {
                    return leftScore > rightScore
                }
                let leftCreated = CommunityTimestampFormatter.parse(lhs.createdAt) ?? .distantPast
                let rightCreated = CommunityTimestampFormatter.parse(rhs.createdAt) ?? .distantPast
                return leftCreated > rightCreated
            }
            .prefix(max(1, min(limit, CommunityFeedMode.hotLimit)))
            .map { $0 }
    }

    static func hotScore(_ post: CommunityPost) -> Int {
        post.commentCount * 3 + post.likeCount * 2
    }

    static func filtered(_ posts: [CommunityPost], matching query: CommunityFeedQuery) -> [CommunityPost] {
        posts.filter { post in
            if let category = query.category,
               normalized(post.category) != normalized(category) {
                return false
            }

            guard let search = query.search else { return true }
            let normalizedSearch = normalized(search)
            let searchableText = [
                post.title,
                post.body,
                post.categoryLabel,
                post.displayAuthorName
            ]
                .map(normalized)
                .joined(separator: " ")

            return searchableText.localizedCaseInsensitiveContains(normalizedSearch)
        }
    }

    static func sorted(_ posts: [CommunityPost]) -> [CommunityPost] {
        posts.sorted { lhs, rhs in
            switch (lhs.pin, rhs.pin) {
            case let (leftPin?, rightPin?):
                if leftPin.priority != rightPin.priority {
                    return leftPin.priority > rightPin.priority
                }
                let leftStart = CommunityTimestampFormatter.parse(leftPin.startsAt) ?? .distantPast
                let rightStart = CommunityTimestampFormatter.parse(rightPin.startsAt) ?? .distantPast
                if leftStart != rightStart {
                    return leftStart > rightStart
                }
            case (.some, .none):
                return true
            case (.none, .some):
                return false
            case (.none, .none):
                break
            }

            let leftCreated = CommunityTimestampFormatter.parse(lhs.createdAt) ?? .distantPast
            let rightCreated = CommunityTimestampFormatter.parse(rhs.createdAt) ?? .distantPast
            return leftCreated > rightCreated
        }
    }

    private static func normalized(_ value: String?) -> String {
        (value ?? "")
            .trimmingCharacters(in: .whitespacesAndNewlines)
            .lowercased()
    }
}

nonisolated struct CommunityComment: Codable, Identifiable, Hashable, Sendable {
    let id: UUID
    let postID: UUID
    let authorID: UUID
    let body: String
    let isAnonymous: Bool
    let status: String
    let createdAt: String
    let updatedAt: String
    let author: CommunityProfile?

    var displayAuthorName: String {
        if isAnonymous { return L10n.text("匿名同学") }
        return author?.limitedResolvedDisplayName ?? L10n.text(ActiveCampusContext.descriptor.defaultStudentDisplayName)
    }

    var relativeTimestamp: String {
        CommunityTimestampFormatter.displayText(from: createdAt)
    }

    enum CodingKeys: String, CodingKey {
        case id
        case postID = "post_id"
        case authorID = "author_id"
        case body
        case isAnonymous = "is_anonymous"
        case status
        case createdAt = "created_at"
        case updatedAt = "updated_at"
        case author
    }
}

nonisolated struct CommunityNotification: Codable, Identifiable, Hashable, Sendable {
    let id: UUID
    let recipientID: UUID
    let actorID: UUID?
    let postID: UUID?
    let commentID: UUID?
    let type: CommunityNotificationType
    let title: String
    let body: String?
    let isRead: Bool
    let createdAt: String
    let actor: CommunityProfile?

    var relativeTimestamp: String {
        CommunityTimestampFormatter.displayText(from: createdAt)
    }

    var systemImage: String {
        switch type {
        case .comment:
            return "message.fill"
        case .like:
            return "heart.fill"
        }
    }

    func markingRead() -> CommunityNotification {
        CommunityNotification(
            id: id,
            recipientID: recipientID,
            actorID: actorID,
            postID: postID,
            commentID: commentID,
            type: type,
            title: title,
            body: body,
            isRead: true,
            createdAt: createdAt,
            actor: actor
        )
    }

    enum CodingKeys: String, CodingKey {
        case id
        case recipientID = "recipient_id"
        case actorID = "actor_id"
        case postID = "post_id"
        case commentID = "comment_id"
        case type
        case title
        case body
        case isRead = "is_read"
        case createdAt = "created_at"
        case actor
    }
}

nonisolated enum CommunityNotificationType: String, Codable, Hashable, Sendable {
    case comment
    case like
}

nonisolated struct CommunityNotificationSettings: Codable, Hashable, Sendable {
    let userID: UUID
    let mutedAll: Bool
    let updatedAt: String?

    enum CodingKeys: String, CodingKey {
        case userID = "user_id"
        case mutedAll = "muted_all"
        case updatedAt = "updated_at"
    }
}

nonisolated struct SiteAnnouncement: Codable, Identifiable, Hashable, Sendable {
    let id: UUID
    let title: String
    let body: String
    let level: SiteAnnouncementLevel
    let status: String
    let publishedAt: String?
    let expiresAt: String?
    let createdBy: UUID
    let createdAt: String
    let readAt: String?

    var isRead: Bool {
        readAt != nil
    }

    var relativeTimestamp: String {
        CommunityTimestampFormatter.displayText(from: publishedAt ?? createdAt)
    }

    var systemImage: String {
        "megaphone.fill"
    }

    func markingRead(at timestamp: String) -> SiteAnnouncement {
        SiteAnnouncement(
            id: id,
            title: title,
            body: body,
            level: level,
            status: status,
            publishedAt: publishedAt,
            expiresAt: expiresAt,
            createdBy: createdBy,
            createdAt: createdAt,
            readAt: timestamp
        )
    }

    enum CodingKeys: String, CodingKey {
        case id
        case title
        case body
        case level
        case status
        case publishedAt = "published_at"
        case expiresAt = "expires_at"
        case createdBy = "created_by"
        case createdAt = "created_at"
        case readAt = "read_at"
    }
}

nonisolated enum SiteAnnouncementLevel: String, Codable, Hashable, Sendable {
    case info
    case warning
    case urgent
}

nonisolated enum NotificationFeedItem: Identifiable, Hashable, Sendable {
    case community(CommunityNotification)
    case announcement(SiteAnnouncement)

    var id: String {
        switch self {
        case .community(let notification):
            return "community-\(notification.id.uuidString)"
        case .announcement(let announcement):
            return "announcement-\(announcement.id.uuidString)"
        }
    }

    var title: String {
        switch self {
        case .community(let notification):
            return notification.title
        case .announcement(let announcement):
            return announcement.title
        }
    }

    var body: String? {
        switch self {
        case .community(let notification):
            return notification.body
        case .announcement(let announcement):
            return announcement.body
        }
    }

    var isRead: Bool {
        switch self {
        case .community(let notification):
            return notification.isRead
        case .announcement(let announcement):
            return announcement.isRead
        }
    }

    var relativeTimestamp: String {
        switch self {
        case .community(let notification):
            return notification.relativeTimestamp
        case .announcement(let announcement):
            return announcement.relativeTimestamp
        }
    }

    var systemImage: String {
        switch self {
        case .community(let notification):
            return notification.systemImage
        case .announcement(let announcement):
            return announcement.systemImage
        }
    }

    func markingRead(at timestamp: String) -> NotificationFeedItem {
        switch self {
        case .community(let notification):
            return .community(notification.markingRead())
        case .announcement(let announcement):
            return .announcement(announcement.markingRead(at: timestamp))
        }
    }

    var sortDate: Date {
        let rawValue: String
        switch self {
        case .community(let notification):
            rawValue = notification.createdAt
        case .announcement(let announcement):
            rawValue = announcement.publishedAt ?? announcement.createdAt
        }

        return CommunityTimestampFormatter.parse(rawValue) ?? .distantPast
    }
}

nonisolated struct CreatePostInput: Sendable {
    let title: String
    let body: String
    let category: String?
    let isAnonymous: Bool
}

nonisolated enum CommunityPollRules {
    static let minOptions = 2
    static let maxOptions = 6
    static let maxQuestionLength = 120
    static let maxDetailLength = 500
    static let maxOptionLength = 80
}

nonisolated struct CommunityPollOption: Codable, Identifiable, Hashable, Sendable {
    let id: UUID
    let pollID: UUID
    let text: String
    let sortOrder: Int
    let voteCount: Int
    let createdAt: String

    func voteShare(totalVotes: Int) -> Double {
        guard totalVotes > 0 else { return 0 }
        return Double(voteCount) / Double(totalVotes)
    }

    func percentageText(totalVotes: Int) -> String {
        let percentage = Int((voteShare(totalVotes: totalVotes) * 100).rounded())
        return "\(percentage)%"
    }

    enum CodingKeys: String, CodingKey {
        case id
        case pollID = "poll_id"
        case text
        case sortOrder = "sort_order"
        case voteCount = "vote_count"
        case createdAt = "created_at"
    }
}

nonisolated struct CommunityPoll: Codable, Identifiable, Hashable, Sendable {
    let id: UUID
    let authorID: UUID
    let question: String
    let detail: String?
    let status: String
    let totalVoteCount: Int
    let viewerOptionID: UUID?
    let closesAt: String?
    let deletionStatus: String
    let deletionRequestedAt: String?
    let deletionReason: String?
    let deletionReviewedAt: String?
    let deletionReviewReason: String?
    let createdAt: String
    let updatedAt: String
    let author: CommunityProfile?
    let options: [CommunityPollOption]

    var relativeTimestamp: String {
        CommunityTimestampFormatter.displayText(from: createdAt)
    }

    var isClosed: Bool {
        guard status == "published" else { return true }
        guard let closesAt, let closeDate = CommunityTimestampFormatter.parse(closesAt) else {
            return false
        }
        return closeDate <= Date()
    }

    var isPendingReview: Bool {
        status == "pending_review"
    }

    var isDeletionPending: Bool {
        deletionStatus == "pending"
    }

    var canRequestDeletion: Bool {
        status != "deleted" && deletionStatus != "pending"
    }

    var statusText: String {
        if deletionStatus == "pending" {
            return "删除待审核"
        }
        if deletionStatus == "rejected" {
            return "删除被拒"
        }

        switch status {
        case "pending_review": return "待审核"
        case "published": return isClosed ? "已截止" : "投票中"
        case "hidden": return "未通过"
        case "deleted": return "已删除"
        default: return status
        }
    }

    var canVote: Bool {
        !isClosed && !options.isEmpty
    }

    var shouldRevealResults: Bool {
        viewerOptionID != nil || isClosed
    }

    var closesAtText: String? {
        guard let closesAt else { return nil }
        return CommunityTimestampFormatter.displayText(from: closesAt)
    }

    var displayAuthorName: String {
        author?.limitedResolvedDisplayName ?? ActiveCampusContext.descriptor.defaultStudentDisplayName
    }

    enum CodingKeys: String, CodingKey {
        case id
        case authorID = "author_id"
        case question
        case detail
        case status
        case totalVoteCount = "total_vote_count"
        case viewerOptionID = "viewer_option_id"
        case closesAt = "closes_at"
        case deletionStatus = "deletion_status"
        case deletionRequestedAt = "deletion_requested_at"
        case deletionReason = "deletion_reason"
        case deletionReviewedAt = "deletion_reviewed_at"
        case deletionReviewReason = "deletion_review_reason"
        case createdAt = "created_at"
        case updatedAt = "updated_at"
        case author
        case options
    }

    init(
        id: UUID,
        authorID: UUID,
        question: String,
        detail: String?,
        status: String,
        totalVoteCount: Int,
        viewerOptionID: UUID?,
        closesAt: String?,
        deletionStatus: String = "none",
        deletionRequestedAt: String? = nil,
        deletionReason: String? = nil,
        deletionReviewedAt: String? = nil,
        deletionReviewReason: String? = nil,
        createdAt: String,
        updatedAt: String,
        author: CommunityProfile?,
        options: [CommunityPollOption]
    ) {
        self.id = id
        self.authorID = authorID
        self.question = question
        self.detail = detail
        self.status = status
        self.totalVoteCount = totalVoteCount
        self.viewerOptionID = viewerOptionID
        self.closesAt = closesAt
        self.deletionStatus = deletionStatus
        self.deletionRequestedAt = deletionRequestedAt
        self.deletionReason = deletionReason
        self.deletionReviewedAt = deletionReviewedAt
        self.deletionReviewReason = deletionReviewReason
        self.createdAt = createdAt
        self.updatedAt = updatedAt
        self.author = author
        self.options = options
    }

    init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        id = try container.decode(UUID.self, forKey: .id)
        authorID = try container.decode(UUID.self, forKey: .authorID)
        question = try container.decode(String.self, forKey: .question)
        detail = try container.decodeIfPresent(String.self, forKey: .detail)
        status = try container.decode(String.self, forKey: .status)
        totalVoteCount = try container.decode(Int.self, forKey: .totalVoteCount)
        viewerOptionID = try container.decodeIfPresent(UUID.self, forKey: .viewerOptionID)
        closesAt = try container.decodeIfPresent(String.self, forKey: .closesAt)
        deletionStatus = try container.decodeIfPresent(String.self, forKey: .deletionStatus) ?? "none"
        deletionRequestedAt = try container.decodeIfPresent(String.self, forKey: .deletionRequestedAt)
        deletionReason = try container.decodeIfPresent(String.self, forKey: .deletionReason)
        deletionReviewedAt = try container.decodeIfPresent(String.self, forKey: .deletionReviewedAt)
        deletionReviewReason = try container.decodeIfPresent(String.self, forKey: .deletionReviewReason)
        createdAt = try container.decode(String.self, forKey: .createdAt)
        updatedAt = try container.decode(String.self, forKey: .updatedAt)
        author = try container.decodeIfPresent(CommunityProfile.self, forKey: .author)
        options = try container.decodeIfPresent([CommunityPollOption].self, forKey: .options) ?? []
    }
}

nonisolated struct CreatePollInput: Sendable {
    let question: String
    let detail: String?
    let options: [String]
    let closesAt: String?

    var normalizedQuestion: String {
        question.trimmingCharacters(in: .whitespacesAndNewlines)
    }

    var normalizedDetail: String? {
        let trimmed = detail?.trimmingCharacters(in: .whitespacesAndNewlines) ?? ""
        return trimmed.isEmpty ? nil : trimmed
    }

    var normalizedOptions: [String] {
        options
            .map { $0.trimmingCharacters(in: .whitespacesAndNewlines) }
            .filter { !$0.isEmpty }
    }

    var validationError: String? {
        if normalizedQuestion.isEmpty {
            return "投票问题不能为空。"
        }
        if normalizedQuestion.count > CommunityPollRules.maxQuestionLength {
            return "投票问题最多 \(CommunityPollRules.maxQuestionLength) 个字。"
        }
        if (normalizedDetail?.count ?? 0) > CommunityPollRules.maxDetailLength {
            return "补充说明最多 \(CommunityPollRules.maxDetailLength) 个字。"
        }
        if normalizedOptions.count < CommunityPollRules.minOptions {
            return "至少需要 \(CommunityPollRules.minOptions) 个选项。"
        }
        if normalizedOptions.count > CommunityPollRules.maxOptions {
            return "最多只能设置 \(CommunityPollRules.maxOptions) 个选项。"
        }
        if normalizedOptions.contains(where: { $0.count > CommunityPollRules.maxOptionLength }) {
            return "单个选项最多 \(CommunityPollRules.maxOptionLength) 个字。"
        }
        return nil
    }
}

nonisolated struct CommunityProfileUpdateInput: Sendable {
    let nickname: String
    let major: String?
    let grade: String?
    let bio: String?
    let showsEduVerificationBadge: Bool

    init(
        nickname: String,
        major: String?,
        grade: String?,
        bio: String? = nil,
        showsEduVerificationBadge: Bool = false
    ) {
        self.nickname = nickname
        self.major = major
        self.grade = grade
        self.bio = bio
        self.showsEduVerificationBadge = showsEduVerificationBadge
    }
}

nonisolated enum CommunityEmailBinding {
    static let verificationCodeLength = 8

    static func normalizedEmail(_ value: String) -> String {
        value.trimmingCharacters(in: .whitespacesAndNewlines).lowercased()
    }

    static func normalizedCode(_ value: String) -> String {
        String(value.filter(\.isNumber).prefix(verificationCodeLength))
    }

    static func isCompleteVerificationCode(_ value: String) -> Bool {
        value.filter(\.isNumber).count == verificationCodeLength
    }

    static func shouldResendVerification(pendingEmail: String?, requestedEmail: String) -> Bool {
        guard let pendingEmail else { return false }
        let normalizedPendingEmail = normalizedEmail(pendingEmail)
        let normalizedRequestedEmail = normalizedEmail(requestedEmail)
        return !normalizedPendingEmail.isEmpty && normalizedPendingEmail == normalizedRequestedEmail
    }

    static func isAlreadyBound(boundEmail: String?, requestedEmail: String) -> Bool {
        guard let boundEmail else { return false }
        let normalizedBoundEmail = normalizedEmail(boundEmail)
        let normalizedRequestedEmail = normalizedEmail(requestedEmail)
        return !normalizedBoundEmail.isEmpty && normalizedBoundEmail == normalizedRequestedEmail
    }

    static func isValidEmail(_ email: String) -> Bool {
        let pattern = #"^[A-Z0-9._%+-]+@[A-Z0-9.-]+\.[A-Z]{2,}$"#
        return email.range(of: pattern, options: [.regularExpression, .caseInsensitive]) != nil
    }
}

nonisolated struct CommunityEmailBindingInput: Sendable {
    let email: String

    init(email: String) {
        self.email = CommunityEmailBinding.normalizedEmail(email)
    }
}

nonisolated struct CommunityEmailVerificationInput: Sendable {
    let email: String
    let code: String

    init(email: String, code: String) {
        self.email = CommunityEmailBinding.normalizedEmail(email)
        self.code = CommunityEmailBinding.normalizedCode(code)
    }
}

nonisolated struct TeacherProfile: Codable, Identifiable, Hashable, Sendable {
    let id: Int64
    let name: String
    let unit: String
    let ratingAverage: Double
    let ratingCount: Int
    let rating1Count: Int
    let rating2Count: Int
    let rating3Count: Int
    let rating4Count: Int
    let rating5Count: Int
    let createdAt: String
    let updatedAt: String

    var ratingCountsByStars: [Int: Int] {
        [
            1: rating1Count,
            2: rating2Count,
            3: rating3Count,
            4: rating4Count,
            5: rating5Count
        ]
    }

    enum CodingKeys: String, CodingKey {
        case id
        case name
        case unit
        case ratingAverage = "rating_average"
        case ratingCount = "rating_count"
        case rating1Count = "rating_1_count"
        case rating2Count = "rating_2_count"
        case rating3Count = "rating_3_count"
        case rating4Count = "rating_4_count"
        case rating5Count = "rating_5_count"
        case createdAt = "created_at"
        case updatedAt = "updated_at"
    }
}

nonisolated struct TeacherRating: Codable, Hashable, Sendable {
    let teacherID: Int64
    let userID: UUID
    let stars: Int
    let createdAt: String
    let updatedAt: String

    enum CodingKeys: String, CodingKey {
        case teacherID = "teacher_id"
        case userID = "user_id"
        case stars
        case createdAt = "created_at"
        case updatedAt = "updated_at"
    }
}

nonisolated struct TeacherRatingSummary: Identifiable, Hashable, Sendable {
    let teacher: TeacherProfile
    let myRating: TeacherRating?

    var id: Int64 { teacher.id }
}

nonisolated enum CatalogSuggestionType: String, Codable, Hashable, Sendable {
    case teacher
    case course
    case dish
}

nonisolated struct CatalogSuggestionInput: Hashable, Sendable {
    let type: CatalogSuggestionType
    let name: String
    let unit: String
    let teacherName: String?
    let category: String?
    let credit: Double?
    let initialStars: Int?
    let note: String?
}

nonisolated struct CourseProfile: Codable, Identifiable, Hashable, Sendable {
    let id: Int64
    let name: String
    let unit: String
    let category: String
    let credit: Double
    let ratingAverage: Double
    let ratingCount: Int
    let rating1Count: Int
    let rating2Count: Int
    let rating3Count: Int
    let rating4Count: Int
    let rating5Count: Int
    let createdAt: String
    let updatedAt: String

    var ratingCountsByStars: [Int: Int] {
        [
            1: rating1Count,
            2: rating2Count,
            3: rating3Count,
            4: rating4Count,
            5: rating5Count
        ]
    }

    var displayCategory: String {
        let trimmed = category.trimmingCharacters(in: .whitespacesAndNewlines)
        return trimmed.isEmpty ? "公选课" : trimmed
    }

    var displayUnit: String {
        let trimmed = unit.trimmingCharacters(in: .whitespacesAndNewlines)
        return trimmed.isEmpty ? "未设置开课单位" : trimmed
    }

    enum CodingKeys: String, CodingKey {
        case id
        case name
        case unit
        case category
        case credit
        case ratingAverage = "rating_average"
        case ratingCount = "rating_count"
        case rating1Count = "rating_1_count"
        case rating2Count = "rating_2_count"
        case rating3Count = "rating_3_count"
        case rating4Count = "rating_4_count"
        case rating5Count = "rating_5_count"
        case createdAt = "created_at"
        case updatedAt = "updated_at"
    }
}

nonisolated struct CourseRating: Codable, Hashable, Sendable {
    let courseID: Int64
    let userID: UUID
    let stars: Int
    let createdAt: String
    let updatedAt: String

    enum CodingKeys: String, CodingKey {
        case courseID = "course_id"
        case userID = "user_id"
        case stars
        case createdAt = "created_at"
        case updatedAt = "updated_at"
    }
}

nonisolated struct CourseRatingSummary: Identifiable, Hashable, Sendable {
    let course: CourseProfile
    let myRating: CourseRating?

    var id: Int64 { course.id }
}

nonisolated struct DishProfile: Codable, Identifiable, Hashable, Sendable {
    let id: Int64
    let name: String
    let location: String
    let ratingAverage: Double
    let ratingCount: Int
    let rating1Count: Int
    let rating2Count: Int
    let rating3Count: Int
    let rating4Count: Int
    let rating5Count: Int
    let createdAt: String
    let updatedAt: String

    var ratingCountsByStars: [Int: Int] {
        [
            1: rating1Count,
            2: rating2Count,
            3: rating3Count,
            4: rating4Count,
            5: rating5Count
        ]
    }

    enum CodingKeys: String, CodingKey {
        case id
        case name
        case location
        case ratingAverage = "rating_average"
        case ratingCount = "rating_count"
        case rating1Count = "rating_1_count"
        case rating2Count = "rating_2_count"
        case rating3Count = "rating_3_count"
        case rating4Count = "rating_4_count"
        case rating5Count = "rating_5_count"
        case createdAt = "created_at"
        case updatedAt = "updated_at"
    }
}

nonisolated struct DishRating: Codable, Hashable, Sendable {
    let dishID: Int64
    let userID: UUID
    let stars: Int
    let createdAt: String
    let updatedAt: String

    enum CodingKeys: String, CodingKey {
        case dishID = "dish_id"
        case userID = "user_id"
        case stars
        case createdAt = "created_at"
        case updatedAt = "updated_at"
    }
}

nonisolated struct DishRatingSummary: Identifiable, Hashable, Sendable {
    let dish: DishProfile
    let myRating: DishRating?

    var id: Int64 { dish.id }
}

nonisolated struct CommunityImageUpload: Identifiable, Hashable, Sendable {
    static let postImageLimit = 4
    static let postImageMaxPixelDimension: CGFloat = 1600
    static let postImageMaxBytes = 800 * 1024
    static let avatarImageMaxPixelDimension: CGFloat = 512
    static let avatarImageMaxBytes = 250 * 1024
    static let profileCoverImageMaxPixelDimension: CGFloat = 1800
    static let profileCoverImageMaxBytes = 900 * 1024

    let id: UUID
    let data: Data
    let mimeType: String
    let fileExtension: String
    let width: Int?
    let height: Int?

    init(
        id: UUID = UUID(),
        data: Data,
        mimeType: String,
        fileExtension: String,
        width: Int? = nil,
        height: Int? = nil
    ) {
        self.id = id
        self.data = data
        self.mimeType = mimeType
        self.fileExtension = fileExtension
        self.width = width
        self.height = height
    }
}

nonisolated enum CommunityTimestampFormatter {
    private static let fractionalFormatter: ISO8601DateFormatter = {
        let formatter = ISO8601DateFormatter()
        formatter.formatOptions = [.withInternetDateTime, .withFractionalSeconds]
        return formatter
    }()

    private static let plainFormatter: ISO8601DateFormatter = {
        let formatter = ISO8601DateFormatter()
        formatter.formatOptions = [.withInternetDateTime]
        return formatter
    }()

    private static func relativeFormatter(language: AppLanguagePreference) -> RelativeDateTimeFormatter {
        let formatter = RelativeDateTimeFormatter()
        formatter.locale = Locale(identifier: language.localeIdentifier)
        formatter.unitsStyle = .full
        return formatter
    }

    static func displayText(from rawValue: String) -> String {
        guard let date = parse(rawValue) else { return rawValue }
        let language = AppLanguagePreference.current

        let calendar = Calendar.current
        if calendar.isDateInToday(date) {
            let formatter = DateFormatter()
            formatter.locale = Locale(identifier: language.localeIdentifier)
            formatter.dateFormat = "今天 HH:mm"
            return formatter.string(from: date)
        }

        if calendar.isDateInYesterday(date) {
            let formatter = DateFormatter()
            formatter.locale = Locale(identifier: language.localeIdentifier)
            formatter.dateFormat = "昨天 HH:mm"
            return formatter.string(from: date)
        }

        let now = Date()
        if abs(date.timeIntervalSince(now)) < 6 * 24 * 60 * 60 {
            return relativeFormatter(language: language).localizedString(for: date, relativeTo: now)
        }

        let formatter = DateFormatter()
        formatter.locale = Locale(identifier: language.localeIdentifier)
        formatter.dateFormat = "MM-dd HH:mm"
        return formatter.string(from: date)
    }

    static func parse(_ rawValue: String) -> Date? {
        fractionalFormatter.date(from: rawValue) ?? plainFormatter.date(from: rawValue)
    }
}
