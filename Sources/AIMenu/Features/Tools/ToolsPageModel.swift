import Foundation
import Combine

@MainActor
final class ToolsPageModel: ObservableObject {
    private let defaultTrackedPorts = [8002, 8787]
    private let coordinator: ProviderCoordinator
    private let cursor2APIService: Cursor2APIServiceProtocol
    private let portService: PortManagementServiceProtocol
    private let noticeScheduler = NoticeAutoDismissScheduler()

    enum ToolsSection: String, CaseIterable { case configs, mcp, prompts, hooks, skills }

    @Published var activeSection: ToolsSection = .mcp
    @Published var localConfigBundles: [LocalConfigBundle] = []
    @Published var mcpServers: [MCPServer] = []
    @Published var prompts: [Prompt] = []
    @Published var selectedPromptApp: PromptAppType = .claude
    @Published var claudeHooks: [ClaudeHook] = []
    @Published var skills: SkillStore = SkillStore(repos: SkillStore.defaultRepos)
    @Published var discoverableSkills: [DiscoverableSkill] = []
    @Published var previewingDiscoverableSkillDocument: DiscoverableSkillPreviewDocument?
    @Published var previewingDiscoverableSkillKey: String?
    @Published var editingInstalledSkillDocument: InstalledSkillDocument?
    @Published var skillDiscoveryLoading = false
    @Published var cursor2APIStatus: Cursor2APIStatus = .idle
    @Published var trackedPortNumbers: [Int] = [8002, 8787]
    @Published var trackedPorts: [ManagedPortStatus] = [.idle(port: 8002), .idle(port: 8787)]
    @Published var customPortText = "3000"
    @Published var loading = false
    @Published var notice: NoticeMessage? {
        didSet { noticeScheduler.schedule(notice) { [weak self] in self?.notice = nil } }
    }

    init(
        coordinator: ProviderCoordinator,
        cursor2APIService: Cursor2APIServiceProtocol,
        portService: PortManagementServiceProtocol
    ) {
        self.coordinator = coordinator
        self.cursor2APIService = cursor2APIService
        self.portService = portService
    }

    func load() async {
        loading = true
        defer { loading = false }
        do {
            localConfigBundles = try await coordinator.listLocalConfigBundles()
            mcpServers = try await coordinator.listMCPServers()
            prompts = try await coordinator.listPrompts(for: selectedPromptApp)
            claudeHooks = try await coordinator.listClaudeHooks()
            var skillStore = try await coordinator.loadSkillStore()
            skillStore.installedSkills = try await coordinator.listInstalledSkills()
            skills = skillStore
            await refreshManagedToolStatus()
        } catch {
            notice = NoticeMessage(style: .error, text: error.localizedDescription)
        }
    }

    // MARK: - MCP

    func addMCPFromPreset(_ preset: MCPPreset) async {
        let server = preset.makeServer()
        do {
            try await coordinator.addMCPServer(server)
            mcpServers = try await coordinator.listMCPServers()
            localConfigBundles = try await coordinator.listLocalConfigBundles()
            notice = NoticeMessage(style: .success, text: "已添加 MCP：\(server.name)")
        } catch {
            notice = NoticeMessage(style: .error, text: error.localizedDescription)
        }
    }

    func saveMCPServer(_ server: MCPServer) async {
        do {
            if mcpServers.contains(where: { $0.id == server.id }) {
                try await coordinator.updateMCPServer(server)
                notice = NoticeMessage(style: .success, text: "MCP 服务器已更新")
            } else {
                try await coordinator.addMCPServer(server)
                notice = NoticeMessage(style: .success, text: "MCP 服务器已添加")
            }
            mcpServers = try await coordinator.listMCPServers()
            localConfigBundles = try await coordinator.listLocalConfigBundles()
        } catch {
            notice = NoticeMessage(style: .error, text: error.localizedDescription)
        }
    }

    func deleteMCPServer(id: String) async {
        do {
            try await coordinator.deleteMCPServer(id: id)
            mcpServers = try await coordinator.listMCPServers()
            localConfigBundles = try await coordinator.listLocalConfigBundles()
            notice = NoticeMessage(style: .info, text: "MCP 服务器已移除")
        } catch {
            notice = NoticeMessage(style: .error, text: error.localizedDescription)
        }
    }

    func importLiveMCPServers() async {
        do {
            mcpServers = try await coordinator.importLiveMCPServers()
            localConfigBundles = try await coordinator.listLocalConfigBundles()
            notice = NoticeMessage(style: .success, text: "已导入本地 MCP 配置")
        } catch {
            notice = NoticeMessage(style: .error, text: error.localizedDescription)
        }
    }

    func toggleMCPApp(serverId: String, app: ProviderAppType, enabled: Bool) async {
        do {
            try await coordinator.toggleMCPApp(serverId: serverId, app: app, enabled: enabled)
            mcpServers = try await coordinator.listMCPServers()
            localConfigBundles = try await coordinator.listLocalConfigBundles()
        } catch {
            notice = NoticeMessage(style: .error, text: error.localizedDescription)
        }
    }

    // MARK: - Local Config Overview

    func refreshLocalConfigBundles(showNotice: Bool = true) async {
        do {
            localConfigBundles = try await coordinator.listLocalConfigBundles()
            if showNotice {
                notice = NoticeMessage(style: .success, text: "已刷新本地配置概览")
            }
        } catch {
            notice = NoticeMessage(style: .error, text: error.localizedDescription)
        }
    }

    // MARK: - Prompts

    func switchPromptApp(_ app: PromptAppType) async {
        selectedPromptApp = app
        do {
            prompts = try await coordinator.listPrompts(for: app)
        } catch {
            notice = NoticeMessage(style: .error, text: error.localizedDescription)
        }
    }

    func addPrompt(name: String, content: String) async {
        let now = Int64(Date().timeIntervalSince1970)
        let prompt = Prompt(
            id: UUID().uuidString,
            name: name,
            appType: selectedPromptApp,
            content: content,
            isActive: false,
            createdAt: now,
            updatedAt: now
        )
        do {
            try await coordinator.addPrompt(prompt)
            prompts = try await coordinator.listPrompts(for: selectedPromptApp)
            notice = NoticeMessage(style: .success, text: "提示词已添加")
        } catch {
            notice = NoticeMessage(style: .error, text: error.localizedDescription)
        }
    }

    func updatePrompt(_ prompt: Prompt) async {
        do {
            try await coordinator.updatePrompt(prompt)
            prompts = try await coordinator.listPrompts(for: selectedPromptApp)
            notice = NoticeMessage(style: .success, text: "提示词已更新")
        } catch {
            notice = NoticeMessage(style: .error, text: error.localizedDescription)
        }
    }

    func activatePrompt(id: String) async {
        do {
            try await coordinator.activatePrompt(id: id, appType: selectedPromptApp)
            prompts = try await coordinator.listPrompts(for: selectedPromptApp)
            localConfigBundles = try await coordinator.listLocalConfigBundles()
            notice = NoticeMessage(style: .success, text: "Prompt activated \u{2192} \(selectedPromptApp.fileName)")
        } catch {
            notice = NoticeMessage(style: .error, text: error.localizedDescription)
        }
    }

    func deletePrompt(id: String) async {
        do {
            try await coordinator.deletePrompt(id: id)
            prompts = try await coordinator.listPrompts(for: selectedPromptApp)
            notice = NoticeMessage(style: .info, text: "提示词已删除")
        } catch {
            notice = NoticeMessage(style: .error, text: error.localizedDescription)
        }
    }

    func importLivePrompt() async {
        do {
            if let imported = try await coordinator.importLivePrompt(for: selectedPromptApp) {
                try await coordinator.addPrompt(imported)
                prompts = try await coordinator.listPrompts(for: selectedPromptApp)
                localConfigBundles = try await coordinator.listLocalConfigBundles()
                notice = NoticeMessage(style: .success, text: "已从 \(selectedPromptApp.fileName) 导入")
            } else {
                notice = NoticeMessage(style: .info, text: "未找到 \(selectedPromptApp.fileName)")
            }
        } catch {
            notice = NoticeMessage(style: .error, text: error.localizedDescription)
        }
    }

    // MARK: - Hooks

    func refreshClaudeHooks() async {
        do {
            claudeHooks = try await coordinator.listClaudeHooks()
            localConfigBundles = try await coordinator.listLocalConfigBundles()
            notice = NoticeMessage(style: .success, text: "已刷新 Hooks")
        } catch {
            notice = NoticeMessage(style: .error, text: error.localizedDescription)
        }
    }

    func toggleHookApp(hookIdentity: String, app: ProviderAppType, enabled: Bool) async {
        do {
            try await coordinator.toggleHookApp(hookIdentity: hookIdentity, app: app, enabled: enabled)
            claudeHooks = try await coordinator.listClaudeHooks()
            localConfigBundles = try await coordinator.listLocalConfigBundles()
        } catch {
            notice = NoticeMessage(style: .error, text: error.localizedDescription)
        }
    }

    // MARK: - Skills

    func refreshSkillsFromDisk() async {
        do {
            var skillStore = try await coordinator.loadSkillStore()
            skillStore.installedSkills = try await coordinator.syncInstalledSkillsFromDisk()
            skills = skillStore
            notice = NoticeMessage(style: .success, text: "已同步本地技能目录")
        } catch {
            notice = NoticeMessage(style: .error, text: error.localizedDescription)
        }
    }

    func discoverSkills() async {
        skillDiscoveryLoading = true
        defer { skillDiscoveryLoading = false }
        do {
            discoverableSkills = try await coordinator.discoverAvailableSkills()
            refreshDiscoverableSkillPreviewIfNeeded()
            notice = NoticeMessage(style: .success, text: "已获取可安装技能列表")
        } catch {
            notice = NoticeMessage(style: .error, text: error.localizedDescription)
        }
    }

    func installSkill(_ skill: DiscoverableSkill) async {
        loading = true
        defer { loading = false }
        do {
            try await coordinator.installSkill(skill)
            var skillStore = try await coordinator.loadSkillStore()
            skillStore.installedSkills = try await coordinator.listInstalledSkills()
            skills = skillStore
            discoverableSkills = try await coordinator.discoverAvailableSkills()
            refreshDiscoverableSkillPreviewIfNeeded()
            notice = NoticeMessage(style: .success, text: "已安装技能：\(skill.name)")
        } catch {
            notice = NoticeMessage(style: .error, text: error.localizedDescription)
        }
    }

    func toggleDiscoverableSkillApp(skillId: String, app: ProviderAppType, enabled: Bool) {
        guard let index = discoverableSkills.firstIndex(where: { $0.id == skillId }) else { return }
        discoverableSkills[index].apps.setEnabled(enabled, for: app)
        refreshDiscoverableSkillPreviewIfNeeded()
    }

    func addSkillRepo(owner: String, name: String, branch: String) async {
        let trimmedOwner = owner.trimmingCharacters(in: .whitespacesAndNewlines)
        let trimmedName = name.trimmingCharacters(in: .whitespacesAndNewlines)
        let trimmedBranch = branch.trimmingCharacters(in: .whitespacesAndNewlines)

        guard !trimmedOwner.isEmpty, !trimmedName.isEmpty, !trimmedBranch.isEmpty else {
            notice = NoticeMessage(style: .error, text: "请完整填写仓库信息")
            return
        }

        do {
            let repo = SkillRepo(
                owner: trimmedOwner,
                name: trimmedName,
                branch: trimmedBranch,
                isEnabled: true,
                isDefault: false
            )
            try await coordinator.addSkillRepo(repo)
            skills = try await coordinator.loadSkillStore()
            notice = NoticeMessage(style: .success, text: "已添加技能仓库")
        } catch {
            notice = NoticeMessage(style: .error, text: error.localizedDescription)
        }
    }

    func removeSkillRepo(_ repo: SkillRepo) async {
        do {
            try await coordinator.removeSkillRepo(owner: repo.owner, name: repo.name)
            skills = try await coordinator.loadSkillStore()
            discoverableSkills.removeAll {
                $0.repoOwner.caseInsensitiveCompare(repo.owner) == .orderedSame &&
                    $0.repoName.caseInsensitiveCompare(repo.name) == .orderedSame
            }
            notice = NoticeMessage(style: .info, text: "技能仓库已移除")
        } catch {
            notice = NoticeMessage(style: .error, text: error.localizedDescription)
        }
    }

    func setSkillRepoEnabled(_ repo: SkillRepo, enabled: Bool) async {
        do {
            try await coordinator.setSkillRepoEnabled(owner: repo.owner, name: repo.name, enabled: enabled)
            skills = try await coordinator.loadSkillStore()

            if !discoverableSkills.isEmpty || !enabled {
                discoverableSkills = try await coordinator.discoverAvailableSkills()
                refreshDiscoverableSkillPreviewIfNeeded()
            }

            let stateText = enabled ? "已启用" : "已停用"
            notice = NoticeMessage(style: .success, text: "\(stateText)技能仓库：\(repo.owner)/\(repo.name)")
        } catch {
            notice = NoticeMessage(style: .error, text: error.localizedDescription)
        }
    }

    func uninstallSkill(directory: String) async {
        do {
            try await coordinator.uninstallSkill(directory: directory)
            var skillStore = try await coordinator.loadSkillStore()
            skillStore.installedSkills = try await coordinator.listInstalledSkills()
            skills = skillStore
            if !discoverableSkills.isEmpty {
                discoverableSkills = try await coordinator.discoverAvailableSkills()
                refreshDiscoverableSkillPreviewIfNeeded()
            }
            notice = NoticeMessage(style: .info, text: "技能已移除")
        } catch {
            notice = NoticeMessage(style: .error, text: error.localizedDescription)
        }
    }

    func toggleInstalledSkillApp(directory: String, app: ProviderAppType, enabled: Bool) async {
        do {
            try await coordinator.toggleSkillApp(directory: directory, app: app, enabled: enabled)
            var skillStore = try await coordinator.loadSkillStore()
            skillStore.installedSkills = try await coordinator.listInstalledSkills()
            skills = skillStore
            if !discoverableSkills.isEmpty {
                discoverableSkills = try await coordinator.discoverAvailableSkills()
                refreshDiscoverableSkillPreviewIfNeeded()
            }
        } catch {
            notice = NoticeMessage(style: .error, text: error.localizedDescription)
        }
    }

    func previewDiscoverableSkill(_ skill: DiscoverableSkill) async {
        previewingDiscoverableSkillKey = skill.key
        defer { previewingDiscoverableSkillKey = nil }

        do {
            previewingDiscoverableSkillDocument = try await coordinator.readDiscoverableSkillDocument(skill)
        } catch {
            notice = NoticeMessage(style: .error, text: error.localizedDescription)
        }
    }

    func openInstalledSkill(directory: String) async {
        do {
            editingInstalledSkillDocument = try await coordinator.readInstalledSkillDocument(directory: directory)
        } catch {
            notice = NoticeMessage(style: .error, text: error.localizedDescription)
        }
    }

    func saveInstalledSkill(directory: String, content: String) async {
        do {
            editingInstalledSkillDocument = try await coordinator.updateInstalledSkillContent(directory: directory, content: content)
            var skillStore = try await coordinator.loadSkillStore()
            skillStore.installedSkills = try await coordinator.listInstalledSkills()
            skills = skillStore
            notice = NoticeMessage(style: .success, text: "技能内容已保存")
        } catch {
            notice = NoticeMessage(style: .error, text: error.localizedDescription)
        }
    }

    // MARK: - Managed Services

    func refreshManagedToolStatus() async {
        cursor2APIStatus = await cursor2APIService.status()
        await refreshTrackedPorts()
    }

    func installCursor2API() async {
        loading = true
        defer { loading = false }
        do {
            cursor2APIStatus = try await cursor2APIService.install()
            await refreshTrackedPorts()
            notice = NoticeMessage(style: .success, text: "Cursor2API 已安装")
        } catch {
            notice = NoticeMessage(style: .error, text: error.localizedDescription)
        }
    }

    func startCursor2API() async {
        loading = true
        defer { loading = false }
        do {
            let models = cursor2APIStatus.models.isEmpty ? ["claude-sonnet-4.6"] : cursor2APIStatus.models
            cursor2APIStatus = try await cursor2APIService.start(
                port: cursor2APIStatus.port,
                apiKey: cursor2APIStatus.apiKey,
                models: models
            )
            await refreshTrackedPorts()
            notice = NoticeMessage(style: .success, text: "Cursor2API 已启动")
        } catch {
            notice = NoticeMessage(style: .error, text: error.localizedDescription)
        }
    }

    func stopCursor2API() async {
        loading = true
        defer { loading = false }
        cursor2APIStatus = await cursor2APIService.stop()
        await refreshTrackedPorts()
        notice = NoticeMessage(style: .info, text: "Cursor2API 已停止")
    }

    func applyCursor2APIToClaude() async {
        loading = true
        defer { loading = false }
        do {
            guard cursor2APIStatus.running else {
                throw AppError.invalidData("请先启动 Cursor2API")
            }
            _ = try await coordinator.upsertManagedClaudeCursor2APIProvider(from: cursor2APIStatus)
            localConfigBundles = try await coordinator.listLocalConfigBundles()
            notice = NoticeMessage(style: .success, text: "已切换 Claude Code 到 Cursor2API 本地桥接")
        } catch {
            notice = NoticeMessage(style: .error, text: error.localizedDescription)
        }
    }

    func refreshTrackedPorts() async {
        var updated: [ManagedPortStatus] = []
        for port in trackedPortNumbers.sorted() {
            updated.append(await portService.status(for: port))
        }
        trackedPorts = updated
    }

    func addTrackedPort() async {
        guard let port = Int(customPortText.trimmingCharacters(in: .whitespacesAndNewlines)),
              (1...65535).contains(port) else {
            notice = NoticeMessage(style: .error, text: "请输入有效端口号")
            return
        }

        if !trackedPortNumbers.contains(port) {
            trackedPortNumbers.append(port)
            trackedPortNumbers.sort()
        }

        customPortText = ""
        await refreshTrackedPorts()
    }

    func removeTrackedPort(_ port: Int) async {
        guard !defaultTrackedPorts.contains(port) else { return }
        trackedPortNumbers.removeAll { $0 == port }
        trackedPorts.removeAll { $0.port == port }
    }

    func killPort(_ port: Int) async {
        loading = true
        defer { loading = false }
        do {
            _ = try await portService.kill(port: port)
            await refreshManagedToolStatus()
            notice = NoticeMessage(style: .success, text: "端口 \(port) 已释放")
        } catch {
            notice = NoticeMessage(style: .error, text: error.localizedDescription)
        }
    }

    private func refreshDiscoverableSkillPreviewIfNeeded() {
        guard var document = previewingDiscoverableSkillDocument else { return }
        guard let updatedSkill = discoverableSkills.first(where: { $0.key == document.skill.key }) else { return }
        document.skill = updatedSkill
        previewingDiscoverableSkillDocument = document
    }
}
