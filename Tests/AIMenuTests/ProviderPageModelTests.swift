import XCTest
@testable import AIMenu

@MainActor
final class ProviderPageModelTests: XCTestCase {
    func testFilteredProvidersMatchesNameModelAndHost() async throws {
        let tempHome = try makeTemporaryHome()
        defer { try? FileManager.default.removeItem(at: tempHome) }

        let service = ProviderConfigService(homeDirectory: tempHome)
        let coordinator = ProviderCoordinator(configService: service)
        let model = ProviderPageModel(coordinator: coordinator)

        var claude = ProviderPresets.claudePresets[0].makeProvider(apiKey: "sk-claude")
        claude.id = "claude-official"
        claude.name = "Claude Official"
        claude.claudeConfig?.baseUrl = "https://api.anthropic.com"
        claude.claudeConfig?.model = "claude-sonnet-4"

        var router = ProviderPresets.claudePresets[1].makeProvider(apiKey: "sk-router")
        router.id = "claude-openrouter"
        router.name = "OpenRouter Fast"
        router.claudeConfig?.baseUrl = "https://openrouter.ai/api/v1"
        router.claudeConfig?.model = "claude-3.7-sonnet"

        _ = try await coordinator.addProvider(claude)
        _ = try await coordinator.addProvider(router)

        await model.load()

        model.providerSearchText = "openrouter"
        XCTAssertEqual(model.filteredProviders.map(\.id), ["claude-openrouter"])

        model.providerSearchText = "claude-sonnet-4"
        XCTAssertEqual(model.filteredProviders.map(\.id), ["claude-official"])

        model.providerSearchText = "anthropic"
        XCTAssertEqual(model.filteredProviders.map(\.id), ["claude-official"])
    }

    func testCurrentProviderReturnsActiveProvider() async throws {
        let tempHome = try makeTemporaryHome()
        defer { try? FileManager.default.removeItem(at: tempHome) }

        let service = ProviderConfigService(homeDirectory: tempHome)
        let coordinator = ProviderCoordinator(configService: service)
        let model = ProviderPageModel(coordinator: coordinator)

        var first = ProviderPresets.claudePresets[0].makeProvider(apiKey: "sk-first")
        first.id = "first"
        first.name = "First"

        var second = ProviderPresets.claudePresets[1].makeProvider(apiKey: "sk-second")
        second.id = "second"
        second.name = "Second"

        _ = try await coordinator.addProvider(first)
        _ = try await coordinator.addProvider(second)
        try await coordinator.switchProvider(id: second.id, appType: .claude)

        await model.load()

        XCTAssertEqual(model.currentProvider?.id, "second")
    }

    private func makeTemporaryHome() throws -> URL {
        let url = FileManager.default.temporaryDirectory
            .appendingPathComponent(UUID().uuidString, isDirectory: true)
        try FileManager.default.createDirectory(at: url, withIntermediateDirectories: true)
        return url
    }
}
