import SwiftUI
import AppKit

struct ProviderPageView: View {
    @ObservedObject var model: ProviderPageModel

    @State private var hoveredProvider: String? = nil
    @State private var addingPreset: ProviderPreset?

    private var hasActiveModal: Bool {
        addingPreset != nil || model.editingProvider != nil
    }

    var body: some View {
        ZStack {
            pageContent
                .blur(radius: hasActiveModal ? 2 : 0)
                .allowsHitTesting(!hasActiveModal)

            if let addingPreset {
                providerModal(accent: model.selectedApp.formAccent) {
                    AddProviderSheet(
                        appType: model.selectedApp,
                        initialPreset: addingPreset,
                        onAdd: { draft in
                            Task { await model.addProvider(draft: draft) }
                        },
                        onCancel: closeAddProviderSheet
                    )
                }
            } else if let editing = model.editingProvider {
                providerModal(accent: editing.appType.formAccent) {
                    EditProviderSheet(
                        provider: editing,
                        onSave: { updated in
                            Task { await model.updateProvider(updated) }
                        },
                        onCancel: { model.editingProvider = nil }
                    )
                }
            }
        }
        .task {
            await model.load()
        }
        .onChange(of: model.selectedApp) { _, _ in
            if !model.isAddingProvider { addingPreset = nil }
        }
        .onChange(of: model.isAddingProvider) { _, isAddingProvider in
            if !isAddingProvider {
                addingPreset = nil
            }
        }
        .animation(.spring(response: 0.28, dampingFraction: 0.84), value: hasActiveModal)
    }

    private var pageContent: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: LayoutRules.sectionSpacing) {
                toolBar
                    .padding(.horizontal, LayoutRules.pagePadding)

                if currentProvider != nil {
                    providerSummaryCard
                        .padding(.horizontal, LayoutRules.pagePadding)
                }

                if model.loading && model.providers.isEmpty {
                    ProgressView("加载中...")
                        .frame(maxWidth: .infinity, minHeight: 120)
                        .padding(.horizontal, LayoutRules.pagePadding)
                } else if model.providers.isEmpty {
                    EmptyStateView(
                        title: "暂无提供商",
                        message: "添加提供商以开始使用 \(model.selectedApp.displayName)。",
                        icon: model.selectedApp.iconName,
                        tint: pageAccent
                    )
                    .padding(.horizontal, LayoutRules.pagePadding)
                } else {
                    LazyVStack(spacing: 2) {
                        ForEach(model.providers) { provider in
                            providerRow(provider)
                        }
                    }
                    .padding(.horizontal, LayoutRules.pagePadding)
                }
            }
        }
        .padding(.top, LayoutRules.pagePadding)
        .padding(.bottom, 12)
        .scrollIndicators(.hidden)
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
    }

    @ViewBuilder
    private func providerModal<Content: View>(
        accent: Color,
        @ViewBuilder content: @escaping () -> Content
    ) -> some View {
        GeometryReader { geometry in
            ZStack {
                Color.black.opacity(0.24)
                    .ignoresSafeArea()
                    .contentShape(Rectangle())
                    .onTapGesture {}

                ProviderModalPanel(accent: accent) {
                    content()
                }
                .frame(
                    width: min(max(420, geometry.size.width - 28), 540),
                    height: max(460, geometry.size.height - 28)
                )
                .padding(.horizontal, 14)
                .padding(.top, modalTopInset(for: geometry.size.height))
                .padding(.bottom, 14)
                .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .top)
                .transition(.move(edge: .top).combined(with: .scale(scale: 0.97)).combined(with: .opacity))
            }
            .zIndex(20)
        }
    }

    private func modalTopInset(for height: CGFloat) -> CGFloat {
        min(52, max(16, height * 0.08))
    }

    // MARK: - Toolbar (App Picker + Actions)

    private var currentProvider: Provider? {
        model.providers.first(where: \.isCurrent)
    }

    private var pageAccent: Color {
        model.selectedApp.formAccent
    }

    private var providerSummaryCard: some View {
        Group {
            if let currentProvider {
                HStack(spacing: 12) {
                    RoundedRectangle(cornerRadius: 12, style: .continuous)
                        .fill(pageAccent.opacity(0.10))
                        .overlay {
                            Image(systemName: model.selectedApp.iconName)
                                .font(.system(size: 17, weight: .semibold))
                                .foregroundStyle(pageAccent)
                        }
                        .frame(width: 38, height: 38)

                    VStack(alignment: .leading, spacing: 7) {
                        HStack(spacing: 8) {
                            Text(model.selectedApp.displayName)
                                .font(.headline.weight(.semibold))
                            ProviderConfigBadge(text: "已接管", tint: .mint)
                        }

                        Text(currentProvider.name)
                            .font(.subheadline.weight(.medium))
                            .foregroundStyle(.primary)
                            .lineLimit(1)

                        HStack(spacing: 6) {
                            if let host = providerEndpointHost(currentProvider) {
                                providerFeatureChip(text: host, tint: .secondary)
                            }

                            if let modelName = providerModelName(currentProvider) {
                                providerFeatureChip(text: modelName, tint: .accentColor)
                            }
                        }
                    }
                }
            }
        }
        .padding(12)
        .cardSurface(cornerRadius: 14, tint: pageAccent.opacity(0.035))
    }

    // MARK: - Provider Row

    @ViewBuilder
    private func providerRow(_ provider: Provider) -> some View {
        let isHovered = hoveredProvider == provider.id
        let rowAccent = providerIconColor(provider)

        HStack(alignment: .center, spacing: 10) {
            RoundedRectangle(cornerRadius: 10, style: .continuous)
                .fill((provider.isCurrent ? rowAccent : Color.primary).opacity(provider.isCurrent ? 0.16 : 0.05))
                .overlay {
                    Image(systemName: provider.displayIcon)
                        .font(.system(size: 13, weight: .semibold))
                        .foregroundStyle(provider.isCurrent ? rowAccent : Color.secondary)
                }
                .frame(width: 32, height: 32)

            VStack(alignment: .leading, spacing: 6) {
                HStack(spacing: 6) {
                    Text(provider.name)
                        .font(.system(size: 13, weight: .medium))
                        .lineLimit(1)

                    if provider.isCurrent {
                        Text("使用中")
                            .font(.system(size: 10, weight: .medium))
                            .foregroundStyle(.mint)
                            .padding(.horizontal, 5)
                            .padding(.vertical, 2)
                            .background(Color.mint.opacity(0.12), in: Capsule())
                    }
                }

                HStack(spacing: 6) {
                    if let modelName = providerModelName(provider) {
                        providerFeatureChip(text: modelName, tint: .accentColor)
                    }
                    if let host = providerEndpointHost(provider) {
                        providerFeatureChip(text: host, tint: .secondary)
                    }
                    if provider.proxyConfig?.enabled == true {
                        providerFeatureChip(text: "代理", tint: .orange)
                    }
                    if let billing = providerBillingSummary(provider) {
                        providerFeatureChip(text: billing, tint: .purple)
                    }
                }
            }

            Spacer(minLength: 0)

            VStack(alignment: .trailing, spacing: 6) {
                HStack(spacing: 4) {
                    if let result = model.speedTestResults[provider.id] {
                        Circle()
                            .fill(providerSpeedColor(result.qualityLevel))
                            .frame(width: 5, height: 5)
                        Text(result.statusText)
                            .font(.system(size: 10, weight: .medium))
                            .foregroundStyle(.secondary)
                    } else {
                        Text("未测速")
                            .font(.system(size: 10, weight: .medium))
                            .foregroundStyle(.tertiary)
                    }
                }

                HStack(spacing: 4) {
                    if !provider.isCurrent {
                        providerTinyButton(icon: "checkmark", tint: .mint, tooltip: "切换") {
                            Task { await model.switchProvider(provider) }
                        }
                    }
                    providerTinyButton(icon: "bolt", tint: .orange, tooltip: "测速") {
                        Task { await model.speedTest(provider) }
                    }
                    providerTinyButton(icon: "pencil", tint: .secondary, tooltip: "编辑") {
                        model.editingProvider = provider
                    }
                    providerTinyButton(icon: "trash", tint: .red, tooltip: "删除") {
                        Task { await model.deleteProvider(provider) }
                    }
                }
            }
        }
        .padding(.horizontal, 10)
        .padding(.vertical, 9)
        .background(
            RoundedRectangle(cornerRadius: 12, style: .continuous)
                .fill(
                    provider.isCurrent
                        ? rowAccent.opacity(isHovered ? 0.10 : 0.065)
                        : Color.primary.opacity(isHovered ? 0.04 : 0.018)
                )
                .overlay(
                    RoundedRectangle(cornerRadius: 12, style: .continuous)
                        .strokeBorder(
                            provider.isCurrent
                                ? rowAccent.opacity(0.16)
                                : Color.primary.opacity(isHovered ? 0.08 : 0.04),
                            lineWidth: 1
                        )
                )
        )
        .contentShape(Rectangle())
        .onHover { hoveredProvider = $0 ? provider.id : nil }
        .animation(.easeInOut(duration: 0.12), value: isHovered)
    }

    private func providerTinyButton(icon: String, tint: Color, tooltip: String, action: @escaping () -> Void) -> some View {
        Button(action: action) {
            Image(systemName: icon)
                .font(.system(size: 11, weight: .medium))
                .foregroundStyle(tint == .secondary ? Color.secondary : tint)
                .frame(width: 22, height: 22)
                .background(
                    RoundedRectangle(cornerRadius: 7, style: .continuous)
                        .fill(tint == .secondary ? Color.primary.opacity(0.05) : tint.opacity(0.08))
                        .overlay(
                            RoundedRectangle(cornerRadius: 7, style: .continuous)
                                .strokeBorder((tint == .secondary ? Color.primary : tint).opacity(0.10), lineWidth: 1)
                        )
                )
        }
        .buttonStyle(.plain)
        .help(tooltip)
    }

    private func providerFeatureChip(text: String, tint: Color) -> some View {
        Text(text)
            .font(.system(size: 10, weight: .medium))
            .foregroundStyle(tint == .secondary ? .secondary : tint)
            .padding(.horizontal, 6)
            .padding(.vertical, 3)
            .background(
                Capsule()
                    .fill((tint == .secondary ? Color.primary : tint).opacity(0.06))
            )
            .lineLimit(1)
    }

    private func providerDetailRow(label: String, value: String) -> some View {
        HStack(alignment: .top, spacing: 8) {
            Text(label)
                .font(.caption.weight(.medium))
                .foregroundStyle(.secondary)
                .frame(width: 64, alignment: .leading)
            Text(value)
                .font(.caption.monospaced())
                .foregroundStyle(.primary)
                .textSelection(.enabled)
                .lineLimit(2)
        }
    }

    private func providerIconColor(_ provider: Provider) -> Color {
        if let hex = provider.iconColor { return Color(hex: hex) }
        return .secondary
    }

    private func providerModelName(_ provider: Provider) -> String? {
        let rawValue: String?
        switch provider.appType {
        case .claude:
            rawValue = provider.claudeConfig?.model
        case .codex:
            rawValue = provider.codexConfig?.model
        case .gemini:
            rawValue = provider.geminiConfig?.model
        }
        let trimmed = rawValue?.trimmingCharacters(in: .whitespacesAndNewlines)
        return (trimmed?.isEmpty == false) ? trimmed : nil
    }

    private func providerEndpointHost(_ provider: Provider) -> String? {
        let rawBaseURL: String?
        switch provider.appType {
        case .claude:
            rawBaseURL = provider.claudeConfig?.baseUrl
        case .codex:
            rawBaseURL = provider.codexConfig?.baseUrl
        case .gemini:
            rawBaseURL = provider.geminiConfig?.baseUrl
        }

        guard let rawBaseURL = rawBaseURL?.trimmingCharacters(in: .whitespacesAndNewlines),
              !rawBaseURL.isEmpty else {
            return nil
        }
        return URL(string: rawBaseURL)?.host ?? rawBaseURL
    }

    private func providerBillingSummary(_ provider: Provider) -> String? {
        guard let billing = provider.billingConfig?.normalized else { return nil }
        let input = billing.inputPricePerMillion.isEmpty ? nil : "in \(billing.inputPricePerMillion)"
        let output = billing.outputPricePerMillion.isEmpty ? nil : "out \(billing.outputPricePerMillion)"
        return [input, output].compactMap { $0 }.joined(separator: " · ")
    }

    private func providerSpeedColor(_ quality: SpeedTestQuality) -> Color {
        switch quality {
        case .excellent: return .green
        case .good: return .mint
        case .fair: return .orange
        case .poor: return .red
        case .unknown: return .gray
        }
    }

    // MARK: - Toolbar

    private var toolBar: some View {
        VStack(spacing: 10) {
            HStack(spacing: LayoutRules.listRowSpacing) {
                ForEach(ProviderAppType.allCases) { app in
                    Button {
                        Task { await model.switchApp(app) }
                    } label: {
                        HStack(spacing: 6) {
                            Image(systemName: app.iconName)
                                .font(.caption.weight(.semibold))
                            Text(app.displayName)
                                .font(.subheadline.weight(.medium))
                        }
                        .lineLimit(1)
                    }
                    .aimenuActionButtonStyle(
                        prominent: model.selectedApp == app,
                        tint: model.selectedApp == app ? app.formAccent : nil,
                        density: .compact
                    )
                }
            }
            .frame(maxWidth: 340)
            .frame(maxWidth: .infinity, alignment: .center)

            HStack(spacing: 8) {
                Button {
                    openAddProviderSheet()
                } label: {
                    Label("添加", systemImage: "plus")
                        .lineLimit(1)
                }
                .aimenuActionButtonStyle(prominent: true, tint: pageAccent, density: .compact)

                Button {
                    Task { await model.speedTestAll() }
                } label: {
                    Label("全部测速", systemImage: "bolt.horizontal.fill")
                        .lineLimit(1)
                }
                .aimenuActionButtonStyle(prominent: true, tint: .orange, density: .compact)
                .disabled(model.providers.isEmpty)
            }
            .frame(maxWidth: 220)
            .frame(maxWidth: .infinity, alignment: .center)
        }
    }

    private func openAddProviderSheet() {
        guard let preset = ProviderPresets.presets(for: model.selectedApp).first else { return }
        addingPreset = preset
        model.isAddingProvider = true
    }

    private func closeAddProviderSheet() {
        model.isAddingProvider = false
        addingPreset = nil
    }
}

private struct ProviderModalPanel<Content: View>: View {
    let accent: Color
    @ViewBuilder let content: Content

    var body: some View {
        VStack(spacing: 0) {
            content
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .top)
        .background {
            ZStack {
                RoundedRectangle(cornerRadius: 22, style: .continuous)
                    .fill(Color(nsColor: .windowBackgroundColor).opacity(0.985))
                RoundedRectangle(cornerRadius: 22, style: .continuous)
                    .fill(accent.opacity(0.03))
                RoundedRectangle(cornerRadius: 22, style: .continuous)
                    .strokeBorder(Color(nsColor: .separatorColor).opacity(0.14), lineWidth: 1)
            }
        }
        .clipShape(RoundedRectangle(cornerRadius: 22, style: .continuous))
        .shadow(color: .black.opacity(0.14), radius: 18, x: 0, y: 10)
    }
}

// MARK: - Add Provider Sheet

private struct AddProviderSheet: View {
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
    @State private var isFetchingModels = false
    @State private var fetchedModels: [String] = []
    @State private var modelFetchStatus: String?
    @State private var modelFetchFailed = false
    @State private var showAllPresets = false
    @State private var showConfigPreview = true
    @State private var showProxyConfig = false
    @State private var showBillingConfig = false

    @State private var proxyEnabled = false
    @State private var proxyHost = ""
    @State private var proxyPort = ""
    @State private var proxyUsername = ""
    @State private var proxyPassword = ""

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
                .padding(.horizontal, 20)
                .padding(.top, 16)
                .padding(.bottom, 12)

            Divider()

            presetPickerStep
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
    }

    private var configureView: some View {
        VStack(alignment: .leading, spacing: 0) {
            sheetHeader
                .padding(.horizontal, 20)
                .padding(.top, 16)
                .padding(.bottom, 12)

            Divider()

            configureStep
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
    }

    private var sheetHeader: some View {
        HStack(spacing: 12) {
            RoundedRectangle(cornerRadius: 12, style: .continuous)
                .fill(accentTint.opacity(0.14))
                .overlay {
                    Image(systemName: step == .selectPreset ? "square.grid.2x2.fill" : (selectedPreset?.icon ?? appType.iconName))
                        .font(.system(size: 16, weight: .semibold))
                        .foregroundStyle(accentTint)
                }
                .frame(width: 38, height: 38)

            VStack(alignment: .leading, spacing: 4) {
                HStack(spacing: 8) {
                    Text(step == .selectPreset ? "选择提供商" : (selectedPreset?.name ?? "配置详情"))
                        .font(.headline.weight(.semibold))

                    Text(step == .selectPreset ? "预设" : "配置")
                        .font(.caption2.weight(.bold))
                        .foregroundStyle(accentTint)
                        .padding(.horizontal, 7)
                        .padding(.vertical, 3)
                        .background(accentTint.opacity(0.12), in: Capsule())
                }
                Text(step == .selectPreset ? "先挑一个常用预设，再补充接口与模型。" : appType.liveConfigPathsText)
                    .font(.caption)
                    .foregroundStyle(.secondary)
                    .lineLimit(1)
            }

            Spacer(minLength: 0)

            if step == .configure {
                Button("返回预设") {
                    withAnimation(.easeInOut(duration: 0.2)) {
                        step = .selectPreset
                    }
                }
                .aimenuActionButtonStyle(density: .compact)
            }

            CloseGlassButton { handleClose() }
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
                    TextField("搜索提供商...", text: $searchText)
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
                            title: "精选",
                            count: featuredPresetCount,
                            isActive: !showAllPresets
                        ) {
                            withAnimation(.easeInOut(duration: 0.2)) {
                                showAllPresets = false
                            }
                        }

                        if hiddenPresetCount > 0 {
                            presetScopeButton(
                                title: "全部",
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
                            text: "搜索结果 \(filteredPresets.count)",
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
                            text: "点击卡片进入配置",
                            tint: .secondary
                        )
                    }
                }
            }
            .padding(.horizontal, 18)
            .padding(.top, 14)
            .padding(.bottom, 12)
            .background(
                LinearGradient(
                    colors: [
                        accentTint.opacity(0.08),
                        Color.clear
                    ],
                    startPoint: .topLeading,
                    endPoint: .bottomTrailing
                )
            )

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

            Divider()
                .overlay(Color.white.opacity(0.08))

            HStack(spacing: 8) {
                HStack(spacing: 6) {
                    Image(systemName: showAllPresets ? "square.grid.2x2" : "sparkles")
                        .font(.caption2.weight(.semibold))
                    Text(showAllPresets ? "已展开全部预设" : "优先展示常用预设")
                        .font(.caption)
                }
                .foregroundStyle(.secondary)

                Spacer(minLength: 0)

                Text("当前 \(presets.count) / 共 \(filteredPresets.count)")
                    .font(.caption)
                    .foregroundStyle(.tertiary)

                Button("取消") { onCancel() }
                    .aimenuActionButtonStyle()
            }
            .padding(.horizontal, 18)
            .padding(.vertical, 10)
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .top)
    }

    private var configureStep: some View {
        VStack(spacing: 0) {
            ScrollView {
                VStack(alignment: .leading, spacing: 12) {
                    formHeroCard

                    configSectionCard(title: "基本信息") {
                        HStack(alignment: .top, spacing: 12) {
                            configField(label: "供应商名称 *", hint: nil, hintLabel: nil) {
                                TextField(selectedPreset?.name ?? "名称", text: $providerName)
                                    .frostedRoundedInput(cornerRadius: 10)
                            }
                            .frame(maxWidth: .infinity, alignment: .leading)

                            configField(
                                label: "官网地址",
                                hint: selectedPreset?.websiteUrl,
                                hintLabel: selectedPreset?.websiteUrl != nil ? "访问" : nil
                            ) {
                                TextField("https://（可选）", text: $websiteUrl)
                                    .frostedRoundedInput(cornerRadius: 10)
                            }
                            .frame(maxWidth: .infinity, alignment: .leading)
                        }

                        configField(label: "备注", hint: nil, hintLabel: nil) {
                            TextField("可选备注信息", text: $providerNotes)
                                .frostedRoundedInput(cornerRadius: 10)
                        }
                    }

                    configSectionCard(title: "接口凭据") {
                        configField(
                            label: "API 密钥 *",
                            hint: selectedPreset?.apiKeyUrl,
                            hintLabel: "获取 Key"
                        ) {
                            SecureField("粘贴或输入 API Key", text: $apiKey)
                                .frostedRoundedInput(cornerRadius: 10)
                        }
                        configField(label: "接口地址", hint: nil, hintLabel: nil) {
                            TextField(selectedPreset?.baseUrl ?? appType.defaultBaseURL, text: $baseUrl)
                                .frostedRoundedInput(cornerRadius: 10)
                        }
                        HStack(spacing: 8) {
                            ProviderConfigBadge(text: "写入", tint: accentTint)
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
                .padding(.vertical, 14)
            }
            .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .top)

            Divider()

            HStack(spacing: 8) {
                if let preset = selectedPreset {
                    Image(systemName: preset.icon ?? "server.rack")
                        .foregroundStyle(accentTint)
                        .font(.subheadline)
                    Text(preset.name)
                        .font(.subheadline.weight(.medium))
                        .lineLimit(1)
                }
                Spacer(minLength: 0)
                Button("取消") { onCancel() }
                    .aimenuActionButtonStyle()
                Button("添加") {
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
            .padding(.horizontal, 18)
            .padding(.vertical, 12)
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
    private var formHeroCard: some View {
        if let preset = selectedPreset {
            configSectionCard(emphasis: true) {
                HStack(alignment: .top, spacing: 12) {
                    Image(systemName: preset.icon ?? appType.iconName)
                        .font(.system(size: 18, weight: .semibold))
                        .foregroundStyle(accentTint)
                        .frame(width: 40, height: 40)
                        .background(accentTint.opacity(0.14), in: RoundedRectangle(cornerRadius: 12))

                    VStack(alignment: .leading, spacing: 8) {
                        Text(preset.name)
                            .font(.headline)
                        Text("写入 \(appType.liveConfigPathsText)")
                            .font(.caption)
                            .foregroundStyle(.secondary)

                        HStack(spacing: 6) {
                            ProviderConfigBadge(text: preset.category.displayName, tint: accentTint)
                            if let host = URL(string: resolvedBaseURL)?.host {
                                ProviderConfigBadge(text: host, tint: .secondary)
                            }
                            if let defaultModel = preset.defaultModel?.trimmedNonEmpty {
                                ProviderConfigBadge(text: defaultModel, tint: accentTint)
                            }
                        }
                    }
                }
            }
        }
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
            configSectionCard(title: "Claude 模型与认证", subtitle: "主模型 + 自动拉取") {
                configField(label: "API 格式", hint: nil, hintLabel: nil) {
                    Picker("", selection: $claudeApiFormat) {
                        Text("Anthropic 原生").tag(ClaudeApiFormat.anthropic)
                        Text("OpenAI Chat").tag(ClaudeApiFormat.openaiChat)
                        Text("OpenAI Responses").tag(ClaudeApiFormat.openaiResponses)
                    }
                    .pickerStyle(.segmented)
                }
                configField(label: "认证字段", hint: nil, hintLabel: nil) {
                    Picker("", selection: $claudeApiKeyField) {
                        Text("ANTHROPIC_AUTH_TOKEN").tag(ClaudeApiKeyField.authToken)
                        Text("ANTHROPIC_API_KEY").tag(ClaudeApiKeyField.apiKey)
                    }
                    .pickerStyle(.segmented)
                }
                ProviderModelInputRow(
                    title: "主模型",
                    placeholder: selectedPreset?.defaultModel ?? "留空使用默认",
                    text: $model,
                    isFetching: isFetchingModels,
                    canFetch: canFetchModels,
                    accent: accentTint,
                    onFetch: fetchModels
                )
                modelFetchStatusView
                fetchedModelRow(selection: $model)
            }

            configSectionCard {
                Button {
                    withAnimation(.easeInOut(duration: 0.2)) { showClaudeAdvanced.toggle() }
                } label: {
                    HStack {
                        VStack(alignment: .leading, spacing: 3) {
                            Text("模型路由与运行参数")
                                .font(.subheadline.weight(.semibold))
                                .foregroundStyle(.primary)
                            Text("按需覆盖附加模型与运行参数。")
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
                            configField(label: "Haiku 默认模型", hint: nil, hintLabel: nil) {
                                TextField("可选覆盖", text: $claudeHaikuModel)
                                    .frostedRoundedInput(cornerRadius: 10)
                            }
                            .frame(maxWidth: .infinity, alignment: .leading)

                            configField(label: "Sonnet 默认模型", hint: nil, hintLabel: nil) {
                                TextField("可选覆盖", text: $claudeSonnetModel)
                                    .frostedRoundedInput(cornerRadius: 10)
                            }
                            .frame(maxWidth: .infinity, alignment: .leading)
                        }
                        HStack(alignment: .top, spacing: 12) {
                            configField(label: "Opus 默认模型", hint: nil, hintLabel: nil) {
                                TextField("可选覆盖", text: $claudeOpusModel)
                                    .frostedRoundedInput(cornerRadius: 10)
                            }
                            .frame(maxWidth: .infinity, alignment: .leading)

                            configField(label: "最大输出 Token", hint: nil, hintLabel: nil) {
                                TextField("留空使用默认", text: $claudeMaxOutputTokens)
                                    .frostedRoundedInput(cornerRadius: 10)
                            }
                            .frame(maxWidth: .infinity, alignment: .leading)
                        }
                        configField(label: "超时 (ms)", hint: nil, hintLabel: nil) {
                            TextField("留空使用默认", text: $claudeApiTimeoutMs)
                                .frostedRoundedInput(cornerRadius: 10)
                        }
                        Toggle("禁用非必要流量", isOn: $claudeDisableNonessential)
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
            configSectionCard(title: "Codex 模型", subtitle: "写入 `auth.json` + `config.toml`") {
                ProviderModelInputRow(
                    title: "模型名称",
                    placeholder: selectedPreset?.defaultModel ?? "例如：gpt-5-codex",
                    text: $model,
                    isFetching: isFetchingModels,
                    canFetch: canFetchModels,
                    accent: accentTint,
                    onFetch: fetchModels
                )
                modelFetchStatusView
                fetchedModelRow(selection: $model)
            }

            configSectionCard(title: "Codex 运行参数", subtitle: "只更新根字段") {
                HStack(alignment: .top, spacing: 12) {
                    configField(label: "Wire API", hint: nil, hintLabel: nil) {
                        Picker("", selection: $wireApi) {
                            Text("responses").tag("responses")
                            Text("chat").tag("chat")
                        }
                        .pickerStyle(.segmented)
                    }
                    .frame(maxWidth: .infinity, alignment: .leading)

                    configField(label: "推理强度", hint: nil, hintLabel: nil) {
                        Picker("", selection: $reasoningEffort) {
                            Text("low").tag("low")
                            Text("medium").tag("medium")
                            Text("high").tag("high")
                        }
                        .pickerStyle(.segmented)
                    }
                    .frame(maxWidth: .infinity, alignment: .leading)
                }
            }
        }
    }

    private var geminiSection: some View {
        configSectionCard(title: "Gemini 模型", subtitle: "支持官方与聚合接口") {
            ProviderModelInputRow(
                title: "模型名称",
                placeholder: selectedPreset?.defaultModel ?? "默认模型",
                text: $model,
                isFetching: isFetchingModels,
                canFetch: canFetchModels,
                accent: accentTint,
                onFetch: fetchModels
            )
            modelFetchStatusView
            fetchedModelRow(selection: $model)
        }
    }

    private var configPreviewSection: some View {
        configSectionCard {
            Button {
                withAnimation(.easeInOut(duration: 0.2)) { showConfigPreview.toggle() }
            } label: {
                HStack {
                    VStack(alignment: .leading, spacing: 3) {
                        Text("配置预览")
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
                            title: "通用配置 (JSON)",
                            subtitle: "合并写入 `~/.claude/settings.json` 顶层；`hooks` 与 Hooks 页共用字段",
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
        configSectionCard {
            Button {
                withAnimation(.easeInOut(duration: 0.2)) { showProxyConfig.toggle() }
            } label: {
                HStack {
                    Text("代理配置")
                        .font(.subheadline.weight(.semibold))
                        .foregroundStyle(.primary)
                    Spacer(minLength: 0)
                    if proxyEnabled {
                        ProviderConfigBadge(text: "已启用", tint: .orange)
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
                    Toggle("启用代理", isOn: $proxyEnabled)
                        .toggleStyle(.checkbox)
                        .font(.subheadline)
                    if proxyEnabled {
                        HStack(alignment: .top, spacing: 12) {
                            configField(label: "代理主机", hint: nil, hintLabel: nil) {
                                TextField("127.0.0.1", text: $proxyHost)
                                    .frostedRoundedInput(cornerRadius: 10)
                            }
                            .frame(maxWidth: .infinity, alignment: .leading)

                            configField(label: "端口", hint: nil, hintLabel: nil) {
                                TextField("7890", text: $proxyPort)
                                    .frostedRoundedInput(cornerRadius: 10)
                            }
                            .frame(maxWidth: .infinity, alignment: .leading)
                        }
                        HStack(alignment: .top, spacing: 12) {
                            configField(label: "用户名（可选）", hint: nil, hintLabel: nil) {
                                TextField("留空跳过", text: $proxyUsername)
                                    .frostedRoundedInput(cornerRadius: 10)
                            }
                            .frame(maxWidth: .infinity, alignment: .leading)

                            configField(label: "密码（可选）", hint: nil, hintLabel: nil) {
                                SecureField("留空跳过", text: $proxyPassword)
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
        configSectionCard {
            Button {
                withAnimation(.easeInOut(duration: 0.2)) { showBillingConfig.toggle() }
            } label: {
                HStack {
                    Text("计费配置")
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
                        configField(label: "输入价格（$/M tokens）", hint: nil, hintLabel: nil) {
                            TextField("例：3.00", text: $billingInputPrice)
                                .frostedRoundedInput(cornerRadius: 10)
                        }
                        .frame(maxWidth: .infinity, alignment: .leading)

                        configField(label: "输出价格（$/M tokens）", hint: nil, hintLabel: nil) {
                            TextField("例：15.00", text: $billingOutputPrice)
                                .frostedRoundedInput(cornerRadius: 10)
                        }
                        .frame(maxWidth: .infinity, alignment: .leading)
                    }
                    configField(label: "备注", hint: nil, hintLabel: nil) {
                        TextField("可选备注信息", text: $billingNotes)
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
            return "可直接改 `settings.json` 预览。"
        case .codex:
            return "分开编辑 `auth.json` 与 `config.toml`。"
        case .gemini:
            return "可直接改 `.env` 预览。"
        }
    }

    private var previewBlocks: [ProviderPreviewBlockData] {
        switch appType {
        case .claude:
            return [
                ProviderPreviewBlockData(
                    title: "settings.json (JSON)",
                    subtitle: "写入 `~/.claude/settings.json`",
                    content: buildClaudePreview(),
                    onApply: applyClaudePreview
                )
            ]
        case .codex:
            return [
                ProviderPreviewBlockData(
                    title: "auth.json (JSON)",
                    subtitle: "写入 `~/.codex/auth.json`",
                    content: buildCodexAuthPreview(),
                    onApply: applyCodexAuthPreview
                ),
                ProviderPreviewBlockData(
                    title: "config.toml (TOML)",
                    subtitle: "增量更新根字段，保留已有 MCP 配置",
                    content: buildCodexTomlPreview(),
                    onApply: applyCodexTomlPreview
                )
            ]
        case .gemini:
            return [
                ProviderPreviewBlockData(
                    title: ".env",
                    subtitle: "写入 `~/.gemini/.env`",
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
                                        .fill(selection.wrappedValue == modelID ? accentTint.opacity(0.18) : Color.primary.opacity(0.06))
                                        .overlay(
                                            RoundedRectangle(cornerRadius: 8, style: .continuous)
                                                .strokeBorder(selection.wrappedValue == modelID ? accentTint.opacity(0.35) : Color.primary.opacity(0.08), lineWidth: 1)
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
        modelFetchStatus = nil
        modelFetchFailed = false
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
        lines.append("# 其他段落（如 [mcp_servers.xxx]）会被保留")
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

        isFetchingModels = true
        modelFetchFailed = false
        modelFetchStatus = "正在获取模型列表..."

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
                    isFetchingModels = false
                    modelFetchFailed = false
                    modelFetchStatus = models.isEmpty ? "接口已响应，但没有返回可用模型，可手动填写。" : "已获取 \(models.count) 个模型"
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

    @ViewBuilder
    private func configSectionCard<Content: View>(
        title: String? = nil,
        subtitle: String? = nil,
        emphasis: Bool = false,
        @ViewBuilder content: () -> Content
    ) -> some View {
        VStack(alignment: .leading, spacing: 12) {
            if let title {
                VStack(alignment: .leading, spacing: 3) {
                    Text(title)
                        .font(.subheadline.weight(.semibold))
                        .foregroundStyle(.primary)
                    if let subtitle {
                        Text(subtitle)
                            .font(.caption)
                            .foregroundStyle(.secondary)
                    }
                }
            }
            content()
        }
        .padding(14)
        .cardSurface(cornerRadius: 14, tint: accentTint.opacity(emphasis ? 0.05 : 0.025))
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
                    .font(.caption.weight(.semibold))
                    .foregroundStyle(.primary)
                Spacer(minLength: 0)
                if let hint, let hintLabel, let url = URL(string: hint) {
                    Link(hintLabel, destination: url)
                        .font(.caption)
                        .foregroundStyle(accentTint)
                }
            }
            content()
        }
    }
}

// MARK: - Edit Provider Sheet

private struct EditProviderSheet: View {
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
            HStack(spacing: 12) {
                RoundedRectangle(cornerRadius: 12, style: .continuous)
                    .fill(accentTint.opacity(0.14))
                    .overlay {
                        Image(systemName: provider.displayIcon)
                            .font(.system(size: 16, weight: .semibold))
                            .foregroundStyle(accentTint)
                    }
                    .frame(width: 38, height: 38)

                VStack(alignment: .leading, spacing: 4) {
                    HStack(spacing: 8) {
                        Text("编辑提供商")
                            .font(.headline.weight(.semibold))

                        Text("配置")
                            .font(.caption2.weight(.bold))
                            .foregroundStyle(accentTint)
                            .padding(.horizontal, 7)
                            .padding(.vertical, 3)
                            .background(accentTint.opacity(0.12), in: Capsule())
                    }
                    Text(provider.appType.liveConfigPathsText)
                        .font(.caption)
                        .foregroundStyle(.secondary)
                        .lineLimit(1)
                }
                Spacer(minLength: 0)
                CloseGlassButton { onCancel() }
            }
            .padding(.horizontal, 20)
            .padding(.top, 16)
            .padding(.bottom, 12)

            Divider()

            ScrollView {
                VStack(alignment: .leading, spacing: 12) {
                    editHeroCard

                    sectionCard(title: "基础信息") {
                        HStack(alignment: .top, spacing: 12) {
                            editConfigField(label: "名称") {
                                TextField("提供商名称", text: $providerName)
                                    .frostedRoundedInput(cornerRadius: 10)
                            }
                            .frame(maxWidth: .infinity, alignment: .leading)

                            editConfigField(label: "备注") {
                                TextField("可选备注", text: $notes)
                                    .frostedRoundedInput(cornerRadius: 10)
                            }
                            .frame(maxWidth: .infinity, alignment: .leading)
                        }
                    }

                    sectionCard(title: "接口凭据") {
                        editConfigField(
                            label: "API 密钥 *",
                            trailingLink: apiKeyUrl.isEmpty ? nil : URL(string: apiKeyUrl),
                            trailingLinkLabel: "获取 Key"
                        ) {
                            HStack(spacing: 6) {
                                Group {
                                    if showApiKey {
                                        TextField("粘贴或输入 API Key", text: currentApiKeyBinding)
                                    } else {
                                        SecureField("粘贴或输入 API Key", text: currentApiKeyBinding)
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
                            label: "接口地址",
                            trailingLink: websiteUrl.isEmpty ? nil : URL(string: websiteUrl),
                            trailingLinkLabel: "访问"
                        ) {
                            TextField(currentBaseUrlPlaceholder, text: currentBaseUrlBinding)
                                .frostedRoundedInput(cornerRadius: 10)
                        }
                    }

                    appSpecificEditSection

                    previewSection

                    sectionCard(title: "链接信息") {
                        HStack(alignment: .top, spacing: 12) {
                            editConfigField(label: "官网链接") {
                                TextField("https://", text: $websiteUrl)
                                    .frostedRoundedInput(cornerRadius: 10)
                            }
                            .frame(maxWidth: .infinity, alignment: .leading)

                            editConfigField(label: "获取 Key 链接") {
                                TextField("https://", text: $apiKeyUrl)
                                    .frostedRoundedInput(cornerRadius: 10)
                            }
                            .frame(maxWidth: .infinity, alignment: .leading)
                        }
                    }
                }
                .padding(.horizontal, 18)
                .padding(.vertical, 14)
            }
            .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .top)

            Divider()

            HStack(spacing: 8) {
                Spacer(minLength: 0)
                Button("取消") { onCancel() }
                    .aimenuActionButtonStyle()
                Button("保存") { saveProvider() }
                    .aimenuActionButtonStyle(prominent: true, tint: accentTint)
                    .disabled(!canSave)
            }
            .padding(.horizontal, 18)
            .padding(.vertical, 12)
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
    }

    @ViewBuilder
    private var editHeroCard: some View {
        sectionCard(emphasis: true) {
            HStack(alignment: .top, spacing: 12) {
                Image(systemName: provider.displayIcon)
                    .font(.system(size: 18, weight: .semibold))
                    .foregroundStyle(accentTint)
                    .frame(width: 40, height: 40)
                    .background(accentTint.opacity(0.14), in: RoundedRectangle(cornerRadius: 12))

                VStack(alignment: .leading, spacing: 8) {
                    Text(provider.name)
                        .font(.headline)
                    Text("同步 \(provider.appType.liveConfigPathsText)")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                    HStack(spacing: 6) {
                        if provider.isCurrent {
                            ProviderConfigBadge(text: "使用中", tint: .mint)
                        }
                        if let host = URL(string: resolvedBaseURL)?.host {
                            ProviderConfigBadge(text: host, tint: .secondary)
                        }
                        if let model = currentModelName.trimmedNonEmpty {
                            ProviderConfigBadge(text: model, tint: accentTint)
                        }
                    }
                }
            }
        }
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
            sectionCard(title: "Claude 模型与认证", subtitle: "主模型 + 自动拉取") {
                editConfigField(label: "API 格式") {
                    Picker("", selection: $claudeApiFormat) {
                        Text("Anthropic 原生").tag(ClaudeApiFormat.anthropic)
                        Text("OpenAI Chat").tag(ClaudeApiFormat.openaiChat)
                        Text("OpenAI Responses").tag(ClaudeApiFormat.openaiResponses)
                    }
                    .pickerStyle(.segmented)
                }
                editConfigField(label: "认证字段") {
                    Picker("", selection: $claudeApiKeyField) {
                        Text("ANTHROPIC_AUTH_TOKEN").tag(ClaudeApiKeyField.authToken)
                        Text("ANTHROPIC_API_KEY").tag(ClaudeApiKeyField.apiKey)
                    }
                    .pickerStyle(.segmented)
                }
                ProviderModelInputRow(
                    title: "主模型",
                    placeholder: "留空使用默认",
                    text: $claudeModel,
                    isFetching: isFetchingModels,
                    canFetch: canSave,
                    accent: accentTint,
                    onFetch: fetchModels
                )
                modelFetchStatusView
                fetchedModelRow(selection: $claudeModel)
            }

            sectionCard {
                Button {
                    withAnimation(.easeInOut(duration: 0.2)) { showClaudeAdvanced.toggle() }
                } label: {
                    HStack {
                        VStack(alignment: .leading, spacing: 3) {
                            Text("模型路由与运行参数")
                                .font(.subheadline.weight(.semibold))
                                .foregroundStyle(.primary)
                            Text("按需覆盖附加模型与运行参数。")
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
                            editConfigField(label: "Haiku 默认模型") {
                                TextField("可选覆盖", text: $claudeHaikuModel)
                                    .frostedRoundedInput(cornerRadius: 10)
                            }
                            .frame(maxWidth: .infinity, alignment: .leading)

                            editConfigField(label: "Sonnet 默认模型") {
                                TextField("可选覆盖", text: $claudeSonnetModel)
                                    .frostedRoundedInput(cornerRadius: 10)
                            }
                            .frame(maxWidth: .infinity, alignment: .leading)
                        }
                        HStack(alignment: .top, spacing: 12) {
                            editConfigField(label: "Opus 默认模型") {
                                TextField("可选覆盖", text: $claudeOpusModel)
                                    .frostedRoundedInput(cornerRadius: 10)
                            }
                            .frame(maxWidth: .infinity, alignment: .leading)

                            editConfigField(label: "最大输出 Token") {
                                TextField("留空使用默认", text: $claudeMaxOutputTokens)
                                    .frostedRoundedInput(cornerRadius: 10)
                            }
                            .frame(maxWidth: .infinity, alignment: .leading)
                        }
                        editConfigField(label: "超时 (ms)") {
                            TextField("留空使用默认", text: $claudeApiTimeoutMs)
                                .frostedRoundedInput(cornerRadius: 10)
                        }
                        Toggle("禁用非必要流量", isOn: $claudeDisableNonessential)
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
            sectionCard(title: "Codex 模型", subtitle: "写入 `auth.json` + `config.toml`") {
                ProviderModelInputRow(
                    title: "模型名称",
                    placeholder: "例如：gpt-5-codex",
                    text: $codexModel,
                    isFetching: isFetchingModels,
                    canFetch: canSave,
                    accent: accentTint,
                    onFetch: fetchModels
                )
                modelFetchStatusView
                fetchedModelRow(selection: $codexModel)
            }

            sectionCard(title: "Codex 运行参数", subtitle: "只更新根字段") {
                HStack(alignment: .top, spacing: 12) {
                    editConfigField(label: "Wire API") {
                        Picker("", selection: $codexWireApi) {
                            Text("responses").tag("responses")
                            Text("chat").tag("chat")
                        }
                        .pickerStyle(.segmented)
                    }
                    .frame(maxWidth: .infinity, alignment: .leading)

                    editConfigField(label: "推理强度") {
                        Picker("", selection: $codexReasoningEffort) {
                            Text("low").tag("low")
                            Text("medium").tag("medium")
                            Text("high").tag("high")
                        }
                        .pickerStyle(.segmented)
                    }
                    .frame(maxWidth: .infinity, alignment: .leading)
                }
            }
        }
    }

    private var geminiEditFields: some View {
        sectionCard(title: "Gemini 模型", subtitle: "支持官方与聚合接口") {
            ProviderModelInputRow(
                title: "模型名称",
                placeholder: "例如：gemini-2.5-pro",
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
        sectionCard {
            Button {
                withAnimation(.easeInOut(duration: 0.2)) { showConfigPreview.toggle() }
            } label: {
                HStack {
                    VStack(alignment: .leading, spacing: 3) {
                        Text("配置预览")
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
                            title: "通用配置 (JSON)",
                            subtitle: "合并写入 `~/.claude/settings.json` 顶层；`hooks` 与 Hooks 页共用字段",
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
            return "可直接改 `settings.json` 预览。"
        case .codex:
            return "分开编辑 `auth.json` 与 `config.toml`。"
        case .gemini:
            return "可直接改 `.env` 预览。"
        }
    }

    private var previewBlocks: [ProviderPreviewBlockData] {
        switch provider.appType {
        case .claude:
            return [
                ProviderPreviewBlockData(
                    title: "settings.json (JSON)",
                    subtitle: "写入 `~/.claude/settings.json`",
                    content: buildClaudePreview(),
                    onApply: applyClaudePreview
                )
            ]
        case .codex:
            return [
                ProviderPreviewBlockData(
                    title: "auth.json (JSON)",
                    subtitle: "写入 `~/.codex/auth.json`",
                    content: buildCodexAuthPreview(),
                    onApply: applyCodexAuthPreview
                ),
                ProviderPreviewBlockData(
                    title: "config.toml (TOML)",
                    subtitle: "增量更新根字段，保留已有 MCP 配置",
                    content: buildCodexTomlPreview(),
                    onApply: applyCodexTomlPreview
                )
            ]
        case .gemini:
            return [
                ProviderPreviewBlockData(
                    title: ".env",
                    subtitle: "写入 `~/.gemini/.env`",
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
                                        .fill(selection.wrappedValue == modelID ? accentTint.opacity(0.18) : Color.primary.opacity(0.06))
                                        .overlay(
                                            RoundedRectangle(cornerRadius: 8, style: .continuous)
                                                .strokeBorder(selection.wrappedValue == modelID ? accentTint.opacity(0.35) : Color.primary.opacity(0.08), lineWidth: 1)
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
        lines.append("# 其他段落（如 [mcp_servers.xxx]）会被保留")
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
        modelFetchStatus = "正在获取模型列表..."

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
                    modelFetchStatus = models.isEmpty ? "接口已响应，但没有返回可用模型，可手动填写。" : "已获取 \(models.count) 个模型"
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
        emphasis: Bool = false,
        @ViewBuilder content: () -> Content
    ) -> some View {
        VStack(alignment: .leading, spacing: 12) {
            if let title {
                VStack(alignment: .leading, spacing: 3) {
                    Text(title)
                        .font(.subheadline.weight(.semibold))
                        .foregroundStyle(.primary)
                    if let subtitle {
                        Text(subtitle)
                            .font(.caption)
                            .foregroundStyle(.secondary)
                    }
                }
            }
            content()
        }
        .padding(14)
        .cardSurface(cornerRadius: 14, tint: accentTint.opacity(emphasis ? 0.05 : 0.025))
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
                    .font(.caption.weight(.semibold))
                    .foregroundStyle(.primary)
                Spacer(minLength: 0)
                if let url = trailingLink {
                    Link(trailingLinkLabel, destination: url)
                        .font(.caption)
                        .foregroundStyle(accentTint)
                }
            }
            content()
        }
    }
}

private struct ProviderPreviewBlockData {
    let title: String
    let subtitle: String
    let content: String
    let onApply: (String) throws -> Void
}

private struct ProviderConfigPreviewBlock: View {
    let title: String
    let subtitle: String
    let content: String
    let accent: Color
    let onApply: (String) throws -> Void

    @State private var draft: String
    @State private var lastGeneratedContent: String
    @State private var statusMessage: String?
    @State private var statusIsError = false

    init(
        title: String,
        subtitle: String,
        content: String,
        accent: Color,
        onApply: @escaping (String) throws -> Void
    ) {
        self.title = title
        self.subtitle = subtitle
        self.content = content
        self.accent = accent
        self.onApply = onApply
        _draft = State(initialValue: content)
        _lastGeneratedContent = State(initialValue: content)
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 10) {
            HStack(alignment: .center, spacing: 10) {
                VStack(alignment: .leading, spacing: 2) {
                    HStack(spacing: 6) {
                        Text(title)
                            .font(.caption.weight(.semibold))
                            .foregroundStyle(.primary)
                        ProviderConfigBadge(text: "可编辑", tint: accent)
                    }
                    Text(subtitle)
                        .font(.caption2)
                        .foregroundStyle(.secondary)
                        .lineLimit(1)
                }

                Spacer(minLength: 0)

                HStack(spacing: 6) {
                    Button("复制") {
                        NSPasteboard.general.clearContents()
                        NSPasteboard.general.setString(draft, forType: .string)
                        statusIsError = false
                        statusMessage = "已复制"
                    }
                    .aimenuActionButtonStyle(density: .compact)

                    Button("还原") {
                        draft = content
                        lastGeneratedContent = content
                        statusMessage = nil
                        statusIsError = false
                    }
                    .aimenuActionButtonStyle(density: .compact)
                    .disabled(draft == content)

                    Button("应用") {
                        applyDraft()
                    }
                    .aimenuActionButtonStyle(prominent: true, tint: accent, density: .compact)
                }
            }

            HStack(spacing: 8) {
                HStack(spacing: 6) {
                    Image(systemName: statusIsError ? "exclamationmark.circle.fill" : "pencil.tip.crop.circle")
                        .font(.caption2)
                    Text(statusMessage ?? "可直接修改内容后点应用")
                        .font(.caption2)
                        .lineLimit(1)
                }
                .foregroundStyle(statusIsError ? .red : .secondary)

                Spacer(minLength: 0)

                ProviderConfigBadge(text: "实时可编辑", tint: accent)
            }

            TextEditor(text: $draft)
                .font(.system(size: 12, weight: .regular, design: .monospaced))
                .foregroundStyle(.primary.opacity(0.92))
                .scrollContentBackground(.hidden)
                .padding(12)
                .frame(minHeight: 320, alignment: .topLeading)
                .cardSurface(cornerRadius: 12, tint: accent.opacity(0.04))
        }
        .padding(12)
        .cardSurface(cornerRadius: 14, tint: accent.opacity(0.03))
        .onChange(of: content) { _, newValue in
            if draft == lastGeneratedContent {
                draft = newValue
            }
            lastGeneratedContent = newValue
        }
    }

    private func applyDraft() {
        do {
            try onApply(draft)
            lastGeneratedContent = draft
            statusIsError = false
            statusMessage = "已应用到表单"
        } catch {
            statusIsError = true
            statusMessage = error.localizedDescription
        }
    }
}

private struct ProviderModelInputRow: View {
    let title: String
    let placeholder: String
    @Binding var text: String
    let isFetching: Bool
    let canFetch: Bool
    let accent: Color
    let onFetch: () -> Void

    var body: some View {
        HStack(alignment: .bottom, spacing: 10) {
            VStack(alignment: .leading, spacing: 6) {
                Text(title)
                    .font(.caption.weight(.semibold))
                    .foregroundStyle(.primary)
                TextField(placeholder, text: $text)
                    .frostedRoundedInput(cornerRadius: 10)
            }
            .frame(maxWidth: .infinity, alignment: .leading)

            Button {
                onFetch()
            } label: {
                HStack(spacing: 6) {
                    if isFetching {
                        ProgressView()
                            .controlSize(.small)
                    } else {
                        Image(systemName: "arrow.clockwise")
                            .font(.caption.weight(.semibold))
                    }
                    Text("自动获取模型")
                        .font(.caption.weight(.semibold))
                }
                .lineLimit(1)
            }
            .aimenuActionButtonStyle(prominent: true, tint: accent, density: .compact)
            .disabled(!canFetch || isFetching)
        }
        .padding(10)
        .cardSurface(cornerRadius: 12, tint: accent.opacity(0.035))
    }
}

private struct ProviderConfigBadge: View {
    let text: String
    let tint: Color

    var body: some View {
        Text(text)
            .font(.system(size: 10, weight: .semibold))
            .foregroundStyle(tint == .secondary ? .secondary : tint)
            .padding(.horizontal, 8)
            .padding(.vertical, 4)
            .background(
                Capsule()
                    .fill((tint == .secondary ? Color.primary : tint).opacity(0.1))
            )
    }
}

private struct ClaudeCommonConfigControls: View {
    @Binding var hideAttribution: Bool
    @Binding var alwaysThinking: Bool
    @Binding var enableTeammates: Bool
    @Binding var applyCommonConfig: Bool
    @Binding var showCommonConfigEditor: Bool
    let accent: Color

    var body: some View {
        VStack(alignment: .leading, spacing: 10) {
            Text("常用开关")
                .font(.caption.weight(.semibold))
                .foregroundStyle(.secondary)

            HStack(alignment: .top, spacing: 12) {
                claudeQuickToggle("隐藏 Attribution", isOn: $hideAttribution)
                claudeQuickToggle("开启 Thinking", isOn: $alwaysThinking)
                claudeQuickToggle("启用 Teammates", isOn: $enableTeammates)
            }
            .font(.subheadline)

            HStack(alignment: .center, spacing: 12) {
                Toggle("写入通用配置", isOn: $applyCommonConfig)
                    .toggleStyle(.checkbox)
                    .font(.subheadline)

                Button(showCommonConfigEditor ? "收起通用配置" : "编辑通用配置") {
                    if !applyCommonConfig {
                        applyCommonConfig = true
                    }
                    withAnimation(.easeInOut(duration: 0.18)) {
                        showCommonConfigEditor.toggle()
                    }
                }
                .aimenuActionButtonStyle(density: .compact)

                Spacer(minLength: 0)
            }

            Text("`hooks` 会和 Hooks 页面共用同一字段，谁最后写入就以谁为准。")
                .font(.caption2)
                .foregroundStyle(.secondary)
        }
        .padding(12)
        .cardSurface(cornerRadius: 12, tint: accent.opacity(0.025))
    }

    private func claudeQuickToggle(_ title: String, isOn: Binding<Bool>) -> some View {
        Toggle(title, isOn: isOn)
            .toggleStyle(.checkbox)
            .frame(maxWidth: .infinity, alignment: .leading)
    }
}

private enum ProviderModelCatalogService {
    private enum ResponseStyle {
        case openAI
        case anthropic
        case gemini
    }

    private struct Endpoint {
        let url: URL
        let style: ResponseStyle
    }

    static func fetch(
        appType: ProviderAppType,
        baseUrl: String,
        apiKey: String,
        claudeApiFormat: ClaudeApiFormat?
    ) async throws -> [String] {
        let endpoint = try resolveEndpoint(
            appType: appType,
            baseUrl: baseUrl.trimmingCharacters(in: .whitespacesAndNewlines),
            apiKey: apiKey.trimmingCharacters(in: .whitespacesAndNewlines),
            claudeApiFormat: claudeApiFormat
        )
        var request = URLRequest(url: endpoint.url, timeoutInterval: 15)
        request.httpMethod = "GET"

        switch endpoint.style {
        case .openAI:
            request.setValue("Bearer \(apiKey)", forHTTPHeaderField: "Authorization")
        case .anthropic:
            request.setValue(apiKey, forHTTPHeaderField: "x-api-key")
            request.setValue("2023-06-01", forHTTPHeaderField: "anthropic-version")
        case .gemini:
            break
        }

        let (data, response) = try await URLSession.shared.data(for: request)
        guard let httpResponse = response as? HTTPURLResponse else {
            throw ProviderModelFetchServiceError.invalidResponse
        }
        guard (200..<300).contains(httpResponse.statusCode) else {
            throw ProviderModelFetchServiceError.httpStatus(httpResponse.statusCode)
        }

        let models = try parseModels(from: data, style: endpoint.style)
        return Array(Set(models)).sorted { $0.localizedStandardCompare($1) == .orderedAscending }
    }

    private static func resolveEndpoint(
        appType: ProviderAppType,
        baseUrl: String,
        apiKey: String,
        claudeApiFormat: ClaudeApiFormat?
    ) throws -> Endpoint {
        switch appType {
        case .claude:
            if claudeApiFormat == .anthropic {
                return Endpoint(url: try anthropicModelsURL(from: baseUrl), style: .anthropic)
            }
            return Endpoint(url: try openAIModelsURL(from: baseUrl, officialHostHint: "openai.com"), style: .openAI)
        case .codex:
            return Endpoint(url: try openAIModelsURL(from: baseUrl, officialHostHint: "openai.com"), style: .openAI)
        case .gemini:
            if baseUrl.contains("generativelanguage.googleapis.com") {
                return Endpoint(url: try geminiModelsURL(from: baseUrl, apiKey: apiKey), style: .gemini)
            }
            return Endpoint(url: try openAIModelsURL(from: baseUrl, officialHostHint: "openai.com"), style: .openAI)
        }
    }

    private static func openAIModelsURL(from baseUrl: String, officialHostHint: String) throws -> URL {
        guard var components = URLComponents(string: baseUrl) else {
            throw ProviderModelFetchServiceError.invalidBaseURL
        }
        let trimmedPath = components.path.trimmingCharacters(in: CharacterSet(charactersIn: "/"))
        let lowercasedPath = trimmedPath.lowercased()
        let host = components.host?.lowercased() ?? ""

        if lowercasedPath.hasSuffix("models") {
            guard let url = components.url else {
                throw ProviderModelFetchServiceError.invalidBaseURL
            }
            return url
        }

        let newPath: String
        if lowercasedPath.isEmpty, host.contains(officialHostHint) {
            newPath = "/v1/models"
        } else if lowercasedPath.hasSuffix("v1") || lowercasedPath.hasSuffix("v1beta") || lowercasedPath.hasSuffix("v1alpha") {
            newPath = "/\(trimmedPath)/models"
        } else if trimmedPath.isEmpty {
            newPath = "/models"
        } else {
            newPath = "/\(trimmedPath)/models"
        }
        components.path = newPath.replacingOccurrences(of: "//", with: "/")
        guard let url = components.url else {
            throw ProviderModelFetchServiceError.invalidBaseURL
        }
        return url
    }

    private static func anthropicModelsURL(from baseUrl: String) throws -> URL {
        guard var components = URLComponents(string: baseUrl) else {
            throw ProviderModelFetchServiceError.invalidBaseURL
        }
        let trimmedPath = components.path.trimmingCharacters(in: CharacterSet(charactersIn: "/"))
        let lowercasedPath = trimmedPath.lowercased()

        let newPath: String
        if lowercasedPath.hasSuffix("v1/models") {
            newPath = "/\(trimmedPath)"
        } else if lowercasedPath.hasSuffix("v1") {
            newPath = "/\(trimmedPath)/models"
        } else if trimmedPath.isEmpty {
            newPath = "/v1/models"
        } else {
            newPath = "/\(trimmedPath)/v1/models"
        }
        components.path = newPath.replacingOccurrences(of: "//", with: "/")
        guard let url = components.url else {
            throw ProviderModelFetchServiceError.invalidBaseURL
        }
        return url
    }

    private static func geminiModelsURL(from baseUrl: String, apiKey: String) throws -> URL {
        guard var components = URLComponents(string: baseUrl) else {
            throw ProviderModelFetchServiceError.invalidBaseURL
        }
        let trimmedPath = components.path.trimmingCharacters(in: CharacterSet(charactersIn: "/"))
        let lowercasedPath = trimmedPath.lowercased()

        let newPath: String
        if lowercasedPath.hasSuffix("models") {
            newPath = "/\(trimmedPath)"
        } else if lowercasedPath.hasSuffix("v1beta") || lowercasedPath.hasSuffix("v1") || lowercasedPath.hasSuffix("v1alpha") {
            newPath = "/\(trimmedPath)/models"
        } else if trimmedPath.isEmpty {
            newPath = "/v1beta/models"
        } else {
            newPath = "/\(trimmedPath)/models"
        }
        components.path = newPath.replacingOccurrences(of: "//", with: "/")
        var items = components.queryItems ?? []
        if !apiKey.isEmpty {
            items.append(URLQueryItem(name: "key", value: apiKey))
        }
        components.queryItems = items.isEmpty ? nil : items
        guard let url = components.url else {
            throw ProviderModelFetchServiceError.invalidBaseURL
        }
        return url
    }

    private static func parseModels(from data: Data, style: ResponseStyle) throws -> [String] {
        let object = try JSONSerialization.jsonObject(with: data)
        guard let dictionary = object as? [String: Any] else {
            throw ProviderModelFetchServiceError.unsupportedResponse
        }

        switch style {
        case .openAI, .anthropic:
            let list = (dictionary["data"] as? [[String: Any]]) ?? (dictionary["models"] as? [[String: Any]]) ?? []
            let ids = list.compactMap { item -> String? in
                (item["id"] as? String)?.trimmedNonEmpty ?? (item["name"] as? String)?.trimmedNonEmpty
            }
            guard !ids.isEmpty else {
                throw ProviderModelFetchServiceError.unsupportedResponse
            }
            return ids
        case .gemini:
            let list = (dictionary["models"] as? [[String: Any]]) ?? []
            let ids = list.compactMap { item -> String? in
                if let name = (item["name"] as? String)?.trimmedNonEmpty {
                    return name.replacingOccurrences(of: "models/", with: "")
                }
                return (item["id"] as? String)?.trimmedNonEmpty
            }
            guard !ids.isEmpty else {
                throw ProviderModelFetchServiceError.unsupportedResponse
            }
            return ids
        }
    }
}

private enum ProviderModelFetchServiceError: LocalizedError {
    case invalidBaseURL
    case invalidResponse
    case httpStatus(Int)
    case unsupportedResponse

    var errorDescription: String? {
        switch self {
        case .invalidBaseURL:
            return "接口地址无效，无法获取模型列表。"
        case .invalidResponse:
            return "模型接口返回异常，请稍后重试。"
        case .httpStatus(let code):
            return "获取模型失败（HTTP \(code)），请检查接口地址和 API Key。"
        case .unsupportedResponse:
            return "当前接口没有返回可识别的模型列表，可手动填写模型名。"
        }
    }
}

private extension ProviderAppType {
    var formAccent: Color {
        switch self {
        case .claude:
            return Color(hex: "#D4915D")
        case .codex:
            return Color(hex: "#3A82F7")
        case .gemini:
            return Color(hex: "#1FA67A")
        }
    }

    var defaultBaseURL: String {
        switch self {
        case .claude:
            return "https://api.anthropic.com"
        case .codex:
            return "https://api.openai.com"
        case .gemini:
            return "https://generativelanguage.googleapis.com/v1beta"
        }
    }

    var liveConfigPathsText: String {
        switch self {
        case .claude:
            return "~/.claude/settings.json"
        case .codex:
            return "~/.codex/auth.json + ~/.codex/config.toml"
        case .gemini:
            return "~/.gemini/.env"
        }
    }
}

private func prettyJSONString(_ object: [String: Any]) -> String {
    guard JSONSerialization.isValidJSONObject(object),
          let data = try? JSONSerialization.data(withJSONObject: object, options: [.prettyPrinted, .sortedKeys]),
          let string = String(data: data, encoding: .utf8) else {
        return "{}"
    }
    return string
}

private func parsedJSONObjectString(_ text: String) -> [String: Any]? {
    guard let normalized = text.trimmedNonEmpty,
          let data = normalized.data(using: .utf8),
          let object = try? JSONSerialization.jsonObject(with: data) as? [String: Any] else {
        return nil
    }
    return object
}

private func normalizedJSONObjectString(_ text: String) -> String? {
    guard let object = parsedJSONObjectString(text) else { return nil }
    return prettyJSONString(object)
}

private func extractClaudeCommonConfig(from payload: [String: Any]) -> [String: Any] {
    var common = payload
    common.removeValue(forKey: "env")
    common.removeValue(forKey: "attribution")
    common.removeValue(forKey: "alwaysThinkingEnabled")
    return common
}

private func tomlQuoted(_ value: String) -> String {
    let escaped = value
        .replacingOccurrences(of: "\\", with: "\\\\")
        .replacingOccurrences(of: "\"", with: "\\\"")
    return "\"\(escaped)\""
}

private func dotenvEscaped(_ value: String) -> String {
    if value.contains(" ") || value.contains("#") {
        return "\"\(value.replacingOccurrences(of: "\"", with: "\\\""))\""
    }
    return value
}

private enum ProviderPreviewParseError: LocalizedError {
    case invalidJSON
    case invalidJSONObject
    case invalidTOML
    case invalidDotEnv

    var errorDescription: String? {
        switch self {
        case .invalidJSON:
            return "JSON 内容无效，请检查逗号和引号。"
        case .invalidJSONObject:
            return "需要顶层对象格式，不能只粘贴数组或片段。"
        case .invalidTOML:
            return "TOML 解析失败，请保持 `key = value` 的根字段格式。"
        case .invalidDotEnv:
            return "ENV 解析失败，请保持 `KEY=value` 格式。"
        }
    }
}

private func parsePreviewJSONObject(_ text: String) throws -> [String: Any] {
    guard let data = text.data(using: .utf8) else {
        throw ProviderPreviewParseError.invalidJSON
    }
    let object: Any
    do {
        object = try JSONSerialization.jsonObject(with: data)
    } catch {
        throw ProviderPreviewParseError.invalidJSON
    }
    guard let dictionary = object as? [String: Any] else {
        throw ProviderPreviewParseError.invalidJSONObject
    }
    return dictionary
}

private func previewString(_ value: Any?) -> String? {
    switch value {
    case let string as String:
        let trimmed = string.trimmingCharacters(in: .whitespacesAndNewlines)
        return trimmed.isEmpty ? nil : trimmed
    case let number as NSNumber:
        return number.stringValue
    default:
        return nil
    }
}

private func previewBool(_ value: Any?) -> Bool {
    switch value {
    case let bool as Bool:
        return bool
    case let string as String:
        return ["1", "true", "yes", "on"].contains(string.trimmingCharacters(in: .whitespacesAndNewlines).lowercased())
    case let number as NSNumber:
        return number.boolValue
    default:
        return false
    }
}

private func parsePreviewTOML(_ text: String) throws -> [String: String] {
    var result: [String: String] = [:]

    for rawLine in text.components(separatedBy: .newlines) {
        let line = rawLine.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !line.isEmpty, !line.hasPrefix("#"), !line.hasPrefix("[") else { continue }
        let parts = line.split(separator: "=", maxSplits: 1).map(String.init)
        guard parts.count == 2 else { continue }
        let key = parts[0].trimmingCharacters(in: .whitespacesAndNewlines)
        let value = previewUnquoted(parts[1].trimmingCharacters(in: .whitespacesAndNewlines))
        guard !key.isEmpty else { continue }
        result[key] = value
    }

    guard !result.isEmpty else {
        throw ProviderPreviewParseError.invalidTOML
    }
    return result
}

private func parsePreviewDotEnv(_ text: String) throws -> [String: String] {
    var result: [String: String] = [:]

    for rawLine in text.components(separatedBy: .newlines) {
        let line = rawLine.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !line.isEmpty, !line.hasPrefix("#") else { continue }
        let parts = line.split(separator: "=", maxSplits: 1).map(String.init)
        guard parts.count == 2 else { continue }
        let key = parts[0].trimmingCharacters(in: .whitespacesAndNewlines)
        let value = previewUnquoted(parts[1].trimmingCharacters(in: .whitespacesAndNewlines))
        guard !key.isEmpty else { continue }
        result[key] = value
    }

    guard !result.isEmpty else {
        throw ProviderPreviewParseError.invalidDotEnv
    }
    return result
}

private func previewUnquoted(_ value: String) -> String {
    var trimmed = value.trimmingCharacters(in: .whitespacesAndNewlines)
    if trimmed.hasPrefix("\""), trimmed.hasSuffix("\""), trimmed.count >= 2 {
        trimmed.removeFirst()
        trimmed.removeLast()
        trimmed = trimmed.replacingOccurrences(of: "\\\"", with: "\"")
    }
    return trimmed
}

// MARK: - Preset Row

private struct PresetRow: View {
    let preset: ProviderPreset
    let isSelected: Bool
    let accent: Color

    private var rowTint: Color {
        if let hex = preset.iconColor {
            return Color(hex: hex)
        }
        return accent
    }

    private var hostLabel: String? {
        guard let baseURL = preset.baseUrl?.trimmingCharacters(in: .whitespacesAndNewlines),
              !baseURL.isEmpty else {
            return preset.category == .custom ? "手动填写地址与模型" : nil
        }
        return URL(string: baseURL)?.host ?? baseURL
    }

    private var defaultModelLabel: String? {
        preset.defaultModel?.trimmedNonEmpty
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 11) {
            HStack(alignment: .top, spacing: 10) {
                Image(systemName: preset.icon ?? "server.rack")
                    .font(.system(size: 14, weight: .semibold))
                    .foregroundStyle(isSelected ? rowTint : .secondary)
                    .frame(width: 34, height: 34)
                    .background(
                        RoundedRectangle(cornerRadius: 10, style: .continuous)
                            .fill(
                                isSelected
                                    ? rowTint.opacity(0.16)
                                    : Color.primary.opacity(0.05)
                            )
                    )

                VStack(alignment: .leading, spacing: 6) {
                    Text(preset.name)
                        .font(.system(size: 12, weight: .semibold))
                        .foregroundStyle(isSelected ? rowTint : .primary)
                        .lineLimit(2)

                    HStack(spacing: 6) {
                        Text(preset.category.displayName)
                            .font(.caption2.weight(.semibold))
                            .foregroundStyle(isSelected ? rowTint : .secondary)
                            .padding(.horizontal, 6)
                            .padding(.vertical, 3)
                            .background((isSelected ? rowTint : Color.primary).opacity(isSelected ? 0.12 : 0.06), in: Capsule())

                        if preset.isPartner {
                            Text("渠道")
                                .font(.caption2.weight(.semibold))
                                .foregroundStyle(.secondary)
                                .padding(.horizontal, 6)
                                .padding(.vertical, 3)
                                .background(Color.primary.opacity(0.05), in: Capsule())
                        }
                    }
                }

                Spacer(minLength: 0)

                Image(systemName: isSelected ? "checkmark.circle.fill" : "arrow.up.right.circle")
                    .font(.caption.weight(.semibold))
                    .foregroundStyle(isSelected ? rowTint : Color.secondary.opacity(0.7))
            }

            VStack(alignment: .leading, spacing: 6) {
                if let hostLabel {
                    presetInfoRow(icon: "network", text: hostLabel)
                }
                if let defaultModelLabel {
                    presetInfoRow(icon: "sparkles", text: defaultModelLabel)
                }
            }
        }
        .frame(maxWidth: .infinity)
        .frame(minHeight: 108, alignment: .topLeading)
        .padding(13)
        .background(
            RoundedRectangle(cornerRadius: 14, style: .continuous)
                .fill(
                    LinearGradient(
                        colors: [
                            isSelected ? rowTint.opacity(0.17) : Color.primary.opacity(0.05),
                            Color.primary.opacity(isSelected ? 0.028 : 0.02)
                        ],
                        startPoint: .topLeading,
                        endPoint: .bottomTrailing
                    )
                )
                .overlay(
                    RoundedRectangle(cornerRadius: 14, style: .continuous)
                        .strokeBorder(isSelected ? rowTint.opacity(0.42) : Color.primary.opacity(0.08), lineWidth: 1)
                )
        )
        .contentShape(RoundedRectangle(cornerRadius: 14))
    }

    private func presetInfoRow(icon: String, text: String) -> some View {
        HStack(spacing: 6) {
            Image(systemName: icon)
                .font(.caption2.weight(.semibold))
                .foregroundStyle(isSelected ? rowTint : Color.secondary.opacity(0.7))
            Text(text)
                .font(.caption2)
                .foregroundStyle(.secondary)
                .lineLimit(1)
                .truncationMode(.middle)
        }
    }
}

// MARK: - Color Hex Init

private extension Color {
    init(hex: String) {
        let cleaned = hex.trimmingCharacters(in: CharacterSet(charactersIn: "#"))
        var rgb: UInt64 = 0
        Scanner(string: cleaned).scanHexInt64(&rgb)
        let r = Double((rgb >> 16) & 0xFF) / 255
        let g = Double((rgb >> 8) & 0xFF) / 255
        let b = Double(rgb & 0xFF) / 255
        self.init(red: r, green: g, blue: b)
    }
}
