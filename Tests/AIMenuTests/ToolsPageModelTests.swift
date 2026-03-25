import XCTest
@testable import AIMenu

@MainActor
final class ToolsPageModelTests: XCTestCase {
    func testAddTrackedPortRejectsDuplicateWithInfoNotice() async throws {
        let model = try makeModel()
        // Add 8787 first, then try again
        await model.addTrackedPort(8787)
        model.customPortText = "8787"

        await model.addTrackedPort()

        XCTAssertNotNil(model.notice)
        XCTAssertEqual(model.notice?.style, .info)
    }

    func testAddTrackedPortAppendsSortsAndClearsInput() async throws {
        let model = try makeModel()
        model.customPortText = "3000"

        await model.addTrackedPort()

        XCTAssertTrue(model.trackedPortNumbers.contains(3000))
        XCTAssertTrue(model.trackedPorts.contains(where: { $0.port == 3000 }))
        XCTAssertEqual(model.customPortText, "")
        XCTAssertEqual(model.notice?.style, .success)
    }

    func testRefreshTrackedPortsKeepsTrackedPortsAndAddsListeningPorts() async throws {
        let portService = ConfigurablePortManagementService(
            scannedPorts: [
                ManagedPortStatus(port: 3000, occupied: true, processID: 321, command: "node", endpoint: "127.0.0.1:3000"),
                ManagedPortStatus(port: 8787, occupied: true, processID: 654, command: "cursor2api", endpoint: "*:8787")
            ]
        )
        let model = try makeModel(portService: portService)

        await model.refreshTrackedPorts()

        XCTAssertEqual(model.trackedPortNumbers, [8002, 8787])
        XCTAssertEqual(model.trackedPorts.map(\.port), [3000, 8002, 8787])
        XCTAssertFalse(try XCTUnwrap(model.trackedPorts.first(where: { $0.port == 8002 })).occupied)
        XCTAssertTrue(try XCTUnwrap(model.trackedPorts.first(where: { $0.port == 8787 })).occupied)
    }

    func testUntrackPortHidesListeningPortAcrossRefreshes() async throws {
        let portService = ConfigurablePortManagementService(
            scannedPorts: [
                ManagedPortStatus(port: 3000, occupied: true, processID: 321, command: "node", endpoint: "127.0.0.1:3000")
            ]
        )
        let model = try makeModel(portService: portService)

        await model.refreshTrackedPorts()
        await model.untrackPort(3000)
        await model.refreshTrackedPorts()

        XCTAssertFalse(model.trackedPorts.contains(where: { $0.port == 3000 }))
        XCTAssertEqual(model.notice, NoticeMessage(style: .info, text: "端口 3000 已设为不关注"))
    }

    func testAddTrackedPortRestoresIgnoredPort() async throws {
        let model = try makeModel()

        await model.untrackPort(8002)
        await model.addTrackedPort(8002)

        XCTAssertTrue(model.trackedPortNumbers.contains(8002))
        XCTAssertTrue(model.trackedPorts.contains(where: { $0.port == 8002 }))
        XCTAssertEqual(model.notice?.style, .success)
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

    func testWebRemoteAddProviderUsesSecondTimestamps() async throws {
        let home = FileManager.default.temporaryDirectory
            .appendingPathComponent(UUID().uuidString, isDirectory: true)
        try FileManager.default.createDirectory(at: home, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: home) }

        let configService = ProviderConfigService(homeDirectory: home)
        let providerCoordinator = ProviderCoordinator(configService: configService)
        let webCoordinator = makeStubWebCoordinator(providerCoordinator: providerCoordinator)
        let requestID = UUID().uuidString
        let message = WebClientMessage(
            type: .addProvider,
            token: nil,
            requestID: requestID,
            text: nil,
            sessionID: nil,
            agent: nil,
            mode: nil,
            model: nil,
            cwd: nil,
            providerID: nil,
            providerName: "Remote Claude",
            providerAppType: ProviderAppType.claude.rawValue,
            providerApiKey: "sk-test",
            providerBaseUrl: "https://example.com",
            providerModel: "claude-test"
        )

        let response = await webCoordinator.handleRequest(message, from: "test-connection")
        let providers = try await providerCoordinator.listProviders(for: .claude)
        let provider = try XCTUnwrap(providers.first(where: { $0.name == "Remote Claude" }))
        let now = Int64(Date().timeIntervalSince1970)

        XCTAssertEqual(response.type, .providerSaved)
        XCTAssertEqual(response.requestID, requestID)
        XCTAssertLessThanOrEqual(abs(provider.createdAt - now), 5)
        XCTAssertLessThanOrEqual(abs(provider.updatedAt - now), 5)
        XCTAssertLessThan(provider.createdAt, 10_000_000_000)
        XCTAssertLessThan(provider.updatedAt, 10_000_000_000)
    }

    func testLoadOverviewReturnsBeforeManagedStatusRefreshFinishes() async throws {
        let cursor2APIService = BlockingCursor2APIService()
        let portService = BlockingPortManagementService(
            scannedPorts: [
                ManagedPortStatus(port: 9090, occupied: true, processID: 42, command: "AIMenu", endpoint: "127.0.0.1:9090")
            ]
        )
        let model = try makeModel(
            cursor2APIService: cursor2APIService,
            portService: portService
        )

        let returned = expectation(description: "loadOverview returned")
        Task {
            await model.loadOverview()
            returned.fulfill()
        }

        await fulfillment(of: [returned], timeout: 0.2)
        XCTAssertFalse(model.loading)
        let didReturnBeforeResume = await cursor2APIService.hasReturnedStatus()
        let didFinishScanBeforeResume = await portService.hasFinishedScan()
        XCTAssertFalse(didReturnBeforeResume)
        XCTAssertFalse(didFinishScanBeforeResume)

        await cursor2APIService.resume()
        await portService.resumeScan()
        try? await Task.sleep(for: .milliseconds(50))

        let didReturnAfterResume = await cursor2APIService.hasReturnedStatus()
        let didFinishScanAfterResume = await portService.hasFinishedScan()
        XCTAssertTrue(didReturnAfterResume)
        XCTAssertTrue(didFinishScanAfterResume)
        XCTAssertTrue(model.trackedPorts.contains(where: { $0.port == 9090 && $0.occupied }))
    }

    func testMakeWebRemoteReachableURLsIncludesLocalAndLANTargets() {
        let urls = ToolsPageModel.makeWebRemoteReachableURLs(
            httpPort: 9090,
            wsPort: 9091,
            token: "token-123",
            lanHosts: ["192.168.1.8", "10.0.0.6", "192.168.1.8"]
        )

        XCTAssertEqual(urls.count, 3)
        XCTAssertEqual(urls.first?.host, "127.0.0.1")
        XCTAssertEqual(urls.filter(\.isLAN).map(\.host), ["192.168.1.8", "10.0.0.6"])
        XCTAssertEqual(urls.first?.displayURL, "http://127.0.0.1:9090?wsPort=9091")
        XCTAssertEqual(urls.first?.browserURL, "http://127.0.0.1:9090?wsPort=9091#token=token-123")
    }

    func testWebRemoteAccessURLPrefersPrimaryReachableURL() async throws {
        let model = try makeModel()
        model.webRemoteStatus = WebRemoteStatus(
            running: true,
            httpPort: 9090,
            wsPort: 9091,
            connectedClients: 0,
            lastError: nil
        )
        model.webRemoteToken = "token-xyz"

        XCTAssertEqual(model.webRemoteAccessURL, "http://127.0.0.1:9090?wsPort=9091#token=token-xyz")
    }

    private func makeModel(
        cursor2APIService: any Cursor2APIServiceProtocol = StubCursor2APIService(),
        portService: any PortManagementServiceProtocol = StubPortManagementService()
    ) throws -> ToolsPageModel {
        let home = FileManager.default.temporaryDirectory
            .appendingPathComponent(UUID().uuidString, isDirectory: true)
        try FileManager.default.createDirectory(at: home, withIntermediateDirectories: true)

        let configService = ProviderConfigService(homeDirectory: home)

        let providerCoordinator = ProviderCoordinator(configService: configService)

        return ToolsPageModel(
            providerCoordinator: providerCoordinator,
            mcpCoordinator: MCPCoordinator(configService: configService),
            promptCoordinator: PromptCoordinator(configService: configService),
            skillCoordinator: SkillCoordinator(configService: configService),
            cursor2APIService: cursor2APIService,
            portService: portService,
            webCoordinator: makeStubWebCoordinator(providerCoordinator: providerCoordinator)
        )
    }

    private func makeStubWebCoordinator(providerCoordinator: ProviderCoordinator) -> WebCoordinator {
        let storeRepo = InMemoryAccountsStoreRepository(store: AccountsStore())
        let authRepo = ToolsTestAuthRepository()
        let accounts = AccountsCoordinator(
            storeRepository: storeRepo,
            authRepository: authRepo,
            usageService: ToolsTestUsageService(),
            workspaceMetadataService: ToolsTestWorkspaceMetadataService(),
            chatGPTOAuthLoginService: ToolsTestChatGPTOAuthLoginService(),
            codexCLIService: ToolsTestCodexCLIService(),
            editorAppService: ToolsTestEditorAppService(),
            opencodeAuthSyncService: ToolsTestOpencodeAuthSyncService()
        )
        let proxy = ProxyCoordinator(
            proxyService: ToolsTestProxyService(),
            cloudflaredService: ToolsTestCloudflaredService(),
            providerCoordinator: providerCoordinator
        )
        let sessionStore = AgentSessionStore(
            directory: FileManager.default.temporaryDirectory
                .appendingPathComponent(UUID().uuidString, isDirectory: true)
        )
        let agentRuntime = AgentRuntimeCoordinator(sessionStore: sessionStore)
        return WebCoordinator(
            accountsCoordinator: accounts,
            providerCoordinator: providerCoordinator,
            proxyCoordinator: proxy,
            authService: WebRemoteAuthService(),
            agentRuntime: agentRuntime
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
    func scanListeningPorts() async -> [ManagedPortStatus] { [] }
}

private actor BlockingCursor2APIService: Cursor2APIServiceProtocol {
    private var continuation: CheckedContinuation<Void, Never>?
    private var resumeRequested = false
    private(set) var didReturnStatus = false

    func status() async -> Cursor2APIStatus {
        if !resumeRequested {
            await withCheckedContinuation { continuation in
                self.continuation = continuation
            }
        }
        resumeRequested = false
        didReturnStatus = true
        return .idle
    }

    func install() async throws -> Cursor2APIStatus { .idle }

    func start(port: Int?, apiKey: String?, models: [String]) async throws -> Cursor2APIStatus {
        _ = port
        _ = apiKey
        _ = models
        return .idle
    }

    func stop() async -> Cursor2APIStatus { .idle }

    func hasReturnedStatus() -> Bool {
        didReturnStatus
    }

    func resume() {
        if let continuation {
            continuation.resume()
            self.continuation = nil
        } else {
            resumeRequested = true
        }
    }
}

private actor ConfigurablePortManagementService: PortManagementServiceProtocol {
    private let statuses: [Int: ManagedPortStatus]
    private let scannedPorts: [ManagedPortStatus]

    init(statuses: [Int: ManagedPortStatus] = [:], scannedPorts: [ManagedPortStatus]) {
        self.statuses = statuses
        self.scannedPorts = scannedPorts
    }

    func status(for port: Int) async -> ManagedPortStatus {
        statuses[port] ?? .idle(port: port)
    }

    func terminate(port: Int) async throws -> ManagedPortStatus {
        statuses[port] ?? .idle(port: port)
    }

    func forceKill(port: Int) async throws -> ManagedPortStatus {
        statuses[port] ?? .idle(port: port)
    }

    func scanListeningPorts() async -> [ManagedPortStatus] {
        scannedPorts
    }
}

private actor BlockingPortManagementService: PortManagementServiceProtocol {
    private let scannedPorts: [ManagedPortStatus]
    private var continuation: CheckedContinuation<Void, Never>?
    private var resumeRequested = false
    private(set) var didFinishScan = false

    init(scannedPorts: [ManagedPortStatus]) {
        self.scannedPorts = scannedPorts
    }

    func status(for port: Int) async -> ManagedPortStatus { .idle(port: port) }

    func terminate(port: Int) async throws -> ManagedPortStatus { .idle(port: port) }

    func forceKill(port: Int) async throws -> ManagedPortStatus { .idle(port: port) }

    func scanListeningPorts() async -> [ManagedPortStatus] {
        if !resumeRequested {
            await withCheckedContinuation { continuation in
                self.continuation = continuation
            }
        }
        resumeRequested = false
        didFinishScan = true
        return scannedPorts
    }

    func hasFinishedScan() -> Bool {
        didFinishScan
    }

    func resumeScan() {
        if let continuation {
            continuation.resume()
            self.continuation = nil
        } else {
            resumeRequested = true
        }
    }
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

    func scanListeningPorts() async -> [ManagedPortStatus] { [] }
}

// Stubs for WebCoordinator dependencies
private final class ToolsTestAuthRepository: AuthRepository, @unchecked Sendable {
    func readCurrentAuth() throws -> JSONValue { .null }
    func readCurrentAuthOptional() throws -> JSONValue? { nil }
    func readAuth(from url: URL) throws -> JSONValue { .null }
    func writeCurrentAuth(_ auth: JSONValue) throws {}
    func removeCurrentAuth() throws {}
    func makeChatGPTAuth(from tokens: ChatGPTOAuthTokens) throws -> JSONValue { .null }
    func extractAuth(from auth: JSONValue) throws -> ExtractedAuth { ExtractedAuth(accountID: "", accessToken: "") }
    func currentAuthAccountID() -> String? { nil }
}
private struct ToolsTestUsageService: UsageService {
    func fetchUsage(accessToken: String, accountID: String) async throws -> UsageSnapshot { UsageSnapshot(fetchedAt: 0) }
}
private struct ToolsTestWorkspaceMetadataService: WorkspaceMetadataService {
    func fetchWorkspaceMetadata(accessToken: String) async throws -> [WorkspaceMetadata] { [] }
}
private struct ToolsTestChatGPTOAuthLoginService: ChatGPTOAuthLoginServiceProtocol {
    func signInWithChatGPT(timeoutSeconds: TimeInterval) async throws -> ChatGPTOAuthTokens { throw AppError.unauthorized("stub") }
}
private struct ToolsTestCodexCLIService: CodexCLIServiceProtocol {
    func launchApp(workspacePath: String?) async throws -> Bool { false }
}
private struct ToolsTestEditorAppService: EditorAppServiceProtocol {
    func listInstalledApps() -> [InstalledEditorApp] { [] }
    func restartSelectedApps(_ targets: [EditorAppID]) async -> (restarted: [EditorAppID], error: String?) { ([], nil) }
}
private struct ToolsTestOpencodeAuthSyncService: OpencodeAuthSyncServiceProtocol {
    func syncFromCodexAuth(_ authJSON: JSONValue) throws {}
}
private struct ToolsTestProxyService: ProxyRuntimeService {
    func status() async -> ApiProxyStatus { .idle }
    func start(preferredPort: Int?) async throws -> ApiProxyStatus { .idle }
    func stop() async -> ApiProxyStatus { .idle }
    func refreshAPIKey() async throws -> ApiProxyStatus { .idle }
    func syncAccountsStore() async throws {}
}
private struct ToolsTestCloudflaredService: CloudflaredServiceProtocol {
    func status() async -> CloudflaredStatus { .idle }
    func install() async throws -> CloudflaredStatus { .idle }
    func start(_ input: StartCloudflaredTunnelInput) async throws -> CloudflaredStatus { .idle }
    func stop() async -> CloudflaredStatus { .idle }
}
