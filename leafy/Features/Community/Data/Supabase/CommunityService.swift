import Foundation
import OSLog
import Supabase

enum CommunityServiceError: LocalizedError {
    case missingAuthenticatedUser
    case schoolSessionMissing
    case imageLimitExceeded
    case postRateLimitExceeded
    case profileCompletionRequired
    case invalidEmail
    case cannotLikeOwnPost
    case userMuted
    case termsAcceptanceRequired
    case contentRejected
    case invalidPoll
    case pollClosed
    case edgeFunctionRejected(String)

    var errorDescription: String? {
        switch self {
        case .missingAuthenticatedUser:
            return "社区身份尚未建立，请稍后重试。"
        case .schoolSessionMissing:
            return "教务学号缺失，请连接校园网后重新登录教务系统。"
        case .imageLimitExceeded:
            return "单条帖子最多上传 \(CommunityImageUpload.postImageLimit) 张图片。"
        case .postRateLimitExceeded:
            return "发帖太频繁了，每小时最多发布 2 篇帖子。"
        case .profileCompletionRequired:
            return "请先完善社区资料后再继续。"
        case .invalidEmail:
            return "请输入有效的邮箱地址。"
        case .cannotLikeOwnPost:
            return "不能点赞自己的帖子。"
        case .userMuted:
            return "账号已被社区禁言，暂时不能发帖或评论。"
        case .termsAcceptanceRequired:
            return "请先阅读并同意社区条款。"
        case .contentRejected:
            return "内容包含可能违规的信息，请修改后再发布。"
        case .invalidPoll:
            return "投票内容不完整，请检查问题和选项。"
        case .pollClosed:
            return "投票已截止。"
        case .edgeFunctionRejected(let message):
            return message
        }
    }
}

nonisolated enum LeafyFirstValueMap {
    static func build<Key: Hashable, Value>(_ pairs: [(Key, Value)]) -> [Key: Value] {
        var result: [Key: Value] = [:]
        for (key, value) in pairs where result[key] == nil {
            result[key] = value
        }
        return result
    }
}

actor CommunityService {
    static let shared = CommunityService()

    private nonisolated static let storageBucket = "community-images"
    private nonisolated static let publicImageCacheControl = "31536000"
    private var activeEnsureSessionTask: Task<Void, Error>?

    private init() {}

    func cancelInFlightWork() {
        activeEnsureSessionTask?.cancel()
        activeEnsureSessionTask = nil
    }

    func ensureAnonymousSession() async throws {
        if let activeEnsureSessionTask {
            do {
                try await activeEnsureSessionTask.value
            } catch {
                activeEnsureSessionTask.cancel()
                self.activeEnsureSessionTask = nil
                throw error
            }
            return
        }

        let task = Task.detached {
            try await Self.performEnsureAnonymousSession()
        }

        activeEnsureSessionTask = task
        defer { self.activeEnsureSessionTask = nil }
        do {
            try await task.value
        } catch {
            task.cancel()
            throw error
        }
    }

    func replaceAnonymousSession() async throws {
        activeEnsureSessionTask?.cancel()
        activeEnsureSessionTask = nil
        let client = try LeafySupabase.shared.requireClient()
        if client.auth.currentSession != nil {
            try await client.auth.signOut()
        }
        _ = try await client.auth.signInAnonymously()
    }

    private static func performEnsureAnonymousSession() async throws {
        try Task.checkCancellation()
        let client = try LeafySupabase.shared.requireClient()

        if client.auth.currentSession != nil {
            do {
                try Task.checkCancellation()
                _ = try await client.auth.session
                return
            } catch {
                try await client.auth.signOut()
            }
        }

        try Task.checkCancellation()
        _ = try await client.auth.signInAnonymously()
    }
}

// MARK: - Identity and Profile

extension CommunityService {
    func bootstrapCommunityUser(
        eduID: String,
        displayName: String?,
        campusID: String = ActiveCampusContext.descriptor.id.rawValue
    ) async throws -> CommunityProfile {
        let trimmedEduID = eduID.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmedEduID.isEmpty else {
            throw CommunityServiceError.schoolSessionMissing
        }
        let trimmedDisplayName = trimmedText(displayName) ?? trimmedEduID
        let normalizedCampusID = campusID.trimmingCharacters(in: .whitespacesAndNewlines).lowercased()

        let client = try LeafySupabase.shared.requireClient()
        let config = try LeafySupabase.shared.requireConfig()
        let session = try await client.auth.session
        client.functions.setAuth(token: session.accessToken)

        do {
            let response: CommunityBootstrapResponse = try await client.functions.invoke(
                config.bootstrapFunctionName,
                options: FunctionInvokeOptions(
                    headers: [
                        "Authorization": "Bearer \(session.accessToken)"
                    ],
                    body: CommunityBootstrapRequest(
                        eduID: trimmedEduID,
                        displayName: trimmedDisplayName,
                        campusID: normalizedCampusID.isEmpty ? CampusID.bjfu.rawValue : normalizedCampusID
                    )
                )
            )

            return response.profile
        } catch let error as FunctionsError {
            throw mapFunctionsError(error)
        }
    }

    func fetchCurrentProfile() async throws -> CommunityProfile? {
        let client = try LeafySupabase.shared.requireClient()
        guard let profileID = try await fetchCurrentProfileID(client: client) else {
            return nil
        }

        return try await fetchProfile(id: profileID, client: client)
    }

    func fetchCurrentProfile(userID: UUID) async throws -> CommunityProfile? {
        try await fetchProfile(id: userID)
    }

    func fetchPublicProfile(userID: UUID) async throws -> CommunityProfile? {
        try await fetchProfile(id: userID)
    }

    func searchCommunityCampuses(query: String, limit: Int = 20) async throws -> [CommunityCampusOption] {
        let client = try LeafySupabase.shared.requireClient()
        guard client.auth.currentUser != nil else {
            throw CommunityServiceError.missingAuthenticatedUser
        }

        return try await client
            .rpc(
                "community_campuses_v1",
                params: CommunityCampusSearchParams(search: query, limit: limit)
            )
            .execute()
            .value
    }

    func fetchCurrentCampusMembershipRequest() async throws -> CommunityCampusMembershipRequest? {
        let response = try await invokeCampusRequest(
            CommunityCampusRequestSubmitRequest(action: .current)
        )
        return response.request
    }

    func selectCommunityCampus(campusID: String) async throws -> CommunityProfile {
        let trimmedCampusID = campusID.trimmingCharacters(in: .whitespacesAndNewlines).lowercased()
        guard !trimmedCampusID.isEmpty else {
            throw CommunityServiceError.edgeFunctionRejected("请选择学校。")
        }

        let response = try await invokeCampusRequest(
            CommunityCampusRequestSubmitRequest(action: .selectExisting, campusID: trimmedCampusID)
        )
        if let profile = response.profile {
            return profile
        }
        if let profile = try await fetchCurrentProfile() {
            return profile
        }
        throw CommunityServiceError.missingAuthenticatedUser
    }

    func submitCommunitySchoolChangeRequest(campusID: String) async throws -> CommunityCampusMembershipRequest {
        let trimmedCampusID = campusID.trimmingCharacters(in: .whitespacesAndNewlines).lowercased()
        guard !trimmedCampusID.isEmpty else {
            throw CommunityServiceError.edgeFunctionRejected("请选择新的学校。")
        }

        let response = try await invokeCampusRequest(
            CommunityCampusRequestSubmitRequest(action: .requestChange, campusID: trimmedCampusID)
        )
        guard let request = response.request else {
            throw CommunityServiceError.edgeFunctionRejected("学校更换申请未创建，请稍后重试。")
        }
        return request
    }

    func submitCampusMembershipRequest(schoolName: String) async throws -> CommunityProfile {
        let trimmedSchoolName = schoolName.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmedSchoolName.isEmpty else {
            throw CommunityServiceError.edgeFunctionRejected("请填写学校名称。")
        }

        let response = try await invokeCampusRequest(
            CommunityCampusRequestSubmitRequest(action: .submitNewSchool, schoolName: trimmedSchoolName)
        )
        if let profile = response.profile {
            return profile
        }
        if let profile = try await fetchCurrentProfile() {
            return profile
        }
        throw CommunityServiceError.missingAuthenticatedUser
    }

    private func invokeCampusRequest(_ body: CommunityCampusRequestSubmitRequest) async throws -> CommunityCampusRequestResponse {
        let client = try LeafySupabase.shared.requireClient()
        let config = try LeafySupabase.shared.requireConfig()
        let session = try await client.auth.session
        client.functions.setAuth(token: session.accessToken)

        do {
            return try await client.functions.invoke(
                "campus-request",
                options: FunctionInvokeOptions(
                    headers: [
                        "Authorization": "Bearer \(session.accessToken)"
                    ],
                    region: config.edgeRegion,
                    body: body
                )
            )
        } catch let error as FunctionsError {
            throw mapFunctionsError(error)
        }
    }

    func fetchProfileStats(profileIDs: [UUID]) async throws -> [CommunityProfileStats] {
        let uniqueProfileIDs = Array(Set(profileIDs))
        guard !uniqueProfileIDs.isEmpty else { return [] }

        let client = try LeafySupabase.shared.requireClient()
        let response: CommunityProfileStatsResponse = try await client
            .rpc(
                "community_profile_stats_v1",
                params: CommunityProfileStatsRPCParams(profileIDs: uniqueProfileIDs)
            )
            .execute()
            .value

        return response.profiles
    }

    func updateProfile(
        input: CommunityProfileUpdateInput,
        avatar: CommunityImageUpload?,
        cover: CommunityImageUpload? = nil,
        resetCoverToDefault: Bool = false
    ) async throws -> CommunityProfile {
        let client = try LeafySupabase.shared.requireClient()
        guard client.auth.currentUser != nil else {
            throw CommunityServiceError.missingAuthenticatedUser
        }
        guard let existingProfile = try await fetchCurrentProfile() else {
            throw CommunityServiceError.missingAuthenticatedUser
        }

        let trimmedNickname = CommunityNickname.normalized(input.nickname)
        guard !trimmedNickname.isEmpty else {
            throw CommunityServiceError.profileCompletionRequired
        }

        let now = ISO8601DateFormatter().string(from: Date())
        let avatarPath = try await uploadProfileAvatarIfNeeded(avatar, userID: existingProfile.id) ?? existingProfile.avatarPath
        let coverPath: String?
        if resetCoverToDefault {
            coverPath = nil
        } else {
            coverPath = try await uploadProfileCoverIfNeeded(cover, userID: existingProfile.id) ?? existingProfile.coverPath
        }
        let update = CommunityProfileUpdate(
            nickname: trimmedNickname,
            avatarPath: avatarPath,
            coverPath: coverPath,
            bio: CommunityProfileBio.normalized(input.bio),
            major: trimmedText(input.major),
            grade: trimmedText(input.grade),
            profileEditedAt: now,
            isProfileComplete: true,
            showsEduVerificationBadge: input.showsEduVerificationBadge,
            updatedAt: now
        )

        do {
            _ = try await client
                .from("profiles")
                .update(update)
                .eq("id", value: existingProfile.id.uuidString)
                .execute()
        } catch where isMissingSchemaColumn(error, column: "profile_edited_at") ||
            isMissingSchemaColumn(error, column: "shows_edu_verification_badge") ||
            isMissingSchemaColumn(error, column: "cover_path") {
            let legacyUpdate = CommunityProfileLegacyUpdate(
                nickname: trimmedNickname,
                avatarPath: avatarPath,
                bio: CommunityProfileBio.normalized(input.bio),
                major: trimmedText(input.major),
                grade: trimmedText(input.grade),
                isProfileComplete: true,
                updatedAt: now
            )

            _ = try await client
                .from("profiles")
                .update(legacyUpdate)
                .eq("id", value: existingProfile.id.uuidString)
                .execute()
        }

        guard let profile = try await fetchProfile(id: existingProfile.id, client: client) else {
            throw CommunityServiceError.missingAuthenticatedUser
        }

        return profile
    }

    func requestEmailVerification(input: CommunityEmailBindingInput) async throws -> CommunityProfile {
        let client = try LeafySupabase.shared.requireClient()
        guard client.auth.currentUser != nil else {
            throw CommunityServiceError.missingAuthenticatedUser
        }
        guard let currentProfile = try await fetchCurrentProfile() else {
            throw CommunityServiceError.missingAuthenticatedUser
        }

        let email = CommunityEmailBinding.normalizedEmail(input.email)
        guard CommunityEmailBinding.isValidEmail(email) else {
            throw CommunityServiceError.invalidEmail
        }

        do {
            if CommunityEmailBinding.shouldResendVerification(
                pendingEmail: currentProfile.pendingBoundEmail,
                requestedEmail: email
            ) {
                try await client.auth.resend(
                    email: email,
                    type: .emailChange,
                    emailRedirectTo: LeafySupabase.authCallbackURL
                )
            } else {
                _ = try await client.auth.update(
                    user: UserAttributes(email: email),
                    redirectTo: LeafySupabase.authCallbackURL
                )
            }
        } catch {
            throw mapEmailAuthError(error)
        }

        let now = ISO8601DateFormatter().string(from: Date())
        let update = CommunityPendingEmailUpdate(
            pendingBoundEmail: email,
            emailVerificationSentAt: now,
            updatedAt: now
        )

        _ = try await client
            .from("profiles")
            .update(update)
            .eq("id", value: currentProfile.id.uuidString)
            .execute()

        guard let profile = try await fetchProfile(id: currentProfile.id, client: client) else {
            throw CommunityServiceError.missingAuthenticatedUser
        }

        return profile
    }

    func verifyEmailBinding(input: CommunityEmailVerificationInput) async throws -> CommunityProfile {
        let client = try LeafySupabase.shared.requireClient()
        guard client.auth.currentUser != nil else {
            throw CommunityServiceError.missingAuthenticatedUser
        }
        guard let currentProfile = try await fetchCurrentProfile() else {
            throw CommunityServiceError.missingAuthenticatedUser
        }

        let email = CommunityEmailBinding.normalizedEmail(input.email)
        guard CommunityEmailBinding.isValidEmail(email) else {
            throw CommunityServiceError.invalidEmail
        }
        guard CommunityEmailBinding.isCompleteVerificationCode(input.code) else {
            throw CommunityServiceError.edgeFunctionRejected("请输入邮件中的 8 位验证码。")
        }

        do {
            _ = try await client.auth.verifyOTP(
                email: email,
                token: input.code,
                type: .emailChange,
                redirectTo: LeafySupabase.authCallbackURL
            )
        } catch {
            throw mapEmailAuthError(error)
        }

        let update = CommunityVerifiedEmailUpdate(
            boundEmail: email,
            pendingBoundEmail: nil,
            emailVerificationSentAt: nil,
            updatedAt: ISO8601DateFormatter().string(from: Date())
        )

        do {
            _ = try await client
                .from("profiles")
                .update(update)
                .eq("id", value: currentProfile.id.uuidString)
                .execute()
        } catch {
            throw mapEmailAuthError(error)
        }

        guard let profile = try await fetchProfile(id: currentProfile.id, client: client) else {
            throw CommunityServiceError.missingAuthenticatedUser
        }

        return profile
    }

    func requestCommunityRecovery(email rawEmail: String) async throws {
        let email = CommunityEmailBinding.normalizedEmail(rawEmail)
        guard CommunityEmailBinding.isValidEmail(email) else {
            throw CommunityServiceError.invalidEmail
        }
        let client = try LeafySupabase.shared.requireClient()
        do {
            try await client.auth.signInWithOTP(
                email: email,
                redirectTo: LeafySupabase.authCallbackURL,
                shouldCreateUser: false
            )
        } catch {
            throw mapEmailAuthError(error)
        }
    }

    func verifyCommunityRecovery(email rawEmail: String, code: String) async throws -> CommunityProfile {
        let email = CommunityEmailBinding.normalizedEmail(rawEmail)
        guard CommunityEmailBinding.isValidEmail(email) else {
            throw CommunityServiceError.invalidEmail
        }
        guard CommunityEmailBinding.isCompleteVerificationCode(code) else {
            throw CommunityServiceError.edgeFunctionRejected("请输入邮件中的 8 位验证码。")
        }

        let client = try LeafySupabase.shared.requireClient()
        do {
            let response = try await client.auth.verifyOTP(
                email: email,
                token: code,
                type: .magiclink,
                redirectTo: LeafySupabase.authCallbackURL
            )
            guard response.session != nil else {
                throw CommunityServiceError.missingAuthenticatedUser
            }
        } catch let error as CommunityServiceError {
            throw error
        } catch {
            throw mapEmailAuthError(error)
        }

        guard let profile = try await fetchCurrentProfile() else {
            try? await client.auth.signOut()
            throw CommunityServiceError.edgeFunctionRejected("该邮箱没有可恢复的社区账号。")
        }
        return profile
    }

    func hasAcceptedCurrentTerms() async throws -> Bool {
        let client = try LeafySupabase.shared.requireClient()
        guard client.auth.currentUser != nil else {
            throw CommunityServiceError.missingAuthenticatedUser
        }
        guard let currentProfile = try await fetchCurrentProfile() else {
            throw CommunityServiceError.missingAuthenticatedUser
        }

        let records: [CommunityTermsAcceptanceRecord] = try await client
            .from("community_terms_acceptances")
            .select()
            .eq("user_id", value: currentProfile.id.uuidString)
            .eq("terms_version", value: CommunityTerms.currentVersion)
            .limit(1)
            .execute()
            .value

        return !records.isEmpty
    }

    func acceptCurrentTerms() async throws {
        let client = try LeafySupabase.shared.requireClient()
        guard client.auth.currentUser != nil else {
            throw CommunityServiceError.missingAuthenticatedUser
        }

        _ = try await client
            .rpc(
                "accept_community_terms",
                params: CommunityTermsAcceptanceRPCParams(termsVersion: CommunityTerms.currentVersion)
            )
            .execute()
    }

    func revokeCurrentTerms() async throws {
        let client = try LeafySupabase.shared.requireClient()
        guard client.auth.currentUser != nil else {
            throw CommunityServiceError.missingAuthenticatedUser
        }

        _ = try await client
            .rpc(
                "revoke_community_terms",
                params: CommunityTermsAcceptanceRPCParams(termsVersion: CommunityTerms.currentVersion)
            )
            .execute()
    }
}

// MARK: - Feed and Posts

extension CommunityService {
    nonisolated func fetchPosts(query: CommunityFeedQuery = .default) async throws -> [CommunityPost] {
        let client = try LeafySupabase.shared.requireClient()
        let config = try LeafySupabase.shared.requireConfig()
        let session = try await client.auth.session
        let feedCapability = await backendFeatureSupport(.communityFeed)

        if feedCapability == false {
            CommunityDiagnostics.log.info("Community feed capability unavailable, using legacy PostgREST feed")
            return try await fetchPostsLegacy(query: query)
        }

        if let apiBaseURL = config.communityAPIBaseURL {
            do {
                let response = try await fetchPostsFromCommunityAPI(
                    baseURL: apiBaseURL,
                    functionName: config.feedFunctionName,
                    query: query,
                    accessToken: session.accessToken
                )
                return response.posts.map { postWithPublicStorageURLs($0, config: config) }
            } catch {
                if feedCapability == nil && shouldFallbackToLegacyCommunityFeed(error) {
                    CommunityDiagnostics.log.info("Community feed API unavailable, falling back to legacy PostgREST feed")
                    return try await fetchPostsLegacy(query: query)
                }
                throw error
            }
        }

        client.functions.setAuth(token: session.accessToken)

        do {
            let response: CommunityFeedResponse = try await client.functions.invoke(
                config.feedFunctionName,
                options: FunctionInvokeOptions(
                    method: .get,
                    query: communityFeedQueryItems(query),
                    headers: [
                        "Authorization": "Bearer \(session.accessToken)"
                    ],
                    region: config.edgeRegion
                )
            )

            return response.posts.map { postWithPublicStorageURLs($0, config: config) }
        } catch let error as FunctionsError {
            if feedCapability == nil && shouldFallbackToLegacyCommunityFeed(error) {
                CommunityDiagnostics.log.info("Community feed function unavailable, falling back to legacy PostgREST feed")
                return try await fetchPostsLegacy(query: query)
            }
            throw mapFunctionsError(error)
        }
    }

    nonisolated func fetchPostsLegacy(query: CommunityFeedQuery = .default) async throws -> [CommunityPost] {
        CommunityDiagnostics.log.info("CommunityService.fetchPosts legacy begin")
        let client = try LeafySupabase.shared.requireClient()
        if query.mode.isHot {
            return try await fetchHotPostsLegacy(query: query, client: client)
        }

        let activePins = try await fetchActivePostPins(query: query, client: client)
        let pinnedPostIDs = activePins.map(\.postID)
        let campusID = ActiveCampusContext.descriptor.id.rawValue
        let pinnedRecords: [CommunityPostRecord]
        if pinnedPostIDs.isEmpty {
            pinnedRecords = []
        } else {
            pinnedRecords = try await client
                .from("posts")
                .select()
                .in("id", values: pinnedPostIDs.map(\.uuidString))
                .eq("campus_id", value: campusID)
                .eq("status", value: "published")
                .execute()
                .value
        }

        let fetchLimit = query.hasSearch ? min(query.limit * 4, 100) : query.limit
        var latestQuery = client
            .from("posts")
            .select()
            .eq("campus_id", value: campusID)
            .eq("status", value: "published")

        if let category = query.category {
            latestQuery = latestQuery.eq("category", value: category)
        }

        let latestRecords: [CommunityPostRecord] = try await latestQuery
            .order("created_at", ascending: false)
            .limit(fetchLimit)
            .execute()
            .value
        let records = uniquePostRecords(pinnedRecords + latestRecords)

        CommunityDiagnostics.log.info("CommunityService.fetchPosts received \(records.count) records")
        let viewerID = try? await fetchCurrentProfileID(client: client)
        let posts = try await hydratePosts(
            from: records,
            client: client,
            viewerID: viewerID,
            pins: activePins
        )
        let visiblePosts = try await filterBlockedPosts(posts, viewerID: viewerID, client: client)
        let sortedPosts = CommunityFeedOrdering.ordered(visiblePosts, matching: query)
        CommunityDiagnostics.log.info("CommunityService.fetchPosts hydrated \(sortedPosts.count) posts")
        return Array(sortedPosts.prefix(query.limit))
    }

    private nonisolated func fetchHotPostsLegacy(
        query: CommunityFeedQuery,
        client: SupabaseClient
    ) async throws -> [CommunityPost] {
        let cutoff = Calendar(identifier: .gregorian)
            .date(byAdding: .day, value: -query.hotDays, to: Date()) ?? Date()
        let cutoffText = ISO8601DateFormatter().string(from: cutoff)
        let fetchLimit = max(query.limit * 8, 80)
        let records: [CommunityPostRecord] = try await client
            .from("posts")
            .select()
            .eq("campus_id", value: ActiveCampusContext.descriptor.id.rawValue)
            .eq("status", value: "published")
            .gte("created_at", value: cutoffText)
            .order("created_at", ascending: false)
            .limit(fetchLimit)
            .execute()
            .value

        let viewerID = try? await fetchCurrentProfileID(client: client)
        let posts = try await hydratePosts(
            from: records,
            client: client,
            viewerID: viewerID
        )
        let visiblePosts = try await filterBlockedPosts(posts, viewerID: viewerID, client: client)
        let sortedPosts = CommunityFeedOrdering.ordered(visiblePosts, matching: query)
        return Array(sortedPosts.prefix(query.limit))
    }

    func fetchPosts(authoredBy userID: UUID, limit: Int = 20) async throws -> [CommunityPost] {
        let client = try LeafySupabase.shared.requireClient()
        let records: [CommunityPostRecord] = try await client
            .from("posts")
            .select()
            .eq("author_id", value: userID.uuidString)
            .in("status", values: ["published", "pending_review", "hidden"])
            .order("created_at", ascending: false)
            .limit(limit)
            .execute()
            .value

        let viewerID = try? await fetchCurrentProfileID(client: client)
        let posts = try await hydratePosts(
            from: records,
            client: client,
            viewerID: viewerID
        )
        return try await filterBlockedPosts(posts, viewerID: viewerID, client: client)
    }

    func fetchPublicPosts(authoredBy userID: UUID, limit: Int = 20) async throws -> [CommunityPost] {
        let client = try LeafySupabase.shared.requireClient()
        let records: [CommunityPostRecord] = try await client
            .from("posts")
            .select()
            .eq("campus_id", value: ActiveCampusContext.descriptor.id.rawValue)
            .eq("author_id", value: userID.uuidString)
            .eq("status", value: "published")
            .eq("is_anonymous", value: false)
            .order("created_at", ascending: false)
            .limit(limit)
            .execute()
            .value

        let viewerID = try? await fetchCurrentProfileID(client: client)
        let posts = try await hydratePosts(
            from: records,
            client: client,
            viewerID: viewerID
        )
        return try await filterBlockedPosts(posts, viewerID: viewerID, client: client)
    }

    func fetchLikedPosts(by userID: UUID, limit: Int = 20) async throws -> [CommunityPost] {
        let client = try LeafySupabase.shared.requireClient()
        let likes: [CommunityPostLikeRecord] = try await client
            .from("post_likes")
            .select()
            .eq("user_id", value: userID.uuidString)
            .order("created_at", ascending: false)
            .limit(limit)
            .execute()
            .value

        let postIDs = likes.map(\.postID)
        guard !postIDs.isEmpty else { return [] }

        let records: [CommunityPostRecord] = try await client
            .from("posts")
            .select()
            .in("id", values: postIDs.map(\.uuidString))
            .eq("status", value: "published")
            .execute()
            .value

        let orderMap = LeafyFirstValueMap.build(postIDs.enumerated().map { ($0.element, $0.offset) })
        let viewerID = try? await fetchCurrentProfileID(client: client)
        let posts = try await hydratePosts(
            from: records,
            client: client,
            viewerID: viewerID
        )
            .sorted { (orderMap[$0.id] ?? Int.max) < (orderMap[$1.id] ?? Int.max) }
        return try await filterBlockedPosts(posts, viewerID: viewerID, client: client)
    }

    func fetchFavoritedPosts(by userID: UUID, limit: Int = 20) async throws -> [CommunityPost] {
        let client = try LeafySupabase.shared.requireClient()
        let favorites: [CommunityPostFavoriteRecord] = try await client
            .from("post_favorites")
            .select()
            .eq("user_id", value: userID.uuidString)
            .order("created_at", ascending: false)
            .limit(limit)
            .execute()
            .value

        let postIDs = favorites.map(\.postID)
        guard !postIDs.isEmpty else { return [] }

        let records: [CommunityPostRecord] = try await client
            .from("posts")
            .select()
            .in("id", values: postIDs.map(\.uuidString))
            .eq("status", value: "published")
            .execute()
            .value

        let orderMap = LeafyFirstValueMap.build(postIDs.enumerated().map { ($0.element, $0.offset) })
        let viewerID = try? await fetchCurrentProfileID(client: client)
        let posts = try await hydratePosts(
            from: records,
            client: client,
            viewerID: viewerID
        )
            .sorted { (orderMap[$0.id] ?? Int.max) < (orderMap[$1.id] ?? Int.max) }
        return try await filterBlockedPosts(posts, viewerID: viewerID, client: client)
    }

    func createPost(input: CreatePostInput, images: [CommunityImageUpload]) async throws -> CommunityPost {
        guard images.count <= CommunityImageUpload.postImageLimit else {
            throw CommunityServiceError.imageLimitExceeded
        }
        let title = input.title.trimmingCharacters(in: .whitespacesAndNewlines)
        let body = input.body.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !title.isEmpty, title.count <= 80 else {
            throw CommunityServiceError.edgeFunctionRejected("标题需为 1–80 个字符。")
        }
        guard !body.isEmpty, body.count <= 10_000 else {
            throw CommunityServiceError.edgeFunctionRejected("正文需为 1–10,000 个字符。")
        }

        let client = try LeafySupabase.shared.requireClient()
        guard client.auth.currentUser != nil else {
            throw CommunityServiceError.missingAuthenticatedUser
        }
        let actorProfile = try await requireCompletedCurrentProfile()
        try await requireAcceptedCurrentTerms()
        try await enforcePostRateLimit(authorID: actorProfile.id, client: client)

        let postID = UUID()
        let category = CommunityPostCategory.normalized(input.category)

        let createdRecord: CommunityPostRecord
        do {
            createdRecord = try await client
                .rpc(
                    "create_community_post_v2",
                    params: CommunityCreatePostRPCParams(
                        id: postID,
                        title: title,
                        body: body,
                        category: category,
                        isAnonymous: input.isAnonymous,
                        hasImages: !images.isEmpty
                    )
                )
                .execute()
                .value
        } catch {
            throw mapCreatePostError(error)
        }

        if !images.isEmpty {
            do {
                try await uploadPostImages(images, authorID: actorProfile.id, postID: postID)
                try await publishPostAfterImageUpload(postID: postID)
            } catch {
                try? await markPostDeleted(postID: postID)
                throw CommunityServiceError.edgeFunctionRejected("图片发布失败：\(error.localizedDescription)")
            }
        }

        let fallbackStatus = images.isEmpty ? createdRecord.status : "published"
        return try await fetchPost(postID: postID) ?? CommunityPost(
            id: createdRecord.id,
            authorID: createdRecord.authorID,
            title: createdRecord.title,
            body: createdRecord.body,
            category: createdRecord.category,
            isAnonymous: createdRecord.isAnonymous,
            commentCount: createdRecord.commentCount,
            likeCount: 0,
            status: fallbackStatus,
            createdAt: createdRecord.createdAt,
            updatedAt: createdRecord.updatedAt,
            viewerHasLiked: false,
            viewerHasFavorited: false,
            author: actorProfile,
            images: []
        )
    }
}

// MARK: - Polls

extension CommunityService {
    func fetchPolls(limit: Int = 30) async throws -> [CommunityPoll] {
        let client = try LeafySupabase.shared.requireClient()
        guard client.auth.currentUser != nil else {
            throw CommunityServiceError.missingAuthenticatedUser
        }

        let safeLimit = max(1, min(limit, 50))
        let records: [CommunityPollRecord] = try await client
            .from("community_polls")
            .select()
            .eq("campus_id", value: ActiveCampusContext.descriptor.id.rawValue)
            .neq("status", value: "deleted")
            .order("created_at", ascending: false)
            .limit(safeLimit)
            .execute()
            .value

        let viewerID = try? await fetchCurrentProfileID(client: client)
        return try await hydratePolls(from: records, client: client, viewerID: viewerID)
    }

    func fetchMyAuthoredPolls(limit: Int = 30) async throws -> [CommunityPoll] {
        let client = try LeafySupabase.shared.requireClient()
        guard client.auth.currentUser != nil else {
            throw CommunityServiceError.missingAuthenticatedUser
        }

        do {
            let records: [CommunityPoll] = try await client
                .rpc("my_authored_community_polls_v1", params: CommunityPollListRPCParams(limit: limit))
                .execute()
                .value
            return try records.map { try pollWithPublicAvatarURL($0) }
        } catch {
            throw mapCommunityMutationError(error, fallback: "我的投票加载失败")
        }
    }

    func fetchMyVotedPolls(limit: Int = 30) async throws -> [CommunityPoll] {
        let client = try LeafySupabase.shared.requireClient()
        guard client.auth.currentUser != nil else {
            throw CommunityServiceError.missingAuthenticatedUser
        }

        do {
            let records: [CommunityPoll] = try await client
                .rpc("my_voted_community_polls_v1", params: CommunityPollListRPCParams(limit: limit))
                .execute()
                .value
            return try records.map { try pollWithPublicAvatarURL($0) }
        } catch {
            throw mapCommunityMutationError(error, fallback: "我的投票加载失败")
        }
    }

    func createPoll(input: CreatePollInput) async throws -> CommunityPoll {
        if input.validationError != nil {
            throw CommunityServiceError.invalidPoll
        }

        let client = try LeafySupabase.shared.requireClient()
        guard client.auth.currentUser != nil else {
            throw CommunityServiceError.missingAuthenticatedUser
        }
        _ = try await requireCompletedCurrentProfile()
        try await requireAcceptedCurrentTerms()

        let record: CommunityPoll
        do {
            record = try await client
                .rpc(
                    "create_community_poll_v1",
                    params: CommunityCreatePollRPCParams(input: input)
                )
                .execute()
                .value
        } catch {
            throw mapCommunityMutationError(error, fallback: "投票发布失败")
        }

        return try pollWithPublicAvatarURL(record)
    }

    func votePoll(pollID: UUID, optionID: UUID) async throws -> CommunityPoll {
        let client = try LeafySupabase.shared.requireClient()
        guard client.auth.currentUser != nil else {
            throw CommunityServiceError.missingAuthenticatedUser
        }

        let record: CommunityPoll
        do {
            record = try await client
                .rpc(
                    "vote_community_poll_v1",
                    params: CommunityVotePollRPCParams(pollID: pollID, optionID: optionID)
                )
                .execute()
                .value
        } catch {
            throw mapCommunityMutationError(error, fallback: "投票失败")
        }

        return try pollWithPublicAvatarURL(record)
    }

    func requestPollDeletion(pollID: UUID, reason: String?) async throws -> CommunityPoll {
        let client = try LeafySupabase.shared.requireClient()
        guard client.auth.currentUser != nil else {
            throw CommunityServiceError.missingAuthenticatedUser
        }

        do {
            let record: CommunityPoll = try await client
                .rpc(
                    "request_delete_community_poll_v1",
                    params: CommunityRequestPollDeletionRPCParams(pollID: pollID, reason: reason)
                )
                .execute()
                .value
            return try pollWithPublicAvatarURL(record)
        } catch {
            throw mapCommunityMutationError(error, fallback: "删除申请提交失败")
        }
    }

    func deleteOwnPoll(pollID: UUID) async throws {
        _ = try await requestPollDeletion(pollID: pollID, reason: nil)
    }
}

// MARK: - Post Detail and Moderation

extension CommunityService {
    nonisolated func fetchPost(postID: UUID) async throws -> CommunityPost? {
        let client = try LeafySupabase.shared.requireClient()
        let records: [CommunityPostRecord] = try await client
            .from("posts")
            .select()
            .eq("id", value: postID.uuidString)
            .eq("status", value: "published")
            .limit(1)
            .execute()
            .value

        let viewerID = try? await fetchCurrentProfileID(client: client)
        let pins = try await fetchActivePostPins(postIDs: records.map(\.id), client: client)
        let posts = try await hydratePosts(
            from: records,
            client: client,
            viewerID: viewerID,
            pins: pins
        )
        let config = try LeafySupabase.shared.requireConfig()
        return try await filterBlockedPosts(posts, viewerID: viewerID, client: client)
            .first
            .map { postWithPublicStorageURLs($0, config: config) }
    }

    nonisolated func fetchComments(postID: UUID) async throws -> [CommunityComment] {
        let client = try LeafySupabase.shared.requireClient()
        let records: [CommunityCommentRecord] = try await client
            .from("comments")
            .select()
            .eq("post_id", value: postID.uuidString)
            .eq("status", value: "published")
            .order("created_at", ascending: true)
            .execute()
            .value

        let viewerID = try? await fetchCurrentProfileID(client: client)
        let comments = try await hydrateComments(from: records, client: client)
        return try await filterBlockedComments(comments, viewerID: viewerID, client: client)
    }

    func fetchMyComments(limit: Int = 80) async throws -> [CommunityComment] {
        let client = try LeafySupabase.shared.requireClient()
        guard client.auth.currentUser != nil else {
            throw CommunityServiceError.missingAuthenticatedUser
        }
        guard let currentProfile = try await fetchCurrentProfile() else {
            throw CommunityServiceError.missingAuthenticatedUser
        }

        let records: [CommunityCommentRecord] = try await client
            .from("comments")
            .select()
            .eq("author_id", value: currentProfile.id.uuidString)
            .eq("status", value: "published")
            .order("created_at", ascending: false)
            .limit(max(1, min(limit, 100)))
            .execute()
            .value

        let viewerID = try? await fetchCurrentProfileID(client: client)
        let comments = try await hydrateComments(from: records, client: client)
        return try await filterBlockedComments(comments, viewerID: viewerID, client: client)
    }

    func createComment(postID: UUID, body: String) async throws -> CommunityComment {
        let normalizedBody = body.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !normalizedBody.isEmpty, normalizedBody.count <= 2_000 else {
            throw CommunityServiceError.edgeFunctionRejected("评论需为 1–2,000 个字符。")
        }
        let client = try LeafySupabase.shared.requireClient()
        guard client.auth.currentUser != nil else {
            throw CommunityServiceError.missingAuthenticatedUser
        }
        let actorProfile = try await requireCompletedCurrentProfile()
        try await requireAcceptedCurrentTerms()

        let createdRecord: CommunityCommentRecord
        do {
            createdRecord = try await client
                .rpc(
                    "create_community_comment_v1",
                    params: CommunityCreateCommentRPCParams(
                        id: UUID(),
                        postID: postID,
                        body: normalizedBody,
                        isAnonymous: false
                    )
                )
                .execute()
                .value
        } catch {
            throw mapCommunityMutationError(error, fallback: "评论发布失败")
        }

        if let post = try await fetchPost(postID: postID), post.authorID != actorProfile.id {
            do {
                try await createNotification(
                    recipientID: post.authorID,
                    actorID: actorProfile.id,
                    postID: postID,
                    commentID: createdRecord.id,
                    type: .comment,
                    title: "\(actorProfile.limitedResolvedDisplayName) 回复了你的帖子",
                    body: String((trimmedText(body) ?? "").prefix(120))
                )
            } catch {
                CommunityDiagnostics.log.error("Create comment notification failed: \(error.localizedDescription, privacy: .public)")
            }
        }

        return CommunityComment(
            id: createdRecord.id,
            postID: createdRecord.postID,
            authorID: createdRecord.authorID,
            body: createdRecord.body,
            isAnonymous: createdRecord.isAnonymous,
            status: createdRecord.status,
            createdAt: createdRecord.createdAt,
            updatedAt: createdRecord.updatedAt,
            author: actorProfile
        )
    }

    func togglePostLike(postID: UUID) async throws -> CommunityPost {
        let client = try LeafySupabase.shared.requireClient()
        guard client.auth.currentUser != nil else {
            throw CommunityServiceError.missingAuthenticatedUser
        }
        let rpcCapability = await backendRPCSupport("toggle_post_like_v1")

        if rpcCapability == false {
            CommunityDiagnostics.log.info("toggle_post_like_v1 capability unavailable, using legacy like mutation")
            return try await togglePostLikeLegacy(postID: postID)
        }

        let record: CommunityPost
        do {
            record = try await client
                .rpc(
                    "toggle_post_like_v1",
                    params: CommunityPostIDRPCParams(postID: postID)
                )
                .execute()
                .value
        } catch {
            if rpcCapability == nil && shouldFallbackToLegacyCommunityMutation(error) {
                CommunityDiagnostics.log.info("toggle_post_like_v1 unavailable, falling back to legacy like mutation")
                return try await togglePostLikeLegacy(postID: postID)
            }
            throw mapCommunityMutationError(error, fallback: "点赞失败")
        }

        let config = try LeafySupabase.shared.requireConfig()
        return postWithPublicStorageURLs(record, config: config)
    }

    func togglePostFavorite(postID: UUID) async throws -> CommunityPost {
        let client = try LeafySupabase.shared.requireClient()
        guard client.auth.currentUser != nil else {
            throw CommunityServiceError.missingAuthenticatedUser
        }
        let rpcCapability = await backendRPCSupport("toggle_post_favorite_v1")

        if rpcCapability == false {
            CommunityDiagnostics.log.info("toggle_post_favorite_v1 capability unavailable, using legacy favorite mutation")
            return try await togglePostFavoriteLegacy(postID: postID)
        }

        let record: CommunityPost
        do {
            record = try await client
                .rpc(
                    "toggle_post_favorite_v1",
                    params: CommunityPostIDRPCParams(postID: postID)
                )
                .execute()
                .value
        } catch {
            if rpcCapability == nil && shouldFallbackToLegacyCommunityMutation(error) {
                CommunityDiagnostics.log.info("toggle_post_favorite_v1 unavailable, falling back to legacy favorite mutation")
                return try await togglePostFavoriteLegacy(postID: postID)
            }
            throw mapCommunityMutationError(error, fallback: "收藏失败")
        }

        let config = try LeafySupabase.shared.requireConfig()
        return postWithPublicStorageURLs(record, config: config)
    }

    private func togglePostLikeLegacy(postID: UUID) async throws -> CommunityPost {
        let client = try LeafySupabase.shared.requireClient()
        guard client.auth.currentUser != nil else {
            throw CommunityServiceError.missingAuthenticatedUser
        }
        let actorProfile = try await requireCompletedCurrentProfile()
        try await requireAcceptedCurrentTerms()

        guard let targetPost = try await fetchPost(postID: postID) else {
            throw CommunityServiceError.edgeFunctionRejected("帖子已不存在。")
        }

        guard targetPost.authorID != actorProfile.id else {
            throw CommunityServiceError.cannotLikeOwnPost
        }

        let existingLikes: [CommunityPostLikeRecord] = try await client
            .from("post_likes")
            .select()
            .eq("post_id", value: postID.uuidString)
            .eq("user_id", value: actorProfile.id.uuidString)
            .limit(1)
            .execute()
            .value

        let didCreateLike = existingLikes.isEmpty

        if didCreateLike {
            let insert = CommunityPostLikeInsert(
                postID: postID,
                userID: actorProfile.id,
                createdAt: ISO8601DateFormatter().string(from: Date())
            )
            _ = try await client
                .from("post_likes")
                .insert(insert)
                .execute()
        } else {
            _ = try await client
                .from("post_likes")
                .delete()
                .eq("post_id", value: postID.uuidString)
                .eq("user_id", value: actorProfile.id.uuidString)
                .execute()
        }

        guard let updatedPost = try await fetchPost(postID: postID) else {
            throw CommunityServiceError.edgeFunctionRejected("帖子已不存在。")
        }

        if didCreateLike {
            do {
                try await createNotification(
                    recipientID: updatedPost.authorID,
                    actorID: actorProfile.id,
                    postID: postID,
                    commentID: nil,
                    type: .like,
                    title: "\(actorProfile.limitedResolvedDisplayName) 点赞了你的帖子",
                    body: updatedPost.title
                )
            } catch {
                CommunityDiagnostics.log.error("Create legacy like notification failed: \(error.localizedDescription, privacy: .public)")
            }
        }

        return updatedPost
    }

    private func togglePostFavoriteLegacy(postID: UUID) async throws -> CommunityPost {
        let client = try LeafySupabase.shared.requireClient()
        guard client.auth.currentUser != nil else {
            throw CommunityServiceError.missingAuthenticatedUser
        }
        let actorProfile = try await requireCompletedCurrentProfile()
        try await requireAcceptedCurrentTerms()

        guard let targetPost = try await fetchPost(postID: postID) else {
            throw CommunityServiceError.edgeFunctionRejected("帖子已不存在。")
        }

        let existingFavorites: [CommunityPostFavoriteRecord] = try await client
            .from("post_favorites")
            .select()
            .eq("post_id", value: postID.uuidString)
            .eq("user_id", value: actorProfile.id.uuidString)
            .limit(1)
            .execute()
            .value

        if existingFavorites.isEmpty {
            let insert = CommunityPostFavoriteInsert(
                postID: postID,
                userID: actorProfile.id,
                createdAt: ISO8601DateFormatter().string(from: Date())
            )
            _ = try await client
                .from("post_favorites")
                .insert(insert)
                .execute()
        } else {
            _ = try await client
                .from("post_favorites")
                .delete()
                .eq("post_id", value: postID.uuidString)
                .eq("user_id", value: actorProfile.id.uuidString)
                .execute()
        }

        return try await fetchPost(postID: postID) ?? targetPost
    }

    func deleteComment(commentID: UUID) async throws {
        let client = try LeafySupabase.shared.requireClient()
        guard client.auth.currentUser != nil else {
            throw CommunityServiceError.missingAuthenticatedUser
        }

        _ = try await client
            .rpc(
                "soft_delete_own_comment",
                params: CommunityCommentSoftDeleteRPCParams(targetCommentID: commentID)
            )
            .execute()
    }

    func deletePost(postID: UUID) async throws {
        let client = try LeafySupabase.shared.requireClient()
        guard client.auth.currentUser != nil else {
            throw CommunityServiceError.missingAuthenticatedUser
        }

        try await markPostDeleted(postID: postID)
    }

    func reportPost(postID: UUID, reason: String, detail: String? = nil) async throws {
        try await reportCommunityContent(
            targetType: .post,
            postID: postID,
            commentID: nil,
            reportedUserID: nil,
            reason: reason,
            detail: detail
        )
    }

    func reportComment(commentID: UUID, reason: String, detail: String? = nil) async throws {
        try await reportCommunityContent(
            targetType: .comment,
            postID: nil,
            commentID: commentID,
            reportedUserID: nil,
            reason: reason,
            detail: detail
        )
    }

    func reportUser(userID: UUID, reason: String, detail: String? = nil) async throws {
        try await reportCommunityContent(
            targetType: .user,
            postID: nil,
            commentID: nil,
            reportedUserID: userID,
            reason: reason,
            detail: detail
        )
    }

    func blockUser(userID: UUID, reason: String? = nil) async throws {
        let client = try LeafySupabase.shared.requireClient()
        guard client.auth.currentUser != nil else {
            throw CommunityServiceError.missingAuthenticatedUser
        }

        _ = try await client
            .rpc(
                "block_community_user",
                params: CommunityBlockUserRPCParams(blockedID: userID, reason: reason)
            )
            .execute()
    }

    func unblockUser(userID: UUID) async throws {
        let client = try LeafySupabase.shared.requireClient()
        guard client.auth.currentUser != nil else {
            throw CommunityServiceError.missingAuthenticatedUser
        }

        _ = try await client
            .rpc("unblock_community_user", params: CommunityUnblockUserRPCParams(blockedID: userID))
            .execute()
    }
}

// MARK: - Notifications

extension CommunityService {
    func fetchNotifications(limit: Int = 50) async throws -> [CommunityNotification] {
        let client = try LeafySupabase.shared.requireClient()
        guard client.auth.currentUser != nil else {
            throw CommunityServiceError.missingAuthenticatedUser
        }
        guard let currentProfile = try await fetchCurrentProfile() else {
            throw CommunityServiceError.missingAuthenticatedUser
        }

        let records: [CommunityNotificationRecord] = try await client
            .from("community_notifications")
            .select()
            .eq("recipient_id", value: currentProfile.id.uuidString)
            .order("created_at", ascending: false)
            .limit(limit)
            .execute()
            .value

        let visibleRecords = records.filter { $0.dismissedAt == nil }
        let blockedIDs = try await fetchBlockedUserIDs(viewerID: currentProfile.id, client: client)
        return try await hydrateNotifications(from: visibleRecords.filter { record in
            guard let actorID = record.actorID else { return true }
            return !blockedIDs.contains(actorID)
        })
    }

    func fetchNotificationFeed(limit: Int = 50) async throws -> [NotificationFeedItem] {
        let settings = try await fetchNotificationSettings()
        guard !settings.mutedAll else { return [] }

        let communityNotifications = try await fetchNotifications(limit: limit)
        let siteAnnouncements = try await fetchSiteAnnouncements(limit: limit)

        return Array(
            (communityNotifications.map(NotificationFeedItem.community) + siteAnnouncements.map(NotificationFeedItem.announcement))
                .sorted { $0.sortDate > $1.sortDate }
                .prefix(limit)
        )
    }

    func fetchSiteAnnouncements(limit: Int = 50) async throws -> [SiteAnnouncement] {
        let client = try LeafySupabase.shared.requireClient()
        guard let currentUser = client.auth.currentUser else {
            throw CommunityServiceError.missingAuthenticatedUser
        }

        let records: [SiteAnnouncementRecord] = try await client
            .from("site_announcements")
            .select()
            .eq("status", value: "published")
            .order("published_at", ascending: false)
            .limit(limit)
            .execute()
            .value

        let activeRecords = records.filter(isSiteAnnouncementActive)
        let reads = try await fetchSiteAnnouncementReads(
            announcementIDs: activeRecords.map(\.id),
            userID: currentUser.id
        )
        let visibleReads = reads.filter { $0.dismissedAt == nil }
        let dismissedIDs = Set(reads.filter { $0.dismissedAt != nil }.map(\.announcementID))
        let readMap = LeafyFirstValueMap.build(visibleReads.map { ($0.announcementID, $0.readAt) })

        return activeRecords.filter { !dismissedIDs.contains($0.id) }.map { record in
            SiteAnnouncement(
                id: record.id,
                title: record.title,
                body: record.body,
                level: record.level,
                status: record.status,
                publishedAt: record.publishedAt,
                expiresAt: record.expiresAt,
                createdBy: record.createdBy,
                createdAt: record.createdAt,
                readAt: readMap[record.id]
            )
        }
    }

    func fetchUnreadNotificationCount(limit: Int = 100) async throws -> Int {
        let settings = try await fetchNotificationSettings()
        guard !settings.mutedAll else { return 0 }

        let client = try LeafySupabase.shared.requireClient()
        guard client.auth.currentUser != nil else {
            throw CommunityServiceError.missingAuthenticatedUser
        }
        guard let currentProfile = try await fetchCurrentProfile() else {
            throw CommunityServiceError.missingAuthenticatedUser
        }

        let records: [CommunityNotificationRecord] = try await client
            .from("community_notifications")
            .select()
            .eq("recipient_id", value: currentProfile.id.uuidString)
            .eq("is_read", value: false)
            .limit(limit)
            .execute()
            .value

        let unreadAnnouncementCount = try await fetchSiteAnnouncements(limit: limit)
            .filter { !$0.isRead }
            .count

        let blockedIDs = try await fetchBlockedUserIDs(viewerID: currentProfile.id, client: client)
        let visibleUnreadCount = records.filter { record in
            guard record.dismissedAt == nil else { return false }
            guard let actorID = record.actorID else { return true }
            return !blockedIDs.contains(actorID)
        }.count

        return visibleUnreadCount + unreadAnnouncementCount
    }

    func fetchNotificationSettings() async throws -> CommunityNotificationSettings {
        let client = try LeafySupabase.shared.requireClient()
        guard client.auth.currentUser != nil else {
            throw CommunityServiceError.missingAuthenticatedUser
        }
        guard let currentProfile = try await fetchCurrentProfile() else {
            throw CommunityServiceError.missingAuthenticatedUser
        }

        let records: [CommunityNotificationSettingsRecord] = try await client
            .from("community_notification_settings")
            .select()
            .eq("user_id", value: currentProfile.id.uuidString)
            .limit(1)
            .execute()
            .value

        guard let record = records.first else {
            return CommunityNotificationSettings(userID: currentProfile.id, mutedAll: false, updatedAt: nil)
        }

        return CommunityNotificationSettings(
            userID: record.userID,
            mutedAll: record.mutedAll,
            updatedAt: record.updatedAt
        )
    }

    func updateNotificationSettings(mutedAll: Bool) async throws -> CommunityNotificationSettings {
        let client = try LeafySupabase.shared.requireClient()
        guard client.auth.currentUser != nil else {
            throw CommunityServiceError.missingAuthenticatedUser
        }
        guard let currentProfile = try await fetchCurrentProfile() else {
            throw CommunityServiceError.missingAuthenticatedUser
        }

        let update = CommunityNotificationSettingsUpsert(
            userID: currentProfile.id,
            mutedAll: mutedAll,
            updatedAt: ISO8601DateFormatter().string(from: Date())
        )

        let record: CommunityNotificationSettingsRecord = try await client
            .from("community_notification_settings")
            .upsert(update, onConflict: "user_id")
            .select()
            .single()
            .execute()
            .value

        return CommunityNotificationSettings(
            userID: record.userID,
            mutedAll: record.mutedAll,
            updatedAt: record.updatedAt
        )
    }

    func markNotificationRead(notificationID: UUID) async throws {
        let client = try LeafySupabase.shared.requireClient()
        let update = CommunityNotificationReadUpdate(isRead: true)

        _ = try await client
            .from("community_notifications")
            .update(update)
            .eq("id", value: notificationID.uuidString)
            .execute()
    }

    func markNotificationFeedRead(announcementLimit: Int = 500) async throws {
        let client = try LeafySupabase.shared.requireClient()
        guard client.auth.currentUser != nil else {
            throw CommunityServiceError.missingAuthenticatedUser
        }
        guard let currentProfile = try await fetchCurrentProfile() else {
            throw CommunityServiceError.missingAuthenticatedUser
        }

        let now = ISO8601DateFormatter().string(from: Date())
        let communityUpdate = CommunityNotificationReadUpdate(isRead: true)

        _ = try await client
            .from("community_notifications")
            .update(communityUpdate)
            .eq("recipient_id", value: currentProfile.id.uuidString)
            .eq("is_read", value: false)
            .is("dismissed_at", value: nil)
            .execute()

        let unreadAnnouncements = try await fetchSiteAnnouncements(limit: announcementLimit)
            .filter { !$0.isRead }
        guard !unreadAnnouncements.isEmpty else { return }

        guard let currentUser = client.auth.currentUser else {
            throw CommunityServiceError.missingAuthenticatedUser
        }
        let inserts = unreadAnnouncements.map { announcement in
            SiteAnnouncementReadInsert(
                announcementID: announcement.id,
                userID: currentUser.id,
                readAt: now,
                dismissedAt: nil
            )
        }

        _ = try await client
            .from("site_announcement_reads")
            .upsert(
                inserts,
                onConflict: "announcement_id,user_id",
                ignoreDuplicates: true
            )
            .execute()
    }

    func dismissNotificationFeedItem(_ item: NotificationFeedItem) async throws {
        switch item {
        case .community(let notification):
            try await dismissCommunityNotification(notificationID: notification.id)
        case .announcement(let announcement):
            try await dismissSiteAnnouncement(announcementID: announcement.id)
        }
    }

    func dismissCommunityNotification(notificationID: UUID) async throws {
        let client = try LeafySupabase.shared.requireClient()
        let update = CommunityNotificationDismissUpdate(
            isRead: true,
            dismissedAt: ISO8601DateFormatter().string(from: Date())
        )

        _ = try await client
            .from("community_notifications")
            .update(update)
            .eq("id", value: notificationID.uuidString)
            .execute()
    }

    func markSiteAnnouncementRead(announcementID: UUID) async throws {
        let client = try LeafySupabase.shared.requireClient()
        guard let currentUser = client.auth.currentUser else {
            throw CommunityServiceError.missingAuthenticatedUser
        }

        let insert = SiteAnnouncementReadInsert(
            announcementID: announcementID,
            userID: currentUser.id,
            readAt: ISO8601DateFormatter().string(from: Date()),
            dismissedAt: nil
        )

        _ = try await client
            .from("site_announcement_reads")
            .upsert(
                insert,
                onConflict: "announcement_id,user_id",
                ignoreDuplicates: true
            )
            .execute()
    }

    func dismissSiteAnnouncement(announcementID: UUID) async throws {
        let client = try LeafySupabase.shared.requireClient()
        guard let currentUser = client.auth.currentUser else {
            throw CommunityServiceError.missingAuthenticatedUser
        }

        let now = ISO8601DateFormatter().string(from: Date())
        let insert = SiteAnnouncementReadInsert(
            announcementID: announcementID,
            userID: currentUser.id,
            readAt: now,
            dismissedAt: now
        )

        _ = try await client
            .from("site_announcement_reads")
            .upsert(insert, onConflict: "announcement_id,user_id")
            .execute()
    }
}

// MARK: - Feedback and Catalog

extension CommunityService {
    func submitFeedback(issueType: String, body: String, contact: String?, deviceInfo: [String: String]) async throws {
        try await ensureAnonymousSession()
        let client = try LeafySupabase.shared.requireClient()
        guard client.auth.currentUser != nil else {
            throw CommunityServiceError.missingAuthenticatedUser
        }

        let trimmedBody = trimmedText(body) ?? ""
        guard !trimmedBody.isEmpty else {
            throw CommunityServiceError.edgeFunctionRejected("请先填写反馈内容。")
        }

        let currentProfile = try? await fetchCurrentProfile()
        let insert = FeedbackSubmissionInsert(
            userID: currentProfile?.id,
            issueType: trimmedText(issueType) ?? "问题反馈",
            body: trimmedBody,
            contact: trimmedText(contact),
            deviceInfo: deviceInfo
        )

        _ = try await client
            .from("feedback_submissions")
            .insert(insert)
            .execute()
    }

    func submitCatalogSuggestion(input: CatalogSuggestionInput) async throws {
        try await ensureAnonymousSession()
        let client = try LeafySupabase.shared.requireClient()
        guard client.auth.currentUser != nil else {
            throw CommunityServiceError.missingAuthenticatedUser
        }

        let name = trimmedText(input.name) ?? ""
        let unit = trimmedText(input.unit) ?? ""
        guard !name.isEmpty, !unit.isEmpty else {
            throw CommunityServiceError.edgeFunctionRejected("请填写名称和学院/单位。")
        }

        let teacherName: String?
        let category: String?
        let credit: Double?
        switch input.type {
        case .teacher:
            teacherName = nil
            category = nil
            credit = nil
        case .course:
            teacherName = trimmedText(input.teacherName)
            guard teacherName != nil else {
                throw CommunityServiceError.edgeFunctionRejected("请填写授课老师。")
            }
            category = trimmedText(input.category) ?? "公选课"
            credit = input.credit
            if let credit, credit < 0 {
                throw CommunityServiceError.edgeFunctionRejected("学分不能小于 0。")
            }
        case .dish:
            teacherName = nil
            category = nil
            credit = nil
        }

        if let initialStars = input.initialStars, !(1...5).contains(initialStars) {
            throw CommunityServiceError.edgeFunctionRejected("评分必须在 1 到 5 星之间。")
        }

        let currentProfile = try? await fetchCurrentProfile()
        let insert = CatalogSuggestionInsert(
            suggestionType: input.type.rawValue,
            userID: currentProfile?.id,
            name: name,
            unit: unit,
            teacherName: teacherName,
            category: category,
            credit: credit,
            initialStars: input.initialStars,
            note: trimmedText(input.note)
        )

        do {
            _ = try await client
                .from("catalog_suggestions")
                .insert(insert)
                .execute()
        } catch {
            if isDuplicateCatalogSuggestion(error) {
                return
            }
            throw error
        }
    }
}

// MARK: - Ratings

extension CommunityService {
    func fetchTeacherRatingSummaries(
        search: String = "",
        limit: Int = 50,
        offset: Int = 0
    ) async throws -> [TeacherRatingSummary] {
        let client = try LeafySupabase.shared.requireClient()
        let normalizedSearch = trimmedText(search)?.lowercased()
        let cappedLimit = max(1, min(limit, 100))
        let safeOffset = max(offset, 0)
        let rangeEnd = safeOffset + cappedLimit - 1

        let teachers: [TeacherProfile]
        if let normalizedSearch {
            teachers = try await client
                .from("teachers")
                .select()
                .ilike("search_text", pattern: "%\(normalizedSearch)%")
                .order("rating_average", ascending: false)
                .order("rating_count", ascending: false)
                .order("name", ascending: true)
                .range(from: safeOffset, to: rangeEnd)
                .execute()
                .value
        } else {
            teachers = try await client
                .from("teachers")
                .select()
                .order("rating_average", ascending: false)
                .order("rating_count", ascending: false)
                .order("name", ascending: true)
                .range(from: safeOffset, to: rangeEnd)
                .execute()
                .value
        }

        let ratings = try await fetchMyTeacherRatings(teacherIDs: teachers.map(\.id))
        let ratingMap = LeafyFirstValueMap.build(ratings.map { ($0.teacherID, $0) })

        return teachers.map { teacher in
            TeacherRatingSummary(teacher: teacher, myRating: ratingMap[teacher.id])
        }
    }

    func fetchTeacherRatingSummary(teacherID: Int64) async throws -> TeacherRatingSummary {
        let client = try LeafySupabase.shared.requireClient()
        let teachers: [TeacherProfile] = try await client
            .from("teachers")
            .select()
            .eq("id", value: Int(teacherID))
            .limit(1)
            .execute()
            .value

        guard let teacher = teachers.first else {
            throw CommunityServiceError.edgeFunctionRejected("没有找到这位老师。")
        }

        let rating = try await fetchMyTeacherRatings(teacherIDs: [teacherID]).first
        return TeacherRatingSummary(teacher: teacher, myRating: rating)
    }

    func submitTeacherRating(teacherID: Int64, stars: Int) async throws -> TeacherRatingSummary {
        guard (1...5).contains(stars) else {
            throw CommunityServiceError.edgeFunctionRejected("评分必须在 1 到 5 星之间。")
        }

        let client = try LeafySupabase.shared.requireClient()
        guard client.auth.currentUser != nil else {
            throw CommunityServiceError.missingAuthenticatedUser
        }

        guard let currentProfile = try await fetchCurrentProfile() else {
            throw CommunityServiceError.missingAuthenticatedUser
        }

        let existingRating = try await fetchMyTeacherRatings(teacherIDs: [teacherID]).first
        if existingRating == nil {
            let insert = TeacherRatingInsert(
                teacherID: teacherID,
                userID: currentProfile.id,
                stars: stars
            )

            do {
                _ = try await client
                    .from("teacher_ratings")
                    .insert(insert)
                    .execute()
            } catch {
                let update = TeacherRatingStarsUpdate(stars: stars)
                _ = try await client
                    .from("teacher_ratings")
                    .update(update)
                    .eq("teacher_id", value: Int(teacherID))
                    .eq("user_id", value: currentProfile.id.uuidString)
                    .execute()
            }
        } else {
            let update = TeacherRatingStarsUpdate(stars: stars)
            _ = try await client
                .from("teacher_ratings")
                .update(update)
                .eq("teacher_id", value: Int(teacherID))
                .eq("user_id", value: currentProfile.id.uuidString)
                .execute()
        }

        return try await fetchTeacherRatingSummary(teacherID: teacherID)
    }

    func fetchCourseRatingSummaries(
        search: String = "",
        category: String? = nil,
        limit: Int = 50,
        offset: Int = 0
    ) async throws -> [CourseRatingSummary] {
        let client = try LeafySupabase.shared.requireClient()
        let normalizedSearch = trimmedText(search)?.lowercased()
        let normalizedCategory = trimmedText(category)
        let cappedLimit = max(1, min(limit, 100))
        let safeOffset = max(offset, 0)
        let rangeEnd = safeOffset + cappedLimit - 1

        let courses: [CourseProfile]
        switch (normalizedSearch, normalizedCategory) {
        case let (search?, category?):
            courses = try await client
                .from("course_catalog")
                .select()
                .eq("status", value: "published")
                .eq("category", value: category)
                .ilike("search_text", pattern: "%\(search)%")
                .order("rating_average", ascending: false)
                .order("rating_count", ascending: false)
                .order("name", ascending: true)
                .range(from: safeOffset, to: rangeEnd)
                .execute()
                .value
        case let (search?, nil):
            courses = try await client
                .from("course_catalog")
                .select()
                .eq("status", value: "published")
                .ilike("search_text", pattern: "%\(search)%")
                .order("rating_average", ascending: false)
                .order("rating_count", ascending: false)
                .order("name", ascending: true)
                .range(from: safeOffset, to: rangeEnd)
                .execute()
                .value
        case let (nil, category?):
            courses = try await client
                .from("course_catalog")
                .select()
                .eq("status", value: "published")
                .eq("category", value: category)
                .order("rating_average", ascending: false)
                .order("rating_count", ascending: false)
                .order("name", ascending: true)
                .range(from: safeOffset, to: rangeEnd)
                .execute()
                .value
        case (nil, nil):
            courses = try await client
                .from("course_catalog")
                .select()
                .eq("status", value: "published")
                .order("rating_average", ascending: false)
                .order("rating_count", ascending: false)
                .order("name", ascending: true)
                .range(from: safeOffset, to: rangeEnd)
                .execute()
                .value
        }

        let ratings = try await fetchMyCourseRatings(courseIDs: courses.map(\.id))
        let ratingMap = LeafyFirstValueMap.build(ratings.map { ($0.courseID, $0) })

        return courses.map { course in
            CourseRatingSummary(course: course, myRating: ratingMap[course.id])
        }
    }

    func fetchCourseRatingSummary(courseID: Int64) async throws -> CourseRatingSummary {
        let client = try LeafySupabase.shared.requireClient()
        let courses: [CourseProfile] = try await client
            .from("course_catalog")
            .select()
            .eq("id", value: Int(courseID))
            .eq("status", value: "published")
            .limit(1)
            .execute()
            .value

        guard let course = courses.first else {
            throw CommunityServiceError.edgeFunctionRejected("没有找到这门课程。")
        }

        let rating = try await fetchMyCourseRatings(courseIDs: [courseID]).first
        return CourseRatingSummary(course: course, myRating: rating)
    }

    func submitCourseRating(courseID: Int64, stars: Int) async throws -> CourseRatingSummary {
        guard (1...5).contains(stars) else {
            throw CommunityServiceError.edgeFunctionRejected("评分必须在 1 到 5 星之间。")
        }

        let client = try LeafySupabase.shared.requireClient()
        guard client.auth.currentUser != nil else {
            throw CommunityServiceError.missingAuthenticatedUser
        }

        guard let currentProfile = try await fetchCurrentProfile() else {
            throw CommunityServiceError.missingAuthenticatedUser
        }

        let existingRating = try await fetchMyCourseRatings(courseIDs: [courseID]).first
        if existingRating == nil {
            let insert = CourseRatingInsert(
                courseID: courseID,
                userID: currentProfile.id,
                stars: stars
            )

            do {
                _ = try await client
                    .from("course_ratings")
                    .insert(insert)
                    .execute()
            } catch {
                let update = TeacherRatingStarsUpdate(stars: stars)
                _ = try await client
                    .from("course_ratings")
                    .update(update)
                    .eq("course_id", value: Int(courseID))
                    .eq("user_id", value: currentProfile.id.uuidString)
                    .execute()
            }
        } else {
            let update = TeacherRatingStarsUpdate(stars: stars)
            _ = try await client
                .from("course_ratings")
                .update(update)
                .eq("course_id", value: Int(courseID))
                .eq("user_id", value: currentProfile.id.uuidString)
                .execute()
        }

        return try await fetchCourseRatingSummary(courseID: courseID)
    }

    func fetchDishRatingSummaries(
        search: String = "",
        canteen: String? = nil,
        location: String? = nil,
        limit: Int = 50,
        offset: Int = 0
    ) async throws -> [DishRatingSummary] {
        let client = try LeafySupabase.shared.requireClient()
        let normalizedSearch = trimmedText(search)?.lowercased()
        let normalizedCanteen = trimmedText(canteen)
        let normalizedLocation = trimmedText(location)
        let cappedLimit = max(1, min(limit, 100))
        let safeOffset = max(offset, 0)
        let rangeEnd = safeOffset + cappedLimit - 1

        var query = client
            .from("dish_catalog")
            .select()
            .eq("status", value: "published")

        if let normalizedLocation {
            query = query.eq("location", value: normalizedLocation)
        } else if let normalizedCanteen {
            query = query.ilike("location", pattern: "\(normalizedCanteen)%")
        }

        if let normalizedSearch {
            query = query.ilike("search_text", pattern: "%\(normalizedSearch)%")
        }

        let dishes: [DishProfile] = try await query
            .order("rating_average", ascending: false)
            .order("rating_count", ascending: false)
            .order("name", ascending: true)
            .range(from: safeOffset, to: rangeEnd)
            .execute()
            .value

        let ratings = try await fetchMyDishRatings(dishIDs: dishes.map(\.id))
        let ratingMap = LeafyFirstValueMap.build(ratings.map { ($0.dishID, $0) })

        return dishes.map { dish in
            DishRatingSummary(dish: dish, myRating: ratingMap[dish.id])
        }
    }

    func fetchDishRatingSummary(dishID: Int64) async throws -> DishRatingSummary {
        let client = try LeafySupabase.shared.requireClient()
        let dishes: [DishProfile] = try await client
            .from("dish_catalog")
            .select()
            .eq("id", value: Int(dishID))
            .eq("status", value: "published")
            .limit(1)
            .execute()
            .value

        guard let dish = dishes.first else {
            throw CommunityServiceError.edgeFunctionRejected("没有找到这个菜品。")
        }

        let rating = try await fetchMyDishRatings(dishIDs: [dishID]).first
        return DishRatingSummary(dish: dish, myRating: rating)
    }

    func submitDishRating(dishID: Int64, stars: Int) async throws -> DishRatingSummary {
        guard (1...5).contains(stars) else {
            throw CommunityServiceError.edgeFunctionRejected("评分必须在 1 到 5 星之间。")
        }

        let client = try LeafySupabase.shared.requireClient()
        guard client.auth.currentUser != nil else {
            throw CommunityServiceError.missingAuthenticatedUser
        }

        guard let currentProfile = try await fetchCurrentProfile() else {
            throw CommunityServiceError.missingAuthenticatedUser
        }

        let existingRating = try await fetchMyDishRatings(dishIDs: [dishID]).first
        if existingRating == nil {
            let insert = DishRatingInsert(
                dishID: dishID,
                userID: currentProfile.id,
                stars: stars
            )

            do {
                _ = try await client
                    .from("dish_ratings")
                    .insert(insert)
                    .execute()
            } catch {
                let update = TeacherRatingStarsUpdate(stars: stars)
                _ = try await client
                    .from("dish_ratings")
                    .update(update)
                    .eq("dish_id", value: Int(dishID))
                    .eq("user_id", value: currentProfile.id.uuidString)
                    .execute()
            }
        } else {
            let update = TeacherRatingStarsUpdate(stars: stars)
            _ = try await client
                .from("dish_ratings")
                .update(update)
                .eq("dish_id", value: Int(dishID))
                .eq("user_id", value: currentProfile.id.uuidString)
                .execute()
        }

        return try await fetchDishRatingSummary(dishID: dishID)
    }

    private func fetchMyTeacherRatings(teacherIDs: [Int64]) async throws -> [TeacherRating] {
        guard !teacherIDs.isEmpty else { return [] }

        let client = try LeafySupabase.shared.requireClient()
        guard client.auth.currentUser != nil,
              let currentProfile = try await fetchCurrentProfile() else {
            return []
        }

        return try await client
            .from("teacher_ratings")
            .select()
            .eq("user_id", value: currentProfile.id.uuidString)
            .in("teacher_id", values: teacherIDs.map { Int($0) })
            .execute()
            .value
    }

    private func fetchMyDishRatings(dishIDs: [Int64]) async throws -> [DishRating] {
        guard !dishIDs.isEmpty else { return [] }

        let client = try LeafySupabase.shared.requireClient()
        guard client.auth.currentUser != nil,
              let currentProfile = try await fetchCurrentProfile() else {
            return []
        }

        return try await client
            .from("dish_ratings")
            .select()
            .eq("user_id", value: currentProfile.id.uuidString)
            .in("dish_id", values: dishIDs.map { Int($0) })
            .execute()
            .value
    }

    private func fetchMyCourseRatings(courseIDs: [Int64]) async throws -> [CourseRating] {
        guard !courseIDs.isEmpty else { return [] }

        let client = try LeafySupabase.shared.requireClient()
        guard client.auth.currentUser != nil,
              let currentProfile = try await fetchCurrentProfile() else {
            return []
        }

        return try await client
            .from("course_ratings")
            .select()
            .eq("user_id", value: currentProfile.id.uuidString)
            .in("course_id", values: courseIDs.map { Int($0) })
            .execute()
            .value
    }
}

// MARK: - Shared Supabase Implementation

extension CommunityService {
    private func createNotification(
        recipientID: UUID,
        actorID: UUID,
        postID: UUID,
        commentID: UUID?,
        type: CommunityNotificationType,
        title: String,
        body: String?
    ) async throws {
        let client = try LeafySupabase.shared.requireClient()
        let params = CommunityNotificationRPCParams(
            recipientID: recipientID,
            actorID: actorID,
            postID: postID,
            commentID: commentID,
            type: type,
            title: title,
            body: body
        )

        _ = try await client
            .rpc("create_community_notification", params: params)
            .execute()
    }

    private func reportCommunityContent(
        targetType: CommunityReportTargetType,
        postID: UUID?,
        commentID: UUID?,
        reportedUserID: UUID?,
        reason: String,
        detail: String?
    ) async throws {
        let normalizedReason = reason.trimmingCharacters(in: .whitespacesAndNewlines)
        let normalizedDetail = detail?.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !normalizedReason.isEmpty else {
            throw CommunityServiceError.edgeFunctionRejected("请选择举报原因。")
        }
        guard (normalizedDetail?.count ?? 0) <= 1_000 else {
            throw CommunityServiceError.edgeFunctionRejected("举报说明最多 1,000 个字符。")
        }
        let client = try LeafySupabase.shared.requireClient()
        guard client.auth.currentUser != nil else {
            throw CommunityServiceError.missingAuthenticatedUser
        }

        _ = try await client
            .rpc(
                "report_community_content",
                params: CommunityReportContentRPCParams(
                    targetType: targetType,
                    postID: postID,
                    commentID: commentID,
                    reportedUserID: reportedUserID,
                    reason: normalizedReason,
                    detail: normalizedDetail
                )
            )
            .execute()
    }

    private func enforcePostRateLimit(authorID: UUID, client: SupabaseClient) async throws {
        let threshold = ISO8601DateFormatter().string(from: Date().addingTimeInterval(-60 * 60))
        let recentPosts: [CommunityPostRateLimitRecord] = try await client
            .from("posts")
            .select("id")
            .eq("author_id", value: authorID.uuidString)
            .gte("created_at", value: threshold)
            .limit(2)
            .execute()
            .value

        if recentPosts.count >= 2 {
            throw CommunityServiceError.postRateLimitExceeded
        }
    }

    private func uploadPostImages(_ images: [CommunityImageUpload], authorID: UUID, postID: UUID) async throws {
        let client = try LeafySupabase.shared.requireClient()
        let authorPathComponent = authorID.uuidString.lowercased()
        let postPathComponent = postID.uuidString.lowercased()

        for (index, image) in images.enumerated() {
            let imagePathComponent = image.id.uuidString.lowercased()
            let objectPath = "posts/\(authorPathComponent)/\(postPathComponent)/full/\(imagePathComponent).\(image.fileExtension)"
            let thumbnailUpload = try await MainActor.run {
                try image.thumbnailUpload()
            }
            let thumbnailPath = "posts/\(authorPathComponent)/\(postPathComponent)/thumb/\(imagePathComponent).\(thumbnailUpload.fileExtension)"
            _ = try await client.storage
                .from(Self.storageBucket)
                .upload(
                    objectPath,
                    data: image.data,
                    options: FileOptions(
                        cacheControl: Self.publicImageCacheControl,
                        contentType: image.mimeType,
                        upsert: false
                    )
                )
            _ = try await client.storage
                .from(Self.storageBucket)
                .upload(
                    thumbnailPath,
                    data: thumbnailUpload.data,
                    options: FileOptions(
                        cacheControl: Self.publicImageCacheControl,
                        contentType: thumbnailUpload.mimeType,
                        upsert: false
                    )
                )

            do {
                let session = try await client.auth.session
                client.functions.setAuth(token: session.accessToken)
                let validation: CommunityUploadValidationResponse = try await client.functions.invoke(
                    "community-validate-upload",
                    options: FunctionInvokeOptions(
                        headers: ["Authorization": "Bearer \(session.accessToken)"],
                        body: CommunityUploadValidationRequest(
                            postID: postID,
                            fullPath: objectPath,
                            thumbnailPath: thumbnailPath
                        )
                    )
                )
                _ = try await client
                    .rpc(
                        "attach_community_post_image_v1",
                        params: CommunityAttachPostImageRPCParams(
                            receiptID: validation.receiptID,
                            imageID: image.id,
                            sortOrder: index
                        )
                    )
                    .execute()
            } catch {
                _ = try? await client.storage.from(Self.storageBucket).remove(paths: [objectPath, thumbnailPath])
                throw CommunityServiceError.edgeFunctionRejected("图片记录写入失败：\(error.localizedDescription)")
            }
        }
    }

    private func publishPostAfterImageUpload(postID: UUID) async throws {
        let client = try LeafySupabase.shared.requireClient()
        _ = try await client
            .rpc(
                "publish_community_post_v1",
                params: CommunityPublishPostRPCParams(postID: postID)
            )
            .execute()
    }

    private func markPostDeleted(postID: UUID) async throws {
        let client = try LeafySupabase.shared.requireClient()
        _ = try await client
            .rpc(
                "soft_delete_own_post",
                params: CommunityPostSoftDeleteRPCParams(targetPostID: postID)
            )
            .execute()
    }

    private func uploadProfileAvatarIfNeeded(_ avatar: CommunityImageUpload?, userID: UUID) async throws -> String? {
        guard let avatar else { return nil }

        let client = try LeafySupabase.shared.requireClient()
        let userPathComponent = userID.uuidString.lowercased()
        let avatarPathComponent = avatar.id.uuidString.lowercased()
        let objectPath = "avatars/\(userPathComponent)/\(avatarPathComponent).\(avatar.fileExtension)"

        _ = try await client.storage
            .from(Self.storageBucket)
            .upload(
                objectPath,
                data: avatar.data,
                options: FileOptions(
                    cacheControl: Self.publicImageCacheControl,
                    contentType: avatar.mimeType,
                    upsert: true
                )
            )

        do {
            try await validateProfileImageUpload(kind: "avatar", path: objectPath, client: client)
        } catch {
            _ = try? await client.storage.from(Self.storageBucket).remove(paths: [objectPath])
            throw error
        }

        return objectPath
    }

    private func uploadProfileCoverIfNeeded(_ cover: CommunityImageUpload?, userID: UUID) async throws -> String? {
        guard let cover else { return nil }

        let client = try LeafySupabase.shared.requireClient()
        let userPathComponent = userID.uuidString.lowercased()
        let coverPathComponent = cover.id.uuidString.lowercased()
        let objectPath = "profile-covers/\(userPathComponent)/\(coverPathComponent).\(cover.fileExtension)"

        _ = try await client.storage
            .from(Self.storageBucket)
            .upload(
                objectPath,
                data: cover.data,
                options: FileOptions(
                    cacheControl: Self.publicImageCacheControl,
                    contentType: cover.mimeType,
                    upsert: true
                )
            )

        do {
            try await validateProfileImageUpload(kind: "cover", path: objectPath, client: client)
        } catch {
            _ = try? await client.storage.from(Self.storageBucket).remove(paths: [objectPath])
            throw error
        }

        return objectPath
    }

    private func validateProfileImageUpload(
        kind: String,
        path: String,
        client: SupabaseClient
    ) async throws {
        let session = try await client.auth.session
        client.functions.setAuth(token: session.accessToken)
        let response: CommunityProfileUploadValidationResponse = try await client.functions.invoke(
            "community-validate-upload",
            options: FunctionInvokeOptions(
                headers: ["Authorization": "Bearer \(session.accessToken)"],
                body: CommunityProfileUploadValidationRequest(kind: kind, objectPath: path)
            )
        )
        guard response.validated else {
            throw CommunityServiceError.edgeFunctionRejected("图片验证失败，请重新选择图片。")
        }
    }

    private nonisolated func hydratePosts(
        from records: [CommunityPostRecord],
        client: SupabaseClient,
        viewerID: UUID?,
        pins: [CommunityPostPin] = []
    ) async throws -> [CommunityPost] {
        guard !records.isEmpty else { return [] }

        let authorIDs = Array(Set(records.map(\.authorID)))
        let postIDs = records.map(\.id)
        let profiles = try await fetchProfiles(ids: authorIDs, client: client)
        let images = try await fetchPostImages(postIDs: postIDs, client: client)
        let likes = try await fetchPostLikes(postIDs: postIDs, client: client)
        let favorites = try await fetchPostFavorites(postIDs: postIDs, viewerID: viewerID, client: client)

        let profileMap = LeafyFirstValueMap.build(profiles.map { ($0.id, $0) })
        let imageMap = Dictionary(grouping: images, by: \.postID)
        let likeMap = Dictionary(grouping: likes, by: \.postID)
        let favoritedPostIDs = Set(favorites.map(\.postID))
        let pinMap = preferredPinMap(from: pins)

        return records.map { record in
            let postLikes = likeMap[record.id] ?? []
            return CommunityPost(
                id: record.id,
                authorID: record.authorID,
                title: record.title,
                body: record.body,
                category: record.category,
                isAnonymous: record.isAnonymous,
                commentCount: record.commentCount,
                likeCount: postLikes.count,
                status: record.status,
                createdAt: record.createdAt,
                updatedAt: record.updatedAt,
                viewerHasLiked: postLikes.contains(where: { $0.userID == viewerID }),
                viewerHasFavorited: favoritedPostIDs.contains(record.id),
                pin: pinMap[record.id],
                author: profileMap[record.authorID],
                images: imageMap[record.id] ?? []
            )
        }
    }

    private nonisolated func hydrateComments(
        from records: [CommunityCommentRecord],
        client: SupabaseClient
    ) async throws -> [CommunityComment] {
        guard !records.isEmpty else { return [] }

        let profiles = try await fetchProfiles(ids: Array(Set(records.map(\.authorID))), client: client)
        let profileMap = LeafyFirstValueMap.build(profiles.map { ($0.id, $0) })

        return records.map { record in
            CommunityComment(
                id: record.id,
                postID: record.postID,
                authorID: record.authorID,
                body: record.body,
                isAnonymous: record.isAnonymous,
                status: record.status,
                createdAt: record.createdAt,
                updatedAt: record.updatedAt,
                author: profileMap[record.authorID]
            )
        }
    }

    private func hydrateNotifications(from records: [CommunityNotificationRecord]) async throws -> [CommunityNotification] {
        guard !records.isEmpty else { return [] }

        let actorIDs = records.compactMap(\.actorID)
        let profiles = try await fetchProfiles(ids: Array(Set(actorIDs)))
        let profileMap = LeafyFirstValueMap.build(profiles.map { ($0.id, $0) })

        return records.map { record in
            CommunityNotification(
                id: record.id,
                recipientID: record.recipientID,
                actorID: record.actorID,
                postID: record.postID,
                commentID: record.commentID,
                type: record.type,
                title: record.title,
                body: record.body,
                isRead: record.isRead,
                createdAt: record.createdAt,
                actor: record.actorID.flatMap { profileMap[$0] }
            )
        }
    }

    private nonisolated func fetchProfiles(ids: [UUID], client providedClient: SupabaseClient? = nil) async throws -> [CommunityProfile] {
        guard !ids.isEmpty else { return [] }

        let client: SupabaseClient
        if let providedClient {
            client = providedClient
        } else {
            client = try LeafySupabase.shared.requireClient()
        }
        let profiles: [CommunityProfile] = try await client
            .from("profiles")
            .select()
            .in("id", values: ids.map(\.uuidString))
            .execute()
            .value

        return try await hydrateProfiles(profiles, client: client)
    }

    private nonisolated func fetchProfile(id: UUID, client providedClient: SupabaseClient? = nil) async throws -> CommunityProfile? {
        try await fetchProfiles(ids: [id], client: providedClient).first
    }

    private nonisolated func fetchActivePostPins(
        query: CommunityFeedQuery,
        client: SupabaseClient
    ) async throws -> [CommunityPostPin] {
        do {
            let records: [CommunityPostPin] = try await client
                .from("community_post_pins")
                .select()
                .eq("status", value: "active")
                .order("priority", ascending: false)
                .order("starts_at", ascending: false)
                .limit(50)
                .execute()
                .value

            return records.filter { pin in
                guard pin.isCurrentlyActive else { return false }
                switch pin.scope {
                case .global:
                    return true
                case .category:
                    guard let selectedCategory = query.category else { return false }
                    return normalizedCommunityText(pin.category) == normalizedCommunityText(selectedCategory)
                }
            }
        } catch {
            if isMissingPostPinsTable(error) {
                return []
            }
            throw error
        }
    }

    private nonisolated func fetchActivePostPins(
        postIDs: [UUID],
        client: SupabaseClient
    ) async throws -> [CommunityPostPin] {
        guard !postIDs.isEmpty else { return [] }

        do {
            let records: [CommunityPostPin] = try await client
                .from("community_post_pins")
                .select()
                .eq("status", value: "active")
                .in("post_id", values: postIDs.map(\.uuidString))
                .order("priority", ascending: false)
                .order("starts_at", ascending: false)
                .execute()
                .value

            return records.filter(\.isCurrentlyActive)
        } catch {
            if isMissingPostPinsTable(error) {
                return []
            }
            throw error
        }
    }

    private nonisolated func fetchCurrentProfileID(client: SupabaseClient) async throws -> UUID? {
        guard let currentUserID = client.auth.currentUser?.id else {
            return nil
        }

        do {
            let links: [CommunityProfileAuthLinkRecord] = try await client
                .from("profile_auth_links")
                .select()
                .eq("auth_user_id", value: currentUserID.uuidString)
                .limit(1)
                .execute()
                .value

            if let profileID = links.first?.profileID {
                return profileID
            }
        } catch where isMissingSchemaColumn(error, column: "campus_id") {
            let links: [CommunityProfileAuthLinkRecord] = try await client
                .from("profile_auth_links")
                .select()
                .eq("auth_user_id", value: currentUserID.uuidString)
                .limit(1)
                .execute()
                .value

            if let profileID = links.first?.profileID {
                return profileID
            }
        } catch {
            return currentUserID
        }

        return currentUserID
    }

    private nonisolated func uniquePostRecords(_ records: [CommunityPostRecord]) -> [CommunityPostRecord] {
        var seen: Set<UUID> = []
        var result: [CommunityPostRecord] = []
        for record in records where !seen.contains(record.id) {
            seen.insert(record.id)
            result.append(record)
        }
        return result
    }

    private nonisolated func preferredPinMap(from pins: [CommunityPostPin]) -> [UUID: CommunityPostPin] {
        Dictionary(grouping: pins, by: \.postID).compactMapValues { postPins in
            postPins.sorted { lhs, rhs in
                if lhs.priority != rhs.priority {
                    return lhs.priority > rhs.priority
                }
                let leftStart = CommunityTimestampFormatter.parse(lhs.startsAt) ?? .distantPast
                let rightStart = CommunityTimestampFormatter.parse(rhs.startsAt) ?? .distantPast
                return leftStart > rightStart
            }.first
        }
    }

    private nonisolated func normalizedCommunityText(_ value: String?) -> String {
        (value ?? "")
            .trimmingCharacters(in: .whitespacesAndNewlines)
            .lowercased()
    }

    private nonisolated func communityFeedQueryItems(_ query: CommunityFeedQuery) -> [URLQueryItem] {
        var items = [
            URLQueryItem(name: "limit", value: String(query.limit)),
            URLQueryItem(name: "campus_id", value: ActiveCampusContext.descriptor.id.rawValue)
        ]
        if case .hot(let days) = query.mode.normalized {
            items.append(URLQueryItem(name: "mode", value: "hot"))
            items.append(URLQueryItem(name: "days", value: String(days)))
        }
        if let category = query.category {
            items.append(URLQueryItem(name: "category", value: category))
        }
        if let search = query.search {
            items.append(URLQueryItem(name: "search", value: search))
        }
        return items
    }

    private nonisolated func fetchPostsFromCommunityAPI(
        baseURL: URL,
        functionName: String,
        query: CommunityFeedQuery,
        accessToken: String
    ) async throws -> CommunityFeedResponse {
        guard let url = communityAPIURL(baseURL: baseURL, functionName: functionName, query: query) else {
            throw CommunityServiceError.edgeFunctionRejected("社区接口地址无效。")
        }

        var request = URLRequest(url: url, timeoutInterval: 15)
        request.httpMethod = "GET"
        request.setValue("Bearer \(accessToken)", forHTTPHeaderField: "Authorization")
        request.setValue("application/json", forHTTPHeaderField: "Accept")

        let (data, response) = try await URLSession.shared.data(for: request)
        guard let httpResponse = response as? HTTPURLResponse else {
            throw CommunityServiceError.edgeFunctionRejected("社区接口响应无效。")
        }

        guard (200..<300).contains(httpResponse.statusCode) else {
            if let payload = try? JSONDecoder().decode(EdgeFunctionErrorPayload.self, from: data),
               let message = payload.error?.trimmingCharacters(in: .whitespacesAndNewlines),
               !message.isEmpty {
                throw CommunityServiceError.edgeFunctionRejected(message)
            }

            throw CommunityServiceError.edgeFunctionRejected("社区接口返回了 \(httpResponse.statusCode) 错误。")
        }

        do {
            return try JSONDecoder().decode(CommunityFeedResponse.self, from: data)
        } catch {
            throw CommunityServiceError.edgeFunctionRejected("社区接口数据解析失败：\(error.localizedDescription)")
        }
    }

    private nonisolated func communityAPIURL(
        baseURL: URL,
        functionName: String,
        query: CommunityFeedQuery
    ) -> URL? {
        let trimmedFunctionName = functionName.trimmingCharacters(in: .whitespacesAndNewlines)
        let endpoint: URL
        if trimmedFunctionName.isEmpty || baseURL.lastPathComponent == trimmedFunctionName {
            endpoint = baseURL
        } else {
            endpoint = baseURL.appendingPathComponent(trimmedFunctionName)
        }

        guard var components = URLComponents(url: endpoint, resolvingAgainstBaseURL: false) else {
            return nil
        }

        let existingItems = components.queryItems ?? []
        components.queryItems = existingItems + communityFeedQueryItems(query)
        return components.url
    }

    private nonisolated func publicStorageURL(path: String?, config _: SupabaseConfig) -> URL? {
        guard let path = path?.trimmingCharacters(in: .whitespacesAndNewlines),
              !path.isEmpty,
              let client = LeafySupabase.shared.client else {
            return nil
        }

        return try? client.storage
            .from(Self.storageBucket)
            .getPublicURL(path: path)
    }

    private nonisolated func postWithPublicStorageURLs(_ post: CommunityPost, config: SupabaseConfig) -> CommunityPost {
        CommunityPost(
            id: post.id,
            authorID: post.authorID,
            title: post.title,
            body: post.body,
            category: post.category,
            isAnonymous: post.isAnonymous,
            commentCount: post.commentCount,
            likeCount: post.likeCount,
            status: post.status,
            createdAt: post.createdAt,
            updatedAt: post.updatedAt,
            viewerHasLiked: post.viewerHasLiked,
            viewerHasFavorited: post.viewerHasFavorited,
            pin: post.pin,
            author: post.author.map { profileWithPublicAvatarURL($0, config: config) },
            images: post.images.map { imageWithPublicStorageURLs($0, config: config) }
        )
    }

    private nonisolated func profileWithPublicAvatarURL(_ profile: CommunityProfile, config: SupabaseConfig) -> CommunityProfile {
        CommunityProfile(
            id: profile.id,
            eduID: profile.eduID,
            campusID: profile.campusID,
            communityCampusID: profile.communityCampusID,
            communityAccessStatusRaw: profile.communityAccessStatusRaw,
            communitySchoolName: profile.communitySchoolName,
            communityRejectionReason: profile.communityRejectionReason,
            nickname: profile.nickname,
            displayName: profile.displayName,
            avatarPath: profile.avatarPath,
            coverPath: profile.coverPath,
            bio: profile.bio,
            major: profile.major,
            grade: profile.grade,
            boundEmail: profile.boundEmail,
            pendingBoundEmail: profile.pendingBoundEmail,
            emailVerificationSentAt: profile.emailVerificationSentAt,
            profileEditedAt: profile.profileEditedAt,
            isProfileComplete: profile.isProfileComplete,
            createdAt: profile.createdAt,
            updatedAt: profile.updatedAt,
            signedAvatarURL: profile.signedAvatarURL,
            avatarURL: profile.avatarURL ?? publicStorageURL(path: profile.avatarPath, config: config),
            signedCoverURL: profile.signedCoverURL,
            coverURL: profile.coverURL ?? publicStorageURL(path: profile.coverPath, config: config),
            showsEduVerificationBadge: profile.showsEduVerificationBadge
        )
    }

    private nonisolated func imageWithPublicStorageURLs(_ image: CommunityPostImage, config: SupabaseConfig) -> CommunityPostImage {
        CommunityPostImage(
            id: image.id,
            postID: image.postID,
            path: image.path,
            thumbnailPath: image.thumbnailPath,
            sortOrder: image.sortOrder,
            width: image.width,
            height: image.height,
            thumbnailWidth: image.thumbnailWidth,
            thumbnailHeight: image.thumbnailHeight,
            fullWidth: image.fullWidth,
            fullHeight: image.fullHeight,
            createdAt: image.createdAt,
            signedURL: image.signedURL,
            thumbnailURL: image.thumbnailURL ?? publicStorageURL(path: image.thumbnailPath ?? image.path, config: config),
            fullURL: image.fullURL ?? publicStorageURL(path: image.path, config: config)
        )
    }

    private nonisolated func pollWithPublicAvatarURL(_ poll: CommunityPoll) throws -> CommunityPoll {
        let config = try LeafySupabase.shared.requireConfig()
        return CommunityPoll(
            id: poll.id,
            authorID: poll.authorID,
            question: poll.question,
            detail: poll.detail,
            status: poll.status,
            totalVoteCount: poll.totalVoteCount,
            viewerOptionID: poll.viewerOptionID,
            closesAt: poll.closesAt,
            deletionStatus: poll.deletionStatus,
            deletionRequestedAt: poll.deletionRequestedAt,
            deletionReason: poll.deletionReason,
            deletionReviewedAt: poll.deletionReviewedAt,
            deletionReviewReason: poll.deletionReviewReason,
            createdAt: poll.createdAt,
            updatedAt: poll.updatedAt,
            author: poll.author.map { profileWithPublicAvatarURL($0, config: config) },
            options: poll.options
        )
    }

    private nonisolated func hydratePolls(
        from records: [CommunityPollRecord],
        client: SupabaseClient,
        viewerID: UUID?
    ) async throws -> [CommunityPoll] {
        guard !records.isEmpty else { return [] }

        let pollIDs = records.map(\.id)
        let authorIDs = Array(Set(records.map(\.authorID)))
        let profiles = try await fetchProfiles(ids: authorIDs, client: client)
        let options: [CommunityPollOption] = try await client
            .from("community_poll_options")
            .select()
            .in("poll_id", values: pollIDs.map(\.uuidString))
            .order("sort_order", ascending: true)
            .execute()
            .value

        let votes = try await fetchPollVotes(pollIDs: pollIDs, viewerID: viewerID, client: client)
        let profileMap = LeafyFirstValueMap.build(profiles.map { ($0.id, $0) })
        let optionMap = Dictionary(grouping: options, by: \.pollID)
        let voteMap = LeafyFirstValueMap.build(votes.map { ($0.pollID, $0.optionID) })

        return records.map { record in
            CommunityPoll(
                id: record.id,
                authorID: record.authorID,
                question: record.question,
                detail: record.detail,
                status: record.status,
                totalVoteCount: record.totalVoteCount,
                viewerOptionID: voteMap[record.id],
                closesAt: record.closesAt,
                deletionStatus: record.deletionStatus,
                deletionRequestedAt: record.deletionRequestedAt,
                deletionReason: record.deletionReason,
                deletionReviewedAt: record.deletionReviewedAt,
                deletionReviewReason: record.deletionReviewReason,
                createdAt: record.createdAt,
                updatedAt: record.updatedAt,
                author: profileMap[record.authorID],
                options: optionMap[record.id] ?? []
            )
        }
    }

    private nonisolated func fetchPollVotes(
        pollIDs: [UUID],
        viewerID: UUID?,
        client: SupabaseClient
    ) async throws -> [CommunityPollVoteRecord] {
        guard let viewerID, !pollIDs.isEmpty else { return [] }

        return try await client
            .from("community_poll_votes")
            .select()
            .eq("user_id", value: viewerID.uuidString)
            .in("poll_id", values: pollIDs.map(\.uuidString))
            .execute()
            .value
    }

    private nonisolated func fetchPostImages(postIDs: [UUID], client: SupabaseClient) async throws -> [CommunityPostImage] {
        guard !postIDs.isEmpty else { return [] }

        let records: [CommunityPostImageRecord] = try await client
            .from("post_images")
            .select()
            .in("post_id", values: postIDs.map(\.uuidString))
            .order("sort_order", ascending: true)
            .execute()
            .value

        guard !records.isEmpty else { return [] }

        let paths = records
            .map(\.path)
            .map { $0.trimmingCharacters(in: .whitespacesAndNewlines) }
            .filter { !$0.isEmpty }

        guard !paths.isEmpty else {
            return records.map { record in
                CommunityPostImage(
                    id: record.id,
                    postID: record.postID,
                    path: record.path,
                    thumbnailPath: record.thumbnailPath,
                    sortOrder: record.sortOrder,
                    width: record.width,
                    height: record.height,
                    thumbnailWidth: record.thumbnailWidth,
                    thumbnailHeight: record.thumbnailHeight,
                    fullWidth: record.fullWidth,
                    fullHeight: record.fullHeight,
                    createdAt: record.createdAt,
                    signedURL: nil,
                    thumbnailURL: nil,
                    fullURL: nil
                )
            }
        }

        let signedResults = try await client.storage
            .from(Self.storageBucket)
            .createSignedURLs(paths: paths, expiresIn: 60 * 60 * 24)

        let signedPairs: [(String, URL)] = signedResults.compactMap { result in
            guard let signedURL = result.signedURL else { return nil }
            return (result.path, signedURL)
        }
        let signedMap = LeafyFirstValueMap.build(signedPairs)

        return records.map { record in
            CommunityPostImage(
                id: record.id,
                postID: record.postID,
                path: record.path,
                thumbnailPath: record.thumbnailPath,
                sortOrder: record.sortOrder,
                width: record.width,
                height: record.height,
                thumbnailWidth: record.thumbnailWidth,
                thumbnailHeight: record.thumbnailHeight,
                fullWidth: record.fullWidth,
                fullHeight: record.fullHeight,
                createdAt: record.createdAt,
                signedURL: signedMap[record.path],
                thumbnailURL: nil,
                fullURL: nil
            )
        }
    }

    private nonisolated func fetchPostLikes(postIDs: [UUID], client: SupabaseClient) async throws -> [CommunityPostLikeRecord] {
        guard !postIDs.isEmpty else { return [] }

        return try await client
            .from("post_likes")
            .select()
            .in("post_id", values: postIDs.map(\.uuidString))
            .execute()
            .value
    }

    private nonisolated func fetchPostFavorites(
        postIDs: [UUID],
        viewerID: UUID?,
        client: SupabaseClient
    ) async throws -> [CommunityPostFavoriteRecord] {
        guard let viewerID, !postIDs.isEmpty else { return [] }

        return try await client
            .from("post_favorites")
            .select()
            .eq("user_id", value: viewerID.uuidString)
            .in("post_id", values: postIDs.map(\.uuidString))
            .execute()
            .value
    }

    private nonisolated func fetchBlockedUserIDs(viewerID: UUID, client: SupabaseClient) async throws -> Set<UUID> {
        let records: [CommunityBlockRecord] = try await client
            .from("community_blocks")
            .select()
            .eq("blocker_id", value: viewerID.uuidString)
            .execute()
            .value

        return Set(records.map(\.blockedID))
    }

    private nonisolated func filterBlockedPosts(
        _ posts: [CommunityPost],
        viewerID: UUID?,
        client: SupabaseClient
    ) async throws -> [CommunityPost] {
        guard let viewerID else { return posts }
        let blockedIDs = try await fetchBlockedUserIDs(viewerID: viewerID, client: client)
        guard !blockedIDs.isEmpty else { return posts }
        return posts.filter { !blockedIDs.contains($0.authorID) }
    }

    private nonisolated func filterBlockedComments(
        _ comments: [CommunityComment],
        viewerID: UUID?,
        client: SupabaseClient
    ) async throws -> [CommunityComment] {
        guard let viewerID else { return comments }
        let blockedIDs = try await fetchBlockedUserIDs(viewerID: viewerID, client: client)
        guard !blockedIDs.isEmpty else { return comments }
        return comments.filter { !blockedIDs.contains($0.authorID) }
    }

    private func fetchSiteAnnouncementReads(
        announcementIDs: [UUID],
        userID: UUID
    ) async throws -> [SiteAnnouncementReadRecord] {
        guard !announcementIDs.isEmpty else { return [] }

        let client = try LeafySupabase.shared.requireClient()
        return try await client
            .from("site_announcement_reads")
            .select()
            .eq("user_id", value: userID.uuidString)
            .in("announcement_id", values: announcementIDs.map(\.uuidString))
            .execute()
            .value
    }

    private func isSiteAnnouncementActive(_ record: SiteAnnouncementRecord) -> Bool {
        guard record.status == "published" else { return false }

        let now = Date()
        if let publishedAt = record.publishedAt.flatMap(CommunityTimestampFormatter.parse),
           publishedAt > now {
            return false
        }

        if let expiresAt = record.expiresAt.flatMap(CommunityTimestampFormatter.parse),
           expiresAt <= now {
            return false
        }

        return true
    }

    private nonisolated func hydrateProfiles(_ profiles: [CommunityProfile], client: SupabaseClient) async throws -> [CommunityProfile] {
        let storagePaths = profiles
            .flatMap { [$0.avatarPath, $0.coverPath] }
            .compactMap { $0 }
            .map { $0.trimmingCharacters(in: .whitespacesAndNewlines) }
            .filter { !$0.isEmpty }

        guard !storagePaths.isEmpty else { return profiles }

        let signedResults = try await client.storage
            .from(Self.storageBucket)
            .createSignedURLs(paths: storagePaths, expiresIn: 60 * 60 * 24)

        let signedPairs: [(String, URL)] = signedResults.compactMap { result in
            guard let signedURL = result.signedURL else { return nil }
            return (result.path, signedURL)
        }
        let signedMap = LeafyFirstValueMap.build(signedPairs)

        return profiles.map { profile in
            CommunityProfile(
                id: profile.id,
                eduID: profile.eduID,
                campusID: profile.campusID,
                communityCampusID: profile.communityCampusID,
                communityAccessStatusRaw: profile.communityAccessStatusRaw,
                communitySchoolName: profile.communitySchoolName,
                communityRejectionReason: profile.communityRejectionReason,
                nickname: profile.nickname,
                displayName: profile.displayName,
                avatarPath: profile.avatarPath,
                coverPath: profile.coverPath,
                bio: profile.bio,
                major: profile.major,
                grade: profile.grade,
                boundEmail: profile.boundEmail,
                pendingBoundEmail: profile.pendingBoundEmail,
                emailVerificationSentAt: profile.emailVerificationSentAt,
                profileEditedAt: profile.profileEditedAt,
                isProfileComplete: profile.isProfileComplete,
                createdAt: profile.createdAt,
                updatedAt: profile.updatedAt,
                signedAvatarURL: profile.avatarPath.flatMap { signedMap[$0] },
                avatarURL: profile.avatarURL,
                signedCoverURL: profile.coverPath.flatMap { signedMap[$0] },
                coverURL: profile.coverURL,
                showsEduVerificationBadge: profile.showsEduVerificationBadge
            )
        }
    }

    private func requireCompletedCurrentProfile() async throws -> CommunityProfile {
        guard let profile = try await fetchCurrentProfile() else {
            throw CommunityServiceError.missingAuthenticatedUser
        }

        let trimmedNickname = profile.nickname.trimmingCharacters(in: .whitespacesAndNewlines)
        guard profile.isProfileComplete && !trimmedNickname.isEmpty else {
            throw CommunityServiceError.profileCompletionRequired
        }

        return profile
    }

    private func requireAcceptedCurrentTerms() async throws {
        guard try await hasAcceptedCurrentTerms() else {
            throw CommunityServiceError.termsAcceptanceRequired
        }
    }

    private func trimmedText(_ text: String?) -> String? {
        let trimmed = text?.trimmingCharacters(in: .whitespacesAndNewlines) ?? ""
        return trimmed.isEmpty ? nil : trimmed
    }

    private func mapEmailAuthError(_ error: Error) -> CommunityServiceError {
        if let serviceError = error as? CommunityServiceError {
            return serviceError
        }

        if let authError = error as? AuthError {
            CommunityDiagnostics.log.error(
                "Email verification failed authCode=\(String(describing: authError.errorCode), privacy: .public)"
            )
            switch authError.errorCode {
            case .otpExpired:
                return .edgeFunctionRejected("验证码已失效，请重新发送并使用最新邮件中的验证码。")
            case .overEmailSendRateLimit, .overRequestRateLimit:
                return .edgeFunctionRejected("验证码发送太频繁，请稍后再试。")
            case .emailExists, .userAlreadyExists, .conflict:
                return .edgeFunctionRejected("这个邮箱已被其他账号绑定或注册，请换一个邮箱。")
            case .emailProviderDisabled, .otpDisabled:
                return .edgeFunctionRejected("当前邮箱验证服务暂不可用，请稍后再试。")
            default:
                let message = authError.message
                if message.localizedCaseInsensitiveContains("otp")
                    || message.localizedCaseInsensitiveContains("token")
                    || message.localizedCaseInsensitiveContains("code") {
                    return .edgeFunctionRejected("验证码不正确，请核对邮件中的数字后重试。")
                }
                if message.localizedCaseInsensitiveContains("email") {
                    return .edgeFunctionRejected(message)
                }
            }
        }

        let message = error.localizedDescription
        if message.localizedCaseInsensitiveContains("EMAIL_NOT_VERIFIED") {
            return .edgeFunctionRejected("邮箱尚未完成验证，请输入邮件验证码。")
        }
        if message.contains("23505")
            || message.localizedCaseInsensitiveContains("profiles_bound_email_unique")
            || message.localizedCaseInsensitiveContains("duplicate key") {
            return .edgeFunctionRejected("这个邮箱已被其他账号绑定或注册，请换一个邮箱。")
        }
        return .edgeFunctionRejected(message)
    }

    private func isDuplicateCatalogSuggestion(_ error: Error) -> Bool {
        let message = error.localizedDescription.lowercased()
        return message.contains("23505")
            || message.contains("duplicate key")
            || message.contains("idx_catalog_suggestions_open_unique")
    }

    private nonisolated func isMissingSchemaColumn(_ error: Error, column: String) -> Bool {
        let message = error.localizedDescription
        return message.contains(column) && message.localizedCaseInsensitiveContains("schema cache")
    }

    private nonisolated func isMissingPostPinsTable(_ error: Error) -> Bool {
        let message = error.localizedDescription
        return message.contains("community_post_pins")
            && (
                message.localizedCaseInsensitiveContains("schema cache")
                || message.localizedCaseInsensitiveContains("does not exist")
                || message.localizedCaseInsensitiveContains("not found")
            )
    }

    private nonisolated func backendFeatureSupport(_ feature: BackendFeature) async -> Bool? {
        do {
            return try await SupabaseBackendClient.shared.capabilities().supports(feature)
        } catch {
            CommunityDiagnostics.log.info("Backend capabilities unavailable: \(error.localizedDescription, privacy: .public)")
            return nil
        }
    }

    private nonisolated func backendRPCSupport(_ name: String) async -> Bool? {
        do {
            return try await SupabaseBackendClient.shared.capabilities().supportsRPC(name)
        } catch {
            CommunityDiagnostics.log.info("Backend RPC capability unavailable for \(name, privacy: .public): \(error.localizedDescription, privacy: .public)")
            return nil
        }
    }

    private nonisolated func shouldFallbackToLegacyCommunityFeed(_ error: Error) -> Bool {
        if let functionsError = error as? FunctionsError {
            return shouldFallbackToLegacyCommunityFeed(functionsError)
        }

        return isMissingCommunityFeedCapability(error.localizedDescription)
    }

    private nonisolated func shouldFallbackToLegacyCommunityFeed(_ error: FunctionsError) -> Bool {
        switch error {
        case .relayError:
            return true
        case .httpError(let code, let data):
            let payload = try? JSONDecoder().decode(EdgeFunctionErrorPayload.self, from: data)
            let message = payload?.errorEnvelope?.message
                ?? payload?.error
                ?? String(data: data, encoding: .utf8)
                ?? ""
            return code == 404
                || code == 503
                || isMissingCommunityFeedCapability(message)
        }
    }

    private nonisolated func shouldFallbackToLegacyCommunityMutation(_ error: Error) -> Bool {
        isMissingCommunityFeedCapability(error.localizedDescription)
    }

    nonisolated static func isMissingCommunityFeedCapabilityMessage(_ message: String) -> Bool {
        isMissingCommunityFeedCapability(message)
    }

    private nonisolated static func isMissingCommunityFeedCapability(_ message: String) -> Bool {
        let lowercasedMessage = message.lowercased()
        let capabilityNames = [
            "community-feed",
            "community_feed_v1",
            "community_hot_posts_v1",
            "community_post_summary_v1",
            "toggle_post_like_v1",
            "toggle_post_favorite_v1"
        ]

        guard capabilityNames.contains(where: { lowercasedMessage.contains($0) }) else {
            return false
        }

        return lowercasedMessage.contains("schema cache")
            || lowercasedMessage.contains("does not exist")
            || lowercasedMessage.contains("not found")
            || lowercasedMessage.contains("could not find")
            || lowercasedMessage.contains("404")
            || lowercasedMessage.contains("pgrst202")
    }

    private nonisolated func isMissingCommunityFeedCapability(_ message: String) -> Bool {
        Self.isMissingCommunityFeedCapability(message)
    }

    private nonisolated func mapFunctionsError(_ error: FunctionsError) -> CommunityServiceError {
        let envelope = SupabaseBackendClient.shared.mapFunctionsError(
            error,
            fallbackMessage: "社区函数调用失败，请稍后重试。"
        )
        return .edgeFunctionRejected(envelope.message)
    }

    private func mapCreatePostError(_ error: Error) -> CommunityServiceError {
        mapCommunityMutationError(error, fallback: "帖子发布失败")
    }

    private func mapCommunityMutationError(_ error: Error, fallback: String) -> CommunityServiceError {
        let message = error.localizedDescription
        if message.contains("POST_RATE_LIMIT_EXCEEDED") {
            return .postRateLimitExceeded
        }
        if message.contains("COMMUNITY_USER_MUTED") {
            return .userMuted
        }
        if message.contains("COMMUNITY_PROFILE_REQUIRED") {
            return .missingAuthenticatedUser
        }
        if message.contains("PROFILE_COMPLETION_REQUIRED") {
            return .profileCompletionRequired
        }
        if message.contains("COMMUNITY_TERMS_REQUIRED") {
            return .termsAcceptanceRequired
        }
        if message.contains("CANNOT_LIKE_OWN_POST") {
            return .cannotLikeOwnPost
        }
        if message.contains("COMMUNITY_POST_NOT_FOUND") {
            return .edgeFunctionRejected("内容已不存在或不可见。")
        }
        if message.contains("COMMUNITY_CONTENT_REJECTED") {
            return .contentRejected
        }
        if message.contains("COMMUNITY_POLL_INVALID") {
            return .invalidPoll
        }
        if message.contains("COMMUNITY_POLL_CLOSED") {
            return .pollClosed
        }
        if message.contains("COMMUNITY_POLL_DELETION_PENDING") {
            return .edgeFunctionRejected("删除申请正在审核中。")
        }
        if message.contains("COMMUNITY_POLL_NOT_FOUND") || message.contains("COMMUNITY_POLL_OPTION_NOT_FOUND") {
            return .edgeFunctionRejected("投票已不存在或不可见。")
        }

        return .edgeFunctionRejected("\(fallback)：\(message)")
    }
}

private nonisolated struct EdgeFunctionErrorPayload: Decodable, Sendable {
    let error: String?
    let errorEnvelope: BackendErrorEnvelope?
}

private nonisolated enum CommunityCampusRequestAction: String, Encodable, Sendable {
    case current
    case submitNewSchool = "submit_new_school"
    case selectExisting = "select_existing"
    case requestChange = "request_change"
}

private nonisolated struct CommunityCampusSearchParams: Encodable, Sendable {
    let search: String
    let limit: Int

    enum CodingKeys: String, CodingKey {
        case search = "p_search"
        case limit = "p_limit"
    }
}

private nonisolated struct CommunityCampusRequestSubmitRequest: Encodable, Sendable {
    let action: CommunityCampusRequestAction
    let schoolName: String?
    let campusID: String?

    init(
        action: CommunityCampusRequestAction,
        schoolName: String? = nil,
        campusID: String? = nil
    ) {
        self.action = action
        self.schoolName = schoolName
        self.campusID = campusID
    }

    enum CodingKeys: String, CodingKey {
        case action
        case schoolName = "school_name"
        case campusID = "campus_id"
    }
}

private nonisolated struct CommunityCampusRequestResponse: Decodable, Sendable {
    let profile: CommunityProfile?
    let request: CommunityCampusMembershipRequest?
}

private nonisolated struct CommunityBootstrapRequest: Encodable, Sendable {
    let eduID: String
    let displayName: String
    let campusID: String

    enum CodingKeys: String, CodingKey {
        case eduID = "edu_id"
        case displayName = "display_name"
        case campusID = "campus_id"
    }
}

private nonisolated struct CommunityBootstrapResponse: Decodable, Sendable {
    let profile: CommunityProfile
    let isNewUser: Bool
    let isProfileComplete: Bool

    enum CodingKeys: String, CodingKey {
        case profile
        case isNewUser = "is_new_user"
        case isProfileComplete = "is_profile_complete"
    }
}

private nonisolated struct CommunityFeedResponse: Decodable, Sendable {
    let generatedAt: String?
    let posts: [CommunityPost]

    enum CodingKeys: String, CodingKey {
        case generatedAt = "generated_at"
        case posts
    }
}

private nonisolated struct CommunityProfileStatsRPCParams: Encodable, Sendable {
    let profileIDs: [UUID]

    enum CodingKeys: String, CodingKey {
        case profileIDs = "p_profile_ids"
    }
}

private nonisolated struct CommunityProfileStatsResponse: Decodable, Sendable {
    let generatedAt: String?
    let profiles: [CommunityProfileStats]

    enum CodingKeys: String, CodingKey {
        case generatedAt = "generated_at"
        case profiles
    }
}

private nonisolated struct CommunityProfileAuthLinkRecord: Decodable, Sendable {
    let authUserID: UUID
    let profileID: UUID

    enum CodingKeys: String, CodingKey {
        case authUserID = "auth_user_id"
        case profileID = "profile_id"
    }
}

nonisolated struct CommunityProfileUpdate: Encodable, Sendable {
    let nickname: String
    let avatarPath: String?
    let coverPath: String?
    let bio: String?
    let major: String?
    let grade: String?
    let profileEditedAt: String
    let isProfileComplete: Bool
    let showsEduVerificationBadge: Bool
    let updatedAt: String

    enum CodingKeys: String, CodingKey {
        case nickname
        case avatarPath = "avatar_path"
        case coverPath = "cover_path"
        case bio
        case major
        case grade
        case profileEditedAt = "profile_edited_at"
        case isProfileComplete = "is_profile_complete"
        case showsEduVerificationBadge = "shows_edu_verification_badge"
        case updatedAt = "updated_at"
    }

    func encode(to encoder: Encoder) throws {
        var container = encoder.container(keyedBy: CodingKeys.self)
        try container.encode(nickname, forKey: .nickname)
        try container.encodeIfPresent(avatarPath, forKey: .avatarPath)
        if let coverPath {
            try container.encode(coverPath, forKey: .coverPath)
        } else {
            try container.encodeNil(forKey: .coverPath)
        }
        try container.encodeIfPresent(bio, forKey: .bio)
        try container.encodeIfPresent(major, forKey: .major)
        try container.encodeIfPresent(grade, forKey: .grade)
        try container.encode(profileEditedAt, forKey: .profileEditedAt)
        try container.encode(isProfileComplete, forKey: .isProfileComplete)
        try container.encode(showsEduVerificationBadge, forKey: .showsEduVerificationBadge)
        try container.encode(updatedAt, forKey: .updatedAt)
    }
}

private nonisolated struct CommunityProfileLegacyUpdate: Encodable, Sendable {
    let nickname: String
    let avatarPath: String?
    let bio: String?
    let major: String?
    let grade: String?
    let isProfileComplete: Bool
    let updatedAt: String

    enum CodingKeys: String, CodingKey {
        case nickname
        case avatarPath = "avatar_path"
        case bio
        case major
        case grade
        case isProfileComplete = "is_profile_complete"
        case updatedAt = "updated_at"
    }
}

private nonisolated struct CommunityPendingEmailUpdate: Encodable, Sendable {
    let pendingBoundEmail: String
    let emailVerificationSentAt: String
    let updatedAt: String

    enum CodingKeys: String, CodingKey {
        case pendingBoundEmail = "pending_bound_email"
        case emailVerificationSentAt = "email_verification_sent_at"
        case updatedAt = "updated_at"
    }
}

private nonisolated struct CommunityVerifiedEmailUpdate: Encodable, Sendable {
    let boundEmail: String
    let pendingBoundEmail: String?
    let emailVerificationSentAt: String?
    let updatedAt: String

    enum CodingKeys: String, CodingKey {
        case boundEmail = "bound_email"
        case pendingBoundEmail = "pending_bound_email"
        case emailVerificationSentAt = "email_verification_sent_at"
        case updatedAt = "updated_at"
    }

    func encode(to encoder: Encoder) throws {
        var container = encoder.container(keyedBy: CodingKeys.self)
        try container.encode(boundEmail, forKey: .boundEmail)
        try container.encodeNil(forKey: .pendingBoundEmail)
        try container.encodeNil(forKey: .emailVerificationSentAt)
        try container.encode(updatedAt, forKey: .updatedAt)
    }
}

private nonisolated struct CommunityPostSoftDeleteRPCParams: Encodable, Sendable {
    let targetPostID: UUID

    enum CodingKeys: String, CodingKey {
        case targetPostID = "target_post_id"
    }
}

private nonisolated struct CommunityCommentSoftDeleteRPCParams: Encodable, Sendable {
    let targetCommentID: UUID

    enum CodingKeys: String, CodingKey {
        case targetCommentID = "target_comment_id"
    }
}

private nonisolated struct CommunityTermsAcceptanceRecord: Decodable, Sendable {
    let userID: UUID
    let termsVersion: String
    let acceptedAt: String

    enum CodingKeys: String, CodingKey {
        case userID = "user_id"
        case termsVersion = "terms_version"
        case acceptedAt = "accepted_at"
    }
}

private nonisolated struct CommunityTermsAcceptanceRPCParams: Encodable, Sendable {
    let termsVersion: String

    enum CodingKeys: String, CodingKey {
        case termsVersion = "p_terms_version"
    }
}

private nonisolated struct CommunityPostIDRPCParams: Encodable, Sendable {
    let postID: UUID

    enum CodingKeys: String, CodingKey {
        case postID = "p_post_id"
    }
}

private nonisolated struct CommunityPollIDRPCParams: Encodable, Sendable {
    let pollID: UUID

    enum CodingKeys: String, CodingKey {
        case pollID = "p_poll_id"
    }
}

private nonisolated struct CommunityPollListRPCParams: Encodable, Sendable {
    let limit: Int

    enum CodingKeys: String, CodingKey {
        case limit = "p_limit"
    }
}

private nonisolated struct CommunityRequestPollDeletionRPCParams: Encodable, Sendable {
    let pollID: UUID
    let reason: String?

    enum CodingKeys: String, CodingKey {
        case pollID = "p_poll_id"
        case reason = "p_reason"
    }
}

private nonisolated struct CommunityVotePollRPCParams: Encodable, Sendable {
    let pollID: UUID
    let optionID: UUID

    enum CodingKeys: String, CodingKey {
        case pollID = "p_poll_id"
        case optionID = "p_option_id"
    }
}

private nonisolated struct CommunityCreatePollRPCParams: Encodable, Sendable {
    let question: String
    let detail: String?
    let options: [String]
    let closesAt: String?

    init(input: CreatePollInput) {
        question = String(input.normalizedQuestion.prefix(CommunityPollRules.maxQuestionLength))
        detail = input.normalizedDetail.map { String($0.prefix(CommunityPollRules.maxDetailLength)) }
        options = input.normalizedOptions
            .prefix(CommunityPollRules.maxOptions)
            .map { String($0.prefix(CommunityPollRules.maxOptionLength)) }
        closesAt = input.closesAt
    }

    enum CodingKeys: String, CodingKey {
        case question = "p_question"
        case detail = "p_detail"
        case options = "p_options"
        case closesAt = "p_closes_at"
    }
}

private nonisolated struct CommunityBlockRecord: Decodable, Sendable {
    let blockerID: UUID
    let blockedID: UUID
    let createdAt: String

    enum CodingKeys: String, CodingKey {
        case blockerID = "blocker_id"
        case blockedID = "blocked_id"
        case createdAt = "created_at"
    }
}

private nonisolated struct CommunityReportContentRPCParams: Encodable, Sendable {
    let targetType: CommunityReportTargetType
    let postID: UUID?
    let commentID: UUID?
    let reportedUserID: UUID?
    let reason: String
    let detail: String?

    enum CodingKeys: String, CodingKey {
        case targetType = "p_target_type"
        case postID = "p_post_id"
        case commentID = "p_comment_id"
        case reportedUserID = "p_reported_user_id"
        case reason = "p_reason"
        case detail = "p_detail"
    }
}

private nonisolated struct CommunityBlockUserRPCParams: Encodable, Sendable {
    let blockedID: UUID
    let reason: String?

    enum CodingKeys: String, CodingKey {
        case blockedID = "p_blocked_id"
        case reason = "p_reason"
    }
}

private nonisolated struct CommunityUnblockUserRPCParams: Encodable, Sendable {
    let blockedID: UUID

    enum CodingKeys: String, CodingKey {
        case blockedID = "p_blocked_id"
    }
}

private nonisolated struct CommunityPostRecord: Decodable, Sendable {
    let id: UUID
    let authorID: UUID
    let title: String
    let body: String
    let category: String?
    let isAnonymous: Bool
    let commentCount: Int
    let status: String
    let createdAt: String
    let updatedAt: String

    enum CodingKeys: String, CodingKey {
        case id
        case authorID = "author_id"
        case title
        case body
        case category
        case isAnonymous = "is_anonymous"
        case commentCount = "comment_count"
        case status
        case createdAt = "created_at"
        case updatedAt = "updated_at"
    }
}

private nonisolated struct CommunityPostRateLimitRecord: Decodable, Sendable {
    let id: UUID
}

private nonisolated struct CommunityPollRecord: Decodable, Sendable {
    let id: UUID
    let authorID: UUID
    let question: String
    let detail: String?
    let status: String
    let totalVoteCount: Int
    let closesAt: String?
    let deletionStatus: String
    let deletionRequestedAt: String?
    let deletionReason: String?
    let deletionReviewedAt: String?
    let deletionReviewReason: String?
    let createdAt: String
    let updatedAt: String

    enum CodingKeys: String, CodingKey {
        case id
        case authorID = "author_id"
        case question
        case detail
        case status
        case totalVoteCount = "total_vote_count"
        case closesAt = "closes_at"
        case deletionStatus = "deletion_status"
        case deletionRequestedAt = "deletion_requested_at"
        case deletionReason = "deletion_reason"
        case deletionReviewedAt = "deletion_reviewed_at"
        case deletionReviewReason = "deletion_review_reason"
        case createdAt = "created_at"
        case updatedAt = "updated_at"
    }

    init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        id = try container.decode(UUID.self, forKey: .id)
        authorID = try container.decode(UUID.self, forKey: .authorID)
        question = try container.decode(String.self, forKey: .question)
        detail = try container.decodeIfPresent(String.self, forKey: .detail)
        status = try container.decode(String.self, forKey: .status)
        totalVoteCount = try container.decode(Int.self, forKey: .totalVoteCount)
        closesAt = try container.decodeIfPresent(String.self, forKey: .closesAt)
        deletionStatus = try container.decodeIfPresent(String.self, forKey: .deletionStatus) ?? "none"
        deletionRequestedAt = try container.decodeIfPresent(String.self, forKey: .deletionRequestedAt)
        deletionReason = try container.decodeIfPresent(String.self, forKey: .deletionReason)
        deletionReviewedAt = try container.decodeIfPresent(String.self, forKey: .deletionReviewedAt)
        deletionReviewReason = try container.decodeIfPresent(String.self, forKey: .deletionReviewReason)
        createdAt = try container.decode(String.self, forKey: .createdAt)
        updatedAt = try container.decode(String.self, forKey: .updatedAt)
    }
}

private nonisolated struct CommunityPollVoteRecord: Decodable, Sendable {
    let pollID: UUID
    let optionID: UUID
    let userID: UUID
    let createdAt: String?
    let updatedAt: String?

    enum CodingKeys: String, CodingKey {
        case pollID = "poll_id"
        case optionID = "option_id"
        case userID = "user_id"
        case createdAt = "created_at"
        case updatedAt = "updated_at"
    }
}

private nonisolated struct CommunityPostLikeRecord: Decodable, Sendable {
    let postID: UUID
    let userID: UUID
    let createdAt: String?

    enum CodingKeys: String, CodingKey {
        case postID = "post_id"
        case userID = "user_id"
        case createdAt = "created_at"
    }
}

private nonisolated struct CommunityPostLikeInsert: Encodable, Sendable {
    let postID: UUID
    let userID: UUID
    let createdAt: String

    enum CodingKeys: String, CodingKey {
        case postID = "post_id"
        case userID = "user_id"
        case createdAt = "created_at"
    }
}

private nonisolated struct CommunityPostFavoriteRecord: Decodable, Sendable {
    let postID: UUID
    let userID: UUID
    let createdAt: String?

    enum CodingKeys: String, CodingKey {
        case postID = "post_id"
        case userID = "user_id"
        case createdAt = "created_at"
    }
}

private nonisolated struct CommunityPostFavoriteInsert: Encodable, Sendable {
    let postID: UUID
    let userID: UUID
    let createdAt: String

    enum CodingKeys: String, CodingKey {
        case postID = "post_id"
        case userID = "user_id"
        case createdAt = "created_at"
    }
}

private nonisolated struct CommunityNotificationRecord: Decodable, Sendable {
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
    let dismissedAt: String?

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
        case dismissedAt = "dismissed_at"
    }
}

private nonisolated struct CommunityNotificationSettingsRecord: Decodable, Sendable {
    let userID: UUID
    let mutedAll: Bool
    let updatedAt: String?

    enum CodingKeys: String, CodingKey {
        case userID = "user_id"
        case mutedAll = "muted_all"
        case updatedAt = "updated_at"
    }
}

private nonisolated struct SiteAnnouncementRecord: Decodable, Sendable {
    let id: UUID
    let title: String
    let body: String
    let level: SiteAnnouncementLevel
    let status: String
    let publishedAt: String?
    let expiresAt: String?
    let createdBy: UUID
    let createdAt: String

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
    }
}

private nonisolated struct SiteAnnouncementReadRecord: Decodable, Sendable {
    let announcementID: UUID
    let userID: UUID
    let readAt: String
    let dismissedAt: String?

    enum CodingKeys: String, CodingKey {
        case announcementID = "announcement_id"
        case userID = "user_id"
        case readAt = "read_at"
        case dismissedAt = "dismissed_at"
    }
}

private nonisolated struct CommunityNotificationReadUpdate: Encodable, Sendable {
    let isRead: Bool

    enum CodingKeys: String, CodingKey {
        case isRead = "is_read"
    }
}

private nonisolated struct CommunityNotificationDismissUpdate: Encodable, Sendable {
    let isRead: Bool
    let dismissedAt: String

    enum CodingKeys: String, CodingKey {
        case isRead = "is_read"
        case dismissedAt = "dismissed_at"
    }
}

private nonisolated struct CommunityNotificationSettingsUpsert: Encodable, Sendable {
    let userID: UUID
    let mutedAll: Bool
    let updatedAt: String

    enum CodingKeys: String, CodingKey {
        case userID = "user_id"
        case mutedAll = "muted_all"
        case updatedAt = "updated_at"
    }
}

private nonisolated struct CommunityNotificationRPCParams: Encodable, Sendable {
    let recipientID: UUID
    let actorID: UUID
    let postID: UUID
    let commentID: UUID?
    let type: CommunityNotificationType
    let title: String
    let body: String?

    enum CodingKeys: String, CodingKey {
        case recipientID = "p_recipient_id"
        case actorID = "p_actor_id"
        case postID = "p_post_id"
        case commentID = "p_comment_id"
        case type = "p_type"
        case title = "p_title"
        case body = "p_body"
    }
}

private nonisolated struct SiteAnnouncementReadInsert: Encodable, Sendable {
    let announcementID: UUID
    let userID: UUID
    let readAt: String
    let dismissedAt: String?

    enum CodingKeys: String, CodingKey {
        case announcementID = "announcement_id"
        case userID = "user_id"
        case readAt = "read_at"
        case dismissedAt = "dismissed_at"
    }
}

private nonisolated struct FeedbackSubmissionInsert: Encodable, Sendable {
    let userID: UUID?
    let issueType: String
    let body: String
    let contact: String?
    let deviceInfo: [String: String]

    enum CodingKeys: String, CodingKey {
        case userID = "user_id"
        case issueType = "issue_type"
        case body
        case contact
        case deviceInfo = "device_info"
    }
}

private nonisolated struct CatalogSuggestionInsert: Encodable, Sendable {
    let suggestionType: String
    let userID: UUID?
    let name: String
    let unit: String
    let teacherName: String?
    let category: String?
    let credit: Double?
    let initialStars: Int?
    let note: String?

    enum CodingKeys: String, CodingKey {
        case suggestionType = "suggestion_type"
        case userID = "user_id"
        case name
        case unit
        case teacherName = "teacher_name"
        case category
        case credit
        case initialStars = "initial_stars"
        case note
    }
}

private nonisolated struct TeacherRatingInsert: Encodable, Sendable {
    let teacherID: Int64
    let userID: UUID
    let stars: Int

    enum CodingKeys: String, CodingKey {
        case teacherID = "teacher_id"
        case userID = "user_id"
        case stars
    }
}

private nonisolated struct TeacherRatingStarsUpdate: Encodable, Sendable {
    let stars: Int
}

private nonisolated struct CourseRatingInsert: Encodable, Sendable {
    let courseID: Int64
    let userID: UUID
    let stars: Int

    enum CodingKeys: String, CodingKey {
        case courseID = "course_id"
        case userID = "user_id"
        case stars
    }
}

private nonisolated struct DishRatingInsert: Encodable, Sendable {
    let dishID: Int64
    let userID: UUID
    let stars: Int

    enum CodingKeys: String, CodingKey {
        case dishID = "dish_id"
        case userID = "user_id"
        case stars
    }
}

private nonisolated struct CommunityCreatePostRPCParams: Encodable, Sendable {
    let id: UUID
    let title: String
    let body: String
    let category: String?
    let isAnonymous: Bool
    let hasImages: Bool

    enum CodingKeys: String, CodingKey {
        case id = "p_id"
        case title = "p_title"
        case body = "p_body"
        case category = "p_category"
        case isAnonymous = "p_is_anonymous"
        case hasImages = "p_has_images"
    }
}

private nonisolated struct CommunityPostImageRecord: Decodable, Sendable {
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
    }
}

private nonisolated struct CommunityUploadValidationRequest: Encodable, Sendable {
    let postID: UUID
    let fullPath: String
    let thumbnailPath: String

    enum CodingKeys: String, CodingKey {
        case postID = "post_id"
        case fullPath = "full_path"
        case thumbnailPath = "thumbnail_path"
    }
}

private nonisolated struct CommunityProfileUploadValidationRequest: Encodable, Sendable {
    let kind: String
    let objectPath: String

    enum CodingKeys: String, CodingKey {
        case kind
        case objectPath = "object_path"
    }
}

private nonisolated struct CommunityProfileUploadValidationResponse: Decodable, Sendable {
    let validated: Bool
}

private nonisolated struct CommunityUploadValidationResponse: Decodable, Sendable {
    let receiptID: UUID

    enum CodingKeys: String, CodingKey {
        case receiptID = "receipt_id"
    }
}

private nonisolated struct CommunityAttachPostImageRPCParams: Encodable, Sendable {
    let receiptID: UUID
    let imageID: UUID
    let sortOrder: Int

    enum CodingKeys: String, CodingKey {
        case receiptID = "p_receipt_id"
        case imageID = "p_image_id"
        case sortOrder = "p_sort_order"
    }
}

private nonisolated struct CommunityPublishPostRPCParams: Encodable, Sendable {
    let postID: UUID

    enum CodingKeys: String, CodingKey {
        case postID = "p_post_id"
    }
}

private nonisolated struct CommunityCommentRecord: Decodable, Sendable {
    let id: UUID
    let postID: UUID
    let authorID: UUID
    let body: String
    let isAnonymous: Bool
    let status: String
    let createdAt: String
    let updatedAt: String

    enum CodingKeys: String, CodingKey {
        case id
        case postID = "post_id"
        case authorID = "author_id"
        case body
        case isAnonymous = "is_anonymous"
        case status
        case createdAt = "created_at"
        case updatedAt = "updated_at"
    }
}

private nonisolated struct CommunityCreateCommentRPCParams: Encodable, Sendable {
    let id: UUID
    let postID: UUID
    let body: String
    let isAnonymous: Bool

    enum CodingKeys: String, CodingKey {
        case id = "p_id"
        case postID = "p_post_id"
        case body = "p_body"
        case isAnonymous = "p_is_anonymous"
    }
}
