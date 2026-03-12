import Foundation

enum AppTab: String, CaseIterable, Identifiable {
    case accounts
    case proxy
    case settings

    var id: String { rawValue }
}

struct AccountsStore: Codable, Equatable {
    var version: Int = 1
    var accounts: [StoredAccount] = []
    var settings: AppSettings = .defaultValue
}

struct StoredAccount: Codable, Equatable, Identifiable {
    var id: String
    var label: String
    var email: String?
    var accountID: String
    var planType: String?
    var teamName: String?
    var teamAlias: String?
    var authJSON: JSONValue
    var addedAt: Int64
    var updatedAt: Int64
    var usage: UsageSnapshot?
    var usageError: String?

    enum CodingKeys: String, CodingKey {
        case id
        case label
        case email
        case accountID = "accountId"
        case planType
        case teamName
        case teamAlias
        case authJSON = "authJson"
        case addedAt
        case updatedAt
        case usage
        case usageError
    }
}

struct AccountSummary: Equatable, Identifiable {
    var id: String
    var label: String
    var email: String?
    var accountID: String
    var planType: String?
    var teamName: String?
    var teamAlias: String?
    var addedAt: Int64
    var updatedAt: Int64
    var usage: UsageSnapshot?
    var usageError: String?
    var isCurrent: Bool

    var displayTeamName: String? {
        if let alias = teamAlias?.trimmingCharacters(in: .whitespacesAndNewlines),
           !alias.isEmpty {
            return alias
        }
        if let teamName = teamName?.trimmingCharacters(in: .whitespacesAndNewlines),
           !teamName.isEmpty {
            return teamName
        }
        return nil
    }
}

struct UsageSnapshot: Codable, Equatable {
    var fetchedAt: Int64
    var planType: String?
    var fiveHour: UsageWindow?
    var oneWeek: UsageWindow?
    var credits: CreditSnapshot?
}

struct UsageWindow: Codable, Equatable {
    var usedPercent: Double
    var windowSeconds: Int64
    var resetAt: Int64?
}

struct CreditSnapshot: Codable, Equatable {
    var hasCredits: Bool
    var unlimited: Bool
    var balance: String?
}

struct ExtractedAuth: Equatable {
    var accountID: String
    var accessToken: String
    var email: String?
    var planType: String?
    var teamName: String?
}

enum TrayUsageDisplayMode: String, Codable, CaseIterable {
    case remaining
    case used
    case hidden
}

enum EditorAppID: String, Codable, CaseIterable, Identifiable {
    case vscode
    case vscodeInsiders
    case cursor
    case antigravity
    case kiro
    case trae
    case qoder

    var id: String { rawValue }
}

struct InstalledEditorApp: Equatable, Identifiable {
    var id: EditorAppID
    var label: String
}

struct SwitchAccountExecutionResult: Equatable {
    var usedFallbackCLI: Bool
    var opencodeSynced: Bool
    var opencodeSyncError: String?
    var restartedEditorApps: [EditorAppID]
    var editorRestartError: String?

    static let idle = SwitchAccountExecutionResult(
        usedFallbackCLI: false,
        opencodeSynced: false,
        opencodeSyncError: nil,
        restartedEditorApps: [],
        editorRestartError: nil
    )
}

struct RemoteServerConfig: Codable, Equatable, Identifiable {
    var id: String
    var label: String
    var host: String
    var sshPort: Int
    var sshUser: String
    var authMode: String
    var identityFile: String?
    var privateKey: String?
    var password: String?
    var remoteDir: String
    var listenPort: Int
}

struct AppSettings: Codable, Equatable {
    var launchAtStartup: Bool
    var trayUsageDisplayMode: TrayUsageDisplayMode
    var launchCodexAfterSwitch: Bool
    var syncOpencodeOpenaiAuth: Bool
    var restartEditorsOnSwitch: Bool
    var restartEditorTargets: [EditorAppID]
    var autoStartApiProxy: Bool
    var remoteServers: [RemoteServerConfig]
    var locale: String

    static let defaultValue = AppSettings(
        launchAtStartup: false,
        trayUsageDisplayMode: .remaining,
        launchCodexAfterSwitch: true,
        syncOpencodeOpenaiAuth: false,
        restartEditorsOnSwitch: false,
        restartEditorTargets: [],
        autoStartApiProxy: false,
        remoteServers: [],
        locale: AppLocale.simplifiedChinese.identifier
    )
}

struct AppSettingsPatch {
    var launchAtStartup: Bool? = nil
    var trayUsageDisplayMode: TrayUsageDisplayMode? = nil
    var launchCodexAfterSwitch: Bool? = nil
    var syncOpencodeOpenaiAuth: Bool? = nil
    var restartEditorsOnSwitch: Bool? = nil
    var restartEditorTargets: [EditorAppID]? = nil
    var autoStartApiProxy: Bool? = nil
    var remoteServers: [RemoteServerConfig]? = nil
    var locale: String? = nil
}

struct ApiProxyStatus: Equatable {
    var running: Bool
    var port: Int?
    var apiKey: String?
    var baseURL: String?
    var availableAccounts: Int
    var activeAccountID: String?
    var activeAccountLabel: String?
    var lastError: String?

    static let idle = ApiProxyStatus(
        running: false,
        port: nil,
        apiKey: nil,
        baseURL: nil,
        availableAccounts: 0,
        activeAccountID: nil,
        activeAccountLabel: nil,
        lastError: nil
    )
}

enum CloudflaredTunnelMode: String, Codable, CaseIterable {
    case quick
    case named
}

struct StartCloudflaredTunnelInput: Equatable {
    var apiProxyPort: Int
    var useHTTP2: Bool
    var mode: CloudflaredTunnelMode
    var hostname: String?
}

struct CloudflaredStatus: Equatable {
    var installed: Bool
    var binaryPath: String?
    var running: Bool
    var tunnelMode: CloudflaredTunnelMode?
    var publicURL: String?
    var customHostname: String?
    var useHTTP2: Bool
    var lastError: String?

    static let idle = CloudflaredStatus(
        installed: false,
        binaryPath: nil,
        running: false,
        tunnelMode: nil,
        publicURL: nil,
        customHostname: nil,
        useHTTP2: false,
        lastError: nil
    )
}

struct RemoteProxyStatus: Equatable {
    var installed: Bool
    var serviceInstalled: Bool
    var running: Bool
    var enabled: Bool
    var serviceName: String
    var pid: Int?
    var baseURL: String
    var apiKey: String?
    var lastError: String?
}

struct PendingUpdateInfo: Equatable {
    var currentVersion: String
    var latestVersion: String
    var releaseURL: String
    var notes: String?
    var publishedAt: String?
}
