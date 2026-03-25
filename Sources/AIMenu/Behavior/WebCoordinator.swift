import Foundation
import Network

actor WebCoordinator {
    private let accountsCoordinator: AccountsCoordinator
    private let providerCoordinator: ProviderCoordinator
    private let proxyCoordinator: ProxyCoordinator
    private let authService: WebRemoteAuthService
    private let agentRuntime: AgentRuntimeCoordinator
    private let skillCoordinator: SkillCoordinator?

    private var httpServer: SimpleHTTPServer?
    private var wsServer: WebSocketServer?
    private var sessionManager: WebSessionManager?
    private var wsDelegate: WebSocketBridge?
    private var currentHTTPPort: Int?
    private var currentWSPort: Int?
    private var lastError: String?

    init(
        accountsCoordinator: AccountsCoordinator,
        providerCoordinator: ProviderCoordinator,
        proxyCoordinator: ProxyCoordinator,
        authService: WebRemoteAuthService,
        agentRuntime: AgentRuntimeCoordinator,
        skillCoordinator: SkillCoordinator? = nil
    ) {
        self.accountsCoordinator = accountsCoordinator
        self.providerCoordinator = providerCoordinator
        self.proxyCoordinator = proxyCoordinator
        self.authService = authService
        self.agentRuntime = agentRuntime
        self.skillCoordinator = skillCoordinator
    }

    func status() -> WebRemoteStatus {
        WebRemoteStatus(
            running: httpServer != nil && wsServer != nil,
            httpPort: currentHTTPPort,
            wsPort: currentWSPort,
            connectedClients: wsServer?.activeConnectionCount ?? 0,
            lastError: lastError
        )
    }

    func start(httpPort: Int, wsPort: Int) async throws -> WebRemoteStatus {
        // Guard against reentrant start — stop existing servers first
        if httpServer != nil || wsServer != nil {
            _ = await stop()
        }

        do {
            let handler = WebRemoteHTTPHandler()
            let http = try SimpleHTTPServer(port: UInt16(httpPort)) { request in
                await handler.handle(request: request)
            }

            let ws = try WebSocketServer(port: UInt16(wsPort))
            let manager = WebSessionManager(authService: authService)

            let bridge = WebSocketBridge(sessionManager: manager, wsServer: ws)
            ws.delegate = bridge

            // Wire auth timeout disconnection
            let capturedWsForTimeout = ws
            await manager.setOnDisconnect { connectionID in
                capturedWsForTimeout.disconnect(connectionID)
            }

            await manager.setOnAuthenticatedMessage { [weak self] connectionID, message in
                guard let self else {
                    return WebServerMessage.error("Server unavailable")
                }
                return await self.handleRequest(message, from: connectionID)
            }

            // 先安装事件处理器，再对外监听端口，避免启动瞬间丢消息。
            let capturedWs = ws
            let capturedManager = manager
            await self.agentRuntime.setOnStreamEvent { [weak self] _, message in
                guard self != nil else { return }
                guard let data = try? JSONEncoder().encode(message) else { return }
                let connectionIDs = await capturedManager.authenticatedConnectionIDs()
                capturedWs.broadcast(data: data, to: connectionIDs)
            }

            self.httpServer = http
            self.wsServer = ws
            self.sessionManager = manager
            self.wsDelegate = bridge
            self.currentHTTPPort = httpPort
            self.currentWSPort = wsPort
            self.lastError = nil

            // Wait for both listeners to confirm they are bound and ready
            try await http.startAndWaitReady()
            try await ws.startAndWaitReady()

            NSLog("[WebCoordinator] started on HTTP:\(httpPort) WS:\(wsPort)")
            return status()
        } catch {
            lastError = error.localizedDescription
            httpServer?.stop()
            wsServer?.stop()
            httpServer = nil
            wsServer = nil
            sessionManager = nil
            wsDelegate = nil
            currentHTTPPort = nil
            currentWSPort = nil
            await agentRuntime.setOnStreamEvent(nil)
            NSLog("[WebCoordinator] start failed: \(error.localizedDescription)")
            throw error
        }
    }

    @discardableResult
    func stop() async -> WebRemoteStatus {
        await agentRuntime.setOnStreamEvent(nil)
        httpServer?.stop()
        wsServer?.stop()
        httpServer = nil
        wsServer = nil
        sessionManager = nil
        wsDelegate = nil
        currentHTTPPort = nil
        currentWSPort = nil
        NSLog("[WebCoordinator] stopped")
        return status()
    }

    func currentToken() async -> String {
        await authService.currentToken()
    }

    func regenerateToken() async -> String {
        let newToken = await authService.regenerateToken()
        await sessionManager?.revokeAllAuthenticated()
        return newToken
    }

    // MARK: - Request Handling

    func handleRequest(_ message: WebClientMessage, from connectionID: String) async -> WebServerMessage {
        switch message.type {
        case .requestAccounts:
            let snapshot = await fetchAccountsSnapshot()
            return WebServerMessage.snapshot(type: .accountsSnapshot, payload: snapshot, requestID: message.requestID)

        case .requestProviders:
            let snapshot = await fetchProvidersSnapshot()
            return WebServerMessage.snapshot(type: .providersSnapshot, payload: snapshot, requestID: message.requestID)

        case .requestProxyStatus:
            let snapshot = await fetchProxySnapshot()
            return WebServerMessage.snapshot(type: .proxyStatusSnapshot, payload: snapshot, requestID: message.requestID)

        case .auth, .ping:
            // These are handled by WebSessionManager, should not reach here
            return WebServerMessage.error("Unexpected message type", requestID: message.requestID)

        case .sendMessage, .createSession, .listSessions, .loadSession, .deleteSession, .abortSession, .renameSession:
            return await handleChatRequest(message, from: connectionID)

        case .listAllProviders:
            return await handleListAllProviders(message)

        case .addProvider, .updateProvider, .deleteProvider, .switchProvider:
            return await handleProviderCRUD(message)

        case .setToken:
            return await handleSetToken(message)

        case .listDirectories:
            return handleListDirectories(message)

        case .requestSlashCommands:
            return await handleSlashCommands(message)
        }
    }

    // MARK: - Data Fetchers

    private func fetchAccountsSnapshot() async -> JSONValue {
        do {
            let accounts = try await accountsCoordinator.listAccounts()
            let items: [JSONValue] = accounts.map { account in
                let dict: [String: JSONValue] = [
                    "id": .string(account.id),
                    "label": .string(account.label),
                    "email": .string(account.email ?? ""),
                    "planType": .string(account.planType ?? ""),
                    "isCurrent": .bool(account.isCurrent),
                    "teamName": account.displayTeamName.map { JSONValue.string($0) } ?? .null
                ]
                return JSONValue.object(dict)
            }
            let result: [String: JSONValue] = [
                "accounts": .array(items),
                "count": .number(Double(items.count))
            ]
            return .object(result)
        } catch {
            let result: [String: JSONValue] = ["error": .string(error.localizedDescription), "accounts": .array([])]
            return .object(result)
        }
    }

    private func fetchProvidersSnapshot() async -> JSONValue {
        do {
            var allProviders: [JSONValue] = []
            for appType in ProviderAppType.allCases {
                let providers = try await providerCoordinator.listProviders(for: appType)
                for provider in providers {
                    let dict: [String: JSONValue] = [
                        "id": .string(provider.id),
                        "name": .string(provider.name),
                        "appType": .string(provider.appType.rawValue),
                        "isCurrent": .bool(provider.isCurrent)
                    ]
                    allProviders.append(JSONValue.object(dict))
                }
            }
            let result: [String: JSONValue] = [
                "providers": .array(allProviders),
                "count": .number(Double(allProviders.count))
            ]
            return .object(result)
        } catch {
            let result: [String: JSONValue] = ["error": .string(error.localizedDescription), "providers": .array([])]
            return .object(result)
        }
    }

    private func fetchProxySnapshot() async -> JSONValue {
        let (proxyStatus, cloudflaredStatus) = await proxyCoordinator.loadStatus()
        let proxyDict: [String: JSONValue] = [
            "running": .bool(proxyStatus.running),
            "port": proxyStatus.port.map { JSONValue.number(Double($0)) } ?? .null,
            "baseURL": proxyStatus.baseURL.map { JSONValue.string($0) } ?? .null,
            "apiKey": proxyStatus.apiKey.map { JSONValue.string(Self.maskSecret($0)) } ?? .null,
            "availableAccounts": .number(Double(proxyStatus.availableAccounts)),
            "lastError": proxyStatus.lastError.map { JSONValue.string($0) } ?? .null
        ]
        let cfDict: [String: JSONValue] = [
            "running": .bool(cloudflaredStatus.running),
            "publicURL": cloudflaredStatus.publicURL.map { JSONValue.string($0) } ?? .null,
            "installed": .bool(cloudflaredStatus.installed)
        ]
        let result: [String: JSONValue] = [
            "proxy": .object(proxyDict),
            "cloudflared": .object(cfDict)
        ]
        return .object(result)
    }

    // MARK: - Chat Request Handler

    private func handleChatRequest(_ message: WebClientMessage, from connectionID: String) async -> WebServerMessage {
        do {
            switch message.type {
            case .listSessions:
                let sessions = try await agentRuntime.listSessions()
                let items: [JSONValue] = sessions.map { s in
                    JSONValue.object([
                        "id": .string(s.id),
                        "title": .string(s.title),
                        "agent": .string(s.agent.rawValue),
                        "isRunning": .bool(s.isRunning),
                        "updatedAt": .number(Double(s.updatedAt))
                    ])
                }
                return .snapshot(type: .sessionList, payload: .object(["sessions": .array(items)]), requestID: message.requestID)

            case .createSession:
                let agent = AgentType(rawValue: message.agent ?? "claude") ?? .claude
                let mode = AgentPermissionMode(rawValue: message.mode ?? "default") ?? .default
                let session = try await agentRuntime.createSession(agent: agent, mode: mode, model: message.model, cwd: message.cwd)
                return .snapshot(type: .sessionDetail, payload: encodeSession(session), requestID: message.requestID)

            case .loadSession:
                guard let sessionID = message.sessionID else {
                    return .error("sessionID required", requestID: message.requestID)
                }
                guard let session = try await agentRuntime.loadSession(id: sessionID) else {
                    return .error("Session not found", requestID: message.requestID)
                }
                return .snapshot(type: .sessionDetail, payload: encodeSession(session), requestID: message.requestID)

            case .deleteSession:
                guard let sessionID = message.sessionID else {
                    return .error("sessionID required", requestID: message.requestID)
                }
                try await agentRuntime.deleteSession(id: sessionID)
                return .snapshot(type: .sessionList, payload: .object(["deleted": .string(sessionID)]), requestID: message.requestID)

            case .sendMessage:
                guard let sessionID = message.sessionID, let text = message.text, !text.isEmpty else {
                    return .error("sessionID and text required", requestID: message.requestID)
                }
                guard text.utf8.count <= 102_400 else {
                    return .error("Message too large (max 100KB)", requestID: message.requestID)
                }
                try await agentRuntime.sendMessage(sessionId: sessionID, text: text)
                return WebServerMessage(type: .chatDone, success: true, requestID: message.requestID, message: "Message sent", timestamp: Int64(Date().timeIntervalSince1970 * 1000))

            case .abortSession:
                guard let sessionID = message.sessionID else {
                    return .error("sessionID required", requestID: message.requestID)
                }
                await agentRuntime.abortSession(id: sessionID)
                return WebServerMessage(type: .chatDone, success: true, requestID: message.requestID, message: "Session aborted", timestamp: Int64(Date().timeIntervalSince1970 * 1000))

            case .renameSession:
                guard let sessionID = message.sessionID,
                      let title = message.sessionTitle?.trimmingCharacters(in: .whitespacesAndNewlines),
                      !title.isEmpty else {
                    return .error("sessionID and sessionTitle required", requestID: message.requestID)
                }
                try await agentRuntime.renameSession(id: sessionID, title: String(title.prefix(120)))
                return .snapshot(type: .sessionRenamed, payload: .object(["id": .string(sessionID), "title": .string(title)]), requestID: message.requestID)

            default:
                return .error("Unexpected chat message type", requestID: message.requestID)
            }
        } catch {
            return .error(error.localizedDescription, requestID: message.requestID)
        }
    }

    private func encodeSession(_ session: AgentSession) -> JSONValue {
        let messages: [JSONValue] = session.messages.map { msg in
            var dict: [String: JSONValue] = [
                "role": .string(msg.role.rawValue),
                "content": .string(msg.content),
                "timestamp": .number(Double(msg.timestamp))
            ]
            if let toolCalls = msg.toolCalls {
                let tools: [JSONValue] = toolCalls.map { tc in
                    JSONValue.object([
                        "id": .string(tc.id),
                        "name": .string(tc.name),
                        "input": tc.input.map { JSONValue.string($0) } ?? .null,
                        "result": tc.result.map { JSONValue.string($0) } ?? .null,
                        "isDone": .bool(tc.isDone)
                    ])
                }
                dict["toolCalls"] = .array(tools)
            }
            return JSONValue.object(dict)
        }
        let sessionDict: [String: JSONValue] = [
            "id": .string(session.id),
            "agent": .string(session.agent.rawValue),
            "title": .string(session.title),
            "permissionMode": .string(session.permissionMode.rawValue),
            "model": session.model.map { JSONValue.string($0) } ?? .null,
            "cwd": session.cwd.map { JSONValue.string($0) } ?? .null,
            "isRunning": .bool(session.isRunning),
            "messages": .array(messages),
            "createdAt": .number(Double(session.createdAt)),
            "updatedAt": .number(Double(session.updatedAt))
        ]
        return .object(sessionDict)
    }

    // MARK: - Provider Handlers

    private func handleListAllProviders(_ message: WebClientMessage) async -> WebServerMessage {
        do {
            var allProviders: [JSONValue] = []
            for appType in ProviderAppType.allCases {
                let providers = try await providerCoordinator.listProviders(for: appType)
                for provider in providers {
                    let apiKey: JSONValue
                    if let k = provider.claudeConfig?.apiKey { apiKey = .string(Self.maskSecret(k)) }
                    else if let k = provider.codexConfig?.apiKey { apiKey = .string(Self.maskSecret(k)) }
                    else if let k = provider.geminiConfig?.apiKey { apiKey = .string(Self.maskSecret(k)) }
                    else { apiKey = .null }

                    let baseUrl: JSONValue
                    if let u = provider.claudeConfig?.baseUrl { baseUrl = .string(u) }
                    else if let u = provider.codexConfig?.baseUrl { baseUrl = .string(u) }
                    else if let u = provider.geminiConfig?.baseUrl { baseUrl = .string(u) }
                    else { baseUrl = .null }

                    let model: JSONValue
                    if let m = provider.claudeConfig?.model { model = .string(m) }
                    else if let m = provider.codexConfig?.model { model = .string(m) }
                    else if let m = provider.geminiConfig?.model { model = .string(m) }
                    else { model = .null }

                    let dict: [String: JSONValue] = [
                        "id": .string(provider.id),
                        "name": .string(provider.name),
                        "appType": .string(provider.appType.rawValue),
                        "isCurrent": .bool(provider.isCurrent),
                        "apiKey": apiKey,
                        "baseUrl": baseUrl,
                        "model": model,
                        "category": .string(provider.category.rawValue),
                        "isPreset": .bool(provider.isPreset)
                    ]
                    allProviders.append(JSONValue.object(dict))
                }
            }
            let result: [String: JSONValue] = [
                "providers": .array(allProviders),
                "count": .number(Double(allProviders.count))
            ]
            return .snapshot(type: .providerList, payload: .object(result), requestID: message.requestID)
        } catch {
            return .error(error.localizedDescription, requestID: message.requestID)
        }
    }

    private func handleProviderCRUD(_ message: WebClientMessage) async -> WebServerMessage {
        do {
            switch message.type {
            case .switchProvider:
                guard let id = message.providerID,
                      let appStr = message.providerAppType,
                      let appType = ProviderAppType(rawValue: appStr) else {
                    return .error("providerID and providerAppType required", requestID: message.requestID)
                }
                _ = try await providerCoordinator.switchProvider(id: id, appType: appType)
                return .snapshot(type: .providerSaved, payload: .object(["switched": .string(id)]), requestID: message.requestID)

            case .addProvider:
                guard let name = message.providerName,
                      let appStr = message.providerAppType,
                      let appType = ProviderAppType(rawValue: appStr) else {
                    return .error("providerName and providerAppType required", requestID: message.requestID)
                }
                let now = Int64(Date().timeIntervalSince1970)
                let apiKey = message.providerApiKey ?? ""
                var provider = Provider(
                    id: UUID().uuidString,
                    name: name,
                    appType: appType,
                    category: .custom,
                    isPreset: false,
                    sortIndex: 999,
                    createdAt: now,
                    updatedAt: now,
                    isCurrent: false
                )
                switch appType {
                case .claude:
                    var config = ClaudeSettingsConfig(apiKey: apiKey)
                    config.baseUrl = message.providerBaseUrl
                    config.model = message.providerModel
                    provider.claudeConfig = config
                case .codex:
                    var config = CodexSettingsConfig(apiKey: apiKey)
                    config.baseUrl = message.providerBaseUrl
                    config.model = message.providerModel
                    provider.codexConfig = config
                case .gemini:
                    var config = GeminiSettingsConfig(apiKey: apiKey)
                    config.baseUrl = message.providerBaseUrl
                    config.model = message.providerModel
                    provider.geminiConfig = config
                }
                _ = try await providerCoordinator.addProvider(provider)
                return .snapshot(type: .providerSaved, payload: .object(["added": .string(provider.id)] as [String: JSONValue]), requestID: message.requestID)

            case .updateProvider:
                guard let id = message.providerID else {
                    return .error("providerID required", requestID: message.requestID)
                }
                guard let appStr = message.providerAppType,
                      let appType = ProviderAppType(rawValue: appStr) else {
                    return .error("providerAppType required", requestID: message.requestID)
                }
                let providers = try await providerCoordinator.listProviders(for: appType)
                guard var provider = providers.first(where: { $0.id == id }) else {
                    return .error("Provider not found", requestID: message.requestID)
                }
                if let name = message.providerName { provider.name = name }
                // Update config based on app type — only update apiKey if explicitly provided
                let newApiKey = message.providerApiKey
                switch appType {
                case .claude:
                    if provider.claudeConfig == nil { provider.claudeConfig = ClaudeSettingsConfig(apiKey: "") }
                    if let k = newApiKey, !k.isEmpty { provider.claudeConfig?.apiKey = k }
                    if let u = message.providerBaseUrl { provider.claudeConfig?.baseUrl = u }
                    if let m = message.providerModel { provider.claudeConfig?.model = m }
                case .codex:
                    if provider.codexConfig == nil { provider.codexConfig = CodexSettingsConfig(apiKey: "") }
                    if let k = newApiKey, !k.isEmpty { provider.codexConfig?.apiKey = k }
                    if let u = message.providerBaseUrl { provider.codexConfig?.baseUrl = u }
                    if let m = message.providerModel { provider.codexConfig?.model = m }
                case .gemini:
                    if provider.geminiConfig == nil { provider.geminiConfig = GeminiSettingsConfig(apiKey: "") }
                    if let k = newApiKey, !k.isEmpty { provider.geminiConfig?.apiKey = k }
                    if let u = message.providerBaseUrl { provider.geminiConfig?.baseUrl = u }
                    if let m = message.providerModel { provider.geminiConfig?.model = m }
                }
                _ = try await providerCoordinator.updateProvider(provider)
                return .snapshot(type: .providerSaved, payload: .object(["updated": .string(id)]), requestID: message.requestID)

            case .deleteProvider:
                guard let id = message.providerID,
                      let appStr = message.providerAppType,
                      let appType = ProviderAppType(rawValue: appStr) else {
                    return .error("providerID and providerAppType required", requestID: message.requestID)
                }
                _ = try await providerCoordinator.deleteProvider(id: id, appType: appType)
                return .snapshot(type: .providerDeleted, payload: .object(["deleted": .string(id)]), requestID: message.requestID)

            default:
                return .error("Unknown provider operation", requestID: message.requestID)
            }
        } catch {
            return .error(error.localizedDescription, requestID: message.requestID)
        }
    }

    // MARK: - Token Handler

    private func handleSetToken(_ message: WebClientMessage) async -> WebServerMessage {
        guard let newToken = message.token, !newToken.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty else {
            return .error("token required", requestID: message.requestID)
        }
        let applied = await authService.setCustomToken(newToken)
        // Invalidate all existing authenticated sessions — they hold the old token
        await sessionManager?.revokeAllAuthenticated()
        return .snapshot(type: .tokenUpdated, payload: .object(["token": .string(applied)]), requestID: message.requestID)
    }

    // MARK: - Directory History

    private static let directoryHistoryKey = "WebRemoteDirectoryHistory"
    private static let maxDirectoryHistory = 15

    private func handleListDirectories(_ message: WebClientMessage) -> WebServerMessage {
        // If cwd is provided, list subdirectories of that path
        let basePath = message.cwd ?? NSHomeDirectory()
        let baseURL = URL(fileURLWithPath: basePath)

        var dirs: [String] = []

        // List subdirectories of the base path
        if let contents = try? FileManager.default.contentsOfDirectory(
            at: baseURL,
            includingPropertiesForKeys: [.isDirectoryKey],
            options: [.skipsHiddenFiles]
        ) {
            for item in contents {
                if let isDir = try? item.resourceValues(forKeys: [.isDirectoryKey]).isDirectory, isDir {
                    dirs.append(item.path)
                }
            }
            dirs.sort()
        }

        // Add history entries
        let history = UserDefaults.standard.stringArray(forKey: Self.directoryHistoryKey) ?? []
        for h in history {
            if !dirs.contains(h) { dirs.append(h) }
        }

        // Add common defaults if empty
        if dirs.isEmpty {
            dirs = [NSHomeDirectory(), NSHomeDirectory() + "/Documents", NSHomeDirectory() + "/Desktop"]
        }

        let parentPath = baseURL.deletingLastPathComponent().path
        let items: [JSONValue] = dirs.map { .string($0) }
        let result: [String: JSONValue] = [
            "directories": .array(items),
            "currentPath": .string(basePath),
            "parentPath": .string(parentPath)
        ]
        return .snapshot(type: .directoryList, payload: .object(result), requestID: message.requestID)
    }

    static func addDirectoryToHistory(_ dir: String) {
        var dirs = UserDefaults.standard.stringArray(forKey: directoryHistoryKey) ?? []
        dirs.removeAll { $0 == dir }
        dirs.insert(dir, at: 0)
        if dirs.count > maxDirectoryHistory {
            dirs = Array(dirs.prefix(maxDirectoryHistory))
        }
        UserDefaults.standard.set(dirs, forKey: directoryHistoryKey)
    }

    // MARK: - Slash Commands

    private func handleSlashCommands(_ message: WebClientMessage) async -> WebServerMessage {
        var commands: [[String: JSONValue]] = []

        // Claude built-in commands
        let claudeCommands: [(String, String)] = [
            ("/compact", "Compress conversation context to save tokens"),
            ("/clear", "Clear conversation history"),
            ("/cost", "Show token usage and cost"),
            ("/model", "Switch model (opus, sonnet, haiku)"),
            ("/help", "Show available commands"),
            ("/init", "Initialize project with CLAUDE.md"),
            ("/review", "Review recent changes"),
            ("/vim", "Toggle vim keybindings"),
            ("/terminal-setup", "Configure terminal integration"),
            ("/memory", "View and manage memory files"),
            ("/forget", "Remove a memory entry"),
            ("/permissions", "Manage tool permissions"),
            ("/config", "View and modify configuration"),
            ("/doctor", "Diagnose common issues"),
            ("/login", "Authenticate with Anthropic"),
            ("/logout", "Log out of Anthropic"),
            ("/status", "Show session status"),
            ("/resume", "Resume a previous conversation"),
            ("/listen", "Listen to audio input"),
            ("/bug", "Report a bug"),
        ]

        for (cmd, desc) in claudeCommands {
            commands.append([
                "command": .string(cmd),
                "description": .string(desc),
                "agent": .string("claude")
            ])
        }

        // Codex built-in commands
        let codexCommands: [(String, String)] = [
            ("/compact", "Compress conversation context"),
            ("/clear", "Clear conversation"),
            ("/model", "Switch model"),
            ("/help", "Show help"),
            ("/undo", "Undo last action"),
        ]

        for (cmd, desc) in codexCommands {
            commands.append([
                "command": .string(cmd),
                "description": .string(desc),
                "agent": .string("codex")
            ])
        }

        // Try to list installed skills as slash commands
        if let skillCoord = skillCoordinator {
            do {
                let skills = try await skillCoord.listInstalledSkills()
                for skill in skills {
                    commands.append([
                        "command": .string("/\(skill.name)"),
                        "description": .string("Skill: \(skill.name)"),
                        "agent": .string("claude")
                    ])
                }
            } catch {
                // Silently skip if skills can't be loaded
            }
        }

        let items: [JSONValue] = commands.map { .object($0) }
        return .snapshot(type: .slashCommands, payload: .object(["commands": .array(items)]), requestID: message.requestID)
    }

    // MARK: - Helpers

    private static func maskSecret(_ value: String) -> String {
        guard value.count > 6 else { return String(repeating: "*", count: value.count) }
        let prefix = String(value.prefix(3))
        let suffix = String(value.suffix(4))
        return "\(prefix)...\(suffix)"
    }
}

// MARK: - WebSocket Bridge (delegate adapter)

/// Bridges WebSocketServerDelegate callbacks to the async WebSessionManager actor.
/// Must be a class (reference semantics) for the weak delegate pattern.
final class WebSocketBridge: WebSocketServerDelegate, @unchecked Sendable {
    private let sessionManager: WebSessionManager
    private let wsServer: WebSocketServer

    init(sessionManager: WebSessionManager, wsServer: WebSocketServer) {
        self.sessionManager = sessionManager
        self.wsServer = wsServer
    }

    func webSocketDidAcceptConnection(id: String, remoteAddress: String) {
        NSLog("[WebSocketBridge] new connection: \(id) from \(remoteAddress)")
        Task {
            await sessionManager.handleConnect(id: id, remoteAddress: remoteAddress)
        }
    }

    func webSocketDidReceiveMessage(data: Data, from connectionID: String) {
        NSLog("[WebSocketBridge] message from \(connectionID): \(data.count) bytes")
        Task {
            if let responseData = await sessionManager.handleMessage(data: data, from: connectionID) {
                NSLog("[WebSocketBridge] sending response to \(connectionID): \(responseData.count) bytes")
                wsServer.send(data: responseData, to: connectionID)
            }
        }
    }

    func webSocketDidCloseConnection(id: String) {
        NSLog("[WebSocketBridge] connection closed: \(id)")
        Task {
            await sessionManager.handleDisconnect(id: id)
        }
    }
}
