import SwiftUI

// MARK: - AddProviderSheet + Preview Builders & Apply Functions

extension AddProviderSheet {

    var previewSubtitle: String {
        switch appType {
        case .claude:
            return L10n.tr("providers.preview.subtitle.claude")
        case .codex:
            return L10n.tr("providers.preview.subtitle.codex")
        case .gemini:
            return L10n.tr("providers.preview.subtitle.gemini")
        }
    }

    var previewBlocks: [ProviderPreviewBlockData] {
        switch appType {
        case .claude:
            return [
                ProviderPreviewBlockData(
                    title: "settings.json (JSON)",
                    subtitle: L10n.tr("providers.preview.target.claude"),
                    content: buildClaudePreview(),
                    onApply: applyClaudePreview
                )
            ]
        case .codex:
            return [
                ProviderPreviewBlockData(
                    title: "auth.json (JSON)",
                    subtitle: L10n.tr("providers.preview.target.codex_auth"),
                    content: buildCodexAuthPreview(),
                    onApply: applyCodexAuthPreview
                ),
                ProviderPreviewBlockData(
                    title: "config.toml (TOML)",
                    subtitle: L10n.tr("providers.preview.target.codex_toml"),
                    content: buildCodexTomlPreview(),
                    onApply: applyCodexTomlPreview
                )
            ]
        case .gemini:
            return [
                ProviderPreviewBlockData(
                    title: ".env",
                    subtitle: L10n.tr("providers.preview.target.gemini"),
                    content: buildGeminiPreview(),
                    onApply: applyGeminiPreview
                )
            ]
        }
    }

    var normalizedClaudeCommonConfigJSON: String {
        normalizedJSONObjectString(claude.commonConfigJSON) ?? "{}"
    }

    // MARK: - Apply Functions

    func applyClaudePreview(_ text: String) throws {
        let payload = try parsePreviewJSONObject(text)
        let env = payload["env"] as? [String: Any] ?? [:]

        if let token = previewString(env["ANTHROPIC_AUTH_TOKEN"]) {
            claude.apiKeyField = .authToken
            apiKey = token
        } else if let key = previewString(env["ANTHROPIC_API_KEY"]) {
            claude.apiKeyField = .apiKey
            apiKey = key
        }

        if let value = previewString(env["ANTHROPIC_BASE_URL"]) { baseUrl = value }
        if let value = previewString(env["ANTHROPIC_MODEL"]) { model = value }
        claude.haikuModel = previewString(env["ANTHROPIC_DEFAULT_HAIKU_MODEL"]) ?? ""
        claude.sonnetModel = previewString(env["ANTHROPIC_DEFAULT_SONNET_MODEL"]) ?? ""
        claude.opusModel = previewString(env["ANTHROPIC_DEFAULT_OPUS_MODEL"]) ?? ""
        claude.maxOutputTokens = previewString(env["CLAUDE_CODE_MAX_OUTPUT_TOKENS"]) ?? ""
        claude.apiTimeoutMs = previewString(env["API_TIMEOUT_MS"]) ?? ""
        claude.disableNonessential = previewBool(env["CLAUDE_CODE_DISABLE_NONESSENTIAL_TRAFFIC"])
        claude.enableTeammates = previewBool(env["CLAUDE_CODE_EXPERIMENTAL_AGENT_TEAMS"])
        claude.hideAttribution = payload["attribution"] != nil
        claude.alwaysThinking = previewBool(payload["alwaysThinkingEnabled"])
        let commonConfig = extractClaudeCommonConfig(from: payload)
        claude.applyCommonConfig = !commonConfig.isEmpty
        claude.commonConfigJSON = commonConfig.isEmpty ? "" : prettyJSONString(commonConfig)
    }

    func applyClaudeCommonConfigPreview(_ text: String) throws {
        let payload = try parsePreviewJSONObject(text)
        claude.applyCommonConfig = !payload.isEmpty
        claude.commonConfigJSON = payload.isEmpty ? "" : prettyJSONString(payload)
    }

    func applyCodexAuthPreview(_ text: String) throws {
        let payload = try parsePreviewJSONObject(text)
        if let value = previewString(payload["OPENAI_API_KEY"]) { apiKey = value }
        if let value = previewString(payload["OPENAI_BASE_URL"]) { baseUrl = value }
    }

    func applyCodexTomlPreview(_ text: String) throws {
        let payload = try parsePreviewTOML(text)
        if let value = payload["model"] { model = value }
        if let value = payload["wire_api"] { codex.wireApi = value }
        if let value = payload["base_url"] { baseUrl = value }
        if let value = payload["reasoning_effort"] { codex.reasoningEffort = value }
    }

    func applyGeminiPreview(_ text: String) throws {
        let payload = try parsePreviewDotEnv(text)
        if let value = payload["GEMINI_API_KEY"] { apiKey = value }
        if let value = payload["GOOGLE_GEMINI_BASE_URL"] { baseUrl = value }
        if let value = payload["GEMINI_MODEL"] { model = value }
    }

    // MARK: - Build Functions

    func buildClaudePreview() -> String {
        var settings = claude.applyCommonConfig ? (parsedJSONObjectString(claude.commonConfigJSON) ?? [:]) : [:]
        var env: [String: Any] = [
            claude.apiKeyField.rawValue: apiKey.trimmedNonEmpty ?? "<API_KEY>"
        ]
        env["ANTHROPIC_BASE_URL"] = resolvedBaseURL
        if let model = model.trimmedNonEmpty {
            env["ANTHROPIC_MODEL"] = model
        }
        if let model = claude.haikuModel.trimmedNonEmpty {
            env["ANTHROPIC_DEFAULT_HAIKU_MODEL"] = model
        }
        if let model = claude.sonnetModel.trimmedNonEmpty {
            env["ANTHROPIC_DEFAULT_SONNET_MODEL"] = model
        }
        if let model = claude.opusModel.trimmedNonEmpty {
            env["ANTHROPIC_DEFAULT_OPUS_MODEL"] = model
        }
        if let tokens = claude.maxOutputTokens.trimmedNonEmpty {
            env["CLAUDE_CODE_MAX_OUTPUT_TOKENS"] = tokens
        }
        if let timeout = claude.apiTimeoutMs.trimmedNonEmpty {
            env["API_TIMEOUT_MS"] = timeout
        }
        if claude.disableNonessential {
            env["CLAUDE_CODE_DISABLE_NONESSENTIAL_TRAFFIC"] = "1"
        }
        if claude.enableTeammates {
            env["CLAUDE_CODE_EXPERIMENTAL_AGENT_TEAMS"] = "1"
        }

        settings["env"] = env
        if claude.hideAttribution {
            settings["attribution"] = ["commit": "", "pr": ""]
        } else {
            settings.removeValue(forKey: "attribution")
        }
        if claude.alwaysThinking {
            settings["alwaysThinkingEnabled"] = true
        } else {
            settings.removeValue(forKey: "alwaysThinkingEnabled")
        }
        return prettyJSONString(settings)
    }

    func buildClaudeCommonConfigPreview() -> String {
        normalizedClaudeCommonConfigJSON
    }

    func buildCodexAuthPreview() -> String {
        var auth: [String: Any] = ["OPENAI_API_KEY": apiKey.trimmedNonEmpty ?? "<API_KEY>"]
        auth["OPENAI_BASE_URL"] = resolvedBaseURL
        return prettyJSONString(auth)
    }

    func buildCodexTomlPreview() -> String {
        var lines: [String] = []
        if let model = model.trimmedNonEmpty {
            lines.append("model = \(tomlQuoted(model))")
        }
        lines.append("wire_api = \(tomlQuoted(codex.wireApi))")
        lines.append("base_url = \(tomlQuoted(resolvedBaseURL))")
        lines.append("reasoning_effort = \(tomlQuoted(codex.reasoningEffort))")
        lines.append("")
        lines.append(L10n.tr("providers.toml.comment_preserved_sections"))
        return lines.joined(separator: "\n")
    }

    func buildGeminiPreview() -> String {
        [
            "GEMINI_API_KEY=\(dotenvEscaped(apiKey.trimmedNonEmpty ?? "<API_KEY>"))",
            "GOOGLE_GEMINI_BASE_URL=\(dotenvEscaped(resolvedBaseURL))",
            "GEMINI_MODEL=\(dotenvEscaped(model.trimmedNonEmpty ?? (selectedPreset?.defaultModel ?? "gemini-2.5-pro")))"
        ].joined(separator: "\n")
    }

    // MARK: - Preset Application

    func applyPreset(_ preset: ProviderPreset) {
        selectedPreset = preset
        providerName = preset.name
        websiteUrl = preset.websiteUrl ?? ""
        providerNotes = ""
        baseUrl = preset.baseUrl ?? ""
        model = preset.defaultModel ?? ""
        apiKey = ""
        proxyEnabled = false
        proxyHost = ""
        proxyPort = ""
        proxyUsername = ""
        proxyPassword = ""
        billing = BillingFormState()
        claude = ClaudeFormState(
            apiFormat: preset.apiFormat ?? .anthropic,
            apiKeyField: preset.apiKeyField ?? .authToken
        )
        codex = CodexFormState(
            wireApi: preset.wireApi ?? "responses"
        )
        fetchedModels = []
        modelFetchState = .idle
    }

    // MARK: - Model Fetching

    func fetchModels() {
        let base = resolvedBaseURL
        let key = apiKey.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !key.isEmpty else { return }

        modelFetchState = .fetching

        Task {
            do {
                let models = try await ProviderModelCatalogService.fetch(
                    appType: appType,
                    baseUrl: base,
                    apiKey: key,
                    claudeApiFormat: appType == .claude ? claude.apiFormat : nil
                )
                await MainActor.run {
                    fetchedModels = models
                    modelFetchState = models.isEmpty
                        ? .success(L10n.tr("providers.models.empty_success"))
                        : .success(L10n.tr("providers.models.fetched_count_format", String(models.count)))
                }
            } catch {
                await MainActor.run {
                    fetchedModels = []
                    modelFetchState = .failure(error.localizedDescription)
                }
            }
        }
    }
}
