import XCTest
@testable import AIMenu

final class ClaudeHooksTests: XCTestCase {
    func testListClaudeHooksParsesNestedHookGroups() async throws {
        let tempHome = try makeTemporaryHome()
        defer { try? FileManager.default.removeItem(at: tempHome) }

        let service = ProviderConfigService(homeDirectory: tempHome)
        let coordinator = ProviderCoordinator(configService: service)
        let settingsPath = tempHome.appendingPathComponent(".claude/settings.json")

        try FileManager.default.createDirectory(at: settingsPath.deletingLastPathComponent(), withIntermediateDirectories: true)
        let settings = """
        {
          "hooks": {
            "PreToolUse": [
              {
                "matcher": "Edit|Write",
                "hooks": [
                  {
                    "type": "command",
                    "command": "echo before-edit",
                    "timeout": 15
                  },
                  {
                    "type": "command",
                    "command": "npm test"
                  }
                ]
              }
            ],
            "Stop": [
              {
                "hooks": [
                  {
                    "type": "command",
                    "command": "say done"
                  }
                ]
              }
            ]
          }
        }
        """
        try settings.write(to: settingsPath, atomically: true, encoding: .utf8)

        let hooks = try await coordinator.listClaudeHooks()

        XCTAssertEqual(hooks.count, 3)
        XCTAssertEqual(hooks.first?.scope, .user)
        XCTAssertEqual(hooks.first?.sourcePath, settingsPath.path)

        let beforeEdit = try XCTUnwrap(hooks.first(where: { $0.command == "echo before-edit" }))
        XCTAssertEqual(beforeEdit.event, "PreToolUse")
        XCTAssertEqual(beforeEdit.matcher, "Edit|Write")
        XCTAssertEqual(beforeEdit.commandType, "command")
        XCTAssertEqual(beforeEdit.timeout, 15)

        let stopHook = try XCTUnwrap(hooks.first(where: { $0.command == "say done" }))
        XCTAssertEqual(stopHook.event, "Stop")
        XCTAssertNil(stopHook.matcher)
    }

    func testListClaudeHooksDoesNotPersistHookStoreOnRead() async throws {
        let tempHome = try makeTemporaryHome()
        defer { try? FileManager.default.removeItem(at: tempHome) }

        let service = ProviderConfigService(homeDirectory: tempHome)
        let coordinator = ProviderCoordinator(configService: service)
        let settingsPath = tempHome.appendingPathComponent(".claude/settings.json")
        let hookStorePath = tempHome.appendingPathComponent("Library/Application Support/AIMenu/hooks.json")

        try FileManager.default.createDirectory(at: settingsPath.deletingLastPathComponent(), withIntermediateDirectories: true)
        let settings = """
        {
          "hooks": {
            "Stop": [
              {
                "hooks": [
                  {
                    "type": "command",
                    "command": "echo stop"
                  }
                ]
              }
            ]
          }
        }
        """
        try settings.write(to: settingsPath, atomically: true, encoding: .utf8)

        _ = try await coordinator.listClaudeHooks()

        XCTAssertEqual(try String(contentsOf: settingsPath, encoding: .utf8), settings)
        XCTAssertFalse(FileManager.default.fileExists(atPath: hookStorePath.path))
    }

    func testListClaudeHooksKeepsDistinctHooksWhenIDsDiffer() async throws {
        let tempHome = try makeTemporaryHome()
        defer { try? FileManager.default.removeItem(at: tempHome) }

        let service = ProviderConfigService(homeDirectory: tempHome)
        let coordinator = ProviderCoordinator(configService: service)
        let settingsPath = tempHome.appendingPathComponent(".claude/settings.json")

        try FileManager.default.createDirectory(at: settingsPath.deletingLastPathComponent(), withIntermediateDirectories: true)
        let settings = """
        {
          "hooks": {
            "Stop": [
              {
                "hooks": [
                  {
                    "id": "hook-a",
                    "type": "command",
                    "command": "echo same"
                  },
                  {
                    "id": "hook-b",
                    "type": "command",
                    "command": "echo same"
                  }
                ]
              }
            ]
          }
        }
        """
        try settings.write(to: settingsPath, atomically: true, encoding: .utf8)

        let hooks = try await coordinator.listClaudeHooks()

        XCTAssertEqual(hooks.count, 2)
        XCTAssertEqual(Set(hooks.map(\.id)), ["hook-a", "hook-b"])
        XCTAssertEqual(Set(hooks.map(\.identityKey)).count, 2)
    }

    func testListClaudeHooksSupportsLegacyFlatEntries() async throws {
        let tempHome = try makeTemporaryHome()
        defer { try? FileManager.default.removeItem(at: tempHome) }

        let service = ProviderConfigService(homeDirectory: tempHome)
        let coordinator = ProviderCoordinator(configService: service)
        let settingsPath = tempHome.appendingPathComponent(".claude/settings.json")

        try FileManager.default.createDirectory(at: settingsPath.deletingLastPathComponent(), withIntermediateDirectories: true)
        let settings = """
        {
          "hooks": {
            "Notification": [
              {
                "matcher": "build",
                "command": "echo notify",
                "type": "command",
                "timeout": 8
              }
            ]
          }
        }
        """
        try settings.write(to: settingsPath, atomically: true, encoding: .utf8)

        let hooks = try await coordinator.listClaudeHooks()

        XCTAssertEqual(hooks.count, 1)
        XCTAssertEqual(hooks[0].event, "Notification")
        XCTAssertEqual(hooks[0].matcher, "build")
        XCTAssertEqual(hooks[0].command, "echo notify")
        XCTAssertEqual(hooks[0].timeout, 8)
        XCTAssertEqual(hooks[0].commandType, "command")
    }

    // MARK: - Helpers

    private func makeTemporaryHome() throws -> URL {
        let directory = FileManager.default.temporaryDirectory
            .appendingPathComponent(UUID().uuidString, isDirectory: true)
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        return directory
    }
}
