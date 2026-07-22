import SwiftUI

struct ProfileEmailBindingView: View {
    @Environment(\.leafyLanguage) private var leafyLanguage
    @ObservedObject private var sessionManager = CommunitySessionManager.shared

    @State private var email = ""
    @State private var code = ""
    @State private var hasEditedEmail = false
    @State private var isSendingCode = false
    @State private var isVerifyingCode = false
    @State private var cooldownRemaining = 0
    @State private var cooldownTask: Task<Void, Never>?
    @State private var alertMessage: String?

    private let cooldownSeconds = 60

    private var profile: CommunityProfile? {
        sessionManager.profile
    }

    private var normalizedEmail: String {
        CommunityEmailBinding.normalizedEmail(email)
    }

    private var normalizedCode: String {
        CommunityEmailBinding.normalizedCode(code)
    }

    private var isRequestedEmailAlreadyBound: Bool {
        CommunityEmailBinding.isAlreadyBound(
            boundEmail: profile?.boundEmail,
            requestedEmail: normalizedEmail
        )
    }

    private var canSendCode: Bool {
        !isSendingCode
            && cooldownRemaining == 0
            && !normalizedEmail.isEmpty
            && !isVerifyingCode
            && !isRequestedEmailAlreadyBound
    }

    private var canVerifyCode: Bool {
        !isVerifyingCode
            && !isSendingCode
            && !normalizedEmail.isEmpty
            && CommunityEmailBinding.isCompleteVerificationCode(normalizedCode)
    }

    var body: some View {
        List {
            Section("用途") {
                purposeRow(icon: "exclamationmark.triangle.fill", title: "服务异常通知", detail: "服务器、数据库或关键服务异常时，可通过邮箱联系你。")
                purposeRow(icon: "envelope.badge.fill", title: "重要消息补充", detail: "当 App 内通知不可靠或需要补充说明时，邮箱会作为备用通知方式。")
                purposeRow(icon: "lock.shield.fill", title: "登录方式不变", detail: "邮箱仅用于接收通知；北林登录仍使用学号、教务密码和教务验证码。")
            }
            .listRowBackground(AppTheme.cardBackground)

            Section {
                statusRow
            } header: {
                Text("当前状态")
            } footer: {
                Text(statusFooter)
            }
            .listRowBackground(AppTheme.cardBackground)

            Section {
                TextField("邮箱", text: $email)
                    .keyboardType(.emailAddress)
                    .textContentType(.emailAddress)
                    .textInputAutocapitalization(.never)
                    .autocorrectionDisabled()
                    .onChange(of: email) { _, _ in
                        hasEditedEmail = true
                    }

                HStack(spacing: 12) {
                    TextField("8 位邮箱验证码", text: $code)
                        .textContentType(.oneTimeCode)
                        .keyboardType(.numberPad)
                        .onChange(of: code) { _, newValue in
                            let normalized = CommunityEmailBinding.normalizedCode(newValue)
                            if normalized != newValue {
                                code = normalized
                            }
                        }

                    Button {
                        Task { await sendCode() }
                    } label: {
                        if isSendingCode {
                            ProgressView()
                        } else {
                            Label(sendCodeButtonTitle, systemImage: "paperplane")
                        }
                    }
                    .buttonStyle(.plain)
                    .foregroundStyle(AppTheme.accent)
                    .font(.system(size: 13, weight: .semibold))
                    .disabled(!canSendCode)
                    .accessibilityLabel(sendCodeButtonTitle)
                }

                Button {
                    Task { await verifyCode() }
                } label: {
                    HStack(spacing: 8) {
                        if isVerifyingCode {
                            ProgressView()
                        }
                        Text(isVerifyingCode ? "验证中" : "完成绑定")
                            .frame(maxWidth: .infinity)
                    }
                }
                .buttonStyle(.borderedProminent)
                .tint(AppTheme.accent)
                .disabled(!canVerifyCode)
            } header: {
                Text("绑定邮箱")
            } footer: {
                Text("请输入 \(AppBrand.displayName) 邮件中的 8 位验证码。国内邮箱可能需要等待数分钟，请也检查垃圾箱。")
            }
            .listRowBackground(AppTheme.cardBackground)
        }
        .leafyInsetGroupedListStyle()
        .scrollContentBackground(.hidden)
        .background(LeafyPageBackground())
        .navigationTitle("绑定邮箱")
        .navigationBarTitleDisplayMode(.inline)
        .task {
            sessionManager.startBootstrapIfNeeded()
            seedEmailIfNeeded()
        }
        .onChange(of: sessionManager.profile) { _, _ in
            seedEmailIfNeeded()
        }
        .onDisappear {
            cooldownTask?.cancel()
            cooldownTask = nil
        }
        .alert("绑定邮箱", isPresented: Binding(
            get: { alertMessage != nil },
            set: { if !$0 { alertMessage = nil } }
        )) {
            Button("好", role: .cancel) {}
        } message: {
            Text(alertMessage ?? "")
        }
    }

    private var sendCodeButtonTitle: String {
        if isRequestedEmailAlreadyBound {
            return "已绑定"
        }
        if cooldownRemaining > 0 {
            return "\(cooldownRemaining) 秒后重发"
        }
        return profile?.pendingBoundEmail == nil ? "发送验证码" : "重发验证码"
    }

    private var statusFooter: String {
        let boundEmail = profile?.boundEmail?.trimmingCharacters(in: .whitespacesAndNewlines) ?? ""
        let pendingEmail = profile?.pendingBoundEmail?.trimmingCharacters(in: .whitespacesAndNewlines) ?? ""

        if !boundEmail.isEmpty, !pendingEmail.isEmpty {
            return "当前通知邮箱仍是 \(boundEmail)。\(pendingEmail) 验证成功后会替换旧邮箱。"
        }
        if !boundEmail.isEmpty {
            return "此邮箱仅用于接收服务异常和重要通知，不会改变北林登录方式。"
        }
        if !pendingEmail.isEmpty {
            return "验证码已发送到 \(pendingEmail)，输入验证码后完成绑定。"
        }
        return "绑定邮箱后，重要服务异常可通过邮箱通知你；北林登录仍使用学号和教务密码。"
    }

    @ViewBuilder
    private var statusRow: some View {
        let boundEmail = profile?.boundEmail?.trimmingCharacters(in: .whitespacesAndNewlines) ?? ""
        let pendingEmail = profile?.pendingBoundEmail?.trimmingCharacters(in: .whitespacesAndNewlines) ?? ""

        if sessionManager.isBootstrapping && profile == nil {
            HStack {
                ProgressView()
                Text("正在加载社区身份")
                    .foregroundStyle(AppTheme.secondaryText)
            }
        } else if !boundEmail.isEmpty {
            statusContent(
                icon: "checkmark.seal.fill",
                tint: AppTheme.accent,
                title: "已绑定",
                detail: boundEmail
            )
        } else if !pendingEmail.isEmpty {
            statusContent(
                icon: "envelope.badge.fill",
                tint: AppTheme.warning,
                title: "待验证",
                detail: pendingEmail
            )
        } else {
            statusContent(
                icon: "envelope.fill",
                tint: AppTheme.secondaryText,
                title: "未绑定",
                detail: "暂无邮箱"
            )
        }
    }

    private func purposeRow(icon: String, title: String, detail: String) -> some View {
        HStack(alignment: .top, spacing: 12) {
            Image(systemName: icon)
                .font(.system(size: 18, weight: .semibold))
                .foregroundStyle(AppTheme.accent)
                .frame(width: 28, height: 28)

            VStack(alignment: .leading, spacing: 3) {
                Text(L10n.text(title, language: leafyLanguage))
                    .leafyBody()
                    .foregroundStyle(AppTheme.primaryText)
                Text(L10n.text(detail, language: leafyLanguage))
                    .microCaption()
                    .foregroundStyle(AppTheme.secondaryText)
            }
        }
        .padding(.vertical, 2)
    }

    private func statusContent(icon: String, tint: Color, title: String, detail: String) -> some View {
        HStack(spacing: 12) {
            Image(systemName: icon)
                .font(.system(size: 20, weight: .semibold))
                .foregroundStyle(tint)
                .frame(width: 30, height: 30)

            VStack(alignment: .leading, spacing: 3) {
                Text(title)
                    .leafyBody()
                    .foregroundStyle(AppTheme.primaryText)
                Text(detail)
                    .microCaption()
                    .foregroundStyle(AppTheme.secondaryText)
                    .lineLimit(2)
                    .minimumScaleFactor(0.8)
            }

            Spacer()
        }
    }

    @MainActor
    private func seedEmailIfNeeded() {
        guard !hasEditedEmail else { return }
        let candidate = profile?.pendingBoundEmail ?? profile?.boundEmail ?? ""
        let normalized = CommunityEmailBinding.normalizedEmail(candidate)
        guard !normalized.isEmpty else { return }
        email = normalized
    }

    @MainActor
    private func sendCode() async {
        guard !isSendingCode else { return }
        guard CommunityEmailBinding.isValidEmail(normalizedEmail) else {
            alertMessage = CommunityServiceError.invalidEmail.localizedDescription
            return
        }
        if isRequestedEmailAlreadyBound {
            alertMessage = "此通知邮箱已绑定，无需重复验证。"
            return
        }

        isSendingCode = true
        defer { isSendingCode = false }

        do {
            try await sessionManager.requestEmailVerification(input: CommunityEmailBindingInput(email: normalizedEmail))
            email = normalizedEmail
            code = ""
            hasEditedEmail = false
            alertMessage = "验证码已发送到 \(normalizedEmail)。"
            startCooldown()
        } catch {
            alertMessage = error.localizedDescription
        }
    }

    @MainActor
    private func verifyCode() async {
        guard !isVerifyingCode else { return }
        guard CommunityEmailBinding.isValidEmail(normalizedEmail) else {
            alertMessage = CommunityServiceError.invalidEmail.localizedDescription
            return
        }
        guard CommunityEmailBinding.isCompleteVerificationCode(normalizedCode) else {
            alertMessage = "请输入邮件中的 8 位验证码。"
            return
        }

        isVerifyingCode = true
        defer { isVerifyingCode = false }

        do {
            try await sessionManager.verifyEmailBinding(email: normalizedEmail, code: normalizedCode)
            email = sessionManager.profile?.boundEmail ?? normalizedEmail
            code = ""
            hasEditedEmail = false
            alertMessage = "通知邮箱已绑定。服务异常或重要消息可通过此邮箱联系你。"
        } catch {
            alertMessage = error.localizedDescription
        }
    }

    @MainActor
    private func startCooldown() {
        cooldownTask?.cancel()
        cooldownRemaining = cooldownSeconds

        cooldownTask = Task { @MainActor in
            while cooldownRemaining > 0 {
                try? await Task.sleep(for: .seconds(1))
                guard !Task.isCancelled else { return }
                cooldownRemaining -= 1
            }
            cooldownTask = nil
        }
    }
}
