import XCTest
@testable import AIMenu

@MainActor
final class ProxyPageModelTests: XCTestCase {
    func testCloudflaredNamedInputReadyRequiresAllFields() {
        let model = makeModel()

        model.cloudflaredNamedInput = NamedCloudflaredTunnelInput(
            apiToken: "token",
            accountID: "",
            zoneID: "zone",
            hostname: "api.example.com"
        )
        XCTAssertFalse(model.cloudflaredNamedInputReady)

        model.cloudflaredNamedInput.accountID = "account"
        XCTAssertTrue(model.cloudflaredNamedInputReady)
    }

    func testCanStartCloudflaredDependsOnProxyStateAndTunnelMode() {
        let model = makeModel()
        model.proxyStatus = ApiProxyStatus(
            running: true,
            port: 8787,
            apiKey: nil,
            baseURL: nil,
            availableAccounts: 1,
            activeAccountID: nil,
            activeAccountLabel: nil,
            lastError: nil
        )
        model.cloudflaredStatus = CloudflaredStatus(
            installed: true,
            binaryPath: "/usr/local/bin/cloudflared",
            running: false,
            tunnelMode: nil,
            publicURL: nil,
            customHostname: nil,
            useHTTP2: false,
            lastError: nil
        )

        model.cloudflaredTunnelMode = .quick
        XCTAssertTrue(model.canStartCloudflared)

        model.cloudflaredTunnelMode = .named
        XCTAssertFalse(model.canStartCloudflared)

        model.cloudflaredNamedInput = NamedCloudflaredTunnelInput(
            apiToken: "token",
            accountID: "account",
            zoneID: "zone",
            hostname: "api.example.com"
        )
        XCTAssertTrue(model.canStartCloudflared)
    }

    func testStartProxyAutoGeneratesManagedCodexProvider() async throws {
        let tempHome = try makeTemporaryHome()
        defer { try? FileManager.default.removeItem(at: tempHome) }

        let service = ProviderConfigService(homeDirectory: tempHome)
        let providerCoordinator = ProviderCoordinator(configService: service)
        let proxyCoordinator = ProxyCoordinator(
            proxyService: RunningStubProxyRuntimeService(
                runningStatus: ApiProxyStatus(
                    running: true,
                    port: 8787,
                    apiKey: "cp_live_key",
                    baseURL: "http://127.0.0.1:8787/v1",
                    availableAccounts: 2,
                    activeAccountID: nil,
                    activeAccountLabel: nil,
                    lastError: nil
                )
            ),
            cloudflaredService: StubCloudflaredService(),
            providerCoordinator: providerCoordinator
        )
        let model = ProxyPageModel(
            coordinator: proxyCoordinator,
            settingsCoordinator: makeSettingsCoordinator()
        )

        await model.startProxy()

        let store = try await service.loadProviderStore()
        XCTAssertEqual(store.providers.count, 1)
        XCTAssertEqual(store.providers.first?.name, ProviderCoordinator.managedCodexProxyName)
        XCTAssertEqual(store.currentCodexProviderId, store.providers.first?.id)
    }

    private func makeModel() -> ProxyPageModel {
        let providerCoordinator = ProviderCoordinator(
            configService: ProviderConfigService(homeDirectory: try? makeTemporaryHome())
        )
        let proxyCoordinator = ProxyCoordinator(
            proxyService: StubProxyRuntimeService(),
            cloudflaredService: StubCloudflaredService(),
            providerCoordinator: providerCoordinator
        )

        return ProxyPageModel(
            coordinator: proxyCoordinator,
            settingsCoordinator: makeSettingsCoordinator()
        )
    }

    private func makeTemporaryHome() throws -> URL {
        let directory = FileManager.default.temporaryDirectory
            .appendingPathComponent(UUID().uuidString, isDirectory: true)
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        return directory
    }

    private func makeSettingsCoordinator() -> SettingsCoordinator {
        SettingsCoordinator(
            storeRepository: InMemoryAccountsStoreRepository(store: AccountsStore()),
            launchAtStartupService: StubLaunchAtStartupService()
        )
    }
}

private final class InMemoryAccountsStoreRepository: AccountsStoreRepository, @unchecked Sendable {
    private var store: AccountsStore

    init(store: AccountsStore) {
        self.store = store
    }

    func loadStore() throws -> AccountsStore {
        store
    }

    func saveStore(_ store: AccountsStore) throws {
        self.store = store
    }
}

private struct StubLaunchAtStartupService: LaunchAtStartupServiceProtocol {
    func setEnabled(_ enabled: Bool) throws {
        _ = enabled
    }

    func syncWithStoreValue(_ enabled: Bool) throws {
        _ = enabled
    }
}

private struct StubProxyRuntimeService: ProxyRuntimeService {
    func status() async -> ApiProxyStatus { .idle }
    func start(preferredPort: Int?) async throws -> ApiProxyStatus {
        _ = preferredPort
        return .idle
    }
    func stop() async -> ApiProxyStatus { .idle }
    func refreshAPIKey() async throws -> ApiProxyStatus { .idle }
    func syncAccountsStore() async throws {}
}

private struct RunningStubProxyRuntimeService: ProxyRuntimeService {
    let runningStatus: ApiProxyStatus

    func status() async -> ApiProxyStatus { runningStatus }
    func start(preferredPort: Int?) async throws -> ApiProxyStatus {
        _ = preferredPort
        return runningStatus
    }
    func stop() async -> ApiProxyStatus { .idle }
    func refreshAPIKey() async throws -> ApiProxyStatus { runningStatus }
    func syncAccountsStore() async throws {}
}

private struct StubCloudflaredService: CloudflaredServiceProtocol {
    func status() async -> CloudflaredStatus { .idle }
    func install() async throws -> CloudflaredStatus { .idle }
    func start(_ input: StartCloudflaredTunnelInput) async throws -> CloudflaredStatus {
        _ = input
        return .idle
    }
    func stop() async -> CloudflaredStatus { .idle }
}
