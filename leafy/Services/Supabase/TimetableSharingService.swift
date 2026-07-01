import Foundation
import Supabase

nonisolated enum TimetableSharingError: LocalizedError {
    case missingProfile
    case profileCompletionRequired
    case emptySnapshot
    case timetableNotPublished
    case invalidInviteCode
    case inviteExpired
    case inviteUsed
    case inviteSelf
    case inviteCollision
    case notShareOwner
    case backend(String)

    var errorDescription: String? {
        switch self {
        case .missingProfile:
            return "共享课表需要先建立社区身份，请稍后重试。"
        case .profileCompletionRequired:
            return "请先完善社区昵称后再使用共享课表。"
        case .emptySnapshot:
            return "本地课表为空，请先在课表页或缓存与同步中同步课表。"
        case .timetableNotPublished:
            return "请先发布或更新你的课表，再生成邀请码。"
        case .invalidInviteCode:
            return "邀请码无效，请检查后重新输入。"
        case .inviteExpired:
            return "邀请码已过期，请让对方重新生成。"
        case .inviteUsed:
            return "邀请码已经被使用，请让对方重新生成。"
        case .inviteSelf:
            return "不能接受自己的共享课表邀请码。"
        case .inviteCollision:
            return "邀请码生成冲突，请重新生成一次。"
        case .notShareOwner:
            return "你没有权限撤销这条共享关系。"
        case .backend(let message):
            return message
        }
    }
}

actor TimetableSharingService {
    static let shared = TimetableSharingService()

    private let inviteCodeLength = 12
    private let inviteCodeAlphabet = Array("ABCDEFGHJKLMNPQRSTUVWXYZ234567")

    private init() {}

    func publishSnapshot(courses: [SharedTimetableCourse]) async throws -> SharedTimetableSnapshot {
        guard !courses.isEmpty else {
            throw TimetableSharingError.emptySnapshot
        }

        let profile = try await requireCompletedProfile()
        let client = try LeafySupabase.shared.requireClient()
        let semesterConfig = await SemesterConfig.refreshRemoteIfAvailable()
        let now = ISO8601DateFormatter().string(from: Date())
        let upsert = TimetableSnapshotUpsert(
            campusID: profile.campusID,
            ownerID: profile.id,
            semesterID: semesterConfig.semesterID,
            courses: courses,
            courseCount: courses.count,
            publishedAt: now
        )

        do {
            let record: TimetableSnapshotRecord = try await client
                .from("timetable_snapshots")
                .upsert(upsert, onConflict: "owner_id,semester_id")
                .select()
                .single()
                .execute()
                .value

            return try await hydrateSnapshot(record)
        } catch {
            throw mapError(error)
        }
    }

    @discardableResult
    func publishExistingSnapshotIfNeeded(courses: [SharedTimetableCourse]) async -> Bool {
        guard !courses.isEmpty,
              let profile = try? await completedProfileIfAvailable(),
              let client = try? LeafySupabase.shared.requireClient() else {
            return false
        }
        let semesterConfig = await SemesterConfig.refreshRemoteIfAvailable()

        do {
            let records: [TimetableSnapshotRecord] = try await client
                .from("timetable_snapshots")
                .select()
                .eq("campus_id", value: profile.campusID)
                .eq("owner_id", value: profile.id.uuidString)
                .eq("semester_id", value: semesterConfig.semesterID)
                .limit(1)
                .execute()
                .value

            guard !records.isEmpty else { return false }
            _ = try await publishSnapshot(courses: courses)
            return true
        } catch {
            return false
        }
    }

    func fetchMySnapshot() async throws -> SharedTimetableSnapshot? {
        let profile = try await requireCompletedProfile()
        let client = try LeafySupabase.shared.requireClient()
        let semesterConfig = await SemesterConfig.refreshRemoteIfAvailable()

        do {
            let records: [TimetableSnapshotRecord] = try await client
                .from("timetable_snapshots")
                .select()
                .eq("campus_id", value: profile.campusID)
                .eq("owner_id", value: profile.id.uuidString)
                .eq("semester_id", value: semesterConfig.semesterID)
                .limit(1)
                .execute()
                .value

            guard let record = records.first else { return nil }
            return try await hydrateSnapshot(record)
        } catch {
            throw mapError(error)
        }
    }

    func fetchViewableSnapshots() async throws -> [SharedTimetableSnapshot] {
        let profile = try await requireCompletedProfile()
        let client = try LeafySupabase.shared.requireClient()
        let semesterConfig = await SemesterConfig.refreshRemoteIfAvailable()

        do {
            let records: [TimetableSnapshotRecord] = try await client
                .from("timetable_snapshots")
                .select()
                .eq("campus_id", value: profile.campusID)
                .eq("semester_id", value: semesterConfig.semesterID)
                .neq("owner_id", value: profile.id.uuidString)
                .order("published_at", ascending: false)
                .execute()
                .value

            return try await hydrateSnapshots(records)
        } catch {
            throw mapError(error)
        }
    }

    func fetchMyShareMembers() async throws -> [TimetableShareMember] {
        let profile = try await requireCompletedProfile()
        let client = try LeafySupabase.shared.requireClient()

        do {
            let records: [TimetableShareMemberRecord] = try await client
                .from("timetable_share_members")
                .select()
                .eq("campus_id", value: profile.campusID)
                .eq("owner_id", value: profile.id.uuidString)
                .order("created_at", ascending: false)
                .execute()
                .value

            let activeRecords = records.filter { $0.revokedAt == nil }
            return try await hydrateMembers(activeRecords)
        } catch {
            throw mapError(error)
        }
    }

    func fetchMyInvites() async throws -> [TimetableInvite] {
        let profile = try await requireCompletedProfile()
        let client = try LeafySupabase.shared.requireClient()

        do {
            let records: [TimetableInviteRecord] = try await client
                .from("timetable_invites")
                .select()
                .eq("campus_id", value: profile.campusID)
                .eq("owner_id", value: profile.id.uuidString)
                .order("created_at", ascending: false)
                .limit(20)
                .execute()
                .value

            return records.map { $0.invite(code: nil) }
        } catch {
            throw mapError(error)
        }
    }

    func createInvite() async throws -> TimetableInvite {
        _ = try await requireCompletedProfile()
        let client = try LeafySupabase.shared.requireClient()

        var lastError: Error?
        for _ in 0..<3 {
            let code = generateInviteCode()
            do {
                let records: [TimetableInviteRecord] = try await client
                    .rpc("create_timetable_invite", params: TimetableInviteCodeRPCParams(code: code))
                    .execute()
                    .value

                guard let record = records.first else {
                    throw TimetableSharingError.backend("邀请码创建失败，请稍后重试。")
                }
                return record.invite(code: code)
            } catch {
                let mapped = mapError(error)
                if case TimetableSharingError.inviteCollision = mapped {
                    lastError = mapped
                    continue
                }
                throw mapped
            }
        }

        throw lastError.map(mapError) ?? TimetableSharingError.inviteCollision
    }

    func acceptInvite(code: String) async throws -> SharedTimetableSnapshot {
        _ = try await requireCompletedProfile()
        let client = try LeafySupabase.shared.requireClient()
        let normalized = normalizeInviteCode(code)

        do {
            let records: [TimetableSnapshotRecord] = try await client
                .rpc("accept_timetable_invite", params: TimetableInviteCodeRPCParams(code: normalized))
                .execute()
                .value

            guard let record = records.first else {
                throw TimetableSharingError.backend("接受邀请失败，请稍后重试。")
            }
            return try await hydrateSnapshot(record)
        } catch {
            throw mapError(error)
        }
    }

    func revokeShare(viewerID: UUID) async throws {
        let profile = try await requireCompletedProfile()
        let client = try LeafySupabase.shared.requireClient()

        do {
            _ = try await client
                .rpc(
                    "revoke_timetable_share",
                    params: TimetableRevokeShareRPCParams(ownerID: profile.id, viewerID: viewerID)
                )
                .execute()
        } catch {
            throw mapError(error)
        }
    }

    func stopSharing() async throws {
        _ = try await requireCompletedProfile()
        let client = try LeafySupabase.shared.requireClient()

        do {
            _ = try await client
                .rpc("stop_timetable_sharing")
                .execute()
        } catch {
            throw mapError(error)
        }
    }

    func leaveShare(ownerID: UUID) async throws {
        _ = try await requireCompletedProfile()
        let client = try LeafySupabase.shared.requireClient()

        do {
            _ = try await client
                .rpc("leave_timetable_share", params: TimetableLeaveShareRPCParams(ownerID: ownerID))
                .execute()
        } catch {
            throw mapError(error)
        }
    }

    private func requireCompletedProfile() async throws -> CommunityProfile {
        try await CommunityService.shared.ensureAnonymousSession()
        guard let profile = try await CommunityService.shared.fetchCurrentProfile() else {
            throw TimetableSharingError.missingProfile
        }

        guard profile.isProfileComplete,
              !profile.nickname.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty else {
            throw TimetableSharingError.profileCompletionRequired
        }

        return profile
    }

    private func completedProfileIfAvailable() async throws -> CommunityProfile? {
        try await CommunityService.shared.ensureAnonymousSession()
        guard let profile = try await CommunityService.shared.fetchCurrentProfile(),
              profile.isProfileComplete,
              !profile.nickname.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty else {
            return nil
        }

        return profile
    }

    private func hydrateSnapshots(_ records: [TimetableSnapshotRecord]) async throws -> [SharedTimetableSnapshot] {
        var snapshots: [SharedTimetableSnapshot] = []
        snapshots.reserveCapacity(records.count)
        for record in records {
            snapshots.append(try await hydrateSnapshot(record))
        }
        return snapshots
    }

    private func hydrateSnapshot(_ record: TimetableSnapshotRecord) async throws -> SharedTimetableSnapshot {
        let owner = try? await CommunityService.shared.fetchCurrentProfile(userID: record.ownerID)
        return record.snapshot(owner: owner)
    }

    private func hydrateMembers(_ records: [TimetableShareMemberRecord]) async throws -> [TimetableShareMember] {
        var members: [TimetableShareMember] = []
        members.reserveCapacity(records.count)
        for record in records {
            let viewer = try? await CommunityService.shared.fetchCurrentProfile(userID: record.viewerID)
            members.append(record.member(viewer: viewer))
        }
        return members
    }

    private func generateInviteCode() -> String {
        var generator = SystemRandomNumberGenerator()
        return String((0..<inviteCodeLength).map { _ in
            inviteCodeAlphabet.randomElement(using: &generator) ?? "A"
        })
    }

    nonisolated static func normalizeInviteCode(_ code: String) -> String {
        let allowedCharacters = Set("ABCDEFGHIJKLMNOPQRSTUVWXYZ234567")
        return code
            .uppercased()
            .filter { allowedCharacters.contains($0) }
    }

    private nonisolated func normalizeInviteCode(_ code: String) -> String {
        Self.normalizeInviteCode(code)
    }

    private nonisolated func mapError(_ error: Error) -> TimetableSharingError {
        if let sharingError = error as? TimetableSharingError {
            return sharingError
        }

        let message = error.localizedDescription
        if message.contains("MISSING_PROFILE") { return .missingProfile }
        if message.contains("TIMETABLE_NOT_PUBLISHED") { return .timetableNotPublished }
        if message.contains("INVALID_INVITE_CODE") { return .invalidInviteCode }
        if message.contains("INVITE_EXPIRED") { return .inviteExpired }
        if message.contains("INVITE_USED") { return .inviteUsed }
        if message.contains("INVITE_SELF") { return .inviteSelf }
        if message.contains("INVITE_CODE_COLLISION") { return .inviteCollision }
        if message.contains("NOT_SHARE_OWNER") { return .notShareOwner }
        if message.contains("function digest") || message.contains("hash_timetable_invite_code") {
            return .backend("共享课表服务正在更新，请稍后重试。")
        }
        if message.contains("column reference")
            && (message.contains("owner_id") || message.contains("own_id"))
            && message.contains("ambiguous") {
            return .backend("共享课表服务正在更新，请稍后重试。")
        }
        return .backend(message)
    }
}

private nonisolated struct TimetableSnapshotRecord: Codable, Sendable {
    let id: UUID
    let ownerID: UUID
    let semesterID: String
    let courses: [SharedTimetableCourse]
    let courseCount: Int
    let publishedAt: String
    let createdAt: String
    let updatedAt: String

    func snapshot(owner: CommunityProfile?) -> SharedTimetableSnapshot {
        SharedTimetableSnapshot(
            id: id,
            ownerID: ownerID,
            semesterID: semesterID,
            courses: courses,
            courseCount: courseCount,
            publishedAt: publishedAt,
            createdAt: createdAt,
            updatedAt: updatedAt,
            owner: owner
        )
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
    }
}

private nonisolated struct TimetableSnapshotUpsert: Encodable, Sendable {
    let campusID: String
    let ownerID: UUID
    let semesterID: String
    let courses: [SharedTimetableCourse]
    let courseCount: Int
    let publishedAt: String

    enum CodingKeys: String, CodingKey {
        case campusID = "campus_id"
        case ownerID = "owner_id"
        case semesterID = "semester_id"
        case courses
        case courseCount = "course_count"
        case publishedAt = "published_at"
    }
}

private nonisolated struct TimetableShareMemberRecord: Codable, Sendable {
    let id: UUID
    let ownerID: UUID
    let viewerID: UUID
    let createdAt: String
    let updatedAt: String
    let revokedAt: String?

    func member(viewer: CommunityProfile?) -> TimetableShareMember {
        TimetableShareMember(
            id: id,
            ownerID: ownerID,
            viewerID: viewerID,
            createdAt: createdAt,
            updatedAt: updatedAt,
            revokedAt: revokedAt,
            viewer: viewer
        )
    }

    enum CodingKeys: String, CodingKey {
        case id
        case ownerID = "owner_id"
        case viewerID = "viewer_id"
        case createdAt = "created_at"
        case updatedAt = "updated_at"
        case revokedAt = "revoked_at"
    }
}

private nonisolated struct TimetableInviteRecord: Codable, Sendable {
    let id: UUID
    let ownerID: UUID
    let semesterID: String
    let expiresAt: String
    let acceptedBy: UUID?
    let acceptedAt: String?
    let createdAt: String

    func invite(code: String?) -> TimetableInvite {
        TimetableInvite(
            id: id,
            ownerID: ownerID,
            semesterID: semesterID,
            code: code,
            expiresAt: expiresAt,
            acceptedBy: acceptedBy,
            acceptedAt: acceptedAt,
            createdAt: createdAt
        )
    }

    enum CodingKeys: String, CodingKey {
        case id
        case ownerID = "owner_id"
        case semesterID = "semester_id"
        case expiresAt = "expires_at"
        case acceptedBy = "accepted_by"
        case acceptedAt = "accepted_at"
        case createdAt = "created_at"
    }
}

private nonisolated struct TimetableInviteCodeRPCParams: Encodable, Sendable {
    let code: String

    enum CodingKeys: String, CodingKey {
        case code = "p_code"
    }
}

private nonisolated struct TimetableRevokeShareRPCParams: Encodable, Sendable {
    let ownerID: UUID
    let viewerID: UUID

    enum CodingKeys: String, CodingKey {
        case ownerID = "p_owner_id"
        case viewerID = "p_viewer_id"
    }
}

private nonisolated struct TimetableLeaveShareRPCParams: Encodable, Sendable {
    let ownerID: UUID

    enum CodingKeys: String, CodingKey {
        case ownerID = "p_owner_id"
    }
}
