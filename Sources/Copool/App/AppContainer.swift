import Foundation

@MainActor
struct AppContainer {
    let accountsModel: AccountsPageModel
    let proxyModel: ProxyPageModel
    let settingsModel: SettingsPageModel
    let trayModel: TrayMenuModel

    static func liveOrCrash() -> AppContainer {
        do {
            let paths = try FileSystemPaths.live()
            let storeRepository = StoreFileRepository(paths: paths)
            let authRepository = AuthFileRepository(paths: paths)
            let usageService = DefaultUsageService(configPath: paths.codexConfigPath)
            let proxyService = SwiftNativeProxyRuntimeService(
                paths: paths,
                storeRepository: storeRepository,
                authRepository: authRepository
            )
            let cloudflaredService = CloudflaredService(paths: paths)
            let remoteService: RemoteProxyServiceProtocol
            if let repoRoot = RepositoryLocator.findRepoRoot(startingAt: URL(fileURLWithPath: #filePath)) {
                remoteService = RemoteProxyService(
                    repoRoot: repoRoot,
                    sourceAccountStorePath: paths.accountStorePath
                )
            } else {
                remoteService = UnavailableRemoteProxyService(
                    unavailableReason: L10n.tr("error.remote.unavailable_missing_proxyd_source")
                )
            }
            let codexCLIService = CodexCLIService()
            let editorAppService = EditorAppService()
            let opencodeSyncService = OpencodeAuthSyncService()
            let launchAtStartupService = LaunchAtStartupService()

            let settingsCoordinator = SettingsCoordinator(
                storeRepository: storeRepository,
                launchAtStartupService: launchAtStartupService
            )
            let accountsCoordinator = AccountsCoordinator(
                storeRepository: storeRepository,
                authRepository: authRepository,
                usageService: usageService,
                codexCLIService: codexCLIService,
                editorAppService: editorAppService,
                opencodeAuthSyncService: opencodeSyncService
            )
            let proxyCoordinator = ProxyCoordinator(
                proxyService: proxyService,
                cloudflaredService: cloudflaredService,
                remoteService: remoteService
            )
            let trayModel = TrayMenuModel(
                accountsCoordinator: accountsCoordinator,
                settingsCoordinator: settingsCoordinator
            )
            let settingsModel = SettingsPageModel(
                settingsCoordinator: settingsCoordinator,
                editorAppService: editorAppService,
                onSettingsUpdated: { settings in
                    trayModel.applySettings(settings)
                }
            )

            Task {
                do {
                    try await settingsCoordinator.syncLaunchAtStartupFromStore()
                } catch {
                    // Keep launch non-blocking even if system login item sync fails.
                }
            }

            return AppContainer(
                accountsModel: AccountsPageModel(coordinator: accountsCoordinator),
                proxyModel: ProxyPageModel(
                    coordinator: proxyCoordinator,
                    settingsCoordinator: settingsCoordinator
                ),
                settingsModel: settingsModel,
                trayModel: trayModel
            )
        } catch {
            fatalError("Failed to bootstrap Swift migration app: \(error.localizedDescription)")
        }
    }
}

private actor UnavailableRemoteProxyService: RemoteProxyServiceProtocol {
    private let unavailableReason: String

    init(unavailableReason: String) {
        self.unavailableReason = unavailableReason
    }

    func status(server: RemoteServerConfig) async -> RemoteProxyStatus {
        RemoteProxyStatus(
            installed: false,
            serviceInstalled: false,
            running: false,
            enabled: false,
            serviceName: "codex-tools-proxyd-\(safeFragment(server.id)).service",
            pid: nil,
            baseURL: "http://\(server.host):\(server.listenPort)/v1",
            apiKey: nil,
            lastError: unavailableReason
        )
    }

    func deploy(server _: RemoteServerConfig) async throws -> RemoteProxyStatus {
        throw AppError.io(unavailableReason)
    }

    func start(server _: RemoteServerConfig) async throws -> RemoteProxyStatus {
        throw AppError.io(unavailableReason)
    }

    func stop(server _: RemoteServerConfig) async throws -> RemoteProxyStatus {
        throw AppError.io(unavailableReason)
    }

    func readLogs(server _: RemoteServerConfig, lines _: Int) async throws -> String {
        throw AppError.io(unavailableReason)
    }

    private func safeFragment(_ input: String) -> String {
        let transformed = input
            .lowercased()
            .map { char -> Character in
                if char.isLetter || char.isNumber {
                    return char
                }
                return "-"
            }
        let collapsed = String(transformed)
            .replacingOccurrences(of: "--+", with: "-", options: .regularExpression)
            .trimmingCharacters(in: CharacterSet(charactersIn: "-"))
        return collapsed.isEmpty ? "remote" : collapsed
    }
}
