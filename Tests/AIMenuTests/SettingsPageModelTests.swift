import Combine
import XCTest
@testable import AIMenu

@MainActor
final class SettingsPageModelTests: XCTestCase {
    func testSetRestartEditorsOnSwitchRequiresInstalledEditor() async throws {
        let repository = InMemoryAccountsStoreRepository()
        let coordinator = SettingsCoordinator(
            storeRepository: repository,
            launchAtStartupService: StubLaunchAtStartupService()
        )
        let model = SettingsPageModel(
            settingsCoordinator: coordinator,
            editorAppService: StubEditorAppService(apps: [])
        )

        await model.load()
        model.setRestartEditorsOnSwitch(true)

        // No async Task is spawned when no editors are installed;
        // notice is set synchronously, so assertions are safe immediately.
        XCTAssertFalse(model.settings.restartEditorsOnSwitch)
        XCTAssertEqual(model.settings.restartEditorTargets, [])
        XCTAssertEqual(model.notice?.text, L10n.tr("error.editor.no_restart_target_selected"))
    }

    func testSetRestartEditorsOnSwitchAutoSelectsFirstInstalledEditor() async throws {
        let repository = InMemoryAccountsStoreRepository()
        let coordinator = SettingsCoordinator(
            storeRepository: repository,
            launchAtStartupService: StubLaunchAtStartupService()
        )
        let model = SettingsPageModel(
            settingsCoordinator: coordinator,
            editorAppService: StubEditorAppService(
                apps: [
                    InstalledEditorApp(id: .cursor, label: "Cursor"),
                    InstalledEditorApp(id: .vscode, label: "VS Code")
                ]
            )
        )

        await model.load()
        model.setRestartEditorsOnSwitch(true)

        // setRestartEditorsOnSwitch spawns a fire-and-forget Task on MainActor.
        // Wait for the @Published settings property to reflect the update.
        let settingsUpdated = expectation(description: "settings.restartEditorsOnSwitch becomes true")
        let cancellable = model.$settings
            .dropFirst()
            .sink { settings in
                if settings.restartEditorsOnSwitch {
                    settingsUpdated.fulfill()
                }
            }
        await fulfillment(of: [settingsUpdated], timeout: 2)
        cancellable.cancel()

        XCTAssertTrue(model.settings.restartEditorsOnSwitch)
        XCTAssertEqual(model.settings.restartEditorTargets, [.cursor])
    }
}

// InMemoryAccountsStoreRepository is defined in Helpers/SharedTestDoubles.swift
// StubLaunchAtStartupService is defined in Helpers/SharedTestDoubles.swift
// StubEditorAppService is defined in Helpers/SharedTestDoubles.swift
