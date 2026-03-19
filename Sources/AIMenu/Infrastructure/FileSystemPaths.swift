import Foundation

struct FileSystemPaths {
    static let appSupportDirectoryName = "AIMenu"
    static let legacyAppSupportDirectoryName = "CodexToolsSwift"

    var applicationSupportDirectory: URL
    var accountStorePath: URL
    var codexAuthPath: URL
    var codexConfigPath: URL
    var proxyDaemonDataDirectory: URL
    var proxyDaemonKeyPath: URL
    var cloudflaredLogDirectory: URL
    var managedToolsDirectory: URL
    var cursor2APIDirectory: URL
    var cursor2APIBinaryPath: URL
    var cursor2APIConfigPath: URL
    var cursor2APILogDirectory: URL

    init(
        applicationSupportDirectory: URL,
        accountStorePath: URL,
        codexAuthPath: URL,
        codexConfigPath: URL,
        proxyDaemonDataDirectory: URL,
        proxyDaemonKeyPath: URL,
        cloudflaredLogDirectory: URL,
        managedToolsDirectory: URL? = nil,
        cursor2APIDirectory: URL? = nil,
        cursor2APIBinaryPath: URL? = nil,
        cursor2APIConfigPath: URL? = nil,
        cursor2APILogDirectory: URL? = nil
    ) {
        let resolvedManagedToolsDirectory = managedToolsDirectory
            ?? applicationSupportDirectory.appendingPathComponent("managed-tools", isDirectory: true)
        let resolvedCursor2APIDirectory = cursor2APIDirectory
            ?? resolvedManagedToolsDirectory.appendingPathComponent("cursor2api-go", isDirectory: true)

        self.applicationSupportDirectory = applicationSupportDirectory
        self.accountStorePath = accountStorePath
        self.codexAuthPath = codexAuthPath
        self.codexConfigPath = codexConfigPath
        self.proxyDaemonDataDirectory = proxyDaemonDataDirectory
        self.proxyDaemonKeyPath = proxyDaemonKeyPath
        self.cloudflaredLogDirectory = cloudflaredLogDirectory
        self.managedToolsDirectory = resolvedManagedToolsDirectory
        self.cursor2APIDirectory = resolvedCursor2APIDirectory
        self.cursor2APIBinaryPath = cursor2APIBinaryPath
            ?? resolvedCursor2APIDirectory.appendingPathComponent("cursor2api-go", isDirectory: false)
        self.cursor2APIConfigPath = cursor2APIConfigPath
            ?? resolvedCursor2APIDirectory.appendingPathComponent("config.yaml", isDirectory: false)
        self.cursor2APILogDirectory = cursor2APILogDirectory
            ?? resolvedCursor2APIDirectory.appendingPathComponent("logs", isDirectory: true)
    }

    init(
        applicationSupportDirectory: URL,
        accountStorePath: URL,
        codexAuthPath: URL,
        codexConfigPath: URL,
        proxyDaemonDataDirectory: URL,
        proxyDaemonKeyPath: URL,
        cloudflaredLogDirectory: URL
    ) {
        self.init(
            applicationSupportDirectory: applicationSupportDirectory,
            accountStorePath: accountStorePath,
            codexAuthPath: codexAuthPath,
            codexConfigPath: codexConfigPath,
            proxyDaemonDataDirectory: proxyDaemonDataDirectory,
            proxyDaemonKeyPath: proxyDaemonKeyPath,
            cloudflaredLogDirectory: cloudflaredLogDirectory,
            managedToolsDirectory: nil,
            cursor2APIDirectory: nil,
            cursor2APIBinaryPath: nil,
            cursor2APIConfigPath: nil,
            cursor2APILogDirectory: nil
        )
    }

    static func live(fileManager: FileManager = .default) throws -> FileSystemPaths {
        let appSupportBase = try fileManager.url(
            for: .applicationSupportDirectory,
            in: .userDomainMask,
            appropriateFor: nil,
            create: true
        )

        let appSupportDirectory = resolveAppSupportDirectory(
            baseDirectory: appSupportBase,
            fileManager: fileManager
        )
        let homeDirectory = fileManager.homeDirectoryForCurrentUser
        let codexDirectory = homeDirectory.appendingPathComponent(".codex", isDirectory: true)
        let proxyDaemonDataDirectory = homeDirectory.appendingPathComponent(".codex-tools-proxyd", isDirectory: true)
        let cloudflaredLogDirectory = appSupportDirectory.appendingPathComponent("cloudflared-logs", isDirectory: true)
        let managedToolsDirectory = appSupportDirectory.appendingPathComponent("managed-tools", isDirectory: true)
        let cursor2APIDirectory = managedToolsDirectory.appendingPathComponent("cursor2api-go", isDirectory: true)
        let cursor2APILogDirectory = cursor2APIDirectory.appendingPathComponent("logs", isDirectory: true)

        return FileSystemPaths(
            applicationSupportDirectory: appSupportDirectory,
            accountStorePath: appSupportDirectory.appendingPathComponent("accounts.json", isDirectory: false),
            codexAuthPath: codexDirectory.appendingPathComponent("auth.json", isDirectory: false),
            codexConfigPath: codexDirectory.appendingPathComponent("config.toml", isDirectory: false),
            proxyDaemonDataDirectory: proxyDaemonDataDirectory,
            proxyDaemonKeyPath: proxyDaemonDataDirectory.appendingPathComponent("api-proxy.key", isDirectory: false),
            cloudflaredLogDirectory: cloudflaredLogDirectory,
            managedToolsDirectory: managedToolsDirectory,
            cursor2APIDirectory: cursor2APIDirectory,
            cursor2APIBinaryPath: cursor2APIDirectory.appendingPathComponent("cursor2api-go", isDirectory: false),
            cursor2APIConfigPath: cursor2APIDirectory.appendingPathComponent("config.yaml", isDirectory: false),
            cursor2APILogDirectory: cursor2APILogDirectory
        )
    }

    private static func resolveAppSupportDirectory(baseDirectory: URL, fileManager: FileManager) -> URL {
        let current = baseDirectory.appendingPathComponent(appSupportDirectoryName, isDirectory: true)
        let legacy = baseDirectory.appendingPathComponent(legacyAppSupportDirectoryName, isDirectory: true)

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
}
