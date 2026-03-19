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
        homeDirectory.appendingPathComponent("Library/Application Support/CodexToolsSwift", isDirectory: true)
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

    private func writeClaudeConfig(_ config: ClaudeSettingsConfig) throws {
        let settingsPath = claudeSettingsPath
        try fileManager.createDirectory(at: settingsPath.deletingLastPathComponent(), withIntermediateDirectories: true)

        var settings = loadJSONObject(from: settingsPath)
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
        homeDirectory.appendingPathComponent(".claude/skills")
    }

    private func loadJSONObject(from path: URL) -> [String: Any] {
        guard fileManager.fileExists(atPath: path.path),
              let data = try? Data(contentsOf: path),
              let object = try? JSONSerialization.jsonObject(with: data) as? [String: Any] else {
            return [:]
        }
        return object
    }

    private func writeJSONObject(_ object: [String: Any], to path: URL) throws {
        try fileManager.createDirectory(at: path.deletingLastPathComponent(), withIntermediateDirectories: true)
        let data = try JSONSerialization.data(withJSONObject: object, options: [.prettyPrinted, .sortedKeys])
        try data.write(to: path, options: .atomic)
    }

    private func setJSONValue(_ object: inout [String: Any], key: String, value: String?) {
        if let value {
            object[key] = value
        } else {
            object.removeValue(forKey: key)
        }
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
