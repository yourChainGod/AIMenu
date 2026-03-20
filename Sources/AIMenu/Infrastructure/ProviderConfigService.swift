import Foundation

actor ProviderConfigService {
    private let fileManager: FileManager
    private let homeDirectory: URL

    init(fileManager: FileManager = .default, homeDirectory: URL? = nil) {
        self.fileManager = fileManager
        self.homeDirectory = homeDirectory ?? fileManager.homeDirectoryForCurrentUser
    }

    // MARK: - Provider Store Persistence

    private var appSupportDirectory: URL {
        let baseDirectory = homeDirectory.appendingPathComponent("Library/Application Support", isDirectory: true)
        let current = baseDirectory.appendingPathComponent(FileSystemPaths.appSupportDirectoryName, isDirectory: true)
        let legacy = baseDirectory.appendingPathComponent(FileSystemPaths.legacyAppSupportDirectoryName, isDirectory: true)

        if fileManager.fileExists(atPath: legacy.path), !fileManager.fileExists(atPath: current.path) {
            try? fileManager.moveItem(at: legacy, to: current)
        }

        if fileManager.fileExists(atPath: current.path) {
            return current
        }

        if fileManager.fileExists(atPath: legacy.path) {
            return legacy
        }

        return current
    }

    private var providerStorePath: URL {
        appSupportDirectory.appendingPathComponent("providers.json")
    }

    func loadProviderStore() throws -> ProviderStore {
        let path = providerStorePath
        guard fileManager.fileExists(atPath: path.path) else {
            return ProviderStore()
        }
        let data = try Data(contentsOf: path)
        return try JSONDecoder().decode(ProviderStore.self, from: data)
    }

    func saveProviderStore(_ store: ProviderStore) throws {
        let path = providerStorePath
        let parent = path.deletingLastPathComponent()
        try fileManager.createDirectory(at: parent, withIntermediateDirectories: true)
        let data = try JSONEncoder.pretty.encode(store)
        try data.write(to: path, options: .atomic)
    }

    // MARK: - Switch Provider (Write to Live Config)

    func switchProvider(_ provider: Provider) throws {
        switch provider.appType {
        case .claude:
            guard let config = provider.claudeConfig else { return }
            try writeClaudeConfig(config)
        case .codex:
            guard let config = provider.codexConfig else { return }
            try writeCodexConfig(config)
        case .gemini:
            guard let config = provider.geminiConfig else { return }
            try writeGeminiConfig(config)
        }
    }

    func clearProvider(for appType: ProviderAppType) throws {
        switch appType {
        case .claude:
            try clearClaudeConfig()
        case .codex:
            try clearCodexConfig()
        case .gemini:
            try clearGeminiConfig()
        }
    }

    // MARK: - Claude Code Config

    private var claudeSettingsPath: URL {
        homeDirectory.appendingPathComponent(".claude/settings.json")
    }

    private var claudeSkillsDirectory: URL {
        homeDirectory.appendingPathComponent(".claude/skills", isDirectory: true)
    }

    private func writeClaudeConfig(_ config: ClaudeSettingsConfig) throws {
        let settingsPath = claudeSettingsPath
        try fileManager.createDirectory(at: settingsPath.deletingLastPathComponent(), withIntermediateDirectories: true)

        var settings = loadJSONObject(from: settingsPath)
        if config.applyCommonConfig == true,
           let commonConfigJSON = config.commonConfigJSON?.trimmedNonEmpty {
            let commonObject = try parseJSONObjectString(commonConfigJSON)
            settings = mergingJSONObject(settings, with: commonObject)
        }
        var env = (settings["env"] as? [String: Any]) ?? [:]

        let claudeKeys = [
            ClaudeApiKeyField.authToken.rawValue,
            ClaudeApiKeyField.apiKey.rawValue,
            "ANTHROPIC_BASE_URL",
            "ANTHROPIC_MODEL",
            "ANTHROPIC_DEFAULT_HAIKU_MODEL",
            "ANTHROPIC_DEFAULT_SONNET_MODEL",
            "ANTHROPIC_DEFAULT_OPUS_MODEL",
            "CLAUDE_CODE_MAX_OUTPUT_TOKENS",
            "API_TIMEOUT_MS",
            "CLAUDE_CODE_DISABLE_NONESSENTIAL_TRAFFIC",
            "CLAUDE_CODE_EXPERIMENTAL_AGENT_TEAMS",
            "AWS_REGION",
            "AWS_ACCESS_KEY_ID",
            "AWS_SECRET_ACCESS_KEY"
        ]
        claudeKeys.forEach { env.removeValue(forKey: $0) }

        let keyField = config.apiKeyField ?? .authToken
        setJSONValue(&env, key: keyField.rawValue, value: config.apiKey.trimmedNonEmpty)
        setJSONValue(&env, key: "ANTHROPIC_BASE_URL", value: config.baseUrl?.trimmedNonEmpty)
        setJSONValue(&env, key: "ANTHROPIC_MODEL", value: config.model?.trimmedNonEmpty)
        setJSONValue(&env, key: "ANTHROPIC_DEFAULT_HAIKU_MODEL", value: config.haikuModel?.trimmedNonEmpty)
        setJSONValue(&env, key: "ANTHROPIC_DEFAULT_SONNET_MODEL", value: config.sonnetModel?.trimmedNonEmpty)
        setJSONValue(&env, key: "ANTHROPIC_DEFAULT_OPUS_MODEL", value: config.opusModel?.trimmedNonEmpty)
        setJSONValue(&env, key: "CLAUDE_CODE_MAX_OUTPUT_TOKENS", value: config.maxOutputTokens.map(String.init))
        setJSONValue(&env, key: "API_TIMEOUT_MS", value: config.apiTimeoutMs.map(String.init))
        setJSONValue(
            &env,
            key: "CLAUDE_CODE_DISABLE_NONESSENTIAL_TRAFFIC",
            value: config.disableNonessentialTraffic == true ? "1" : nil
        )
        setJSONValue(
            &env,
            key: "CLAUDE_CODE_EXPERIMENTAL_AGENT_TEAMS",
            value: config.enableTeammates == true ? "1" : nil
        )
        setJSONValue(&env, key: "AWS_REGION", value: config.awsRegion?.trimmedNonEmpty)
        setJSONValue(&env, key: "AWS_ACCESS_KEY_ID", value: config.awsAccessKeyId?.trimmedNonEmpty)
        setJSONValue(&env, key: "AWS_SECRET_ACCESS_KEY", value: config.awsSecretAccessKey?.trimmedNonEmpty)

        if config.hideAttribution == true {
            settings["attribution"] = ["commit": "", "pr": ""]
        } else {
            settings.removeValue(forKey: "attribution")
        }

        if config.alwaysThinkingEnabled == true {
            settings["alwaysThinkingEnabled"] = true
        } else {
            settings.removeValue(forKey: "alwaysThinkingEnabled")
        }

        settings["env"] = env
        try writeJSONObject(settings, to: settingsPath)
    }

    private func clearClaudeConfig() throws {
        let settingsPath = claudeSettingsPath
        guard fileManager.fileExists(atPath: settingsPath.path) else { return }
        var settings = loadJSONObject(from: settingsPath)
        var env = (settings["env"] as? [String: Any]) ?? [:]
        [
            ClaudeApiKeyField.authToken.rawValue,
            ClaudeApiKeyField.apiKey.rawValue,
            "ANTHROPIC_BASE_URL",
            "ANTHROPIC_MODEL",
            "ANTHROPIC_DEFAULT_HAIKU_MODEL",
            "ANTHROPIC_DEFAULT_SONNET_MODEL",
            "ANTHROPIC_DEFAULT_OPUS_MODEL",
            "CLAUDE_CODE_MAX_OUTPUT_TOKENS",
            "API_TIMEOUT_MS",
            "CLAUDE_CODE_DISABLE_NONESSENTIAL_TRAFFIC",
            "CLAUDE_CODE_EXPERIMENTAL_AGENT_TEAMS",
            "AWS_REGION",
            "AWS_ACCESS_KEY_ID",
            "AWS_SECRET_ACCESS_KEY"
        ].forEach { env.removeValue(forKey: $0) }
        settings.removeValue(forKey: "attribution")
        settings.removeValue(forKey: "alwaysThinkingEnabled")
        settings["env"] = env
        try writeJSONObject(settings, to: settingsPath)
    }

    // MARK: - Codex Config

    private var codexAuthPath: URL {
        homeDirectory.appendingPathComponent(".codex/auth.json")
    }

    private var codexConfigPath: URL {
        homeDirectory.appendingPathComponent(".codex/config.toml")
    }

    private var codexHooksPath: URL {
        homeDirectory.appendingPathComponent(".codex/hooks.json")
    }

    private var codexSkillsDirectory: URL {
        homeDirectory.appendingPathComponent(".codex/skills", isDirectory: true)
    }

    func writeCodexConfig(_ config: CodexSettingsConfig) throws {
        let authPath = codexAuthPath
        try fileManager.createDirectory(at: authPath.deletingLastPathComponent(), withIntermediateDirectories: true)

        var auth = loadJSONObject(from: authPath)
        setJSONValue(&auth, key: "OPENAI_API_KEY", value: config.apiKey.trimmedNonEmpty)
        setJSONValue(&auth, key: "OPENAI_BASE_URL", value: config.baseUrl?.trimmedNonEmpty)
        try writeJSONObject(auth, to: authPath)
        #if canImport(Darwin)
        _ = chmod(authPath.path, S_IRUSR | S_IWUSR)
        #endif

        let updatedConfig = updateCodexRootConfig(
            values: [
                "model": config.model?.trimmedNonEmpty,
                "wire_api": config.wireApi?.trimmedNonEmpty,
                "base_url": config.baseUrl?.trimmedNonEmpty,
                "reasoning_effort": config.reasoningEffort?.trimmedNonEmpty
            ]
        )
        try writeTOML(updatedConfig, to: codexConfigPath)
    }

    private func clearCodexConfig() throws {
        guard fileManager.fileExists(atPath: codexAuthPath.path) || fileManager.fileExists(atPath: codexConfigPath.path) else {
            return
        }

        if fileManager.fileExists(atPath: codexAuthPath.path) {
            var auth = loadJSONObject(from: codexAuthPath)
            auth.removeValue(forKey: "OPENAI_API_KEY")
            auth.removeValue(forKey: "OPENAI_BASE_URL")
            try writeJSONObject(auth, to: codexAuthPath)
            #if canImport(Darwin)
            _ = chmod(codexAuthPath.path, S_IRUSR | S_IWUSR)
            #endif
        }

        let updatedConfig = updateCodexRootConfig(
            values: [
                "model": nil,
                "wire_api": nil,
                "base_url": nil,
                "reasoning_effort": nil
            ]
        )
        try writeTOML(updatedConfig, to: codexConfigPath)
    }

    // MARK: - Gemini Config

    private var geminiEnvPath: URL {
        homeDirectory.appendingPathComponent(".gemini/.env")
    }

    private var geminiSettingsPath: URL {
        homeDirectory.appendingPathComponent(".gemini/settings.json")
    }

    private var geminiSkillsDirectory: URL {
        homeDirectory.appendingPathComponent(".gemini/skills", isDirectory: true)
    }

    func writeGeminiConfig(_ config: GeminiSettingsConfig) throws {
        let envPath = geminiEnvPath
        try fileManager.createDirectory(at: envPath.deletingLastPathComponent(), withIntermediateDirectories: true)

        let updatedContent = updateDotEnv(
            at: envPath,
            assignments: [
                "GEMINI_API_KEY": config.apiKey.trimmedNonEmpty,
                "GOOGLE_GEMINI_BASE_URL": config.baseUrl?.trimmedNonEmpty,
                "GEMINI_MODEL": config.model?.trimmedNonEmpty
            ]
        )
        try writeEnvFile(updatedContent, to: envPath)
    }

    private func clearGeminiConfig() throws {
        let envPath = geminiEnvPath
        guard fileManager.fileExists(atPath: envPath.path) else { return }
        let updatedContent = updateDotEnv(
            at: envPath,
            assignments: [
                "GEMINI_API_KEY": nil,
                "GOOGLE_GEMINI_BASE_URL": nil,
                "GEMINI_MODEL": nil
            ]
        )
        try writeEnvFile(updatedContent, to: envPath)
    }

    // MARK: - Speed Test

    func testEndpointLatency(baseUrl: String, apiKey: String, appType: ProviderAppType) async -> Int? {
        let testUrl: String
        switch appType {
        case .claude:
            // Use a lightweight endpoint
            let base = baseUrl.isEmpty ? "https://api.anthropic.com" : baseUrl
            testUrl = "\(base.trimmingCharacters(in: CharacterSet(charactersIn: "/")))/v1/models"
        case .codex:
            let base = baseUrl.isEmpty ? "https://api.openai.com" : baseUrl
            testUrl = "\(base.trimmingCharacters(in: CharacterSet(charactersIn: "/")))/v1/models"
        case .gemini:
            let base = baseUrl.isEmpty ? "https://generativelanguage.googleapis.com" : baseUrl
            testUrl = "\(base.trimmingCharacters(in: CharacterSet(charactersIn: "/")))/v1beta/models"
        }

        guard let url = URL(string: testUrl) else { return nil }

        var request = URLRequest(url: url)
        request.httpMethod = "GET"
        request.timeoutInterval = 10

        switch appType {
        case .claude:
            request.setValue("Bearer \(apiKey)", forHTTPHeaderField: "Authorization")
            request.setValue("2023-06-01", forHTTPHeaderField: "anthropic-version")
            request.setValue(apiKey, forHTTPHeaderField: "x-api-key")
        case .codex:
            request.setValue("Bearer \(apiKey)", forHTTPHeaderField: "Authorization")
        case .gemini:
            // API key as query parameter for Gemini
            if var components = URLComponents(url: url, resolvingAgainstBaseURL: false) {
                var items = components.queryItems ?? []
                items.append(URLQueryItem(name: "key", value: apiKey))
                components.queryItems = items
                if let newUrl = components.url {
                    request.url = newUrl
                }
            }
        }

        let start = DispatchTime.now()
        do {
            let (_, response) = try await URLSession.shared.data(for: request)
            let end = DispatchTime.now()
            let elapsed = end.uptimeNanoseconds - start.uptimeNanoseconds
            let ms = Int(elapsed / 1_000_000)

            if let httpResponse = response as? HTTPURLResponse,
               (200..<500).contains(httpResponse.statusCode) {
                return ms
            }
            return nil
        } catch {
            return nil
        }
    }

    // MARK: - MCP Store Persistence

    private var mcpStorePath: URL {
        appSupportDirectory.appendingPathComponent("mcp_servers.json")
    }

    func loadMCPStore() throws -> MCPStore {
        let path = mcpStorePath
        guard fileManager.fileExists(atPath: path.path) else {
            return MCPStore()
        }
        let data = try Data(contentsOf: path)
        return try JSONDecoder().decode(MCPStore.self, from: data)
    }

    func saveMCPStore(_ store: MCPStore) throws {
        let path = mcpStorePath
        let parent = path.deletingLastPathComponent()
        try fileManager.createDirectory(at: parent, withIntermediateDirectories: true)
        let data = try JSONEncoder.pretty.encode(store)
        try data.write(to: path, options: .atomic)
    }

    func importLiveMCPServers() throws -> [MCPServer] {
        var merged: [String: MCPServer] = [:]
        let now = Int64(Date().timeIntervalSince1970)

        try importJSONMCPServers(
            from: homeDirectory.appendingPathComponent(".claude.json"),
            app: .claude,
            now: now,
            into: &merged
        )
        try importCodexMCPServers(now: now, into: &merged)
        try importJSONMCPServers(
            from: homeDirectory.appendingPathComponent(".gemini/settings.json"),
            app: .gemini,
            now: now,
            into: &merged
        )

        return merged.values.sorted { $0.name.localizedCaseInsensitiveCompare($1.name) == .orderedAscending }
    }

    // MARK: - MCP Sync to Live Configs

    func syncMCPServer(_ server: MCPServer) throws {
        if server.apps.claude { try syncMCPToClaude(server) }
        if server.apps.codex { try syncMCPToCodex(server) }
        if server.apps.gemini { try syncMCPToGemini(server) }
    }

    func removeMCPServer(_ server: MCPServer) throws {
        if server.apps.claude { try removeMCPFromClaude(server.id) }
        if server.apps.codex { try removeMCPFromCodex(server.id) }
        if server.apps.gemini { try removeMCPFromGemini(server.id) }
    }

    private func importJSONMCPServers(
        from path: URL,
        app: ProviderAppType,
        now: Int64,
        into merged: inout [String: MCPServer]
    ) throws {
        let json = loadJSONObject(from: path)
        guard let mcpServers = json["mcpServers"] as? [String: Any] else { return }

        for (id, value) in mcpServers {
            guard let dictionary = value as? [String: Any],
                  let spec = parseMCPDictionary(dictionary) else { continue }
            mergeImportedServer(
                id: id,
                name: prettifiedImportedName(from: id),
                spec: spec,
                app: app,
                now: now,
                into: &merged
            )
        }
    }

    private func importCodexMCPServers(now: Int64, into merged: inout [String: MCPServer]) throws {
        let content = readTOML(at: codexConfigPath)
        guard !content.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty else { return }

        for (id, spec) in parseCodexMCPServers(from: content) {
            mergeImportedServer(
                id: id,
                name: prettifiedImportedName(from: id),
                spec: spec,
                app: .codex,
                now: now,
                into: &merged
            )
        }
    }

    private func mergeImportedServer(
        id: String,
        name: String,
        spec: MCPServerSpec,
        app: ProviderAppType,
        now: Int64,
        into merged: inout [String: MCPServer]
    ) {
        if var existing = merged[id] {
            existing.server = spec
            existing.updatedAt = now
            switch app {
            case .claude: existing.apps.claude = true
            case .codex: existing.apps.codex = true
            case .gemini: existing.apps.gemini = true
            }
            merged[id] = existing
            return
        }

        var apps = MCPAppToggles(claude: false, codex: false, gemini: false)
        switch app {
        case .claude: apps.claude = true
        case .codex: apps.codex = true
        case .gemini: apps.gemini = true
        }

        merged[id] = MCPServer(
            id: id,
            name: name,
            server: spec,
            apps: apps,
            description: nil,
            tags: nil,
            homepage: nil,
            createdAt: now,
            updatedAt: now,
            isEnabled: true
        )
    }

    private func parseMCPDictionary(_ value: [String: Any]) -> MCPServerSpec? {
        let type = (value["type"] as? String).flatMap(MCPTransportType.init(rawValue:))
            ?? ((value["url"] as? String) != nil ? .http : .stdio)

        let args = (value["args"] as? [Any])?.compactMap { item -> String? in
            if let string = item as? String {
                return string
            }
            return nil
        }

        let env = (value["env"] as? [String: Any])?.reduce(into: [String: String]()) { partialResult, item in
            if let string = item.value as? String {
                partialResult[item.key] = string
            }
        }

        let headers = (value["headers"] as? [String: Any])?.reduce(into: [String: String]()) { partialResult, item in
            if let string = item.value as? String {
                partialResult[item.key] = string
            }
        }

        return MCPServerSpec(
            type: type,
            command: value["command"] as? String,
            args: args,
            env: env,
            cwd: value["cwd"] as? String,
            url: value["url"] as? String,
            headers: headers
        )
    }

    private func parseCodexMCPServers(from content: String) -> [String: MCPServerSpec] {
        let lines = content.normalizedNewlines.components(separatedBy: "\n")
        var result: [String: MCPServerSpec] = [:]
        var currentID: String?
        var currentLines: [String] = []

        func flushCurrentSection() {
            guard let currentID,
                  let spec = parseCodexMCPSection(currentLines) else { return }
            result[currentID] = spec
        }

        for line in lines {
            let trimmed = line.trimmingCharacters(in: .whitespacesAndNewlines)
            if trimmed.hasPrefix("[mcp_servers."), trimmed.hasSuffix("]") {
                flushCurrentSection()
                currentID = String(trimmed.dropFirst("[mcp_servers.".count).dropLast())
                currentLines = []
                continue
            }

            if trimmed.hasPrefix("[") {
                flushCurrentSection()
                currentID = nil
                currentLines = []
                continue
            }

            if currentID != nil {
                currentLines.append(line)
            }
        }

        flushCurrentSection()
        return result
    }

    private func parseCodexMCPSection(_ lines: [String]) -> MCPServerSpec? {
        var type: MCPTransportType = .stdio
        var command: String?
        var args: [String]?
        var env: [String: String]?
        var cwd: String?
        var url: String?
        var headers: [String: String]?

        for rawLine in lines {
            let line = rawLine.trimmingCharacters(in: .whitespacesAndNewlines)
            guard !line.isEmpty,
                  !line.hasPrefix("#"),
                  let assignment = splitTomlAssignment(line) else { continue }

            switch assignment.key {
            case "type":
                type = MCPTransportType(rawValue: parseTomlStringScalar(assignment.value)) ?? type
            case "command":
                command = parseTomlStringScalar(assignment.value)
            case "args":
                args = parseTomlStringArray(assignment.value)
            case "env":
                env = parseTomlInlineTable(assignment.value)
            case "cwd":
                cwd = parseTomlStringScalar(assignment.value)
            case "url":
                url = parseTomlStringScalar(assignment.value)
            case "headers":
                headers = parseTomlInlineTable(assignment.value)
            default:
                continue
            }
        }

        return MCPServerSpec(
            type: type,
            command: command,
            args: args,
            env: env,
            cwd: cwd,
            url: url,
            headers: headers
        )
    }

    private func splitTomlAssignment(_ line: String) -> (key: String, value: String)? {
        guard let equalsIndex = line.firstIndex(of: "=") else { return nil }
        let key = line[..<equalsIndex].trimmingCharacters(in: .whitespacesAndNewlines)
        let value = line[line.index(after: equalsIndex)...].trimmingCharacters(in: .whitespacesAndNewlines)
        guard !key.isEmpty else { return nil }
        return (key, value)
    }

    private func parseTomlStringScalar(_ rawValue: String) -> String {
        let trimmed = rawValue.trimmingCharacters(in: .whitespacesAndNewlines)
        guard trimmed.hasPrefix("\""), trimmed.hasSuffix("\""), trimmed.count >= 2 else {
            return trimmed
        }

        let inner = String(trimmed.dropFirst().dropLast())
        return inner
            .replacingOccurrences(of: "\\\"", with: "\"")
            .replacingOccurrences(of: "\\\\", with: "\\")
    }

    private func parseTomlStringArray(_ rawValue: String) -> [String]? {
        matches(
            in: rawValue,
            pattern: #""((?:\\.|[^"])*)""#
        ).map {
            $0
                .replacingOccurrences(of: "\\\"", with: "\"")
                .replacingOccurrences(of: "\\\\", with: "\\")
        }
    }

    private func parseTomlInlineTable(_ rawValue: String) -> [String: String]? {
        let matches = regexMatches(
            in: rawValue,
            pattern: #""((?:\\.|[^"])*)"\s*=\s*"((?:\\.|[^"])*)""#
        )

        guard !matches.isEmpty else { return nil }

        var result: [String: String] = [:]
        for match in matches where match.count == 3 {
            let key = match[1]
                .replacingOccurrences(of: "\\\"", with: "\"")
                .replacingOccurrences(of: "\\\\", with: "\\")
            let value = match[2]
                .replacingOccurrences(of: "\\\"", with: "\"")
                .replacingOccurrences(of: "\\\\", with: "\\")
            result[key] = value
        }
        return result.isEmpty ? nil : result
    }

    private func matches(in rawValue: String, pattern: String) -> [String] {
        regexMatches(in: rawValue, pattern: pattern).compactMap { match in
            guard match.count > 1 else { return nil }
            return match[1]
        }
    }

    private func regexMatches(in rawValue: String, pattern: String) -> [[String]] {
        guard let regex = try? NSRegularExpression(pattern: pattern) else { return [] }
        let range = NSRange(rawValue.startIndex..<rawValue.endIndex, in: rawValue)
        return regex.matches(in: rawValue, range: range).map { match in
            (0..<match.numberOfRanges).compactMap { index in
                let range = match.range(at: index)
                guard let swiftRange = Range(range, in: rawValue) else { return nil }
                return String(rawValue[swiftRange])
            }
        }
    }

    private func prettifiedImportedName(from id: String) -> String {
        id
            .replacingOccurrences(of: "-", with: " ")
            .replacingOccurrences(of: "_", with: " ")
            .split(separator: " ")
            .map { component in
                guard let first = component.first else { return "" }
                return String(first).uppercased() + String(component.dropFirst())
            }
            .joined(separator: " ")
    }

    private func syncMCPToClaude(_ server: MCPServer) throws {
        let configPath = homeDirectory.appendingPathComponent(".claude.json")
        var config = loadJSONObject(from: configPath)

        var mcpServers = (config["mcpServers"] as? [String: Any]) ?? [:]
        mcpServers[server.id] = buildMCPDict(server.server)
        config["mcpServers"] = mcpServers

        try writeJSONObject(config, to: configPath)
    }

    private func removeMCPFromClaude(_ id: String) throws {
        let configPath = homeDirectory.appendingPathComponent(".claude.json")
        guard fileManager.fileExists(atPath: configPath.path) else { return }
        var config = loadJSONObject(from: configPath)

        var mcpServers = (config["mcpServers"] as? [String: Any]) ?? [:]
        mcpServers.removeValue(forKey: id)
        config["mcpServers"] = mcpServers

        try writeJSONObject(config, to: configPath)
    }

    private func syncMCPToCodex(_ server: MCPServer) throws {
        let content = readTOML(at: codexConfigPath)
        let updatedContent = replacingCodexMCPSection(
            in: content,
            serverID: server.id,
            spec: server.server
        )
        try writeTOML(updatedContent, to: codexConfigPath)
    }

    private func removeMCPFromCodex(_ id: String) throws {
        let content = readTOML(at: codexConfigPath)
        let updatedContent = removingCodexMCPSection(in: content, serverID: id)
        try writeTOML(updatedContent, to: codexConfigPath)
    }

    private func syncMCPToGemini(_ server: MCPServer) throws {
        let configPath = homeDirectory.appendingPathComponent(".gemini/settings.json")
        let parent = configPath.deletingLastPathComponent()
        try fileManager.createDirectory(at: parent, withIntermediateDirectories: true)

        var config = loadJSONObject(from: configPath)

        var mcpServers = (config["mcpServers"] as? [String: Any]) ?? [:]
        mcpServers[server.id] = buildMCPDict(server.server)
        config["mcpServers"] = mcpServers

        try writeJSONObject(config, to: configPath)
    }

    private func removeMCPFromGemini(_ id: String) throws {
        let configPath = homeDirectory.appendingPathComponent(".gemini/settings.json")
        guard fileManager.fileExists(atPath: configPath.path) else { return }
        var config = loadJSONObject(from: configPath)

        var mcpServers = (config["mcpServers"] as? [String: Any]) ?? [:]
        mcpServers.removeValue(forKey: id)
        config["mcpServers"] = mcpServers

        try writeJSONObject(config, to: configPath)
    }

    private func buildMCPDict(_ spec: MCPServerSpec) -> [String: Any] {
        var dict: [String: Any] = ["type": spec.type.rawValue]
        if let cmd = spec.command { dict["command"] = cmd }
        if let args = spec.args { dict["args"] = args }
        if let env = spec.env { dict["env"] = env }
        if let cwd = spec.cwd { dict["cwd"] = cwd }
        if let url = spec.url { dict["url"] = url }
        if let headers = spec.headers { dict["headers"] = headers }
        return dict
    }

    // MARK: - Prompt Store Persistence

    private var promptStorePath: URL {
        appSupportDirectory.appendingPathComponent("prompts.json")
    }

    func loadPromptStore() throws -> PromptStore {
        let path = promptStorePath
        guard fileManager.fileExists(atPath: path.path) else {
            return PromptStore()
        }
        let data = try Data(contentsOf: path)
        return try JSONDecoder().decode(PromptStore.self, from: data)
    }

    func savePromptStore(_ store: PromptStore) throws {
        let path = promptStorePath
        let parent = path.deletingLastPathComponent()
        try fileManager.createDirectory(at: parent, withIntermediateDirectories: true)
        let data = try JSONEncoder.pretty.encode(store)
        try data.write(to: path, options: .atomic)
    }

    func activatePrompt(_ prompt: Prompt) throws {
        let filePath = prompt.appType.filePath(in: homeDirectory)
        let parent = filePath.deletingLastPathComponent()
        try fileManager.createDirectory(at: parent, withIntermediateDirectories: true)
        try prompt.content.write(to: filePath, atomically: true, encoding: .utf8)
    }

    func readLivePrompt(for appType: PromptAppType) throws -> String? {
        let filePath = appType.filePath(in: homeDirectory)
        guard fileManager.fileExists(atPath: filePath.path) else { return nil }
        return try String(contentsOf: filePath, encoding: .utf8)
    }

    // MARK: - Local Config Overview

    func loadLocalConfigBundles() throws -> [LocalConfigBundle] {
        [
            LocalConfigBundle(
                app: .claude,
                rootPath: homeDirectory.appendingPathComponent(".claude", isDirectory: true).path,
                files: [
                    makeLocalConfigFile(label: "settings.json", kind: .json, path: claudeSettingsPath),
                    makeLocalConfigFile(
                        label: "CLAUDE.md",
                        kind: .markdown,
                        path: PromptAppType.claude.filePath(in: homeDirectory)
                    ),
                    makeLocalConfigFile(
                        label: ".claude.json",
                        kind: .json,
                        path: homeDirectory.appendingPathComponent(".claude.json", isDirectory: false)
                    )
                ]
            ),
            LocalConfigBundle(
                app: .codex,
                rootPath: homeDirectory.appendingPathComponent(".codex", isDirectory: true).path,
                files: [
                    makeLocalConfigFile(label: "auth.json", kind: .json, path: codexAuthPath),
                    makeLocalConfigFile(label: "config.toml", kind: .toml, path: codexConfigPath),
                    makeLocalConfigFile(
                        label: "AGENTS.md",
                        kind: .markdown,
                        path: PromptAppType.codex.filePath(in: homeDirectory)
                    )
                ]
            ),
            LocalConfigBundle(
                app: .gemini,
                rootPath: homeDirectory.appendingPathComponent(".gemini", isDirectory: true).path,
                files: [
                    makeLocalConfigFile(label: ".env", kind: .env, path: geminiEnvPath),
                    makeLocalConfigFile(
                        label: "settings.json",
                        kind: .json,
                        path: homeDirectory.appendingPathComponent(".gemini/settings.json", isDirectory: false)
                    ),
                    makeLocalConfigFile(
                        label: "GEMINI.md",
                        kind: .markdown,
                        path: PromptAppType.gemini.filePath(in: homeDirectory)
                    )
                ]
            )
        ]
    }

    // MARK: - Claude Hooks

    func loadClaudeHooks() throws -> [ClaudeHook] {
        mergeLiveHooks(
            loadClaudeUserHooks()
                + loadCodexHooks()
                + loadGeminiHooks()
        )
    }

    private func loadClaudeUserHooks() -> [ClaudeHook] {
        let settings = loadJSONObject(from: claudeSettingsPath)
        guard let hooks = settings["hooks"] as? [String: Any] else { return [] }

        return hooks.keys.sorted().flatMap { event in
            parseClaudeHooks(
                event: event,
                rawValue: hooks[event],
                sourcePath: claudeSettingsPath.path,
                scope: .user,
                apps: MCPAppToggles(claude: true)
            )
        }
    }

    private func loadCodexHooks() -> [ClaudeHook] {
        let object = loadJSONObject(from: codexHooksPath)
        guard let hooks = object["hooks"] as? [String: Any] else { return [] }

        let featureEnabled = isCodexFeatureEnabled("codex_hooks")
        return hooks.keys.sorted().flatMap { event in
            parseClaudeHooks(
                event: event,
                rawValue: hooks[event],
                sourcePath: codexHooksPath.path,
                scope: .user,
                apps: MCPAppToggles(codex: true)
            )
            .map { hook in
                var updated = hook
                updated.enabled = featureEnabled && hook.enabled
                return updated
            }
        }
    }

    private func loadGeminiHooks() -> [ClaudeHook] {
        let settings = loadJSONObject(from: geminiSettingsPath)
        guard let hooks = settings["hooks"] as? [String: Any] else { return [] }

        let hooksConfig = settings["hooksConfig"] as? [String: Any] ?? [:]
        let hooksEnabled = hooksConfig["enabled"] as? Bool ?? true
        let disabledHookNames = Set(
            ((hooksConfig["disabled"] as? [Any]) ?? [])
                .compactMap { $0 as? String }
        )

        return hooks.keys.sorted().flatMap { event in
            parseClaudeHooks(
                event: event,
                rawValue: hooks[event],
                sourcePath: geminiSettingsPath.path,
                scope: .user,
                apps: MCPAppToggles(gemini: true)
            )
            .map { hook in
                var updated = hook
                updated.timeout = hook.timeout.map { max(1, Int(ceil(Double($0) / 1000.0))) }
                if !hooksEnabled || disabledHookNames.contains(hook.id) {
                    updated.enabled = false
                }
                return updated
            }
        }
    }

    private func mergeLiveHooks(_ hooks: [ClaudeHook]) -> [ClaudeHook] {
        var merged: [String: ClaudeHook] = [:]

        for hook in hooks {
            let key = hook.identityKey
            if var existing = merged[key] {
                existing.apps.claude = existing.apps.claude || hook.apps.claude
                existing.apps.codex = existing.apps.codex || hook.apps.codex
                existing.apps.gemini = existing.apps.gemini || hook.apps.gemini
                existing.enabled = existing.enabled || hook.enabled
                existing.sourcePath = liveHookSourceSummary(for: existing.apps)
                merged[key] = existing
            } else {
                var inserted = hook
                inserted.sourcePath = liveHookSourceSummary(for: hook.apps)
                merged[key] = inserted
            }
        }

        return merged.values.sorted { lhs, rhs in
            if lhs.event != rhs.event {
                return lhs.event.localizedCaseInsensitiveCompare(rhs.event) == .orderedAscending
            }
            let lhsMatcher = lhs.matcher ?? ""
            let rhsMatcher = rhs.matcher ?? ""
            if lhsMatcher != rhsMatcher {
                return lhsMatcher.localizedCaseInsensitiveCompare(rhsMatcher) == .orderedAscending
            }
            return lhs.command.localizedCaseInsensitiveCompare(rhs.command) == .orderedAscending
        }
    }

    func syncHooks(_ hooks: [ClaudeHook]) throws {
        try writeClaudeHooks(hooks.filter { $0.apps.claude && $0.supports(app: .claude) })
        try writeCodexHooks(hooks.filter { $0.apps.codex && $0.supports(app: .codex) })
        try writeGeminiHooks(hooks.filter { $0.apps.gemini && $0.supports(app: .gemini) })
    }

    private func writeClaudeHooks(_ hooks: [ClaudeHook]) throws {
        var settings = loadJSONObject(from: claudeSettingsPath)
        let payload = renderClaudeStyleHooksPayload(hooks)
        if payload.isEmpty {
            settings.removeValue(forKey: "hooks")
        } else {
            settings["hooks"] = payload
        }
        try writeJSONObject(settings, to: claudeSettingsPath)
    }

    private func writeCodexHooks(_ hooks: [ClaudeHook]) throws {
        let activeHooks = hooks.filter(\.enabled)
        if activeHooks.isEmpty {
            if fileManager.fileExists(atPath: codexHooksPath.path) {
                try fileManager.removeItem(at: codexHooksPath)
            }
        } else {
            let payload: [String: Any] = ["hooks": renderCodexHooksPayload(activeHooks)]
            try writeJSONObject(payload, to: codexHooksPath)
        }

        let updatedContent = updateCodexFeatureFlags(["codex_hooks": activeHooks.isEmpty ? nil : true])
        try writeTOML(updatedContent, to: codexConfigPath)
    }

    private func writeGeminiHooks(_ hooks: [ClaudeHook]) throws {
        var settings = loadJSONObject(from: geminiSettingsPath)
        let payload = renderGeminiHooksPayload(hooks)
        if payload.isEmpty {
            settings.removeValue(forKey: "hooks")
        } else {
            settings["hooks"] = payload
        }

        var hooksConfig = (settings["hooksConfig"] as? [String: Any]) ?? [:]
        if hooks.isEmpty {
            hooksConfig.removeValue(forKey: "disabled")
        } else {
            hooksConfig["enabled"] = true
            let disabledNames = hooks
                .filter { !$0.enabled }
                .map(geminiHookName(for:))
                .sorted()
            hooksConfig["disabled"] = disabledNames
        }

        if hooksConfig.isEmpty {
            settings.removeValue(forKey: "hooksConfig")
        } else {
            settings["hooksConfig"] = hooksConfig
        }

        try writeJSONObject(settings, to: geminiSettingsPath)
    }

    // MARK: - Hook Store Persistence

    private var hookStorePath: URL {
        appSupportDirectory.appendingPathComponent("hooks.json")
    }

    func loadHookStore() throws -> HookStore {
        let path = hookStorePath
        guard fileManager.fileExists(atPath: path.path) else { return HookStore() }
        let data = try Data(contentsOf: path)
        return try JSONDecoder().decode(HookStore.self, from: data)
    }

    func saveHookStore(_ store: HookStore) throws {
        let path = hookStorePath
        let parent = path.deletingLastPathComponent()
        try fileManager.createDirectory(at: parent, withIntermediateDirectories: true)
        let data = try JSONEncoder.pretty.encode(store)
        try data.write(to: path, options: .atomic)
    }

    func hookSourceSummary(for apps: MCPAppToggles) -> String {
        liveHookSourceSummary(for: apps)
    }

    // MARK: - Skill Store Persistence

    private var skillStorePath: URL {
        appSupportDirectory.appendingPathComponent("skills.json")
    }

    func loadSkillStore() throws -> SkillStore {
        let path = skillStorePath
        guard fileManager.fileExists(atPath: path.path) else {
            return SkillStore(repos: SkillStore.defaultRepos)
        }
        let data = try Data(contentsOf: path)
        return try JSONDecoder().decode(SkillStore.self, from: data)
    }

    func saveSkillStore(_ store: SkillStore) throws {
        let path = skillStorePath
        let parent = path.deletingLastPathComponent()
        try fileManager.createDirectory(at: parent, withIntermediateDirectories: true)
        let data = try JSONEncoder.pretty.encode(store)
        try data.write(to: path, options: .atomic)
    }

    var skillsInstallDirectory: URL {
        appSupportDirectory.appendingPathComponent("skills", isDirectory: true)
    }

    func appSkillsDirectory(for app: ProviderAppType) -> URL {
        switch app {
        case .claude:
            return claudeSkillsDirectory
        case .codex:
            return codexSkillsDirectory
        case .gemini:
            return geminiSkillsDirectory
        }
    }

    func installedSkillMarkdownPath(directory: String) -> URL {
        installedSkillDirectoryURL(directory: directory).appendingPathComponent("SKILL.md", isDirectory: false)
    }

    func readInstalledSkillContent(directory: String) throws -> String {
        let path = installedSkillMarkdownPath(directory: directory)
        guard fileManager.fileExists(atPath: path.path) else {
            throw AppError.fileNotFound("未找到技能文件：\(directory)/SKILL.md")
        }
        return try String(contentsOf: path, encoding: .utf8)
    }

    func writeInstalledSkillContent(directory: String, content: String) throws {
        let path = installedSkillMarkdownPath(directory: directory)
        let parent = path.deletingLastPathComponent()
        guard fileManager.fileExists(atPath: parent.path) else {
            throw AppError.fileNotFound("未找到技能目录：\(directory)")
        }
        try content.write(to: path, atomically: true, encoding: .utf8)
    }

    func syncInstalledSkill(_ skill: InstalledSkill) throws {
        let sourceDirectory = installedSkillDirectoryURL(directory: skill.directory)
        guard fileManager.fileExists(atPath: sourceDirectory.path) else {
            throw AppError.fileNotFound("未找到技能目录：\(skill.directory)")
        }

        for app in ProviderAppType.allCases {
            let targetDirectory = appSkillsDirectory(for: app).appendingPathComponent(skill.directory, isDirectory: true)
            if skill.apps.isEnabled(for: app) {
                try copyDirectoryReplacingExisting(from: sourceDirectory, to: targetDirectory)
            } else if fileManager.fileExists(atPath: targetDirectory.path) {
                try fileManager.removeItem(at: targetDirectory)
            }
        }
    }

    func removeInstalledSkillFromApps(directory: String) throws {
        for app in ProviderAppType.allCases {
            let targetDirectory = appSkillsDirectory(for: app).appendingPathComponent(directory, isDirectory: true)
            if fileManager.fileExists(atPath: targetDirectory.path) {
                try fileManager.removeItem(at: targetDirectory)
            }
        }
    }

    private func loadJSONObject(from path: URL) -> [String: Any] {
        guard fileManager.fileExists(atPath: path.path),
              let data = try? Data(contentsOf: path),
              let object = try? JSONSerialization.jsonObject(with: data) as? [String: Any] else {
            return [:]
        }
        return object
    }

    private func parseJSONObjectString(_ text: String) throws -> [String: Any] {
        guard let data = text.data(using: .utf8) else {
            throw AppError.invalidData("Claude 通用配置 JSON 无法读取")
        }

        let object: Any
        do {
            object = try JSONSerialization.jsonObject(with: data)
        } catch {
            throw AppError.invalidData("Claude 通用配置 JSON 解析失败")
        }

        guard let dictionary = object as? [String: Any] else {
            throw AppError.invalidData("Claude 通用配置需要顶层对象")
        }
        return dictionary
    }

    private func writeJSONObject(_ object: [String: Any], to path: URL) throws {
        try fileManager.createDirectory(at: path.deletingLastPathComponent(), withIntermediateDirectories: true)
        let data = try JSONSerialization.data(withJSONObject: object, options: [.prettyPrinted, .sortedKeys])
        try data.write(to: path, options: .atomic)
    }

    private func installedSkillDirectoryURL(directory: String) -> URL {
        directory
            .split(separator: "/")
            .reduce(skillsInstallDirectory) { partialResult, component in
                partialResult.appendingPathComponent(String(component), isDirectory: true)
            }
    }

    private func copyDirectoryReplacingExisting(from source: URL, to destination: URL) throws {
        let parent = destination.deletingLastPathComponent()
        try fileManager.createDirectory(at: parent, withIntermediateDirectories: true)
        if fileManager.fileExists(atPath: destination.path) {
            try fileManager.removeItem(at: destination)
        }
        try fileManager.copyItem(at: source, to: destination)
    }

    private func liveHookSourceSummary(for apps: MCPAppToggles) -> String {
        var parts: [String] = []
        if apps.claude {
            parts.append(claudeSettingsPath.path)
        }
        if apps.codex {
            parts.append(codexHooksPath.path)
        }
        if apps.gemini {
            parts.append(geminiSettingsPath.path)
        }
        return parts.joined(separator: " · ")
    }

    private func renderClaudeStyleHooksPayload(_ hooks: [ClaudeHook]) -> [String: Any] {
        renderHooksPayload(hooks) { hook in
            var item: [String: Any] = [
                "command": hook.command,
                "type": hook.commandType?.trimmedNonEmpty ?? "command",
            ]
            if let timeout = hook.timeout {
                item["timeout"] = timeout
            }
            if !hook.enabled {
                item["enabled"] = false
            }
            if let id = hook.id.trimmedNonEmpty {
                item["id"] = id
            }
            return item
        }
    }

    private func renderCodexHooksPayload(_ hooks: [ClaudeHook]) -> [String: Any] {
        renderHooksPayload(hooks.filter(\.enabled)) { hook in
            var item: [String: Any] = [
                "command": hook.command,
                "type": hook.commandType?.trimmedNonEmpty ?? "command",
            ]
            if let timeout = hook.timeout {
                item["timeout"] = timeout
            }
            return item
        }
    }

    private func renderGeminiHooksPayload(_ hooks: [ClaudeHook]) -> [String: Any] {
        renderHooksPayload(hooks) { hook in
            var item: [String: Any] = [
                "name": geminiHookName(for: hook),
                "type": hook.commandType?.trimmedNonEmpty ?? "command",
                "command": hook.command,
            ]
            if let timeout = hook.timeout {
                item["timeout"] = timeout * 1000
            }
            return item
        }
    }

    private func renderHooksPayload(
        _ hooks: [ClaudeHook],
        itemBuilder: (ClaudeHook) -> [String: Any]
    ) -> [String: Any] {
        let groupedEvents = Dictionary(grouping: hooks, by: \.event)
        var payload: [String: Any] = [:]

        for event in groupedEvents.keys.sorted() {
            let eventHooks = groupedEvents[event] ?? []
            let groupedMatchers = Dictionary(grouping: eventHooks) { $0.matcher?.trimmedNonEmpty ?? "" }

            let groups: [[String: Any]] = groupedMatchers.keys.sorted().compactMap { matcherKey in
                let matcherHooks = (groupedMatchers[matcherKey] ?? []).sorted { lhs, rhs in
                    if lhs.command != rhs.command {
                        return lhs.command.localizedCaseInsensitiveCompare(rhs.command) == .orderedAscending
                    }
                    return lhs.id.localizedCaseInsensitiveCompare(rhs.id) == .orderedAscending
                }

                guard !matcherHooks.isEmpty else { return nil }

                var group: [String: Any] = ["hooks": matcherHooks.map(itemBuilder)]
                if let matcher = matcherKey.trimmedNonEmpty {
                    group["matcher"] = matcher
                }
                return group
            }

            if !groups.isEmpty {
                payload[event] = groups
            }
        }

        return payload
    }

    private func geminiHookName(for hook: ClaudeHook) -> String {
        let raw = hook.id.trimmedNonEmpty ?? "\(hook.event)-\(hook.command.prefix(32))"
        let sanitized = raw.lowercased().map { character -> Character in
            switch character {
            case "a"..."z", "0"..."9", "-", "_":
                return character
            default:
                return "-"
            }
        }
        let collapsed = String(sanitized)
            .replacingOccurrences(of: "--", with: "-")
            .trimmingCharacters(in: CharacterSet(charactersIn: "-"))
        return collapsed.isEmpty ? "hook-\(hook.event.lowercased())" : collapsed
    }

    private func makeLocalConfigFile(label: String, kind: LocalConfigKind, path: URL) -> LocalConfigFile {
        guard fileManager.fileExists(atPath: path.path) else {
            return LocalConfigFile(
                label: label,
                path: path.path,
                kind: kind,
                exists: false,
                byteCount: nil,
                modifiedAt: nil
            )
        }

        let attributes = try? fileManager.attributesOfItem(atPath: path.path)
        let byteCount = (attributes?[.size] as? NSNumber)?.int64Value
        let modifiedAt = (attributes?[.modificationDate] as? Date).map { Int64($0.timeIntervalSince1970) }

        return LocalConfigFile(
            label: label,
            path: path.path,
            kind: kind,
            exists: true,
            byteCount: byteCount,
            modifiedAt: modifiedAt
        )
    }

    private func parseClaudeHooks(
        event: String,
        rawValue: Any?,
        sourcePath: String,
        scope: ClaudeHookScope,
        apps: MCPAppToggles
    ) -> [ClaudeHook] {
        guard let entries = rawValue as? [Any] else { return [] }

        var hooks: [ClaudeHook] = []

        for (entryIndex, entry) in entries.enumerated() {
            if let group = entry as? [String: Any] {
                let matcher = (group["matcher"] as? String)?.trimmedNonEmpty
                let groupEnabled = group["enabled"] as? Bool ?? true

                if let nestedHooks = group["hooks"] as? [Any] {
                    for (hookIndex, nestedHook) in nestedHooks.enumerated() {
                        if let parsed = parseClaudeHookEntry(
                            event: event,
                            matcher: matcher,
                            rawValue: nestedHook,
                            defaultID: "\(event)-\(entryIndex)-\(hookIndex)",
                            enabled: groupEnabled,
                            sourcePath: sourcePath,
                            scope: scope,
                            apps: apps
                        ) {
                            hooks.append(parsed)
                        }
                    }
                    continue
                }

                if let parsed = parseClaudeHookEntry(
                    event: event,
                    matcher: matcher,
                    rawValue: group,
                    defaultID: "\(event)-\(entryIndex)",
                    enabled: groupEnabled,
                    sourcePath: sourcePath,
                    scope: scope,
                    apps: apps
                ) {
                    hooks.append(parsed)
                }
                continue
            }

            if let parsed = parseClaudeHookEntry(
                event: event,
                matcher: nil,
                rawValue: entry,
                defaultID: "\(event)-\(entryIndex)",
                enabled: true,
                sourcePath: sourcePath,
                scope: scope,
                apps: apps
            ) {
                hooks.append(parsed)
            }
        }

        return hooks
    }

    private func parseClaudeHookEntry(
        event: String,
        matcher: String?,
        rawValue: Any,
        defaultID: String,
        enabled: Bool,
        sourcePath: String,
        scope: ClaudeHookScope,
        apps: MCPAppToggles
    ) -> ClaudeHook? {
        if let command = (rawValue as? String)?.trimmedNonEmpty {
            return ClaudeHook(
                id: defaultID,
                event: event,
                matcher: matcher,
                command: command,
                commandType: nil,
                timeout: nil,
                enabled: enabled,
                scope: scope,
                sourcePath: sourcePath,
                apps: apps
            )
        }

        guard let dictionary = rawValue as? [String: Any],
              let command = (dictionary["command"] as? String)?.trimmedNonEmpty else {
            return nil
        }

        let commandType = (dictionary["type"] as? String)?.trimmedNonEmpty
        let timeout = (dictionary["timeout"] as? Int)
            ?? (dictionary["timeout"] as? NSNumber)?.intValue
        let explicitEnabled = dictionary["enabled"] as? Bool ?? enabled

        return ClaudeHook(
            id: (dictionary["id"] as? String)?.trimmedNonEmpty
                ?? (dictionary["name"] as? String)?.trimmedNonEmpty
                ?? defaultID,
            event: event,
            matcher: matcher,
            command: command,
            commandType: commandType,
            timeout: timeout,
            enabled: explicitEnabled,
            scope: scope,
            sourcePath: sourcePath,
            apps: apps
        )
    }

    private func setJSONValue(_ object: inout [String: Any], key: String, value: String?) {
        if let value {
            object[key] = value
        } else {
            object.removeValue(forKey: key)
        }
    }

    private func mergingJSONObject(_ base: [String: Any], with overlay: [String: Any]) -> [String: Any] {
        var result = base
        for (key, value) in overlay {
            result[key] = value
        }
        return result
    }

    private func readTOML(at path: URL) -> String {
        guard fileManager.fileExists(atPath: path.path) else { return "" }
        return (try? String(contentsOf: path, encoding: .utf8)) ?? ""
    }

    private func writeTOML(_ content: String, to path: URL) throws {
        let normalized = normalizedMultilineContent(content)
        if normalized.isEmpty {
            if fileManager.fileExists(atPath: path.path) {
                try fileManager.removeItem(at: path)
            }
            return
        }
        try fileManager.createDirectory(at: path.deletingLastPathComponent(), withIntermediateDirectories: true)
        try normalized.write(to: path, atomically: true, encoding: .utf8)
    }

    private func updateCodexRootConfig(values: [String: String?]) -> String {
        let content = readTOML(at: codexConfigPath)
        let lines = content.normalizedNewlines.components(separatedBy: "\n")
        let managedKeys = ["model", "wire_api", "base_url", "reasoning_effort"]

        var rootLines: [String] = []
        var sectionLines: [String] = []
        var encounteredSection = false

        for line in lines {
            let trimmed = line.trimmingCharacters(in: .whitespaces)
            if trimmed.hasPrefix("[") {
                encounteredSection = true
            }

            if !encounteredSection {
                if let key = rootAssignmentKey(in: line), managedKeys.contains(key) {
                    continue
                }
                rootLines.append(line)
            } else {
                sectionLines.append(line)
            }
        }

        rootLines = trimTrailingBlankLines(rootLines)
        for key in managedKeys {
            if let value = values[key] ?? nil {
                rootLines.append("\(key) = \(tomlString(value))")
            }
        }

        sectionLines = trimLeadingBlankLines(sectionLines)
        var combined: [String] = []
        if !rootLines.isEmpty {
            combined.append(contentsOf: rootLines)
        }
        if !sectionLines.isEmpty {
            if !combined.isEmpty {
                combined.append("")
            }
            combined.append(contentsOf: sectionLines)
        }

        return combined.joined(separator: "\n")
    }

    private func updateCodexFeatureFlags(_ values: [String: Bool?]) -> String {
        let content = readTOML(at: codexConfigPath)
        let lines = content.normalizedNewlines.components(separatedBy: "\n")

        var beforeSection: [String] = []
        var featureLines: [String] = []
        var afterSection: [String] = []
        var state = 0

        for line in lines {
            let trimmed = line.trimmingCharacters(in: .whitespaces)
            if state == 0 {
                if trimmed == "[features]" {
                    state = 1
                    continue
                }
                beforeSection.append(line)
                continue
            }

            if state == 1 {
                if trimmed.hasPrefix("[") {
                    state = 2
                    afterSection.append(line)
                    continue
                }

                if let key = rootAssignmentKey(in: line), values.keys.contains(key) {
                    continue
                }
                featureLines.append(line)
                continue
            }

            afterSection.append(line)
        }

        featureLines = trimTrailingBlankLines(featureLines)
        for key in values.keys.sorted() {
            if let enabled = values[key] ?? nil {
                featureLines.append("\(key) = \(enabled ? "true" : "false")")
            }
        }

        var combined = trimTrailingBlankLines(beforeSection)
        if !featureLines.isEmpty {
            if !combined.isEmpty {
                combined.append("")
            }
            combined.append("[features]")
            combined.append(contentsOf: featureLines)
        }

        let trailing = trimLeadingBlankLines(afterSection)
        if !trailing.isEmpty {
            if !combined.isEmpty {
                combined.append("")
            }
            combined.append(contentsOf: trailing)
        }

        return collapseDuplicateBlankLines(combined).joined(separator: "\n")
    }

    private func isCodexFeatureEnabled(_ key: String) -> Bool {
        let content = readTOML(at: codexConfigPath)
        guard !content.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty else { return false }

        var inFeaturesSection = false
        for line in content.normalizedNewlines.components(separatedBy: "\n") {
            let trimmed = line.trimmingCharacters(in: .whitespacesAndNewlines)
            if trimmed.hasPrefix("[") {
                inFeaturesSection = trimmed == "[features]"
                continue
            }

            guard inFeaturesSection,
                  rootAssignmentKey(in: line) == key,
                  let equalsIndex = trimmed.firstIndex(of: "=") else {
                continue
            }

            let value = trimmed[trimmed.index(after: equalsIndex)...]
                .trimmingCharacters(in: .whitespacesAndNewlines)
            return value == "true"
        }

        return false
    }

    private func replacingCodexMCPSection(in content: String, serverID: String, spec: MCPServerSpec) -> String {
        replaceTOMLSection(
            in: content,
            header: "[mcp_servers.\(serverID)]",
            replacement: renderCodexMCPSection(serverID: serverID, spec: spec)
        )
    }

    private func removingCodexMCPSection(in content: String, serverID: String) -> String {
        replaceTOMLSection(
            in: content,
            header: "[mcp_servers.\(serverID)]",
            replacement: nil
        )
    }

    private func replaceTOMLSection(in content: String, header: String, replacement: [String]?) -> String {
        let normalized = content.normalizedNewlines
        var lines = normalized.components(separatedBy: "\n")
        if lines.count == 1 && lines[0].isEmpty {
            lines = []
        }

        let startIndex = lines.firstIndex { $0.trimmingCharacters(in: .whitespaces) == header }
        if let startIndex {
            var endIndex = lines.count
            if startIndex + 1 < lines.count {
                for index in (startIndex + 1)..<lines.count {
                    if lines[index].trimmingCharacters(in: .whitespaces).hasPrefix("[") {
                        endIndex = index
                        break
                    }
                }
            }
            lines.removeSubrange(startIndex..<endIndex)
            if let replacement, !replacement.isEmpty {
                lines.insert(contentsOf: replacement, at: startIndex)
            }
        } else if let replacement, !replacement.isEmpty {
            lines = trimTrailingBlankLines(lines)
            if !lines.isEmpty {
                lines.append("")
            }
            lines.append(contentsOf: replacement)
        }

        return trimTrailingBlankLines(collapseDuplicateBlankLines(lines)).joined(separator: "\n")
    }

    private func renderCodexMCPSection(serverID: String, spec: MCPServerSpec) -> [String] {
        var lines = ["[mcp_servers.\(serverID)]", "type = \(tomlString(spec.type.rawValue))"]
        if let command = spec.command?.trimmedNonEmpty {
            lines.append("command = \(tomlString(command))")
        }
        if let args = spec.args, !args.isEmpty {
            lines.append("args = [\(args.map(tomlString).joined(separator: ", "))]")
        }
        if let env = spec.env, !env.isEmpty {
            lines.append("env = \(tomlInlineTable(env))")
        }
        if let cwd = spec.cwd?.trimmedNonEmpty {
            lines.append("cwd = \(tomlString(cwd))")
        }
        if let url = spec.url?.trimmedNonEmpty {
            lines.append("url = \(tomlString(url))")
        }
        if let headers = spec.headers, !headers.isEmpty {
            lines.append("headers = \(tomlInlineTable(headers))")
        }
        return lines
    }

    private func rootAssignmentKey(in line: String) -> String? {
        let trimmed = line.trimmingCharacters(in: .whitespaces)
        guard !trimmed.isEmpty, !trimmed.hasPrefix("#"), !trimmed.hasPrefix("["),
              let equalsIndex = trimmed.firstIndex(of: "=") else {
            return nil
        }
        return String(trimmed[..<equalsIndex]).trimmingCharacters(in: .whitespacesAndNewlines)
    }

    private func tomlString(_ value: String) -> String {
        let escaped = value
            .replacingOccurrences(of: "\\", with: "\\\\")
            .replacingOccurrences(of: "\"", with: "\\\"")
        return "\"\(escaped)\""
    }

    private func tomlInlineTable(_ value: [String: String]) -> String {
        let pairs = value.keys.sorted().map { key in
            "\(tomlString(key)) = \(tomlString(value[key] ?? ""))"
        }
        return "{ \(pairs.joined(separator: ", ")) }"
    }

    private func updateDotEnv(at path: URL, assignments: [String: String?]) -> String {
        let lines = readEnvLines(at: path)
        let keys = Set(assignments.keys)
        var appliedKeys = Set<String>()
        var output: [String] = []

        for line in lines {
            if let key = dotEnvKey(in: line), keys.contains(key) {
                if !appliedKeys.contains(key), let value = assignments[key] ?? nil {
                    output.append("\(key)=\(value)")
                    appliedKeys.insert(key)
                }
                continue
            }
            output.append(line)
        }

        for key in assignments.keys.sorted() where !appliedKeys.contains(key) {
            if let value = assignments[key] ?? nil {
                output.append("\(key)=\(value)")
            }
        }

        return output.joined(separator: "\n")
    }

    private func readEnvLines(at path: URL) -> [String] {
        let content = fileManager.fileExists(atPath: path.path)
            ? ((try? String(contentsOf: path, encoding: .utf8)) ?? "")
            : ""
        let normalized = content.normalizedNewlines
        guard !normalized.isEmpty else { return [] }
        return normalized.components(separatedBy: "\n")
    }

    private func writeEnvFile(_ content: String, to path: URL) throws {
        let normalized = normalizedMultilineContent(content)
        if normalized.isEmpty {
            if fileManager.fileExists(atPath: path.path) {
                try fileManager.removeItem(at: path)
            }
            return
        }
        try fileManager.createDirectory(at: path.deletingLastPathComponent(), withIntermediateDirectories: true)
        try normalized.write(to: path, atomically: true, encoding: .utf8)
    }

    private func dotEnvKey(in line: String) -> String? {
        let trimmed = line.trimmingCharacters(in: .whitespaces)
        guard !trimmed.isEmpty, !trimmed.hasPrefix("#"), let equalsIndex = trimmed.firstIndex(of: "=") else {
            return nil
        }
        let prefix = trimmed[..<equalsIndex]
        if prefix.hasPrefix("export ") {
            return String(prefix.dropFirst("export ".count)).trimmingCharacters(in: .whitespacesAndNewlines)
        }
        return String(prefix).trimmingCharacters(in: .whitespacesAndNewlines)
    }

    private func trimTrailingBlankLines(_ lines: [String]) -> [String] {
        var result = lines
        while let last = result.last, last.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
            result.removeLast()
        }
        return result
    }

    private func trimLeadingBlankLines(_ lines: [String]) -> [String] {
        var result = lines
        while let first = result.first, first.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
            result.removeFirst()
        }
        return result
    }

    private func collapseDuplicateBlankLines(_ lines: [String]) -> [String] {
        var result: [String] = []
        var previousWasBlank = false
        for line in lines {
            let isBlank = line.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
            if isBlank && previousWasBlank {
                continue
            }
            result.append(line)
            previousWasBlank = isBlank
        }
        return result
    }

    private func normalizedMultilineContent(_ content: String) -> String {
        let normalized = content.normalizedNewlines.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !normalized.isEmpty else { return "" }
        return normalized + "\n"
    }
}

// MARK: - JSON Encoder Helper

extension JSONEncoder {
    static let pretty: JSONEncoder = {
        let encoder = JSONEncoder()
        encoder.outputFormatting = [.prettyPrinted, .sortedKeys]
        return encoder
    }()
}

private extension String {
    var normalizedNewlines: String {
        replacingOccurrences(of: "\r\n", with: "\n")
            .replacingOccurrences(of: "\r", with: "\n")
    }
}
