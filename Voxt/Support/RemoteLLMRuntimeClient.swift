import Foundation
import CFNetwork

struct RemoteLLMRuntimeClient {
    struct StreamingFailure: Error {
        let underlying: Error
        let partialText: String
        let emittedChunkCount: Int
    }

    private struct AliyunResponsesStreamingResult {
        let text: String
        let responseID: String?
    }

    private enum CompletionIntent: Equatable {
        case enhancement
        case translation
        case rewrite
    }

    private struct GenerationTuning {
        let maxTokens: Int
        let temperature: Double
        let topP: Double
    }

    func enhance(
        text: String,
        systemPrompt: String,
        provider: RemoteLLMProvider,
        configuration: RemoteProviderConfiguration
    ) async throws -> String {
        let prompt = """
        Clean up this transcription while preserving meaning and style.
        Input:
        \(text)
        """
        let output = try await complete(
            systemPrompt: systemPrompt,
            debugInput: text,
            userPrompt: prompt,
            inputTextLength: text.count,
            intent: .enhancement,
            provider: provider,
            configuration: configuration
        )
        let trimmed = output.trimmingCharacters(in: .whitespacesAndNewlines)
        return trimmed.isEmpty ? text : trimmed
    }

    func enhance(
        userPrompt: String,
        provider: RemoteLLMProvider,
        configuration: RemoteProviderConfiguration
    ) async throws -> String {
        let input = userPrompt.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !input.isEmpty else { return "" }
        let output = try await complete(
            systemPrompt: "",
            debugInput: input,
            userPrompt: input,
            inputTextLength: input.count,
            intent: .enhancement,
            provider: provider,
            configuration: configuration
        )
        return output.trimmingCharacters(in: .whitespacesAndNewlines)
    }

    func translate(
        text: String,
        systemPrompt: String,
        provider: RemoteLLMProvider,
        configuration: RemoteProviderConfiguration
    ) async throws -> String {
        let prompt = """
        Translate the following text according to the instructions.
        Input:
        \(text)
        """
        let output = try await complete(
            systemPrompt: systemPrompt,
            debugInput: text,
            userPrompt: prompt,
            inputTextLength: text.count,
            intent: .translation,
            provider: provider,
            configuration: configuration
        )
        let trimmed = output.trimmingCharacters(in: .whitespacesAndNewlines)
        return trimmed.isEmpty ? text : trimmed
    }

    func rewrite(
        sourceText: String,
        dictatedPrompt: String,
        systemPrompt: String,
        provider: RemoteLLMProvider,
        configuration: RemoteProviderConfiguration,
        conversationHistory: [RewriteConversationPromptTurn] = [],
        previousResponseID: String? = nil,
        onPartialText: (@Sendable (String) -> Void)? = nil,
        onResponseID: ((String) -> Void)? = nil
    ) async throws -> String {
        if shouldUseAliyunResponsesAPI(
            provider: provider,
            configuration: configuration,
            sourceText: sourceText,
            wantsStreaming: onPartialText != nil
        ) {
            let result = try await completeAliyunResponsesRewrite(
                dictatedPrompt: dictatedPrompt,
                systemPrompt: systemPrompt,
                provider: provider,
                configuration: configuration,
                conversationHistory: conversationHistory,
                previousResponseID: previousResponseID,
                onPartialText: onPartialText ?? { _ in },
                onResponseID: onResponseID
            )
            let trimmed = result.text.trimmingCharacters(in: .whitespacesAndNewlines)
            return trimmed.isEmpty ? sourceText : trimmed
        }

        let prompt = """
        Produce the final text to insert according to the instructions.
        Spoken instruction:
        \(dictatedPrompt)

        Selected source text:
        \(sourceText)
        """
        let shouldUseConversationMessages =
            sourceText.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty &&
            !conversationHistory.isEmpty
        let userPrompt = shouldUseConversationMessages ? dictatedPrompt : prompt
        let output = try await complete(
            systemPrompt: systemPrompt,
            debugInput: """
            Spoken instruction:
            \(dictatedPrompt)

            Selected source text:
            \(sourceText)
            """,
            userPrompt: userPrompt,
            inputTextLength: sourceText.count + dictatedPrompt.count,
            intent: .rewrite,
            provider: provider,
            configuration: configuration,
            messagesOverride: shouldUseConversationMessages
                ? openAICompatibleConversationMessages(
                    systemPrompt: systemPrompt,
                    currentUserPrompt: dictatedPrompt,
                    conversationHistory: conversationHistory
                )
                : nil,
            onPartialText: onPartialText
        )
        let trimmed = output.trimmingCharacters(in: .whitespacesAndNewlines)
        return trimmed.isEmpty ? sourceText : trimmed
    }

    func shouldUseAliyunResponsesAPI(
        provider: RemoteLLMProvider,
        configuration: RemoteProviderConfiguration,
        sourceText: String,
        wantsStreaming: Bool
    ) -> Bool {
        guard wantsStreaming,
              sourceText.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
        else {
            return false
        }

        let explicitEndpoint = configuration.endpoint.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !explicitEndpoint.isEmpty,
              let url = URL(string: explicitEndpoint),
              let host = url.host?.lowercased()
        else {
            return false
        }

        let path = url.path.lowercased()
        let isDashScopeHost =
            host.contains("dashscope.aliyuncs.com") ||
            host.contains("dashscope-intl.aliyuncs.com") ||
            host.contains("dashscope-us.aliyuncs.com")
        let isResponsesEndpoint =
            path.hasSuffix("/v1/responses") ||
            path.hasSuffix("/responses")

        return isDashScopeHost && isResponsesEndpoint
    }

    private func completeAliyunResponsesRewrite(
        dictatedPrompt: String,
        systemPrompt: String,
        provider: RemoteLLMProvider,
        configuration: RemoteProviderConfiguration,
        conversationHistory: [RewriteConversationPromptTurn],
        previousResponseID: String?,
        onPartialText: @escaping (String) -> Void,
        onResponseID: ((String) -> Void)?
    ) async throws -> AliyunResponsesStreamingResult {
        let model = configuration.model.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
            ? provider.suggestedModel
            : configuration.model.trimmingCharacters(in: .whitespacesAndNewlines)
        let endpointValue = responsesEndpointValue(provider: provider, endpoint: configuration.endpoint, model: model)
        let request = try makeAliyunResponsesRequest(
            endpointValue: endpointValue,
            model: model,
            systemPrompt: systemPrompt,
            dictatedPrompt: dictatedPrompt,
            configuration: configuration,
            conversationHistory: conversationHistory,
            previousResponseID: previousResponseID,
            streamingEnabled: true
        )
        let requestStartedAt = Date()
        logRequest(
            request: request,
            provider: provider,
            endpointValue: endpointValue,
            model: model,
            inputTextLength: dictatedPrompt.count,
            systemPrompt: systemPrompt,
            debugInput: dictatedPrompt,
            userPrompt: dictatedPrompt,
            tuning: generationTuning(
                for: provider,
                inputTextLength: dictatedPrompt.count,
                systemPromptLength: systemPrompt.count,
                userPromptLength: dictatedPrompt.count,
                intent: .rewrite
            )
        )

        var aggregated = ""
        var responseID: String?
        var emittedChunkCount = 0

        do {
            let (bytes, response) = try await VoxtNetworkSession.active.bytes(for: request)
            guard let http = response as? HTTPURLResponse else {
                throw NSError(domain: "Voxt.RemoteLLM", code: -305, userInfo: [NSLocalizedDescriptionKey: "Invalid remote LLM response."])
            }
            guard (200...299).contains(http.statusCode) else {
                throw NSError(
                    domain: "Voxt.RemoteLLM",
                    code: http.statusCode,
                    userInfo: [NSLocalizedDescriptionKey: "Remote LLM request failed (HTTP \(http.statusCode)) while opening stream."]
                )
            }

            var bufferedEventLines: [String] = []
            var sawEventStreamMarkers = false

            func publish(_ chunkPayload: String) throws {
                let trimmed = chunkPayload.trimmingCharacters(in: .whitespacesAndNewlines)
                guard !trimmed.isEmpty, trimmed != "[DONE]" else { return }
                guard let data = trimmed.data(using: .utf8),
                      let object = try? JSONSerialization.jsonObject(with: data) as? [String: Any] else {
                    return
                }

                if let extractedResponseID = aliyunResponsesResponseID(from: object) {
                    responseID = extractedResponseID
                    onResponseID?(extractedResponseID)
                }

                if let errorMessage = extractStreamingErrorMessage(from: object) ?? aliyunResponsesErrorMessage(from: object) {
                    throw NSError(
                        domain: "Voxt.RemoteLLM",
                        code: -307,
                        userInfo: [NSLocalizedDescriptionKey: errorMessage]
                    )
                }

                if let delta = aliyunResponsesStreamingDelta(from: object), !delta.isEmpty {
                    aggregated.append(delta)
                    emittedChunkCount += 1
                    onPartialText(aggregated)
                }
            }

            for try await line in bytes.lines {
                let trimmedLine = line.trimmingCharacters(in: .newlines)
                if trimmedLine.isEmpty {
                    if !bufferedEventLines.isEmpty {
                        try publish(bufferedEventLines.joined(separator: "\n"))
                        bufferedEventLines.removeAll(keepingCapacity: true)
                    }
                    continue
                }

                if trimmedLine.hasPrefix(":") {
                    continue
                }

                if trimmedLine.hasPrefix("event:") || trimmedLine.hasPrefix("id:") || trimmedLine.hasPrefix("retry:") {
                    sawEventStreamMarkers = true
                    continue
                }

                if trimmedLine.hasPrefix("data:") {
                    sawEventStreamMarkers = true
                    var payload = String(trimmedLine.dropFirst(5))
                    if payload.hasPrefix(" ") {
                        payload.removeFirst()
                    }
                    bufferedEventLines.append(payload)
                    if shouldFlushBufferedEventLines(bufferedEventLines) {
                        try publish(bufferedEventLines.joined(separator: "\n"))
                        bufferedEventLines.removeAll(keepingCapacity: true)
                    }
                    continue
                }

                if sawEventStreamMarkers {
                    bufferedEventLines.append(trimmedLine)
                    if shouldFlushBufferedEventLines(bufferedEventLines) {
                        try publish(bufferedEventLines.joined(separator: "\n"))
                        bufferedEventLines.removeAll(keepingCapacity: true)
                    }
                }
            }

            if !bufferedEventLines.isEmpty {
                try publish(bufferedEventLines.joined(separator: "\n"))
            }

            let totalElapsedMs = Int(Date().timeIntervalSince(requestStartedAt) * 1000)
            VoxtLog.llm(
                "Aliyun Responses streaming response received. endpoint=\(endpointValue), status=\(http.statusCode), chunks=\(emittedChunkCount), totalMs=\(totalElapsedMs), responseID=\(responseID ?? "nil")"
            )
            VoxtLog.llm(
                """
                Aliyun Responses streaming content. endpoint=\(endpointValue), status=\(http.statusCode)
                [output]
                \(VoxtLog.llmPreview(aggregated))
                """
            )
            return AliyunResponsesStreamingResult(text: aggregated, responseID: responseID)
        } catch {
            throw StreamingFailure(
                underlying: error,
                partialText: aggregated,
                emittedChunkCount: emittedChunkCount
            )
        }
    }

    private func complete(
        systemPrompt: String,
        debugInput: String,
        userPrompt: String,
        inputTextLength: Int,
        intent: CompletionIntent,
        provider: RemoteLLMProvider,
        configuration: RemoteProviderConfiguration,
        messagesOverride: [[String: String]]? = nil,
        onPartialText: (@Sendable (String) -> Void)? = nil
    ) async throws -> String {
        let model = configuration.model.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
            ? provider.suggestedModel
            : configuration.model.trimmingCharacters(in: .whitespacesAndNewlines)
        let endpoint = resolvedLLMEndpoint(provider: provider, endpoint: configuration.endpoint, model: model)
        let endpoints = resolvedEndpointCandidates(provider: provider, primaryEndpoint: endpoint)
        var lastError: Error?
        let shouldAttemptStreaming = onPartialText != nil && supportsStreaming(provider: provider, intent: intent)

        for (index, endpointValue) in endpoints.enumerated() {
            let attemptStartedAt = Date()
            let tuning = generationTuning(
                for: provider,
                inputTextLength: inputTextLength,
                systemPromptLength: systemPrompt.count,
                userPromptLength: userPrompt.count,
                intent: intent
            )
            do {
                if shouldAttemptStreaming, let onPartialText {
                    do {
                        let streamingRequest = try makeCompletionRequest(
                            provider: provider,
                            configuration: configuration,
                            endpointValue: endpointValue,
                            model: model,
                            systemPrompt: systemPrompt,
                            userPrompt: userPrompt,
                            messagesOverride: messagesOverride,
                            tuning: tuning,
                            streamingEnabled: true
                        )
                        let requestStartedAt = Date()
                        logRequest(
                            request: streamingRequest,
                            provider: provider,
                            endpointValue: endpointValue,
                            model: model,
                            inputTextLength: inputTextLength,
                            systemPrompt: systemPrompt,
                            debugInput: debugInput,
                            userPrompt: userPrompt,
                            tuning: tuning
                        )
                        let streamed = try await completeStreaming(
                            request: streamingRequest,
                            provider: provider,
                            endpointValue: endpointValue,
                            requestStartedAt: requestStartedAt,
                            attempt: index + 1,
                            endpointCount: endpoints.count,
                            onPartialText: onPartialText
                        )
                        let trimmed = streamed.trimmingCharacters(in: .whitespacesAndNewlines)
                        guard !trimmed.isEmpty else {
                            throw NSError(domain: "Voxt.RemoteLLM", code: -306, userInfo: [NSLocalizedDescriptionKey: "Remote LLM returned no text content."])
                        }
                        return trimmed
                    } catch let streamingFailure as StreamingFailure where streamingFailure.emittedChunkCount == 0 {
                        VoxtLog.warning(
                            "Remote LLM streaming unavailable, retrying non-streaming. provider=\(provider.rawValue), endpoint=\(endpointValue), attempt=\(index + 1)/\(endpoints.count), detail=\(streamingFailure.underlying.localizedDescription)"
                        )
                    } catch {
                        throw error
                    }
                }

                let request = try makeCompletionRequest(
                    provider: provider,
                    configuration: configuration,
                    endpointValue: endpointValue,
                    model: model,
                    systemPrompt: systemPrompt,
                    userPrompt: userPrompt,
                    messagesOverride: messagesOverride,
                    tuning: tuning,
                    streamingEnabled: false
                )
                let requestStartedAt = Date()
                logRequest(
                    request: request,
                    provider: provider,
                    endpointValue: endpointValue,
                    model: model,
                    inputTextLength: inputTextLength,
                    systemPrompt: systemPrompt,
                    debugInput: debugInput,
                    userPrompt: userPrompt,
                    tuning: tuning
                )
                let (data, response) = try await VoxtNetworkSession.active.data(for: request)
                let responseElapsedMs = Int(Date().timeIntervalSince(requestStartedAt) * 1000)
                guard let http = response as? HTTPURLResponse else {
                    throw NSError(domain: "Voxt.RemoteLLM", code: -305, userInfo: [NSLocalizedDescriptionKey: "Invalid remote LLM response."])
                }
                guard (200...299).contains(http.statusCode) else {
                    let payload = String(data: data.prefix(260), encoding: .utf8) ?? ""
                    throw NSError(
                        domain: "Voxt.RemoteLLM",
                        code: http.statusCode,
                        userInfo: [NSLocalizedDescriptionKey: "Remote LLM request failed (HTTP \(http.statusCode)): \(payload)"]
                    )
                }

                let decodeStartedAt = Date()
                let object = try JSONSerialization.jsonObject(with: data)
                let decodeElapsedMs = Int(Date().timeIntervalSince(decodeStartedAt) * 1000)
                let totalElapsedMs = Int(Date().timeIntervalSince(requestStartedAt) * 1000)
                let attempt = index + 1
                if let content = extractPrimaryText(from: object), !content.isEmpty {
                    VoxtLog.llm(
                        "Remote LLM response received. provider=\(provider.rawValue), endpoint=\(endpointValue), status=\(http.statusCode), attempt=\(attempt)/\(endpoints.count), bytes=\(data.count), networkMs=\(responseElapsedMs), decodeMs=\(decodeElapsedMs), totalMs=\(totalElapsedMs)"
                    )
                    VoxtLog.llm(
                        """
                        Remote LLM response content. provider=\(provider.rawValue), endpoint=\(endpointValue), status=\(http.statusCode)
                        [output]
                        \(VoxtLog.llmPreview(content))
                        """
                    )
                    return content
                }

                VoxtLog.warning(
                    "Remote LLM response has no usable text. provider=\(provider.rawValue), endpoint=\(endpointValue), status=\(http.statusCode), attempt=\(attempt)/\(endpoints.count), bytes=\(data.count), networkMs=\(responseElapsedMs), decodeMs=\(decodeElapsedMs), totalMs=\(totalElapsedMs)"
                )
                throw NSError(domain: "Voxt.RemoteLLM", code: -306, userInfo: [NSLocalizedDescriptionKey: "Remote LLM returned no text content."])
            } catch {
                lastError = error
                let elapsedMs = Int(Date().timeIntervalSince(attemptStartedAt) * 1000)
                let nsError = error as NSError
                let isTimeout = nsError.domain == NSURLErrorDomain && nsError.code == NSURLErrorTimedOut
                let detail = networkErrorDetail(error: nsError)
                let attempt = index + 1
                let requestTimeout = requestTimeoutInterval(for: provider)
                let resolvedURL = URL(string: streamingEndpointValue(
                    provider: provider,
                    endpoint: endpointValue,
                    model: model,
                    streamingEnabled: shouldAttemptStreaming
                )) ?? URL(string: endpointValue)
                let proxyRoute = resolvedURL.map {
                    resolvedProxyRoute(for: $0, settings: VoxtNetworkSession.currentProxySettings)
                } ?? "unavailable"
                if isTimeout {
                    VoxtLog.warning("Remote LLM request timeout. provider=\(provider.rawValue), endpoint=\(endpointValue), attempt=\(attempt)/\(endpoints.count), elapsedMs=\(elapsedMs), timeoutSec=\(Int(requestTimeout)), proxy=\(proxyRoute), detail=\(detail)")
                } else {
                    VoxtLog.warning("Remote LLM request failed. provider=\(provider.rawValue), endpoint=\(endpointValue), attempt=\(attempt)/\(endpoints.count), elapsedMs=\(elapsedMs), proxy=\(proxyRoute), detail=\(detail)")
                }

                let hasNext = index < endpoints.count - 1
                if hasNext && shouldRetry(error: error, provider: provider) {
                    VoxtLog.warning("Remote LLM request failed on endpoint \(endpointValue); retrying next endpoint. attempt=\(attempt)/\(endpoints.count), reason=\(error.localizedDescription)")
                    continue
                }
                throw error
            }
        }

        throw lastError ?? NSError(domain: "Voxt.RemoteLLM", code: -306, userInfo: [NSLocalizedDescriptionKey: "Remote LLM returned no text content."])
    }

    private func makeCompletionRequest(
        provider: RemoteLLMProvider,
        configuration: RemoteProviderConfiguration,
        endpointValue: String,
        model: String,
        systemPrompt: String,
        userPrompt: String,
        messagesOverride: [[String: String]]? = nil,
        tuning: GenerationTuning,
        streamingEnabled: Bool
    ) throws -> URLRequest {
        let resolvedEndpoint = streamingEndpointValue(
            provider: provider,
            endpoint: endpointValue,
            model: model,
            streamingEnabled: streamingEnabled
        )
        guard let url = URL(string: resolvedEndpoint) else {
            throw NSError(
                domain: "Voxt.RemoteLLM",
                code: -300,
                userInfo: [NSLocalizedDescriptionKey: "Invalid remote LLM endpoint URL: \(resolvedEndpoint)"]
            )
        }

        var request = URLRequest(url: url)
        request.httpMethod = "POST"
        request.timeoutInterval = requestTimeoutInterval(for: provider)
        request.setValue("application/json", forHTTPHeaderField: "Content-Type")
        request.setValue(
            streamingEnabled ? "text/event-stream, application/x-ndjson, application/json" : "application/json",
            forHTTPHeaderField: "Accept"
        )

        switch provider {
        case .anthropic:
            guard !configuration.apiKey.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty else {
                throw NSError(domain: "Voxt.RemoteLLM", code: -301, userInfo: [NSLocalizedDescriptionKey: "Anthropic API key is empty."])
            }
            request.setValue(configuration.apiKey, forHTTPHeaderField: "x-api-key")
            request.setValue("2023-06-01", forHTTPHeaderField: "anthropic-version")
            var payload: [String: Any] = [
                "model": model,
                "max_tokens": 2048,
                "stream": streamingEnabled,
                "messages": [
                    ["role": "user", "content": userPrompt]
                ]
            ]
            let trimmedSystem = systemPrompt.trimmingCharacters(in: .whitespacesAndNewlines)
            if !trimmedSystem.isEmpty {
                payload["system"] = systemPrompt
            }
            if configuration.searchEnabled && provider.supportsHostedSearch {
                payload["tools"] = [
                    [
                        "type": "web_search_20250305",
                        "name": "web_search",
                        "max_uses": 5
                    ]
                ]
            }
            request.httpBody = try JSONSerialization.data(withJSONObject: payload)
        case .google:
            let apiKey = configuration.apiKey.trimmingCharacters(in: .whitespacesAndNewlines)
            guard !apiKey.isEmpty else {
                throw NSError(domain: "Voxt.RemoteLLM", code: -302, userInfo: [NSLocalizedDescriptionKey: "Google API key is empty."])
            }
            guard var components = URLComponents(url: url, resolvingAgainstBaseURL: false) else {
                throw NSError(domain: "Voxt.RemoteLLM", code: -303, userInfo: [NSLocalizedDescriptionKey: "Invalid Google endpoint URL."])
            }
            var items = components.queryItems ?? []
            if !items.contains(where: { $0.name == "key" }) {
                items.append(URLQueryItem(name: "key", value: apiKey))
            }
            if streamingEnabled && !items.contains(where: { $0.name == "alt" }) {
                items.append(URLQueryItem(name: "alt", value: "sse"))
            }
            components.queryItems = items
            request.url = components.url
            var payload: [String: Any] = [
                "contents": [
                    ["parts": [["text": userPrompt]]]
                ]
            ]
            let trimmedSystem = systemPrompt.trimmingCharacters(in: .whitespacesAndNewlines)
            if !trimmedSystem.isEmpty {
                payload["system_instruction"] = ["parts": [["text": systemPrompt]]]
            }
            if configuration.searchEnabled && provider.supportsHostedSearch {
                payload["tools"] = [googleSearchToolPayload(for: model)]
            }
            request.httpBody = try JSONSerialization.data(withJSONObject: payload)
        case .minimax:
            let apiKey = configuration.apiKey.trimmingCharacters(in: .whitespacesAndNewlines)
            guard !apiKey.isEmpty else {
                throw NSError(domain: "Voxt.RemoteLLM", code: -304, userInfo: [NSLocalizedDescriptionKey: "MiniMax API key is empty."])
            }
            request.setValue("Bearer \(apiKey)", forHTTPHeaderField: "Authorization")
            request.httpBody = try JSONSerialization.data(withJSONObject: [
                "model": model,
                "stream": streamingEnabled,
                "messages": openAICompatibleMessages(systemPrompt: systemPrompt, userPrompt: userPrompt)
            ])
        case .ollama where usesNativeOllamaChatEndpoint(url):
            let apiKey = configuration.apiKey.trimmingCharacters(in: .whitespacesAndNewlines)
            if !apiKey.isEmpty {
                request.setValue("Bearer \(apiKey)", forHTTPHeaderField: "Authorization")
            }
            request.httpBody = try JSONSerialization.data(withJSONObject: [
                "model": model,
                "messages": openAICompatibleMessages(systemPrompt: systemPrompt, userPrompt: userPrompt),
                "stream": streamingEnabled,
                "options": [
                    "temperature": tuning.temperature,
                    "top_p": tuning.topP,
                    "num_predict": tuning.maxTokens
                ]
            ])
        default:
            let apiKey = configuration.apiKey.trimmingCharacters(in: .whitespacesAndNewlines)
            if !apiKey.isEmpty {
                request.setValue("Bearer \(apiKey)", forHTTPHeaderField: "Authorization")
            }
            var payload: [String: Any] = [
                "model": model,
                "messages": messagesOverride ?? openAICompatibleMessages(systemPrompt: systemPrompt, userPrompt: userPrompt),
                "stream": streamingEnabled,
                "max_tokens": tuning.maxTokens,
                "temperature": tuning.temperature,
                "top_p": tuning.topP
            ]
            applyOpenAICompatibleSearchConfiguration(
                to: &payload,
                provider: provider,
                configuration: configuration
            )
            request.httpBody = try JSONSerialization.data(withJSONObject: payload)
        }

        return request
    }

    private func logRequest(
        request: URLRequest,
        provider: RemoteLLMProvider,
        endpointValue: String,
        model: String,
        inputTextLength: Int,
        systemPrompt: String,
        debugInput: String,
        userPrompt: String,
        tuning: GenerationTuning
    ) {
        let proxySettings = VoxtNetworkSession.currentProxySettings
        let proxyRoute = request.url.map { resolvedProxyRoute(for: $0, settings: proxySettings) } ?? "unavailable"
        let networkMode = VoxtNetworkSession.modeDescription
        VoxtLog.llm(
            "Remote LLM request started. provider=\(provider.rawValue), endpoint=\(endpointValue), url=\(request.url?.absoluteString ?? endpointValue), model=\(model), timeoutSec=\(Int(request.timeoutInterval)), inputChars=\(inputTextLength), systemChars=\(systemPrompt.count), userChars=\(userPrompt.count), maxTokens=\(tuning.maxTokens), temp=\(tuning.temperature), topP=\(tuning.topP), networkMode=\(networkMode), proxy=\(proxyRoute)"
        )
        VoxtLog.llm(
            """
            Remote LLM request content. provider=\(provider.rawValue), endpoint=\(endpointValue), model=\(model)
            [system_prompt]
            \(VoxtLog.llmPreview(systemPrompt))
            [input]
            \(VoxtLog.llmPreview(debugInput))
            [request_content]
            \(VoxtLog.llmPreview(userPrompt))
            """
        )
    }

    private func completeStreaming(
        request: URLRequest,
        provider: RemoteLLMProvider,
        endpointValue: String,
        requestStartedAt: Date,
        attempt: Int,
        endpointCount: Int,
        onPartialText: @Sendable (String) -> Void
    ) async throws -> String {
        var aggregated = ""
        var emittedChunkCount = 0
        do {
            let (bytes, response) = try await VoxtNetworkSession.active.bytes(for: request)
            guard let http = response as? HTTPURLResponse else {
                throw NSError(domain: "Voxt.RemoteLLM", code: -305, userInfo: [NSLocalizedDescriptionKey: "Invalid remote LLM response."])
            }
            guard (200...299).contains(http.statusCode) else {
                throw NSError(
                    domain: "Voxt.RemoteLLM",
                    code: http.statusCode,
                    userInfo: [NSLocalizedDescriptionKey: "Remote LLM request failed (HTTP \(http.statusCode)) while opening stream."]
                )
            }

            var bufferedEventLines: [String] = []
            var sawEventStreamMarkers = false
            var nonEventStreamBuffer = ""

            func publish(_ chunkPayload: String) throws {
                let trimmed = chunkPayload.trimmingCharacters(in: .whitespacesAndNewlines)
                guard !trimmed.isEmpty, trimmed != "[DONE]" else { return }

                if let data = trimmed.data(using: .utf8),
                   let object = try? JSONSerialization.jsonObject(with: data) {
                    if let errorMessage = extractStreamingErrorMessage(from: object) {
                        throw NSError(
                            domain: "Voxt.RemoteLLM",
                            code: -307,
                            userInfo: [NSLocalizedDescriptionKey: errorMessage]
                        )
                    }
                    if let delta = extractStreamingDelta(from: object), !delta.isEmpty {
                        aggregated.append(delta)
                    } else if let snapshot = extractPrimaryText(from: object), !snapshot.isEmpty {
                        aggregated = mergedStreamingSnapshot(current: aggregated, next: snapshot)
                    } else {
                        return
                    }
                } else if let recovered = recoverStreamingDelta(fromRawPayload: trimmed), !recovered.isEmpty {
                    aggregated.append(recovered)
                } else if looksLikeStreamingEnvelopeFragment(trimmed) {
                    return
                } else {
                    aggregated = mergedStreamingSnapshot(current: aggregated, next: trimmed)
                }

                emittedChunkCount += 1
                onPartialText(aggregated)
            }

            for try await line in bytes.lines {
                let trimmedLine = line.trimmingCharacters(in: .newlines)
                if trimmedLine.isEmpty {
                    if !bufferedEventLines.isEmpty {
                        try publish(bufferedEventLines.joined(separator: "\n"))
                        bufferedEventLines.removeAll(keepingCapacity: true)
                    }
                    continue
                }

                if trimmedLine.hasPrefix(":") {
                    continue
                }

                if trimmedLine.hasPrefix("event:") || trimmedLine.hasPrefix("id:") || trimmedLine.hasPrefix("retry:") {
                    sawEventStreamMarkers = true
                    continue
                }

                if trimmedLine.hasPrefix("data:") {
                    sawEventStreamMarkers = true
                    var payload = String(trimmedLine.dropFirst(5))
                    if payload.hasPrefix(" ") {
                        payload.removeFirst()
                    }
                    bufferedEventLines.append(payload)
                    if shouldFlushBufferedEventLines(bufferedEventLines) {
                        try publish(bufferedEventLines.joined(separator: "\n"))
                        bufferedEventLines.removeAll(keepingCapacity: true)
                    }
                    continue
                }

                if sawEventStreamMarkers {
                    bufferedEventLines.append(trimmedLine)
                    if shouldFlushBufferedEventLines(bufferedEventLines) {
                        try publish(bufferedEventLines.joined(separator: "\n"))
                        bufferedEventLines.removeAll(keepingCapacity: true)
                    }
                } else {
                    nonEventStreamBuffer.append(line)
                    nonEventStreamBuffer.append("\n")
                    let payloads = drainNonEventStreamPayloads(buffer: &nonEventStreamBuffer)
                    for payload in payloads {
                        try publish(payload)
                    }
                }
            }

            if !bufferedEventLines.isEmpty {
                try publish(bufferedEventLines.joined(separator: "\n"))
            }
            let trailingPayloads = drainNonEventStreamPayloads(buffer: &nonEventStreamBuffer)
            for payload in trailingPayloads {
                try publish(payload)
            }
            let trailingText = nonEventStreamBuffer.trimmingCharacters(in: .whitespacesAndNewlines)
            if !trailingText.isEmpty {
                try publish(trailingText)
            }

            let totalElapsedMs = Int(Date().timeIntervalSince(requestStartedAt) * 1000)
            VoxtLog.llm(
                "Remote LLM streaming response received. provider=\(provider.rawValue), endpoint=\(endpointValue), status=\(http.statusCode), attempt=\(attempt)/\(endpointCount), chunks=\(emittedChunkCount), totalMs=\(totalElapsedMs)"
            )
            VoxtLog.llm(
                """
                Remote LLM streaming content. provider=\(provider.rawValue), endpoint=\(endpointValue), status=\(http.statusCode)
                [output]
                \(VoxtLog.llmPreview(aggregated))
                """
            )
            return aggregated
        } catch {
            throw StreamingFailure(
                underlying: error,
                partialText: aggregated,
                emittedChunkCount: emittedChunkCount
            )
        }
    }

    private func supportsStreaming(provider: RemoteLLMProvider, intent: CompletionIntent) -> Bool {
        guard intent == .rewrite else { return false }
        return true
    }

    func requestTimeoutInterval(for provider: RemoteLLMProvider) -> TimeInterval {
        switch provider {
        case .zai, .volcengine:
            return 30
        default:
            return 40
        }
    }

    private func generationTuning(
        for provider: RemoteLLMProvider,
        inputTextLength: Int,
        systemPromptLength: Int,
        userPromptLength: Int,
        intent: CompletionIntent
    ) -> GenerationTuning {
        let outputBudget = estimatedOutputTokenBudget(
            inputTextLength: inputTextLength,
            systemPromptLength: systemPromptLength,
            userPromptLength: userPromptLength,
            intent: intent
        )
        switch provider {
        case .volcengine:
            // Favor low latency and deterministic rewrite/translation behavior.
            return GenerationTuning(maxTokens: outputBudget, temperature: 0.1, topP: 0.3)
        case .zai:
            return GenerationTuning(maxTokens: outputBudget, temperature: 0.2, topP: 0.7)
        default:
            return GenerationTuning(maxTokens: outputBudget, temperature: 0.2, topP: 0.9)
        }
    }

    private func estimatedOutputTokenBudget(
        inputTextLength: Int,
        systemPromptLength: Int,
        userPromptLength: Int,
        intent: CompletionIntent
    ) -> Int {
        let safeInput = max(1, inputTextLength)
        // Keep output budget mainly tied to ASR text length, and reserve a small
        // extra window for instruction overhead (system/user prompt framing).
        let instructionChars = max(0, systemPromptLength + userPromptLength - safeInput)
        let baseMultiplier: Double
        let minimumBudget: Int
        let maximumBudget: Int

        switch intent {
        case .translation:
            baseMultiplier = 1.35
            minimumBudget = 128
            maximumBudget = 1024
        case .rewrite:
            // Rewrite often needs to synthesize a fresh answer from a short spoken
            // instruction, so the budget cannot track prompt length too closely.
            baseMultiplier = safeInput < 180 ? 2.6 : 1.4
            minimumBudget = safeInput < 180 ? 384 : 256
            maximumBudget = 1536
        case .enhancement:
            baseMultiplier = 1.15
            minimumBudget = 128
            maximumBudget = 1024
        }

        let contentEstimate = Int(Double(safeInput) * baseMultiplier)
        let instructionReserve = min(intent == .rewrite ? 256 : 192, max(32, instructionChars / 12))
        let estimate = contentEstimate + instructionReserve
        return max(minimumBudget, min(estimate, maximumBudget))
    }

    private func shouldRetry(error: Error, provider: RemoteLLMProvider) -> Bool {
        guard provider == .zai else { return false }
        let nsError = error as NSError
        if nsError.domain == NSURLErrorDomain {
            return [
                NSURLErrorTimedOut,
                NSURLErrorCannotConnectToHost,
                NSURLErrorNetworkConnectionLost,
                NSURLErrorNotConnectedToInternet
            ].contains(nsError.code)
        }
        if nsError.domain == "Voxt.RemoteLLM" {
            return (500...599).contains(nsError.code)
        }
        return false
    }

    private func resolvedEndpointCandidates(provider: RemoteLLMProvider, primaryEndpoint: String) -> [String] {
        guard provider == .zai else { return [primaryEndpoint] }

        var values: [String] = [primaryEndpoint]
        if let alternate = alternateZAIEndpoint(from: primaryEndpoint),
           alternate.caseInsensitiveCompare(primaryEndpoint) != .orderedSame {
            values.append(alternate)
        }
        return values
    }

    private func alternateZAIEndpoint(from endpoint: String) -> String? {
        guard var components = URLComponents(string: endpoint) else {
            return "https://api.z.ai/api/paas/v4/chat/completions"
        }
        let host = (components.host ?? "").lowercased()
        if host == "open.bigmodel.cn" {
            components.host = "api.z.ai"
            return components.string
        }
        if host == "api.z.ai" {
            components.host = "open.bigmodel.cn"
            return components.string
        }
        if host.hasSuffix("bigmodel.cn") {
            components.host = "api.z.ai"
            return components.string
        }
        return "https://api.z.ai/api/paas/v4/chat/completions"
    }

}
