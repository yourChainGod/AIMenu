import SwiftUI

// MARK: - AddProviderSheet + Config Preview, Proxy & Billing Sections

extension AddProviderSheet {

    // MARK: - Config Preview

    var configPreviewSection: some View {
        configSectionCard(title: L10n.tr("providers.preview.section_title"), subtitle: previewSubtitle, icon: "doc.text.magnifyingglass") {
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
                .padding(10)
                .providerInsetSurface(accent: accentTint)
            }
            .buttonStyle(.plain)

            if showConfigPreview {
                if appType == .claude {
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

    // MARK: - Proxy

    var proxySection: some View {
        configSectionCard(title: L10n.tr("providers.section.proxy.title"), subtitle: L10n.tr("providers.section.proxy.subtitle"), icon: "point.3.filled.connected.trianglepath.dotted") {
            Button {
                withAnimation(AnimationPreset.quick) { showProxyConfig.toggle() }
            } label: {
                HStack {
                    Text(showProxyConfig ? L10n.tr("providers.action.collapse_proxy") : L10n.tr("providers.action.expand_proxy"))
                        .font(.subheadline.weight(.semibold))
                        .foregroundStyle(.primary)
                    Spacer(minLength: 0)
                    if proxyEnabled {
                        UnifiedBadge(text: L10n.tr("providers.status.enabled"), tint: .orange)
                    }
                    Image(systemName: "chevron.right")
                        .font(.caption.weight(.semibold))
                        .foregroundStyle(.tertiary)
                        .rotationEffect(.degrees(showProxyConfig ? 90 : 0))
                }
                .padding(10)
                .providerInsetSurface(accent: accentTint)
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

    // MARK: - Billing

    var billingSection: some View {
        configSectionCard(title: L10n.tr("providers.section.billing.title"), subtitle: L10n.tr("providers.section.billing.subtitle"), icon: "banknote.fill") {
            Button {
                withAnimation(AnimationPreset.quick) { showBillingConfig.toggle() }
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
                .padding(10)
                .providerInsetSurface(accent: accentTint)
            }
            .buttonStyle(.plain)

            if showBillingConfig {
                VStack(alignment: .leading, spacing: 12) {
                    HStack(alignment: .top, spacing: 12) {
                        configField(label: L10n.tr("providers.field.billing_input_price"), hint: nil, hintLabel: nil) {
                            TextField(L10n.tr("providers.placeholder.price_input_example"), text: $billing.inputPrice)
                                .frostedRoundedInput(cornerRadius: 10)
                        }
                        .frame(maxWidth: .infinity, alignment: .leading)

                        configField(label: L10n.tr("providers.field.billing_output_price"), hint: nil, hintLabel: nil) {
                            TextField(L10n.tr("providers.placeholder.price_output_example"), text: $billing.outputPrice)
                                .frostedRoundedInput(cornerRadius: 10)
                        }
                        .frame(maxWidth: .infinity, alignment: .leading)
                    }
                    configField(label: L10n.tr("providers.field.notes"), hint: nil, hintLabel: nil) {
                        TextField(L10n.tr("providers.field.notes_placeholder"), text: $billing.notes)
                            .frostedRoundedInput(cornerRadius: 10)
                    }
                }
                .padding(.top, 2)
            }
        }
    }
}
