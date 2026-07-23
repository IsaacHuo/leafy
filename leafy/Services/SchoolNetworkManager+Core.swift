import Foundation
import SwiftSoup

extension SchoolNetworkManager {
    var allowsDebugSnapshots: Bool {
        #if DEBUG
        return UserDefaults.standard.bool(forKey: "leafy.debug.allowSchoolSnapshots")
        #else
        return false
        #endif
    }

    func decodedHTML(from data: Data) throws -> String {
        if let html = String(data: data, encoding: .utf8), !html.isEmpty {
            return html
        }

        let enc = CFStringConvertEncodingToNSStringEncoding(CFStringEncoding(CFStringEncodings.GB_18030_2000.rawValue))
        if let htmlGBK = String(data: data, encoding: String.Encoding(rawValue: enc)), !htmlGBK.isEmpty {
            return htmlGBK
        }

        throw URLError(.cannotDecodeRawData)
    }

    func data(for request: URLRequest) async throws -> (Data, URLResponse) {
        do {
            return try await session.data(for: request)
        } catch {
            throw mapSchoolNetworkError(error)
        }
    }

    func html(for request: URLRequest) async throws -> (String, HTTPURLResponse) {
        let preparedRequest = preparedRequest(from: request)
        let (data, response) = try await data(for: preparedRequest)

        guard let httpResponse = response as? HTTPURLResponse else {
            throw URLError(.badServerResponse)
        }

        updatePersistedCookies(from: httpResponse, requestURL: preparedRequest.url)

        guard (200...299).contains(httpResponse.statusCode) else {
            throw URLError(.badServerResponse)
        }

        return (try decodedHTML(from: data), httpResponse)
    }

    func mapSchoolNetworkError(_ error: Error) -> Error {
        if let schoolError = error as? SchoolNetworkError {
            return schoolError
        }

        let nsError = error as NSError
        guard nsError.domain == NSURLErrorDomain else {
            return error
        }
        let code = URLError.Code(rawValue: nsError.code)

        let campusOnlyCodes: Set<URLError.Code> = [
            .cannotFindHost,
            .cannotConnectToHost,
            .dnsLookupFailed,
            .networkConnectionLost,
            .notConnectedToInternet,
            .timedOut,
            .dataNotAllowed,
            .internationalRoamingOff
        ]

        return campusOnlyCodes.contains(code) ? SchoolNetworkError.campusNetworkRequired : error
    }

    func html(from url: URL) async throws -> (String, HTTPURLResponse) {
        try await html(for: makeRequest(url: url))
    }

    func makeRequest(url: URL, method: String = "GET") -> URLRequest {
        var request = URLRequest(url: url)
        request.httpMethod = method
        request.httpShouldHandleCookies = true
        request.cachePolicy = .reloadIgnoringLocalCacheData
        request.timeoutInterval = 8
        request.setValue("no-cache", forHTTPHeaderField: "Cache-Control")
        request.setValue("no-cache", forHTTPHeaderField: "Pragma")
        return request
    }

    func makeRequest(url: URL, method: String = "GET", referer: URL?) -> URLRequest {
        var request = makeRequest(url: url, method: method)
        if let referer {
            request.setValue(referer.absoluteString, forHTTPHeaderField: "Referer")
        }
        return request
    }

    func preparedRequest(from request: URLRequest) -> URLRequest {
        guard let url = request.url else { return request }

        syncPersistedCookiesToStorage(for: url)

        var request = request
        request.httpShouldHandleCookies = true
        request.cachePolicy = .reloadIgnoringLocalCacheData
        request.setValue("no-cache", forHTTPHeaderField: "Cache-Control")
        request.setValue("no-cache", forHTTPHeaderField: "Pragma")

        let cookieHeader = cookieHeaderValue(for: url)
        if !cookieHeader.isEmpty {
            request.setValue(cookieHeader, forHTTPHeaderField: "Cookie")
        }

        return request
    }

    func cookieHeaderValue(for url: URL) -> String {
        var mergedCookies = persistedCookieValues

        if let cookies = HTTPCookieStorage.shared.cookies(for: url) {
            for cookie in cookies {
                mergedCookies[cookie.name] = cookie.value
            }
        }

        return mergedCookies.keys.sorted().compactMap { name in
            guard let value = mergedCookies[name], !value.isEmpty else { return nil }
            return "\(name)=\(value)"
        }.joined(separator: "; ")
    }

    func syncPersistedCookiesToStorage(for url: URL) {
        guard !persistedCookieValues.isEmpty else { return }

        for (name, value) in persistedCookieValues where !value.isEmpty {
            let properties: [HTTPCookiePropertyKey: Any] = [
                .domain: url.host ?? "newjwxt.bjfu.edu.cn",
                .path: "/",
                .name: name,
                .value: value,
                .secure: false,
                .discard: true
            ]

            if let cookie = HTTPCookie(properties: properties) {
                HTTPCookieStorage.shared.setCookie(cookie)
            }
        }
    }

    func updatePersistedCookies(from response: HTTPURLResponse, requestURL: URL?) {
        guard let url = requestURL ?? response.url else { return }

        let responseHeaders: [String: String] = Dictionary(uniqueKeysWithValues: response.allHeaderFields.compactMap { key, value in
            guard let keyString = key as? String else { return nil }
            return (keyString, String(describing: value))
        })
        let responseCookies = HTTPCookie.cookies(withResponseHeaderFields: responseHeaders, for: url)
        var mergedCookies = persistedCookieValues

        for cookie in responseCookies {
            mergedCookies[cookie.name] = cookie.value
            HTTPCookieStorage.shared.setCookie(cookie)
        }

        if let storageCookies = HTTPCookieStorage.shared.cookies(for: url) {
            for cookie in storageCookies {
                mergedCookies[cookie.name] = cookie.value
            }
        }

        persistedCookieValues = mergedCookies
    }

    func clearPersistedCookies() {
        persistedCookieValues = [:]
        UserDefaults.standard.removeObject(forKey: CampusScopedDefaults.key("schoolSessionCookies"))

        let schoolURLs = [URL(string: baseURL), URL(string: graduateBaseURL)].compactMap { $0 }
        for url in schoolURLs {
            for cookie in HTTPCookieStorage.shared.cookies(for: url) ?? [] {
                HTTPCookieStorage.shared.deleteCookie(cookie)
            }
        }
    }

    func persistAuthenticatedIdentity(eduID: String, displayName: String? = nil) {
        let trimmedEduID = eduID.trimmingCharacters(in: .whitespacesAndNewlines)
        let trimmedDisplayName = displayName?.trimmingCharacters(in: .whitespacesAndNewlines)
        let sessionCookies = persistedCookieValues
        let landingURLString = lastLandingURLString
        let portal = currentPortal

        if !trimmedEduID.isEmpty {
            let identity = CampusIdentity(
                campusID: campusDescriptor.id,
                eduID: trimmedEduID,
                displayName: (trimmedDisplayName?.isEmpty == false) ? trimmedDisplayName : trimmedEduID,
                portal: currentPortal
            )
            CampusIdentityStore.activate(identity)

            if !sessionCookies.isEmpty {
                persistedCookieValues = sessionCookies
            }
            if let landingURLString {
                lastLandingURLString = landingURLString
            }
            currentPortal = portal
            CampusScopedDefaults.migrateLegacyValuesIfNeeded(
                keys: [
                    "isLoggedIn",
                    "schoolSessionCookies",
                    "schoolPortal",
                    "lastLandingURL",
                    "authenticatedEduID",
                    "authenticatedDisplayName"
                ],
                migrationID: "schoolSession",
                identity: identity
            )
        }

        authenticatedEduID = trimmedEduID.isEmpty ? nil : trimmedEduID
        authenticatedDisplayName = (trimmedDisplayName?.isEmpty == false) ? trimmedDisplayName : trimmedEduID
    }

    @MainActor
    func persistDemoIdentity(eduID: String, displayName: String) {
        persistAuthenticatedIdentity(eduID: eduID, displayName: displayName)
        isLoggedIn = true
    }

    func clearAuthenticatedIdentity() {
        authenticatedEduID = nil
        authenticatedDisplayName = nil
    }

    func clearSession() {
        clearPersistedCookies()
        HTTPCookieStorage.shared.removeCookies(since: Date.distantPast)
        lastLandingURLString = nil
        currentPortal = .undergraduate
        isLoggedIn = false
        clearAuthenticatedIdentity()
        CampusIdentityStore.clear()
        ReviewDemoMode.disable()
        clearDebugSnapshots()
    }

    func cancelInFlightRequests() {
        session.getAllTasks { tasks in
            tasks.forEach { $0.cancel() }
        }
    }

    func cookieDebugSummary(for url: URL?) -> String {
        #if DEBUG
        guard let url else { return "cookies: unavailable" }
        let names = Set(persistedCookieValues.keys)
            .union(HTTPCookieStorage.shared.cookies(for: url)?.map(\.name) ?? [])
            .sorted()
        return names.isEmpty ? "cookies: none" : "cookie names: \(names.joined(separator: ", "))"
        #else
        return "cookies: redacted"
        #endif
    }

    func debugDirectory() -> URL? {
        guard allowsDebugSnapshots else { return nil }

        let manager = FileManager.default
        if let caches = manager.urls(for: .cachesDirectory, in: .userDomainMask).first {
            let directory = caches.appendingPathComponent("leafy-debug", isDirectory: true)
            try? manager.createDirectory(at: directory, withIntermediateDirectories: true)
            return directory
        }

        if let documents = manager.urls(for: .documentDirectory, in: .userDomainMask).first {
            try? manager.createDirectory(at: documents, withIntermediateDirectories: true)
            return documents
        }

        return nil
    }

    @discardableResult
    func persistDebugHTML(_ html: String, filename: String) -> URL? {
        guard allowsDebugSnapshots else { return nil }
        guard let directory = debugDirectory() else { return nil }
        let url = directory.appendingPathComponent(filename)
        do {
            try redactedDebugSnapshot(html).write(to: url, atomically: true, encoding: .utf8)
            return url
        } catch {
            print("[SchoolNetworkManager] Failed to persist debug HTML:", error.localizedDescription)
            return nil
        }
    }

    func clearDebugSnapshots() {
        let manager = FileManager.default
        if let caches = manager.urls(for: .cachesDirectory, in: .userDomainMask).first {
            try? manager.removeItem(at: caches.appendingPathComponent("leafy-debug", isDirectory: true))
        }
    }

    private func redactedDebugSnapshot(_ raw: String) -> String {
        let text: String
        if let document = try? SwiftSoup.parse(raw) {
            _ = try? document.select("script,style,form,input,textarea,select,option").remove()
            let title = (try? document.title()) ?? ""
            let body = (try? document.body()?.text()) ?? ""
            text = "title: \(title)\nbody: \(body)"
        } else {
            text = raw
        }

        let bounded = String(text.prefix(2_000))
        let patterns = [
            #"[A-Z0-9._%+-]+@[A-Z0-9.-]+\.[A-Z]{2,}"#,
            #"(?<!\d)\d{6,}(?!\d)"#
        ]
        return patterns.reduce(bounded) { value, pattern in
            guard let regex = try? NSRegularExpression(pattern: pattern, options: [.caseInsensitive]) else {
                return value
            }
            let range = NSRange(value.startIndex..., in: value)
            return regex.stringByReplacingMatches(in: value, range: range, withTemplate: "[REDACTED]")
        }
    }

    func pageDebugSummary(html: String, responseURL: URL?, snapshotName: String) -> String {
        let title: String = {
            guard let document = try? SwiftSoup.parse(html) else { return L10n.text("无标题") }
            return ((try? document.title())?.trimmingCharacters(in: .whitespacesAndNewlines)).flatMap { $0.isEmpty ? nil : $0 } ?? L10n.text("无标题")
        }()

        let bodyText: String = {
            guard let document = try? SwiftSoup.parse(html) else { return "" }
            let raw = ((try? document.body()?.text()) ?? "")
                .replacingOccurrences(of: "\n", with: " ")
                .replacingOccurrences(of: "\t", with: " ")
                .trimmingCharacters(in: .whitespacesAndNewlines)
            return String(raw.prefix(80))
        }()

        let urlPart = responseURL?.absoluteString ?? "unknown"

        #if DEBUG
        let textPart = bodyText.isEmpty ? "" : L10n.text("，正文前缀：%@", bodyText)
        let cookiePart = responseURL.map { L10n.text("，%@", cookieDebugSummary(for: $0)) } ?? ""
        return L10n.text("URL: %@，标题: %@%@%@", urlPart, title, textPart, cookiePart)
        #else
        return L10n.text("页面返回异常，URL: %@，标题: %@。请确认校园网连接，或重新登录后重试。", urlPart, title)
        #endif
    }

    func isLoginPage(_ html: String) -> Bool {
        let markers = [
            "Logon.do?method=logon",
            "stulogin_do",
            "name=\"RANDOMCODE\"",
            "name='RANDOMCODE'",
            "verifycode.servlet",
            "verificationcode",
            "pubkey",
            "验证码"
        ]
        return markers.contains { html.contains($0) }
    }

    func containsAny(_ text: String, markers: [String]) -> Bool {
        markers.contains { text.contains($0) }
    }

    func isAuthenticatedResponse(url: URL?, html: String) -> Bool {
        if isLoginPage(html) {
            return false
        }

        let urlString = url?.absoluteString ?? ""
        let urlMarkers = [
            "xsMain.jsp",
            "/jsxsd/framework/",
            "/jsxsd/xsks/",
            "/jsxsd/xskb/",
            "/jsxsd/kscj/"
        ]

        if containsAny(urlString, markers: urlMarkers), !urlString.contains("Logon.do?method=logon") {
            return true
        }

        let htmlMarkers = [
            "xsMain.jsp",
            "退出系统",
            "安全退出",
            "个人信息",
            "学生课表",
            "成绩查询"
        ]

        return containsAny(html, markers: htmlMarkers)
    }

    func extractLoginMessage(from html: String) -> String? {
        let ignoredMessages: Set<String> = [
            "请输入完整的登陆信息！",
            "系统检查到您两次登录的账号不一致，是否确定用新账号登录？"
        ]
        let patterns = [
            #"alert\(['"]([^'"]+)['"]\)"#,
            #"showMsg\(['"]([^'"]+)['"]\)"#,
            #"<font[^>]*color=['"]?red['"]?[^>]*>([^<]+)</font>"#
        ]

        for pattern in patterns {
            guard let regex = try? NSRegularExpression(pattern: pattern, options: [.caseInsensitive]) else {
                continue
            }

            let range = NSRange(html.startIndex..., in: html)
            guard let match = regex.firstMatch(in: html, options: [], range: range),
                  match.numberOfRanges > 1,
                  let captureRange = Range(match.range(at: 1), in: html) else {
                continue
            }

            let message = String(html[captureRange]).trimmingCharacters(in: .whitespacesAndNewlines)
            if !message.isEmpty && !ignoredMessages.contains(message) {
                return message
            }
        }

        return nil
    }

    func verifyAuthenticatedSession(retryCount: Int = 1) async -> Bool {
        if currentPortal == .graduate {
            return await verifyGraduateAuthenticatedSession(retryCount: retryCount)
        }

        guard let url = URL(string: "\(baseURL)/jsxsd/framework/xsMain.jsp") else {
            return false
        }

        for attempt in 0...retryCount {
            do {
                let (html, response) = try await html(from: url)
                if isAuthenticatedResponse(url: response.url, html: html) {
                    return true
                }
            } catch {
            }

            if attempt < retryCount {
                try? await Task.sleep(nanoseconds: 300_000_000)
            }
        }

        return false
    }

    func preflightAuthenticatedSession(
        timeoutInterval: TimeInterval = 1.5
    ) async -> SchoolSessionPreflightResult {
        if ReviewDemoMode.isEnabled {
            return .authenticated
        }

        guard hasCachedIdentity, isLoggedIn else {
            return .requiresReauthentication
        }

        if let lastAuthenticatedSessionValidationAt,
           Date().timeIntervalSince(lastAuthenticatedSessionValidationAt) < 5 {
            return .authenticated
        }

        if currentPortal == .graduate {
            guard let url = graduateURL(path: "/student/default/getxscardinfo") else {
                return .networkUnavailable
            }

            do {
                _ = try await fetchGraduateDisplayName(
                    from: url,
                    timeoutInterval: timeoutInterval
                )
                lastAuthenticatedSessionValidationAt = Date()
                return .authenticated
            } catch {
                if SchoolReauthentication.requiresReauthentication(error) {
                    clearPersistedCookies()
                    isLoggedIn = false
                    return .requiresReauthentication
                }
                return .networkUnavailable
            }
        }

        guard let url = URL(string: "\(baseURL)/jsxsd/framework/xsMain.jsp") else {
            return .networkUnavailable
        }

        var request = makeRequest(url: url)
        request.timeoutInterval = timeoutInterval

        do {
            let (html, response) = try await html(for: request)
            if isAuthenticatedResponse(url: response.url, html: html) {
                lastAuthenticatedSessionValidationAt = Date()
                return .authenticated
            }
            if isLoginPage(html) {
                clearPersistedCookies()
                isLoggedIn = false
                return .requiresReauthentication
            }
            return .networkUnavailable
        } catch {
            return .networkUnavailable
        }
    }

    func invalidateSessionIfNeeded() async -> Bool {
        let stillAuthenticated = await verifyAuthenticatedSession(retryCount: 1)
        if !stillAuthenticated {
            clearPersistedCookies()
            // Keep the cached student identity so the app can open offline and
            // community identity can still be restored on non-campus networks.
            await MainActor.run { self.isLoggedIn = false }
        }
        return !stillAuthenticated
    }

    func persistLandingURL(_ url: URL?) {
        guard let url else { return }
        let absoluteString = url.absoluteString
        guard !absoluteString.contains("Logon.do?method=logon") else { return }
        lastLandingURLString = absoluteString
    }
}
