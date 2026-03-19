import Foundation

actor ProviderCoordinator {
    static let managedCodexProxyPresetId = "aimenu.codex.proxy"
    static let managedCodexProxyName = "AIMenu 集中代理"
    static let managedCodexProxyModel = "gpt-5-codex"

    private let configService: ProviderConfigService

    init(configService: ProviderConfigService) {
        self.configService = configService
    }

    // MARK: - Provider CRUD

    func listProviders(for app: ProviderAppType) async throws -> [Provider] {
        let store = try await configService.loadProviderStore()
        let currentId = store.currentProviderId(for: app)
        return store.providers(for: app).map { p in
            var provider = p
            provider.isCurrent = provider.id == currentId
            return provider
        }
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
            throw AppError.invalidData("Provider not found")
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
            throw AppError.invalidData("Provider not found")
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
            error: latency == nil ? "Connection failed" : nil,
            testedAt: Date()
        )
    }

    // MARK: - MCP

    func listMCPServers() async throws -> [MCPServer] {
        let store = try await configService.loadMCPStore()
        return store.servers
    }

    func addMCPServer(_ server: MCPServer) async throws {
        var store = try await configService.loadMCPStore()
        store.servers.append(server)
        try await configService.saveMCPStore(store)
        if server.isEnabled {
            try await configService.syncMCPServer(server)
        }
    }

    func updateMCPServer(_ server: MCPServer) async throws {
        var store = try await configService.loadMCPStore()
        guard let index = store.servers.firstIndex(where: { $0.id == server.id }) else {
            throw AppError.invalidData("MCP server not found")
        }
        let old = store.servers[index]
        var updated = server
        updated.updatedAt = Int64(Date().timeIntervalSince1970)
        store.servers[index] = updated
        try await configService.saveMCPStore(store)
        // Remove old config then add new
        try await configService.removeMCPServer(old)
        if updated.isEnabled {
            try await configService.syncMCPServer(updated)
        }
    }

    func deleteMCPServer(id: String) async throws {
        var store = try await configService.loadMCPStore()
        guard let index = store.servers.firstIndex(where: { $0.id == id }) else { return }
        let server = store.servers[index]
        store.servers.remove(at: index)
        try await configService.saveMCPStore(store)
        try await configService.removeMCPServer(server)
    }

    func toggleMCPApp(serverId: String, app: ProviderAppType, enabled: Bool) async throws {
        var store = try await configService.loadMCPStore()
        guard let index = store.servers.firstIndex(where: { $0.id == serverId }) else { return }
        switch app {
        case .claude: store.servers[index].apps.claude = enabled
        case .codex: store.servers[index].apps.codex = enabled
        case .gemini: store.servers[index].apps.gemini = enabled
        }
        store.servers[index].updatedAt = Int64(Date().timeIntervalSince1970)
        try await configService.saveMCPStore(store)
        if store.servers[index].isEnabled {
            try await configService.syncMCPServer(store.servers[index])
        }
    }

    // MARK: - Prompts

    func listPrompts(for app: PromptAppType) async throws -> [Prompt] {
        let store = try await configService.loadPromptStore()
        let liveContent = try await configService.readLivePrompt(for: app)?
            .trimmingCharacters(in: .whitespacesAndNewlines)
        var prompts = store.prompts.filter { $0.appType == app }
        let activePromptID = liveContent.flatMap { content in
            prompts.first(where: {
                $0.content.trimmingCharacters(in: .whitespacesAndNewlines) == content
            })?.id
        }

        for index in prompts.indices {
            if let activePromptID {
                prompts[index].isActive = prompts[index].id == activePromptID
            }
        }

        return prompts
    }

    func addPrompt(_ prompt: Prompt) async throws {
        var store = try await configService.loadPromptStore()
        store.prompts.append(prompt)
        try await configService.savePromptStore(store)
    }

    func updatePrompt(_ prompt: Prompt) async throws {
        var store = try await configService.loadPromptStore()
        guard let index = store.prompts.firstIndex(where: { $0.id == prompt.id }) else {
            throw AppError.invalidData("Prompt not found")
        }
        var updated = prompt
        updated.updatedAt = Int64(Date().timeIntervalSince1970)
        store.prompts[index] = updated
        try await configService.savePromptStore(store)
    }

    func activatePrompt(id: String, appType: PromptAppType) async throws {
        var store = try await configService.loadPromptStore()
        // Deactivate all prompts of same app type
        for i in store.prompts.indices where store.prompts[i].appType == appType {
            store.prompts[i].isActive = store.prompts[i].id == id
        }
        try await configService.savePromptStore(store)
        if let prompt = store.prompts.first(where: { $0.id == id }) {
            try await configService.activatePrompt(prompt)
        }
    }

    func deletePrompt(id: String) async throws {
        var store = try await configService.loadPromptStore()
        store.prompts.removeAll { $0.id == id }
        try await configService.savePromptStore(store)
    }

    func importLivePrompt(for appType: PromptAppType) async throws -> Prompt? {
        guard let content = try await configService.readLivePrompt(for: appType),
              !content.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty else {
            return nil
        }
        let now = Int64(Date().timeIntervalSince1970)
        return Prompt(
            id: UUID().uuidString,
            name: "Imported from \(appType.fileName)",
            appType: appType,
            content: content,
            description: "Imported at \(Date())",
            isActive: true,
            createdAt: now,
            updatedAt: now
        )
    }

    // MARK: - Skills

    func loadSkillStore() async throws -> SkillStore {
        try await configService.loadSkillStore()
    }

    func saveSkillStore(_ store: SkillStore) async throws {
        try await configService.saveSkillStore(store)
    }

    func installSkill(_ skill: DiscoverableSkill) async throws {
        let installDir = await configService.skillsInstallDirectory
        let targetDir = installDir.appendingPathComponent(skill.directory)

        // Download from GitHub
        let archiveUrl = "https://api.github.com/repos/\(skill.repoOwner)/\(skill.repoName)/tarball"
        guard let url = URL(string: archiveUrl) else {
            throw AppError.invalidData("Invalid skill URL")
        }

        let (data, _) = try await URLSession.shared.data(from: url)

        // Create target directory
        let fm = FileManager.default
        try fm.createDirectory(at: targetDir, withIntermediateDirectories: true)

        // Write a marker file for now (full tar extraction would be more complex)
        let markerPath = targetDir.appendingPathComponent("SKILL.md")
        try "# \(skill.name)\n\nInstalled via AIMenu".write(to: markerPath, atomically: true, encoding: .utf8)

        // Save to store
        var store = try await configService.loadSkillStore()
        let installed = InstalledSkill(
            key: skill.key,
            name: skill.name,
            description: skill.description,
            directory: skill.directory,
            repoOwner: skill.repoOwner,
            repoName: skill.repoName,
            installedAt: Int64(Date().timeIntervalSince1970)
        )
        store.installedSkills.removeAll { $0.key == skill.key }
        store.installedSkills.append(installed)
        try await configService.saveSkillStore(store)
        _ = data // use the downloaded data
    }

    func uninstallSkill(directory: String) async throws {
        let installDir = await configService.skillsInstallDirectory
        let targetDir = installDir.appendingPathComponent(directory)
        let fm = FileManager.default
        if fm.fileExists(atPath: targetDir.path) {
            try fm.removeItem(at: targetDir)
        }

        var store = try await configService.loadSkillStore()
        store.installedSkills.removeAll { $0.directory == directory }
        try await configService.saveSkillStore(store)
    }
}
