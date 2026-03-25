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
                ModalOverlay(accent: model.selectedApp.formAccent, onDismiss: closeAddProviderSheet) {
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
                ModalOverlay(accent: editing.appType.formAccent, onDismiss: { model.editingProvider = nil }) {
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
        .animation(AnimationPreset.sheet, value: hasActiveModal)
    }

    private var pageContent: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: LayoutRules.sectionSpacing) {
                toolBar
                    .padding(.horizontal, LayoutRules.pagePadding)

                if !model.providers.isEmpty {
                    providerSummaryPanel
                        .padding(.horizontal, LayoutRules.pagePadding)
                    providerSearchField
                        .padding(.horizontal, LayoutRules.pagePadding)
                }

                if model.loading && model.providers.isEmpty {
                    ProgressView(L10n.tr("providers.loading"))
                        .frame(maxWidth: .infinity, minHeight: 120)
                        .padding(.horizontal, LayoutRules.pagePadding)
                } else if model.providers.isEmpty {
                    EmptyStateView(
                        title: L10n.tr("providers.empty.title"),
                        message: L10n.tr("providers.empty.message_format", model.selectedApp.displayName),
                        icon: model.selectedApp.iconName,
                        tint: pageAccent
                    )
                    .padding(.horizontal, LayoutRules.pagePadding)
                } else if model.filteredProviders.isEmpty {
                    ContentUnavailableView.search(text: model.providerSearchText)
                        .frame(maxWidth: .infinity, minHeight: 180)
                        .padding(.horizontal, LayoutRules.pagePadding)
                } else {
                    LazyVStack(spacing: 2) {
                        ForEach(model.filteredProviders) { provider in
                            providerRow(provider)
                                .draggable(provider.id) {
                                    // Drag preview: icon + name in a card chip
                                    HStack(spacing: 6) {
                                        Image(systemName: provider.icon ?? model.selectedApp.iconName)
                                            .font(.caption2)
                                        Text(provider.name)
                                            .font(.caption.weight(.medium))
                                    }
                                    .padding(.horizontal, 10)
                                    .padding(.vertical, 6)
                                    .background(Color(nsColor: .controlBackgroundColor), in: RoundedRectangle(cornerRadius: 8))
                                    .shadow(color: .black.opacity(0.15), radius: 4, y: 2)
                                }
                                .dropDestination(for: String.self) { droppedIDs, _ in
                                    guard let draggedID = droppedIDs.first, draggedID != provider.id else { return false }
                                    Task { await model.moveProvider(draggedID: draggedID, toID: provider.id) }
                                    return true
                                }
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

    // MARK: - Toolbar (App Picker + Actions)

    private var pageAccent: Color {
        model.selectedApp.formAccent
    }

    private var providerSummaryPanel: some View {
        let filteredCount = model.filteredProviders.count
        let totalCount = model.providers.count
        let currentProvider = model.currentProvider
        let currentModel = currentProvider.flatMap(providerModelName)
        let currentHost = currentProvider.flatMap(providerEndpointHost)

        return VStack(alignment: .leading, spacing: 10) {
            HStack(alignment: .top, spacing: 10) {
                VStack(alignment: .leading, spacing: 6) {
                    HStack(spacing: 6) {
                        Image(systemName: model.selectedApp.iconName)
                            .font(.caption.weight(.semibold))
                            .foregroundStyle(pageAccent)
                        Text(currentProvider?.name ?? model.selectedApp.displayName)
                            .font(.headline.weight(.semibold))
                            .lineLimit(1)
                    }

                    if let currentModel {
                        Text(currentModel)
                            .font(.system(size: 12, weight: .semibold, design: .monospaced))
                            .foregroundStyle(.secondary)
                            .lineLimit(1)
                            .truncationMode(.middle)
                    }
                }

                Spacer(minLength: 0)

                if !model.providers.isEmpty {
                    Button {
                        Task { await model.speedTestAll() }
                    } label: {
                        Label(L10n.tr("providers.action.speed_test_all"), systemImage: "bolt.horizontal.fill")
                            .lineLimit(1)
                    }
                    .aimenuActionButtonStyle(prominent: true, tint: InterfaceAccent.remote, density: .compact)
                }
            }

            HStack(spacing: 6) {
                UnifiedBadge(
                    text: L10n.tr("providers.sheet.current_total_format", String(filteredCount), String(totalCount)),
                    tint: .secondary,
                    density: .compact
                )

                if currentProvider != nil {
                    UnifiedBadge(text: L10n.tr("providers.badge.current"), tint: pageAccent, density: .compact)
                }

                if let currentHost {
                    UnifiedBadge(text: currentHost, tint: .secondary, density: .compact)
                }
            }
        }
        .padding(12)
        .cardSurface(cornerRadius: LayoutRules.radiusCard, tint: pageAccent.opacity(OpacityScale.ghost))
    }

    private var providerSearchField: some View {
        HStack(spacing: 8) {
            Image(systemName: "magnifyingglass")
                .font(.caption.weight(.semibold))
                .foregroundStyle(.secondary)

            TextField(L10n.tr("providers.search.providers_placeholder"), text: $model.providerSearchText)
                .textFieldStyle(.plain)
                .font(.subheadline)

            if !model.providerSearchText.isEmpty {
                Button {
                    model.providerSearchText = ""
                } label: {
                    Image(systemName: "xmark.circle.fill")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }
                .buttonStyle(.plain)
            }
        }
        .padding(.horizontal, 10)
        .padding(.vertical, 9)
        .background(
            RoundedRectangle(cornerRadius: 12, style: .continuous)
                .fill(Color.primary.opacity(OpacityScale.ghost))
                .overlay(
                    RoundedRectangle(cornerRadius: 12, style: .continuous)
                        .strokeBorder(Color.primary.opacity(OpacityScale.subtle), lineWidth: 1)
                )
        )
    }

    // MARK: - Provider Row

    @ViewBuilder
    private func providerRow(_ provider: Provider) -> some View {
        let isHovered = hoveredProvider == provider.id
        let rowAccent = providerIconColor(provider)
        let isTopProvider = model.providers.first?.id == provider.id
        let isBottomProvider = model.providers.last?.id == provider.id

        HStack(alignment: .center, spacing: 10) {
            RoundedRectangle(cornerRadius: 10, style: .continuous)
                .fill((provider.isCurrent ? rowAccent : Color.primary).opacity(provider.isCurrent ? OpacityScale.medium : OpacityScale.subtle))
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
                        UnifiedBadge(
                            text: L10n.tr("providers.badge.current"),
                            tint: pageAccent,
                            density: .compact
                        )
                    }
                }

                // Model name (prominent display)
                if let modelName = providerModelName(provider) {
                    Text(modelName)
                        .font(.system(size: 11, weight: .semibold, design: .monospaced))
                        .foregroundStyle(provider.isCurrent ? rowAccent : .secondary)
                        .lineLimit(1)
                        .truncationMode(.middle)
                }

                HStack(spacing: 6) {
                    if let host = providerEndpointHost(provider) {
                        UnifiedBadge(text: host, tint: .secondary, density: .compact)
                    }
                    if provider.proxyConfig?.enabled == true {
                        UnifiedBadge(text: L10n.tr("providers.badge.proxy"), tint: InterfaceAccent.runtime, density: .compact)
                    }
                    if let billing = providerBillingSummary(provider) {
                        UnifiedBadge(text: billing, tint: .purple, density: .compact)
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
                        Text(L10n.tr("providers.speed.not_tested"))
                            .font(.system(size: 10, weight: .medium))
                            .foregroundStyle(.tertiary)
                    }
                }

                HStack(spacing: 4) {
                    if !provider.isCurrent {
                        providerTinyButton(icon: "checkmark", tint: pageAccent, tooltip: L10n.tr("providers.tooltip.switch")) {
                            Task { await model.switchProvider(provider) }
                        }
                    }
                    providerTinyButton(icon: "bolt", tint: InterfaceAccent.remote, tooltip: L10n.tr("providers.tooltip.speed_test")) {
                        Task { await model.speedTest(provider) }
                    }
                    providerTinyButton(icon: "pencil", tint: .secondary, tooltip: L10n.tr("providers.tooltip.edit")) {
                        model.editingProvider = provider
                    }
                    providerTinyButton(icon: "trash", tint: .red, tooltip: L10n.tr("providers.tooltip.delete")) {
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
                        ? rowAccent.opacity(isHovered ? OpacityScale.muted : OpacityScale.subtle)
                        : Color.primary.opacity(isHovered ? OpacityScale.faint : OpacityScale.ghost)
                )
                .overlay(
                    RoundedRectangle(cornerRadius: 12, style: .continuous)
                        .strokeBorder(
                            provider.isCurrent
                                ? rowAccent.opacity(OpacityScale.medium)
                                : Color.primary.opacity(isHovered ? OpacityScale.muted : OpacityScale.faint),
                            lineWidth: 1
                        )
                )
        )
        .contentShape(Rectangle())
        .onHover { hoveredProvider = $0 ? provider.id : nil }
        .animation(AnimationPreset.snappy, value: isHovered)
        .contextMenu {
            Button(L10n.tr("providers.action.move_to_top")) {
                Task { await model.moveProviderToTop(provider) }
            }
            .disabled(isTopProvider)

            Button(L10n.tr("providers.action.move_to_bottom")) {
                Task { await model.moveProviderToBottom(provider) }
            }
            .disabled(isBottomProvider)
        }
    }

    private func providerTinyButton(icon: String, tint: Color, tooltip: String, action: @escaping () -> Void) -> some View {
        Button(action: action) {
            Image(systemName: icon)
                .font(.system(size: 11, weight: .medium))
                .foregroundStyle(tint == .secondary ? Color.secondary : tint)
                .frame(width: 22, height: 22)
                .background(
                    RoundedRectangle(cornerRadius: 7, style: .continuous)
                        .fill(tint == .secondary ? Color.primary.opacity(OpacityScale.subtle) : tint.opacity(OpacityScale.muted))
                        .overlay(
                            RoundedRectangle(cornerRadius: 7, style: .continuous)
                                .strokeBorder((tint == .secondary ? Color.primary : tint).opacity(OpacityScale.muted), lineWidth: 1)
                        )
                )
        }
        .buttonStyle(.plain)
        .help(tooltip)
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
                    Label(L10n.tr("providers.action.add"), systemImage: "plus")
                        .lineLimit(1)
                }
                .aimenuActionButtonStyle(prominent: true, tint: pageAccent, density: .compact)

                Button {
                    Task { await model.speedTestAll() }
                } label: {
                    Label(L10n.tr("providers.action.speed_test_all"), systemImage: "bolt.horizontal.fill")
                        .lineLimit(1)
                }
                .aimenuActionButtonStyle(prominent: true, tint: InterfaceAccent.remote, density: .compact)
                .disabled(model.providers.isEmpty)

                Button {
                    Task { await model.exportProviders() }
                } label: {
                    Label(L10n.tr("providers.action.export"), systemImage: "square.and.arrow.up")
                        .lineLimit(1)
                }
                .aimenuActionButtonStyle(density: .compact)

                Button {
                    Task { await model.importProviders() }
                } label: {
                    Label(L10n.tr("providers.action.import"), systemImage: "square.and.arrow.down")
                        .lineLimit(1)
                }
                .aimenuActionButtonStyle(density: .compact)
            }
            .frame(maxWidth: 340)
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
