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

    static let allEnabled = MCPAppToggles(claude: true, codex: true, gemini: true)
    static let claudeOnly = MCPAppToggles(claude: true, codex: false, gemini: false)
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
        return parts.isEmpty ? "无" : parts.joined(separator: ", ")
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
        case .user: return "用户"
        case .project: return "项目"
        }
    }
}

struct ClaudeHook: Equatable, Identifiable {
    var id: String
    var event: String
    var matcher: String?
    var command: String
    var commandType: String?
    var timeout: Int?
    var enabled: Bool
    var scope: ClaudeHookScope
    var sourcePath: String
}

struct SkillStore: Codable, Equatable {
    var version: Int = 1
    var repos: [SkillRepo] = []
    var installedSkills: [InstalledSkill] = []

    static var defaultRepos: [SkillRepo] {
        [
            SkillRepo(owner: "anthropics", name: "skills", branch: "main", isEnabled: true, isDefault: true),
            SkillRepo(owner: "ComposioHQ", name: "awesome-claude-skills", branch: "master", isEnabled: true, isDefault: true),
        ]
    }
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
