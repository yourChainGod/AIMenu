import SwiftUI
import AppKit

// MARK: - Edit Provider Sheet

struct EditProviderSheet: View {
    let provider: Provider
    let onSave: (Provider) -> Void
    let onCancel: () -> Void

    @State private var providerName: String
    @State private var websiteUrl: String
    @State private var apiKeyUrl: String
    @State private var notes: String
    @State private var showApiKey = false
    @State private var isFetchingModels = false
    @State private var fetchedModels: [String] = []
    @State private var modelFetchStatus: String?
    @State private var modelFetchFailed = false
    @State private var showConfigPreview = true

    @State private var claudeApiKey: String
    @State private var claudeBaseUrl: String
    @State private var claudeModel: String
    @State private var claudeHaikuModel: String
    @State private var claudeSonnetModel: String
    @State private var claudeOpusModel: String
    @State private var claudeMaxOutputTokens: String
    @State private var claudeApiTimeoutMs: String
    @State private var claudeApiFormat: ClaudeApiFormat
    @State private var claudeApiKeyField: ClaudeApiKeyField
    @State private var claudeDisableNonessential: Bool
    @State private var claudeHideAttribution: Bool
    @State private var claudeAlwaysThinking: Bool
    @State private var claudeEnableTeammates: Bool
    @State private var claudeApplyCommonConfig: Bool
    @State private var claudeCommonConfigJSON: String
    @State private var showClaudeAdvanced = false
    @State private var showClaudeCommonConfigEditor = false

    @State private var codexApiKey: String
    @State private var codexBaseUrl: String
    @State private var codexModel: String
    @State private var codexWireApi: String
    @State private var codexReasoningEffort: String

    @State private var geminiApiKey: String
    @State private var geminiBaseUrl: String
    @State private var geminiModel: String

    init(provider: Provider, onSave: @escaping (Provider) -> Void, onCancel: @escaping () -> Void) {
        self.provider = provider
        self.onSave = onSave
        self.onCancel = onCancel
        _providerName = State(initialValue: provider.name)
        _websiteUrl = State(initialValue: provider.websiteUrl ?? "")
        _apiKeyUrl = State(initialValue: provider.apiKeyUrl ?? "")
        _notes = State(initialValue: provider.notes ?? "")

        _claudeApiKey = State(initialValue: provider.claudeConfig?.apiKey ?? "")
        _claudeBaseUrl = State(initialValue: provider.claudeConfig?.baseUrl ?? "")
        _claudeModel = State(initialValue: provider.claudeConfig?.model ?? "")
        _claudeHaikuModel = State(initialValue: provider.claudeConfig?.haikuModel ?? "")
        _claudeSonnetModel = State(initialValue: provider.claudeConfig?.sonnetModel ?? "")
        _claudeOpusModel = State(initialValue: provider.claudeConfig?.opusModel ?? "")
        _claudeMaxOutputTokens = State(initialValue: provider.claudeConfig?.maxOutputTokens.map(String.init) ?? "")
        _claudeApiTimeoutMs = State(initialValue: provider.claudeConfig?.apiTimeoutMs.map(String.init) ?? "")
        _claudeApiFormat = State(initialValue: provider.claudeConfig?.apiFormat ?? .anthropic)
        _claudeApiKeyField = State(initialValue: provider.claudeConfig?.apiKeyField ?? .authToken)
        _claudeDisableNonessential = State(initialValue: provider.claudeConfig?.disableNonessentialTraffic ?? false)
        _claudeHideAttribution = State(initialValue: provider.claudeConfig?.hideAttribution ?? false)
        _claudeAlwaysThinking = State(initialValue: provider.claudeConfig?.alwaysThinkingEnabled ?? false)
        _claudeEnableTeammates = State(initialValue: provider.claudeConfig?.enableTeammates ?? false)
        _claudeApplyCommonConfig = State(initialValue: provider.claudeConfig?.applyCommonConfig ?? false)
        _claudeCommonConfigJSON = State(initialValue: provider.claudeConfig?.commonConfigJSON ?? "")

        _codexApiKey = State(initialValue: provider.codexConfig?.apiKey ?? "")
        _codexBaseUrl = State(initialValue: provider.codexConfig?.baseUrl ?? "")
        _codexModel = State(initialValue: provider.codexConfig?.model ?? "")
        _codexWireApi = State(initialValue: provider.codexConfig?.wireApi ?? "responses")
        _codexReasoningEffort = State(initialValue: provider.codexConfig?.reasoningEffort ?? "medium")

        _geminiApiKey = State(initialValue: provider.geminiConfig?.apiKey ?? "")
        _geminiBaseUrl = State(initialValue: provider.geminiConfig?.baseUrl ?? "")
        _geminiModel = State(initialValue: provider.geminiConfig?.model ?? "")
    }

    private var accentTint: Color { provider.appType.formAccent }

    private var currentApiKeyBinding: Binding<String> {
        switch provider.appType {
        case .claude: return $claudeApiKey
        case .codex: return $codexApiKey
        case .gemini: return $geminiApiKey
        }
    }

    private var currentBaseUrlBinding: Binding<String> {
        switch provider.appType {
        case .claude: return $claudeBaseUrl
        case .codex: return $codexBaseUrl
        case .gemini: return $geminiBaseUrl
        }
    }

    private var currentBaseUrlPlaceholder: String { provider.appType.defaultBaseURL }

    private var canSave: Bool {
        !currentApiKeyBinding.wrappedValue.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
    }

    private var resolvedBaseURL: String {
        currentBaseUrlBinding.wrappedValue.trimmedNonEmpty ?? provider.appType.defaultBaseURL
    }

    private var currentModelName: String {
        switch provider.appType {
        case .claude: return claudeModel
        case .codex: return codexModel
        case .gemini: return geminiModel
        }
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            HStack(alignment: .center, spacing: 10) {
                RoundedRectangle(cornerRadius: 10, style: .continuous)
                    .fill(accentTint.opacity(0.07))
                    .overlay {
                        Image(systemName: provider.displayIcon)
                            .font(.system(size: 13, weight: .semibold))
                            .foregroundStyle(accentTint)
                    }
                    .frame(width: 30, height: 30)

                VStack(alignment: .leading, spacing: 3) {
                    HStack(spacing: 7) {
                        Text(provider.name)
                            .font(.system(size: 18, weight: .semibold))
                            .lineLimit(1)

                        ProviderConfigBadge(text: provider.appType.displayName, tint: accentTint)
                    }

                    HStack(spacing: 8) {
                        ProviderConfigBadge(
                            text: provider.isCurrent ? L10n.tr("providers.status.current") : L10n.tr("providers.status.inactive"),
                            tint: provider.isCurrent ? .mint : .secondary
                        )

                        HStack(spacing: 5) {
                            Image(systemName: "arrow.down.doc.fill")
                                .font(.caption2.weight(.semibold))
                            Text(provider.appType.liveConfigPathsText)
                                .font(.caption2)
                                .lineLimit(1)
                                .truncationMode(.middle)
                        }
                        .foregroundStyle(.secondary)
                    }
                }

                Spacer(minLength: 0)

                CloseGlassButton { onCancel() }
            }
            .padding(.horizontal, 16)
            .padding(.top, 10)
            .padding(.bottom, 6)

            Rectangle()
                .fill(accentTint.opacity(0.06))
                .frame(height: 1)

            ScrollView {
                VStack(alignment: .leading, spacing: 12) {
                    sectionCard(title: L10n.tr("providers.section.basic.title"), subtitle: L10n.tr("providers.section.basic.subtitle"), icon: "square.text.square") {
                        HStack(alignment: .top, spacing: 12) {
                            editConfigField(label: L10n.tr("common.name")) {
                                TextField(L10n.tr("providers.field.provider_name_placeholder"), text: $providerName)
                                    .frostedRoundedInput(cornerRadius: 10)
                            }
                            .frame(maxWidth: .infinity, alignment: .leading)

                            editConfigField(label: L10n.tr("providers.field.notes")) {
                                TextField(L10n.tr("providers.field.notes_placeholder"), text: $notes)
                                    .frostedRoundedInput(cornerRadius: 10)
                            }
                            .frame(maxWidth: .infinity, alignment: .leading)
                        }
                    }

                    sectionCard(title: L10n.tr("providers.section.credentials.title"), subtitle: L10n.tr("providers.section.credentials.subtitle"), icon: "key.fill") {
                        editConfigField(
                            label: L10n.tr("providers.field.api_key_required"),
                            trailingLink: apiKeyUrl.isEmpty ? nil : URL(string: apiKeyUrl),
                            trailingLinkLabel: L10n.tr("providers.action.get_key")
                        ) {
                            HStack(spacing: 6) {
                                Group {
                                    if showApiKey {
                                        TextField(L10n.tr("providers.field.api_key_placeholder"), text: currentApiKeyBinding)
                                    } else {
                                        SecureField(L10n.tr("providers.field.api_key_placeholder"), text: currentApiKeyBinding)
                                    }
                                }
                                .frostedRoundedInput(cornerRadius: 10)
                                Button { showApiKey.toggle() } label: {
                                    Image(systemName: showApiKey ? "eye.slash" : "eye")
                                        .foregroundStyle(.secondary)
                                        .font(.subheadline)
                                }
                                .buttonStyle(.plain)
                            }
                        }

                        editConfigField(
                            label: L10n.tr("providers.field.base_url"),
                            trailingLink: websiteUrl.isEmpty ? nil : URL(string: websiteUrl),
                            trailingLinkLabel: L10n.tr("providers.action.visit")
                        ) {
                            TextField(currentBaseUrlPlaceholder, text: currentBaseUrlBinding)
                                .frostedRoundedInput(cornerRadius: 10)
                        }
                    }

                    appSpecificEditSection

                    previewSection

                    sectionCard(title: L10n.tr("providers.section.links.title"), subtitle: L10n.tr("providers.section.links.subtitle"), icon: "link") {
                        HStack(alignment: .top, spacing: 12) {
                            editConfigField(label: L10n.tr("providers.field.website_link")) {
                                TextField("https://", text: $websiteUrl)
                                    .frostedRoundedInput(cornerRadius: 10)
                            }
                            .frame(maxWidth: .infinity, alignment: .leading)

                            editConfigField(label: L10n.tr("providers.field.api_key_link")) {
                                TextField("https://", text: $apiKeyUrl)
                                    .frostedRoundedInput(cornerRadius: 10)
                            }
                            .frame(maxWidth: .infinity, alignment: .leading)
                        }
                    }
                }
                .padding(.horizontal, 18)
                .padding(.vertical, 10)
            }
            .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .top)

            HStack(spacing: 10) {
                Button(L10n.tr("common.cancel")) { onCancel() }
                    .aimenuActionButtonStyle()
                Button(L10n.tr("common.save")) { saveProvider() }
                    .aimenuActionButtonStyle(prominent: true, tint: accentTint)
                    .disabled(!canSave)
            }
            .frame(maxWidth: .infinity, alignment: .center)
            .padding(.horizontal, 18)
            .padding(.vertical, 10)
            .background(
                LinearGradient(
                    colors: [
                        accentTint.opacity(0.05),
                        Color.clear
                    ],
                    startPoint: .topLeading,
                    endPoint: .bottomTrailing
                )
            )
            .overlay(alignment: .top) {
                Rectangle()
                    .fill(accentTint.opacity(0.08))
                    .frame(height: 1)
            }
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
    }

    @ViewBuilder
    private var appSpecificEditSection: some View {
        switch provider.appType {
        case .claude:
            claudeEditFields
        case .codex:
            codexEditFields
        case .gemini:
            geminiEditFields
        }
    }

    private var claudeEditFields: some View {
        VStack(alignment: .leading, spacing: 12) {
            sectionCard(title: L10n.tr("providers.section.claude.title"), subtitle: L10n.tr("providers.section.claude.subtitle"), icon: "sparkles.rectangle.stack.fill") {
                editConfigField(label: L10n.tr("providers.field.api_format")) {
                    ProviderSegmentedControl(
                        selection: $claudeApiFormat,
                        options: [
                            .init(title: L10n.tr("providers.option.anthropic_native"), value: .anthropic),
                            .init(title: "OpenAI Chat", value: .openaiChat),
                            .init(title: "OpenAI Responses", value: .openaiResponses)
                        ],
                        accent: accentTint
                    )
                }
                editConfigField(label: L10n.tr("providers.field.auth_field")) {
                    ProviderSegmentedControl(
                        selection: $claudeApiKeyField,
                        options: [
                            .init(title: "ANTHROPIC_AUTH_TOKEN", value: .authToken),
                            .init(title: "ANTHROPIC_API_KEY", value: .apiKey)
                        ],
                        accent: accentTint
                    )
                }
                ProviderModelInputRow(
                    title: L10n.tr("providers.field.primary_model"),
                    placeholder: L10n.tr("providers.placeholder.use_default"),
                    text: $claudeModel,
                    isFetching: isFetchingModels,
                    canFetch: canSave,
                    accent: accentTint,
                    onFetch: fetchModels
                )
                modelFetchStatusView
                fetchedModelRow(selection: $claudeModel)
            }

            sectionCard(title: L10n.tr("providers.section.advanced.title"), subtitle: L10n.tr("providers.section.advanced.subtitle"), icon: "dial.medium.fill") {
                Button {
                    withAnimation(.easeInOut(duration: 0.2)) { showClaudeAdvanced.toggle() }
                } label: {
                    HStack {
                        VStack(alignment: .leading, spacing: 3) {
                            Text(L10n.tr("providers.advanced.summary_title"))
                                .font(.subheadline.weight(.semibold))
                                .foregroundStyle(.primary)
                            Text(L10n.tr("providers.advanced.summary_subtitle"))
                                .font(.caption)
                                .foregroundStyle(.secondary)
                        }
                        Spacer(minLength: 0)
                        Image(systemName: "chevron.right")
                            .font(.caption.weight(.semibold))
                            .foregroundStyle(.tertiary)
                            .rotationEffect(.degrees(showClaudeAdvanced ? 90 : 0))
                    }
                }
                .buttonStyle(.plain)

                if showClaudeAdvanced {
                    VStack(alignment: .leading, spacing: 12) {
                        HStack(alignment: .top, spacing: 12) {
                            editConfigField(label: L10n.tr("providers.field.haiku_default_model")) {
                                TextField(L10n.tr("providers.placeholder.optional_override"), text: $claudeHaikuModel)
                                    .frostedRoundedInput(cornerRadius: 10)
                            }
                            .frame(maxWidth: .infinity, alignment: .leading)

                            editConfigField(label: L10n.tr("providers.field.sonnet_default_model")) {
                                TextField(L10n.tr("providers.placeholder.optional_override"), text: $claudeSonnetModel)
                                    .frostedRoundedInput(cornerRadius: 10)
                            }
                            .frame(maxWidth: .infinity, alignment: .leading)
                        }
                        HStack(alignment: .top, spacing: 12) {
                            editConfigField(label: L10n.tr("providers.field.opus_default_model")) {
                                TextField(L10n.tr("providers.placeholder.optional_override"), text: $claudeOpusModel)
                                    .frostedRoundedInput(cornerRadius: 10)
                            }
                            .frame(maxWidth: .infinity, alignment: .leading)

                            editConfigField(label: L10n.tr("providers.field.max_output_tokens")) {
                                TextField(L10n.tr("providers.placeholder.use_default"), text: $claudeMaxOutputTokens)
                                    .frostedRoundedInput(cornerRadius: 10)
                            }
                            .frame(maxWidth: .infinity, alignment: .leading)
                        }
                        editConfigField(label: L10n.tr("providers.field.timeout_ms")) {
                            TextField(L10n.tr("providers.placeholder.use_default"), text: $claudeApiTimeoutMs)
                                .frostedRoundedInput(cornerRadius: 10)
                        }
                        Toggle(L10n.tr("providers.toggle.disable_nonessential"), isOn: $claudeDisableNonessential)
                            .toggleStyle(.checkbox)
                            .font(.subheadline)
                    }
                    .padding(.top, 2)
                }
            }
        }
    }

    private var codexEditFields: some View {
        VStack(alignment: .leading, spacing: 12) {
            sectionCard(title: L10n.tr("providers.section.codex_model.title"), subtitle: L10n.tr("providers.section.codex_model.subtitle"), icon: "chevron.left.forwardslash.chevron.right") {
                ProviderModelInputRow(
                    title: L10n.tr("providers.field.model_name"),
                    placeholder: L10n.tr("providers.placeholder.codex_model_example"),
                    text: $codexModel,
                    isFetching: isFetchingModels,
                    canFetch: canSave,
                    accent: accentTint,
                    onFetch: fetchModels
                )
                modelFetchStatusView
                fetchedModelRow(selection: $codexModel)
            }

            sectionCard(title: L10n.tr("providers.section.codex_runtime.title"), subtitle: L10n.tr("providers.section.codex_runtime.subtitle"), icon: "slider.horizontal.3") {
                HStack(alignment: .top, spacing: 12) {
                    editConfigField(label: L10n.tr("providers.field.wire_api")) {
                        ProviderSegmentedControl(
                            selection: $codexWireApi,
                            options: [
                                .init(title: "responses", value: "responses"),
                                .init(title: "chat", value: "chat")
                            ],
                            accent: accentTint
                        )
                    }
                    .frame(maxWidth: .infinity, alignment: .leading)

                    editConfigField(label: L10n.tr("providers.field.reasoning_effort")) {
                        ProviderSegmentedControl(
                            selection: $codexReasoningEffort,
                            options: [
                                .init(title: "low", value: "low"),
                                .init(title: "medium", value: "medium"),
                                .init(title: "high", value: "high")
                            ],
                            accent: accentTint
                        )
                    }
                    .frame(maxWidth: .infinity, alignment: .leading)
                }
            }
        }
    }

    private var geminiEditFields: some View {
        sectionCard(title: L10n.tr("providers.section.gemini.title"), subtitle: L10n.tr("providers.section.gemini.subtitle"), icon: "diamond.fill") {
            ProviderModelInputRow(
                title: L10n.tr("providers.field.model_name"),
                placeholder: L10n.tr("providers.placeholder.gemini_model_example"),
                text: $geminiModel,
                isFetching: isFetchingModels,
                canFetch: canSave,
                accent: accentTint,
                onFetch: fetchModels
            )
            modelFetchStatusView
            fetchedModelRow(selection: $geminiModel)
        }
    }

    private var previewSection: some View {
        sectionCard(title: L10n.tr("providers.preview.section_title"), subtitle: previewSubtitle, icon: "doc.text.magnifyingglass") {
            Button {
                withAnimation(.easeInOut(duration: 0.2)) { showConfigPreview.toggle() }
            } label: {
                HStack {
                    VStack(alignment: .leading, spacing: 3) {
                        Text(showConfigPreview ? L10n.tr("providers.action.collapse_preview") : L10n.tr("providers.action.expand_preview"))
                            .font(.subheadline.weight(.semibold))
                            .foregroundStyle(.primary)
                        Text(previewSubtitle)
                            .font(.caption)
                            .foregroundStyle(.secondary)
                    }
                    Spacer(minLength: 0)
                    Image(systemName: "chevron.right")
                        .font(.caption.weight(.semibold))
                        .foregroundStyle(.tertiary)
                        .rotationEffect(.degrees(showConfigPreview ? 90 : 0))
                }
            }
            .buttonStyle(.plain)

            if showConfigPreview {
                if provider.appType == .claude {
                    ClaudeCommonConfigControls(
                        hideAttribution: $claudeHideAttribution,
                        alwaysThinking: $claudeAlwaysThinking,
                        enableTeammates: $claudeEnableTeammates,
                        applyCommonConfig: $claudeApplyCommonConfig,
                        showCommonConfigEditor: $showClaudeCommonConfigEditor,
                        accent: accentTint
                    )

                    if claudeApplyCommonConfig && showClaudeCommonConfigEditor {
                        ProviderConfigPreviewBlock(
                            title: L10n.tr("providers.preview.common_config_title"),
                            subtitle: L10n.tr("providers.preview.common_config_subtitle"),
                            content: buildClaudeCommonConfigPreview(),
                            accent: accentTint,
                            onApply: applyClaudeCommonConfigPreview
                        )
                    }
                }

                ForEach(previewBlocks, id: \.title) { block in
                    ProviderConfigPreviewBlock(
                        title: block.title,
                        subtitle: block.subtitle,
                        content: block.content,
                        accent: accentTint,
                        onApply: block.onApply
                    )
                }
            }
        }
    }

    private var previewSubtitle: String {
        switch provider.appType {
        case .claude:
            return L10n.tr("providers.preview.subtitle.claude")
        case .codex:
            return L10n.tr("providers.preview.subtitle.codex")
        case .gemini:
            return L10n.tr("providers.preview.subtitle.gemini")
        }
    }

    private var previewBlocks: [ProviderPreviewBlockData] {
        switch provider.appType {
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

    private var normalizedClaudeCommonConfigJSON: String {
        normalizedJSONObjectString(claudeCommonConfigJSON) ?? "{}"
    }

    @ViewBuilder
    private var modelFetchStatusView: some View {
        if let modelFetchStatus {
            Text(modelFetchStatus)
                .font(.caption)
                .foregroundStyle(modelFetchFailed ? .red : .secondary)
        }
    }

    @ViewBuilder
    private func fetchedModelRow(selection: Binding<String>) -> some View {
        if !fetchedModels.isEmpty {
            ScrollView(.horizontal, showsIndicators: false) {
                HStack(spacing: 6) {
                    ForEach(fetchedModels, id: \.self) { modelID in
                        Button {
                            selection.wrappedValue = modelID
                        } label: {
                            Text(modelID)
                                .font(.caption2.weight(.medium))
                                .padding(.horizontal, 9)
                                .padding(.vertical, 5)
                                .background(
                                    RoundedRectangle(cornerRadius: 8, style: .continuous)
                                        .fill(selection.wrappedValue == modelID ? accentTint.opacity(0.11) : Color.primary.opacity(0.04))
                                        .overlay(
                                            RoundedRectangle(cornerRadius: 8, style: .continuous)
                                                .strokeBorder(selection.wrappedValue == modelID ? accentTint.opacity(0.22) : Color.primary.opacity(0.06), lineWidth: 1)
                                        )
                                )
                                .foregroundStyle(selection.wrappedValue == modelID ? accentTint : .secondary)
                        }
                        .buttonStyle(.plain)
                    }
                }
                .padding(.vertical, 2)
            }
        }
    }

    private func applyClaudePreview(_ text: String) throws {
        let payload = try parsePreviewJSONObject(text)
        let env = payload["env"] as? [String: Any] ?? [:]

        if let token = previewString(env["ANTHROPIC_AUTH_TOKEN"]) {
            claudeApiKeyField = .authToken
            claudeApiKey = token
        } else if let key = previewString(env["ANTHROPIC_API_KEY"]) {
            claudeApiKeyField = .apiKey
            claudeApiKey = key
        }

        if let value = previewString(env["ANTHROPIC_BASE_URL"]) { claudeBaseUrl = value }
        claudeModel = previewString(env["ANTHROPIC_MODEL"]) ?? ""
        claudeHaikuModel = previewString(env["ANTHROPIC_DEFAULT_HAIKU_MODEL"]) ?? ""
        claudeSonnetModel = previewString(env["ANTHROPIC_DEFAULT_SONNET_MODEL"]) ?? ""
        claudeOpusModel = previewString(env["ANTHROPIC_DEFAULT_OPUS_MODEL"]) ?? ""
        claudeMaxOutputTokens = previewString(env["CLAUDE_CODE_MAX_OUTPUT_TOKENS"]) ?? ""
        claudeApiTimeoutMs = previewString(env["API_TIMEOUT_MS"]) ?? ""
        claudeDisableNonessential = previewBool(env["CLAUDE_CODE_DISABLE_NONESSENTIAL_TRAFFIC"])
        claudeEnableTeammates = previewBool(env["CLAUDE_CODE_EXPERIMENTAL_AGENT_TEAMS"])
        claudeHideAttribution = payload["attribution"] != nil
        claudeAlwaysThinking = previewBool(payload["alwaysThinkingEnabled"])
        let commonConfig = extractClaudeCommonConfig(from: payload)
        claudeApplyCommonConfig = !commonConfig.isEmpty
        claudeCommonConfigJSON = commonConfig.isEmpty ? "" : prettyJSONString(commonConfig)
    }

    private func applyClaudeCommonConfigPreview(_ text: String) throws {
        let payload = try parsePreviewJSONObject(text)
        claudeApplyCommonConfig = !payload.isEmpty
        claudeCommonConfigJSON = payload.isEmpty ? "" : prettyJSONString(payload)
    }

    private func applyCodexAuthPreview(_ text: String) throws {
        let payload = try parsePreviewJSONObject(text)
        if let value = previewString(payload["OPENAI_API_KEY"]) { codexApiKey = value }
        if let value = previewString(payload["OPENAI_BASE_URL"]) { codexBaseUrl = value }
    }

    private func applyCodexTomlPreview(_ text: String) throws {
        let payload = try parsePreviewTOML(text)
        if let value = payload["model"] { codexModel = value }
        if let value = payload["wire_api"] { codexWireApi = value }
        if let value = payload["base_url"] { codexBaseUrl = value }
        if let value = payload["reasoning_effort"] { codexReasoningEffort = value }
    }

    private func applyGeminiPreview(_ text: String) throws {
        let payload = try parsePreviewDotEnv(text)
        if let value = payload["GEMINI_API_KEY"] { geminiApiKey = value }
        if let value = payload["GOOGLE_GEMINI_BASE_URL"] { geminiBaseUrl = value }
        if let value = payload["GEMINI_MODEL"] { geminiModel = value }
    }

    private func buildClaudePreview() -> String {
        var settings = claudeApplyCommonConfig ? (parsedJSONObjectString(claudeCommonConfigJSON) ?? [:]) : [:]
        var env: [String: Any] = [
            claudeApiKeyField.rawValue: claudeApiKey.trimmedNonEmpty ?? "<API_KEY>"
        ]
        env["ANTHROPIC_BASE_URL"] = resolvedBaseURL
        if let model = claudeModel.trimmedNonEmpty {
            env["ANTHROPIC_MODEL"] = model
        }
        if let model = claudeHaikuModel.trimmedNonEmpty {
            env["ANTHROPIC_DEFAULT_HAIKU_MODEL"] = model
        }
        if let model = claudeSonnetModel.trimmedNonEmpty {
            env["ANTHROPIC_DEFAULT_SONNET_MODEL"] = model
        }
        if let model = claudeOpusModel.trimmedNonEmpty {
            env["ANTHROPIC_DEFAULT_OPUS_MODEL"] = model
        }
        if let tokens = claudeMaxOutputTokens.trimmedNonEmpty {
            env["CLAUDE_CODE_MAX_OUTPUT_TOKENS"] = tokens
        }
        if let timeout = claudeApiTimeoutMs.trimmedNonEmpty {
            env["API_TIMEOUT_MS"] = timeout
        }
        if claudeDisableNonessential {
            env["CLAUDE_CODE_DISABLE_NONESSENTIAL_TRAFFIC"] = "1"
        }
        if claudeEnableTeammates {
            env["CLAUDE_CODE_EXPERIMENTAL_AGENT_TEAMS"] = "1"
        }

        settings["env"] = env
        if claudeHideAttribution {
            settings["attribution"] = ["commit": "", "pr": ""]
        } else {
            settings.removeValue(forKey: "attribution")
        }
        if claudeAlwaysThinking {
            settings["alwaysThinkingEnabled"] = true
        } else {
            settings.removeValue(forKey: "alwaysThinkingEnabled")
        }
        return prettyJSONString(settings)
    }

    private func buildClaudeCommonConfigPreview() -> String {
        normalizedClaudeCommonConfigJSON
    }

    private func buildCodexAuthPreview() -> String {
        var auth: [String: Any] = ["OPENAI_API_KEY": codexApiKey.trimmedNonEmpty ?? "<API_KEY>"]
        auth["OPENAI_BASE_URL"] = resolvedBaseURL
        return prettyJSONString(auth)
    }

    private func buildCodexTomlPreview() -> String {
        var lines: [String] = []
        if let model = codexModel.trimmedNonEmpty {
            lines.append("model = \(tomlQuoted(model))")
        }
        lines.append("wire_api = \(tomlQuoted(codexWireApi))")
        lines.append("base_url = \(tomlQuoted(resolvedBaseURL))")
        lines.append("reasoning_effort = \(tomlQuoted(codexReasoningEffort))")
        lines.append("")
        lines.append(L10n.tr("providers.toml.comment_preserved_sections"))
        return lines.joined(separator: "\n")
    }

    private func buildGeminiPreview() -> String {
        [
            "GEMINI_API_KEY=\(dotenvEscaped(geminiApiKey.trimmedNonEmpty ?? "<API_KEY>"))",
            "GOOGLE_GEMINI_BASE_URL=\(dotenvEscaped(resolvedBaseURL))",
            "GEMINI_MODEL=\(dotenvEscaped(geminiModel.trimmedNonEmpty ?? "gemini-2.5-pro"))"
        ].joined(separator: "\n")
    }

    private func fetchModels() {
        let base = resolvedBaseURL
        let key = currentApiKeyBinding.wrappedValue.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !key.isEmpty else { return }

        isFetchingModels = true
        modelFetchFailed = false
        modelFetchStatus = L10n.tr("providers.models.fetching")

        Task {
            do {
                let models = try await ProviderModelCatalogService.fetch(
                    appType: provider.appType,
                    baseUrl: base,
                    apiKey: key,
                    claudeApiFormat: provider.appType == .claude ? claudeApiFormat : nil
                )
                await MainActor.run {
                    fetchedModels = models
                    isFetchingModels = false
                    modelFetchFailed = false
                    modelFetchStatus = models.isEmpty
                        ? L10n.tr("providers.models.empty_success")
                        : L10n.tr("providers.models.fetched_count_format", String(models.count))
                }
            } catch {
                await MainActor.run {
                    fetchedModels = []
                    isFetchingModels = false
                    modelFetchFailed = true
                    modelFetchStatus = error.localizedDescription
                }
            }
        }
    }

    private func saveProvider() {
        var updated = provider
        updated.name = providerName.isEmpty ? provider.name : providerName
        updated.websiteUrl = websiteUrl.isEmpty ? nil : websiteUrl
        updated.apiKeyUrl = apiKeyUrl.isEmpty ? nil : apiKeyUrl
        updated.notes = notes.isEmpty ? nil : notes

        switch provider.appType {
        case .claude:
            updated.claudeConfig?.apiKey = claudeApiKey
            updated.claudeConfig?.baseUrl = claudeBaseUrl.isEmpty ? nil : claudeBaseUrl
            updated.claudeConfig?.model = claudeModel.isEmpty ? nil : claudeModel
            updated.claudeConfig?.haikuModel = claudeHaikuModel.isEmpty ? nil : claudeHaikuModel
            updated.claudeConfig?.sonnetModel = claudeSonnetModel.isEmpty ? nil : claudeSonnetModel
            updated.claudeConfig?.opusModel = claudeOpusModel.isEmpty ? nil : claudeOpusModel
            updated.claudeConfig?.maxOutputTokens = Int(claudeMaxOutputTokens)
            updated.claudeConfig?.apiTimeoutMs = Int(claudeApiTimeoutMs)
            updated.claudeConfig?.apiFormat = claudeApiFormat
            updated.claudeConfig?.apiKeyField = claudeApiKeyField
            updated.claudeConfig?.disableNonessentialTraffic = claudeDisableNonessential
            updated.claudeConfig?.hideAttribution = claudeHideAttribution
            updated.claudeConfig?.alwaysThinkingEnabled = claudeAlwaysThinking
            updated.claudeConfig?.enableTeammates = claudeEnableTeammates
            updated.claudeConfig?.applyCommonConfig = claudeApplyCommonConfig
            updated.claudeConfig?.commonConfigJSON = claudeApplyCommonConfig ? normalizedClaudeCommonConfigJSON : nil
        case .codex:
            updated.codexConfig?.apiKey = codexApiKey
            updated.codexConfig?.baseUrl = codexBaseUrl.isEmpty ? nil : codexBaseUrl
            updated.codexConfig?.model = codexModel.isEmpty ? nil : codexModel
            updated.codexConfig?.wireApi = codexWireApi
            updated.codexConfig?.reasoningEffort = codexReasoningEffort
        case .gemini:
            updated.geminiConfig?.apiKey = geminiApiKey
            updated.geminiConfig?.baseUrl = geminiBaseUrl.isEmpty ? nil : geminiBaseUrl
            updated.geminiConfig?.model = geminiModel.isEmpty ? nil : geminiModel
        }
        onSave(updated)
    }

    @ViewBuilder
    private func sectionCard<Content: View>(
        title: String? = nil,
        subtitle: String? = nil,
        icon: String? = nil,
        emphasis: Bool = false,
        @ViewBuilder content: () -> Content
    ) -> some View {
        VStack(alignment: .leading, spacing: 12) {
            if let title {
                HStack(alignment: .top, spacing: 10) {
                    if let icon {
                        RoundedRectangle(cornerRadius: 10, style: .continuous)
                            .fill(accentTint.opacity(0.065))
                            .overlay {
                                Image(systemName: icon)
                                    .font(.system(size: 11, weight: .semibold))
                                    .foregroundStyle(accentTint)
                            }
                            .frame(width: 26, height: 26)
                    }

                    VStack(alignment: .leading, spacing: 3) {
                        Text(title)
                            .font(.callout.weight(.semibold))
                            .foregroundStyle(.primary)
                        if let subtitle {
                            Text(subtitle)
                                .font(.caption2)
                                .foregroundStyle(.secondary)
                        }
                    }

                    Spacer(minLength: 0)
                }
            }
            content()
        }
        .padding(13)
        .background(
            RoundedRectangle(cornerRadius: 14, style: .continuous)
                .fill(
                    LinearGradient(
                        colors: [
                            Color(nsColor: .controlBackgroundColor).opacity(0.97),
                            accentTint.opacity(emphasis ? 0.038 : 0.018)
                        ],
                        startPoint: .topLeading,
                        endPoint: .bottomTrailing
                    )
                )
                .overlay(
                    RoundedRectangle(cornerRadius: 14, style: .continuous)
                        .strokeBorder(
                            accentTint.opacity(emphasis ? 0.1 : 0.06),
                            lineWidth: 1
                        )
                )
        )
        .shadow(color: accentTint.opacity(emphasis ? 0.028 : 0.01), radius: emphasis ? 10 : 4, x: 0, y: emphasis ? 4 : 2)
    }

    @ViewBuilder
    private func editConfigField<Content: View>(
        label: String,
        trailingLink: URL? = nil,
        trailingLinkLabel: String = "",
        @ViewBuilder content: () -> Content
    ) -> some View {
        VStack(alignment: .leading, spacing: 6) {
            HStack(spacing: 4) {
                Text(label)
                    .font(.caption2.weight(.semibold))
                    .foregroundStyle(.secondary)
                Spacer(minLength: 0)
                if let url = trailingLink {
                    Link(trailingLinkLabel, destination: url)
                        .font(.caption2)
                        .foregroundStyle(accentTint)
                }
            }
            content()
        }
    }
}
