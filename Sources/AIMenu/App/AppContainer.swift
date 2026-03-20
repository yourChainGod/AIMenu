import Foundation

@MainActor
struct AppContainer {
    let accountsModel: AccountsPageModel
    let providerModel: ProviderPageModel
    let proxyModel: ProxyPageModel
    let toolsModel: ToolsPageModel
    let settingsModel: SettingsPageModel
    let trayModel: TrayMenuModel

    static func liveOrCrash() -> AppContainer {
        do {
            let paths = try FileSystemPaths.live()
            let storeRepository = StoreFileRepository(paths: paths)
            let authRepository = AuthFileRepository(paths: paths)
            let initialStore = try storeRepository.loadStore()
            let usageService = DefaultUsageService(configPath: paths.codexConfigPath)
            let workspaceMetadataService = DefaultWorkspaceMetadataService(configPath: paths.codexConfigPath)
            let proxyService = SwiftNativeProxyRuntimeService(
                paths: paths,
                storeRepository: storeRepository,
                authRepository: authRepository
            )
            let portManagementService = PortManagementService()
            let cloudflaredService = CloudflaredService(paths: paths)
            let cursor2APIService = Cursor2APIService(
                paths: paths,
                portService: portManagementService
            )
            let chatGPTOAuthLoginService = OpenAIChatGPTOAuthLoginService(configPath: paths.codexConfigPath)
            let codexCLIService = CodexCLIService()
            let editorAppService = EditorAppService()
            let opencodeSyncService = OpencodeAuthSyncService()
            let launchAtStartupService = LaunchAtStartupService()

            // cc-switch provider config service
            let providerConfigService = ProviderConfigService()
            let providerCoordinator = ProviderCoordinator(configService: providerConfigService)
            let mcpCoordinator = MCPCoordinator(configService: providerConfigService)
            let promptCoordinator = PromptCoordinator(configService: providerConfigService)
            let skillCoordinator = SkillCoordinator(configService: providerConfigService)

            let settingsCoordinator = SettingsCoordinator(
                storeRepository: storeRepository,
                launchAtStartupService: launchAtStartupService
            )
            let accountsCoordinator = AccountsCoordinator(
                storeRepository: storeRepository,
                authRepository: authRepository,
                usageService: usageService,
                workspaceMetadataService: workspaceMetadataService,
                chatGPTOAuthLoginService: chatGPTOAuthLoginService,
                codexCLIService: codexCLIService,
                editorAppService: editorAppService,
                opencodeAuthSyncService: opencodeSyncService
            )
            let initialAccounts = initialStore.accountSummaries(
                currentAccountID: authRepository.currentAuthAccountID()
            )
            let proxyCoordinator = ProxyCoordinator(
                proxyService: proxyService,
                cloudflaredService: cloudflaredService,
                providerCoordinator: providerCoordinator
            )
            let trayModel = TrayMenuModel(
                accountsCoordinator: accountsCoordinator,
                settingsCoordinator: settingsCoordinator,
                initialAccounts: initialAccounts
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
                accountsModel: AccountsPageModel(
                    coordinator: accountsCoordinator,
                    manualRefreshService: trayModel,
                    onLocalAccountsChanged: { accounts in
                        trayModel.acceptLocalAccountsSnapshot(accounts)
                    },
                    initialAccounts: initialAccounts
                ),
                providerModel: ProviderPageModel(
                    coordinator: providerCoordinator
                ),
                proxyModel: ProxyPageModel(
                    coordinator: proxyCoordinator,
                    settingsCoordinator: settingsCoordinator
                ),
                toolsModel: ToolsPageModel(
                    providerCoordinator: providerCoordinator,
                    mcpCoordinator: mcpCoordinator,
                    promptCoordinator: promptCoordinator,
                    skillCoordinator: skillCoordinator,
                    cursor2APIService: cursor2APIService,
                    portService: portManagementService
                ),
                settingsModel: settingsModel,
                trayModel: trayModel
            )
        } catch {
            fatalError("Failed to bootstrap Swift migration app: \(error.localizedDescription)")
        }
    }
}
