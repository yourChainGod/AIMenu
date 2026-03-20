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
    @State private var claude = ClaudeFormState()

    @State private var codexApiKey: String
    @State private var codexBaseUrl: String
    @State private var codexModel: String
    @State private var codex = CodexFormState()

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
        var claudeState = ClaudeFormState()
        if let cc = provider.claudeConfig {
            claudeState.apiFormat = cc.apiFormat ?? .anthropic
            claudeState.apiKeyField = cc.apiKeyField ?? .authToken
            claudeState.haikuModel = cc.haikuModel ?? ""
            claudeState.sonnetModel = cc.sonnetModel ?? ""
            claudeState.opusModel = cc.opusModel ?? ""
            claudeState.maxOutputTokens = cc.maxOutputTokens.map(String.init) ?? ""
            claudeState.apiTimeoutMs = cc.apiTimeoutMs.map(String.init) ?? ""
            claudeState.disableNonessential = cc.disableNonessentialTraffic ?? false
            claudeState.hideAttribution = cc.hideAttribution ?? false
            claudeState.alwaysThinking = cc.alwaysThinkingEnabled ?? false
            claudeState.enableTeammates = cc.enableTeammates ?? false
            claudeState.applyCommonConfig = cc.applyCommonConfig ?? false
            claudeState.commonConfigJSON = cc.commonConfigJSON ?? ""
        }
        _claude = State(initialValue: claudeState)

        _codexApiKey = State(initialValue: provider.codexConfig?.apiKey ?? "")
        _codexBaseUrl = State(initialValue: provider.codexConfig?.baseUrl ?? "")
        _codexModel = State(initialValue: provider.codexConfig?.model ?? "")
        var codexState = CodexFormState()
        if let xc = provider.codexConfig {
            codexState.wireApi = xc.wireApi ?? "responses"
            codexState.reasoningEffort = xc.reasoningEffort ?? "medium"
        }
        _codex = State(initialValue: codexState)

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
                    .fill(accentTint.opacity(OpacityScale.subtle))
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

                        UnifiedBadge(text: provider.appType.displayName, tint: accentTint)
                    }

                    HStack(spacing: 8) {
                        UnifiedBadge(
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
                .fill(accentTint.opacity(OpacityScale.subtle))
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
                        accentTint.opacity(OpacityScale.subtle),
                        Color.clear
                    ],
                    startPoint: .topLeading,
                    endPoint: .bottomTrailing
                )
            )
            .overlay(alignment: .top) {
                Rectangle()
                    .fill(accentTint.opacity(OpacityScale.muted))
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
                        selection: $claude.apiFormat,
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
                        selection: $claude.apiKeyField,
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
                    withAnimation(AnimationPreset.quick) { claude.showAdvanced.toggle() }
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
                            .rotationEffect(.degrees(claude.showAdvanced ? 90 : 0))
                    }
                }
                .buttonStyle(.plain)

                if claude.showAdvanced {
                    VStack(alignment: .leading, spacing: 12) {
                        HStack(alignment: .top, spacing: 12) {
                            editConfigField(label: L10n.tr("providers.field.haiku_default_model")) {
                                TextField(L10n.tr("providers.placeholder.optional_override"), text: $claude.haikuModel)
                                    .frostedRoundedInput(cornerRadius: 10)
                            }
                            .frame(maxWidth: .infinity, alignment: .leading)

                            editConfigField(label: L10n.tr("providers.field.sonnet_default_model")) {
                                TextField(L10n.tr("providers.placeholder.optional_override"), text: $claude.sonnetModel)
                                    .frostedRoundedInput(cornerRadius: 10)
                            }
                            .frame(maxWidth: .infinity, alignment: .leading)
                        }
                        HStack(alignment: .top, spacing: 12) {
                            editConfigField(label: L10n.tr("providers.field.opus_default_model")) {
                                TextField(L10n.tr("providers.placeholder.optional_override"), text: $claude.opusModel)
                                    .frostedRoundedInput(cornerRadius: 10)
                            }
                            .frame(maxWidth: .infinity, alignment: .leading)

                            editConfigField(label: L10n.tr("providers.field.max_output_tokens")) {
                                TextField(L10n.tr("providers.placeholder.use_default"), text: $claude.maxOutputTokens)
                                    .frostedRoundedInput(cornerRadius: 10)
                            }
                            .frame(maxWidth: .infinity, alignment: .leading)
                        }
                        editConfigField(label: L10n.tr("providers.field.timeout_ms")) {
                            TextField(L10n.tr("providers.placeholder.use_default"), text: $claude.apiTimeoutMs)
                                .frostedRoundedInput(cornerRadius: 10)
                        }
                        Toggle(L10n.tr("providers.toggle.disable_nonessential"), isOn: $claude.disableNonessential)
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
                            selection: $codex.wireApi,
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
                            selection: $codex.reasoningEffort,
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
                withAnimation(AnimationPreset.quick) { showConfigPreview.toggle() }
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
                        hideAttribution: $claude.hideAttribution,
                        alwaysThinking: $claude.alwaysThinking,
                        enableTeammates: $claude.enableTeammates,
                        applyCommonConfig: $claude.applyCommonConfig,
                        showCommonConfigEditor: $claude.showCommonConfigEditor,
                        accent: accentTint
                    )

                    if claude.applyCommonConfig && claude.showCommonConfigEditor {
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
        normalizedJSONObjectString(claude.commonConfigJSON) ?? "{}"
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
                                        .fill(selection.wrappedValue == modelID ? accentTint.opacity(OpacityScale.muted) : Color.primary.opacity(OpacityScale.faint))
                                        .overlay(
                                            RoundedRectangle(cornerRadius: 8, style: .continuous)
                                                .strokeBorder(selection.wrappedValue == modelID ? accentTint.opacity(OpacityScale.accent) : Color.primary.opacity(OpacityScale.subtle), lineWidth: 1)
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
            claude.apiKeyField = .authToken
            claudeApiKey = token
        } else if let key = previewString(env["ANTHROPIC_API_KEY"]) {
            claude.apiKeyField = .apiKey
            claudeApiKey = key
        }

        if let value = previewString(env["ANTHROPIC_BASE_URL"]) { claudeBaseUrl = value }
        claudeModel = previewString(env["ANTHROPIC_MODEL"]) ?? ""
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

    private func applyClaudeCommonConfigPreview(_ text: String) throws {
        let payload = try parsePreviewJSONObject(text)
        claude.applyCommonConfig = !payload.isEmpty
        claude.commonConfigJSON = payload.isEmpty ? "" : prettyJSONString(payload)
    }

    private func applyCodexAuthPreview(_ text: String) throws {
        let payload = try parsePreviewJSONObject(text)
        if let value = previewString(payload["OPENAI_API_KEY"]) { codexApiKey = value }
        if let value = previewString(payload["OPENAI_BASE_URL"]) { codexBaseUrl = value }
    }

    private func applyCodexTomlPreview(_ text: String) throws {
        let payload = try parsePreviewTOML(text)
        if let value = payload["model"] { codexModel = value }
        if let value = payload["wire_api"] { codex.wireApi = value }
        if let value = payload["base_url"] { codexBaseUrl = value }
        if let value = payload["reasoning_effort"] { codex.reasoningEffort = value }
    }

    private func applyGeminiPreview(_ text: String) throws {
        let payload = try parsePreviewDotEnv(text)
        if let value = payload["GEMINI_API_KEY"] { geminiApiKey = value }
        if let value = payload["GOOGLE_GEMINI_BASE_URL"] { geminiBaseUrl = value }
        if let value = payload["GEMINI_MODEL"] { geminiModel = value }
    }

    private func buildClaudePreview() -> String {
        var settings = claude.applyCommonConfig ? (parsedJSONObjectString(claude.commonConfigJSON) ?? [:]) : [:]
        var env: [String: Any] = [
            claude.apiKeyField.rawValue: claudeApiKey.trimmedNonEmpty ?? "<API_KEY>"
        ]
        env["ANTHROPIC_BASE_URL"] = resolvedBaseURL
        if let model = claudeModel.trimmedNonEmpty {
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
        lines.append("wire_api = \(tomlQuoted(codex.wireApi))")
        lines.append("base_url = \(tomlQuoted(resolvedBaseURL))")
        lines.append("reasoning_effort = \(tomlQuoted(codex.reasoningEffort))")
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
                    claudeApiFormat: provider.appType == .claude ? claude.apiFormat : nil
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
            updated.claudeConfig?.haikuModel = claude.haikuModel.isEmpty ? nil : claude.haikuModel
            updated.claudeConfig?.sonnetModel = claude.sonnetModel.isEmpty ? nil : claude.sonnetModel
            updated.claudeConfig?.opusModel = claude.opusModel.isEmpty ? nil : claude.opusModel
            updated.claudeConfig?.maxOutputTokens = Int(claude.maxOutputTokens)
            updated.claudeConfig?.apiTimeoutMs = Int(claude.apiTimeoutMs)
            updated.claudeConfig?.apiFormat = claude.apiFormat
            updated.claudeConfig?.apiKeyField = claude.apiKeyField
            updated.claudeConfig?.disableNonessentialTraffic = claude.disableNonessential
            updated.claudeConfig?.hideAttribution = claude.hideAttribution
            updated.claudeConfig?.alwaysThinkingEnabled = claude.alwaysThinking
            updated.claudeConfig?.enableTeammates = claude.enableTeammates
            updated.claudeConfig?.applyCommonConfig = claude.applyCommonConfig
            updated.claudeConfig?.commonConfigJSON = claude.applyCommonConfig ? normalizedClaudeCommonConfigJSON : nil
        case .codex:
            updated.codexConfig?.apiKey = codexApiKey
            updated.codexConfig?.baseUrl = codexBaseUrl.isEmpty ? nil : codexBaseUrl
            updated.codexConfig?.model = codexModel.isEmpty ? nil : codexModel
            updated.codexConfig?.wireApi = codex.wireApi
            updated.codexConfig?.reasoningEffort = codex.reasoningEffort
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
        @ViewBuilder content: @escaping () -> Content
    ) -> some View {
        FormSectionCard(
            title: title,
            subtitle: subtitle,
            icon: icon,
            accent: accentTint,
            emphasis: emphasis,
            content: content
        )
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
