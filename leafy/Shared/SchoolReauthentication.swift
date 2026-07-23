import SwiftUI
#if canImport(UIKit)
import UIKit
#elseif canImport(AppKit)
import AppKit
#endif

nonisolated enum SchoolReauthentication {
    static func requiresReauthentication(_ error: Error) -> Bool {
        if case SchoolNetworkError.sessionExpired = error {
            return true
        }

        if let urlError = error as? URLError {
            return urlError.code == .userAuthenticationRequired
        }

        let nsError = error as NSError
        return nsError.domain == NSURLErrorDomain &&
            nsError.code == URLError.userAuthenticationRequired.rawValue
    }

    static func shouldPromptForUserInitiatedAccess(_ error: Error) -> Bool {
        if requiresReauthentication(error) {
            return true
        }

        if case SchoolNetworkError.campusNetworkRequired = error {
            return true
        }

        return false
    }

    @MainActor
    static func preflightRequest(
        networkManager: SchoolNetworkManager,
        context: SchoolReauthenticationContext
    ) async -> SchoolReauthenticationRequest? {
        switch await networkManager.preflightAuthenticatedSession() {
        case .authenticated:
            return nil
        case .requiresReauthentication, .networkUnavailable:
            return SchoolReauthenticationRequest(context: context)
        }
    }
}

nonisolated enum SchoolSessionPreflightResult: Equatable, Sendable {
    case authenticated
    case requiresReauthentication
    case networkUnavailable
}

struct SchoolReauthenticationContext: Equatable {
    let portal: SchoolPortal
    let title: String
    let message: String
    let submitTitle: String

    static func timetable(portal: SchoolPortal) -> SchoolReauthenticationContext {
        SchoolReauthenticationContext(
            portal: portal,
            title: "重新登录教务",
            message: "当前教务登录状态已失效，请先连接校园网并重新登录，之后会继续刷新课表。",
            submitTitle: "登录并刷新课表"
        )
    }

    static let grades = SchoolReauthenticationContext(
        portal: .undergraduate,
        title: "重新登录教务",
        message: "当前教务登录状态已失效，请先连接校园网并重新登录，之后会继续刷新成绩。",
        submitTitle: "登录并刷新成绩"
    )

    static let examSchedule = SchoolReauthenticationContext(
        portal: .undergraduate,
        title: "重新登录教务",
        message: "当前教务登录状态已失效，请先连接校园网并重新登录，之后会继续刷新考试安排。",
        submitTitle: "登录并刷新考试"
    )

    static let teachingPlan = SchoolReauthenticationContext(
        portal: .undergraduate,
        title: "重新登录教务",
        message: "当前教务登录状态已失效，请先连接校园网并重新登录，之后会继续刷新教学计划。",
        submitTitle: "登录并刷新计划"
    )

    static let trainingProgram = SchoolReauthenticationContext(
        portal: .undergraduate,
        title: "重新登录教务",
        message: "当前教务登录状态已失效，请先连接校园网并重新登录，之后会继续刷新培养方案。",
        submitTitle: "登录并刷新方案"
    )

    static let emptyClassrooms = SchoolReauthenticationContext(
        portal: .undergraduate,
        title: "重新登录教务",
        message: "当前教务登录状态已失效，请先连接校园网并重新登录，之后会继续刚才的空教室查询。",
        submitTitle: "登录并继续查询"
    )

    static let campusHeatmap = SchoolReauthenticationContext(
        portal: .undergraduate,
        title: "重新登录教务",
        message: "请先连接校园网并重新登录，之后会抓取所选日期和节次的空闲教室数据。",
        submitTitle: "登录并更新数据"
    )

    static let schoolDataSync = SchoolReauthenticationContext(
        portal: .undergraduate,
        title: "重新登录教务",
        message: "当前教务登录状态已失效，请先连接校园网并重新登录，之后会重新同步本次教务数据。",
        submitTitle: "登录并继续同步"
    )
}

struct SchoolReauthenticationRequest: Identifiable {
    let id = UUID()
    let context: SchoolReauthenticationContext
}

extension View {
    func schoolReauthenticationSheet(
        request: Binding<SchoolReauthenticationRequest?>,
        networkManager: SchoolNetworkManager,
        onAuthenticated: @escaping (SchoolReauthenticationContext) -> Void
    ) -> some View {
        sheet(item: request) { item in
            SchoolReauthenticationSheet(
                networkManager: networkManager,
                context: item.context
            ) {
                request.wrappedValue = nil
                onAuthenticated(item.context)
            }
            .presentationDetents([.large])
        }
    }
}

private struct SchoolReauthenticationSheet: View {
    @Environment(\.dismiss) private var dismiss
    @Environment(\.leafyControlScale) private var leafyControlScale
    @Environment(\.leafyLanguage) private var leafyLanguage

    @ObservedObject private var networkManager: SchoolNetworkManager

    let context: SchoolReauthenticationContext
    let onAuthenticated: () -> Void

    @State private var account: String
    @State private var password = ""
    @State private var captchaCode = ""
    @State private var captchaKey = ""
    @State private var captchaImage: UIImage?
    @State private var isPasswordVisible = false
    @State private var isCaptchaLoading = false
    @State private var isLoggingIn = false
    @State private var errorMessage: String?

    private var canSubmit: Bool {
        !isLoggingIn &&
        !account.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty &&
        !password.isEmpty &&
        !captchaCode.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
    }

    init(
        networkManager: SchoolNetworkManager,
        context: SchoolReauthenticationContext,
        onAuthenticated: @escaping () -> Void
    ) {
        _networkManager = ObservedObject(wrappedValue: networkManager)
        _account = State(initialValue: networkManager.authenticatedEduID ?? "")
        self.context = context
        self.onAuthenticated = onAuthenticated
    }

    var body: some View {
        NavigationStack {
            ScrollView {
                VStack(alignment: .leading, spacing: AppSpacing.card) {
                    VStack(alignment: .leading, spacing: 8) {
                        Text(L10n.text(context.title, language: leafyLanguage))
                            .leafyTitle3()
                            .foregroundStyle(AppTheme.primaryText)
                        Text(L10n.text(context.message, language: leafyLanguage))
                            .leafyBody()
                            .foregroundStyle(AppTheme.secondaryText)
                        Text(L10n.text(context.portal.loginHint, language: leafyLanguage))
                            .microCaption()
                            .foregroundStyle(AppTheme.tertiaryText)
                    }

                    VStack(spacing: 0) {
                        TextField(L10n.text("学号", language: leafyLanguage), text: $account)
                            .leafyDisableAutocapitalization()
                            .autocorrectionDisabled()
                            .leafyUsernameContentType()
                            .padding(.horizontal, 16 * leafyControlScale)
                            .frame(height: 52 * leafyControlScale)

                        Divider()
                            .padding(.leading, 16 * leafyControlScale)

                        HStack(spacing: 12) {
                            Group {
                                if isPasswordVisible {
                                    TextField(L10n.text("密码", language: leafyLanguage), text: $password)
                                } else {
                                    SecureField(L10n.text("密码", language: leafyLanguage), text: $password)
                                }
                            }
                            .leafyDisableAutocapitalization()
                            .autocorrectionDisabled()
                            .leafyPasswordContentType()

                            Button {
                                isPasswordVisible.toggle()
                            } label: {
                                Image(systemName: isPasswordVisible ? "eye.slash" : "eye")
                                    .frame(width: 34 * leafyControlScale, height: 34 * leafyControlScale)
                            }
                            .buttonStyle(.plain)
                            .foregroundStyle(AppTheme.secondaryText)
                            .accessibilityLabel(isPasswordVisible ? L10n.text("隐藏密码", language: leafyLanguage) : L10n.text("显示密码", language: leafyLanguage))
                        }
                        .padding(.horizontal, 16 * leafyControlScale)
                        .frame(height: 52 * leafyControlScale)

                        Divider()
                            .padding(.leading, 16 * leafyControlScale)

                        HStack(spacing: 12) {
                            TextField(L10n.text("验证码", language: leafyLanguage), text: $captchaCode)
                                .leafyDisableAutocapitalization()
                                .autocorrectionDisabled()
                                .leafyOneTimeCodeContentType()

                            Button {
                                Task { await fetchCaptcha(resetError: true) }
                            } label: {
                                ZStack {
                                    if let captchaImage {
                                        Image(uiImage: captchaImage)
                                            .resizable()
                                            .interpolation(.none)
                                            .scaledToFill()
                                    } else if isCaptchaLoading {
                                        ProgressView()
                                    } else {
                                        Image(systemName: "arrow.clockwise")
                                            .font(.system(size: 14 * leafyControlScale, weight: .semibold))
                                            .foregroundStyle(AppTheme.accent)
                                    }
                                }
                                .frame(width: 112 * leafyControlScale, height: 38 * leafyControlScale)
                                .clipShape(RoundedRectangle(cornerRadius: AppRadius.small, style: .continuous))
                            }
                            .buttonStyle(.plain)
                            .disabled(isCaptchaLoading)
                            .leafyGlassSurface(
                                in: RoundedRectangle(cornerRadius: AppRadius.small, style: .continuous),
                                isInteractive: true
                            )
                            .accessibilityLabel(L10n.text("刷新验证码", language: leafyLanguage))
                        }
                        .padding(.leading, 16 * leafyControlScale)
                        .padding(.trailing, 14 * leafyControlScale)
                        .frame(height: 52 * leafyControlScale)
                    }
                    .leafyCardStyle()

                    if let errorMessage {
                        Text(errorMessage)
                            .leafyBody()
                            .foregroundStyle(AppTheme.danger)
                    }

                    Button {
                        Task { await submitLogin() }
                    } label: {
                        HStack(spacing: 8) {
                            if isLoggingIn {
                                ProgressView()
                                    .tint(.white)
                            }
                            Text(L10n.text(context.submitTitle, language: leafyLanguage))
                                .font(.subheadline.weight(.semibold))
                        }
                        .frame(maxWidth: .infinity)
                        .padding(.vertical, 12)
                        .foregroundStyle(.white)
                        .background(Capsule().fill(canSubmit ? AppTheme.accent : AppTheme.tertiaryText))
                    }
                    .buttonStyle(.plain)
                    .disabled(!canSubmit)
                }
                .padding(AppSpacing.page)
            }
            .background(LeafyPageBackground())
            .navigationTitle(L10n.text(context.portal.title, language: leafyLanguage))
            .leafyInlineNavigationTitle()
            .toolbar {
                ToolbarItem(placement: .leafyTrailing) {
                    Button(L10n.text("取消", language: leafyLanguage)) {
                        clearSensitiveFields()
                        dismiss()
                    }
                }
            }
            .task {
                await fetchCaptcha(resetError: true)
            }
        }
    }

    @MainActor
    private func fetchCaptcha(resetError: Bool) async {
        guard !isCaptchaLoading else { return }
        isCaptchaLoading = true
        defer { isCaptchaLoading = false }

        do {
            let captcha = try await networkManager.fetchCaptcha(for: context.portal)
            captchaKey = captcha.key
            captchaImage = captcha.image
            captchaCode = ""
            if resetError {
                errorMessage = nil
            }
        } catch {
            captchaKey = ""
            captchaImage = nil
            if case SchoolNetworkError.campusNetworkRequired = error {
                errorMessage = L10n.text(
                    "暂时无法连接教务验证码。请先连接 bjfu-wifi 或北林 VPN，再点击验证码区域重试。",
                    language: leafyLanguage
                )
            } else {
                errorMessage = error.localizedDescription
            }
        }
    }

    @MainActor
    private func submitLogin() async {
        guard canSubmit else { return }
        isLoggingIn = true
        defer { isLoggingIn = false }

        do {
            let didLogin = try await networkManager.performLogin(
                account: account,
                password: password,
                captcha: captchaCode,
                key: captchaKey,
                portal: context.portal
            )

            guard didLogin else {
                errorMessage = L10n.text("登录请求已发送，但未能确认登录成功。请重试。", language: leafyLanguage)
                captchaCode = ""
                await fetchCaptcha(resetError: false)
                return
            }

            networkManager.isLoggedIn = true
            clearSensitiveFields()
            dismiss()
            onAuthenticated()
        } catch {
            errorMessage = error.localizedDescription
            captchaCode = ""
            await fetchCaptcha(resetError: false)
        }
    }

    private func clearSensitiveFields() {
        password = ""
        captchaCode = ""
        captchaKey = ""
    }
}
