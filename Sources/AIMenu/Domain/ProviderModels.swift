import Foundation

// MARK: - Provider App Types

enum ProviderAppType: String, Codable, CaseIterable, Identifiable {
    case claude
    case codex
    case gemini

    var id: String { rawValue }

    var displayName: String {
        switch self {
        case .claude: return "Claude Code"
        case .codex: return "Codex"
        case .gemini: return "Gemini"
        }
    }

    var iconName: String {
        switch self {
        case .claude: return "c.circle.fill"
        case .codex: return "chevron.left.forwardslash.chevron.right"
        case .gemini: return "diamond.fill"
        }
    }
}

// MARK: - Provider Category

enum ProviderCategory: String, Codable, CaseIterable {
    case official
    case cnOfficial = "cn_official"
    case cloudProvider = "cloud_provider"
    case aggregator
    case thirdParty = "third_party"
    case custom

    var displayName: String {
        switch self {
        case .official: return "官方"
        case .cnOfficial: return "国内官方"
        case .cloudProvider: return "云服务"
        case .aggregator: return "聚合"
        case .thirdParty: return "第三方"
        case .custom: return "自定义"
        }
    }
}

// MARK: - Claude API Format

enum ClaudeApiFormat: String, Codable {
    case anthropic
    case openaiChat = "openai_chat"
    case openaiResponses = "openai_responses"
}

enum ClaudeApiKeyField: String, Codable {
    case authToken = "ANTHROPIC_AUTH_TOKEN"
    case apiKey = "ANTHROPIC_API_KEY"
}

// MARK: - Provider Settings Config (per app type)

struct ClaudeSettingsConfig: Codable, Equatable {
    var apiKey: String
    var baseUrl: String?
    var model: String?
    var haikuModel: String?
    var sonnetModel: String?
    var opusModel: String?
    var maxOutputTokens: Int?
    var apiTimeoutMs: Int?
    var disableNonessentialTraffic: Bool?
    var hideAttribution: Bool?
    var alwaysThinkingEnabled: Bool?
    var enableTeammates: Bool?
    var apiFormat: ClaudeApiFormat?
    var apiKeyField: ClaudeApiKeyField?
    // AWS Bedrock fields
    var awsRegion: String?
    var awsAccessKeyId: String?
    var awsSecretAccessKey: String?

    static let empty = ClaudeSettingsConfig(apiKey: "")
}

struct CodexSettingsConfig: Codable, Equatable {
    var apiKey: String
    var baseUrl: String?
    var model: String?
    var wireApi: String? // "responses" or "chat"
    var reasoningEffort: String? // "low", "medium", "high"

    static let empty = CodexSettingsConfig(apiKey: "")
}

struct GeminiSettingsConfig: Codable, Equatable {
    var apiKey: String
    var baseUrl: String?
    var model: String?

    static let empty = GeminiSettingsConfig(apiKey: "")
}

// MARK: - Provider

struct Provider: Codable, Equatable, Identifiable {
    var id: String
    var name: String
    var appType: ProviderAppType
    var category: ProviderCategory
    var claudeConfig: ClaudeSettingsConfig?
    var codexConfig: CodexSettingsConfig?
    var geminiConfig: GeminiSettingsConfig?
    var websiteUrl: String?
    var apiKeyUrl: String?
    var notes: String?
    var icon: String?
    var iconColor: String?
    var isPreset: Bool
    var presetId: String?
    var sortIndex: Int
    var createdAt: Int64
    var updatedAt: Int64
    var isCurrent: Bool
    var proxyConfig: ProviderProxyConfig?
    var billingConfig: ProviderBillingConfig?

    var displayIcon: String {
        icon ?? appType.iconName
    }

    var settingsDescription: String {
        switch appType {
        case .claude:
            let base = claudeConfig?.baseUrl ?? "api.anthropic.com"
            let model = claudeConfig?.model ?? "default"
            return "\(base) · \(model)"
        case .codex:
            let base = codexConfig?.baseUrl ?? "api.openai.com"
            let model = codexConfig?.model ?? "default"
            return "\(base) · \(model)"
        case .gemini:
            let base = geminiConfig?.baseUrl ?? "generativelanguage.googleapis.com"
            let model = geminiConfig?.model ?? "default"
            return "\(base) · \(model)"
        }
    }
}

struct ProviderDraft {
    var preset: ProviderPreset
    var customName: String
    var websiteUrl: String
    var apiKey: String
    var baseUrl: String
    var model: String
    var notes: String
    var proxyConfig: ProviderProxyConfig?
    var billingConfig: ProviderBillingConfig?
    var extraConfig: [String: String]

    func makeProvider() -> Provider {
        var provider = preset.makeProvider(apiKey: apiKey.trimmingCharacters(in: .whitespacesAndNewlines))

        let trimmedName = customName.trimmingCharacters(in: .whitespacesAndNewlines)
        if !trimmedName.isEmpty {
            provider.name = trimmedName
        }

        let trimmedWebsite = websiteUrl.trimmingCharacters(in: .whitespacesAndNewlines)
        provider.websiteUrl = trimmedWebsite.isEmpty ? provider.websiteUrl : trimmedWebsite

        let trimmedNotes = notes.trimmingCharacters(in: .whitespacesAndNewlines)
        provider.notes = trimmedNotes.isEmpty ? nil : trimmedNotes

        let trimmedBaseUrl = baseUrl.trimmingCharacters(in: .whitespacesAndNewlines)
        let trimmedModel = model.trimmingCharacters(in: .whitespacesAndNewlines)

        switch provider.appType {
        case .claude:
            if provider.claudeConfig != nil {
                provider.claudeConfig?.baseUrl = trimmedBaseUrl.isEmpty ? nil : trimmedBaseUrl
                provider.claudeConfig?.model = trimmedModel.isEmpty ? nil : trimmedModel
                if let value = extraConfig["claudeApiFormat"], let format = ClaudeApiFormat(rawValue: value) {
                    provider.claudeConfig?.apiFormat = format
                }
                if let value = extraConfig["claudeApiKeyField"], let field = ClaudeApiKeyField(rawValue: value) {
                    provider.claudeConfig?.apiKeyField = field
                }
                if let value = extraConfig["claudeHaikuModel"]?.trimmedNonEmpty {
                    provider.claudeConfig?.haikuModel = value
                }
                if let value = extraConfig["claudeSonnetModel"]?.trimmedNonEmpty {
                    provider.claudeConfig?.sonnetModel = value
                }
                if let value = extraConfig["claudeOpusModel"]?.trimmedNonEmpty {
                    provider.claudeConfig?.opusModel = value
                }
                if let value = extraConfig["claudeMaxOutputTokens"], let intValue = Int(value) {
                    provider.claudeConfig?.maxOutputTokens = intValue
                }
                if let value = extraConfig["claudeApiTimeoutMs"], let intValue = Int(value) {
                    provider.claudeConfig?.apiTimeoutMs = intValue
                }
                if let value = extraConfig["claudeDisableNonessential"] {
                    provider.claudeConfig?.disableNonessentialTraffic = value == "true"
                }
                if let value = extraConfig["claudeHideAttribution"] {
                    provider.claudeConfig?.hideAttribution = value == "true"
                }
                if let value = extraConfig["claudeAlwaysThinking"] {
                    provider.claudeConfig?.alwaysThinkingEnabled = value == "true"
                }
                if let value = extraConfig["claudeEnableTeammates"] {
                    provider.claudeConfig?.enableTeammates = value == "true"
                }
                if let value = extraConfig["claudeAwsRegion"]?.trimmedNonEmpty {
                    provider.claudeConfig?.awsRegion = value
                }
                if let value = extraConfig["claudeAwsAccessKeyId"]?.trimmedNonEmpty {
                    provider.claudeConfig?.awsAccessKeyId = value
                }
                if let value = extraConfig["claudeAwsSecretAccessKey"]?.trimmedNonEmpty {
                    provider.claudeConfig?.awsSecretAccessKey = value
                }
            }
        case .codex:
            if provider.codexConfig != nil {
                provider.codexConfig?.baseUrl = trimmedBaseUrl.isEmpty ? nil : trimmedBaseUrl
                provider.codexConfig?.model = trimmedModel.isEmpty ? nil : trimmedModel
                if let value = extraConfig["wireApi"]?.trimmedNonEmpty {
                    provider.codexConfig?.wireApi = value
                }
                if let value = extraConfig["reasoningEffort"]?.trimmedNonEmpty {
                    provider.codexConfig?.reasoningEffort = value
                }
            }
        case .gemini:
            if provider.geminiConfig != nil {
                provider.geminiConfig?.baseUrl = trimmedBaseUrl.isEmpty ? nil : trimmedBaseUrl
                provider.geminiConfig?.model = trimmedModel.isEmpty ? nil : trimmedModel
            }
        }

        provider.proxyConfig = proxyConfig?.normalized
        provider.billingConfig = billingConfig?.normalized
        return provider
    }
}

struct ProviderSaveOutcome: Equatable {
    var provider: Provider
    var didApplyToLiveConfig: Bool
}

struct ProviderDeletionOutcome: Equatable {
    var didDeleteCurrentProvider: Bool
    var fallbackProvider: Provider?
}

// MARK: - Proxy Config

struct ProviderProxyConfig: Codable, Equatable {
    var enabled: Bool = false
    var host: String = ""
    var port: String = ""
    var username: String = ""
    var password: String = ""

    var normalized: ProviderProxyConfig? {
        let trimmedHost = host.trimmingCharacters(in: .whitespacesAndNewlines)
        guard enabled, !trimmedHost.isEmpty else { return nil }
        return ProviderProxyConfig(
            enabled: true,
            host: trimmedHost,
            port: port.trimmingCharacters(in: .whitespacesAndNewlines),
            username: username.trimmingCharacters(in: .whitespacesAndNewlines),
            password: password.trimmingCharacters(in: .whitespacesAndNewlines)
        )
    }
}

// MARK: - Billing Config

struct ProviderBillingConfig: Codable, Equatable {
    var inputPricePerMillion: String = ""   // USD per 1M tokens
    var outputPricePerMillion: String = ""  // USD per 1M tokens
    var currency: String = "USD"
    var notes: String = ""

    var normalized: ProviderBillingConfig? {
        let trimmedInput = inputPricePerMillion.trimmingCharacters(in: .whitespacesAndNewlines)
        let trimmedOutput = outputPricePerMillion.trimmingCharacters(in: .whitespacesAndNewlines)
        let trimmedNotes = notes.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmedInput.isEmpty || !trimmedOutput.isEmpty || !trimmedNotes.isEmpty else {
            return nil
        }
        return ProviderBillingConfig(
            inputPricePerMillion: trimmedInput,
            outputPricePerMillion: trimmedOutput,
            currency: currency.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty ? "USD" : currency.trimmingCharacters(in: .whitespacesAndNewlines),
            notes: trimmedNotes
        )
    }
}

// MARK: - Provider Store

struct ProviderStore: Codable, Equatable {
    var version: Int = 1
    var providers: [Provider] = []
    var currentClaudeProviderId: String?
    var currentCodexProviderId: String?
    var currentGeminiProviderId: String?

    func currentProviderId(for app: ProviderAppType) -> String? {
        switch app {
        case .claude: return currentClaudeProviderId
        case .codex: return currentCodexProviderId
        case .gemini: return currentGeminiProviderId
        }
    }

    mutating func setCurrentProviderId(_ id: String?, for app: ProviderAppType) {
        switch app {
        case .claude: currentClaudeProviderId = id
        case .codex: currentCodexProviderId = id
        case .gemini: currentGeminiProviderId = id
        }
    }

    func providers(for app: ProviderAppType) -> [Provider] {
        providers.filter { $0.appType == app }.sorted { $0.sortIndex < $1.sortIndex }
    }
}

extension String {
    var trimmedNonEmpty: String? {
        let trimmed = trimmingCharacters(in: .whitespacesAndNewlines)
        return trimmed.isEmpty ? nil : trimmed
    }
}

// MARK: - Speed Test

struct SpeedTestResult: Equatable, Identifiable {
    var id: String { providerId }
    var providerId: String
    var providerName: String
    var latencyMs: Int?
    var error: String?
    var testedAt: Date

    var statusText: String {
        if let error { return error }
        if let ms = latencyMs { return "\(ms)ms" }
        return "Testing..."
    }

    var qualityLevel: SpeedTestQuality {
        guard let ms = latencyMs else { return .unknown }
        if ms < 500 { return .excellent }
        if ms < 1500 { return .good }
        if ms < 3000 { return .fair }
        return .poor
    }
}

enum SpeedTestQuality {
    case excellent, good, fair, poor, unknown

    var color: String {
        switch self {
        case .excellent: return "green"
        case .good: return "mint"
        case .fair: return "orange"
        case .poor: return "red"
        case .unknown: return "gray"
        }
    }
}

// MARK: - Provider Preset Template

struct ProviderPreset: Identifiable {
    var id: String
    var name: String
    var appType: ProviderAppType
    var category: ProviderCategory
    var baseUrl: String?
    var defaultModel: String?
    var websiteUrl: String?
    var apiKeyUrl: String?
    var icon: String?
    var iconColor: String?
    var isPartner: Bool
    var apiFormat: ClaudeApiFormat?
    var apiKeyField: ClaudeApiKeyField?
    var templateValues: [String: String]?
    // Codex-specific
    var wireApi: String?

    func makeProvider(apiKey: String) -> Provider {
        let now = Int64(Date().timeIntervalSince1970)
        var provider = Provider(
            id: UUID().uuidString,
            name: name,
            appType: appType,
            category: category,
            websiteUrl: websiteUrl,
            apiKeyUrl: apiKeyUrl,
            icon: icon,
            iconColor: iconColor,
            isPreset: true,
            presetId: id,
            sortIndex: 0,
            createdAt: now,
            updatedAt: now,
            isCurrent: false
        )

        switch appType {
        case .claude:
            provider.claudeConfig = ClaudeSettingsConfig(
                apiKey: apiKey,
                baseUrl: baseUrl,
                model: defaultModel,
                apiFormat: apiFormat,
                apiKeyField: apiKeyField ?? .authToken
            )
        case .codex:
            provider.codexConfig = CodexSettingsConfig(
                apiKey: apiKey,
                baseUrl: baseUrl,
                model: defaultModel,
                wireApi: wireApi ?? "responses"
            )
        case .gemini:
            provider.geminiConfig = GeminiSettingsConfig(
                apiKey: apiKey,
                baseUrl: baseUrl,
                model: defaultModel
            )
        }

        return provider
    }
}
