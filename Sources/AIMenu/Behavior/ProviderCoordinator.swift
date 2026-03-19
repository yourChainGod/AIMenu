import Foundation

actor ProviderCoordinator {
    private struct GitHubTreeResponse: Decodable {
        struct Entry: Decodable {
            let path: String
            let type: String
        }

        let tree: [Entry]
    }

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

    func importLiveMCPServers() async throws -> [MCPServer] {
        let importedServers = try await configService.importLiveMCPServers()
        guard !importedServers.isEmpty else { return try await listMCPServers() }

        var store = try await configService.loadMCPStore()
        let now = Int64(Date().timeIntervalSince1970)

        for imported in importedServers {
            if let existingIndex = store.servers.firstIndex(where: { $0.id == imported.id }) {
                var existing = store.servers[existingIndex]
                existing.name = imported.name
                existing.server = imported.server
                existing.apps = imported.apps
                existing.updatedAt = now
                if existing.description?.trimmedNonEmpty == nil {
                    existing.description = imported.description
                }
                if existing.homepage?.trimmedNonEmpty == nil {
                    existing.homepage = imported.homepage
                }
                if existing.tags == nil || existing.tags?.isEmpty == true {
                    existing.tags = imported.tags
                }
                store.servers[existingIndex] = existing
            } else {
                store.servers.append(imported)
            }
        }

        try await configService.saveMCPStore(store)
        return store.servers.sorted { $0.name.localizedCaseInsensitiveCompare($1.name) == .orderedAscending }
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

    func addSkillRepo(_ repo: SkillRepo) async throws {
        var store = try await configService.loadSkillStore()
        store.repos.removeAll {
            $0.owner.caseInsensitiveCompare(repo.owner) == .orderedSame &&
                $0.name.caseInsensitiveCompare(repo.name) == .orderedSame
        }
        store.repos.append(repo)
        store.repos.sort {
            "\($0.owner)/\($0.name)".localizedCaseInsensitiveCompare("\($1.owner)/\($1.name)") == .orderedAscending
        }
        try await configService.saveSkillStore(store)
    }

    func removeSkillRepo(owner: String, name: String) async throws {
        var store = try await configService.loadSkillStore()
        store.repos.removeAll {
            $0.owner.caseInsensitiveCompare(owner) == .orderedSame &&
                $0.name.caseInsensitiveCompare(name) == .orderedSame
        }
        try await configService.saveSkillStore(store)
    }

    func discoverAvailableSkills() async throws -> [DiscoverableSkill] {
        let store = try await configService.loadSkillStore()
        let installedKeys = Set(store.installedSkills.map(\.key))

        var discovered: [DiscoverableSkill] = []
        var firstError: Error?

        for repo in store.repos where repo.isEnabled {
            do {
                let repoSkills = try await discoverAvailableSkills(in: repo, installedKeys: installedKeys)
                discovered.append(contentsOf: repoSkills)
            } catch {
                if firstError == nil {
                    firstError = error
                }
            }
        }

        let unique = Dictionary(uniqueKeysWithValues: discovered.map { ($0.key, $0) })
        let merged = unique.values.sorted { lhs, rhs in
            if lhs.isInstalled != rhs.isInstalled {
                return !lhs.isInstalled && rhs.isInstalled
            }
            return lhs.name.localizedCaseInsensitiveCompare(rhs.name) == .orderedAscending
        }

        if merged.isEmpty, let firstError {
            throw firstError
        }

        return merged
    }

    func installSkill(_ skill: DiscoverableSkill) async throws {
        let installDir = await configService.skillsInstallDirectory
        let fm = FileManager.default
        try fm.createDirectory(at: installDir, withIntermediateDirectories: true)

        let tempRoot = fm.temporaryDirectory.appendingPathComponent("aimenu-skill-\(UUID().uuidString)")
        let cloneTarget = tempRoot.appendingPathComponent("repo")
        defer { try? fm.removeItem(at: tempRoot) }

        try fm.createDirectory(at: tempRoot, withIntermediateDirectories: true)
        _ = try CommandRunner.runChecked(
            "/usr/bin/env",
            arguments: [
                "git", "clone",
                "--depth=1",
                "--branch", skill.repoBranch,
                "https://github.com/\(skill.repoOwner)/\(skill.repoName).git",
                cloneTarget.path
            ],
            timeout: 45,
            errorPrefix: "克隆技能仓库失败"
        )

        let sourceDirectory = cloneTarget.appendingPathComponent(skill.directory)
        guard fm.fileExists(atPath: sourceDirectory.path) else {
            throw AppError.fileNotFound("技能目录不存在：\(skill.directory)")
        }

        let installName = skill.directory
            .replacingOccurrences(of: "/", with: "__")
            .replacingOccurrences(of: " ", with: "-")
            .lowercased()
        let targetDir = installDir.appendingPathComponent(installName)
        if fm.fileExists(atPath: targetDir.path) {
            try fm.removeItem(at: targetDir)
        }
        try fm.copyItem(at: sourceDirectory, to: targetDir)

        var store = try await configService.loadSkillStore()
        let installed = InstalledSkill(
            key: skill.key,
            name: skill.name,
            description: skill.description,
            directory: installName,
            repoOwner: skill.repoOwner,
            repoName: skill.repoName,
            installedAt: Int64(Date().timeIntervalSince1970)
        )
        store.installedSkills.removeAll { $0.key == skill.key || $0.directory == installName }
        store.installedSkills.append(installed)
        try await configService.saveSkillStore(store)
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

    func syncInstalledSkillsFromDisk() async throws -> [InstalledSkill] {
        let installDir = await configService.skillsInstallDirectory
        let fm = FileManager.default
        try fm.createDirectory(at: installDir, withIntermediateDirectories: true)

        let existingStore = try await configService.loadSkillStore()
        let existingByDirectory = Dictionary(uniqueKeysWithValues: existingStore.installedSkills.map { ($0.directory, $0) })

        let enumerator = fm.enumerator(
            at: installDir,
            includingPropertiesForKeys: [.isRegularFileKey],
            options: [.skipsHiddenFiles]
        )

        var scanned: [InstalledSkill] = []
        while let url = enumerator?.nextObject() as? URL {
            guard url.lastPathComponent == "SKILL.md" else { continue }
            let skillDir = url.deletingLastPathComponent()
            let relativePath = skillDir.path.replacingOccurrences(of: installDir.path + "/", with: "")
            let metadata = parseSkillMetadata(at: url)

            if let existing = existingByDirectory[relativePath] {
                var skill = existing
                if skill.name.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
                    skill.name = metadata.name
                }
                if skill.description?.trimmedNonEmpty == nil {
                    skill.description = metadata.description
                }
                scanned.append(skill)
            } else {
                scanned.append(
                    InstalledSkill(
                        key: "local:\(relativePath)",
                        name: metadata.name,
                        description: metadata.description,
                        directory: relativePath,
                        repoOwner: "",
                        repoName: "",
                        installedAt: Int64(Date().timeIntervalSince1970)
                    )
                )
            }
        }

        let merged = scanned.sorted { $0.name.localizedCaseInsensitiveCompare($1.name) == .orderedAscending }
        var updatedStore = existingStore
        updatedStore.installedSkills = merged
        try await configService.saveSkillStore(updatedStore)
        return merged
    }

    private func parseSkillMetadata(at url: URL) -> (name: String, description: String?) {
        guard let content = try? String(contentsOf: url, encoding: .utf8) else {
            return (url.deletingLastPathComponent().lastPathComponent, nil)
        }

        return parseSkillMetadata(from: content, fallbackName: url.deletingLastPathComponent().lastPathComponent)
    }

    private func discoverAvailableSkills(
        in repo: SkillRepo,
        installedKeys: Set<String>
    ) async throws -> [DiscoverableSkill] {
        let tree = try await fetchGitHubTree(owner: repo.owner, repo: repo.name, branch: repo.branch)
        let skillPaths = tree
            .filter { $0.type == "blob" && $0.path.hasSuffix("SKILL.md") }
            .map(\.path)

        var discovered: [DiscoverableSkill] = []
        for skillPath in skillPaths {
            let directory = String(skillPath.dropLast("/SKILL.md".count))
            let fallbackName = directory.components(separatedBy: "/").last ?? directory
            let content = try? await fetchGitHubFile(
                owner: repo.owner,
                repo: repo.name,
                branch: repo.branch,
                path: skillPath
            )
            let metadata: (name: String, description: String?) = content.map {
                parseSkillMetadata(from: $0, fallbackName: fallbackName)
            } ?? (
                name: prettifiedSkillName(from: fallbackName),
                description: nil
            )

            let key = "\(repo.owner)/\(repo.name):\(directory)"
            discovered.append(
                DiscoverableSkill(
                    key: key,
                    name: metadata.name,
                    description: metadata.description,
                    readmeUrl: "https://github.com/\(repo.owner)/\(repo.name)/tree/\(repo.branch)/\(directory)",
                    repoOwner: repo.owner,
                    repoName: repo.name,
                    repoBranch: repo.branch,
                    directory: directory,
                    isInstalled: installedKeys.contains(key)
                )
            )
        }

        return discovered
    }

    private func fetchGitHubTree(owner: String, repo: String, branch: String) async throws -> [GitHubTreeResponse.Entry] {
        guard let url = URL(string: "https://api.github.com/repos/\(owner)/\(repo)/git/trees/\(branch)?recursive=1") else {
            throw AppError.invalidData("技能仓库地址无效")
        }

        var request = URLRequest(url: url)
        request.setValue("AIMenu/1.0", forHTTPHeaderField: "User-Agent")
        request.setValue("application/vnd.github+json", forHTTPHeaderField: "Accept")

        let (data, response) = try await URLSession.shared.data(for: request)
        if let httpResponse = response as? HTTPURLResponse, !(200..<300).contains(httpResponse.statusCode) {
            throw AppError.io("读取技能仓库目录失败：HTTP \(httpResponse.statusCode)")
        }

        let payload = try JSONDecoder().decode(GitHubTreeResponse.self, from: data)
        return payload.tree
    }

    private func fetchGitHubFile(owner: String, repo: String, branch: String, path: String) async throws -> String {
        guard let url = URL(string: "https://raw.githubusercontent.com/\(owner)/\(repo)/\(branch)/\(path)") else {
            throw AppError.invalidData("技能文件地址无效")
        }

        var request = URLRequest(url: url)
        request.setValue("AIMenu/1.0", forHTTPHeaderField: "User-Agent")

        let (data, response) = try await URLSession.shared.data(for: request)
        if let httpResponse = response as? HTTPURLResponse, !(200..<300).contains(httpResponse.statusCode) {
            throw AppError.io("读取技能说明失败：HTTP \(httpResponse.statusCode)")
        }

        guard let content = String(data: data, encoding: .utf8) else {
            throw AppError.invalidData("技能说明文件不是 UTF-8 编码")
        }
        return content
    }

    private func parseSkillMetadata(from content: String, fallbackName: String) -> (name: String, description: String?) {
        let lines = content.components(separatedBy: .newlines)
        let title = (
            lines.first(where: { $0.trimmingCharacters(in: .whitespaces).hasPrefix("#") })
                .map { $0.replacingOccurrences(of: "#", with: "").trimmingCharacters(in: .whitespacesAndNewlines) }
        )?.trimmedNonEmpty ?? prettifiedSkillName(from: fallbackName)

        let description = lines
            .map { $0.trimmingCharacters(in: .whitespacesAndNewlines) }
            .first(where: { !$0.isEmpty && !$0.hasPrefix("#") })

        return (title, description)
    }

    private func prettifiedSkillName(from value: String) -> String {
        value
            .replacingOccurrences(of: "-", with: " ")
            .replacingOccurrences(of: "_", with: " ")
            .split(separator: " ")
            .map { fragment in
                guard let first = fragment.first else { return "" }
                return String(first).uppercased() + String(fragment.dropFirst())
            }
            .joined(separator: " ")
    }
}
