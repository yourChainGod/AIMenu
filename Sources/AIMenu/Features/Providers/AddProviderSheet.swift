import SwiftUI
import AppKit

// MARK: - Model Fetch State

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

// MARK: - Form State Sub-Structs

struct ClaudeFormState {
    var apiFormat: ClaudeApiFormat = .anthropic
    var apiKeyField: ClaudeApiKeyField = .authToken
    var haikuModel = ""
    var sonnetModel = ""
    var opusModel = ""
    var maxOutputTokens = ""
    var apiTimeoutMs = ""
    var disableNonessential = false
    var hideAttribution = false
    var alwaysThinking = false
    var enableTeammates = false
    var applyCommonConfig = false
    var commonConfigJSON = ""
    var showAdvanced = false
    var showCommonConfigEditor = false
}

struct CodexFormState {
    var wireApi = "responses"
    var reasoningEffort = "medium"
}

struct BillingFormState {
    var inputPrice = ""
    var outputPrice = ""
    var notes = ""
}

// MARK: - Add Provider Sheet

struct AddProviderSheet: View {
    let appType: ProviderAppType
    let initialPreset: ProviderPreset
    let onAdd: (ProviderDraft) -> Void
    let onCancel: () -> Void

    @State var selectedPreset: ProviderPreset?
    @State var searchText = ""
    @State var step: SheetStep = .selectPreset
    @State var didBootstrap = false

    @State var providerName = ""
    @State var websiteUrl = ""
    @State var providerNotes = ""
    @State var apiKey = ""
    @State var baseUrl = ""
    @State var model = ""
    @State var modelFetchState: ModelFetchState = .idle
    @State var fetchedModels: [String] = []
    @State var showAllPresets = false
    @State var showConfigPreview = true
    @State var showProxyConfig = false
    @State var showBillingConfig = false

    @State var proxyEnabled = false
    @State var proxyHost = ""
    @State var proxyPort = ""
    @State var proxyUsername = ""
    /// Sensitive credential — accessed by extension files, do not expose outside AddProviderSheet extensions.
    @State var proxyPassword = ""

    @State var claude = ClaudeFormState()
    @State var codex = CodexFormState()
    @State var billing = BillingFormState()

    enum SheetStep { case selectPreset, configure }

    var accentTint: Color { appType.formAccent }

    var allPresets: [ProviderPreset] {
        ProviderPresets.presets(for: appType)
    }

    var featuredPresetIDs: Set<String> {
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

    var filteredPresets: [ProviderPreset] {
        guard !searchText.isEmpty else { return allPresets }
        return allPresets.filter { $0.name.localizedCaseInsensitiveContains(searchText) }
    }

    var presets: [ProviderPreset] {
        guard searchText.isEmpty, !showAllPresets else { return filteredPresets }
        let featured = filteredPresets.filter { featuredPresetIDs.contains($0.id) }
        return featured.isEmpty ? filteredPresets : featured
    }

    var hiddenPresetCount: Int {
        max(filteredPresets.count - presets.count, 0)
    }

    var featuredPresetCount: Int {
        filteredPresets.filter { featuredPresetIDs.contains($0.id) }.count
    }

    var canAdd: Bool {
        guard selectedPreset != nil else { return false }
        return !apiKey.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
    }

    var canFetchModels: Bool {
        !apiKey.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
    }

    var resolvedBaseURL: String {
        if let baseUrl = baseUrl.trimmedNonEmpty { return baseUrl }
        if let presetBase = selectedPreset?.baseUrl?.trimmedNonEmpty { return presetBase }
        return appType.defaultBaseURL
    }

    // MARK: - Body

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
            // Auto-skip to configure if few presets
            if featuredPresetCount <= 3 {
                step = .configure
            }
        }
    }

    // MARK: - Top-Level Layout

    private var presetSelectionView: some View {
        VStack(alignment: .leading, spacing: 0) {
            sheetHeader
                .padding(.horizontal, 16)
                .padding(.top, 10)
                .padding(.bottom, 6)

            Rectangle()
                .fill(accentTint.opacity(OpacityScale.subtle))
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
                .fill(accentTint.opacity(OpacityScale.subtle))
                .frame(height: 1)

            configureStep
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
    }

    // MARK: - Sheet Header

    private var sheetHeader: some View {
        HStack(alignment: .center, spacing: 10) {
            RoundedRectangle(cornerRadius: 10, style: .continuous)
                .fill(accentTint.opacity(OpacityScale.subtle))
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

                    UnifiedBadge(
                        text: step == .selectPreset ? L10n.tr("providers.sheet.badge.preset_selection") : appType.displayName,
                        tint: accentTint
                    )
                }

                HStack(spacing: 8) {
                    UnifiedBadge(
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
                        withAnimation(AnimationPreset.quick) {
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
            withAnimation(AnimationPreset.quick) {
                step = .selectPreset
            }
            return
        }
        onCancel()
    }

    // MARK: - Configure Step

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
                            UnifiedBadge(text: L10n.tr("providers.badge.write"), tint: accentTint)
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
                        ProviderConfigKey.wireApi.rawValue: codex.wireApi,
                        ProviderConfigKey.reasoningEffort.rawValue: codex.reasoningEffort,
                        ProviderConfigKey.claudeApiFormat.rawValue: claude.apiFormat.rawValue,
                        ProviderConfigKey.claudeApiKeyField.rawValue: claude.apiKeyField.rawValue,
                        ProviderConfigKey.claudeHaikuModel.rawValue: claude.haikuModel,
                        ProviderConfigKey.claudeSonnetModel.rawValue: claude.sonnetModel,
                        ProviderConfigKey.claudeOpusModel.rawValue: claude.opusModel,
                        ProviderConfigKey.claudeMaxOutputTokens.rawValue: claude.maxOutputTokens,
                        ProviderConfigKey.claudeApiTimeoutMs.rawValue: claude.apiTimeoutMs,
                        ProviderConfigKey.claudeDisableNonessential.rawValue: claude.disableNonessential ? "true" : "false",
                        ProviderConfigKey.claudeHideAttribution.rawValue: claude.hideAttribution ? "true" : "false",
                        ProviderConfigKey.claudeAlwaysThinking.rawValue: claude.alwaysThinking ? "true" : "false",
                        ProviderConfigKey.claudeEnableTeammates.rawValue: claude.enableTeammates ? "true" : "false",
                        ProviderConfigKey.claudeApplyCommonConfig.rawValue: claude.applyCommonConfig ? "true" : "false",
                        ProviderConfigKey.claudeCommonConfigJSON.rawValue: claude.applyCommonConfig ? normalizedClaudeCommonConfigJSON : ""
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
                            inputPricePerMillion: billing.inputPrice,
                            outputPricePerMillion: billing.outputPrice,
                            currency: "USD",
                            notes: billing.notes
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
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .top)
    }

    // MARK: - App-Specific Section Router

    @ViewBuilder
    var appSpecificSection: some View {
        switch appType {
        case .claude:
            claudeSection
        case .codex:
            codexSection
        case .gemini:
            geminiSection
        }
    }

    // MARK: - Model Fetch Status & Selection

    @ViewBuilder
    var modelFetchStatusView: some View {
        if let msg = modelFetchState.statusMessage {
            Text(msg)
                .font(.caption)
                .foregroundStyle(modelFetchState.isFailed ? .red : .secondary)
        }
    }

    @ViewBuilder
    func fetchedModelRow(selection: Binding<String>) -> some View {
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

    // MARK: - Reusable Form Helpers

    @ViewBuilder
    func configSectionCard<Content: View>(
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
    func configField<Content: View>(
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
