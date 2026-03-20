import Foundation

actor MCPCoordinator {
    private let configService: ProviderConfigService

    init(configService: ProviderConfigService) {
        self.configService = configService
    }

    // MARK: - MCP Servers

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
            throw AppError.invalidData(L10n.tr("error.provider.mcp_server_not_found"))
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
        let previous = store.servers[index]
        switch app {
        case .claude: store.servers[index].apps.claude = enabled
        case .codex: store.servers[index].apps.codex = enabled
        case .gemini: store.servers[index].apps.gemini = enabled
        }
        store.servers[index].updatedAt = Int64(Date().timeIntervalSince1970)
        try await configService.saveMCPStore(store)
        if store.servers[index].isEnabled {
            try await configService.removeMCPServer(previous)
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

    func listLocalConfigBundles() async throws -> [LocalConfigBundle] {
        try await configService.loadLocalConfigBundles()
    }
}
