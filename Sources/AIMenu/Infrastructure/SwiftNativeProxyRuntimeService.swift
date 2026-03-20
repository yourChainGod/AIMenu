import Foundation

actor SwiftNativeProxyRuntimeService: ProxyRuntimeService {
    enum UpstreamRouteFamily: Equatable {
        case codex
        case general
    }

    private static let stableClientModels = [
        "gpt-5",
        "gpt-5-4",
        "gpt-5.4",
        "gpt-5-mini",
        "gpt-5.1",
        "gpt-5.2",
        "gpt-5.3"
    ]

    private static let compatibilityCodexModels = [
        "gpt-5-codex",
        "gpt-5-codex-mini",
        "gpt-5.1-codex",
        "gpt-5.1-codex-mini",
        "gpt-5.1-codex-max",
        "gpt-5.2-codex",
        "gpt-5.3-codex",
        "gpt-5.3-codex-spark"
    ]

    private static let clientVisibleModels = stableClientModels + compatibilityCodexModels
    private static let defaultCodexClientVersion = "0.101.0"
    private static let defaultCodexUserAgent = "codex_cli_rs/0.101.0 (Mac OS 26.0.1; arm64) Apple_Terminal/464"

    private let paths: FileSystemPaths
    private let storeRepository: AccountsStoreRepository
    private let authRepository: AuthRepository
    // Shared by runtime helpers split across companion extensions.
    let dateProvider: DateProviding

    private var server: SimpleHTTPServer?
    private var runningPort: Int?
    private var activeAccountID: String?
    private var activeAccountLabel: String?
    private var lastError: String?

    private let models = SwiftNativeProxyRuntimeService.clientVisibleModels

    init(
        paths: FileSystemPaths,
        storeRepository: AccountsStoreRepository,
        authRepository: AuthRepository,
        dateProvider: DateProviding = SystemDateProvider()
    ) {
        self.paths = paths
        self.storeRepository = storeRepository
        self.authRepository = authRepository
        self.dateProvider = dateProvider
    }

    func status() async -> ApiProxyStatus {
        let running = server != nil
        let apiKey = try? readPersistedAPIKey()
        let availableAccounts = (try? loadCandidates().count) ?? 0

        return ApiProxyStatus(
            running: running,
            port: running ? runningPort : nil,
            apiKey: apiKey,
            baseURL: runningPort.map { "http://127.0.0.1:\($0)/v1" },
            availableAccounts: availableAccounts,
            activeAccountID: activeAccountID,
            activeAccountLabel: activeAccountLabel,
            lastError: lastError
        )
    }

    func start(preferredPort: Int?) async throws -> ApiProxyStatus {
        if server != nil {
            return await status()
        }

        let desiredPort = preferredPort ?? 8787
        guard desiredPort > 0 && desiredPort < 65536 else {
            throw AppError.invalidData(L10n.tr("error.proxy_runtime.invalid_port_format", String(desiredPort)))
        }

        _ = try ensurePersistedAPIKey()

        let boundServer: SimpleHTTPServer
        do {
            boundServer = try SimpleHTTPServer(port: UInt16(desiredPort)) { [weak self] request in
                guard let self else {
                    return HTTPResponse.json(statusCode: 500, object: ["error": ["message": "Proxy runtime unavailable"]])
                }
                return await self.handle(request: request)
            }
            boundServer.start()
        } catch {
            lastError = L10n.tr("error.proxy_runtime.start_swift_proxy_failed_format", error.localizedDescription)
            throw AppError.io(lastError ?? L10n.tr("error.proxy_runtime.start_failed"), underlying: error)
        }

        server = boundServer
        runningPort = desiredPort
        lastError = nil

        let healthy = await waitForHealth(port: desiredPort)
        if !healthy {
            _ = await stop()
            lastError = L10n.tr("error.proxy_runtime.health_check_failed")
            throw AppError.io(lastError ?? L10n.tr("error.proxy_runtime.start_failed"))
        }

        return await status()
    }

    func stop() async -> ApiProxyStatus {
        server?.stop()
        server = nil
        runningPort = nil
        activeAccountID = nil
        activeAccountLabel = nil
        return await status()
    }

    func refreshAPIKey() async throws -> ApiProxyStatus {
        let key = randomAPIKey()
        try persistAPIKey(key)
        return await status()
    }

    func syncAccountsStore() async throws {
        // Swift native runtime reads the same app store source directly.
    }

    private func handle(request: HTTPRequest) async -> HTTPResponse {
        if request.path == "/health" && request.method == "GET" {
            return HTTPResponse.json(statusCode: 200, object: ["ok": true])
        }

        guard isAuthorized(request.headers) else {
            return jsonError(statusCode: 401, message: "Invalid proxy api key.")
        }

        if request.path == "/v1/models" && request.method == "GET" {
            let list = models.map { model in
                [
                    "id": model,
                    "object": "model",
                    "created": 0,
                    "owned_by": "openai"
                ] as [String: Any]
            }
            return HTTPResponse.json(statusCode: 200, object: ["object": "list", "data": list])
        }

        if request.path == "/v1/responses" && request.method == "POST" {
            return await handleResponsesRequest(body: request.body, downstreamHeaders: request.headers)
        }

        if request.path == "/v1/chat/completions" && request.method == "POST" {
            return await handleChatCompletionsRequest(body: request.body, downstreamHeaders: request.headers)
        }

        return jsonError(
            statusCode: 404,
            message: L10n.tr("error.proxy_runtime.unsupported_route")
        )
    }

    private func handleResponsesRequest(body: Data, downstreamHeaders: [String: String]) async -> HTTPResponse {
        let object: [String: Any]
        do {
            object = try parseJSONObject(from: body)
        } catch {
            return jsonError(statusCode: 400, message: error.localizedDescription)
        }

        let payload: [String: Any]
        let downstreamStream: Bool
        do {
            let normalized = try normalizeResponsesRequest(object)
            payload = normalized.payload
            downstreamStream = normalized.downstreamStream
        } catch {
            return jsonError(statusCode: 400, message: error.localizedDescription)
        }

        let upstream: UpstreamResponse
        do {
            upstream = try await sendOverCandidates(payload: payload, downstreamHeaders: downstreamHeaders)
        } catch {
            return jsonError(statusCode: 502, message: error.localizedDescription)
        }

        if downstreamStream {
            return HTTPResponse(
                statusCode: 200,
                headers: ["Content-Type": "text/event-stream; charset=utf-8"],
                body: upstream.body
            )
        }

        do {
            let completed = try extractCompletedResponse(fromSSE: upstream.body)
            let rewritten = rewriteResponseModelFields(completed)
            return HTTPResponse.json(statusCode: 200, object: rewritten)
        } catch {
            return jsonError(statusCode: 502, message: error.localizedDescription)
        }
    }

    private func handleChatCompletionsRequest(body: Data, downstreamHeaders: [String: String]) async -> HTTPResponse {
        let object: [String: Any]
        do {
            object = try parseJSONObject(from: body)
        } catch {
            return jsonError(statusCode: 400, message: error.localizedDescription)
        }

        let payload: [String: Any]
        let downstreamStream: Bool
        let requestedModel: String

        do {
            requestedModel = (object["model"] as? String) ?? "gpt-5"
            let normalized = try convertChatRequestToResponses(object)
            payload = normalized.payload
            downstreamStream = normalized.downstreamStream
        } catch {
            return jsonError(statusCode: 400, message: error.localizedDescription)
        }

        let upstream: UpstreamResponse
        do {
            upstream = try await sendOverCandidates(payload: payload, downstreamHeaders: downstreamHeaders)
        } catch {
            return jsonError(statusCode: 502, message: error.localizedDescription)
        }

        if downstreamStream {
            do {
                let sse = try convertResponsesSSEToChatCompletionsSSE(upstream.body, fallbackModel: requestedModel)
                return HTTPResponse(
                    statusCode: 200,
                    headers: ["Content-Type": "text/event-stream; charset=utf-8"],
                    body: sse
                )
            } catch {
                return jsonError(statusCode: 502, message: error.localizedDescription)
            }
        }

        do {
            let completed = try extractCompletedResponse(fromSSE: upstream.body)
            let completion = convertCompletedResponseToChatCompletion(completed, fallbackModel: requestedModel)
            return HTTPResponse.json(statusCode: 200, object: completion)
        } catch {
            return jsonError(statusCode: 502, message: error.localizedDescription)
        }
    }

    private func sendOverCandidates(payload: [String: Any], downstreamHeaders: [String: String]) async throws -> UpstreamResponse {
        let candidates = try loadCandidates()
        guard !candidates.isEmpty else {
            throw AppError.invalidData(L10n.tr("error.proxy_runtime.no_accounts_available"))
        }

        var failureDetails: [String] = []
        var retryFailures: [RetryFailureInfo] = []
        for candidate in candidates {
            do {
                let response = try await sendUpstream(payload: payload, candidate: candidate, downstreamHeaders: downstreamHeaders)
                if response.statusCode >= 200 && response.statusCode < 300 {
                    activeAccountID = candidate.accountID
                    activeAccountLabel = candidate.label
                    lastError = nil
                    return response
                }

                let bodyText = String(data: response.body, encoding: .utf8) ?? ""
                let detail = "\(candidate.label): \(response.statusCode) \(truncateForError(bodyText, maxLength: 120))"
                failureDetails.append(detail)

                if let retryFailure = classifyRetryFailure(statusCode: response.statusCode, bodyText: bodyText) {
                    retryFailures.append(retryFailure)
                    continue
                } else {
                    lastError = detail
                    break
                }
            } catch {
                let detail = "\(candidate.label): \(error.localizedDescription)"
                failureDetails.append(detail)
            }
        }

        if !retryFailures.isEmpty && retryFailures.count == candidates.count {
            let summary = buildRetriableFailureSummary(retryFailures)
            let message = summary.isEmpty
                ? L10n.tr("error.proxy_runtime.all_accounts_unavailable")
                : L10n.tr("error.proxy_runtime.all_accounts_unavailable_with_summary_format", summary)
            lastError = message
            throw AppError.network(message)
        }

        let preview = failureDetails.prefix(2).joined(separator: " | ")
        let message = failureDetails.count > 2
            ? L10n.tr("error.proxy_runtime.upstream_failed_with_more_format", preview, String(failureDetails.count - 2))
            : L10n.tr("error.proxy_runtime.upstream_failed_format", preview)
        lastError = message
        throw AppError.network(message)
    }

    private func sendUpstream(payload: [String: Any], candidate: ProxyCandidate, downstreamHeaders: [String: String]) async throws -> UpstreamResponse {
        guard JSONSerialization.isValidJSONObject(payload) else {
            throw AppError.invalidData(L10n.tr("error.proxy_runtime.invalid_upstream_payload"))
        }

        let firstResponse = try await performUpstreamRequest(payload: payload, candidate: candidate, downstreamHeaders: downstreamHeaders)
        let firstBodyText = String(data: firstResponse.body, encoding: .utf8) ?? ""
        if Self.shouldRetryWithAutoReasoningSummary(statusCode: firstResponse.statusCode, bodyText: firstBodyText),
           let adjustedPayload = Self.payloadWithAutoReasoningSummaryIfNeeded(payload: payload) {
            return try await performUpstreamRequest(payload: adjustedPayload, candidate: candidate, downstreamHeaders: downstreamHeaders)
        }

        return firstResponse
    }

    private func performUpstreamRequest(payload: [String: Any], candidate: ProxyCandidate, downstreamHeaders: [String: String]) async throws -> UpstreamResponse {
        let body = try JSONSerialization.data(withJSONObject: payload)
        let upstreamModel = (payload["model"] as? String) ?? "gpt-5.4"
        let version = Self.normalizedForwardHeader(downstreamHeaders["version"]) ?? Self.defaultCodexClientVersion
        let sessionID = Self.normalizedForwardHeader(downstreamHeaders["session_id"])
            ?? Self.normalizedForwardHeader(downstreamHeaders["session-id"])
            ?? UUID().uuidString
        let userAgent = Self.normalizedForwardHeader(downstreamHeaders["user-agent"]) ?? Self.defaultCodexUserAgent
        var request = URLRequest(url: responsesEndpoint(forUpstreamModel: upstreamModel))
        request.httpMethod = "POST"
        request.timeoutInterval = NetworkConfig.upstreamTimeoutSeconds
        request.httpBody = body
        request.setValue("Bearer \(candidate.accessToken)", forHTTPHeaderField: "Authorization")
        request.setValue(candidate.accountID, forHTTPHeaderField: "ChatGPT-Account-Id")
        request.setValue("application/json", forHTTPHeaderField: "Content-Type")
        request.setValue("text/event-stream", forHTTPHeaderField: "Accept")
        request.setValue("codex_cli_rs", forHTTPHeaderField: "Originator")
        request.setValue(version, forHTTPHeaderField: "Version")
        request.setValue(sessionID, forHTTPHeaderField: "Session_id")
        request.setValue(userAgent, forHTTPHeaderField: "User-Agent")
        request.setValue("Keep-Alive", forHTTPHeaderField: "Connection")

        let (responseBytes, response) = try await URLSession.shared.bytes(for: request)
        let statusCode = (response as? HTTPURLResponse)?.statusCode ?? 500
        var responseBody = Data()
        responseBody.reserveCapacity(NetworkConfig.upstreamResponseBufferHint)

        for try await byte in responseBytes {
            responseBody.append(byte)
            if responseBody.count > ProxyRuntimeLimits.maxUpstreamResponseBytes {
                throw AppError.network(
                    L10n.tr(
                        "error.proxy_runtime.upstream_response_too_large_format",
                        ProxyRuntimeLimits.limitDescription(for: ProxyRuntimeLimits.maxUpstreamResponseBytes)
                    )
                )
            }
        }

        if statusCode == 200 {
            try? authRepository.writeCurrentAuth(candidate.authJSON)
        }
        return UpstreamResponse(statusCode: statusCode, body: responseBody)
    }


    private func loadCandidates() throws -> [ProxyCandidate] {
        let store = try storeRepository.loadStore()

        let candidates = try store.accounts.compactMap { account -> ProxyCandidate? in
            let extracted = try authRepository.extractAuth(from: account.authJSON)
            return ProxyCandidate(
                id: account.id,
                label: account.label,
                accountID: extracted.accountID,
                accessToken: extracted.accessToken,
                authJSON: account.authJSON,
                oneWeekUsed: account.usage?.oneWeek?.usedPercent,
                fiveHourUsed: account.usage?.fiveHour?.usedPercent
            )
        }

        return candidates.sorted { lhs, rhs in
            lhs.remainingScore > rhs.remainingScore
        }
    }

    private func parseJSONObject(from data: Data) throws -> [String: Any] {
        let object = try JSONSerialization.jsonObject(with: data)
        guard let dict = object as? [String: Any] else {
            throw AppError.invalidData(L10n.tr("error.proxy_runtime.request_body_must_be_object"))
        }
        return dict
    }

    func jsonString(_ object: Any) -> String {
        if let data = try? JSONSerialization.data(withJSONObject: object),
           let text = String(data: data, encoding: .utf8) {
            return text
        }
        return "{}"
    }

    private func jsonError(statusCode: Int, message: String) -> HTTPResponse {
        HTTPResponse.json(statusCode: statusCode, object: [
            "error": [
                "message": message,
                "type": statusCode == 400 ? "invalid_request_error" : "server_error"
            ]
        ])
    }

    private func responsesEndpoint(forUpstreamModel model: String) -> URL {
        let routeFamily = Self.resolveUpstreamRouteFamily(forUpstreamModel: model)
        let base = resolveUpstreamBaseURL(routeFamily: routeFamily)
        return URL(string: "\(base)/responses")!
    }

    private func resolveUpstreamBaseURL(routeFamily: UpstreamRouteFamily) -> String {
        let defaultOrigin = "https://chatgpt.com"
        let configured = readChatGPTBaseURLFromConfig() ?? defaultOrigin
        return Self.resolveUpstreamBaseURL(configuredBaseURL: configured, routeFamily: routeFamily)
    }


    private func readChatGPTBaseURLFromConfig() -> String? {
        guard let raw = try? String(contentsOf: paths.codexConfigPath, encoding: .utf8), !raw.isEmpty else {
            return nil
        }

        for line in raw.split(whereSeparator: { $0.isNewline }) {
            let trimmed = line.trimmingCharacters(in: .whitespaces)
            guard trimmed.hasPrefix("chatgpt_base_url") else { continue }
            guard let equalIndex = trimmed.firstIndex(of: "=") else { continue }
            let value = trimmed[trimmed.index(after: equalIndex)...]
                .trimmingCharacters(in: .whitespaces)
                .trimmingCharacters(in: CharacterSet(charactersIn: "\"'"))
            if !value.isEmpty {
                return value
            }
        }

        return nil
    }

    private func isAuthorized(_ headers: [String: String]) -> Bool {
        guard let expected = try? readPersistedAPIKey(), !expected.isEmpty else {
            return false
        }
        if let apiKeyHeader = headers["x-api-key"]?.trimmingCharacters(in: .whitespacesAndNewlines),
           !apiKeyHeader.isEmpty,
           apiKeyHeader == expected {
            return true
        }

        guard let authorization = headers["authorization"]?.trimmingCharacters(in: .whitespacesAndNewlines),
              !authorization.isEmpty else {
            return false
        }

        let lower = authorization.lowercased()
        if lower.hasPrefix("bearer ") {
            let provided = String(authorization.dropFirst("Bearer ".count)).trimmingCharacters(in: .whitespacesAndNewlines)
            return provided == expected
        }

        return authorization == expected
    }

    private func ensurePersistedAPIKey() throws -> String {
        if let key = try readPersistedAPIKey(), !key.isEmpty {
            return key
        }

        let generated = randomAPIKey()
        try persistAPIKey(generated)
        return generated
    }

    private func readPersistedAPIKey() throws -> String? {
        guard FileManager.default.fileExists(atPath: paths.proxyDaemonKeyPath.path) else {
            return nil
        }

        let text = try String(contentsOf: paths.proxyDaemonKeyPath, encoding: .utf8)
            .trimmingCharacters(in: .whitespacesAndNewlines)
        return text.isEmpty ? nil : text
    }

    private func persistAPIKey(_ value: String) throws {
        try FileManager.default.createDirectory(at: paths.proxyDaemonDataDirectory, withIntermediateDirectories: true)
        try value.write(to: paths.proxyDaemonKeyPath, atomically: true, encoding: .utf8)
        #if canImport(Darwin)
        _ = chmod(paths.proxyDaemonKeyPath.path, S_IRUSR | S_IWUSR)
        #endif
    }

    private func randomAPIKey() -> String {
        "sk-\(UUID().uuidString.replacingOccurrences(of: "-", with: "").lowercased())"
    }

    private func waitForHealth(port: Int) async -> Bool {
        guard let url = URL(string: "http://127.0.0.1:\(port)/health") else { return false }
        let deadline = Date().addingTimeInterval(6)

        while Date() < deadline {
            do {
                let (_, response) = try await URLSession.shared.data(from: url)
                if let http = response as? HTTPURLResponse, (200..<300).contains(http.statusCode) {
                    return true
                }
            } catch {
                // retry until timeout
            }
            try? await Task.sleep(for: .milliseconds(250))
        }

        return false
    }
}

private struct ProxyCandidate {
    var id: String
    var label: String
    var accountID: String
    var accessToken: String
    var authJSON: JSONValue
    var oneWeekUsed: Double?
    var fiveHourUsed: Double?

    var remainingScore: Double {
        let weekUsed = oneWeekUsed ?? 100
        let fiveUsed = fiveHourUsed ?? 100
        let weekRemaining = max(0, 100 - weekUsed)
        let fiveRemaining = max(0, 100 - fiveUsed)
        return weekRemaining * 0.7 + fiveRemaining * 0.3
    }
}


private struct UpstreamResponse {
    var statusCode: Int
    var body: Data
}
