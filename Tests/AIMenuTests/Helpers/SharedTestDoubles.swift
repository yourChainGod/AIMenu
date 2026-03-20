import XCTest
@testable import AIMenu

// MARK: - InMemoryAccountsStoreRepository

/// Thread-safe for tests: only accessed from @MainActor test methods.
final class InMemoryAccountsStoreRepository: AccountsStoreRepository, @unchecked Sendable {
    private var store: AccountsStore

    init(store: AccountsStore = AccountsStore(settings: .defaultValue)) {
        self.store = store
    }

    func loadStore() throws -> AccountsStore {
        store
    }

    func saveStore(_ store: AccountsStore) throws {
        self.store = store
    }
}

// MARK: - StubLaunchAtStartupService

struct StubLaunchAtStartupService: LaunchAtStartupServiceProtocol {
    func setEnabled(_ enabled: Bool) throws {
        _ = enabled
    }

    func syncWithStoreValue(_ enabled: Bool) throws {
        _ = enabled
    }
}

// MARK: - StubEditorAppService

/// Thread-safe for tests: only accessed from @MainActor test methods.
final class StubEditorAppService: EditorAppServiceProtocol, @unchecked Sendable {
    private let apps: [InstalledEditorApp]

    init(apps: [InstalledEditorApp] = []) {
        self.apps = apps
    }

    func listInstalledApps() -> [InstalledEditorApp] {
        apps
    }

    func restartSelectedApps(_ targets: [EditorAppID]) async -> (restarted: [EditorAppID], error: String?) {
        _ = targets
        return ([], nil)
    }
}
