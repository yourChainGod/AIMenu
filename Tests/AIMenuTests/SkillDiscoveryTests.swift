import XCTest
@testable import AIMenu

final class SkillDiscoveryTests: XCTestCase {
    func testReadInstalledSkillDocumentLoadsSkillMarkdown() async throws {
        let tempHome = try makeTemporaryHome()
        defer { try? FileManager.default.removeItem(at: tempHome) }

        let service = ProviderConfigService(homeDirectory: tempHome)
        let coordinator = SkillCoordinator(configService: service)
        let skillDir = tempHome.appendingPathComponent(".claude/skills/demo-skill", isDirectory: true)
        let skillPath = skillDir.appendingPathComponent("SKILL.md", isDirectory: false)
        let managedSkillPath = tempHome
            .appendingPathComponent("Library/Application Support/AIMenu/skills/demo-skill", isDirectory: true)
            .appendingPathComponent("SKILL.md", isDirectory: false)

        try FileManager.default.createDirectory(at: skillDir, withIntermediateDirectories: true)
        try """
        # Demo Skill

        A compact description.
        """.write(to: skillPath, atomically: true, encoding: .utf8)

        _ = try await coordinator.syncInstalledSkillsFromDisk()
        let document = try await coordinator.readInstalledSkillDocument(directory: "demo-skill")

        XCTAssertEqual(document.skill.name, "Demo Skill")
        XCTAssertEqual(document.skill.description, "A compact description.")
        XCTAssertEqual(document.path, managedSkillPath.path)
        XCTAssertTrue(document.content.contains("# Demo Skill"))
        XCTAssertTrue(FileManager.default.fileExists(atPath: managedSkillPath.path))
    }

    func testReadDiscoverableSkillDocumentLoadsRemoteSkillMarkdown() async throws {
        let tempHome = try makeTemporaryHome()
        defer { try? FileManager.default.removeItem(at: tempHome) }

        let service = ProviderConfigService(homeDirectory: tempHome)
        let coordinator = SkillCoordinator(
            configService: service,
            gitHubFileLoader: { owner, repo, branch, path in
                guard owner == "demo",
                      repo == "skill-repo",
                      branch == "main",
                      path == "examples/helper/SKILL.md" else {
                    throw NSError(domain: "SkillDiscoveryTests", code: 1)
                }

                return """
                # Remote Skill

                Remote description.
                """
            }
        )

        let skill = DiscoverableSkill(
            key: "demo/skill-repo:examples/helper",
            name: "Helper",
            description: nil,
            readmeUrl: "https://github.com/demo/skill-repo/tree/main/examples/helper",
            repoOwner: "demo",
            repoName: "skill-repo",
            repoBranch: "main",
            directory: "examples/helper",
            isInstalled: false
        )

        let document = try await coordinator.readDiscoverableSkillDocument(skill)

        XCTAssertEqual(document.skill.key, skill.key)
        XCTAssertEqual(document.sourcePath, "demo/skill-repo @ main / examples/helper/SKILL.md")
        XCTAssertTrue(document.content.contains("# Remote Skill"))
        XCTAssertTrue(document.content.contains("Remote description."))
    }

    func testSetSkillRepoEnabledUpdatesStoredRepoState() async throws {
        let tempHome = try makeTemporaryHome()
        defer { try? FileManager.default.removeItem(at: tempHome) }

        let service = ProviderConfigService(homeDirectory: tempHome)
        let coordinator = SkillCoordinator(configService: service)

        try await coordinator.saveSkillStore(
            SkillStore(
                repos: [
                    SkillRepo(
                        owner: "demo",
                        name: "skills",
                        branch: "main",
                        isEnabled: true,
                        isDefault: false
                    )
                ],
                installedSkills: []
            )
        )

        try await coordinator.setSkillRepoEnabled(owner: "demo", name: "skills", enabled: false)

        let store = try await coordinator.loadSkillStore()
        XCTAssertEqual(store.repos.count, 1)
        XCTAssertEqual(store.repos[0].owner, "demo")
        XCTAssertEqual(store.repos[0].name, "skills")
        XCTAssertFalse(store.repos[0].isEnabled)
    }

    func testUpdateInstalledSkillContentRewritesSkillMarkdownAndRefreshesMetadata() async throws {
        let tempHome = try makeTemporaryHome()
        defer { try? FileManager.default.removeItem(at: tempHome) }

        let service = ProviderConfigService(homeDirectory: tempHome)
        let coordinator = SkillCoordinator(configService: service)
        let skillDir = tempHome.appendingPathComponent(".claude/skills/demo-skill", isDirectory: true)
        let skillPath = skillDir.appendingPathComponent("SKILL.md", isDirectory: false)

        try FileManager.default.createDirectory(at: skillDir, withIntermediateDirectories: true)
        try """
        # Old Skill

        Old description.
        """.write(to: skillPath, atomically: true, encoding: .utf8)

        _ = try await coordinator.syncInstalledSkillsFromDisk()

        let updated = try await coordinator.updateInstalledSkillContent(
            directory: "demo-skill",
            content: """
            # New Skill

            Better description.
            """
        )

        let fileContent = try String(contentsOf: skillPath, encoding: .utf8)

        XCTAssertEqual(updated.skill.name, "New Skill")
        XCTAssertEqual(updated.skill.description, "Better description.")
        XCTAssertTrue(fileContent.contains("# New Skill"))
        XCTAssertTrue(fileContent.contains("Better description."))
    }

    func testDiscoverAvailableSkillsDoesNotImportMountedSkillsOnRead() async throws {
        let tempHome = try makeTemporaryHome()
        defer { try? FileManager.default.removeItem(at: tempHome) }

        let service = ProviderConfigService(homeDirectory: tempHome)
        let coordinator = SkillCoordinator(configService: service)
        let mountedSkillDir = tempHome.appendingPathComponent(".claude/skills/demo-skill", isDirectory: true)
        let mountedSkillPath = mountedSkillDir.appendingPathComponent("SKILL.md", isDirectory: false)
        let managedSkillPath = tempHome
            .appendingPathComponent("Library/Application Support/AIMenu/skills/demo-skill", isDirectory: true)
            .appendingPathComponent("SKILL.md", isDirectory: false)

        try await coordinator.saveSkillStore(
            SkillStore(
                repos: SkillStore.defaultRepos.map {
                    SkillRepo(
                        owner: $0.owner,
                        name: $0.name,
                        branch: $0.branch,
                        isEnabled: false,
                        isDefault: $0.isDefault
                    )
                },
                installedSkills: []
            )
        )
        try FileManager.default.createDirectory(at: mountedSkillDir, withIntermediateDirectories: true)
        try """
        # Demo Skill

        Mounted only.
        """.write(to: mountedSkillPath, atomically: true, encoding: .utf8)

        let discovered = try await coordinator.discoverAvailableSkills()
        let store = try await coordinator.loadSkillStore()

        XCTAssertTrue(discovered.isEmpty)
        XCTAssertTrue(store.installedSkills.isEmpty)
        XCTAssertFalse(FileManager.default.fileExists(atPath: managedSkillPath.path))
    }

    // MARK: - Helpers

    private func makeTemporaryHome() throws -> URL {
        let directory = FileManager.default.temporaryDirectory
            .appendingPathComponent(UUID().uuidString, isDirectory: true)
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        return directory
    }
}
