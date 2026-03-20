import Foundation

actor PromptCoordinator {
    private let configService: ProviderConfigService

    init(configService: ProviderConfigService) {
        self.configService = configService
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
            throw AppError.invalidData(L10n.tr("error.provider.prompt_not_found"))
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
        let importedAt = DateFormatter.localizedString(from: Date(), dateStyle: .medium, timeStyle: .short)
        return Prompt(
            id: UUID().uuidString,
            name: L10n.tr("provider.prompt.imported_name_format", appType.fileName),
            appType: appType,
            content: content,
            description: L10n.tr("provider.prompt.imported_description_format", importedAt),
            isActive: true,
            createdAt: now,
            updatedAt: now
        )
    }
}
