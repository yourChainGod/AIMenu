import Foundation

// MARK: - MCP Transport Type

enum MCPTransportType: String, Codable, CaseIterable {
    case stdio
    case http
    case sse

    var displayName: String {
        switch self {
        case .stdio: return "STDIO"
        case .http: return "HTTP"
        case .sse: return "SSE"
        }
    }
}

// MARK: - MCP Server

struct MCPServerSpec: Codable, Equatable {
    var type: MCPTransportType
    var command: String?
    var args: [String]?
    var env: [String: String]?
    var cwd: String?
    var url: String?
    var headers: [String: String]?

    var displayCommand: String {
        switch type {
        case .stdio:
            let cmd = command ?? ""
            let argStr = (args ?? []).joined(separator: " ")
            return "\(cmd) \(argStr)".trimmingCharacters(in: .whitespaces)
        case .http, .sse:
            return url ?? ""
        }
    }
}

struct MCPAppToggles: Codable, Equatable {
    var claude: Bool
    var codex: Bool
    var gemini: Bool

    init(claude: Bool = false, codex: Bool = false, gemini: Bool = false) {
        self.claude = claude
        self.codex = codex
        self.gemini = gemini
    }

    private enum CodingKeys: String, CodingKey {
        case claude
        case codex
        case gemini
    }

    static let allEnabled = MCPAppToggles(claude: true, codex: true, gemini: true)
    static let claudeOnly = MCPAppToggles(claude: true, codex: false, gemini: false)
    static let none = MCPAppToggles()

    init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        claude = try container.decodeIfPresent(Bool.self, forKey: .claude) ?? false
        codex = try container.decodeIfPresent(Bool.self, forKey: .codex) ?? false
        gemini = try container.decodeIfPresent(Bool.self, forKey: .gemini) ?? false
    }

    mutating func setEnabled(_ enabled: Bool, for app: ProviderAppType) {
        switch app {
        case .claude:
            claude = enabled
        case .codex:
            codex = enabled
        case .gemini:
            gemini = enabled
        }
    }

    func isEnabled(for app: ProviderAppType) -> Bool {
        switch app {
        case .claude:
            return claude
        case .codex:
            return codex
        case .gemini:
            return gemini
        }
    }

    var enabledApps: [ProviderAppType] {
        ProviderAppType.allCases.filter(isEnabled(for:))
    }

    var hasAnyEnabled: Bool {
        !enabledApps.isEmpty
    }

    var displayText: String {
        let names = enabledApps.map(\.displayName)
        return names.isEmpty ? L10n.tr("common.none") : names.joined(separator: ", ")
    }
}

struct MCPServer: Codable, Equatable, Identifiable {
    var id: String
    var name: String
    var server: MCPServerSpec
    var apps: MCPAppToggles
    var description: String?
    var tags: [String]?
    var homepage: String?
    var createdAt: Int64
    var updatedAt: Int64
    var isEnabled: Bool

    var enabledAppsText: String {
        var parts: [String] = []
        if apps.claude { parts.append("Claude") }
        if apps.codex { parts.append("Codex") }
        if apps.gemini { parts.append("Gemini") }
        return parts.isEmpty ? L10n.tr("common.none") : parts.joined(separator: ", ")
    }
}

struct MCPStore: Codable, Equatable {
    var version: Int = 1
    var servers: [MCPServer] = []
}

// MARK: - MCP Presets

struct MCPPreset: Identifiable {
    var id: String
    var name: String
    var description: String
    var server: MCPServerSpec
    var defaultApps: MCPAppToggles
    var homepage: String?
    var tags: [String]

    func makeServer() -> MCPServer {
        let now = Int64(Date().timeIntervalSince1970)
        return MCPServer(
            id: UUID().uuidString,
            name: name,
            server: server,
            apps: defaultApps,
            description: description,
            tags: tags,
            homepage: homepage,
            createdAt: now,
            updatedAt: now,
            isEnabled: true
        )
    }
}

// MARK: - Prompt

enum PromptAppType: String, Codable, CaseIterable, Identifiable {
    case claude
    case codex
    case gemini

    var id: String { rawValue }

    var displayName: String {
        switch self {
        case .claude: return "Claude"
        case .codex: return "Codex"
        case .gemini: return "Gemini"
        }
    }

    var fileName: String {
        switch self {
        case .claude: return "CLAUDE.md"
        case .codex: return "AGENTS.md"
        case .gemini: return "GEMINI.md"
        }
    }

    var configDirectory: String {
        switch self {
        case .claude: return ".claude"
        case .codex: return ".codex"
        case .gemini: return ".gemini"
        }
    }

    func filePath(in homeDirectory: URL = FileManager.default.homeDirectoryForCurrentUser) -> URL {
        homeDirectory.appendingPathComponent(configDirectory).appendingPathComponent(fileName)
    }

    var filePath: URL {
        filePath(in: FileManager.default.homeDirectoryForCurrentUser)
    }
}

struct Prompt: Codable, Equatable, Identifiable {
    var id: String
    var name: String
    var appType: PromptAppType
    var content: String
    var description: String?
    var isActive: Bool
    var createdAt: Int64
    var updatedAt: Int64
}

struct PromptStore: Codable, Equatable {
    var version: Int = 1
    var prompts: [Prompt] = []
}

// MARK: - Skill

struct SkillRepo: Codable, Equatable, Identifiable {
    var id: String { "\(owner)/\(name)" }
    var owner: String
    var name: String
    var branch: String
    var isEnabled: Bool
    var isDefault: Bool
}

struct DiscoverableSkill: Equatable, Identifiable {
    var id: String { key }
    var key: String // "owner/repo:directory"
    var name: String
    var description: String?
    var readmeUrl: String?
    var repoOwner: String
    var repoName: String
    var repoBranch: String
    var directory: String
    var isInstalled: Bool
    var apps: MCPAppToggles = .claudeOnly
}

struct DiscoverableSkillPreviewDocument: Equatable, Identifiable {
    var id: String { skill.id }
    var skill: DiscoverableSkill
    var sourcePath: String
    var content: String
}

struct InstalledSkill: Codable, Equatable, Identifiable {
    var id: String { directory }
    var key: String
    var name: String
    var description: String?
    var directory: String
    var repoOwner: String
    var repoName: String
    var installedAt: Int64
    var apps: MCPAppToggles

    init(
        key: String,
        name: String,
        description: String?,
        directory: String,
        repoOwner: String,
        repoName: String,
        installedAt: Int64,
        apps: MCPAppToggles = .claudeOnly
    ) {
        self.key = key
        self.name = name
        self.description = description
        self.directory = directory
        self.repoOwner = repoOwner
        self.repoName = repoName
        self.installedAt = installedAt
        self.apps = apps
    }

    private enum CodingKeys: String, CodingKey {
        case key
        case name
        case description
        case directory
        case repoOwner
        case repoName
        case installedAt
        case apps
    }

    init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        key = try container.decode(String.self, forKey: .key)
        name = try container.decode(String.self, forKey: .name)
        description = try container.decodeIfPresent(String.self, forKey: .description)
        directory = try container.decode(String.self, forKey: .directory)
        repoOwner = try container.decodeIfPresent(String.self, forKey: .repoOwner) ?? ""
        repoName = try container.decodeIfPresent(String.self, forKey: .repoName) ?? ""
        installedAt = try container.decodeIfPresent(Int64.self, forKey: .installedAt) ?? Int64(Date().timeIntervalSince1970)
        apps = try container.decodeIfPresent(MCPAppToggles.self, forKey: .apps) ?? .claudeOnly
    }

    var enabledAppsText: String {
        apps.displayText
    }
}

struct InstalledSkillDocument: Equatable, Identifiable {
    var id: String { skill.id }
    var skill: InstalledSkill
    var path: String
    var content: String
}

// MARK: - Local Config Overview

enum LocalConfigKind: String, Codable, Equatable {
    case json
    case toml
    case env
    case markdown

    var displayName: String {
        switch self {
        case .json: return "JSON"
        case .toml: return "TOML"
        case .env: return "ENV"
        case .markdown: return "MD"
        }
    }
}

struct LocalConfigFile: Equatable, Identifiable {
    var id: String { path }
    var label: String
    var path: String
    var kind: LocalConfigKind
    var exists: Bool
    var byteCount: Int64?
    var modifiedAt: Int64?
}

struct LocalConfigBundle: Equatable, Identifiable {
    var id: String { app.id }
    var app: ProviderAppType
    var rootPath: String
    var files: [LocalConfigFile]

    var existingFileCount: Int {
        files.filter(\.exists).count
    }

    var latestModifiedAt: Int64? {
        files.compactMap(\.modifiedAt).max()
    }
}

// MARK: - Claude Hooks

enum ClaudeHookScope: String, Codable, Equatable {
    case user
    case project

    var displayName: String {
        switch self {
        case .user: return L10n.tr("tools.hooks.scope.user")
        case .project: return L10n.tr("tools.hooks.scope.project")
        }
    }
}

struct ClaudeHook: Codable, Equatable, Identifiable {
    var id: String
    var event: String
    var matcher: String?
    var command: String
    var commandType: String?
    var timeout: Int?
    var enabled: Bool
    var scope: ClaudeHookScope
    var sourcePath: String
    var apps: MCPAppToggles

    init(
        id: String,
        event: String,
        matcher: String?,
        command: String,
        commandType: String?,
        timeout: Int?,
        enabled: Bool,
        scope: ClaudeHookScope,
        sourcePath: String,
        apps: MCPAppToggles = .claudeOnly
    ) {
        self.id = id
        self.event = event
        self.matcher = matcher
        self.command = command
        self.commandType = commandType
        self.timeout = timeout
        self.enabled = enabled
        self.scope = scope
        self.sourcePath = sourcePath
        self.apps = apps
    }

    private enum CodingKeys: String, CodingKey {
        case id
        case event
        case matcher
        case command
        case commandType
        case timeout
        case enabled
        case scope
        case sourcePath
        case apps
    }

    init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        id = try container.decode(String.self, forKey: .id)
        event = try container.decode(String.self, forKey: .event)
        matcher = try container.decodeIfPresent(String.self, forKey: .matcher)
        command = try container.decode(String.self, forKey: .command)
        commandType = try container.decodeIfPresent(String.self, forKey: .commandType)
        timeout = try container.decodeIfPresent(Int.self, forKey: .timeout)
        enabled = try container.decodeIfPresent(Bool.self, forKey: .enabled) ?? true
        scope = try container.decodeIfPresent(ClaudeHookScope.self, forKey: .scope) ?? .user
        sourcePath = try container.decodeIfPresent(String.self, forKey: .sourcePath) ?? ""
        apps = try container.decodeIfPresent(MCPAppToggles.self, forKey: .apps) ?? .claudeOnly
    }

    var enabledAppsText: String {
        apps.displayText
    }

    var identityKey: String {
        [
            id,
            event,
            matcher ?? "",
            command,
            commandType ?? "",
            timeout.map(String.init) ?? "",
            scope.rawValue,
        ].joined(separator: "\u{1f}")
    }

    func supports(app: ProviderAppType) -> Bool {
        switch app {
        case .claude:
            return true
        case .codex:
            return Self.codexSupportedEvents.contains(event)
        case .gemini:
            return Self.geminiSupportedEvents.contains(event)
        }
    }

    private static let codexSupportedEvents: Set<String> = [
        "SessionStart",
        "UserPromptSubmit",
        "Stop",
    ]

    private static let geminiSupportedEvents: Set<String> = [
        "BeforeTool",
        "AfterTool",
        "BeforeAgent",
        "AfterAgent",
        "Notification",
        "SessionStart",
        "SessionEnd",
        "PreCompress",
        "BeforeModel",
        "AfterModel",
        "BeforeToolSelection",
    ]
}

struct SkillStore: Codable, Equatable {
    var version: Int = 2
    var repos: [SkillRepo] = []
    var installedSkills: [InstalledSkill] = []

    private enum CodingKeys: String, CodingKey {
        case version
        case repos
        case installedSkills
    }

    init(version: Int = 2, repos: [SkillRepo] = [], installedSkills: [InstalledSkill] = []) {
        self.version = version
        self.repos = repos
        self.installedSkills = installedSkills
    }

    init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        version = try container.decodeIfPresent(Int.self, forKey: .version) ?? 1
        repos = try container.decodeIfPresent([SkillRepo].self, forKey: .repos) ?? SkillStore.defaultRepos
        installedSkills = try container.decodeIfPresent([InstalledSkill].self, forKey: .installedSkills) ?? []
        if repos.isEmpty {
            repos = SkillStore.defaultRepos
        }
    }

    static var defaultRepos: [SkillRepo] {
        [
            SkillRepo(owner: "anthropics", name: "skills", branch: "main", isEnabled: true, isDefault: true),
            SkillRepo(owner: "ComposioHQ", name: "awesome-claude-skills", branch: "master", isEnabled: true, isDefault: true),
        ]
    }
}

struct HookStore: Codable, Equatable {
    var version: Int = 1
    var hooks: [ClaudeHook] = []
}

// MARK: - Managed Local Services

struct Cursor2APIStatus: Equatable {
    var installed: Bool
    var running: Bool
    var port: Int
    var apiKey: String
    var baseURL: String
    var binaryPath: String?
    var configPath: String?
    var logPath: String?
    var models: [String]
    var lastError: String?

    static let idle = Cursor2APIStatus(
        installed: false,
        running: false,
        port: 8002,
        apiKey: "0000",
        baseURL: "http://127.0.0.1:8002",
        binaryPath: nil,
        configPath: nil,
        logPath: nil,
        models: [],
        lastError: nil
    )
}

struct ManagedPortStatus: Equatable, Identifiable {
    var id: Int { port }
    var port: Int
    var occupied: Bool
    var processID: Int?
    var command: String?
    var endpoint: String?

    static func idle(port: Int) -> ManagedPortStatus {
        ManagedPortStatus(
            port: port,
            occupied: false,
            processID: nil,
            command: nil,
            endpoint: nil
        )
    }
}
