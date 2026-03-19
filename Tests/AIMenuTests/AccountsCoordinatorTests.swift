import XCTest
@testable import AIMenu

final class AccountsCoordinatorTests: XCTestCase {
    func testListAccountsBackfillsWorkspaceNameFromRemoteMetadata() async throws {
        let now: Int64 = 1_763_216_000
        let storeRepository = InMemoryAccountsStoreRepository(
            store: AccountsStore(
                version: 1,
                accounts: [
                    StoredAccount(
                        id: "acct-1",
                        label: "Team",
                        email: "test@example.com",
                        accountID: "account-1",
                        planType: "team",
                        teamName: nil,
                        teamAlias: nil,
                        authJSON: .object([:]),
                        addedAt: now,
                        updatedAt: now,
                        usage: nil,
                        usageError: nil
                    )
                ],
                currentSelection: nil,
                settings: .defaultValue
            )
        )
        let coordinator = AccountsCoordinator(
            storeRepository: storeRepository,
            authRepository: RemoteLookupAuthRepository(),
            usageService: CountingUsageService(
                result: UsageSnapshot(
                    fetchedAt: now,
                    planType: "team",
                    fiveHour: nil,
                    oneWeek: nil,
                    credits: nil
                )
            ),
            workspaceMetadataService: StubWorkspaceMetadataService(
                metadata: [WorkspaceMetadata(accountID: "account-1", workspaceName: "remote-space", structure: "workspace")]
            ),
            chatGPTOAuthLoginService: StubChatGPTOAuthLoginService(),
            codexCLIService: StubCodexCLIService(),
            editorAppService: StubEditorAppService(),
            opencodeAuthSyncService: StubOpencodeAuthSyncService(),
            dateProvider: FixedDateProvider(now: now)
        )

        let accounts = try await coordinator.listAccounts()
        let savedStore = try storeRepository.loadStore()

        XCTAssertEqual(accounts.first?.teamName, "remote-space")
        XCTAssertEqual(savedStore.accounts.first?.teamName, "remote-space")
    }

    func testListAccountsReconcilesStoredWorkspaceMetadataFromAuthJSON() async throws {
        let now: Int64 = 1_763_216_000
        let storeRepository = InMemoryAccountsStoreRepository(
            store: AccountsStore(
                version: 1,
                accounts: [
                    StoredAccount(
                        id: "acct-1",
                        label: "Test",
                        email: nil,
                        accountID: "account-1",
                        planType: nil,
                        teamName: nil,
                        teamAlias: nil,
                        authJSON: .object([:]),
                        addedAt: now,
                        updatedAt: now,
                        usage: nil,
                        usageError: nil
                    )
                ],
                currentSelection: nil,
                settings: .defaultValue
            )
        )
        let coordinator = AccountsCoordinator(
            storeRepository: storeRepository,
            authRepository: StubAuthRepository(),
            usageService: CountingUsageService(
                result: UsageSnapshot(
                    fetchedAt: now,
                    planType: "team",
                    fiveHour: nil,
                    oneWeek: nil,
                    credits: nil
                )
            ),
            chatGPTOAuthLoginService: StubChatGPTOAuthLoginService(),
            codexCLIService: StubCodexCLIService(),
            editorAppService: StubEditorAppService(),
            opencodeAuthSyncService: StubOpencodeAuthSyncService(),
            dateProvider: FixedDateProvider(now: now)
        )

        let accounts = try await coordinator.listAccounts()
        let savedStore = try storeRepository.loadStore()

        XCTAssertEqual(accounts.first?.email, "test@example.com")
        XCTAssertEqual(accounts.first?.planType, "pro")
        XCTAssertEqual(accounts.first?.teamName, "workspace-x")
        XCTAssertEqual(savedStore.accounts.first?.teamName, "workspace-x")
    }

    func testImportCurrentAuthPrefersRemoteWorkspaceMetadata() async throws {
        let now: Int64 = 1_763_216_000
        let storeRepository = InMemoryAccountsStoreRepository(store: AccountsStore())
        let coordinator = AccountsCoordinator(
            storeRepository: storeRepository,
            authRepository: RemoteLookupAuthRepository(),
            usageService: CountingUsageService(
                result: UsageSnapshot(
                    fetchedAt: now,
                    planType: "team",
                    fiveHour: nil,
                    oneWeek: nil,
                    credits: nil
                )
            ),
            workspaceMetadataService: StubWorkspaceMetadataService(
                metadata: [WorkspaceMetadata(accountID: "account-1", workspaceName: "remote-space", structure: "workspace")]
            ),
            chatGPTOAuthLoginService: StubChatGPTOAuthLoginService(),
            codexCLIService: StubCodexCLIService(),
            editorAppService: StubEditorAppService(),
            opencodeAuthSyncService: StubOpencodeAuthSyncService(),
            dateProvider: FixedDateProvider(now: now)
        )

        let imported = try await coordinator.importCurrentAuthAccount(customLabel: nil)
        let savedStore = try storeRepository.loadStore()

        XCTAssertEqual(imported.teamName, "remote-space")
        XCTAssertEqual(savedStore.accounts.first?.teamName, "remote-space")
    }

    func testForcedRefreshBypassesUsageThrottle() async throws {
        let now: Int64 = 1_763_216_000
        let existingUsage = UsageSnapshot(
            fetchedAt: now,
            planType: "pro",
            fiveHour: UsageWindow(usedPercent: 10, windowSeconds: 18_000, resetAt: nil),
            oneWeek: UsageWindow(usedPercent: 20, windowSeconds: 604_800, resetAt: nil),
            credits: nil
        )
        let store = AccountsStore(
            version: 1,
            accounts: [
                StoredAccount(
                    id: "acct-1",
                    label: "Test",
                    email: "test@example.com",
                    accountID: "account-1",
                    planType: "pro",
                    teamName: nil,
                    teamAlias: nil,
                    authJSON: .object([:]),
                    addedAt: now,
                    updatedAt: now,
                    usage: existingUsage,
                    usageError: nil
                )
            ],
            currentSelection: nil,
            settings: .defaultValue
        )
        let usageService = CountingUsageService(result: existingUsage)
        let coordinator = AccountsCoordinator(
            storeRepository: InMemoryAccountsStoreRepository(store: store),
            authRepository: StubAuthRepository(),
            usageService: usageService,
            chatGPTOAuthLoginService: StubChatGPTOAuthLoginService(),
            codexCLIService: StubCodexCLIService(),
            editorAppService: StubEditorAppService(),
            opencodeAuthSyncService: StubOpencodeAuthSyncService(),
            dateProvider: FixedDateProvider(now: now)
        )

        _ = try await coordinator.refreshAllUsage()
        XCTAssertEqual(usageService.callCount, 0)

        _ = try await coordinator.refreshAllUsage(force: true)
        XCTAssertEqual(usageService.callCount, 1)
    }

    @MainActor
    func testAccountsPageModelBootstrapsFromInitialAccounts() {
        let account = AccountSummary(
            id: "acct-1",
            label: "Bootstrap",
            email: "bootstrap@example.com",
            accountID: "account-1",
            planType: "pro",
            teamName: nil,
            teamAlias: nil,
            addedAt: 1,
            updatedAt: 1,
            usage: nil,
            usageError: nil,
            isCurrent: true
        )
        let coordinator = AccountsCoordinator(
            storeRepository: InMemoryAccountsStoreRepository(store: AccountsStore()),
            authRepository: StubAuthRepository(),
            usageService: CountingUsageService(
                result: UsageSnapshot(
                    fetchedAt: 1,
                    planType: "pro",
                    fiveHour: nil,
                    oneWeek: nil,
                    credits: nil
                )
            ),
            chatGPTOAuthLoginService: StubChatGPTOAuthLoginService(),
            codexCLIService: StubCodexCLIService(),
            editorAppService: StubEditorAppService(),
            opencodeAuthSyncService: StubOpencodeAuthSyncService()
        )
        let model = AccountsPageModel(
            coordinator: coordinator,
            onLocalAccountsChanged: nil,
            initialAccounts: [account]
        )

        XCTAssertTrue(model.hasResolvedInitialState)
        XCTAssertEqual(model.state, AccountsPageModel.makeViewState(accounts: [account]))
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

private final class CountingUsageService: UsageService, @unchecked Sendable {
    private(set) var callCount = 0
    private let result: UsageSnapshot

    init(result: UsageSnapshot) {
        self.result = result
    }

    func fetchUsage(accessToken: String, accountID: String) async throws -> UsageSnapshot {
        _ = accessToken
        _ = accountID
        callCount += 1
        return result
    }
}

private struct FixedDateProvider: DateProviding {
    let now: Int64

    func unixSecondsNow() -> Int64 {
        now
    }
}

private final class StubWorkspaceMetadataService: WorkspaceMetadataService, @unchecked Sendable {
    private let metadata: [WorkspaceMetadata]

    init(metadata: [WorkspaceMetadata]) {
        self.metadata = metadata
    }

    func fetchWorkspaceMetadata(accessToken: String) async throws -> [WorkspaceMetadata] {
        _ = accessToken
        return metadata
    }
}

private final class StubAuthRepository: AuthRepository, @unchecked Sendable {
    func readCurrentAuth() throws -> JSONValue { .null }
    func readCurrentAuthOptional() throws -> JSONValue? { nil }
    func readAuth(from url: URL) throws -> JSONValue {
        _ = url
        return .null
    }
    func writeCurrentAuth(_ auth: JSONValue) throws {
        _ = auth
    }
    func removeCurrentAuth() throws {}
    func makeChatGPTAuth(from tokens: ChatGPTOAuthTokens) throws -> JSONValue {
        _ = tokens
        return .null
    }
    func extractAuth(from auth: JSONValue) throws -> ExtractedAuth {
        _ = auth
        return ExtractedAuth(
            accountID: "account-1",
            accessToken: "token-1",
            email: "test@example.com",
            planType: "pro",
            teamName: "workspace-x"
        )
    }
    func currentAuthAccountID() -> String? { "account-1" }
}

private final class RemoteLookupAuthRepository: AuthRepository, @unchecked Sendable {
    func readCurrentAuth() throws -> JSONValue { .object([:]) }
    func readCurrentAuthOptional() throws -> JSONValue? { .object([:]) }
    func readAuth(from url: URL) throws -> JSONValue {
        _ = url
        return .object([:])
    }
    func writeCurrentAuth(_ auth: JSONValue) throws {
        _ = auth
    }
    func removeCurrentAuth() throws {}
    func makeChatGPTAuth(from tokens: ChatGPTOAuthTokens) throws -> JSONValue {
        _ = tokens
        return .object([:])
    }
    func extractAuth(from auth: JSONValue) throws -> ExtractedAuth {
        _ = auth
        return ExtractedAuth(
            accountID: "account-1",
            accessToken: "token-1",
            email: "test@example.com",
            planType: "team",
            teamName: nil
        )
    }
    func currentAuthAccountID() -> String? { "account-1" }
}

private final class RecordingAuthRepository: AuthRepository, @unchecked Sendable {
    private(set) var writtenAccountCount = 0
    private let currentAccountIDValue: String?

    init(currentAccountID: String?) {
        self.currentAccountIDValue = currentAccountID
    }

    func readCurrentAuth() throws -> JSONValue { .null }
    func readCurrentAuthOptional() throws -> JSONValue? { nil }
    func readAuth(from url: URL) throws -> JSONValue {
        _ = url
        return .null
    }
    func writeCurrentAuth(_ auth: JSONValue) throws {
        _ = auth
        writtenAccountCount += 1
    }
    func removeCurrentAuth() throws {}
    func makeChatGPTAuth(from tokens: ChatGPTOAuthTokens) throws -> JSONValue {
        _ = tokens
        return .null
    }
    func extractAuth(from auth: JSONValue) throws -> ExtractedAuth {
        _ = auth
        return ExtractedAuth(
            accountID: "account-1",
            accessToken: "token-1",
            email: "test@example.com",
            planType: "pro",
            teamName: "workspace-x"
        )
    }
    func currentAuthAccountID() -> String? { currentAccountIDValue }
}

private final class StubChatGPTOAuthLoginService: ChatGPTOAuthLoginServiceProtocol, @unchecked Sendable {
    func signInWithChatGPT(timeoutSeconds: TimeInterval) async throws -> ChatGPTOAuthTokens {
        _ = timeoutSeconds
        return ChatGPTOAuthTokens(accessToken: "", refreshToken: "", idToken: "", apiKey: nil)
    }
}

private final class StubCodexCLIService: CodexCLIServiceProtocol, @unchecked Sendable {
    func launchApp(workspacePath: String?) throws -> Bool {
        _ = workspacePath
        return false
    }
}

private final class RecordingCodexCLIService: CodexCLIServiceProtocol, @unchecked Sendable {
    private(set) var launchCallCount = 0

    func launchApp(workspacePath: String?) throws -> Bool {
        _ = workspacePath
        launchCallCount += 1
        return false
    }
}

private final class StubEditorAppService: EditorAppServiceProtocol, @unchecked Sendable {
    func listInstalledApps() -> [InstalledEditorApp] { [] }
    func restartSelectedApps(_ targets: [EditorAppID]) -> (restarted: [EditorAppID], error: String?) {
        _ = targets
        return ([], nil)
    }
}

private final class RecordingEditorAppService: EditorAppServiceProtocol, @unchecked Sendable {
    private(set) var restartCallCount = 0

    func listInstalledApps() -> [InstalledEditorApp] { [] }

    func restartSelectedApps(_ targets: [EditorAppID]) -> (restarted: [EditorAppID], error: String?) {
        _ = targets
        restartCallCount += 1
        return ([], nil)
    }
}

private final class StubOpencodeAuthSyncService: OpencodeAuthSyncServiceProtocol, @unchecked Sendable {
    func syncFromCodexAuth(_ authJSON: JSONValue) throws {
        _ = authJSON
    }
}
