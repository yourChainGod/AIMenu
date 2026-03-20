import XCTest
@testable import AIMenu

@MainActor
final class SettingsPageModelTests: XCTestCase {
    func testSetRestartEditorsOnSwitchRequiresInstalledEditor() async throws {
        let repository = InMemoryAccountsStoreRepository()
        let coordinator = SettingsCoordinator(
            storeRepository: repository,
            launchAtStartupService: LaunchAtStartupServiceStub()
        )
        let model = SettingsPageModel(
            settingsCoordinator: coordinator,
            editorAppService: EditorAppServiceStub(apps: [])
        )

        await model.load()
        model.setRestartEditorsOnSwitch(true)
        try await Task.sleep(nanoseconds: 80_000_000)

        XCTAssertFalse(model.settings.restartEditorsOnSwitch)
        XCTAssertEqual(model.settings.restartEditorTargets, [])
        XCTAssertEqual(model.notice?.text, L10n.tr("error.editor.no_restart_target_selected"))
    }

    func testSetRestartEditorsOnSwitchAutoSelectsFirstInstalledEditor() async throws {
        let repository = InMemoryAccountsStoreRepository()
        let coordinator = SettingsCoordinator(
            storeRepository: repository,
            launchAtStartupService: LaunchAtStartupServiceStub()
        )
        let model = SettingsPageModel(
            settingsCoordinator: coordinator,
            editorAppService: EditorAppServiceStub(
                apps: [
                    InstalledEditorApp(id: .cursor, label: "Cursor"),
                    InstalledEditorApp(id: .vscode, label: "VS Code")
                ]
            )
        )

        await model.load()
        model.setRestartEditorsOnSwitch(true)
        try await Task.sleep(nanoseconds: 80_000_000)

        XCTAssertTrue(model.settings.restartEditorsOnSwitch)
        XCTAssertEqual(model.settings.restartEditorTargets, [.cursor])
    }
}

private final class InMemoryAccountsStoreRepository: AccountsStoreRepository, @unchecked Sendable {
    private var store = AccountsStore(settings: .defaultValue)

    func loadStore() throws -> AccountsStore {
        store
    }

    func saveStore(_ store: AccountsStore) throws {
        self.store = store
    }
}

private struct LaunchAtStartupServiceStub: LaunchAtStartupServiceProtocol {
    func setEnabled(_ enabled: Bool) throws {}
    func syncWithStoreValue(_ enabled: Bool) throws {}
}

private struct EditorAppServiceStub: EditorAppServiceProtocol {
    let apps: [InstalledEditorApp]

    func listInstalledApps() -> [InstalledEditorApp] {
        apps
    }

    func restartSelectedApps(_ targets: [EditorAppID]) -> (restarted: [EditorAppID], error: String?) {
        (targets, nil)
    }
}
