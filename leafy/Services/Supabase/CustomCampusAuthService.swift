import Foundation
import Supabase

enum CustomCampusAuthError: LocalizedError {
    case invalidEmail
    case passwordTooShort
    case invalidCode
    case expiredCode
    case emailNotConfirmed(String)
    case invalidCredentials
    case emailRateLimited
    case emailProviderDisabled
    case signupDisabled
    case userAlreadyExists
    case weakPassword(String)
    case codeSendFailed
    case callbackLinkInvalid
    case callbackNeedsOriginalDevice
    case missingSession

    var errorDescription: String? {
        switch self {
        case .invalidEmail:
            return "请输入有效的邮箱地址。"
        case .passwordTooShort:
            return "密码至少需要 8 位。"
        case .invalidCode:
            return "验证码不正确，请核对邮件中的数字后重试。"
        case .expiredCode:
            return "验证码已失效，请重新发送验证码。"
        case .emailNotConfirmed(let email):
            return "\(email) 还没有完成邮箱验证。请切换到注册，重新发送验证码并完成验证。"
        case .invalidCredentials:
            return "邮箱或密码不正确。如果是第一次使用，请先注册并完成邮箱验证码。"
        case .emailRateLimited:
            return "验证码发送太频繁，请稍后再试。"
        case .emailProviderDisabled:
            return "当前 Supabase 项目未启用邮箱登录，请先在后台开启 Email Auth。"
        case .signupDisabled:
            return "当前 Supabase 项目未开放邮箱验证码注册。"
        case .userAlreadyExists:
            return "这个邮箱已经注册。请切换到登录；如果还没完成验证，可以在注册页重新发送验证码。"
        case .weakPassword(let message):
            return "密码强度不足：\(message)"
        case .codeSendFailed:
            return "验证码邮件发送失败，请稍后重试。"
        case .callbackLinkInvalid:
            return "这个邮箱验证链接已失效或已经使用过。请回到 App 输入验证码，或使用邮箱和密码登录。"
        case .callbackNeedsOriginalDevice:
            return "这个验证链接需要在发起注册的设备上完成。请回到 App 输入验证码，或使用邮箱和密码登录。"
        case .missingSession:
            return "登录会话未建立，请稍后重试。"
        }
    }
}

struct CustomCampusAuthSession: Equatable, Sendable {
    let authUserID: UUID
    let email: String

    var campusIdentity: CampusIdentity {
        CampusIdentity(
            campusID: .custom,
            eduID: authUserID.uuidString,
            displayName: email,
            portal: .undergraduate,
            kind: .customSupabase
        )
    }
}

struct CustomCampusAuthService: Sendable {
    private let clientProvider: @Sendable () throws -> SupabaseClient

    init(clientProvider: @escaping @Sendable () throws -> SupabaseClient = {
        try LeafySupabase.shared.requireClient()
    }) {
        self.clientProvider = clientProvider
    }

    func signIn(email: String, password: String) async throws -> CustomCampusAuthSession {
        let credentials = try validatedCredentials(email: email, password: password)
        do {
            let session = try await clientProvider().auth.signIn(email: credentials.email, password: credentials.password)
            return CustomCampusAuthSession(session: session, fallbackEmail: credentials.email)
        } catch {
            throw Self.mapAuthError(error, email: credentials.email)
        }
    }

    func sendSignUpCode(email: String, password: String) async throws {
        let credentials = try validatedCredentials(email: email, password: password)
        do {
            try await clientProvider().auth.signInWithOTP(
                email: credentials.email,
                redirectTo: LeafySupabase.authCallbackURL,
                shouldCreateUser: true
            )
        } catch {
            throw Self.mapAuthError(error, email: credentials.email)
        }
    }

    func resendSignUpCode(email: String) async throws {
        let email = try validatedEmail(email)
        do {
            try await clientProvider().auth.resend(
                email: email,
                type: .signup,
                emailRedirectTo: LeafySupabase.authCallbackURL
            )
        } catch {
            throw Self.mapAuthError(error, email: email)
        }
    }

    func verifySignUpCode(email: String, password: String, code: String) async throws -> CustomCampusAuthSession {
        let email = try validatedEmail(email)
        let password = try validatedCredentials(email: email, password: password).password
        let code = try validatedCode(code)
        do {
            let response = try await clientProvider().auth.verifyOTP(
                email: email,
                token: code,
                type: .magiclink,
                redirectTo: LeafySupabase.authCallbackURL
            )
            guard let session = response.session else {
                throw CustomCampusAuthError.missingSession
            }
            _ = try await clientProvider().auth.update(user: UserAttributes(password: password))
            return CustomCampusAuthSession(session: session, fallbackEmail: email)
        } catch {
            throw Self.mapAuthError(error, email: email)
        }
    }

    func restoreSession(from url: URL) async throws -> CustomCampusAuthSession? {
        guard CustomCampusAuthCallback.isCallback(url) else {
            return nil
        }

        do {
            let session = try await clientProvider().auth.session(from: url)
            return CustomCampusAuthSession(session: session)
        } catch {
            throw Self.mapCallbackError(error)
        }
    }

    private func validatedEmail(_ email: String) throws -> String {
        let trimmedEmail = email.trimmingCharacters(in: .whitespacesAndNewlines).lowercased()
        guard Self.isValidEmail(trimmedEmail) else {
            throw CustomCampusAuthError.invalidEmail
        }
        return trimmedEmail
    }

    private func validatedCredentials(email: String, password: String) throws -> (email: String, password: String) {
        let trimmedEmail = try validatedEmail(email)
        guard password.count >= 8 else {
            throw CustomCampusAuthError.passwordTooShort
        }
        return (trimmedEmail, password)
    }

    private func validatedCode(_ code: String) throws -> String {
        let trimmedCode = Self.normalizedCode(code)
        guard !trimmedCode.isEmpty else {
            throw CustomCampusAuthError.invalidCode
        }
        return trimmedCode
    }

    private static func isValidEmail(_ email: String) -> Bool {
        let pattern = #"^[A-Z0-9._%+-]+@[A-Z0-9.-]+\.[A-Z]{2,}$"#
        return email.range(of: pattern, options: [.regularExpression, .caseInsensitive]) != nil
    }

    private static func normalizedCode(_ code: String) -> String {
        code.filter(\.isNumber)
    }

    static func normalizeCodeForTesting(_ code: String) -> String {
        normalizedCode(code)
    }

    static func mapAuthErrorForTesting(_ error: Error, email: String = "user@example.com") -> Error {
        mapAuthError(error, email: email)
    }

    static func mapCallbackErrorForTesting(_ error: Error) -> Error {
        mapCallbackError(error)
    }

    private static func mapAuthError(_ error: Error, email: String) -> Error {
        guard let authError = error as? AuthError else {
            return error
        }

        switch authError.errorCode {
        case .emailNotConfirmed:
            return CustomCampusAuthError.emailNotConfirmed(email)
        case .invalidCredentials:
            return CustomCampusAuthError.invalidCredentials
        case .otpExpired:
            return CustomCampusAuthError.expiredCode
        case .overEmailSendRateLimit, .overRequestRateLimit:
            return CustomCampusAuthError.emailRateLimited
        case .emailProviderDisabled:
            return CustomCampusAuthError.emailProviderDisabled
        case .signupDisabled:
            return CustomCampusAuthError.signupDisabled
        case .userAlreadyExists, .emailExists:
            return CustomCampusAuthError.userAlreadyExists
        case .weakPassword:
            return CustomCampusAuthError.weakPassword(authError.message)
        default:
            if authError.message.localizedCaseInsensitiveContains("otp")
                || authError.message.localizedCaseInsensitiveContains("token")
                || authError.message.localizedCaseInsensitiveContains("code") {
                return CustomCampusAuthError.invalidCode
            }
            return error
        }
    }

    private static func mapCallbackError(_ error: Error) -> Error {
        guard let authError = error as? AuthError else {
            return error
        }

        switch authError.errorCode {
        case .otpExpired:
            return CustomCampusAuthError.callbackLinkInvalid
        case .badCodeVerifier, .flowStateNotFound, .flowStateExpired:
            return CustomCampusAuthError.callbackNeedsOriginalDevice
        default:
            if let mappedPKCEError = mapPKCECallbackError(authError) {
                return mappedPKCEError
            }
            if authError.message.localizedCaseInsensitiveContains("invalid")
                || authError.message.localizedCaseInsensitiveContains("expired") {
                return CustomCampusAuthError.callbackLinkInvalid
            }
            return error
        }
    }

    private static func mapPKCECallbackError(_ error: AuthError) -> CustomCampusAuthError? {
        guard case .pkceGrantCodeExchange(let message, _, let code) = error else {
            return nil
        }

        switch ErrorCode(code ?? "") {
        case .otpExpired:
            return .callbackLinkInvalid
        case .badCodeVerifier, .flowStateNotFound, .flowStateExpired:
            return .callbackNeedsOriginalDevice
        default:
            if message.localizedCaseInsensitiveContains("expired")
                || message.localizedCaseInsensitiveContains("invalid") {
                return .callbackLinkInvalid
            }
            if message.localizedCaseInsensitiveContains("code verifier")
                || message.localizedCaseInsensitiveContains("flow state") {
                return .callbackNeedsOriginalDevice
            }
            return nil
        }
    }
}

extension CustomCampusAuthSession {
    init(session: Session, fallbackEmail: String? = nil) {
        self.init(
            authUserID: session.user.id,
            email: session.user.email ?? fallbackEmail ?? session.user.id.uuidString
        )
    }
}

nonisolated enum CustomCampusAuthCallback {
    static func isCallback(_ url: URL) -> Bool {
        url.scheme == LeafySupabase.authCallbackURL.scheme
            && url.host == LeafySupabase.authCallbackURL.host
            && url.path == LeafySupabase.authCallbackURL.path
    }
}

@MainActor
extension SchoolNetworkManager {
    func persistCustomCampusAuthSession(_ session: CustomCampusAuthSession) {
        let identity = session.campusIdentity
        CampusIdentityStore.activate(identity)
        currentPortal = .undergraduate
        authenticatedEduID = identity.eduID
        authenticatedDisplayName = session.email
        isLoggedIn = true
    }
}
