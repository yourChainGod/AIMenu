import Foundation

actor ProviderCoordinator {
    static let managedCodexProxyPresetId = "aimenu.codex.proxy"
    static let managedCodexProxyName = "AIMenu 集中代理"
    static let managedCodexProxyModel = "gpt-5-codex"
    static let managedClaudeCursor2APIPresetId = "aimenu.claude.cursor2api"
    static let managedClaudeCursor2APIName = "Cursor2API 本地桥接"

    private let configService: ProviderConfigService

    init(configService: ProviderConfigService) {
        self.configService = configService
    }

    // MARK: - Provider CRUD

    func listProviders(for app: ProviderAppType) async throws -> [Provider] {
        let store = try await configService.loadProviderStore()
        let currentId = store.currentProviderId(for: app)
        var providers = store.providers(for: app).map { p in
            var provider = p
            provider.isCurrent = provider.id == currentId
            return provider
        }

        guard let currentId,
              let index = providers.firstIndex(where: { $0.id == currentId }) else {
            return providers
        }

        providers[index] = try await applyingLiveOverrides(to: providers[index])
        return providers
    }

    func addProvider(_ provider: Provider) async throws -> ProviderSaveOutcome {
        var store = try await configService.loadProviderStore()
        var newProvider = provider
        newProvider.sortIndex = (store.providers(for: provider.appType).map(\.sortIndex).max() ?? -1) + 1
        let shouldApplyToLiveConfig = store.currentProviderId(for: provider.appType) == nil
        if shouldApplyToLiveConfig {
            store.setCurrentProviderId(newProvider.id, for: provider.appType)
            newProvider.isCurrent = true
        }
        store.providers.append(newProvider)
        try await configService.saveProviderStore(store)
        if shouldApplyToLiveConfig {
            try await configService.switchProvider(newProvider)
        }
        return ProviderSaveOutcome(provider: newProvider, didApplyToLiveConfig: shouldApplyToLiveConfig)
    }

    func updateProvider(_ provider: Provider) async throws -> ProviderSaveOutcome {
        var store = try await configService.loadProviderStore()
        guard let index = store.providers.firstIndex(where: { $0.id == provider.id }) else {
            throw AppError.invalidData(L10n.tr("error.provider.not_found"))
        }
        var updated = provider
        updated.updatedAt = Int64(Date().timeIntervalSince1970)
        let shouldApplyToLiveConfig = store.currentProviderId(for: provider.appType) == provider.id
        updated.isCurrent = shouldApplyToLiveConfig
        store.providers[index] = updated
        try await configService.saveProviderStore(store)
        if shouldApplyToLiveConfig {
            try await configService.switchProvider(updated)
        }
        return ProviderSaveOutcome(provider: updated, didApplyToLiveConfig: shouldApplyToLiveConfig)
    }

    func deleteProvider(id: String, appType: ProviderAppType) async throws -> ProviderDeletionOutcome {
        var store = try await configService.loadProviderStore()
        let wasCurrent = store.currentProviderId(for: appType) == id
        store.providers.removeAll { $0.id == id }
        var fallbackProvider: Provider?
        if wasCurrent {
            fallbackProvider = store.providers(for: appType).first
            store.setCurrentProviderId(fallbackProvider?.id, for: appType)
        }
        try await configService.saveProviderStore(store)
        if wasCurrent {
            if let fallbackProvider {
                try await configService.switchProvider(fallbackProvider)
            } else {
                try await configService.clearProvider(for: appType)
            }
        }
        return ProviderDeletionOutcome(
            didDeleteCurrentProvider: wasCurrent,
            fallbackProvider: fallbackProvider
        )
    }

    func switchProvider(id: String, appType: ProviderAppType) async throws {
        var store = try await configService.loadProviderStore()
        guard let provider = store.providers.first(where: { $0.id == id }) else {
            throw AppError.invalidData(L10n.tr("error.provider.not_found"))
        }
        store.setCurrentProviderId(id, for: appType)
        try await configService.saveProviderStore(store)
        try await configService.switchProvider(provider)
    }

    func upsertManagedCodexProxyProvider(from status: ApiProxyStatus) async throws -> Provider? {
        guard status.running,
              let baseURL = status.baseURL?.trimmedNonEmpty,
              let apiKey = status.apiKey?.trimmedNonEmpty else {
            return nil
        }

        var store = try await configService.loadProviderStore()
        let now = Int64(Date().timeIntervalSince1970)
        let codexProviders = store.providers(for: .codex)

        let managedIndex = store.providers.firstIndex(where: {
            $0.appType == .codex &&
                ($0.presetId == Self.managedCodexProxyPresetId || $0.name == Self.managedCodexProxyName)
        })

        let managedConfig = CodexSettingsConfig(
            apiKey: apiKey,
            baseUrl: baseURL,
            model: Self.managedCodexProxyModel,
            wireApi: "responses",
            reasoningEffort: "medium"
        )

        let provider: Provider
        if let managedIndex {
            var existing = store.providers[managedIndex]
            existing.name = Self.managedCodexProxyName
            existing.category = .custom
            existing.codexConfig = managedConfig
            existing.websiteUrl = nil
            existing.apiKeyUrl = nil
            existing.notes = "由 AIMenu 本地集中代理自动生成，端口和代理密钥变化后会自动同步。"
            existing.icon = "network"
            existing.iconColor = "#1FA67A"
            existing.isPreset = false
            existing.presetId = Self.managedCodexProxyPresetId
            existing.updatedAt = now
            provider = existing
            store.providers[managedIndex] = existing
        } else {
            provider = Provider(
                id: UUID().uuidString,
                name: Self.managedCodexProxyName,
                appType: .codex,
                category: .custom,
                claudeConfig: nil,
                codexConfig: managedConfig,
                geminiConfig: nil,
                websiteUrl: nil,
                apiKeyUrl: nil,
                notes: "由 AIMenu 本地集中代理自动生成，端口和代理密钥变化后会自动同步。",
                icon: "network",
                iconColor: "#1FA67A",
                isPreset: false,
                presetId: Self.managedCodexProxyPresetId,
                sortIndex: (codexProviders.map(\.sortIndex).min() ?? 0) - 1,
                createdAt: now,
                updatedAt: now,
                isCurrent: true,
                proxyConfig: nil,
                billingConfig: nil
            )
            store.providers.append(provider)
        }

        store.setCurrentProviderId(provider.id, for: .codex)
        for index in store.providers.indices where store.providers[index].appType == .codex {
            store.providers[index].isCurrent = store.providers[index].id == provider.id
        }
        try await configService.saveProviderStore(store)
        try await configService.switchProvider(provider)
        return provider
    }

    func upsertManagedClaudeCursor2APIProvider(from status: Cursor2APIStatus) async throws -> Provider? {
        guard status.installed, status.running else {
            return nil
        }

        let baseURL = status.baseURL
        let apiKey = status.apiKey
        let preferredModel = status.models.first?.trimmedNonEmpty ?? "claude-sonnet-4.6"

        var store = try await configService.loadProviderStore()
        let now = Int64(Date().timeIntervalSince1970)
        let claudeProviders = store.providers(for: .claude)

        let managedIndex = store.providers.firstIndex(where: {
            $0.appType == .claude &&
                ($0.presetId == Self.managedClaudeCursor2APIPresetId || $0.name == Self.managedClaudeCursor2APIName)
        })

        let managedConfig = ClaudeSettingsConfig(
            apiKey: apiKey,
            baseUrl: baseURL,
            model: preferredModel,
            haikuModel: nil,
            sonnetModel: nil,
            opusModel: nil,
            maxOutputTokens: nil,
            apiTimeoutMs: nil,
            disableNonessentialTraffic: false,
            hideAttribution: false,
            alwaysThinkingEnabled: false,
            enableTeammates: false,
            apiFormat: .anthropic,
            apiKeyField: .authToken,
            awsRegion: nil,
            awsAccessKeyId: nil,
            awsSecretAccessKey: nil
        )

        let provider: Provider
        if let managedIndex {
            var existing = store.providers[managedIndex]
            existing.name = Self.managedClaudeCursor2APIName
            existing.category = .custom
            existing.claudeConfig = managedConfig
            existing.websiteUrl = nil
            existing.apiKeyUrl = nil
            existing.notes = "由 AIMenu 托管的 Cursor2API 本地服务自动生成，启动后可一键切换到 Claude Code。"
            existing.icon = "bolt.horizontal.circle"
            existing.iconColor = "#3A82F7"
            existing.isPreset = false
            existing.presetId = Self.managedClaudeCursor2APIPresetId
            existing.updatedAt = now
            provider = existing
            store.providers[managedIndex] = existing
        } else {
            provider = Provider(
                id: UUID().uuidString,
                name: Self.managedClaudeCursor2APIName,
                appType: .claude,
                category: .custom,
                claudeConfig: managedConfig,
                codexConfig: nil,
                geminiConfig: nil,
                websiteUrl: nil,
                apiKeyUrl: nil,
                notes: "由 AIMenu 托管的 Cursor2API 本地服务自动生成，启动后可一键切换到 Claude Code。",
                icon: "bolt.horizontal.circle",
                iconColor: "#3A82F7",
                isPreset: false,
                presetId: Self.managedClaudeCursor2APIPresetId,
                sortIndex: (claudeProviders.map(\.sortIndex).min() ?? 0) - 1,
                createdAt: now,
                updatedAt: now,
                isCurrent: true,
                proxyConfig: nil,
                billingConfig: nil
            )
            store.providers.append(provider)
        }

        store.setCurrentProviderId(provider.id, for: .claude)
        for index in store.providers.indices where store.providers[index].appType == .claude {
            store.providers[index].isCurrent = store.providers[index].id == provider.id
        }
        try await configService.saveProviderStore(store)
        try await configService.switchProvider(provider)
        return provider
    }

    // MARK: - Speed Test

    func testSpeed(for provider: Provider) async -> SpeedTestResult {
        let baseUrl: String
        let apiKey: String

        switch provider.appType {
        case .claude:
            baseUrl = provider.claudeConfig?.baseUrl ?? ""
            apiKey = provider.claudeConfig?.apiKey ?? ""
        case .codex:
            baseUrl = provider.codexConfig?.baseUrl ?? ""
            apiKey = provider.codexConfig?.apiKey ?? ""
        case .gemini:
            baseUrl = provider.geminiConfig?.baseUrl ?? ""
            apiKey = provider.geminiConfig?.apiKey ?? ""
        }

        let latency = await configService.testEndpointLatency(
            baseUrl: baseUrl,
            apiKey: apiKey,
            appType: provider.appType
        )

        return SpeedTestResult(
            providerId: provider.id,
            providerName: provider.name,
            latencyMs: latency,
            error: latency == nil ? L10n.tr("providers.speed.connection_failed") : nil,
            testedAt: Date()
        )
    }

    // MARK: - Hooks

    func listClaudeHooks() async throws -> [ClaudeHook] {
        try await effectiveHookStore().hooks
    }

    func loadHookStore() async throws -> HookStore {
        try await effectiveHookStore()
    }

    func saveHookStore(_ store: HookStore) async throws {
        try await configService.saveHookStore(store)
        try await configService.syncHooks(store.hooks)
    }

    func toggleHookApp(hookIdentity: String, app: ProviderAppType, enabled: Bool) async throws {
        var store = try await effectiveHookStore()
        guard let index = store.hooks.firstIndex(where: { $0.identityKey == hookIdentity }) else {
            throw AppError.invalidData(L10n.tr("error.provider.hook_not_found"))
        }
        guard !enabled || store.hooks[index].supports(app: app) else {
            throw AppError.invalidData(
                L10n.tr("error.provider.hook_event_unsupported_format", app.displayName, store.hooks[index].event)
            )
        }

        store.hooks[index].apps.setEnabled(enabled, for: app)
        store.hooks[index].sourcePath = await configService.hookSourceSummary(for: store.hooks[index].apps)
        try await saveHookStore(store)
    }

    // MARK: - Private

    private func applyingLiveOverrides(to provider: Provider) async throws -> Provider {
        var updated = provider

        switch provider.appType {
        case .claude:
            guard var config = updated.claudeConfig,
                  let overrides = try await configService.loadClaudeLiveOverrides() else {
                return updated
            }

            config.maxOutputTokens = overrides.maxOutputTokens
            config.apiTimeoutMs = overrides.apiTimeoutMs
            config.disableNonessentialTraffic = overrides.disableNonessentialTraffic
            config.hideAttribution = overrides.hideAttribution
            config.alwaysThinkingEnabled = overrides.alwaysThinkingEnabled
            config.enableTeammates = overrides.enableTeammates
            config.applyCommonConfig = overrides.applyCommonConfig
            config.commonConfigJSON = overrides.commonConfigJSON
            updated.claudeConfig = config
        case .codex:
            guard var config = updated.codexConfig,
                  let overrides = try await configService.loadCodexLiveOverrides() else {
                return updated
            }

            config.wireApi = overrides.wireApi
            config.reasoningEffort = overrides.reasoningEffort
            updated.codexConfig = config
        case .gemini:
            break
        }

        return updated
    }

    private func effectiveHookStore() async throws -> HookStore {
        var store = try await configService.loadHookStore()
        let liveHooks = try await configService.loadClaudeHooks()
        let hooks = try await mergeHooks(stored: store.hooks, live: liveHooks)
        store.hooks = hooks
        return store
    }

    private func mergeHooks(stored: [ClaudeHook], live: [ClaudeHook]) async throws -> [ClaudeHook] {
        var merged: [String: ClaudeHook] = [:]

        for hook in stored {
            var storedHook = hook
            storedHook.sourcePath = await configService.hookSourceSummary(for: storedHook.apps)
            merged[storedHook.identityKey] = storedHook
        }

        for hook in live {
            let key = hook.identityKey
            if var existing = merged[key] {
                existing.id = existing.id.trimmedNonEmpty ?? hook.id
                existing.enabled = existing.enabled || hook.enabled
                existing.apps = mergeAppToggles(existing.apps, hook.apps)
                existing.sourcePath = await configService.hookSourceSummary(for: existing.apps)
                merged[key] = existing
            } else {
                var liveHook = hook
                liveHook.sourcePath = await configService.hookSourceSummary(for: liveHook.apps)
                merged[key] = liveHook
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

    private func mergeAppToggles(_ lhs: MCPAppToggles, _ rhs: MCPAppToggles) -> MCPAppToggles {
        MCPAppToggles(
            claude: lhs.claude || rhs.claude,
            codex: lhs.codex || rhs.codex,
            gemini: lhs.gemini || rhs.gemini
        )
    }
}
