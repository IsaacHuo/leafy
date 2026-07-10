import Combine
import Foundation
import OSLog
import Supabase
import SwiftUI

@MainActor
final class CommunitySessionManager: ObservableObject {
    static let shared = CommunitySessionManager()

    @Published private(set) var profile: CommunityProfile?
    @Published private(set) var isBootstrapping = false
    @Published var bootstrapError: String?

    private let service = CommunityService.shared
    private var activeBootstrapTask: Task<Void, Never>?
    private static let bootstrapTimeoutMessage = "社区身份初始化超时。请检查网络或稍后重试；帖子列表仍可浏览。"

    private init() {}

    var currentUserID: UUID? {
        profile?.id
    }

    private var currentAuthUserID: UUID? {
        LeafySupabase.shared.client?.auth.currentUser?.id
    }

    var requiresProfileCompletion: Bool {
        guard let profile else { return true }
        return !profile.isProfileComplete || profile.nickname.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
    }

    var communityAccessStatus: CommunityAccessStatus {
        profile?.communityAccessStatus ?? .general
    }

    var hasApprovedCommunityAccess: Bool {
        if ActiveCampusContext.descriptor.id == .bjfu && ActiveCampusContext.identity?.isCustom != true {
            return true
        }
        return profile?.hasApprovedCommunityAccess ?? false
    }

    func restoreProfileIfPossible() async {
        CommunityDiagnostics.log.info("Community session restore requested")
        guard currentAuthUserID != nil else {
            CommunityDiagnostics.log.info("Community session restore skipped: no auth user")
            profile = nil
            return
        }

        if profile != nil {
            CommunityDiagnostics.log.info("Community session restore skipped: profile already loaded")
            return
        }

        do {
            profile = try await service.fetchCurrentProfile()
            bootstrapError = nil
            CommunityDiagnostics.log.info("Community session restore finished; hasProfile=\((self.profile != nil), privacy: .public)")
        } catch {
            bootstrapError = error.localizedDescription
            CommunityDiagnostics.log.error("Community session restore failed: \(error.localizedDescription, privacy: .public)")
        }
    }

    func bootstrapCommunityUser(force: Bool = false) async {
        CommunityDiagnostics.log.info("Community bootstrap requested force=\(force, privacy: .public)")
        if let activeBootstrapTask {
            await waitForBootstrapTask(activeBootstrapTask)
            return
        }

        let task = Task { @MainActor in
            await self.performBootstrapCommunityUser(force: force)
        }
        activeBootstrapTask = task
        await waitForBootstrapTask(task)
    }

    func startBootstrapIfNeeded(force: Bool = false) {
        CommunityDiagnostics.log.info("Community bootstrap startIfNeeded requested force=\(force, privacy: .public)")
        guard activeBootstrapTask == nil else { return }

        let eduID = ActiveCampusContext.networkManager.authenticatedEduID?.trimmingCharacters(in: .whitespacesAndNewlines) ?? ""
        let campusID = bootstrapCampusID
        if !force,
           let profile,
           matchesCurrentBootstrap(profile: profile, eduID: eduID, campusID: campusID) {
            bootstrapError = nil
            return
        }

        let task = Task { @MainActor in
            await self.performBootstrapCommunityUser(force: force)
        }
        activeBootstrapTask = task

        Task { @MainActor in
            await self.waitForBootstrapTask(task)
        }
    }

    private func waitForBootstrapTask(_ task: Task<Void, Never>) async {
        do {
            try await CommunityTimeout.run(
                seconds: 25,
                message: Self.bootstrapTimeoutMessage
            ) {
                await task.value
            }
        } catch {
            task.cancel()
            activeBootstrapTask = nil
            isBootstrapping = false
            bootstrapError = error.localizedDescription
            CommunityDiagnostics.log.error("Community bootstrap wait failed: \(error.localizedDescription, privacy: .public)")
        }
    }

    private func performBootstrapCommunityUser(force: Bool) async {
        guard !Task.isCancelled else { return }
        CommunityDiagnostics.log.info("Community bootstrap started force=\(force, privacy: .public)")
        isBootstrapping = true
        defer {
            isBootstrapping = false
            activeBootstrapTask = nil
        }

        do {
            try await CommunityTimeout.run(
                seconds: 12,
                message: Self.bootstrapTimeoutMessage
            ) { [service] in
                try await service.ensureAnonymousSession()
            }
            guard !Task.isCancelled else { return }

            guard currentAuthUserID != nil else {
                profile = nil
                bootstrapError = CommunityServiceError.missingAuthenticatedUser.localizedDescription
                CommunityDiagnostics.log.error("Community bootstrap failed: missing authenticated user")
                return
            }

            let schoolManager = ActiveCampusContext.networkManager
            let eduID = schoolManager.authenticatedEduID?.trimmingCharacters(in: .whitespacesAndNewlines) ?? ""
            guard !eduID.isEmpty else {
                self.profile = nil
                bootstrapError = CommunityServiceError.schoolSessionMissing.localizedDescription
                CommunityDiagnostics.log.error("Community bootstrap failed: missing school session")
                return
            }

            let campusID = bootstrapCampusID
            if !force, let profile, matchesCurrentBootstrap(profile: profile, eduID: eduID, campusID: campusID) {
                bootstrapError = nil
                return
            }

            let profile = try await CommunityTimeout.run(
                seconds: 12,
                message: Self.bootstrapTimeoutMessage
            ) { [service] in
                try await service.bootstrapCommunityUser(
                    eduID: eduID,
                    displayName: schoolManager.authenticatedDisplayName ?? eduID,
                    campusID: campusID
                )
            }
            guard !Task.isCancelled else { return }

            self.profile = profile
            self.bootstrapError = nil
            CommunityDiagnostics.log.info("Community bootstrap finished for profile \(profile.id.uuidString, privacy: .public)")
        } catch {
            self.bootstrapError = error.localizedDescription
            CommunityDiagnostics.log.error("Community bootstrap failed: \(error.localizedDescription, privacy: .public)")
        }
    }

    private var bootstrapCampusID: String {
        ActiveCampusContext.identity?.isCustom == true ? "general" : ActiveCampusContext.descriptor.id.rawValue
    }

    private func matchesCurrentBootstrap(profile: CommunityProfile, eduID: String, campusID: String) -> Bool {
        guard profile.eduID == eduID else { return false }
        if profile.campusID == campusID { return true }
        return ActiveCampusContext.identity?.isCustom == true && profile.hasApprovedCommunityAccess
    }

    func signOut() async {
        if let client = LeafySupabase.shared.client {
            try? await client.auth.signOut()
        }

        profile = nil
        bootstrapError = nil
    }

    func cancelInFlightWork() {
        activeBootstrapTask?.cancel()
        activeBootstrapTask = nil
        isBootstrapping = false
    }

    @discardableResult
    func updateProfile(
        input: CommunityProfileUpdateInput,
        avatar: CommunityImageUpload?,
        cover: CommunityImageUpload? = nil,
        resetCoverToDefault: Bool = false
    ) async throws -> CommunityProfile {
        let updatedProfile = try await service.updateProfile(
            input: input,
            avatar: avatar,
            cover: cover,
            resetCoverToDefault: resetCoverToDefault
        )
        profile = updatedProfile
        bootstrapError = nil
        return updatedProfile
    }

    func requestEmailVerification(input: CommunityEmailBindingInput) async throws {
        let updatedProfile = try await service.requestEmailVerification(input: input)
        profile = updatedProfile
        bootstrapError = nil
    }

    func verifyEmailBinding(input: CommunityEmailVerificationInput) async throws {
        let updatedProfile = try await service.verifyEmailBinding(input: input)
        profile = updatedProfile
        bootstrapError = nil
    }

    func verifyEmailBinding(email: String, code: String) async throws {
        try await verifyEmailBinding(input: CommunityEmailVerificationInput(email: email, code: code))
    }

    @discardableResult
    func submitCampusMembershipRequest(schoolName: String) async throws -> CommunityProfile {
        let updatedProfile = try await service.submitCampusMembershipRequest(schoolName: schoolName)
        profile = updatedProfile
        bootstrapError = nil
        return updatedProfile
    }

    func searchCommunityCampuses(query: String, limit: Int = 20) async throws -> [CommunityCampusOption] {
        try await service.searchCommunityCampuses(query: query, limit: limit)
    }

    @discardableResult
    func selectCommunityCampus(campusID: String) async throws -> CommunityProfile {
        let updatedProfile = try await service.selectCommunityCampus(campusID: campusID)
        profile = updatedProfile
        bootstrapError = nil
        return updatedProfile
    }

    func fetchCurrentCampusMembershipRequest() async throws -> CommunityCampusMembershipRequest? {
        try await service.fetchCurrentCampusMembershipRequest()
    }

    @discardableResult
    func submitCommunitySchoolChangeRequest(campusID: String) async throws -> CommunityCampusMembershipRequest {
        let request = try await service.submitCommunitySchoolChangeRequest(campusID: campusID)
        if let updatedProfile = try await service.fetchCurrentProfile() {
            profile = updatedProfile
        }
        bootstrapError = nil
        return request
    }
}

nonisolated enum CommunityTimeout {
    static func run<T: Sendable>(
        seconds: TimeInterval,
        message: String,
        operation: @Sendable @escaping () async throws -> T
    ) async throws -> T {
        try await withCheckedThrowingContinuation { continuation in
            let state = CommunityTimeoutState(continuation: continuation)
            let operationTask = Task.detached {
                do {
                    state.resume(.success(try await operation()))
                } catch {
                    state.resume(.failure(error))
                }
            }

            Task.detached {
                try? await Task.sleep(for: .seconds(seconds))
                operationTask.cancel()
                state.resume(.failure(CommunityServiceError.edgeFunctionRejected(message)))
            }
        }
    }
}

private nonisolated final class CommunityTimeoutState<T: Sendable>: @unchecked Sendable {
    private let lock = NSLock()
    private var continuation: CheckedContinuation<T, Error>?

    init(continuation: CheckedContinuation<T, Error>) {
        self.continuation = continuation
    }

    func resume(_ result: Result<T, Error>) {
        lock.lock()
        let continuation = continuation
        self.continuation = nil
        lock.unlock()

        continuation?.resume(with: result)
    }
}
