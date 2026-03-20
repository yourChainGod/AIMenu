import XCTest
@testable import AIMenu

final class ProviderIntegrationTests: XCTestCase {
    func testProviderDraftCarriesCustomFieldsIntoProvider() {
        let draft = ProviderDraft(
            preset: ProviderPresets.codexPresets[0],
            customName: "  Team OpenAI  ",
            websiteUrl: "https://example.com/dashboard",
            apiKey: "sk-test",
            baseUrl: "https://api.example.com/v1",
            model: "gpt-5-codex",
            notes: "  primary workspace  ",
            proxyConfig: ProviderProxyConfig(
                enabled: true,
                host: "127.0.0.1",
                port: "7890",
                username: "user",
                password: "pass"
            ),
            billingConfig: ProviderBillingConfig(
                inputPricePerMillion: "3.00",
                outputPricePerMillion: "12.00",
                currency: "USD",
                notes: "cached route"
            ),
            extraConfig: [
                "wireApi": "responses",
                "reasoningEffort": "high"
            ]
        )

        let provider = draft.makeProvider()

        XCTAssertEqual(provider.name, "Team OpenAI")
        XCTAssertEqual(provider.websiteUrl, "https://example.com/dashboard")
        XCTAssertEqual(provider.notes, "primary workspace")
        XCTAssertEqual(provider.codexConfig?.baseUrl, "https://api.example.com/v1")
        XCTAssertEqual(provider.codexConfig?.model, "gpt-5-codex")
        XCTAssertEqual(provider.codexConfig?.wireApi, "responses")
        XCTAssertEqual(provider.codexConfig?.reasoningEffort, "high")
        XCTAssertEqual(provider.proxyConfig?.host, "127.0.0.1")
        XCTAssertEqual(provider.billingConfig?.inputPricePerMillion, "3.00")
    }

    func testWriteCodexConfigPreservesExistingSectionsAndSettings() async throws {
        let tempHome = try makeTemporaryHome()
        defer { try? FileManager.default.removeItem(at: tempHome) }

        let service = ProviderConfigService(homeDirectory: tempHome)
        let codexDirectory = tempHome.appendingPathComponent(".codex", isDirectory: true)
        try FileManager.default.createDirectory(at: codexDirectory, withIntermediateDirectories: true)

        let existingConfig = """
        approval_policy = "never"

        [mcp_servers.fetch]
        command = "uvx"
        args = ["mcp-server-fetch"]

        [profiles.default]
        sandbox_mode = "danger-full-access"
        """
        try existingConfig.write(
            to: codexDirectory.appendingPathComponent("config.toml"),
            atomically: true,
            encoding: .utf8
        )

        let authJSON = """
        {
          "tokens": {
            "access_token": "chatgpt-access"
          }
        }
        """
        try authJSON.write(
            to: codexDirectory.appendingPathComponent("auth.json"),
            atomically: true,
            encoding: .utf8
        )

        try await service.writeCodexConfig(
            CodexSettingsConfig(
                apiKey: "sk-live",
                baseUrl: "https://api.example.com/v1",
                model: "gpt-5-codex",
                wireApi: "responses",
                reasoningEffort: "high"
            )
        )

        let updatedConfig = try String(contentsOf: codexDirectory.appendingPathComponent("config.toml"))
        XCTAssertTrue(updatedConfig.contains("approval_policy = \"never\""))
        XCTAssertTrue(updatedConfig.contains("model = \"gpt-5-codex\""))
        XCTAssertTrue(updatedConfig.contains("wire_api = \"responses\""))
        XCTAssertTrue(updatedConfig.contains("base_url = \"https://api.example.com/v1\""))
        XCTAssertTrue(updatedConfig.contains("[mcp_servers.fetch]"))
        XCTAssertTrue(updatedConfig.contains("[profiles.default]"))

        let authData = try Data(contentsOf: codexDirectory.appendingPathComponent("auth.json"))
        let authObject = try XCTUnwrap(try JSONSerialization.jsonObject(with: authData) as? [String: Any])
        XCTAssertEqual(authObject["OPENAI_API_KEY"] as? String, "sk-live")
        XCTAssertEqual(authObject["OPENAI_BASE_URL"] as? String, "https://api.example.com/v1")
        XCTAssertNotNil(authObject["tokens"])
    }

    func testWriteClaudeConfigPersistsPreviewToggles() async throws {
        let tempHome = try makeTemporaryHome()
        defer { try? FileManager.default.removeItem(at: tempHome) }

        let service = ProviderConfigService(homeDirectory: tempHome)
        let coordinator = ProviderCoordinator(configService: service)

        var provider = ProviderPresets.claudePresets[0].makeProvider(apiKey: "sk-claude")
        provider.id = "claude-preview"
        provider.name = "Claude Preview"
        provider.claudeConfig?.baseUrl = "https://api.example.com"
        provider.claudeConfig?.model = "claude-sonnet-4-20250514"
        provider.claudeConfig?.hideAttribution = true
        provider.claudeConfig?.alwaysThinkingEnabled = true
        provider.claudeConfig?.enableTeammates = true

        let outcome = try await coordinator.addProvider(provider)
        XCTAssertTrue(outcome.didApplyToLiveConfig)

        let settingsPath = tempHome.appendingPathComponent(".claude/settings.json")
        let data = try Data(contentsOf: settingsPath)
        let object = try XCTUnwrap(try JSONSerialization.jsonObject(with: data) as? [String: Any])
        let env = try XCTUnwrap(object["env"] as? [String: Any])
        let attribution = try XCTUnwrap(object["attribution"] as? [String: Any])

        XCTAssertEqual(env["ANTHROPIC_AUTH_TOKEN"] as? String, "sk-claude")
        XCTAssertEqual(env["ANTHROPIC_BASE_URL"] as? String, "https://api.example.com")
        XCTAssertEqual(env["ANTHROPIC_MODEL"] as? String, "claude-sonnet-4-20250514")
        XCTAssertEqual(env["CLAUDE_CODE_EXPERIMENTAL_AGENT_TEAMS"] as? String, "1")
        XCTAssertEqual(object["alwaysThinkingEnabled"] as? Bool, true)
        XCTAssertEqual(attribution["commit"] as? String, "")
        XCTAssertEqual(attribution["pr"] as? String, "")
    }

    func testDeleteCurrentProviderFallsBackAndRewritesLiveConfig() async throws {
        let tempHome = try makeTemporaryHome()
        defer { try? FileManager.default.removeItem(at: tempHome) }

        let service = ProviderConfigService(homeDirectory: tempHome)
        let coordinator = ProviderCoordinator(configService: service)

        let primary = makeCodexProvider(
            id: "primary",
            name: "Primary",
            apiKey: "sk-primary",
            baseUrl: "https://primary.example.com/v1",
            model: "gpt-5-primary"
        )
        let backup = makeCodexProvider(
            id: "backup",
            name: "Backup",
            apiKey: "sk-backup",
            baseUrl: "https://backup.example.com/v1",
            model: "gpt-5-backup"
        )

        let primaryOutcome = try await coordinator.addProvider(primary)
        XCTAssertTrue(primaryOutcome.didApplyToLiveConfig)
        _ = try await coordinator.addProvider(backup)

        let deleteOutcome = try await coordinator.deleteProvider(id: primary.id, appType: .codex)

        XCTAssertTrue(deleteOutcome.didDeleteCurrentProvider)
        XCTAssertEqual(deleteOutcome.fallbackProvider?.id, backup.id)

        let store = try await service.loadProviderStore()
        XCTAssertEqual(store.currentCodexProviderId, backup.id)

        let authPath = tempHome.appendingPathComponent(".codex/auth.json")
        let configPath = tempHome.appendingPathComponent(".codex/config.toml")
        let authData = try Data(contentsOf: authPath)
        let authObject = try XCTUnwrap(try JSONSerialization.jsonObject(with: authData) as? [String: Any])
        let configText = try String(contentsOf: configPath)

        XCTAssertEqual(authObject["OPENAI_API_KEY"] as? String, "sk-backup")
        XCTAssertEqual(authObject["OPENAI_BASE_URL"] as? String, "https://backup.example.com/v1")
        XCTAssertTrue(configText.contains("model = \"gpt-5-backup\""))
    }

    func testUpsertManagedCodexProxyProviderCreatesAndPinsProxyProvider() async throws {
        let tempHome = try makeTemporaryHome()
        defer { try? FileManager.default.removeItem(at: tempHome) }

        let service = ProviderConfigService(homeDirectory: tempHome)
        let coordinator = ProviderCoordinator(configService: service)

        let status = ApiProxyStatus(
            running: true,
            port: 8787,
            apiKey: "cp_test_proxy_key",
            baseURL: "http://127.0.0.1:8787/v1",
            availableAccounts: 3,
            activeAccountID: nil,
            activeAccountLabel: nil,
            lastError: nil
        )

        let provider = try await coordinator.upsertManagedCodexProxyProvider(from: status)
        let unwrappedProvider = try XCTUnwrap(provider)
        let store = try await service.loadProviderStore()
        let authData = try Data(contentsOf: tempHome.appendingPathComponent(".codex/auth.json"))
        let authObject = try XCTUnwrap(try JSONSerialization.jsonObject(with: authData) as? [String: Any])
        let configText = try String(contentsOf: tempHome.appendingPathComponent(".codex/config.toml"))

        XCTAssertEqual(unwrappedProvider.name, ProviderCoordinator.managedCodexProxyName)
        XCTAssertEqual(unwrappedProvider.presetId, ProviderCoordinator.managedCodexProxyPresetId)
        XCTAssertEqual(unwrappedProvider.codexConfig?.model, ProviderCoordinator.managedCodexProxyModel)
        XCTAssertEqual(store.currentCodexProviderId, unwrappedProvider.id)
        XCTAssertEqual(authObject["OPENAI_API_KEY"] as? String, "cp_test_proxy_key")
        XCTAssertEqual(authObject["OPENAI_BASE_URL"] as? String, "http://127.0.0.1:8787/v1")
        XCTAssertTrue(configText.contains("model = \"gpt-5-codex\""))
        XCTAssertTrue(configText.contains("wire_api = \"responses\""))
        XCTAssertTrue(configText.contains("reasoning_effort = \"medium\""))
    }

    func testListPromptsReflectsLivePromptFileContent() async throws {
        let tempHome = try makeTemporaryHome()
        defer { try? FileManager.default.removeItem(at: tempHome) }

        let service = ProviderConfigService(homeDirectory: tempHome)
        let coordinator = ProviderCoordinator(configService: service)

        let firstPrompt = Prompt(
            id: "prompt-1",
            name: "First",
            appType: .codex,
            content: "Use careful reasoning.",
            description: nil,
            isActive: false,
            createdAt: 1,
            updatedAt: 1
        )
        let secondPrompt = Prompt(
            id: "prompt-2",
            name: "Second",
            appType: .codex,
            content: "Prefer concise answers.",
            description: nil,
            isActive: true,
            createdAt: 2,
            updatedAt: 2
        )

        try await coordinator.addPrompt(firstPrompt)
        try await coordinator.addPrompt(secondPrompt)

        let livePath = PromptAppType.codex.filePath(in: tempHome)
        try FileManager.default.createDirectory(at: livePath.deletingLastPathComponent(), withIntermediateDirectories: true)
        try firstPrompt.content.write(to: livePath, atomically: true, encoding: .utf8)

        let prompts = try await coordinator.listPrompts(for: .codex)

        XCTAssertEqual(prompts.first(where: { $0.id == firstPrompt.id })?.isActive, true)
        XCTAssertEqual(prompts.first(where: { $0.id == secondPrompt.id })?.isActive, false)
    }

    func testListLocalConfigBundlesSummarizesLiveFiles() async throws {
        let tempHome = try makeTemporaryHome()
        defer { try? FileManager.default.removeItem(at: tempHome) }

        let service = ProviderConfigService(homeDirectory: tempHome)
        let coordinator = ProviderCoordinator(configService: service)

        let claudeSettings = tempHome.appendingPathComponent(".claude/settings.json")
        let codexConfig = tempHome.appendingPathComponent(".codex/config.toml")
        let geminiEnv = tempHome.appendingPathComponent(".gemini/.env")

        try FileManager.default.createDirectory(
            at: claudeSettings.deletingLastPathComponent(),
            withIntermediateDirectories: true
        )
        try FileManager.default.createDirectory(
            at: codexConfig.deletingLastPathComponent(),
            withIntermediateDirectories: true
        )
        try FileManager.default.createDirectory(
            at: geminiEnv.deletingLastPathComponent(),
            withIntermediateDirectories: true
        )

        try "{}".write(to: claudeSettings, atomically: true, encoding: .utf8)
        try "model = \"gpt-5-codex\"".write(to: codexConfig, atomically: true, encoding: .utf8)
        try "GEMINI_API_KEY=test".write(to: geminiEnv, atomically: true, encoding: .utf8)

        let bundles = try await coordinator.listLocalConfigBundles()

        XCTAssertEqual(bundles.map(\.app), [.claude, .codex, .gemini])

        let claudeBundle = try XCTUnwrap(bundles.first(where: { $0.app == .claude }))
        XCTAssertEqual(claudeBundle.existingFileCount, 1)
        XCTAssertEqual(claudeBundle.files.first(where: { $0.label == "settings.json" })?.exists, true)
        XCTAssertEqual(claudeBundle.files.first(where: { $0.label == "CLAUDE.md" })?.exists, false)

        let codexBundle = try XCTUnwrap(bundles.first(where: { $0.app == .codex }))
        XCTAssertEqual(codexBundle.existingFileCount, 1)
        XCTAssertEqual(codexBundle.files.first(where: { $0.label == "config.toml" })?.kind, .toml)
        XCTAssertEqual(codexBundle.files.first(where: { $0.label == "auth.json" })?.exists, false)

        let geminiBundle = try XCTUnwrap(bundles.first(where: { $0.app == .gemini }))
        XCTAssertEqual(geminiBundle.existingFileCount, 1)
        XCTAssertEqual(geminiBundle.files.first(where: { $0.label == ".env" })?.exists, true)
        XCTAssertEqual(geminiBundle.files.first(where: { $0.label == "settings.json" })?.exists, false)
    }

    func testToggleMCPAppRemovesLiveEntryFromUnmountedClient() async throws {
        let tempHome = try makeTemporaryHome()
        defer { try? FileManager.default.removeItem(at: tempHome) }

        let service = ProviderConfigService(homeDirectory: tempHome)
        let coordinator = ProviderCoordinator(configService: service)
        let server = MCPServer(
            id: "demo-fetch",
            name: "Demo Fetch",
            server: MCPServerSpec(
                type: .stdio,
                command: "uvx",
                args: ["mcp-server-fetch"],
                env: nil,
                cwd: nil,
                url: nil,
                headers: nil
            ),
            apps: MCPAppToggles(claude: true, codex: true, gemini: false),
            description: nil,
            tags: nil,
            homepage: nil,
            createdAt: 1,
            updatedAt: 1,
            isEnabled: true
        )

        try await coordinator.addMCPServer(server)

        let initialClaudeConfig = try XCTUnwrap(
            try JSONSerialization.jsonObject(
                with: Data(contentsOf: tempHome.appendingPathComponent(".claude.json"))
            ) as? [String: Any]
        )
        XCTAssertNotNil((initialClaudeConfig["mcpServers"] as? [String: Any])?["demo-fetch"])

        try await coordinator.toggleMCPApp(serverId: server.id, app: .claude, enabled: false)

        let updatedClaudeConfig = try XCTUnwrap(
            try JSONSerialization.jsonObject(
                with: Data(contentsOf: tempHome.appendingPathComponent(".claude.json"))
            ) as? [String: Any]
        )
        let claudeMCP = (updatedClaudeConfig["mcpServers"] as? [String: Any]) ?? [:]
        XCTAssertNil(claudeMCP["demo-fetch"])

        let codexConfig = try String(contentsOf: tempHome.appendingPathComponent(".codex/config.toml"))
        XCTAssertTrue(codexConfig.contains("[mcp_servers.demo-fetch]"))
        XCTAssertTrue(codexConfig.contains("command = \"uvx\""))
    }

    func testReadInstalledSkillDocumentLoadsSkillMarkdown() async throws {
        let tempHome = try makeTemporaryHome()
        defer { try? FileManager.default.removeItem(at: tempHome) }

        let service = ProviderConfigService(homeDirectory: tempHome)
        let coordinator = ProviderCoordinator(configService: service)
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
        let coordinator = ProviderCoordinator(
            configService: service,
            gitHubFileLoader: { owner, repo, branch, path in
                guard owner == "demo",
                      repo == "skill-repo",
                      branch == "main",
                      path == "examples/helper/SKILL.md" else {
                    throw NSError(domain: "ProviderIntegrationTests", code: 1)
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
        let coordinator = ProviderCoordinator(configService: service)

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
        let coordinator = ProviderCoordinator(configService: service)
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

    func testDiscoverAvailableSkillsDoesNotImportMountedSkillsOnRead() async throws {
        let tempHome = try makeTemporaryHome()
        defer { try? FileManager.default.removeItem(at: tempHome) }

        let service = ProviderConfigService(homeDirectory: tempHome)
        let coordinator = ProviderCoordinator(configService: service)
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

    private func makeTemporaryHome() throws -> URL {
        let directory = FileManager.default.temporaryDirectory
            .appendingPathComponent(UUID().uuidString, isDirectory: true)
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        return directory
    }

    private func makeCodexProvider(
        id: String,
        name: String,
        apiKey: String,
        baseUrl: String,
        model: String
    ) -> Provider {
        Provider(
            id: id,
            name: name,
            appType: .codex,
            category: .official,
            claudeConfig: nil,
            codexConfig: CodexSettingsConfig(
                apiKey: apiKey,
                baseUrl: baseUrl,
                model: model,
                wireApi: "responses",
                reasoningEffort: "medium"
            ),
            geminiConfig: nil,
            websiteUrl: nil,
            apiKeyUrl: nil,
            notes: nil,
            icon: nil,
            iconColor: nil,
            isPreset: false,
            presetId: nil,
            sortIndex: 0,
            createdAt: 1,
            updatedAt: 1,
            isCurrent: false,
            proxyConfig: nil,
            billingConfig: nil
        )
    }
}
