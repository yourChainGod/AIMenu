import Foundation
import Combine

@MainActor
final class ToolsPageModel: ObservableObject {
    private let coordinator: ProviderCoordinator
    private let noticeScheduler = NoticeAutoDismissScheduler()

    enum ToolsSection: String, CaseIterable { case mcp, prompts, skills }

    @Published var activeSection: ToolsSection = .mcp
    @Published var mcpServers: [MCPServer] = []
    @Published var prompts: [Prompt] = []
    @Published var selectedPromptApp: PromptAppType = .claude
    @Published var skills: SkillStore = SkillStore(repos: SkillStore.defaultRepos)
    @Published var loading = false
    @Published var notice: NoticeMessage? {
        didSet { noticeScheduler.schedule(notice) { [weak self] in self?.notice = nil } }
    }

    init(coordinator: ProviderCoordinator) {
        self.coordinator = coordinator
    }

    func load() async {
        loading = true
        defer { loading = false }
        do {
            mcpServers = try await coordinator.listMCPServers()
            prompts = try await coordinator.listPrompts(for: selectedPromptApp)
            skills = try await coordinator.loadSkillStore()
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
            notice = NoticeMessage(style: .success, text: "已添加 MCP：\(server.name)")
        } catch {
            notice = NoticeMessage(style: .error, text: error.localizedDescription)
        }
    }

    func deleteMCPServer(id: String) async {
        do {
            try await coordinator.deleteMCPServer(id: id)
            mcpServers = try await coordinator.listMCPServers()
            notice = NoticeMessage(style: .info, text: "MCP 服务器已移除")
        } catch {
            notice = NoticeMessage(style: .error, text: error.localizedDescription)
        }
    }

    func toggleMCPApp(serverId: String, app: ProviderAppType, enabled: Bool) async {
        do {
            try await coordinator.toggleMCPApp(serverId: serverId, app: app, enabled: enabled)
            mcpServers = try await coordinator.listMCPServers()
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

    func activatePrompt(id: String) async {
        do {
            try await coordinator.activatePrompt(id: id, appType: selectedPromptApp)
            prompts = try await coordinator.listPrompts(for: selectedPromptApp)
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
                notice = NoticeMessage(style: .success, text: "已从 \(selectedPromptApp.fileName) 导入")
            } else {
                notice = NoticeMessage(style: .info, text: "未找到 \(selectedPromptApp.fileName)")
            }
        } catch {
            notice = NoticeMessage(style: .error, text: error.localizedDescription)
        }
    }
}
