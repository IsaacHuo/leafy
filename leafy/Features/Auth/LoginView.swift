import Combine
import Network
import SwiftData
import SwiftUI

struct LoginView: View {
    @Environment(\.modelContext) private var modelContext
    @Environment(\.leafyControlScale) private var leafyControlScale
    @Environment(\.leafyFontScale) private var leafyFontScale
    @Environment(\.leafyLanguage) private var leafyLanguage
    @Environment(\.scenePhase) private var scenePhase
    @StateObject private var schoolNetworkManager = ActiveCampusContext.networkManager
    @StateObject private var networkPathObserver = LoginNetworkPathObserver()
    private let fieldHeight: CGFloat = 54
    private let buttonHeight: CGFloat = 56
    private let automaticCaptchaRetryInterval: TimeInterval = 1.5
    private let customSignUpCodeCooldownSeconds = 60

    @State private var username = ""
    @State private var password = ""
    @State private var customSignUpCode = ""
    @State private var captchaCode = ""
    @State private var captchaImage: UIImage? = nil
    @State private var sessionKey = ""
    @State private var isPasswordVisible = false
    @State private var captchaLoadMessage: String?
    @State private var isCaptchaLoading = false
    @State private var captchaRequestID = UUID()
    @State private var lastAutomaticCaptchaRefreshAt: Date?

    @State private var isLoggingIn = false
    @State private var isEnteringDemo = false

    @State private var showAlert = false
    @State private var alertMessage = ""
    @State private var selectedCampusID: CampusID = CampusCatalog.production.first?.id ?? .bjfu
    @State private var selectedPortal: SchoolPortal = ActiveCampusContext.networkManager.currentPortal
    @State private var customAuthMode: CustomAuthMode = .signIn
    @State private var customSignUpCodeEmail: String?
    @State private var customSignUpCodePassword: String?
    @State private var isSendingCustomSignUpCode = false
    @State private var customSignUpCodeCooldownRemaining = 0
    @State private var customSignUpCodeCooldownTask: Task<Void, Never>?

    private var scaledButtonHeight: CGFloat { buttonHeight * leafyControlScale }
    private var scaledFieldHeight: CGFloat { fieldHeight * leafyControlScale }
    private var loginCampusOptions: [CampusDescriptor] {
        let supported = CampusCatalog.production.filter {
            $0.supports(.authentication)
        }
        return supported.isEmpty ? [.bjfu] : supported
    }

    private var selectedCampus: CampusDescriptor {
        loginCampusOptions.first(where: { $0.id == selectedCampusID }) ?? loginCampusOptions[0]
    }

    private var isCustomCampusSelected: Bool {
        selectedCampus.connectorKind == .custom
    }

    private var isLoginDisabled: Bool {
        if isCustomCampusSelected {
            return isLoggingIn
                || username.isEmpty
                || password.isEmpty
                || (customAuthMode == .signUp && customSignUpCode.isEmpty)
        }
        return isLoggingIn || username.isEmpty || password.isEmpty || captchaCode.isEmpty
    }

    private var shouldAutomaticallyRefreshCaptcha: Bool {
        captchaImage == nil || captchaLoadMessage != nil
    }

    var body: some View {
        NavigationStack {
            GeometryReader { proxy in
                ScrollView(showsIndicators: false) {
                    VStack(spacing: 24 * leafyControlScale) {
                        campusPicker
                            .frame(maxWidth: 360)

                        if isCustomCampusSelected {
                            customAuthModePicker
                                .frame(maxWidth: 360)
                        } else {
                            portalPicker
                                .frame(maxWidth: 360)
                        }

                        loginForm
                            .frame(maxWidth: 360)

                        loginButton
                            .frame(maxWidth: 360, minHeight: scaledButtonHeight)

                        if !isCustomCampusSelected {
                            demoModeButton
                                .frame(maxWidth: 360)
                        }

                        if let captchaLoadMessage {
                            Text(captchaLoadMessage)
                                .microCaption()
                                .foregroundStyle(AppTheme.secondaryText)
                                .multilineTextAlignment(.center)
                                .frame(maxWidth: 360)
                        }
                    }
                    .padding(.horizontal, AppSpacing.page)
                    .padding(.vertical, 40)
                    .padding(.bottom, 80 * leafyControlScale)
                    .frame(maxWidth: .infinity, minHeight: proxy.size.height, alignment: .center)
                }
            }
            .background(LeafyPageBackground())
            .leafyLoginNavigationChrome()
            .task {
                if !isCustomCampusSelected {
                    await fetchCaptcha()
                }
            }
            .onChange(of: selectedCampusID) { _, _ in
                handleSelectedCampusChange()
            }
            .onChange(of: username) { _, newValue in
                handleUsernameChange(newValue)
            }
            .onChange(of: password) { _, newValue in
                handlePasswordChange(newValue)
            }
            .onChange(of: selectedPortal) { _, newValue in
                guard !isCustomCampusSelected else { return }
                schoolNetworkManager.currentPortal = newValue
                Task { await fetchCaptcha() }
            }
            .onChange(of: scenePhase) { _, newPhase in
                guard !isCustomCampusSelected else { return }
                guard newPhase == .active else { return }
                startAutomaticCaptchaRefresh()
            }
            .onChange(of: networkPathObserver.pathUpdateID) { _, _ in
                guard !isCustomCampusSelected else { return }
                guard scenePhase == .active, networkPathObserver.isPathSatisfied else { return }
                startAutomaticCaptchaRefresh()
            }
            .onDisappear {
                customSignUpCodeCooldownTask?.cancel()
                customSignUpCodeCooldownTask = nil
            }
            .alert(L10n.text("提示", language: leafyLanguage), isPresented: $showAlert) {
                Button(L10n.text("确定", language: leafyLanguage)) {
                    if !isCustomCampusSelected {
                        Task { await fetchCaptcha() }
                    }
                }
            } message: {
                Text(alertMessage)
            }
        }
    }

    private var campusPicker: some View {
        VStack(alignment: .leading, spacing: 10 * leafyControlScale) {
            Text(L10n.text("选择入口", language: leafyLanguage))
                .microCaption()
                .foregroundStyle(AppTheme.secondaryText)
                .frame(maxWidth: .infinity, alignment: .leading)

            ForEach(loginCampusOptions) { campus in
                Button {
                    selectedCampusID = campus.id
                } label: {
                    HStack(spacing: 12 * leafyControlScale) {
                        Image(systemName: loginEntryIcon(for: campus))
                            .font(.system(size: 18 * leafyControlScale, weight: .semibold))
                            .foregroundStyle(campus.id == selectedCampusID ? AppTheme.accent : AppTheme.secondaryText)
                            .frame(width: 28 * leafyControlScale, height: 28 * leafyControlScale)

                        VStack(alignment: .leading, spacing: 3 * leafyControlScale) {
                            Text(loginEntryTitle(for: campus))
                                .font(.system(size: 16 * leafyFontScale, weight: .semibold))
                                .foregroundStyle(AppTheme.primaryText)
                                .lineLimit(1)

                            Text(loginEntrySubtitle(for: campus))
                                .microCaption()
                                .foregroundStyle(AppTheme.secondaryText)
                                .lineLimit(2)
                        }

                        Spacer(minLength: 8 * leafyControlScale)

                        Image(systemName: campus.id == selectedCampusID ? "checkmark.circle.fill" : "circle")
                            .font(.system(size: 18 * leafyControlScale, weight: .semibold))
                            .foregroundStyle(campus.id == selectedCampusID ? AppTheme.accent : AppTheme.secondaryText.opacity(0.7))
                    }
                    .padding(.horizontal, 16 * leafyControlScale)
                    .padding(.vertical, 12 * leafyControlScale)
                    .frame(maxWidth: .infinity, minHeight: 64 * leafyControlScale)
                    .leafyCardStyle()
                }
                .buttonStyle(.plain)
                .accessibilityLabel(loginEntryTitle(for: campus))
                .accessibilityValue(campus.id == selectedCampusID ? "已选择" : "未选择")
            }
        }
    }

    private func loginEntryTitle(for campus: CampusDescriptor) -> String {
        if campus.connectorKind == .custom {
            return "通用入口"
        }
        return campus.displayName
    }

    private func loginEntrySubtitle(for campus: CampusDescriptor) -> String {
        if campus.connectorKind == .custom {
            return "通用入口，不连接教务系统，进入 App 后手动导入数据。"
        }
        return "已接入教务系统，可使用校园账号登录。"
    }

    private func loginEntryIcon(for campus: CampusDescriptor) -> String {
        campus.connectorKind == .custom ? "square.and.pencil" : "building.columns"
    }

    private var customAuthModePicker: some View {
        VStack(spacing: 8) {
            Picker("账号操作", selection: $customAuthMode) {
                ForEach(CustomAuthMode.allCases) { mode in
                    Text(mode.title).tag(mode)
                }
            }
            .pickerStyle(.segmented)

            Text(customAuthMode.hint)
                .microCaption()
                .foregroundStyle(AppTheme.secondaryText)
                .frame(maxWidth: .infinity, alignment: .leading)

            if customAuthMode == .signUp, let customSignUpCodeEmail {
                Label("验证码已发送到 \(customSignUpCodeEmail)。国内邮箱可能需要等待数分钟，请也检查垃圾箱。", systemImage: "envelope.badge")
                    .microCaption()
                    .foregroundStyle(AppTheme.secondaryText)
                    .frame(maxWidth: .infinity, alignment: .leading)
            }

            Text("通用入口不会连接教务系统；课表、成绩和考试安排进入 App 后手动导入，学校社区在社区页申请。")
                .microCaption()
                .foregroundStyle(AppTheme.secondaryText)
                .frame(maxWidth: .infinity, alignment: .leading)
        }
    }

    private var portalPicker: some View {
        VStack(spacing: 8) {
            Picker(L10n.text("登录身份", language: leafyLanguage), selection: $selectedPortal) {
                ForEach(SchoolPortal.allCases) { portal in
                    Text(L10n.text(portal.title, language: leafyLanguage)).tag(portal)
                }
            }
            .pickerStyle(.segmented)

            Text(L10n.text(selectedPortal.loginHint, language: leafyLanguage))
                .microCaption()
                .foregroundStyle(AppTheme.secondaryText)
                .frame(maxWidth: .infinity, alignment: .leading)

            Text(L10n.text("当前支持本科生和研究生账号登录，老师账号暂不支持。", language: leafyLanguage))
                .microCaption()
                .foregroundStyle(AppTheme.secondaryText)
                .frame(maxWidth: .infinity, alignment: .leading)
        }
    }

    private var loginForm: some View {
        VStack(spacing: 0) {
            TextField(L10n.text(isCustomCampusSelected ? "邮箱" : "学号", language: leafyLanguage), text: $username)
                .leafyUsernameInput(isEmail: isCustomCampusSelected)
                .padding(.horizontal, 16 * leafyControlScale)
                .frame(height: scaledFieldHeight)

            Divider()
                .padding(.leading, 16 * leafyControlScale)

            if isCustomCampusSelected {
                HStack(spacing: 12) {
                    Group {
                        if isPasswordVisible {
                            TextField(L10n.text("密码", language: leafyLanguage), text: $password)
                        } else {
                            SecureField(L10n.text("密码", language: leafyLanguage), text: $password)
                        }
                    }
                    .leafyPasswordInput(isNewPassword: customAuthMode == .signUp)

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
                .frame(height: scaledFieldHeight)

                if customAuthMode == .signUp {
                    Divider()
                        .padding(.leading, 16 * leafyControlScale)

                    HStack(spacing: 12) {
                        TextField(L10n.text("邮箱验证码", language: leafyLanguage), text: $customSignUpCode)
                        .leafyOneTimeCodeInput(isNumeric: true)
                        .onChange(of: customSignUpCode) { _, newValue in
                            let normalized = newValue.filter(\.isNumber)
                            if normalized != newValue {
                                customSignUpCode = normalized
                            }
                        }

                        Button {
                            Task { await sendCustomSignUpCode() }
                        } label: {
                            if isSendingCustomSignUpCode {
                                ProgressView()
                            } else {
                                Label(customSignUpCodeButtonTitle, systemImage: "paperplane")
                            }
                        }
                        .buttonStyle(.plain)
                        .foregroundStyle(AppTheme.accent)
                        .font(.system(size: 13 * leafyFontScale, weight: .semibold))
                        .frame(width: 118 * leafyControlScale, height: 34 * leafyControlScale)
                        .disabled(isSendingCustomSignUpCode || customSignUpCodeCooldownRemaining > 0 || username.isEmpty || password.isEmpty)
                        .accessibilityLabel(customSignUpCodeButtonTitle)
                    }
                    .padding(.horizontal, 16 * leafyControlScale)
                    .frame(height: scaledFieldHeight)
                }
            } else {
                HStack(spacing: 12) {
                    Group {
                        if isPasswordVisible {
                            TextField(L10n.text("密码", language: leafyLanguage), text: $password)
                        } else {
                            SecureField(L10n.text("密码", language: leafyLanguage), text: $password)
                        }
                    }
                    .leafyPasswordInput(isNewPassword: false)

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
                .frame(height: scaledFieldHeight)

                Divider()
                    .padding(.leading, 16 * leafyControlScale)

                HStack(spacing: 12) {
                    TextField(L10n.text("验证码", language: leafyLanguage), text: $captchaCode)
                        .leafyOneTimeCodeInput(isNumeric: false)

                    captchaButton
                }
                .padding(.leading, 16 * leafyControlScale)
                .padding(.trailing, 14 * leafyControlScale)
                .frame(height: scaledFieldHeight)
            }
        }
        .leafyCardStyle()
    }

    @ViewBuilder
    private var demoModeButton: some View {
        Button {
            enterDemoMode()
        } label: {
            HStack(spacing: 8) {
                if isEnteringDemo {
                    ProgressView()
                }
                Image(systemName: "sparkles")
                Text(L10n.text("进入演示模式", language: leafyLanguage))
                    .frame(maxWidth: .infinity)
            }
        }
        .buttonStyle(.bordered)
        .tint(AppTheme.accent)
        .disabled(isEnteringDemo)
        .accessibilityLabel(L10n.text("进入演示模式", language: leafyLanguage))
    }

    @ViewBuilder
    private var captchaButton: some View {
        Button {
            Task { await fetchCaptcha() }
        } label: {
            ZStack {
                if let image = captchaImage {
                    Image(uiImage: image)
                        .resizable()
                        .interpolation(.none)
                        .scaledToFill()
                } else if isCaptchaLoading {
                    ProgressView()
                } else {
                    VStack(spacing: 1) {
                        Image(systemName: "arrow.clockwise")
                            .font(.system(size: 12 * leafyControlScale, weight: .semibold))
                        Text(L10n.text("重试", language: leafyLanguage))
                            .font(.system(size: 10 * leafyControlScale, weight: .semibold))
                    }
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

    @ViewBuilder
    private var loginButton: some View {
        #if os(iOS)
        if #available(iOS 26.0, *) {
            Button {
                Task { await performLogin() }
            } label: {
                HStack(spacing: 10) {
                    if isLoggingIn {
                        ProgressView()
                    }

                    Text(loginButtonTitle)
                        .frame(maxWidth: .infinity)
                }
                .frame(maxWidth: .infinity)
            }
            .disabled(isLoginDisabled)
            .buttonStyle(.glassProminent)
            .tint(AppTheme.accent)
        } else {
            Button {
                Task { await performLogin() }
            } label: {
                HStack(spacing: 10) {
                    if isLoggingIn {
                        ProgressView()
                    }

                    Text(loginButtonTitle)
                        .frame(maxWidth: .infinity)
                }
                .frame(maxWidth: .infinity)
            }
            .disabled(isLoginDisabled)
            .buttonStyle(.borderedProminent)
            .tint(AppTheme.accent)
        }
        #else
        Button {
            Task { await performLogin() }
        } label: {
            HStack(spacing: 10) {
                if isLoggingIn {
                    ProgressView()
                }
                Text(loginButtonTitle)
                    .frame(maxWidth: .infinity)
            }
            .frame(maxWidth: .infinity)
        }
        .disabled(isLoginDisabled)
        .buttonStyle(.borderedProminent)
        .tint(AppTheme.accent)
        #endif
    }

    private var loginButtonTitle: String {
        if isLoggingIn {
            return L10n.text(customAuthMode == .signUp && isCustomCampusSelected ? "注册中" : "登录中", language: leafyLanguage)
        }
        if isCustomCampusSelected {
            return L10n.text(customAuthMode.primaryActionTitle, language: leafyLanguage)
        }
        return L10n.text("登录", language: leafyLanguage)
    }

    private var customSignUpCodeButtonTitle: String {
        if customSignUpCodeCooldownRemaining > 0 {
            return "\(customSignUpCodeCooldownRemaining) 秒后重发"
        }
        return customSignUpCodeEmail == nil ? "发送验证码" : "重发验证码"
    }

    @MainActor
    private func handleSelectedCampusChange() {
        alertMessage = ""
        captchaLoadMessage = nil
        showAlert = false
        captchaCode = ""
        customSignUpCode = ""

        if isCustomCampusSelected {
            isCaptchaLoading = false
            captchaImage = nil
            sessionKey = ""
        } else {
            customSignUpCodeEmail = nil
            customSignUpCodePassword = nil
            Task { await fetchCaptcha() }
        }
    }

    @MainActor
    private func handleUsernameChange(_ newValue: String) {
        guard isCustomCampusSelected, let customSignUpCodeEmail else { return }
        let normalizedEmail = newValue.trimmingCharacters(in: .whitespacesAndNewlines).lowercased()
        if normalizedEmail != customSignUpCodeEmail {
            self.customSignUpCodeEmail = nil
            self.customSignUpCodePassword = nil
            self.customSignUpCode = ""
        }
    }

    @MainActor
    private func handlePasswordChange(_ newValue: String) {
        guard isCustomCampusSelected, customAuthMode == .signUp, let customSignUpCodePassword else { return }
        if newValue != customSignUpCodePassword {
            self.customSignUpCodeEmail = nil
            self.customSignUpCodePassword = nil
            self.customSignUpCode = ""
        }
    }

    @MainActor
    private func startAutomaticCaptchaRefresh() {
        guard shouldAutomaticallyRefreshCaptcha else { return }
        let now = Date()
        if let lastAutomaticCaptchaRefreshAt,
           now.timeIntervalSince(lastAutomaticCaptchaRefreshAt) < automaticCaptchaRetryInterval {
            return
        }

        lastAutomaticCaptchaRefreshAt = now
        Task { await fetchCaptcha(automatic: true) }
    }

    @MainActor
    private func fetchCaptcha() async {
        await fetchCaptcha(automatic: false)
    }

    @MainActor
    private func fetchCaptcha(automatic: Bool) async {
        if automatic, isCaptchaLoading {
            return
        }
        if automatic, !shouldAutomaticallyRefreshCaptcha {
            return
        }

        let portal = selectedPortal
        let requestID = UUID()
        captchaRequestID = requestID
        isCaptchaLoading = true
        captchaImage = nil
        captchaLoadMessage = nil

        do {
            let result = try await schoolNetworkManager.fetchCaptcha(for: portal)
            guard !Task.isCancelled, captchaRequestID == requestID, selectedPortal == portal else {
                return
            }

            sessionKey = result.key
            captchaImage = result.image
            captchaCode = ""
            captchaLoadMessage = nil
            isCaptchaLoading = false
        } catch {
            guard !isCaptchaRequestCancellation(error) else {
                if captchaRequestID == requestID {
                    isCaptchaLoading = false
                }
                return
            }

            guard captchaRequestID == requestID else {
                return
            }

            captchaLoadMessage = portal == .graduate
                ? L10n.text("当前网络无法连接研究生系统验证码。网络恢复后会自动重试，也可点验证码区域重试。", language: leafyLanguage)
                : L10n.text("当前网络无法连接教务验证码。网络恢复后会自动重试，也可点验证码区域重试。", language: leafyLanguage)
            isCaptchaLoading = false
        }
    }

    private func isCaptchaRequestCancellation(_ error: Error) -> Bool {
        if error is CancellationError {
            return true
        }

        let nsError = error as NSError
        return nsError.domain == NSURLErrorDomain && nsError.code == URLError.cancelled.rawValue
    }

    private func performLogin() async {
        guard !isLoggingIn else { return }

        await MainActor.run {
            isLoggingIn = true
        }

        do {
            if isCustomCampusSelected {
                try await performCustomAuth()
                return
            }

            let portal = selectedPortal
            let loginAccount = username.trimmingCharacters(in: .whitespacesAndNewlines)
            let success = try await schoolNetworkManager.performLogin(
                account: loginAccount,
                password: password,
                captcha: captchaCode,
                key: sessionKey,
                portal: portal
            )

            await MainActor.run {
                isLoggingIn = false
                if success {
                    schoolNetworkManager.isLoggedIn = true
                } else {
                    alertMessage = L10n.text("登录请求已发送，但未能确认登录成功。请重试；如果仍失败，把这条提示发给我。", language: leafyLanguage)
                    showAlert = true
                }
            }
        } catch {
            await MainActor.run {
                isLoggingIn = false
                alertMessage = error.localizedDescription
                showAlert = true
                captchaCode = ""
            }
        }
    }

    private func performCustomAuth() async throws {
        let service = CustomCampusAuthService()
        let session: CustomCampusAuthSession
        switch customAuthMode {
        case .signIn:
            session = try await service.signIn(email: username, password: password)
        case .signUp:
            let normalizedEmail = username.trimmingCharacters(in: .whitespacesAndNewlines).lowercased()
            guard customSignUpCodeEmail == normalizedEmail, customSignUpCodePassword == password else {
                throw CustomCampusAuthError.invalidCode
            }
            session = try await service.verifySignUpCode(email: username, password: password, code: customSignUpCode)
        }

        await MainActor.run {
            schoolNetworkManager.persistCustomCampusAuthSession(session)
            isLoggingIn = false
        }
    }

    private func sendCustomSignUpCode() async {
        guard !isSendingCustomSignUpCode else { return }
        let credentials = await MainActor.run {
            (
                email: username.trimmingCharacters(in: .whitespacesAndNewlines).lowercased(),
                password: password
            )
        }
        guard !credentials.email.isEmpty else {
            await MainActor.run {
                alertMessage = CustomCampusAuthError.invalidEmail.localizedDescription
                showAlert = true
            }
            return
        }

        await MainActor.run {
            isSendingCustomSignUpCode = true
        }

        do {
            try await CustomCampusAuthService().sendSignUpCode(email: credentials.email, password: credentials.password)
            await MainActor.run {
                customSignUpCodeEmail = credentials.email
                customSignUpCodePassword = credentials.password
                isSendingCustomSignUpCode = false
                customSignUpCode = ""
                alertMessage = "验证码已发送到 \(credentials.email)。国内邮箱可能需要数分钟，请也检查垃圾箱。"
                showAlert = true
                startCustomSignUpCodeCooldown()
            }
        } catch {
            await MainActor.run {
                isSendingCustomSignUpCode = false
                alertMessage = error.localizedDescription
                showAlert = true
            }
        }
    }

    @MainActor
    private func startCustomSignUpCodeCooldown() {
        customSignUpCodeCooldownTask?.cancel()
        customSignUpCodeCooldownRemaining = customSignUpCodeCooldownSeconds

        customSignUpCodeCooldownTask = Task { @MainActor in
            while customSignUpCodeCooldownRemaining > 0 {
                try? await Task.sleep(for: .seconds(1))
                guard !Task.isCancelled else { return }
                customSignUpCodeCooldownRemaining -= 1
            }
            customSignUpCodeCooldownTask = nil
        }
    }

    @MainActor
    private func enterDemoMode() {
        isEnteringDemo = true
        ReviewDemoDataSeeder.enter(using: modelContext)
        schoolNetworkManager.isLoggedIn = true
        isEnteringDemo = false
    }
}

private extension View {
    @ViewBuilder
    func leafyLoginNavigationChrome() -> some View {
        #if os(iOS)
        toolbar(.hidden, for: .navigationBar)
        #else
        self
        #endif
    }

    @ViewBuilder
    func leafyUsernameInput(isEmail: Bool) -> some View {
        #if os(iOS)
        textInputAutocapitalization(.never)
            .autocorrectionDisabled()
            .textContentType(isEmail ? .emailAddress : .username)
            .keyboardType(isEmail ? .emailAddress : .default)
        #else
        self
        #endif
    }

    @ViewBuilder
    func leafyPasswordInput(isNewPassword: Bool) -> some View {
        #if os(iOS)
        textInputAutocapitalization(.never)
            .autocorrectionDisabled()
            .textContentType(isNewPassword ? .newPassword : .password)
        #else
        self
        #endif
    }

    @ViewBuilder
    func leafyOneTimeCodeInput(isNumeric: Bool) -> some View {
        #if os(iOS)
        textInputAutocapitalization(.never)
            .autocorrectionDisabled()
            .leafyOneTimeCodeContentType()
            .keyboardType(isNumeric ? .numberPad : .default)
        #else
        self
        #endif
    }
}

#Preview {
    LoginView()
}

private enum CustomAuthMode: String, CaseIterable, Identifiable {
    case signIn
    case signUp

    var id: String { rawValue }

    var title: String {
        switch self {
        case .signIn:
            return "登录"
        case .signUp:
            return "注册"
        }
    }

    var primaryActionTitle: String {
        title
    }

    var hint: String {
        switch self {
        case .signIn:
            return "使用邮箱和密码登录通用入口账号。"
        case .signUp:
            return "首次使用需要邮箱、密码和邮件验证码；验证成功后下次可直接用邮箱密码登录。"
        }
    }
}

@MainActor
private final class LoginNetworkPathObserver: ObservableObject {
    @Published private(set) var pathUpdateID = UUID()
    @Published private(set) var isPathSatisfied = false

    private let monitor = NWPathMonitor()
    private let queue = DispatchQueue(label: "Leafy.LoginNetworkPathObserver")

    init() {
        monitor.pathUpdateHandler = { [weak self] path in
            DispatchQueue.main.async {
                self?.isPathSatisfied = path.status == .satisfied
                self?.pathUpdateID = UUID()
            }
        }
        monitor.start(queue: queue)
    }

    deinit {
        monitor.cancel()
    }
}
