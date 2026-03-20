import XCTest
@testable import AIMenu

final class MCPServerTests: XCTestCase {
    func testToggleMCPAppRemovesLiveEntryFromUnmountedClient() async throws {
        let tempHome = try makeTemporaryHome()
        defer { try? FileManager.default.removeItem(at: tempHome) }

        let service = ProviderConfigService(homeDirectory: tempHome)
        let coordinator = MCPCoordinator(configService: service)
        let server = MCPServer(
            id: "demo-fetch",
            name: "Demo Fetch",
            server: MCPServerSpec(
                type: .stdio,
                command: "uvx",
                args: ["mcp-server-fetch"],
                env: nil,
                cwd: nil,
                url: nil,
                headers: nil
            ),
            apps: MCPAppToggles(claude: true, codex: true, gemini: false),
            description: nil,
            tags: nil,
            homepage: nil,
            createdAt: 1,
            updatedAt: 1,
            isEnabled: true
        )

        try await coordinator.addMCPServer(server)

        let initialClaudeConfig = try XCTUnwrap(
            try JSONSerialization.jsonObject(
                with: Data(contentsOf: tempHome.appendingPathComponent(".claude.json"))
            ) as? [String: Any]
        )
        XCTAssertNotNil((initialClaudeConfig["mcpServers"] as? [String: Any])?["demo-fetch"])

        try await coordinator.toggleMCPApp(serverId: server.id, app: .claude, enabled: false)

        let updatedClaudeConfig = try XCTUnwrap(
            try JSONSerialization.jsonObject(
                with: Data(contentsOf: tempHome.appendingPathComponent(".claude.json"))
            ) as? [String: Any]
        )
        let claudeMCP = (updatedClaudeConfig["mcpServers"] as? [String: Any]) ?? [:]
        XCTAssertNil(claudeMCP["demo-fetch"])

        let codexConfig = try String(contentsOf: tempHome.appendingPathComponent(".codex/config.toml"))
        XCTAssertTrue(codexConfig.contains("[mcp_servers.demo-fetch]"))
        XCTAssertTrue(codexConfig.contains("command = \"uvx\""))
    }

    // MARK: - Helpers

    private func makeTemporaryHome() throws -> URL {
        let directory = FileManager.default.temporaryDirectory
            .appendingPathComponent(UUID().uuidString, isDirectory: true)
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        return directory
    }
}
