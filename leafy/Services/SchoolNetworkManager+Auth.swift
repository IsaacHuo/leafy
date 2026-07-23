import Foundation
import CommonCrypto
import Security
import SwiftSoup
#if canImport(UIKit)
import UIKit
#elseif canImport(AppKit)
import AppKit
#endif

extension SchoolNetworkManager {
    func fetchCaptcha() async throws -> (key: String, image: UIImage) {
        try await fetchCaptcha(for: currentPortal)
    }

    func fetchCaptcha(for portal: SchoolPortal) async throws -> (key: String, image: UIImage) {
        if ReviewDemoMode.isEnabled {
            throw SchoolNetworkError.featureUnavailable("演示模式不连接学校教务验证码。")
        }

        let previousCookies = persistedCookieValues
        do {
            switch portal {
            case .undergraduate:
                return try await fetchUndergraduateCaptcha()
            case .graduate:
                return try await fetchGraduateCaptcha()
            }
        } catch {
            // A failed captcha request usually means the campus network/VPN is
            // unreachable. Preserve the previous session so connectivity is
            // not mistaken for a real logout.
            persistedCookieValues = previousCookies
            for url in [URL(string: baseURL), URL(string: graduateBaseURL)].compactMap({ $0 }) {
                syncPersistedCookiesToStorage(for: url)
            }
            throw error
        }
    }

    private func fetchUndergraduateCaptcha() async throws -> (key: String, image: UIImage) {
        guard let codeUrl = URL(string: "\(baseURL)/Logon.do?method=logon&flag=sess") else {
            throw URLError(.badURL)
        }

        clearPersistedCookies()

        let codeRequest = makeRequest(url: codeUrl)
        let (keyData, keyResponse) = try await data(for: codeRequest)
        if let httpResponse = keyResponse as? HTTPURLResponse {
            updatePersistedCookies(from: httpResponse, requestURL: codeUrl)
        }
        guard let keyString = String(data: keyData, encoding: .utf8)?.trimmingCharacters(in: .whitespacesAndNewlines) else {
            throw URLError(.badServerResponse)
        }

        guard let verifyUrl = URL(string: "\(baseURL)/verifycode.servlet") else {
            throw URLError(.badURL)
        }

        let verifyRequest = makeRequest(url: verifyUrl)
        let (imgData, verifyResponse) = try await data(for: preparedRequest(from: verifyRequest))
        if let httpResponse = verifyResponse as? HTTPURLResponse {
            updatePersistedCookies(from: httpResponse, requestURL: verifyUrl)
        }
        guard let image = UIImage(data: imgData) else {
            throw URLError(.cannotDecodeRawData)
        }

        return (keyString, image)
    }

    private func fetchGraduateCaptcha() async throws -> (key: String, image: UIImage) {
        guard let loginUrl = graduateURL(path: "/home/stulogin"),
              let verifyUrl = graduateURL(path: "/home/verificationcode?codetype=stucode") else {
            throw URLError(.badURL)
        }

        clearPersistedCookies()

        let (loginHTML, loginResponse) = try await html(for: makeRequest(url: loginUrl))
        updatePersistedCookies(from: loginResponse, requestURL: loginUrl)

        let publicKey = try extractGraduatePublicKey(from: loginHTML)
        let verifyRequest = makeRequest(url: verifyUrl, referer: loginUrl)
        let (imgData, verifyResponse) = try await data(for: preparedRequest(from: verifyRequest))
        if let httpResponse = verifyResponse as? HTTPURLResponse {
            updatePersistedCookies(from: httpResponse, requestURL: verifyUrl)
        }
        guard let image = UIImage(data: imgData) else {
            throw URLError(.cannotDecodeRawData)
        }

        return (publicKey, image)
    }

    func refreshLoginKey() async throws -> String {
        if ReviewDemoMode.isEnabled {
            throw SchoolNetworkError.featureUnavailable("演示模式不连接学校教务登录。")
        }

        guard let codeUrl = URL(string: "\(baseURL)/Logon.do?method=logon&flag=sess") else {
            throw URLError(.badURL)
        }

        let request = makeRequest(url: codeUrl, method: "POST", referer: URL(string: baseURL))
        let (keyData, response) = try await data(for: preparedRequest(from: request))
        if let httpResponse = response as? HTTPURLResponse {
            updatePersistedCookies(from: httpResponse, requestURL: codeUrl)
        }

        guard let keyString = String(data: keyData, encoding: .utf8)?.trimmingCharacters(in: .whitespacesAndNewlines),
              !keyString.isEmpty else {
            throw URLError(.badServerResponse)
        }

        return keyString
    }

    func performLogin(account: String, password: String, captcha: String, key: String) async throws -> Bool {
        try await performLogin(account: account, password: password, captcha: captcha, key: key, portal: currentPortal)
    }

    func performLogin(account: String, password: String, captcha: String, key: String, portal: SchoolPortal) async throws -> Bool {
        if ReviewDemoMode.isEnabled {
            throw SchoolNetworkError.featureUnavailable("请先退出演示模式，再连接校园网登录教务系统。")
        }

        switch portal {
        case .undergraduate:
            return try await performUndergraduateLogin(account: account, password: password, captcha: captcha)
        case .graduate:
            return try await performGraduateLogin(account: account, password: password, captcha: captcha, publicKey: key)
        }
    }

    private func performUndergraduateLogin(account: String, password: String, captcha: String) async throws -> Bool {
        let trimmedAccount = account.trimmingCharacters(in: .whitespacesAndNewlines)
        let effectiveKey = try await refreshLoginKey()
        let encodedStr = encodeKey(key: effectiveKey, account: account, password: password)

        guard let loginUrl = URL(string: "\(baseURL)/Logon.do?method=logon") else {
            throw URLError(.badURL)
        }

        var request = URLRequest(url: loginUrl)
        request.httpMethod = "POST"
        request.httpShouldHandleCookies = true
        request.setValue("application/x-www-form-urlencoded", forHTTPHeaderField: "Content-Type")

        request.httpBody = formURLEncodedBody(queryItems: [
            URLQueryItem(name: "useDogCode", value: ""),
            URLQueryItem(name: "encoded", value: encodedStr),
            URLQueryItem(name: "RANDOMCODE", value: captcha.trimmingCharacters(in: .whitespacesAndNewlines))
        ])

        let (data, response) = try await data(for: preparedRequest(from: request))
        guard let httpResponse = response as? HTTPURLResponse else {
            return false
        }

        updatePersistedCookies(from: httpResponse, requestURL: loginUrl)
        persistLandingURL(httpResponse.url)

        let html = (try? decodedHTML(from: data)) ?? ""
        let loggedInFromResponse = isAuthenticatedResponse(url: httpResponse.url, html: html)
        let loggedInFromSessionCheck = await verifyAuthenticatedSession(retryCount: 2)

        if loggedInFromResponse && loggedInFromSessionCheck {
            await MainActor.run {
                self.currentPortal = .undergraduate
                self.persistAuthenticatedIdentity(eduID: trimmedAccount)
                self.isLoggedIn = true
            }
            return true
        }

        if loggedInFromSessionCheck {
            await MainActor.run {
                self.currentPortal = .undergraduate
                self.persistAuthenticatedIdentity(eduID: trimmedAccount)
                self.isLoggedIn = true
            }
            return true
        }

        if let message = extractLoginMessage(from: html) {
            throw SchoolNetworkError.loginFailed(message)
        }

        if isLoginPage(html) {
            throw SchoolNetworkError.loginFailed(
                "登录未成功，服务端仍返回登录页。" +
                pageDebugSummary(html: html, responseURL: httpResponse.url, snapshotName: "last_login_failed_page.html")
            )
        }

        return false
    }

    private func performGraduateLogin(account: String, password: String, captcha: String, publicKey: String) async throws -> Bool {
        let trimmedAccount = account.trimmingCharacters(in: .whitespacesAndNewlines)
        guard let loginUrl = graduateURL(path: "/home/stulogin_do"),
              let refererURL = graduateURL(path: "/home/stulogin"),
              let nameURL = graduateURL(path: "/student/default/getxscardinfo") else {
            throw URLError(.badURL)
        }

        let encryptedPassword = try encryptGraduatePassword(password, publicKeyPEM: publicKey)
        let verification = captcha.trimmingCharacters(in: .whitespacesAndNewlines)
        let payloadObject: [String: Any] = [
            "UserId": trimmedAccount,
            "Password": encryptedPassword,
            "VeriCode": Int(verification) ?? verification,
            "url": "",
            "city": ""
        ]
        let payloadData = try JSONSerialization.data(withJSONObject: payloadObject)
        guard let payload = String(data: payloadData, encoding: .utf8) else {
            throw URLError(.cannotCreateFile)
        }

        var request = makeRequest(url: loginUrl, method: "POST", referer: refererURL)
        request.setValue("application/x-www-form-urlencoded; charset=utf-8", forHTTPHeaderField: "Content-Type")

        request.httpBody = formURLEncodedBody(queryItems: [
            URLQueryItem(name: "json", value: payload)
        ])

        let (data, response) = try await data(for: preparedRequest(from: request))
        guard let httpResponse = response as? HTTPURLResponse else {
            return false
        }
        updatePersistedCookies(from: httpResponse, requestURL: loginUrl)

        let rawBody = String(data: data, encoding: .utf8) ?? ""
        let decryptedBody = decryptGraduateAES(rawBody)
        _ = try parseGraduateLoginRedirect(
            from: decryptedBody,
            rawBody: rawBody,
            responseURL: httpResponse.url,
            statusCode: httpResponse.statusCode
        )

        let displayName = (try? await fetchGraduateDisplayName(from: nameURL)) ?? trimmedAccount
        await MainActor.run {
            self.currentPortal = .graduate
            self.persistAuthenticatedIdentity(eduID: trimmedAccount, displayName: displayName)
            self.isLoggedIn = true
        }
        return true
    }

    func encodeKey(key: String, account: String, password: String) -> String {
        let parts = key.components(separatedBy: "#")
        guard parts.count == 2 else { return "" }

        var secretCode = parts[0]
        let secretKey = Array(parts[1])
        let code = account + "%%%" + password
        let codeChars = Array(code)

        var encoded = ""

        for i in 0..<codeChars.count {
            if i < 20 && i < secretKey.count {
                encoded.append(codeChars[i])
                let shift = Int(String(secretKey[i])) ?? 0

                let prefixCount = min(shift, secretCode.count)
                let prefixIndex = secretCode.index(secretCode.startIndex, offsetBy: prefixCount)
                encoded.append(String(secretCode[..<prefixIndex]))

                secretCode = String(secretCode[prefixIndex...])
            } else {
                let remaining = String(codeChars[i...])
                encoded.append(remaining)
                break
            }
        }

        return encoded
    }

    func formURLEncodedBody(queryItems: [URLQueryItem]) -> Data {
        var components = URLComponents()
        components.queryItems = queryItems
        let bodyString = components.percentEncodedQuery?.replacingOccurrences(of: "+", with: "%2B") ?? ""
        return Data(bodyString.utf8)
    }
}

extension SchoolNetworkManager {
    var graduateAESKey: String { "southsoft12345!#" }

    func graduateURL(path: String) -> URL? {
        URL(string: "\(graduateBaseURL)\(path)")
    }

    func extractGraduatePublicKey(from html: String) throws -> String {
        let document = try SwiftSoup.parse(html)
        let value = try document.select("#pubkey").first()?.attr("value").trimmingCharacters(in: .whitespacesAndNewlines) ?? ""
        guard !value.isEmpty else {
            throw SchoolNetworkError.loginFailed("研究生系统未返回登录公钥，请刷新验证码后重试。")
        }
        return value
    }

    func encryptGraduatePassword(_ password: String, publicKeyPEM: String) throws -> String {
        let key = try makeGraduateRSAKey(publicKeyPEM)
        guard SecKeyIsAlgorithmSupported(key, .encrypt, .rsaEncryptionPKCS1) else {
            throw SchoolNetworkError.loginFailed("当前设备不支持研究生系统密码加密方式。")
        }

        let plainData = Data(password.utf8) as CFData
        var error: Unmanaged<CFError>?
        guard let encrypted = SecKeyCreateEncryptedData(key, .rsaEncryptionPKCS1, plainData, &error) else {
            throw error?.takeRetainedValue() as Error? ?? SchoolNetworkError.loginFailed("研究生系统密码加密失败。")
        }

        return (encrypted as Data).base64EncodedString()
    }

    func makeGraduateRSAKey(_ publicKeyPEM: String) throws -> SecKey {
        let normalized = publicKeyPEM
            .replacingOccurrences(of: "-----BEGIN PUBLIC KEY-----", with: "")
            .replacingOccurrences(of: "-----END PUBLIC KEY-----", with: "")
            .replacingOccurrences(of: "\\s+", with: "", options: .regularExpression)

        guard let keyData = Data(base64Encoded: normalized) else {
            throw SchoolNetworkError.loginFailed("研究生系统登录公钥格式异常。")
        }

        let attributes: [CFString: Any] = [
            kSecAttrKeyType: kSecAttrKeyTypeRSA,
            kSecAttrKeyClass: kSecAttrKeyClassPublic,
            kSecAttrKeySizeInBits: 2048
        ]
        var error: Unmanaged<CFError>?
        if let key = SecKeyCreateWithData(keyData as CFData, attributes as CFDictionary, &error) {
            return key
        }

        let stripped = stripSubjectPublicKeyInfoHeader(from: keyData)
        guard stripped != keyData else {
            throw error?.takeRetainedValue() as Error? ?? SchoolNetworkError.loginFailed("研究生系统登录公钥不可用。")
        }

        if let key = SecKeyCreateWithData(stripped as CFData, attributes as CFDictionary, &error) {
            return key
        }

        throw error?.takeRetainedValue() as Error? ?? SchoolNetworkError.loginFailed("研究生系统登录公钥不可用。")
    }

    func stripSubjectPublicKeyInfoHeader(from data: Data) -> Data {
        let bytes = [UInt8](data)
        let rsaEncryptionOID: [UInt8] = [0x30, 0x0d, 0x06, 0x09, 0x2a, 0x86, 0x48, 0x86, 0xf7, 0x0d, 0x01, 0x01, 0x01, 0x05, 0x00, 0x03]
        guard let oidRange = bytes.firstRange(of: rsaEncryptionOID) else { return data }
        var index = oidRange.upperBound
        guard index < bytes.count else { return data }

        if bytes[index] == 0x82 {
            index += 3
        } else if bytes[index] == 0x81 {
            index += 2
        } else {
            index += 1
        }

        guard index < bytes.count, bytes[index] == 0x00 else { return data }
        index += 1
        return Data(bytes[index..<bytes.count])
    }

    func decryptGraduateAES(_ cipherText: String) -> String {
        let cipherText = cipherText.trimmingCharacters(in: .whitespacesAndNewlines)
        let sentinel = Data("==gwJPTxzG0iY2qTiSUo7wB6".utf8).base64EncodedString()
        if cipherText == sentinel {
            return "-"
        }

        guard let cipherData = Data(base64Encoded: cipherText),
              let keyData = graduateAESKey.data(using: .utf8) else {
            return ""
        }

        return decryptGraduateAESECB(cipherData: cipherData, keyData: keyData)
    }

    func decryptGraduateAESECB(cipherData: Data, keyData: Data) -> String {
        let blockSize = kCCBlockSizeAES128
        let outputLength = cipherData.count + blockSize
        var output = Data(count: outputLength)
        var decryptedLength: size_t = 0

        let result = output.withUnsafeMutableBytes { outputBytes in
            cipherData.withUnsafeBytes { cipherBytes in
                keyData.withUnsafeBytes { keyBytes in
                    CCCrypt(
                        CCOperation(kCCDecrypt),
                        CCAlgorithm(kCCAlgorithmAES),
                        CCOptions(kCCOptionECBMode | kCCOptionPKCS7Padding),
                        keyBytes.baseAddress,
                        keyData.count,
                        nil,
                        cipherBytes.baseAddress,
                        cipherData.count,
                        outputBytes.baseAddress,
                        outputLength,
                        &decryptedLength
                    )
                }
            }
        }

        guard result == kCCSuccess else { return "" }
        output.removeSubrange(decryptedLength..<output.count)
        return String(data: output, encoding: .utf8) ?? ""
    }

    func parseGraduateLoginRedirect(
        from decryptedBody: String,
        rawBody: String? = nil,
        responseURL: URL? = nil,
        statusCode: Int? = nil
    ) throws -> String {
        let trimmed = decryptedBody.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else {
            throw SchoolNetworkError.loginFailed(
                "研究生系统登录响应无法解密。" +
                graduateLoginDebugSummary(rawBody: rawBody, responseURL: responseURL, statusCode: statusCode)
            )
        }

        guard let bodyData = trimmed.data(using: .utf8),
              let object = try? JSONSerialization.jsonObject(with: bodyData) as? [String: Any] else {
            throw SchoolNetworkError.loginFailed(
                "研究生系统登录响应格式异常。" +
                graduateLoginDebugSummary(rawBody: rawBody ?? trimmed, responseURL: responseURL, statusCode: statusCode)
            )
        }

        let status = graduateJSONValue(object["jg"])
        let message = graduateJSONValue(object["msg"]).trimmingCharacters(in: .whitespacesAndNewlines)
        let redirect = graduateJSONValue(object["url"]).trimmingCharacters(in: .whitespacesAndNewlines)

        if status == "1", !redirect.isEmpty {
            return redirect
        }

        if !message.isEmpty {
            throw SchoolNetworkError.loginFailed(message)
        }

        throw SchoolNetworkError.loginFailed(
            "研究生系统未确认登录成功，请刷新验证码后重试。" +
            graduateLoginDebugSummary(rawBody: rawBody ?? trimmed, responseURL: responseURL, statusCode: statusCode)
        )
    }

    func graduateJSONValue(_ value: Any?) -> String {
        switch value {
        case let string as String:
            return string
        case let number as NSNumber:
            return number.stringValue
        default:
            return ""
        }
    }

    func graduateLoginDebugSummary(rawBody: String?, responseURL: URL?, statusCode: Int?) -> String {
        let urlPart = responseURL?.absoluteString ?? "unknown"
        let statusPart = statusCode.map(String.init) ?? "unknown"

        #if DEBUG
        let snapshotName = "last_graduate_login_response.txt"
        let savedURL = rawBody.flatMap { persistDebugHTML($0, filename: snapshotName) }
        let filePart = savedURL?.lastPathComponent ?? snapshotName
        return L10n.text("HTTP: %@，URL: %@，调试文件: %@", statusPart, urlPart, filePart)
        #else
        return L10n.text("HTTP: %@，URL: %@。请确认校园网连接，或刷新验证码后重试。", statusPart, urlPart)
        #endif
    }

    func fetchGraduateDisplayName(
        from url: URL,
        timeoutInterval: TimeInterval? = nil
    ) async throws -> String {
        var request = makeRequest(url: url, method: "POST", referer: graduateURL(path: "/home/stulogin"))
        if let timeoutInterval {
            request.timeoutInterval = timeoutInterval
        }
        request.setValue("application/x-www-form-urlencoded", forHTTPHeaderField: "Content-Type")
        let (data, response) = try await data(for: preparedRequest(from: request))
        if let httpResponse = response as? HTTPURLResponse {
            updatePersistedCookies(from: httpResponse, requestURL: url)
        }

        let rawBody = String(data: data, encoding: .utf8) ?? ""
        if response.url?.path.lowercased().contains("stulogin") == true ||
            rawBody.lowercased().contains("stulogin") ||
            rawBody.lowercased().contains("</script>") {
            throw SchoolNetworkError.sessionExpired
        }
        let decryptedBody = decryptGraduateAES(rawBody)
        guard let bodyData = decryptedBody.data(using: .utf8),
              let array = try? JSONSerialization.jsonObject(with: bodyData) as? [[String: Any]],
              let name = array.first?["xm"] as? String,
              !name.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty else {
            throw URLError(.cannotParseResponse)
        }
        return name.trimmingCharacters(in: .whitespacesAndNewlines)
    }

    func verifyGraduateAuthenticatedSession(retryCount: Int) async -> Bool {
        guard let url = graduateURL(path: "/student/default/getxscardinfo") else {
            return false
        }

        for attempt in 0...retryCount {
            do {
                _ = try await fetchGraduateDisplayName(from: url)
                return true
            } catch {
            }

            if attempt < retryCount {
                try? await Task.sleep(nanoseconds: 300_000_000)
            }
        }

        return false
    }
}
