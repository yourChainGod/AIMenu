import SwiftUI
import AppKit

// MARK: - Add Provider Sheet

enum ModelFetchState {
    case idle
    case fetching
    case success(String)
    case failure(String)

    var isFetching: Bool { if case .fetching = self { return true }; return false }
    var statusMessage: String? {
        switch self {
        case .idle: return nil
        case .fetching: return L10n.tr("providers.models.fetching")
        case .success(let msg): return msg
        case .failure(let msg): return msg
        }
    }
    var isFailed: Bool { if case .failure = self { return true }; return false }
}

struct AddProviderSheet: View {
    let appType: ProviderAppType
    let initialPreset: ProviderPreset
    let onAdd: (ProviderDraft) -> Void
    let onCancel: () -> Void

    @State private var selectedPreset: ProviderPreset?
    @State private var searchText = ""
    @State private var step: SheetStep = .selectPreset
    @State private var didBootstrap = false

    @State private var providerName = ""
    @State private var websiteUrl = ""
    @State private var providerNotes = ""
    @State private var apiKey = ""
    @State private var baseUrl = ""
    @State private var model = ""
    @State private var modelFetchState: ModelFetchState = .idle
    @State private var fetchedModels: [String] = []
    @State private var showAllPresets = false
    @State private var showConfigPreview = true
    @State private var showProxyConfig = false
    @State private var showBillingConfig = false

    @State private var proxyEnabled = false
    @State private var proxyHost = ""
    @State private var proxyPort = ""
    @State private var proxyUsername = ""
    @State private var proxyPassword = "" // sensitive — do not log

    @State private var billingInputPrice = ""
    @State private var billingOutputPrice = ""
    @State private var billingNotes = ""

    @State private var claudeApiFormat: ClaudeApiFormat = .anthropic
    @State private var claudeApiKeyField: ClaudeApiKeyField = .authToken
    @State private var claudeHaikuModel = ""
    @State private var claudeSonnetModel = ""
    @State private var claudeOpusModel = ""
    @State private var claudeMaxOutputTokens = ""
    @State private var claudeApiTimeoutMs = ""
    @State private var claudeDisableNonessential = false
    @State private var claudeHideAttribution = false
    @State private var claudeAlwaysThinking = false
    @State private var claudeEnableTeammates = false
    @State private var claudeApplyCommonConfig = false
    @State private var claudeCommonConfigJSON = ""
    @State private var showClaudeAdvanced = false
    @State private var showClaudeCommonConfigEditor = false

    @State private var wireApi = "responses"
    @State private var reasoningEffort = "medium"

    enum SheetStep { case selectPreset, configure }

    private var accentTint: Color { appType.formAccent }

    private var allPresets: [ProviderPreset] {
        ProviderPresets.presets(for: appType)
    }

    private var featuredPresetIDs: Set<String> {
        switch appType {
        case .claude:
            return [
                "claude-official",
                "claude-deepseek",
                "claude-zhipu",
                "claude-kimi",
                "claude-bailian",
                "claude-siliconflow",
                "claude-openrouter",
                "claude-custom"
            ]
        case .codex:
            return [
                "codex-official",
                "codex-azure",
                "codex-openrouter",
                "codex-dmxapi",
                "codex-custom"
            ]
        case .gemini:
            return [
                "gemini-official",
                "gemini-openrouter",
                "gemini-custom"
            ]
        }
    }

    private var filteredPresets: [ProviderPreset] {
        guard !searchText.isEmpty else { return allPresets }
        return allPresets.filter { $0.name.localizedCaseInsensitiveContains(searchText) }
    }

    private var presets: [ProviderPreset] {
        guard searchText.isEmpty, !showAllPresets else { return filteredPresets }
        let featured = filteredPresets.filter { featuredPresetIDs.contains($0.id) }
        return featured.isEmpty ? filteredPresets : featured
    }

    private var hiddenPresetCount: Int {
        max(filteredPresets.count - presets.count, 0)
    }

    private var featuredPresetCount: Int {
        filteredPresets.filter { featuredPresetIDs.contains($0.id) }.count
    }

    private var canAdd: Bool {
        guard selectedPreset != nil else { return false }
        return !apiKey.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
    }

    private var canFetchModels: Bool {
        !apiKey.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
    }

    private var resolvedBaseURL: String {
        if let baseUrl = baseUrl.trimmedNonEmpty { return baseUrl }
        if let presetBase = selectedPreset?.baseUrl?.trimmedNonEmpty { return presetBase }
        return appType.defaultBaseURL
    }

    var body: some View {
        Group {
            switch step {
            case .selectPreset:
                presetSelectionView
            case .configure:
                configureView
            }
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
        .onAppear {
            guard !didBootstrap else { return }
            didBootstrap = true
            applyPreset(initialPreset)
        }
    }

    private var presetSelectionView: some View {
        VStack(alignment: .leading, spacing: 0) {
            sheetHeader
                .padding(.horizontal, 16)
                .padding(.top, 10)
                .padding(.bottom, 6)

            Rectangle()
                .fill(accentTint.opacity(0.06))
                .frame(height: 1)

            presetPickerStep
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
    }

    private var configureView: some View {
        VStack(alignment: .leading, spacing: 0) {
            sheetHeader
                .padding(.horizontal, 16)
                .padding(.top, 10)
                .padding(.bottom, 6)

            Rectangle()
                .fill(accentTint.opacity(0.06))
                .frame(height: 1)

            configureStep
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
    }

    private var sheetHeader: some View {
        HStack(alignment: .center, spacing: 10) {
            RoundedRectangle(cornerRadius: 10, style: .continuous)
                .fill(accentTint.opacity(0.07))
                .overlay {
                    Image(systemName: step == .selectPreset ? "square.grid.2x2.fill" : (selectedPreset?.icon ?? appType.iconName))
                        .font(.system(size: 13, weight: .semibold))
                        .foregroundStyle(accentTint)
                }
                .frame(width: 30, height: 30)

            VStack(alignment: .leading, spacing: 3) {
                HStack(spacing: 7) {
                    Text(step == .selectPreset ? L10n.tr("providers.sheet.add.title") : (selectedPreset?.name ?? L10n.tr("providers.sheet.details_title")))
                        .font(.system(size: 18, weight: .semibold))
                        .lineLimit(1)

                    ProviderConfigBadge(
                        text: step == .selectPreset ? L10n.tr("providers.sheet.badge.preset_selection") : appType.displayName,
                        tint: accentTint
                    )
                }

                HStack(spacing: 8) {
                    ProviderConfigBadge(
                        text: step == .selectPreset
                            ? L10n.tr("providers.sheet.badge.candidates_format", String(filteredPresets.count))
                            : L10n.tr("providers.sheet.badge.write_target"),
                        tint: step == .selectPreset ? .secondary : accentTint
                    )

                    HStack(spacing: 5) {
                        Image(systemName: step == .selectPreset ? "sparkles" : "arrow.down.doc.fill")
                            .font(.caption2.weight(.semibold))
                        Text(step == .selectPreset ? appType.displayName : appType.liveConfigPathsText)
                            .font(.caption2)
                            .lineLimit(1)
                            .truncationMode(.middle)
                    }
                    .foregroundStyle(.secondary)
                }
            }

            Spacer(minLength: 0)

            HStack(spacing: 8) {
                if step == .configure {
                    Button(L10n.tr("providers.action.back_to_presets")) {
                        withAnimation(.easeInOut(duration: 0.2)) {
                            step = .selectPreset
                        }
                    }
                    .aimenuActionButtonStyle(tint: accentTint, density: .compact)
                }

                CloseGlassButton { handleClose() }
            }
        }
    }

    private func handleClose() {
        if step == .configure {
            withAnimation(.easeInOut(duration: 0.2)) {
                step = .selectPreset
            }
            return
        }
        onCancel()
    }

    private var presetPickerStep: some View {
        VStack(spacing: 0) {
            VStack(alignment: .leading, spacing: 12) {
                HStack(spacing: 8) {
                    Image(systemName: "magnifyingglass")
                        .foregroundStyle(accentTint)
                        .font(.subheadline.weight(.semibold))
                    TextField(L10n.tr("providers.search.providers_placeholder"), text: $searchText)
                        .textFieldStyle(.plain)
                        .font(.subheadline)
                    if !searchText.isEmpty {
                        Button { searchText = "" } label: {
                            Image(systemName: "xmark.circle.fill")
                                .foregroundStyle(.tertiary)
                        }
                        .buttonStyle(.plain)
                    }
                }
                .padding(.horizontal, 12)
                .padding(.vertical, 10)
                .background(
                    RoundedRectangle(cornerRadius: 12, style: .continuous)
                        .fill(
                            LinearGradient(
                                colors: [
                                    accentTint.opacity(0.12),
                                    Color.primary.opacity(0.03)
                                ],
                                startPoint: .topLeading,
                                endPoint: .bottomTrailing
                            )
                        )
                        .overlay(
                            RoundedRectangle(cornerRadius: 12, style: .continuous)
                                .strokeBorder(accentTint.opacity(0.22), lineWidth: 1)
                        )
                )

                HStack(spacing: 8) {
                    if searchText.isEmpty {
                        presetScopeButton(
                            title: L10n.tr("providers.scope.featured"),
                            count: featuredPresetCount,
                            isActive: !showAllPresets
                        ) {
                            withAnimation(.easeInOut(duration: 0.2)) {
                                showAllPresets = false
                            }
                        }

                        if hiddenPresetCount > 0 {
                            presetScopeButton(
                                title: L10n.tr("providers.scope.all"),
                                count: filteredPresets.count,
                                isActive: showAllPresets
                            ) {
                                withAnimation(.easeInOut(duration: 0.2)) {
                                    showAllPresets = true
                                }
                            }
                        }
                    } else {
                        presetMetaBadge(
                            icon: "line.3.horizontal.decrease.circle",
                            text: L10n.tr("providers.search.results_format", String(filteredPresets.count)),
                            tint: accentTint
                        )
                    }

                    Spacer(minLength: 0)

                    if let selectedPreset {
                        presetMetaBadge(
                            icon: "checkmark.circle.fill",
                            text: selectedPreset.name,
                            tint: accentTint
                        )
                    } else {
                        presetMetaBadge(
                            icon: "hand.tap",
                            text: L10n.tr("providers.sheet.tap_to_configure"),
                            tint: .secondary
                        )
                    }
                }
            }
            .padding(.horizontal, 18)
            .padding(.top, 10)
            .padding(.bottom, 10)

            ScrollView {
                LazyVGrid(
                    columns: [GridItem(.adaptive(minimum: 150, maximum: 190), spacing: 10)],
                    spacing: 10
                ) {
                    ForEach(presets) { preset in
                        Button {
                            applyPreset(preset)
                            withAnimation(.easeInOut(duration: 0.2)) {
                                step = .configure
                            }
                        } label: {
                            PresetRow(
                                preset: preset,
                                isSelected: selectedPreset?.id == preset.id,
                                accent: accentTint
                            )
                        }
                        .buttonStyle(.plain)
                    }
                }
                .padding(.horizontal, 16)
                .padding(.top, 12)
                .padding(.bottom, 14)
            }
            .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .top)

            HStack(spacing: 8) {
                HStack(spacing: 6) {
                    Image(systemName: showAllPresets ? "square.grid.2x2" : "sparkles")
                        .font(.caption2.weight(.semibold))
                    Text(showAllPresets ? L10n.tr("providers.sheet.showing_all") : L10n.tr("providers.sheet.showing_featured"))
                        .font(.caption)
                }
                .foregroundStyle(.secondary)

                Spacer(minLength: 0)

                Text(L10n.tr("providers.sheet.current_total_format", String(presets.count), String(filteredPresets.count)))
                    .font(.caption)
                    .foregroundStyle(.tertiary)

                Button(L10n.tr("common.cancel")) { onCancel() }
                    .aimenuActionButtonStyle()
            }
            .padding(.horizontal, 18)
            .padding(.vertical, 8)
            .background(
                LinearGradient(
                    colors: [
                        accentTint.opacity(0.045),
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
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .top)
    }

    private var configureStep: some View {
        VStack(spacing: 0) {
            ScrollView {
                VStack(alignment: .leading, spacing: 12) {
                    configSectionCard(title: L10n.tr("providers.section.basic.title"), subtitle: L10n.tr("providers.section.basic.subtitle"), icon: "square.text.square") {
                        HStack(alignment: .top, spacing: 12) {
                            configField(label: L10n.tr("providers.field.provider_name_required"), hint: nil, hintLabel: nil) {
                                TextField(selectedPreset?.name ?? L10n.tr("common.name"), text: $providerName)
                                    .frostedRoundedInput(cornerRadius: 10)
                            }
                            .frame(maxWidth: .infinity, alignment: .leading)

                            configField(
                                label: L10n.tr("providers.field.website_url"),
                                hint: selectedPreset?.websiteUrl,
                                hintLabel: selectedPreset?.websiteUrl != nil ? L10n.tr("providers.action.visit") : nil
                            ) {
                                TextField(L10n.tr("providers.placeholder.website_optional"), text: $websiteUrl)
                                    .frostedRoundedInput(cornerRadius: 10)
                            }
                            .frame(maxWidth: .infinity, alignment: .leading)
                        }

                        configField(label: L10n.tr("providers.field.notes"), hint: nil, hintLabel: nil) {
                            TextField(L10n.tr("providers.field.notes_placeholder"), text: $providerNotes)
                                .frostedRoundedInput(cornerRadius: 10)
                        }
                    }

                    configSectionCard(title: L10n.tr("providers.section.credentials.title"), subtitle: L10n.tr("providers.section.credentials.subtitle"), icon: "key.fill") {
                        configField(
                            label: L10n.tr("providers.field.api_key_required"),
                            hint: selectedPreset?.apiKeyUrl,
                            hintLabel: L10n.tr("providers.action.get_key")
                        ) {
                            SecureField(L10n.tr("providers.field.api_key_placeholder"), text: $apiKey)
                                .frostedRoundedInput(cornerRadius: 10)
                        }
                        configField(label: L10n.tr("providers.field.base_url"), hint: nil, hintLabel: nil) {
                            TextField(selectedPreset?.baseUrl ?? appType.defaultBaseURL, text: $baseUrl)
                                .frostedRoundedInput(cornerRadius: 10)
                        }
                        HStack(spacing: 8) {
                            ProviderConfigBadge(text: L10n.tr("providers.badge.write"), tint: accentTint)
                            Text(appType.liveConfigPathsText)
                                .font(.caption)
                                .foregroundStyle(.secondary)
                        }
                    }

                    appSpecificSection

                    configPreviewSection

                    proxySection

                    billingSection
                }
                .padding(.horizontal, 18)
                .padding(.vertical, 10)
            }
            .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .top)

            HStack(spacing: 10) {
                Button(L10n.tr("common.cancel")) { onCancel() }
                    .aimenuActionButtonStyle()
                Button(L10n.tr("common.add")) {
                    guard let preset = selectedPreset else { return }
                    let extra: [String: String] = [
                        "wireApi": wireApi,
                        "reasoningEffort": reasoningEffort,
                        "claudeApiFormat": claudeApiFormat.rawValue,
                        "claudeApiKeyField": claudeApiKeyField.rawValue,
                        "claudeHaikuModel": claudeHaikuModel,
                        "claudeSonnetModel": claudeSonnetModel,
                        "claudeOpusModel": claudeOpusModel,
                        "claudeMaxOutputTokens": claudeMaxOutputTokens,
                        "claudeApiTimeoutMs": claudeApiTimeoutMs,
                        "claudeDisableNonessential": claudeDisableNonessential ? "true" : "false",
                        "claudeHideAttribution": claudeHideAttribution ? "true" : "false",
                        "claudeAlwaysThinking": claudeAlwaysThinking ? "true" : "false",
                        "claudeEnableTeammates": claudeEnableTeammates ? "true" : "false",
                        "claudeApplyCommonConfig": claudeApplyCommonConfig ? "true" : "false",
                        "claudeCommonConfigJSON": claudeApplyCommonConfig ? normalizedClaudeCommonConfigJSON : ""
                    ]
                    let draft = ProviderDraft(
                        preset: preset,
                        customName: providerName,
                        websiteUrl: websiteUrl,
                        apiKey: apiKey,
                        baseUrl: baseUrl,
                        model: model,
                        notes: providerNotes,
                        proxyConfig: ProviderProxyConfig(
                            enabled: proxyEnabled,
                            host: proxyHost,
                            port: proxyPort,
                            username: proxyUsername,
                            password: proxyPassword
                        ),
                        billingConfig: ProviderBillingConfig(
                            inputPricePerMillion: billingInputPrice,
                            outputPricePerMillion: billingOutputPrice,
                            currency: "USD",
                            notes: billingNotes
                        ),
                        extraConfig: extra
                    )
                    onAdd(draft)
                }
                .aimenuActionButtonStyle(prominent: true, tint: accentTint)
                .disabled(!canAdd)
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
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .top)
    }

    private func presetScopeButton(
        title: String,
        count: Int,
        isActive: Bool,
        action: @escaping () -> Void
    ) -> some View {
        Button(action: action) {
            HStack(spacing: 6) {
                Text(title)
                Text("\(count)")
                    .font(.caption2.weight(.bold))
                    .padding(.horizontal, 5)
                    .padding(.vertical, 2)
                    .background((isActive ? accentTint : Color.primary).opacity(isActive ? 0.15 : 0.08), in: Capsule())
            }
            .lineLimit(1)
        }
        .aimenuActionButtonStyle(
            prominent: isActive,
            tint: isActive ? accentTint : nil,
            density: .compact
        )
    }

    private func presetMetaBadge(icon: String, text: String, tint: Color) -> some View {
        HStack(spacing: 6) {
            Image(systemName: icon)
                .font(.caption2.weight(.semibold))
            Text(text)
                .font(.caption.weight(.medium))
                .lineLimit(1)
        }
        .foregroundStyle(tint == .secondary ? .secondary : tint)
        .padding(.horizontal, 9)
        .padding(.vertical, 6)
        .background(
            Capsule()
                .fill((tint == .secondary ? Color.primary : tint).opacity(0.08))
        )
    }

    @ViewBuilder
    private var appSpecificSection: some View {
        switch appType {
        case .claude:
            claudeSection
        case .codex:
            codexSection
        case .gemini:
            geminiSection
        }
    }

    private var claudeSection: some View {
        VStack(alignment: .leading, spacing: 12) {
            configSectionCard(title: L10n.tr("providers.section.claude.title"), subtitle: L10n.tr("providers.section.claude.subtitle"), icon: "sparkles.rectangle.stack.fill") {
                configField(label: L10n.tr("providers.field.api_format"), hint: nil, hintLabel: nil) {
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
                configField(label: L10n.tr("providers.field.auth_field"), hint: nil, hintLabel: nil) {
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
                    placeholder: selectedPreset?.defaultModel ?? L10n.tr("providers.placeholder.use_default"),
                    text: $model,
                    isFetching: modelFetchState.isFetching,
                    canFetch: canFetchModels,
                    accent: accentTint,
                    onFetch: fetchModels
                )
                modelFetchStatusView
                fetchedModelRow(selection: $model)
            }

            configSectionCard(title: L10n.tr("providers.section.advanced.title"), subtitle: L10n.tr("providers.section.advanced.subtitle"), icon: "dial.medium.fill") {
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
                            configField(label: L10n.tr("providers.field.haiku_default_model"), hint: nil, hintLabel: nil) {
                                TextField(L10n.tr("providers.placeholder.optional_override"), text: $claudeHaikuModel)
                                    .frostedRoundedInput(cornerRadius: 10)
                            }
                            .frame(maxWidth: .infinity, alignment: .leading)

                            configField(label: L10n.tr("providers.field.sonnet_default_model"), hint: nil, hintLabel: nil) {
                                TextField(L10n.tr("providers.placeholder.optional_override"), text: $claudeSonnetModel)
                                    .frostedRoundedInput(cornerRadius: 10)
                            }
                            .frame(maxWidth: .infinity, alignment: .leading)
                        }
                        HStack(alignment: .top, spacing: 12) {
                            configField(label: L10n.tr("providers.field.opus_default_model"), hint: nil, hintLabel: nil) {
                                TextField(L10n.tr("providers.placeholder.optional_override"), text: $claudeOpusModel)
                                    .frostedRoundedInput(cornerRadius: 10)
                            }
                            .frame(maxWidth: .infinity, alignment: .leading)

                            configField(label: L10n.tr("providers.field.max_output_tokens"), hint: nil, hintLabel: nil) {
                                TextField(L10n.tr("providers.placeholder.use_default"), text: $claudeMaxOutputTokens)
                                    .frostedRoundedInput(cornerRadius: 10)
                            }
                            .frame(maxWidth: .infinity, alignment: .leading)
                        }
                        configField(label: L10n.tr("providers.field.timeout_ms"), hint: nil, hintLabel: nil) {
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

    private var codexSection: some View {
        VStack(alignment: .leading, spacing: 12) {
            configSectionCard(title: L10n.tr("providers.section.codex_model.title"), subtitle: L10n.tr("providers.section.codex_model.subtitle"), icon: "chevron.left.forwardslash.chevron.right") {
                ProviderModelInputRow(
                    title: L10n.tr("providers.field.model_name"),
                    placeholder: selectedPreset?.defaultModel ?? L10n.tr("providers.placeholder.codex_model_example"),
                    text: $model,
                    isFetching: modelFetchState.isFetching,
                    canFetch: canFetchModels,
                    accent: accentTint,
                    onFetch: fetchModels
                )
                modelFetchStatusView
                fetchedModelRow(selection: $model)
            }

            configSectionCard(title: L10n.tr("providers.section.codex_runtime.title"), subtitle: L10n.tr("providers.section.codex_runtime.subtitle"), icon: "slider.horizontal.3") {
                HStack(alignment: .top, spacing: 12) {
                    configField(label: L10n.tr("providers.field.wire_api"), hint: nil, hintLabel: nil) {
                        ProviderSegmentedControl(
                            selection: $wireApi,
                            options: [
                                .init(title: "responses", value: "responses"),
                                .init(title: "chat", value: "chat")
                            ],
                            accent: accentTint
                        )
                    }
                    .frame(maxWidth: .infinity, alignment: .leading)

                    configField(label: L10n.tr("providers.field.reasoning_effort"), hint: nil, hintLabel: nil) {
                        ProviderSegmentedControl(
                            selection: $reasoningEffort,
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

    private var geminiSection: some View {
        configSectionCard(title: L10n.tr("providers.section.gemini.title"), subtitle: L10n.tr("providers.section.gemini.subtitle"), icon: "diamond.fill") {
            ProviderModelInputRow(
                title: L10n.tr("providers.field.model_name"),
                placeholder: selectedPreset?.defaultModel ?? L10n.tr("providers.placeholder.default_model"),
                text: $model,
                isFetching: modelFetchState.isFetching,
                canFetch: canFetchModels,
                accent: accentTint,
                onFetch: fetchModels
            )
            modelFetchStatusView
            fetchedModelRow(selection: $model)
        }
    }

    private var configPreviewSection: some View {
        configSectionCard(title: L10n.tr("providers.preview.section_title"), subtitle: previewSubtitle, icon: "doc.text.magnifyingglass") {
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
                if appType == .claude {
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

    private var proxySection: some View {
        configSectionCard(title: L10n.tr("providers.section.proxy.title"), subtitle: L10n.tr("providers.section.proxy.subtitle"), icon: "point.3.filled.connected.trianglepath.dotted") {
            Button {
                withAnimation(.easeInOut(duration: 0.2)) { showProxyConfig.toggle() }
            } label: {
                HStack {
                    Text(showProxyConfig ? L10n.tr("providers.action.collapse_proxy") : L10n.tr("providers.action.expand_proxy"))
                        .font(.subheadline.weight(.semibold))
                        .foregroundStyle(.primary)
                    Spacer(minLength: 0)
                    if proxyEnabled {
                        ProviderConfigBadge(text: L10n.tr("providers.status.enabled"), tint: .orange)
                    }
                    Image(systemName: "chevron.right")
                        .font(.caption.weight(.semibold))
                        .foregroundStyle(.tertiary)
                        .rotationEffect(.degrees(showProxyConfig ? 90 : 0))
                }
            }
            .buttonStyle(.plain)

            if showProxyConfig {
                VStack(alignment: .leading, spacing: 12) {
                    Toggle(L10n.tr("providers.toggle.enable_proxy"), isOn: $proxyEnabled)
                        .toggleStyle(.checkbox)
                        .font(.subheadline)
                    if proxyEnabled {
                        HStack(alignment: .top, spacing: 12) {
                            configField(label: L10n.tr("providers.field.proxy_host"), hint: nil, hintLabel: nil) {
                                TextField("127.0.0.1", text: $proxyHost)
                                    .frostedRoundedInput(cornerRadius: 10)
                            }
                            .frame(maxWidth: .infinity, alignment: .leading)

                            configField(label: L10n.tr("providers.field.port"), hint: nil, hintLabel: nil) {
                                TextField("7890", text: $proxyPort)
                                    .frostedRoundedInput(cornerRadius: 10)
                            }
                            .frame(maxWidth: .infinity, alignment: .leading)
                        }
                        HStack(alignment: .top, spacing: 12) {
                            configField(label: L10n.tr("providers.field.username_optional"), hint: nil, hintLabel: nil) {
                                TextField(L10n.tr("providers.placeholder.leave_blank_skip"), text: $proxyUsername)
                                    .frostedRoundedInput(cornerRadius: 10)
                            }
                            .frame(maxWidth: .infinity, alignment: .leading)

                            configField(label: L10n.tr("providers.field.password_optional"), hint: nil, hintLabel: nil) {
                                SecureField(L10n.tr("providers.placeholder.leave_blank_skip"), text: $proxyPassword)
                                    .frostedRoundedInput(cornerRadius: 10)
                            }
                            .frame(maxWidth: .infinity, alignment: .leading)
                        }
                    }
                }
                .padding(.top, 2)
            }
        }
    }

    private var billingSection: some View {
        configSectionCard(title: L10n.tr("providers.section.billing.title"), subtitle: L10n.tr("providers.section.billing.subtitle"), icon: "banknote.fill") {
            Button {
                withAnimation(.easeInOut(duration: 0.2)) { showBillingConfig.toggle() }
            } label: {
                HStack {
                    Text(showBillingConfig ? L10n.tr("providers.action.collapse_billing") : L10n.tr("providers.action.expand_billing"))
                        .font(.subheadline.weight(.semibold))
                        .foregroundStyle(.primary)
                    Spacer(minLength: 0)
                    Image(systemName: "chevron.right")
                        .font(.caption.weight(.semibold))
                        .foregroundStyle(.tertiary)
                        .rotationEffect(.degrees(showBillingConfig ? 90 : 0))
                }
            }
            .buttonStyle(.plain)

            if showBillingConfig {
                VStack(alignment: .leading, spacing: 12) {
                    HStack(alignment: .top, spacing: 12) {
                        configField(label: L10n.tr("providers.field.billing_input_price"), hint: nil, hintLabel: nil) {
                            TextField(L10n.tr("providers.placeholder.price_input_example"), text: $billingInputPrice)
                                .frostedRoundedInput(cornerRadius: 10)
                        }
                        .frame(maxWidth: .infinity, alignment: .leading)

                        configField(label: L10n.tr("providers.field.billing_output_price"), hint: nil, hintLabel: nil) {
                            TextField(L10n.tr("providers.placeholder.price_output_example"), text: $billingOutputPrice)
                                .frostedRoundedInput(cornerRadius: 10)
                        }
                        .frame(maxWidth: .infinity, alignment: .leading)
                    }
                    configField(label: L10n.tr("providers.field.notes"), hint: nil, hintLabel: nil) {
                        TextField(L10n.tr("providers.field.notes_placeholder"), text: $billingNotes)
                            .frostedRoundedInput(cornerRadius: 10)
                    }
                }
                .padding(.top, 2)
            }
        }
    }

    private var previewSubtitle: String {
        switch appType {
        case .claude:
            return L10n.tr("providers.preview.subtitle.claude")
        case .codex:
            return L10n.tr("providers.preview.subtitle.codex")
        case .gemini:
            return L10n.tr("providers.preview.subtitle.gemini")
        }
    }

    private var previewBlocks: [ProviderPreviewBlockData] {
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

    private var normalizedClaudeCommonConfigJSON: String {
        normalizedJSONObjectString(claudeCommonConfigJSON) ?? "{}"
    }

    @ViewBuilder
    private var modelFetchStatusView: some View {
        if let msg = modelFetchState.statusMessage {
            Text(msg)
                .font(.caption)
                .foregroundStyle(modelFetchState.isFailed ? .red : .secondary)
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
            apiKey = token
        } else if let key = previewString(env["ANTHROPIC_API_KEY"]) {
            claudeApiKeyField = .apiKey
            apiKey = key
        }

        if let value = previewString(env["ANTHROPIC_BASE_URL"]) { baseUrl = value }
        if let value = previewString(env["ANTHROPIC_MODEL"]) { model = value }
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
        if let value = previewString(payload["OPENAI_API_KEY"]) { apiKey = value }
        if let value = previewString(payload["OPENAI_BASE_URL"]) { baseUrl = value }
    }

    private func applyCodexTomlPreview(_ text: String) throws {
        let payload = try parsePreviewTOML(text)
        if let value = payload["model"] { model = value }
        if let value = payload["wire_api"] { wireApi = value }
        if let value = payload["base_url"] { baseUrl = value }
        if let value = payload["reasoning_effort"] { reasoningEffort = value }
    }

    private func applyGeminiPreview(_ text: String) throws {
        let payload = try parsePreviewDotEnv(text)
        if let value = payload["GEMINI_API_KEY"] { apiKey = value }
        if let value = payload["GOOGLE_GEMINI_BASE_URL"] { baseUrl = value }
        if let value = payload["GEMINI_MODEL"] { model = value }
    }

    private func applyPreset(_ preset: ProviderPreset) {
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
        billingInputPrice = ""
        billingOutputPrice = ""
        billingNotes = ""
        claudeApiFormat = preset.apiFormat ?? .anthropic
        claudeApiKeyField = preset.apiKeyField ?? .authToken
        claudeHaikuModel = ""
        claudeSonnetModel = ""
        claudeOpusModel = ""
        claudeMaxOutputTokens = ""
        claudeApiTimeoutMs = ""
        claudeDisableNonessential = false
        claudeHideAttribution = false
        claudeAlwaysThinking = false
        claudeEnableTeammates = false
        claudeApplyCommonConfig = false
        claudeCommonConfigJSON = ""
        showClaudeCommonConfigEditor = false
        wireApi = preset.wireApi ?? "responses"
        reasoningEffort = "medium"
        fetchedModels = []
        modelFetchState = .idle
    }

    private func buildClaudePreview() -> String {
        var settings = claudeApplyCommonConfig ? (parsedJSONObjectString(claudeCommonConfigJSON) ?? [:]) : [:]
        var env: [String: Any] = [
            claudeApiKeyField.rawValue: apiKey.trimmedNonEmpty ?? "<API_KEY>"
        ]
        env["ANTHROPIC_BASE_URL"] = resolvedBaseURL
        if let model = model.trimmedNonEmpty {
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
        var auth: [String: Any] = ["OPENAI_API_KEY": apiKey.trimmedNonEmpty ?? "<API_KEY>"]
        auth["OPENAI_BASE_URL"] = resolvedBaseURL
        return prettyJSONString(auth)
    }

    private func buildCodexTomlPreview() -> String {
        var lines: [String] = []
        if let model = model.trimmedNonEmpty {
            lines.append("model = \(tomlQuoted(model))")
        }
        lines.append("wire_api = \(tomlQuoted(wireApi))")
        lines.append("base_url = \(tomlQuoted(resolvedBaseURL))")
        lines.append("reasoning_effort = \(tomlQuoted(reasoningEffort))")
        lines.append("")
        lines.append(L10n.tr("providers.toml.comment_preserved_sections"))
        return lines.joined(separator: "\n")
    }

    private func buildGeminiPreview() -> String {
        [
            "GEMINI_API_KEY=\(dotenvEscaped(apiKey.trimmedNonEmpty ?? "<API_KEY>"))",
            "GOOGLE_GEMINI_BASE_URL=\(dotenvEscaped(resolvedBaseURL))",
            "GEMINI_MODEL=\(dotenvEscaped(model.trimmedNonEmpty ?? (selectedPreset?.defaultModel ?? "gemini-2.5-pro")))"
        ].joined(separator: "\n")
    }

    private func fetchModels() {
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
                    claudeApiFormat: appType == .claude ? claudeApiFormat : nil
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

    @ViewBuilder
    private func configSectionCard<Content: View>(
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
    private func configField<Content: View>(
        label: String,
        hint: String?,
        hintLabel: String?,
        @ViewBuilder content: () -> Content
    ) -> some View {
        VStack(alignment: .leading, spacing: 6) {
            HStack {
                Text(label)
                    .font(.caption2.weight(.semibold))
                    .foregroundStyle(.secondary)
                Spacer(minLength: 0)
                if let hint, let hintLabel, let url = URL(string: hint) {
                    Link(hintLabel, destination: url)
                        .font(.caption2)
                        .foregroundStyle(accentTint)
                }
            }
            content()
        }
    }
}
