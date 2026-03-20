import XCTest
@testable import AIMenu

@MainActor
final class ToolsPageModelTests: XCTestCase {
    func testAddTrackedPortRejectsDuplicateWithInfoNotice() async throws {
        let model = try makeModel()
        model.customPortText = "8787"

        await model.addTrackedPort()

        XCTAssertEqual(model.trackedPortNumbers, [8002, 8787])
        XCTAssertEqual(model.notice, NoticeMessage(style: .info, text: "端口 8787 已在关注列表中"))
    }

    func testAddTrackedPortAppendsSortsAndClearsInput() async throws {
        let model = try makeModel()
        model.customPortText = "3000"

        await model.addTrackedPort()

        XCTAssertEqual(model.trackedPortNumbers, [3000, 8002, 8787])
        XCTAssertEqual(model.customPortText, "")
        XCTAssertEqual(model.notice, NoticeMessage(style: .success, text: "已关注端口 3000"))
    }

    func testRemoveTrackedPortKeepsDefaultWatchedPorts() async throws {
        let model = try makeModel()

        await model.removeTrackedPort(8787)

        XCTAssertEqual(model.trackedPortNumbers, [8002, 8787])
    }

    func testReleaseTrackedPortUsesTerminate() async throws {
        let portService = RecordingPortManagementService()
        let model = try makeModel(portService: portService)

        await model.releaseTrackedPort(8002)

        let calls = await portService.calls
        XCTAssertEqual(calls, [.terminate(8002)])
        XCTAssertEqual(model.notice, NoticeMessage(style: .success, text: "端口 8002 已解除占用"))
    }

    func testForceReleaseTrackedPortUsesForceKill() async throws {
        let portService = RecordingPortManagementService()
        let model = try makeModel(portService: portService)

        await model.releaseTrackedPort(8787, force: true)

        let calls = await portService.calls
        XCTAssertEqual(calls, [.forceKill(8787)])
        XCTAssertEqual(model.notice, NoticeMessage(style: .success, text: "端口 8787 已强制解除占用"))
    }

    private func makeModel(
        portService: any PortManagementServiceProtocol = StubPortManagementService()
    ) throws -> ToolsPageModel {
        let home = FileManager.default.temporaryDirectory
            .appendingPathComponent(UUID().uuidString, isDirectory: true)
        try FileManager.default.createDirectory(at: home, withIntermediateDirectories: true)

        let configService = ProviderConfigService(homeDirectory: home)

        return ToolsPageModel(
            providerCoordinator: ProviderCoordinator(configService: configService),
            mcpCoordinator: MCPCoordinator(configService: configService),
            promptCoordinator: PromptCoordinator(configService: configService),
            skillCoordinator: SkillCoordinator(configService: configService),
            cursor2APIService: StubCursor2APIService(),
            portService: portService
        )
    }
}

private struct StubCursor2APIService: Cursor2APIServiceProtocol {
    func status() async -> Cursor2APIStatus { .idle }
    func install() async throws -> Cursor2APIStatus { .idle }
    func start(port: Int?, apiKey: String?, models: [String]) async throws -> Cursor2APIStatus {
        _ = port
        _ = apiKey
        _ = models
        return .idle
    }
    func stop() async -> Cursor2APIStatus { .idle }
}

private struct StubPortManagementService: PortManagementServiceProtocol {
    func status(for port: Int) async -> ManagedPortStatus { .idle(port: port) }
    func terminate(port: Int) async throws -> ManagedPortStatus { .idle(port: port) }
    func forceKill(port: Int) async throws -> ManagedPortStatus { .idle(port: port) }
}

private actor RecordingPortManagementService: PortManagementServiceProtocol {
    enum Call: Equatable {
        case terminate(Int)
        case forceKill(Int)
    }

    private(set) var calls: [Call] = []

    func status(for port: Int) async -> ManagedPortStatus { .idle(port: port) }

    func terminate(port: Int) async throws -> ManagedPortStatus {
        calls.append(.terminate(port))
        return .idle(port: port)
    }

    func forceKill(port: Int) async throws -> ManagedPortStatus {
        calls.append(.forceKill(port))
        return .idle(port: port)
    }
}
