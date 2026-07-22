nonisolated enum CampusAIServiceError: LocalizedError, Equatable {
    case emptyMessage
    case missingAPIKey
    case invalidBaseURL
    case managedServiceUnavailable
    case quotaExhausted(String)
    case providerRejected(String)
    case invalidProviderResponse
    case incompleteStream

    var errorDescription: String? {
        switch self {
        case .emptyMessage:
            return "请先输入想问的问题。"
        case .missingAPIKey:
            return "请先在 Leafy 设置中填写 DeepSeek API Key。"
        case .invalidBaseURL:
            return "Base URL 设置不正确，请使用 HTTPS 地址。"
        case .managedServiceUnavailable:
            return "Leafy AI 服务暂时不可用，请稍后再试。"
        case .quotaExhausted(let message):
            return message
        case .providerRejected(let message):
            return message
        case .invalidProviderResponse:
            return "AI 助手返回了无法识别的响应。"
        case .incompleteStream:
            return "联网连接中断，请重试。"
        }
    }
}

nonisolated private extension String {
    var nonEmptyTrimmed: String? {
        let trimmed = trimmingCharacters(in: .whitespacesAndNewlines)
        return trimmed.isEmpty ? nil : trimmed
    }
}

nonisolated enum CampusAIStreamEvent: Equatable {
    case delta(String)
    case reasoningDelta(String)
    case quota(CampusAIQuotaSnapshot)
    case agentStatus(String)
    case agentStep(CampusAIAgentTraceStep)
    case agentTool(CampusAIAgentToolEvent)
    case agentSearchResults([CampusAISearchResultPreview])
    case agentCitation(CampusAICitation)
    case done(CampusAIResponse)
    case error(String)
}

nonisolated struct CampusAISSEParser {
    private var pendingData = Data()
    private var buffer = ""
    private let decoder = JSONDecoder()
    private var accumulatedAnswer = ""
    private var accumulatedReasoning = ""
    private var finishReason: String?
    private var emittedDone = false
    private let requiresExplicitTerminal: Bool

    init(requiresExplicitTerminal: Bool = false) {
        self.requiresExplicitTerminal = requiresExplicitTerminal
    }

    mutating func append(_ data: Data) throws -> [CampusAIStreamEvent] {
        pendingData.append(data)
        guard let string = String(data: pendingData, encoding: .utf8) else {
            return []
        }
        pendingData.removeAll(keepingCapacity: true)
        guard !string.isEmpty else {
            return []
        }
        buffer += string
        return try drainCompleteBlocks(includeRemainder: false)
    }

    mutating func finish() throws -> [CampusAIStreamEvent] {
        if !pendingData.isEmpty {
            guard let string = String(data: pendingData, encoding: .utf8) else {
                throw CampusAIServiceError.invalidProviderResponse
            }
            buffer += string
            pendingData.removeAll(keepingCapacity: true)
        }
        return try drainCompleteBlocks(includeRemainder: true)
    }

    private mutating func drainCompleteBlocks(includeRemainder: Bool) throws -> [CampusAIStreamEvent] {
        var events: [CampusAIStreamEvent] = []
        while let range = buffer.range(of: "\n\n") ?? buffer.range(of: "\r\n\r\n") {
            let block = String(buffer[..<range.lowerBound])
            buffer.removeSubrange(..<range.upperBound)
            events.append(contentsOf: try parseBlock(block))
        }

        if includeRemainder, !buffer.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
            events.append(contentsOf: try parseBlock(buffer))
            buffer = ""
        }
        if includeRemainder, !emittedDone {
            if requiresExplicitTerminal || accumulatedAnswer.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
                throw CampusAIServiceError.incompleteStream
            }
            emittedDone = true
            events.append(doneEvent())
        }
        return events
    }

    private mutating func parseBlock(_ block: String) throws -> [CampusAIStreamEvent] {
        let dataLines = block
            .replacingOccurrences(of: "\r\n", with: "\n")
            .split(separator: "\n", omittingEmptySubsequences: false)
            .compactMap { line -> String? in
                if line.hasPrefix(":") {
                    return nil
                }
                guard line.hasPrefix("data:") else {
                    return nil
                }
                let value = line.dropFirst(5)
                if value.first == " " {
                    return String(value.dropFirst())
                }
                return String(value)
            }
        let payloadText = dataLines.joined(separator: "\n").trimmingCharacters(in: .whitespacesAndNewlines)
        guard !payloadText.isEmpty else {
            return []
        }
        if payloadText == "[DONE]" {
            guard accumulatedAnswer.nonEmptyTrimmed != nil else {
                throw CampusAIServiceError.invalidProviderResponse
            }
            emittedDone = true
            return [doneEvent()]
        }

        let payloadData = Data(payloadText.utf8)
        if let managedPayload = try? decoder.decode(CampusAIManagedStreamPayload.self, from: payloadData),
           managedPayload.type != nil {
            return try parseManagedPayload(managedPayload)
        }

        let payload: CampusAIProviderStreamPayload
        do {
            payload = try decoder.decode(CampusAIProviderStreamPayload.self, from: payloadData)
        } catch {
            throw CampusAIServiceError.invalidProviderResponse
        }

        if let providerError = payload.error {
            let message = providerError.message?.nonEmptyTrimmed ?? "AI 助手暂时不可用，请稍后重试。"
            throw CampusAIServiceError.providerRejected(CampusAIService.redactProviderError(message))
        }

        let choices = payload.choices ?? []
        if let newFinishReason = choices.compactMap(\.finishReason).last?.nonEmptyTrimmed {
            finishReason = newFinishReason
        }

        let reasoningDelta = choices
            .compactMap { $0.delta?.reasoningContent ?? $0.message?.reasoningContent }
            .joined()
        let contentDelta = choices
            .compactMap { $0.delta?.content ?? $0.message?.content }
            .joined()

        var events: [CampusAIStreamEvent] = []
        if !reasoningDelta.isEmpty {
            accumulatedReasoning += reasoningDelta
            events.append(.reasoningDelta(reasoningDelta))
        }
        if !contentDelta.isEmpty {
            accumulatedAnswer += contentDelta
            events.append(.delta(contentDelta))
        }
        return events
    }

    private mutating func parseManagedPayload(_ payload: CampusAIManagedStreamPayload) throws -> [CampusAIStreamEvent] {
        switch payload.type {
        case "delta":
            let text = payload.text ?? ""
            accumulatedAnswer += text
            return text.isEmpty ? [] : [.delta(text)]
        case "reasoning_delta":
            let text = payload.text ?? ""
            accumulatedReasoning += text
            return text.isEmpty ? [] : [.reasoningDelta(text)]
        case "quota":
            guard let quota = payload.quota else { return [] }
            return [.quota(quota)]
        case "agent_status":
            let text = payload.text ?? ""
            return text.isEmpty ? [] : [.agentStatus(text)]
        case "agent_step":
            guard let step = payload.step else { return [] }
            return [.agentStep(step)]
        case "agent_tool":
            guard let tool = payload.tool else { return [] }
            return [.agentTool(tool)]
        case "agent_citation":
            guard let citation = payload.citation else { return [] }
            return [.agentCitation(citation)]
        case "agent_search_results":
            guard let results = payload.results, !results.isEmpty else { return [] }
            return [.agentSearchResults(results)]
        case "done":
            emittedDone = true
            let answer = payload.answer ?? accumulatedAnswer
            let reasoning = payload.reasoning ?? accumulatedReasoning
            guard answer.nonEmptyTrimmed != nil else {
                throw CampusAIServiceError.invalidProviderResponse
            }
            return [
                .done(
                    CampusAIResponse(
                        answer: answer,
                        reasoning: reasoning,
                        finishReason: payload.finishReason,
                        suggestedTitle: payload.suggestedTitle,
                        summary: payload.summary,
                        actions: payload.actions ?? [],
                        citations: payload.citations ?? [],
                        agentTrace: payload.agentTrace ?? payload.agentTraceSnake ?? [],
                        deliverables: payload.deliverables ?? []
                    )
                )
            ]
        case "error":
            let message = payload.error?.nonEmptyTrimmed ?? "AI 助手暂时不可用，请稍后重试。"
            throw CampusAIServiceError.providerRejected(CampusAIService.redactProviderError(message))
        default:
            return []
        }
    }

    private func doneEvent() -> CampusAIStreamEvent {
        .done(
            CampusAIResponse(
                answer: accumulatedAnswer,
                reasoning: accumulatedReasoning,
                finishReason: finishReason
            )
        )
    }
}

nonisolated private struct CampusAIProviderStreamPayload: Decodable {
    let choices: [Choice]?
    let error: ProviderError?

    struct Choice: Decodable {
        let delta: MessageDelta?
        let message: MessageDelta?
        let finishReason: String?

        enum CodingKeys: String, CodingKey {
            case delta
            case message
            case finishReason = "finish_reason"
        }
    }

    struct MessageDelta: Decodable {
        let content: String?

        let reasoningContent: String?

        enum CodingKeys: String, CodingKey {
            case content
            case reasoningContent = "reasoning_content"
        }
    }

    struct ProviderError: Decodable {
        let message: String?
    }
}

nonisolated private struct CampusAIManagedStreamPayload: Decodable {
    let type: String?
    let text: String?
    let answer: String?
    let reasoning: String?
    let finishReason: String?
    let suggestedTitle: String?
    let summary: String?
    let actions: [CampusAIActionDraft]?
    let citations: [CampusAICitation]?
    let agentTrace: [CampusAIAgentTraceStep]?
    let agentTraceSnake: [CampusAIAgentTraceStep]?
    let deliverables: [CampusAIDeliverable]?
    let step: CampusAIAgentTraceStep?
    let tool: CampusAIAgentToolEvent?
    let citation: CampusAICitation?
    let results: [CampusAISearchResultPreview]?
    let error: String?
    let quota: CampusAIQuotaSnapshot?

    enum CodingKeys: String, CodingKey {
        case type
        case text
        case answer
        case reasoning
        case finishReason = "finish_reason"
        case suggestedTitle = "suggested_title"
        case summary
        case actions
        case citations
        case agentTrace
        case agentTraceSnake = "agent_trace"
        case deliverables
        case step
        case tool
        case citation
        case results
        case error
        case quota
    }
}

nonisolated struct CampusAIChatCompletionsPayload: Encodable, Hashable {
    let model: String
    let messages: [Message]
    let stream: Bool
    let thinking: Thinking
    let streamOptions: StreamOptions
    let temperature: Double
    let maxTokens: Int?
    let user: String?

    enum CodingKeys: String, CodingKey {
        case model
        case messages
        case stream
        case thinking
        case streamOptions = "stream_options"
        case temperature
        case maxTokens = "max_tokens"
        case user
    }

    struct Thinking: Encodable, Hashable {
        let type: String

        static let enabled = Thinking(type: "enabled")
    }

    struct StreamOptions: Encodable, Hashable {
        let includeUsage: Bool

        enum CodingKeys: String, CodingKey {
            case includeUsage = "include_usage"
        }

        static let includeUsage = StreamOptions(includeUsage: true)
    }

    struct Message: Encodable, Hashable {
        let role: String
        let content: String
    }
}

nonisolated struct CampusAIActionPlannerPayload: Encodable, Hashable {
    let model: String
    let messages: [Message]
    let stream: Bool
    let temperature: Double
    let maxTokens: Int
    let user: String?

    enum CodingKeys: String, CodingKey {
        case model
        case messages
        case stream
        case temperature
        case maxTokens = "max_tokens"
        case user
    }

    struct Message: Encodable, Hashable {
        let role: String
        let content: String
    }
}

nonisolated private struct CampusAIActionPlannerProviderResponse: Decodable {
    let choices: [Choice]?

    struct Choice: Decodable {
        let message: Message?
    }

    struct Message: Decodable {
        let content: String?
    }
}

nonisolated private struct CampusAIActionPlannerResult: Decodable {
    let actions: [CampusAIActionDraft]
}

nonisolated struct CampusAIService {
    var streamInvoke: @Sendable (CampusAIRequest, CampusAIUserSettings) -> AsyncThrowingStream<CampusAIStreamEvent, Error>

    init(
        streamInvoke: @escaping @Sendable (CampusAIRequest, CampusAIUserSettings) -> AsyncThrowingStream<CampusAIStreamEvent, Error> = CampusAIService.invokeStream
    ) {
        self.streamInvoke = streamInvoke
    }

    func send(
        message: String,
        context: CampusAIContextPayload,
        recentMessages: [CampusAIChatMessage],
        settings: CampusAIUserSettings = .defaultValue,
        outputMode: CampusAIOutputMode = .automatic
    ) async throws -> CampusAIResponse {
        var accumulatedAnswer = ""
        var accumulatedReasoning = ""
        var finalResponse: CampusAIResponse?
        for try await event in stream(
            message: message,
            context: context,
            recentMessages: recentMessages,
            settings: settings,
            outputMode: outputMode
        ) {
            switch event {
            case .delta(let text):
                accumulatedAnswer += text
            case .reasoningDelta(let text):
                accumulatedReasoning += text
            case .quota:
                break
            case .agentStatus, .agentStep, .agentTool, .agentSearchResults, .agentCitation:
                break
            case .done(let response):
                finalResponse = response
            case .error(let message):
                throw CampusAIServiceError.providerRejected(message)
            }
        }
        var response = finalResponse ?? CampusAIResponse(answer: accumulatedAnswer)
        if response.answer.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
            response.answer = accumulatedAnswer
        }
        if response.reasoning.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
            response.reasoning = accumulatedReasoning
        }
        return response
    }

    func stream(
        message: String,
        context: CampusAIContextPayload,
        recentMessages: [CampusAIChatMessage],
        settings: CampusAIUserSettings = .defaultValue,
        outputMode: CampusAIOutputMode = .automatic
    ) -> AsyncThrowingStream<CampusAIStreamEvent, Error> {
        let trimmed = message.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else {
            return AsyncThrowingStream { continuation in
                continuation.finish(throwing: CampusAIServiceError.emptyMessage)
            }
        }
        let normalizedSettings = settings.normalizedForLocalRuntime
        let capabilities = CampusAICapabilitySet(settings: normalizedSettings)
        let localRetrieval = capabilities.localSearchEnabled
            ? CampusAILocalKnowledgeIndex.search(query: trimmed, context: context)
            : .empty(query: trimmed)
        let request = CampusAIRequest(
            message: trimmed,
            context: context,
            recentMessages: recentMessages,
            model: normalizedSettings.serviceMode == .leafyManaged
                ? CampusAIModelCatalog.flash.modelIdentifier
                : normalizedSettings.selectedModel.modelIdentifier,
            userSystemPrompt: normalizedSettings.effectiveSystemPrompt,
            contextSettings: normalizedSettings.contextSettings,
            agentMode: .auto,
            webSearchEnabled: capabilities.webSearchEnabled,
            capabilities: capabilities,
            localRetrieval: localRetrieval,
            outputMode: outputMode
        )
        return streamInvoke(request, normalizedSettings)
    }

    private static func invokeStream(
        _ request: CampusAIRequest,
        settings: CampusAIUserSettings
    ) -> AsyncThrowingStream<CampusAIStreamEvent, Error> {
        let normalizedSettings = settings.normalizedForLocalRuntime
        if normalizedSettings.serviceMode == .leafyManaged {
            return invokeManagedStream(request, settings: normalizedSettings)
        }
        if request.agentMode == .auto,
           request.webSearchEnabled,
           request.capabilities.webSearchEnabled {
            return CampusAIResearchAgent.invokeStream(request, settings: normalizedSettings)
        }
        return invokeDirectStream(request, settings: normalizedSettings)
    }

    static func invokeDirectStream(
        _ request: CampusAIRequest,
        settings: CampusAIUserSettings,
        usePersonalContext: Bool = true
    ) -> AsyncThrowingStream<CampusAIStreamEvent, Error> {
        AsyncThrowingStream { continuation in
            let task = Task {
                do {
                    let shouldCreateArtifact = CampusAIArtifactIntentResolver.shouldGenerateArtifact(
                        message: request.message,
                        mode: request.outputMode
                    )
                    let usesDirectAgent = shouldRunDirectAgent(request) || shouldCreateArtifact
                    var directAgentTrace: [CampusAIAgentTraceStep] = []
                    if usesDirectAgent {
                        let planningStep = directAgentStep(
                            id: "direct-agent-planner",
                            title: "任务拆解",
                            detail: "使用自备 API Key 进行非联网 agent 规划。",
                            status: "completed"
                        )
                        directAgentTrace.append(planningStep)
                        continuation.yield(.agentStatus("正在拆解任务"))
                        continuation.yield(.agentStep(planningStep))
                    }

                    let apiKey = try CampusAIAPIKeyResolver().resolve(for: settings)
                    let urlRequest = try makeChatCompletionsRequest(
                        for: request,
                        baseURLString: settings.selectedProvider.baseURLString,
                        apiKey: apiKey,
                        usePersonalContext: usePersonalContext
                    )
                    let (bytes, response) = try await URLSession.shared.bytes(for: urlRequest)
                    var finalResponse: CampusAIResponse?
                    let yieldProviderEvents: ([CampusAIStreamEvent]) -> Void = { events in
                        for event in events {
                            if case .done(let response) = event {
                                finalResponse = response
                            } else {
                                continuation.yield(event)
                            }
                        }
                    }
                    guard let httpResponse = response as? HTTPURLResponse else {
                        throw CampusAIServiceError.invalidProviderResponse
                    }
                    guard (200..<300).contains(httpResponse.statusCode) else {
                        let body = try await providerErrorBody(from: bytes)
                        throw CampusAIServiceError.providerRejected(
                            providerHTTPErrorMessage(statusCode: httpResponse.statusCode, body: body)
                        )
                    }

                    let contentType = httpResponse.value(forHTTPHeaderField: "Content-Type")?.lowercased() ?? ""
                    if contentType.contains("text/event-stream") {
                        var parser = CampusAISSEParser()
                        var chunk = Data()
                        chunk.reserveCapacity(4_096)
                        for try await byte in bytes {
                            try Task.checkCancellation()
                            chunk.append(byte)
                            if chunk.count >= 4_096 {
                                yieldProviderEvents(try parser.append(chunk))
                                chunk.removeAll(keepingCapacity: true)
                            }
                        }

                        if !chunk.isEmpty {
                            yieldProviderEvents(try parser.append(chunk))
                        }

                        yieldProviderEvents(try parser.finish())
                    } else {
                        let body = try await providerBody(from: bytes)
                        yieldProviderEvents(try providerEvents(from: body))
                    }
                    if var finalResponse {
                        if usesDirectAgent {
                            let synthesisStep = directAgentStep(
                                id: "direct-agent-synthesis",
                                title: "整合回答",
                                detail: usePersonalContext
                                    ? "结合必要的个人上下文生成回答。"
                                    : "根据当前问题生成回答。",
                                status: "completed"
                            )
                            directAgentTrace.append(synthesisStep)
                            continuation.yield(.agentStep(synthesisStep))
                            continuation.yield(.agentStatus(shouldCreateArtifact ? "正在整理卡片" : "正在整理回答"))
                            if shouldCreateArtifact {
                                continuation.yield(.agentTool(.init(name: "completion.plan", status: "running")))
                            }
                        }
                        if shouldCreateArtifact {
                            finalResponse.artifactState = .generating
                            CampusAIDiagnostics.artifact(.generating, requestID: request.requestID)
                        }
                        do {
                            let completionPlan = try await directCompletionPlan(
                                request: request,
                                answer: finalResponse.answer,
                                settings: settings,
                                apiKey: apiKey
                            )
                            finalResponse.actions = request.actionPlanningRequested
                                ? completionPlan.actions
                                : []
                            if shouldCreateArtifact {
                                guard let artifact = completionPlan.artifact,
                                      let deliverable = CampusAIArtifactAssembler.deliverable(
                                        from: artifact,
                                        request: request
                                      )
                                else {
                                    throw CampusAICompletionPlanError.artifactMissing
                                }
                                finalResponse.deliverables = [deliverable]
                                finalResponse.artifactState = .ready
                                finalResponse.artifactErrorMessage = nil
                                CampusAIDiagnostics.artifact(.ready, requestID: request.requestID)
                            }
                        } catch {
                            CampusAIDiagnostics.failure(error, stage: "completion.plan", requestID: request.requestID)
                            finalResponse.actions = []
                            if shouldCreateArtifact {
                                finalResponse.artifactState = .failed
                                finalResponse.artifactErrorMessage = error.localizedDescription
                                CampusAIDiagnostics.artifact(.failed, requestID: request.requestID)
                            }
                        }
                        if usesDirectAgent {
                            let shouldPublishActionEvents = CampusAICompletionPlanEventPolicy
                                .shouldPublishActionEvents(actionCount: finalResponse.actions.count)
                            if shouldPublishActionEvents {
                                let actionStep = directAgentStep(
                                    id: "direct-agent-action-plan",
                                    title: "动作规划",
                                    detail: "已生成 \(finalResponse.actions.count) 个待确认动作。",
                                    status: "completed",
                                    tool: "completion.plan"
                                )
                                directAgentTrace.append(actionStep)
                                continuation.yield(.agentStep(actionStep))
                            }
                            if shouldCreateArtifact || shouldPublishActionEvents {
                                continuation.yield(.agentTool(.init(
                                    name: "completion.plan",
                                    status: "completed",
                                    resultCount: finalResponse.actions.count + finalResponse.deliverables.count
                                )))
                            }
                            finalResponse.agentTrace = mergeAgentTrace(
                                finalResponse.agentTrace,
                                directAgentTrace
                            )
                        }
                        continuation.yield(.done(finalResponse))
                    }
                    continuation.finish()
                } catch is CancellationError {
                    continuation.finish()
                } catch {
                    continuation.finish(throwing: error)
                }
            }

            continuation.onTermination = { _ in
                task.cancel()
            }
        }
    }

    private static func invokeManagedStream(
        _ request: CampusAIRequest,
        settings: CampusAIUserSettings
    ) -> AsyncThrowingStream<CampusAIStreamEvent, Error> {
        AsyncThrowingStream { continuation in
            let task = Task {
                do {
                    let urlRequest = try await makeManagedFunctionRequest(for: request, settings: settings)
                    let (bytes, response) = try await URLSession.shared.bytes(for: urlRequest)
                    guard let httpResponse = response as? HTTPURLResponse else {
                        throw CampusAIServiceError.invalidProviderResponse
                    }
                    guard (200..<300).contains(httpResponse.statusCode) else {
                        let body = try await providerErrorBody(from: bytes)
                        let message = managedHTTPErrorMessage(statusCode: httpResponse.statusCode, body: body)
                        if httpResponse.statusCode == 402 {
                            throw CampusAIServiceError.quotaExhausted(message)
                        }
                        throw CampusAIServiceError.providerRejected(message)
                    }

                    var parser = CampusAISSEParser(requiresExplicitTerminal: true)
                    var chunk = Data()
                    chunk.reserveCapacity(4_096)
                    for try await byte in bytes {
                        try Task.checkCancellation()
                        chunk.append(byte)
                        if chunk.count >= 4_096 {
                            for event in try parser.append(chunk) {
                                continuation.yield(event)
                            }
                            chunk.removeAll(keepingCapacity: true)
                        }
                    }

                    if !chunk.isEmpty {
                        for event in try parser.append(chunk) {
                            continuation.yield(event)
                        }
                    }

                    for event in try parser.finish() {
                        continuation.yield(event)
                    }
                    continuation.finish()
                } catch is CancellationError {
                    continuation.finish()
                } catch {
                    continuation.finish(throwing: error)
                }
            }

            continuation.onTermination = { _ in
                task.cancel()
            }
        }
    }

    static func makeChatCompletionsRequest(
        for request: CampusAIRequest,
        baseURLString: String,
        apiKey: String,
        usePersonalContext: Bool = true
    ) throws -> URLRequest {
        let url = try chatCompletionsURL(baseURLString: baseURLString)
        var urlRequest = URLRequest(url: url)
        urlRequest.httpMethod = "POST"
        urlRequest.setValue("Bearer \(apiKey)", forHTTPHeaderField: "Authorization")
        urlRequest.setValue("text/event-stream", forHTTPHeaderField: "Accept")
        urlRequest.setValue("application/json", forHTTPHeaderField: "Content-Type")
        urlRequest.httpBody = try providerJSONEncoder().encode(
            chatCompletionsPayload(
                for: request,
                usePersonalContext: usePersonalContext
            )
        )
        return urlRequest
    }

    static func shouldRunDirectAgent(_ request: CampusAIRequest) -> Bool {
        guard request.agentMode == .auto else { return false }
        let text = request.message.lowercased()
        return [
            "拆解",
            "规划",
            "计划",
            "比较",
            "分析",
            "结合",
            "安排",
            "方案",
            "多步",
            "提醒",
            "重要日期",
            "打开"
        ].contains { text.contains($0) }
    }

    private static func directAgentStep(
        id: String,
        title: String,
        detail: String,
        status: String,
        tool: String? = nil,
        role: String? = nil
    ) -> CampusAIAgentTraceStep {
        CampusAIAgentTraceStep(
            id: id,
            kind: tool == nil ? "agent" : "tool",
            title: title,
            detail: detail,
            status: status,
            tool: tool,
            role: role,
            timestamp: ISO8601DateFormatter().string(from: Date())
        )
    }

    private static func mergeAgentTrace(
        _ existing: [CampusAIAgentTraceStep],
        _ additional: [CampusAIAgentTraceStep]
    ) -> [CampusAIAgentTraceStep] {
        var seen = Set(existing.map(\.id))
        var merged = existing
        for step in additional where !seen.contains(step.id) {
            seen.insert(step.id)
            merged.append(step)
        }
        return merged
    }

    static func makeActionPlannerRequest(
        for request: CampusAIRequest,
        answer: String,
        baseURLString: String,
        apiKey: String
    ) throws -> URLRequest {
        let url = try chatCompletionsURL(baseURLString: baseURLString)
        var urlRequest = URLRequest(url: url)
        urlRequest.httpMethod = "POST"
        urlRequest.setValue("Bearer \(apiKey)", forHTTPHeaderField: "Authorization")
        urlRequest.setValue("application/json", forHTTPHeaderField: "Accept")
        urlRequest.setValue("application/json", forHTTPHeaderField: "Content-Type")
        urlRequest.httpBody = try providerJSONEncoder().encode(actionPlannerPayload(for: request, answer: answer))
        return urlRequest
    }

    static func makeManagedFunctionRequest(
        for request: CampusAIRequest,
        settings: CampusAIUserSettings
    ) async throws -> URLRequest {
        try await CommunityService.shared.ensureAnonymousSession()
        let client = try LeafySupabase.shared.requireClient()
        let config = try LeafySupabase.shared.requireConfig()
        let session = try await client.auth.session
        let appTransaction = await CampusAIManagedEntitlementClient.optionalAppTransactionPayload()

        var url = config.url
        url.appendPathComponent("functions")
        url.appendPathComponent("v1")
        url.appendPathComponent(config.campusAIFunctionName)

        var urlRequest = URLRequest(url: url)
        urlRequest.httpMethod = "POST"
        urlRequest.setValue("Bearer \(session.accessToken)", forHTTPHeaderField: "Authorization")
        urlRequest.setValue(config.publishableKey, forHTTPHeaderField: "apikey")
        urlRequest.setValue("text/event-stream", forHTTPHeaderField: "Accept")
        urlRequest.setValue("application/json", forHTTPHeaderField: "Content-Type")
        urlRequest.httpBody = try providerJSONEncoder().encode(
            CampusAIManagedFunctionRequest(
                request: request,
                appTransactionID: appTransaction?.appTransactionID,
                appTransactionJWS: appTransaction?.jwsRepresentation,
                serviceMode: settings.serviceMode
            )
        )
        return urlRequest
    }

    static func chatCompletionsURL(baseURLString: String) throws -> URL {
        guard let trimmed = baseURLString.nonEmptyTrimmed,
              let baseURL = URL(string: trimmed),
              baseURL.scheme?.lowercased() == "https",
              baseURL.host != nil
        else {
            throw CampusAIServiceError.invalidBaseURL
        }
        return baseURL.appendingPathComponent("chat/completions")
    }

    static func chatCompletionsPayload(
        for request: CampusAIRequest,
        usePersonalContext: Bool = true
    ) throws -> CampusAIChatCompletionsPayload {
        let userContent = CampusAIProviderUserContent(
            message: request.message,
            campusID: request.context.campusID,
            campusName: request.context.campusName,
            // Direct BYOK requests receive only the bounded retrieval hits,
            // never the complete local context snapshot.
            context: nil,
            contextSettings: usePersonalContext ? request.contextSettings : nil,
            capabilities: request.capabilities,
            localRetrieval: usePersonalContext ? request.localRetrieval : nil,
            recentMessages: request.recentMessages.suffix(10).map { message in
                CampusAIProviderUserContent.RecentMessage(
                    role: message.role == .assistant ? "assistant" : "user",
                    text: message.text
                )
            }
        )
        guard let userContentString = String(data: try providerJSONEncoder().encode(userContent), encoding: .utf8) else {
            throw CampusAIServiceError.invalidProviderResponse
        }

        return CampusAIChatCompletionsPayload(
            model: request.model,
            messages: [
                .init(
                    role: "system",
                    content: systemPrompt(
                        userPrompt: request.userSystemPrompt,
                        preparesArtifact: CampusAIArtifactIntentResolver.shouldGenerateArtifact(
                            message: request.message,
                            mode: request.outputMode
                        )
                    )
                ),
                .init(role: "user", content: userContentString)
            ],
            stream: true,
            thinking: .enabled,
            streamOptions: .includeUsage,
            temperature: 0.2,
            maxTokens: nil,
            user: nil
        )
    }

    static func actionPlannerPayload(
        for request: CampusAIRequest,
        answer: String
    ) throws -> CampusAIActionPlannerPayload {
        let userContent = CampusAIActionPlannerUserContent(
            message: request.message,
            answer: answer,
            contextSettings: request.contextSettings,
            capabilities: request.capabilities,
            localRetrieval: request.localRetrieval,
            shouldGenerateArtifact: CampusAIArtifactIntentResolver.shouldGenerateArtifact(
                message: request.message,
                mode: request.outputMode
            )
        )
        guard let userContentString = String(data: try providerJSONEncoder().encode(userContent), encoding: .utf8) else {
            throw CampusAIServiceError.invalidProviderResponse
        }

        return CampusAIActionPlannerPayload(
            model: request.model,
            messages: [
                .init(role: "system", content: actionPlannerSystemPrompt()),
                .init(role: "user", content: userContentString)
            ],
            stream: false,
            temperature: 0,
            maxTokens: CampusAIArtifactIntentResolver.shouldGenerateArtifact(
                message: request.message,
                mode: request.outputMode
            ) ? 4_000 : 700,
            user: nil
        )
    }

    static func systemPrompt(userPrompt: String, preparesArtifact: Bool = false) -> String {
        let customPrompt = userPrompt.nonEmptyTrimmed.map { String($0.prefix(3000)) }
        return [
            "你是 Leafy 的通用 AI 助手，当前是测试功能。",
            "回答要直接、具体、可执行；能给结论就先给结论，不要反复解释内部数据来源。",
            "可以回答通用问题；个人课表、考试、成绩、日程和其他本机资料默认不参与回答。只有输入明确包含必要的 context 或 local_retrieval 时，才把其中最相关的少量结果用于用户确实要求的个人事实或个性化安排。不要为了显得个性化而主动提及这些资料，也不要把不确定内容说成事实。",
            "学校公共政策、通知和整体安排应以已验证的官方资料为主要依据；个人记录只能作为“你的个人安排”的补充，不能替代学校整体信息。",
            "每轮输入都会提供 current_local_time 和 time_zone_identifier。把它们作为当前日期与时区的唯一依据；涉及今天、当前学期、最新政策或近期安排时，不得凭训练数据猜测旧年份。",
            "缺少关键信息时，用一句话说明缺什么，并给出用户下一步能做的选择。",
            "不要声称读取了未提供的数据，不要声称读取了用户上传文件正文、图片像素、OCR、PDF、Word、PPT、表格或本地文件路径。",
            "不要推断私信、身份资料、未提供的远端内容或后台登录后的内容。",
            "当用户要求添加日程时，只能说明已准备待确认日程；用户在表单中保存前，不得声称已经添加、设置或执行。",
            "医疗台账只能做整理、提醒、流程梳理和材料核对，不提供诊断、治疗、用药或医疗决策建议。",
            "回复必须是中文 Markdown，并保持适合手机阅读的块级结构。先给结论；不同主题必须换段或使用短标题；三项以上并列信息必须使用列表；表格必须使用完整的 GFM 表头与分隔行，无法稳定构造时改用列表；不要用 emoji、连续加粗或挤在同一段中的序号模拟结构。不要输出 JSON，不要输出动作草稿。",
            preparesArtifact
                ? "本次会另行生成完整卡片。主回答只用一到三句话说明已理解需求、将交付什么，不要重复完整计划、报告、清单或表格。"
                : nil,
            customPrompt.map { "用户自定义偏好：\n\($0)" }
        ].compactMap { $0 }.joined(separator: "\n")
    }

    static func actionPlannerSystemPrompt() -> String {
        [
            "你是 MyLeafy 的交付规划器，只能输出 JSON，不能输出代码块、解释或多余文本。",
            "根据用户问题、AI 已生成回答和本机上下文，一次返回最多 3 个待确认动作，以及可选的 Artifact 卡片。",
            "输出根对象必须是 {\"actions\":[],\"artifact\":null}。当 should_generate_artifact 为 true 时，artifact 必须是 {\"title\":\"...\",\"summary\":\"...\",\"markdown\":\"...\"}；否则 artifact 必须为 null。",
            "Artifact 必须是完整、可直接阅读的中文 Markdown 卡片。可使用标题、列表、表格、引用、Mermaid 或 KaTeX；表格必须包含完整的 GFM 表头与分隔行，无法稳定构造时改用列表；不要在 Artifact 中编造来源。",
            "Artifact 的 title、summary 和正文由你生成；来源、数据范围和本机条目引用由 App 在本地附加，不要输出 sources 字段。",
            "可以使用 local_retrieval 中的 routeHint 和 sourceID 判断动作目标；缺少明确目标 ID 时不要编造编辑或删除动作。",
            "只有用户原问题明确要求打开页面或添加日程时才生成动作；不得根据 AI 回答中的建议自行生成动作，否则返回 {\"actions\":[]}。",
            "考试时间安排是什么、期末整体安排等信息查询不得生成动作；只有用户明确要求打开或管理相应页面时才可生成 openAcademicRoute。",
            "支持 kind：openAcademicRoute、createSchedule。旧 kind 仅用于客户端兼容，不得再生成。",
            "openAcademicRoute.payload.route 必须来自 supported_actions 中的 allowed_values.route。",
            "用户明确想查看、添加或管理考试、考场、考试时间、考试安排时，生成 openAcademicRoute 到 examSchedule。",
            "用户想管理已有日程时生成 openAcademicRoute 到 customCountdowns；用户想新建、添加、设置日程或提醒时生成 createSchedule，即使标题或时间不完整也不要改成页面跳转。",
            "createSchedule.payload 可包含 title、startsAt、endsAt、location、note、minutesBefore；只填写用户明确提供或可靠解析出的字段。startsAt 和 endsAt 使用包含时区的 ISO 8601。",
            "相对日期必须依据输入中的 current_local_time 和 time_zone_identifier 解析。",
            "不要生成删除、修改成绩或课表原始数据、医疗决策、社区发帖评论、远程抓取、后台登录等动作。",
            "输出格式必须是 {\"actions\":[{\"kind\":\"...\",\"title\":\"...\",\"detail\":\"...\",\"payload\":{...}}],\"artifact\":null}，或将 artifact 替换为完整对象。"
        ].joined(separator: "\n")
    }

    private static func directCompletionPlan(
        request: CampusAIRequest,
        answer: String,
        settings: CampusAIUserSettings,
        apiKey: String
    ) async throws -> CampusAICompletionPlan {
        let urlRequest = try makeActionPlannerRequest(
            for: request,
            answer: answer,
            baseURLString: settings.selectedProvider.baseURLString,
            apiKey: apiKey
        )
        let (data, response) = try await URLSession.shared.data(for: urlRequest)
        guard let httpResponse = response as? HTTPURLResponse else {
            throw CampusAIServiceError.invalidProviderResponse
        }
        guard (200..<300).contains(httpResponse.statusCode) else {
            throw CampusAIServiceError.providerRejected("卡片整理服务返回了 \(httpResponse.statusCode) 错误。")
        }
        let providerResponse = try providerJSONDecoder().decode(CampusAIActionPlannerProviderResponse.self, from: data)
        guard let content = providerResponse.choices?
            .compactMap({ $0.message?.content?.nonEmptyTrimmed })
            .first
        else {
            throw CampusAIServiceError.invalidProviderResponse
        }
        return try CampusAICompletionPlanParser.parse(content)
    }

    private static func actionDetail(for route: CampusAIAcademicRouteID) -> String {
        switch route {
        case .examSchedule:
            return "前往考试安排继续查看或管理考试。"
        case .scheduleReports:
            return "前往日程推送继续设置报告。"
        case .customCountdowns:
            return "前往自定日程继续创建或管理日程。"
        default:
            return "前往\(route.title)继续处理。"
        }
    }

    private static func fallbackScheduleStartDate(in message: String, now: Date = Date()) -> Date? {
        var normalized = message
        let chineseHours = [
            "十二点": "12点", "十一点": "11点", "十点": "10点",
            "九点": "9点", "八点": "8点", "七点": "7点", "六点": "6点",
            "五点": "5点", "四点": "4点", "三点": "3点", "两点": "2点", "一点": "1点"
        ]
        for (source, target) in chineseHours {
            normalized = normalized.replacingOccurrences(of: source, with: target)
        }

        let pattern = #"(早上|上午|中午|下午|晚上)?\s*(\d{1,2})(?:点|:|：)(\d{1,2})?"#
        guard let regex = try? NSRegularExpression(pattern: pattern),
              let match = regex.firstMatch(in: normalized, range: NSRange(normalized.startIndex..., in: normalized)),
              let hourRange = Range(match.range(at: 2), in: normalized),
              var hour = Int(normalized[hourRange]) else { return nil }
        let minute: Int = {
            guard match.range(at: 3).location != NSNotFound,
                  let range = Range(match.range(at: 3), in: normalized) else { return 0 }
            return Int(normalized[range]) ?? 0
        }()
        let period: String = {
            guard match.range(at: 1).location != NSNotFound,
                  let range = Range(match.range(at: 1), in: normalized) else { return "" }
            return String(normalized[range])
        }()
        if ["下午", "晚上"].contains(period), hour < 12 { hour += 12 }
        if period == "中午", hour < 11 { hour += 12 }
        guard (0...23).contains(hour), (0...59).contains(minute) else { return nil }

        let dayOffset = normalized.contains("后天") ? 2 : (normalized.contains("明天") ? 1 : 0)
        let calendar = Calendar.current
        let day = calendar.date(byAdding: .day, value: dayOffset, to: calendar.startOfDay(for: now)) ?? now
        return calendar.date(bySettingHour: hour, minute: minute, second: 0, of: day)
    }

    private static let scheduleDateTimeFormatter: DateFormatter = {
        let formatter = DateFormatter()
        formatter.locale = Locale(identifier: "en_US_POSIX")
        formatter.timeZone = .current
        formatter.dateFormat = "yyyy-MM-dd'T'HH:mm:ssXXX"
        return formatter
    }()

    static func actionPlannerActions(fromProviderResponseData data: Data) throws -> [CampusAIActionDraft] {
        let response = try providerJSONDecoder().decode(CampusAIActionPlannerProviderResponse.self, from: data)
        guard let content = response.choices?.compactMap({ $0.message?.content }).first(where: { !$0.isEmpty }) else {
            return []
        }
        return actionPlannerActions(fromContent: content)
    }

    static func actionPlannerActions(fromContent content: String) -> [CampusAIActionDraft] {
        let candidates = actionPlannerJSONCandidates(from: content)
        let decoder = providerJSONDecoder()
        for candidate in candidates {
            let data = Data(candidate.utf8)
            if let result = try? decoder.decode(CampusAIActionPlannerResult.self, from: data) {
                return Array(CampusAIActionValidation.validated(result.actions).prefix(3))
            }
            if let actions = try? decoder.decode([CampusAIActionDraft].self, from: data) {
                return Array(CampusAIActionValidation.validated(actions).prefix(3))
            }
        }
        return []
    }

    private static func actionPlannerJSONCandidates(from content: String) -> [String] {
        let trimmed = content.trimmingCharacters(in: .whitespacesAndNewlines)
        let unfenced: String
        if trimmed.hasPrefix("```") {
            let lines = trimmed
                .replacingOccurrences(of: "\r\n", with: "\n")
                .split(separator: "\n", omittingEmptySubsequences: false)
            unfenced = lines
                .dropFirst()
                .dropLast(lines.last?.trimmingCharacters(in: .whitespacesAndNewlines) == "```" ? 1 : 0)
                .joined(separator: "\n")
                .trimmingCharacters(in: .whitespacesAndNewlines)
        } else {
            unfenced = trimmed
        }

        var candidates = [unfenced]
        if let start = unfenced.firstIndex(of: "{"), let end = unfenced.lastIndex(of: "}"), start <= end {
            candidates.append(String(unfenced[start...end]))
        }
        if let start = unfenced.firstIndex(of: "["), let end = unfenced.lastIndex(of: "]"), start <= end {
            candidates.append(String(unfenced[start...end]))
        }
        var seen = Set<String>()
        return candidates.filter { candidate in
            guard !candidate.isEmpty, !seen.contains(candidate) else { return false }
            seen.insert(candidate)
            return true
        }
    }

    static func redactProviderError(_ value: String) -> String {
        value
            .replacingOccurrences(
                of: #"(?i)(bearer\s+)?[A-Za-z0-9]{24,}\.[A-Za-z0-9._-]+"#,
                with: "[redacted]",
                options: .regularExpression
            )
            .replacingOccurrences(
                of: #"sk-[A-Za-z0-9_-]+"#,
                with: "sk-redacted",
                options: .regularExpression
            )
    }

    private static func providerJSONEncoder() -> JSONEncoder {
        let encoder = JSONEncoder()
        encoder.outputFormatting = [.sortedKeys]
        return encoder
    }

    private static func providerJSONDecoder() -> JSONDecoder {
        JSONDecoder()
    }

    private static func providerErrorBody(from bytes: URLSession.AsyncBytes) async throws -> String {
        var body = ""
        for try await line in bytes.lines {
            if !body.isEmpty {
                body += "\n"
            }
            body += line
            if body.count > 1000 {
                break
            }
        }
        return redactProviderError(body)
    }

    private static func providerBody(from bytes: URLSession.AsyncBytes, limit: Int = 2_000_000) async throws -> String {
        var data = Data()
        for try await byte in bytes {
            data.append(byte)
            if data.count > limit {
                break
            }
        }
        guard let body = String(data: data, encoding: .utf8) else {
            throw CampusAIServiceError.invalidProviderResponse
        }
        return body
    }

    static func providerEvents(from body: String) throws -> [CampusAIStreamEvent] {
        let trimmed = body.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else {
            throw CampusAIServiceError.invalidProviderResponse
        }

        var parser = CampusAISSEParser()
        let parseData: Data
        if trimmed.hasPrefix("data:") || trimmed.contains("\ndata:") || trimmed.contains("\r\ndata:") {
            parseData = Data(body.utf8)
        } else if trimmed.hasPrefix("{") {
            let dataLines = trimmed
                .replacingOccurrences(of: "\r\n", with: "\n")
                .split(separator: "\n", omittingEmptySubsequences: false)
                .map { "data: \($0)" }
                .joined(separator: "\n")
            parseData = Data("\(dataLines)\n\ndata: [DONE]\n\n".utf8)
        } else {
            throw CampusAIServiceError.invalidProviderResponse
        }

        return try parser.append(parseData) + parser.finish()
    }

    private static func providerHTTPErrorMessage(statusCode: Int, body: String) -> String {
        let trimmedBody = body.trimmingCharacters(in: .whitespacesAndNewlines)
        if trimmedBody.isEmpty {
            return "AI 助手返回了 \(statusCode) 错误。"
        }
        return "AI 助手返回了 \(statusCode) 错误：\(trimmedBody)"
    }

    private static func managedHTTPErrorMessage(statusCode: Int, body: String) -> String {
        let trimmedBody = body.trimmingCharacters(in: .whitespacesAndNewlines)
        if let data = trimmedBody.data(using: .utf8),
           let payload = try? JSONDecoder().decode(CampusAIManagedErrorPayload.self, from: data),
           let error = payload.error?.nonEmptyTrimmed {
            return statusCode == 402 ? error : "Leafy AI 服务返回了 \(statusCode) 错误：\(error)"
        }
        if trimmedBody.isEmpty {
            return "Leafy AI 服务返回了 \(statusCode) 错误。"
        }
        return "Leafy AI 服务返回了 \(statusCode) 错误：\(trimmedBody)"
    }
}

nonisolated private struct CampusAIProviderUserContent: Encodable {
    let message: String
    let campusID: String
    let campusName: String
    let context: CampusAIContextPayload?
    let contextSettings: CampusAIContextSettings?
    let capabilities: CampusAICapabilitySet
    let localRetrieval: CampusAILocalRetrievalPayload?
    let recentMessages: [RecentMessage]
    let currentLocalTime: String
    let timeZoneIdentifier: String

    enum CodingKeys: String, CodingKey {
        case message
        case campusID = "campus_id"
        case campusName = "campus_name"
        case context
        case contextSettings = "context_settings"
        case capabilities
        case localRetrieval = "local_retrieval"
        case recentMessages = "recent_messages"
        case currentLocalTime = "current_local_time"
        case timeZoneIdentifier = "time_zone_identifier"
    }

    struct RecentMessage: Encodable, Hashable {
        let role: String
        let text: String
    }

    init(
        message: String,
        campusID: String,
        campusName: String,
        context: CampusAIContextPayload?,
        contextSettings: CampusAIContextSettings?,
        capabilities: CampusAICapabilitySet,
        localRetrieval: CampusAILocalRetrievalPayload?,
        recentMessages: [RecentMessage],
        now: Date = Date(),
        timeZone: TimeZone = .current
    ) {
        self.message = message
        self.campusID = campusID
        self.campusName = campusName
        self.context = context
        self.contextSettings = contextSettings
        self.capabilities = capabilities
        self.localRetrieval = localRetrieval
        self.recentMessages = recentMessages
        let formatter = DateFormatter()
        formatter.locale = Locale(identifier: "en_US_POSIX")
        formatter.timeZone = timeZone
        formatter.dateFormat = "yyyy-MM-dd'T'HH:mm:ssXXX"
        currentLocalTime = formatter.string(from: now)
        timeZoneIdentifier = timeZone.identifier
    }
}

nonisolated private struct CampusAIActionPlannerUserContent: Encodable {
    let message: String
    let answer: String
    let contextSettings: CampusAIContextSettings
    let capabilities: CampusAICapabilitySet
    let localRetrieval: CampusAILocalRetrievalPayload
    let shouldGenerateArtifact: Bool
    let currentLocalTime: String
    let timeZoneIdentifier: String
    let supportedActions: [CampusAIToolSupportedAction]
    let safetyBoundary: [String]

    enum CodingKeys: String, CodingKey {
        case message
        case answer
        case contextSettings = "context_settings"
        case capabilities
        case localRetrieval = "local_retrieval"
        case shouldGenerateArtifact = "should_generate_artifact"
        case currentLocalTime = "current_local_time"
        case timeZoneIdentifier = "time_zone_identifier"
        case supportedActions = "supported_actions"
        case safetyBoundary = "safety_boundary"
    }

    init(
        message: String,
        answer: String,
        contextSettings: CampusAIContextSettings,
        capabilities: CampusAICapabilitySet,
        localRetrieval: CampusAILocalRetrievalPayload,
        shouldGenerateArtifact: Bool
    ) {
        self.message = message
        self.answer = answer
        self.contextSettings = contextSettings
        self.capabilities = capabilities
        self.localRetrieval = localRetrieval
        self.shouldGenerateArtifact = shouldGenerateArtifact
        let formatter = DateFormatter()
        formatter.locale = Locale(identifier: "en_US_POSIX")
        formatter.timeZone = .current
        formatter.dateFormat = "yyyy-MM-dd'T'HH:mm:ssXXX"
        currentLocalTime = formatter.string(from: Date())
        timeZoneIdentifier = TimeZone.current.identifier
        supportedActions = CampusAIToolRegistry.supportedActions()
        safetyBoundary = [
            "所有动作都只生成待确认草稿，不会自动执行。",
            "不要生成修改成绩或课表原始数据、医疗决策、社区发帖评论、远程抓取、后台登录等动作。",
            "编辑或删除必须有 local_retrieval.sourceID 等明确目标 ID；缺少目标 ID 时改生成 openAcademicRoute 或返回空 actions。",
            "删除类动作需要二次确认；当前 schema 未提供删除 kind 时不要输出删除动作。",
            "创建日程缺少的字段保持为空，由用户在确认表单中补充。"
        ]
    }

}

nonisolated struct CampusAIManagedFunctionRequest: Encodable {
    let requestID: String
    let appTransactionID: String?
    let appTransactionJWS: String?
    let serviceMode: String
    let message: String
    let context: CampusAIContextPayload
    let recentMessages: [CampusAIChatMessage]
    let userSystemPrompt: String
    let contextSettings: CampusAIContextSettings
    let agentMode: CampusAIAgentMode
    let webSearchEnabled: Bool
    let capabilities: CampusAICapabilitySet
    let localRetrieval: CampusAILocalRetrievalPayload
    let outputMode: CampusAIOutputMode
    let currentLocalTime: String
    let timeZoneIdentifier: String

    enum CodingKeys: String, CodingKey {
        case requestID = "request_id"
        case appTransactionID = "app_transaction_id"
        case appTransactionJWS = "app_transaction_jws"
        case serviceMode = "service_mode"
        case message
        case context
        case recentMessages = "recent_messages"
        case userSystemPrompt = "user_system_prompt"
        case contextSettings = "context_settings"
        case agentMode = "agent_mode"
        case webSearchEnabled = "web_search_enabled"
        case capabilities
        case localRetrieval = "local_retrieval"
        case outputMode = "output_mode"
        case currentLocalTime = "current_local_time"
        case timeZoneIdentifier = "time_zone_identifier"
    }

    init(
        request: CampusAIRequest,
        appTransactionID: String?,
        appTransactionJWS: String?,
        serviceMode: CampusAIServiceMode
    ) {
        self.requestID = request.requestID.uuidString
        self.appTransactionID = appTransactionID
        self.appTransactionJWS = appTransactionJWS
        self.serviceMode = serviceMode.rawValue
        self.message = request.message
        self.context = request.context
        self.recentMessages = request.recentMessages
        self.userSystemPrompt = request.userSystemPrompt
        self.contextSettings = request.contextSettings
        self.agentMode = request.agentMode
        self.webSearchEnabled = request.webSearchEnabled
        self.capabilities = request.capabilities
        self.localRetrieval = request.localRetrieval
        self.outputMode = request.outputMode
        let formatter = DateFormatter()
        formatter.locale = Locale(identifier: "en_US_POSIX")
        formatter.timeZone = .current
        formatter.dateFormat = "yyyy-MM-dd'T'HH:mm:ssXXX"
        self.currentLocalTime = formatter.string(from: Date())
        self.timeZoneIdentifier = TimeZone.current.identifier
    }
}

nonisolated private struct CampusAIManagedErrorPayload: Decodable {
    let error: String?
}
import Foundation
import Supabase
