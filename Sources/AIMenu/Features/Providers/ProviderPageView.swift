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
        min(28, max(8, height * 0.04))
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
                            ProviderConfigBadge(text: L10n.tr("providers.badge.managed"), tint: .mint)
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
                        Text(L10n.tr("providers.badge.current"))
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
                        providerFeatureChip(text: L10n.tr("providers.badge.proxy"), tint: .orange)
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
                        Text(L10n.tr("providers.speed.not_tested"))
                            .font(.system(size: 10, weight: .medium))
                            .foregroundStyle(.tertiary)
                    }
                }

                HStack(spacing: 4) {
                    if !provider.isCurrent {
                        providerTinyButton(icon: "checkmark", tint: .mint, tooltip: L10n.tr("providers.tooltip.switch")) {
                            Task { await model.switchProvider(provider) }
                        }
                    }
                    providerTinyButton(icon: "bolt", tint: .orange, tooltip: L10n.tr("providers.tooltip.speed_test")) {
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
                    .fill(Color(nsColor: .windowBackgroundColor).opacity(0.97))
                RoundedRectangle(cornerRadius: 22, style: .continuous)
                    .fill(
                        LinearGradient(
                            colors: [
                                accent.opacity(0.14),
                                accent.opacity(0.045),
                                Color.white.opacity(0.02)
                            ],
                            startPoint: .topLeading,
                            endPoint: .bottomTrailing
                        )
                    )
                VStack(spacing: 0) {
                    RoundedRectangle(cornerRadius: 22, style: .continuous)
                        .fill(
                            LinearGradient(
                                colors: [
                                    Color.white.opacity(0.24),
                                    Color.white.opacity(0.02),
                                    Color.clear
                                ],
                                startPoint: .top,
                                endPoint: .bottom
                            )
                        )
                        .frame(height: 110)
                    Spacer(minLength: 0)
                }
                RoundedRectangle(cornerRadius: 22, style: .continuous)
                    .strokeBorder(
                        LinearGradient(
                            colors: [
                                accent.opacity(0.28),
                                Color.white.opacity(0.14),
                                Color.black.opacity(0.06)
                            ],
                            startPoint: .topLeading,
                            endPoint: .bottomTrailing
                        ),
                        lineWidth: 1
                    )
            }
        }
        .clipShape(RoundedRectangle(cornerRadius: 22, style: .continuous))
        .shadow(color: accent.opacity(0.12), radius: 16, x: 0, y: 6)
        .shadow(color: .black.opacity(0.14), radius: 28, x: 0, y: 14)
    }
}
