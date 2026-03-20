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

    private func makeModel() throws -> ToolsPageModel {
        let home = FileManager.default.temporaryDirectory
            .appendingPathComponent(UUID().uuidString, isDirectory: true)
        try FileManager.default.createDirectory(at: home, withIntermediateDirectories: true)

        let coordinator = ProviderCoordinator(
            configService: ProviderConfigService(homeDirectory: home)
        )

        return ToolsPageModel(
            coordinator: coordinator,
            cursor2APIService: StubCursor2APIService(),
            portService: StubPortManagementService()
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
    func kill(port: Int) async throws -> ManagedPortStatus { .idle(port: port) }
}
