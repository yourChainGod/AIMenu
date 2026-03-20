import Foundation
import Combine

@MainActor
final class ToolsPageModel: ObservableObject {
    private let defaultTrackedPorts = [8002, 8787]
    private let providerCoordinator: ProviderCoordinator
    private let mcpCoordinator: MCPCoordinator
    private let promptCoordinator: PromptCoordinator
    private let skillCoordinator: SkillCoordinator
    private let cursor2APIService: Cursor2APIServiceProtocol
    private let portService: PortManagementServiceProtocol
    private let noticeScheduler = NoticeAutoDismissScheduler()

    enum ToolsSection: String, CaseIterable { case mcp, prompts, hooks, skills }

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
        providerCoordinator: ProviderCoordinator,
        mcpCoordinator: MCPCoordinator,
        promptCoordinator: PromptCoordinator,
        skillCoordinator: SkillCoordinator,
        cursor2APIService: Cursor2APIServiceProtocol,
        portService: PortManagementServiceProtocol
    ) {
        self.providerCoordinator = providerCoordinator
        self.mcpCoordinator = mcpCoordinator
        self.promptCoordinator = promptCoordinator
        self.skillCoordinator = skillCoordinator
        self.cursor2APIService = cursor2APIService
        self.portService = portService
    }

    func loadOverview() async {
        loading = true
        defer { loading = false }
        do {
            localConfigBundles = try await mcpCoordinator.listLocalConfigBundles()
            await refreshManagedToolStatus()
        } catch {
            notice = NoticeMessage(style: .error, text: error.localizedDescription)
        }
    }

    func loadWorkbench() async {
        loading = true
        defer { loading = false }
        do {
            mcpServers = try await mcpCoordinator.listMCPServers()
            prompts = try await promptCoordinator.listPrompts(for: selectedPromptApp)
            claudeHooks = try await providerCoordinator.listClaudeHooks()
            var skillStore = try await skillCoordinator.loadSkillStore()
            skillStore.installedSkills = try await skillCoordinator.listInstalledSkills()
            skills = skillStore
        } catch {
            notice = NoticeMessage(style: .error, text: error.localizedDescription)
        }
    }

    // MARK: - MCP

    func addMCPFromPreset(_ preset: MCPPreset) async {
        let server = preset.makeServer()
        do {
            try await mcpCoordinator.addMCPServer(server)
            mcpServers = try await mcpCoordinator.listMCPServers()
            localConfigBundles = try await mcpCoordinator.listLocalConfigBundles()
            notice = NoticeMessage(style: .success, text: L10n.tr("tools.notice.mcp_added_format", server.name))
        } catch {
            notice = NoticeMessage(style: .error, text: error.localizedDescription)
        }
    }

    func saveMCPServer(_ server: MCPServer) async {
        do {
            if mcpServers.contains(where: { $0.id == server.id }) {
                try await mcpCoordinator.updateMCPServer(server)
                notice = NoticeMessage(style: .success, text: L10n.tr("tools.notice.mcp_updated"))
            } else {
                try await mcpCoordinator.addMCPServer(server)
                notice = NoticeMessage(style: .success, text: L10n.tr("tools.notice.mcp_server_added"))
            }
            mcpServers = try await mcpCoordinator.listMCPServers()
            localConfigBundles = try await mcpCoordinator.listLocalConfigBundles()
        } catch {
            notice = NoticeMessage(style: .error, text: error.localizedDescription)
        }
    }

    func deleteMCPServer(id: String) async {
        do {
            try await mcpCoordinator.deleteMCPServer(id: id)
            mcpServers = try await mcpCoordinator.listMCPServers()
            localConfigBundles = try await mcpCoordinator.listLocalConfigBundles()
            notice = NoticeMessage(style: .info, text: L10n.tr("tools.notice.mcp_removed"))
        } catch {
            notice = NoticeMessage(style: .error, text: error.localizedDescription)
        }
    }

    func importLiveMCPServers() async {
        do {
            mcpServers = try await mcpCoordinator.importLiveMCPServers()
            localConfigBundles = try await mcpCoordinator.listLocalConfigBundles()
            notice = NoticeMessage(style: .success, text: L10n.tr("tools.notice.mcp_imported"))
        } catch {
            notice = NoticeMessage(style: .error, text: error.localizedDescription)
        }
    }

    func toggleMCPApp(serverId: String, app: ProviderAppType, enabled: Bool) async {
        do {
            try await mcpCoordinator.toggleMCPApp(serverId: serverId, app: app, enabled: enabled)
            mcpServers = try await mcpCoordinator.listMCPServers()
            localConfigBundles = try await mcpCoordinator.listLocalConfigBundles()
        } catch {
            notice = NoticeMessage(style: .error, text: error.localizedDescription)
        }
    }

    // MARK: - Local Config Overview

    func refreshLocalConfigBundles(showNotice: Bool = true) async {
        do {
            localConfigBundles = try await mcpCoordinator.listLocalConfigBundles()
            if showNotice {
                notice = NoticeMessage(style: .success, text: L10n.tr("tools.notice.local_config_refreshed"))
            }
        } catch {
            notice = NoticeMessage(style: .error, text: error.localizedDescription)
        }
    }

    // MARK: - Prompts

    func switchPromptApp(_ app: PromptAppType) async {
        selectedPromptApp = app
        do {
            prompts = try await promptCoordinator.listPrompts(for: app)
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
            try await promptCoordinator.addPrompt(prompt)
            prompts = try await promptCoordinator.listPrompts(for: selectedPromptApp)
            notice = NoticeMessage(style: .success, text: L10n.tr("tools.notice.prompt_added"))
        } catch {
            notice = NoticeMessage(style: .error, text: error.localizedDescription)
        }
    }

    func updatePrompt(_ prompt: Prompt) async {
        do {
            try await promptCoordinator.updatePrompt(prompt)
            prompts = try await promptCoordinator.listPrompts(for: selectedPromptApp)
            notice = NoticeMessage(style: .success, text: L10n.tr("tools.notice.prompt_updated"))
        } catch {
            notice = NoticeMessage(style: .error, text: error.localizedDescription)
        }
    }

    func activatePrompt(id: String) async {
        do {
            try await promptCoordinator.activatePrompt(id: id, appType: selectedPromptApp)
            prompts = try await promptCoordinator.listPrompts(for: selectedPromptApp)
            localConfigBundles = try await mcpCoordinator.listLocalConfigBundles()
            notice = NoticeMessage(style: .success, text: L10n.tr("tools.notice.prompt_activated_format", selectedPromptApp.fileName))
        } catch {
            notice = NoticeMessage(style: .error, text: error.localizedDescription)
        }
    }

    func deletePrompt(id: String) async {
        do {
            try await promptCoordinator.deletePrompt(id: id)
            prompts = try await promptCoordinator.listPrompts(for: selectedPromptApp)
            notice = NoticeMessage(style: .info, text: L10n.tr("tools.notice.prompt_deleted"))
        } catch {
            notice = NoticeMessage(style: .error, text: error.localizedDescription)
        }
    }

    func importLivePrompt() async {
        do {
            if let imported = try await promptCoordinator.importLivePrompt(for: selectedPromptApp) {
                try await promptCoordinator.addPrompt(imported)
                prompts = try await promptCoordinator.listPrompts(for: selectedPromptApp)
                localConfigBundles = try await mcpCoordinator.listLocalConfigBundles()
                notice = NoticeMessage(style: .success, text: L10n.tr("tools.notice.prompt_imported_format", selectedPromptApp.fileName))
            } else {
                notice = NoticeMessage(style: .info, text: L10n.tr("tools.notice.prompt_not_found_format", selectedPromptApp.fileName))
            }
        } catch {
            notice = NoticeMessage(style: .error, text: error.localizedDescription)
        }
    }

    // MARK: - Hooks

    func refreshClaudeHooks() async {
        do {
            claudeHooks = try await providerCoordinator.listClaudeHooks()
            localConfigBundles = try await mcpCoordinator.listLocalConfigBundles()
            notice = NoticeMessage(style: .success, text: L10n.tr("tools.notice.hooks_refreshed"))
        } catch {
            notice = NoticeMessage(style: .error, text: error.localizedDescription)
        }
    }

    func toggleHookApp(hookIdentity: String, app: ProviderAppType, enabled: Bool) async {
        do {
            try await providerCoordinator.toggleHookApp(hookIdentity: hookIdentity, app: app, enabled: enabled)
            claudeHooks = try await providerCoordinator.listClaudeHooks()
            localConfigBundles = try await mcpCoordinator.listLocalConfigBundles()
        } catch {
            notice = NoticeMessage(style: .error, text: error.localizedDescription)
        }
    }

    // MARK: - Skills

    func refreshSkillsFromDisk() async {
        do {
            var skillStore = try await skillCoordinator.loadSkillStore()
            skillStore.installedSkills = try await skillCoordinator.syncInstalledSkillsFromDisk()
            skills = skillStore
            notice = NoticeMessage(style: .success, text: L10n.tr("tools.notice.skills_synced"))
        } catch {
            notice = NoticeMessage(style: .error, text: error.localizedDescription)
        }
    }

    func discoverSkills() async {
        skillDiscoveryLoading = true
        defer { skillDiscoveryLoading = false }
        do {
            discoverableSkills = try await skillCoordinator.discoverAvailableSkills()
            refreshDiscoverableSkillPreviewIfNeeded()
            notice = NoticeMessage(style: .success, text: L10n.tr("tools.notice.discoverable_skills_loaded"))
        } catch {
            notice = NoticeMessage(style: .error, text: error.localizedDescription)
        }
    }

    func installSkill(_ skill: DiscoverableSkill) async {
        loading = true
        defer { loading = false }
        do {
            try await skillCoordinator.installSkill(skill)
            var skillStore = try await skillCoordinator.loadSkillStore()
            skillStore.installedSkills = try await skillCoordinator.listInstalledSkills()
            skills = skillStore
            discoverableSkills = try await skillCoordinator.discoverAvailableSkills()
            refreshDiscoverableSkillPreviewIfNeeded()
            notice = NoticeMessage(style: .success, text: L10n.tr("tools.notice.skill_installed_format", skill.name))
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
            notice = NoticeMessage(style: .error, text: L10n.tr("tools.notice.skill_repo_form_incomplete"))
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
            try await skillCoordinator.addSkillRepo(repo)
            skills = try await skillCoordinator.loadSkillStore()
            notice = NoticeMessage(style: .success, text: L10n.tr("tools.notice.skill_repo_added"))
        } catch {
            notice = NoticeMessage(style: .error, text: error.localizedDescription)
        }
    }

    func removeSkillRepo(_ repo: SkillRepo) async {
        do {
            try await skillCoordinator.removeSkillRepo(owner: repo.owner, name: repo.name)
            skills = try await skillCoordinator.loadSkillStore()
            discoverableSkills.removeAll {
                $0.repoOwner.caseInsensitiveCompare(repo.owner) == .orderedSame &&
                    $0.repoName.caseInsensitiveCompare(repo.name) == .orderedSame
            }
            notice = NoticeMessage(style: .info, text: L10n.tr("tools.notice.skill_repo_removed"))
        } catch {
            notice = NoticeMessage(style: .error, text: error.localizedDescription)
        }
    }

    func setSkillRepoEnabled(_ repo: SkillRepo, enabled: Bool) async {
        do {
            try await skillCoordinator.setSkillRepoEnabled(owner: repo.owner, name: repo.name, enabled: enabled)
            skills = try await skillCoordinator.loadSkillStore()

            if !discoverableSkills.isEmpty || !enabled {
                discoverableSkills = try await skillCoordinator.discoverAvailableSkills()
                refreshDiscoverableSkillPreviewIfNeeded()
            }

            let stateText = enabled ? L10n.tr("tools.state.enabled") : L10n.tr("tools.state.disabled")
            notice = NoticeMessage(
                style: .success,
                text: L10n.tr("tools.notice.skill_repo_toggled_format", stateText, repo.owner, repo.name)
            )
        } catch {
            notice = NoticeMessage(style: .error, text: error.localizedDescription)
        }
    }

    func uninstallSkill(directory: String) async {
        do {
            try await skillCoordinator.uninstallSkill(directory: directory)
            var skillStore = try await skillCoordinator.loadSkillStore()
            skillStore.installedSkills = try await skillCoordinator.listInstalledSkills()
            skills = skillStore
            if !discoverableSkills.isEmpty {
                discoverableSkills = try await skillCoordinator.discoverAvailableSkills()
                refreshDiscoverableSkillPreviewIfNeeded()
            }
            notice = NoticeMessage(style: .info, text: L10n.tr("tools.notice.skill_removed"))
        } catch {
            notice = NoticeMessage(style: .error, text: error.localizedDescription)
        }
    }

    func toggleInstalledSkillApp(directory: String, app: ProviderAppType, enabled: Bool) async {
        do {
            try await skillCoordinator.toggleSkillApp(directory: directory, app: app, enabled: enabled)
            var skillStore = try await skillCoordinator.loadSkillStore()
            skillStore.installedSkills = try await skillCoordinator.listInstalledSkills()
            skills = skillStore
            if !discoverableSkills.isEmpty {
                discoverableSkills = try await skillCoordinator.discoverAvailableSkills()
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
            previewingDiscoverableSkillDocument = try await skillCoordinator.readDiscoverableSkillDocument(skill)
        } catch {
            notice = NoticeMessage(style: .error, text: error.localizedDescription)
        }
    }

    func openInstalledSkill(directory: String) async {
        do {
            editingInstalledSkillDocument = try await skillCoordinator.readInstalledSkillDocument(directory: directory)
        } catch {
            notice = NoticeMessage(style: .error, text: error.localizedDescription)
        }
    }

    func saveInstalledSkill(directory: String, content: String) async {
        do {
            editingInstalledSkillDocument = try await skillCoordinator.updateInstalledSkillContent(directory: directory, content: content)
            var skillStore = try await skillCoordinator.loadSkillStore()
            skillStore.installedSkills = try await skillCoordinator.listInstalledSkills()
            skills = skillStore
            notice = NoticeMessage(style: .success, text: L10n.tr("tools.notice.skill_saved"))
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
            notice = NoticeMessage(style: .success, text: L10n.tr("tools.notice.cursor2api_installed"))
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
            notice = NoticeMessage(style: .success, text: L10n.tr("tools.notice.cursor2api_started"))
        } catch {
            notice = NoticeMessage(style: .error, text: error.localizedDescription)
        }
    }

    func stopCursor2API() async {
        loading = true
        defer { loading = false }
        cursor2APIStatus = await cursor2APIService.stop()
        await refreshTrackedPorts()
        notice = NoticeMessage(style: .info, text: L10n.tr("tools.notice.cursor2api_stopped"))
    }

    func applyCursor2APIToClaude() async {
        loading = true
        defer { loading = false }
        do {
            guard cursor2APIStatus.running else {
                throw AppError.invalidData(L10n.tr("error.tools.cursor2api_start_first"))
            }
            _ = try await providerCoordinator.upsertManagedClaudeCursor2APIProvider(from: cursor2APIStatus)
            localConfigBundles = try await mcpCoordinator.listLocalConfigBundles()
            notice = NoticeMessage(style: .success, text: L10n.tr("tools.notice.cursor2api_applied"))
        } catch {
            notice = NoticeMessage(style: .error, text: error.localizedDescription)
        }
    }

    func refreshTrackedPorts(showNotice: Bool = false) async {
        trackedPortNumbers = Array(Set(trackedPortNumbers)).sorted()

        var updated: [ManagedPortStatus] = []
        for port in trackedPortNumbers {
            updated.append(await portService.status(for: port))
        }
        trackedPorts = updated

        if showNotice {
            notice = NoticeMessage(style: .success, text: L10n.tr("tools.notice.port_status_refreshed"))
        }
    }

    func addTrackedPort() async {
        guard let port = Int(customPortText.trimmingCharacters(in: .whitespacesAndNewlines)),
              (1...65535).contains(port) else {
            notice = NoticeMessage(style: .error, text: L10n.tr("tools.notice.port_invalid"))
            return
        }

        await addTrackedPort(port, clearsInput: true)
    }

    func addTrackedPort(_ port: Int, clearsInput: Bool = false) async {
        guard (1...65535).contains(port) else {
            notice = NoticeMessage(style: .error, text: L10n.tr("tools.notice.port_invalid"))
            return
        }

        guard !trackedPortNumbers.contains(port) else {
            notice = NoticeMessage(style: .info, text: L10n.tr("tools.notice.port_already_tracked_format", String(port)))
            await refreshTrackedPorts()
            return
        }

        trackedPortNumbers.append(port)
        trackedPortNumbers.sort()

        if clearsInput {
            customPortText = ""
        }

        await refreshTrackedPorts()
        notice = NoticeMessage(style: .success, text: L10n.tr("tools.notice.port_tracked_format", String(port)))
    }

    func removeTrackedPort(_ port: Int) async {
        guard !defaultTrackedPorts.contains(port) else { return }
        guard trackedPortNumbers.contains(port) else { return }
        trackedPortNumbers.removeAll { $0 == port }
        trackedPorts.removeAll { $0.port == port }
        notice = NoticeMessage(style: .info, text: L10n.tr("tools.notice.port_removed_format", String(port)))
    }

    func releaseTrackedPort(_ port: Int, force: Bool = false) async {
        loading = true
        defer { loading = false }
        do {
            if force {
                _ = try await portService.forceKill(port: port)
            } else {
                _ = try await portService.terminate(port: port)
            }
            await refreshManagedToolStatus()
            let message = force
                ? L10n.tr("tools.notice.port_force_released_format", String(port))
                : L10n.tr("tools.notice.port_released_format", String(port))
            notice = NoticeMessage(style: .success, text: message)
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
