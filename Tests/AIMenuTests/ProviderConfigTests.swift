import XCTest
@testable import AIMenu

final class ProviderConfigTests: XCTestCase {
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
                ProviderConfigKey.wireApi.rawValue: "responses",
                ProviderConfigKey.reasoningEffort.rawValue: "high"
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

    func testWriteClaudeConfigMergesCommonJSONConfig() async throws {
        let tempHome = try makeTemporaryHome()
        defer { try? FileManager.default.removeItem(at: tempHome) }

        let service = ProviderConfigService(homeDirectory: tempHome)
        let coordinator = ProviderCoordinator(configService: service)

        var provider = ProviderPresets.claudePresets[0].makeProvider(apiKey: "sk-claude")
        provider.id = "claude-common"
        provider.name = "Claude Common"
        provider.claudeConfig?.baseUrl = "https://api.example.com"
        provider.claudeConfig?.model = "claude-sonnet-4-20250514"
        provider.claudeConfig?.applyCommonConfig = true
        provider.claudeConfig?.commonConfigJSON = """
        {
          "hooks": {
            "PreToolUse": [
              {
                "hooks": [
                  {
                    "command": "echo ok",
                    "type": "command"
                  }
                ],
                "matcher": "Bash"
              }
            ]
          },
          "includeCoAuthoredBy": false,
          "outputStyle": "abyss-cultivator",
          "skipDangerousModePermissionPrompt": true,
          "statusLine": {
            "command": "~/.claude/ccline/ccline",
            "padding": 0,
            "type": "command"
          }
        }
        """

        _ = try await coordinator.addProvider(provider)

        let settingsPath = tempHome.appendingPathComponent(".claude/settings.json")
        let data = try Data(contentsOf: settingsPath)
        let object = try XCTUnwrap(try JSONSerialization.jsonObject(with: data) as? [String: Any])
        let env = try XCTUnwrap(object["env"] as? [String: Any])
        let hooks = try XCTUnwrap(object["hooks"] as? [String: Any])
        let statusLine = try XCTUnwrap(object["statusLine"] as? [String: Any])

        XCTAssertEqual(env["ANTHROPIC_AUTH_TOKEN"] as? String, "sk-claude")
        XCTAssertEqual(object["includeCoAuthoredBy"] as? Bool, false)
        XCTAssertEqual(object["outputStyle"] as? String, "abyss-cultivator")
        XCTAssertEqual(object["skipDangerousModePermissionPrompt"] as? Bool, true)
        XCTAssertNotNil(hooks["PreToolUse"])
        XCTAssertEqual(statusLine["command"] as? String, "~/.claude/ccline/ccline")
        XCTAssertEqual(statusLine["padding"] as? Int, 0)
    }

    func testListProvidersSyncsOnlyClaudeLiveCommonConfigForCurrentProvider() async throws {
        let tempHome = try makeTemporaryHome()
        defer { try? FileManager.default.removeItem(at: tempHome) }

        let service = ProviderConfigService(homeDirectory: tempHome)
        let coordinator = ProviderCoordinator(configService: service)

        var provider = ProviderPresets.claudePresets[0].makeProvider(apiKey: "sk-store")
        provider.id = "claude-live-sync"
        provider.name = "Claude Live Sync"
        provider.claudeConfig?.baseUrl = "https://store.example.com"
        provider.claudeConfig?.model = "claude-store-model"
        provider.claudeConfig?.maxOutputTokens = 2048
        provider.claudeConfig?.apiTimeoutMs = 30_000
        provider.claudeConfig?.disableNonessentialTraffic = false
        provider.claudeConfig?.hideAttribution = false
        provider.claudeConfig?.alwaysThinkingEnabled = false
        provider.claudeConfig?.enableTeammates = false
        provider.claudeConfig?.applyCommonConfig = false
        provider.claudeConfig?.commonConfigJSON = nil

        _ = try await coordinator.addProvider(provider)

        let settingsPath = tempHome.appendingPathComponent(".claude/settings.json")
        try """
        {
          "alwaysThinkingEnabled": true,
          "attribution": {
            "commit": "",
            "pr": ""
          },
          "env": {
            "ANTHROPIC_AUTH_TOKEN": "sk-live",
            "ANTHROPIC_BASE_URL": "https://live.example.com",
            "ANTHROPIC_MODEL": "claude-live-model",
            "API_TIMEOUT_MS": "45000",
            "CLAUDE_CODE_DISABLE_NONESSENTIAL_TRAFFIC": "1",
            "CLAUDE_CODE_EXPERIMENTAL_AGENT_TEAMS": "1",
            "CLAUDE_CODE_MAX_OUTPUT_TOKENS": "4096"
          },
          "hooks": {
            "Stop": [
              {
                "hooks": [
                  {
                    "command": "echo done",
                    "type": "command"
                  }
                ]
              }
            ]
          },
          "outputStyle": "abyss-cultivator"
        }
        """.write(to: settingsPath, atomically: true, encoding: .utf8)

        let providers = try await coordinator.listProviders(for: .claude)
        let synced = try XCTUnwrap(providers.first(where: { $0.id == provider.id }))
        let config = try XCTUnwrap(synced.claudeConfig)

        XCTAssertEqual(config.apiKey, "sk-store")
        XCTAssertEqual(config.baseUrl, "https://store.example.com")
        XCTAssertEqual(config.model, "claude-store-model")
        XCTAssertEqual(config.maxOutputTokens, 4096)
        XCTAssertEqual(config.apiTimeoutMs, 45_000)
        XCTAssertEqual(config.disableNonessentialTraffic, true)
        XCTAssertEqual(config.hideAttribution, true)
        XCTAssertEqual(config.alwaysThinkingEnabled, true)
        XCTAssertEqual(config.enableTeammates, true)
        XCTAssertEqual(config.applyCommonConfig, true)

        let commonData = try XCTUnwrap(config.commonConfigJSON?.data(using: .utf8))
        let commonObject = try XCTUnwrap(try JSONSerialization.jsonObject(with: commonData) as? [String: Any])
        XCTAssertEqual(commonObject["outputStyle"] as? String, "abyss-cultivator")
        XCTAssertNotNil(commonObject["hooks"])

        let store = try await service.loadProviderStore()
        let stored = try XCTUnwrap(store.providers.first(where: { $0.id == provider.id }))
        XCTAssertEqual(stored.claudeConfig?.apiKey, "sk-store")
        XCTAssertEqual(stored.claudeConfig?.baseUrl, "https://store.example.com")
        XCTAssertEqual(stored.claudeConfig?.model, "claude-store-model")
        XCTAssertEqual(stored.claudeConfig?.maxOutputTokens, 2048)
    }

    func testListProvidersSyncsOnlyCodexLiveRuntimeFlagsForCurrentProvider() async throws {
        let tempHome = try makeTemporaryHome()
        defer { try? FileManager.default.removeItem(at: tempHome) }

        let service = ProviderConfigService(homeDirectory: tempHome)
        let coordinator = ProviderCoordinator(configService: service)

        let provider = makeCodexProvider(
            id: "codex-live-sync",
            name: "Codex Live Sync",
            apiKey: "sk-store",
            baseUrl: "https://store.example.com/v1",
            model: "gpt-store"
        )

        _ = try await coordinator.addProvider(provider)

        let codexDirectory = tempHome.appendingPathComponent(".codex", isDirectory: true)
        try FileManager.default.createDirectory(at: codexDirectory, withIntermediateDirectories: true)
        try """
        {
          "OPENAI_API_KEY": "sk-live",
          "OPENAI_BASE_URL": "https://live.example.com/v1"
        }
        """.write(
            to: codexDirectory.appendingPathComponent("auth.json"),
            atomically: true,
            encoding: .utf8
        )
        try """
        model = "gpt-live"
        wire_api = "chat"
        base_url = "https://live.example.com/v1"
        reasoning_effort = "high"

        [profiles.default]
        model = "ignored"
        """.write(
            to: codexDirectory.appendingPathComponent("config.toml"),
            atomically: true,
            encoding: .utf8
        )

        let providers = try await coordinator.listProviders(for: .codex)
        let synced = try XCTUnwrap(providers.first(where: { $0.id == provider.id }))
        let config = try XCTUnwrap(synced.codexConfig)

        XCTAssertEqual(config.apiKey, "sk-store")
        XCTAssertEqual(config.baseUrl, "https://store.example.com/v1")
        XCTAssertEqual(config.model, "gpt-store")
        XCTAssertEqual(config.wireApi, "chat")
        XCTAssertEqual(config.reasoningEffort, "high")

        let store = try await service.loadProviderStore()
        let stored = try XCTUnwrap(store.providers.first(where: { $0.id == provider.id }))
        XCTAssertEqual(stored.codexConfig?.apiKey, "sk-store")
        XCTAssertEqual(stored.codexConfig?.baseUrl, "https://store.example.com/v1")
        XCTAssertEqual(stored.codexConfig?.model, "gpt-store")
        XCTAssertEqual(stored.codexConfig?.wireApi, "responses")
        XCTAssertEqual(stored.codexConfig?.reasoningEffort, "medium")
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

    func testImportProvidersDeduplicatesPayloadAndMapsCurrentSelectionToNewIDs() async throws {
        let tempHome = try makeTemporaryHome()
        defer { try? FileManager.default.removeItem(at: tempHome) }

        let service = ProviderConfigService(homeDirectory: tempHome)
        let coordinator = ProviderCoordinator(configService: service)

        let first = makeCodexProvider(
            id: "imported-primary",
            name: "Imported",
            apiKey: "sk-1",
            baseUrl: "https://imported.example.com/v1",
            model: "gpt-5-imported"
        )
        let duplicate = makeCodexProvider(
            id: "imported-duplicate",
            name: "Imported",
            apiKey: "sk-2",
            baseUrl: "https://imported.example.com/v1",
            model: "gpt-5-duplicate"
        )

        let importedStore = ProviderStore(
            version: 1,
            providers: [first, duplicate],
            currentClaudeProviderId: nil,
            currentCodexProviderId: first.id,
            currentGeminiProviderId: nil
        )
        let data = try JSONEncoder().encode(importedStore)

        let addedCount = try await coordinator.importProviders(from: data)
        XCTAssertEqual(addedCount, 1)

        let savedStore = try await service.loadProviderStore()
        XCTAssertEqual(savedStore.providers.count, 1)

        let selectedID = try XCTUnwrap(savedStore.currentCodexProviderId)
        XCTAssertNotEqual(selectedID, first.id)
        XCTAssertEqual(savedStore.providers.first?.id, selectedID)
        XCTAssertEqual(savedStore.providers.first?.name, "Imported")
    }

    func testListPromptsReflectsLivePromptFileContent() async throws {
        let tempHome = try makeTemporaryHome()
        defer { try? FileManager.default.removeItem(at: tempHome) }

        let service = ProviderConfigService(homeDirectory: tempHome)
        let coordinator = PromptCoordinator(configService: service)

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
        let coordinator = MCPCoordinator(configService: service)

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

    // MARK: - Helpers

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
