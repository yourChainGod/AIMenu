import SwiftUI

// MARK: - AddProviderSheet + Claude Configuration Section

extension AddProviderSheet {

    var claudeSection: some View {
        VStack(alignment: .leading, spacing: 12) {
            configSectionCard(title: L10n.tr("providers.section.claude.title"), subtitle: L10n.tr("providers.section.claude.subtitle"), icon: "sparkles.rectangle.stack.fill") {
                configField(label: L10n.tr("providers.field.api_format"), hint: nil, hintLabel: nil) {
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
                configField(label: L10n.tr("providers.field.auth_field"), hint: nil, hintLabel: nil) {
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
                            configField(label: L10n.tr("providers.field.haiku_default_model"), hint: nil, hintLabel: nil) {
                                TextField(L10n.tr("providers.placeholder.optional_override"), text: $claude.haikuModel)
                                    .frostedRoundedInput(cornerRadius: 10)
                            }
                            .frame(maxWidth: .infinity, alignment: .leading)

                            configField(label: L10n.tr("providers.field.sonnet_default_model"), hint: nil, hintLabel: nil) {
                                TextField(L10n.tr("providers.placeholder.optional_override"), text: $claude.sonnetModel)
                                    .frostedRoundedInput(cornerRadius: 10)
                            }
                            .frame(maxWidth: .infinity, alignment: .leading)
                        }
                        HStack(alignment: .top, spacing: 12) {
                            configField(label: L10n.tr("providers.field.opus_default_model"), hint: nil, hintLabel: nil) {
                                TextField(L10n.tr("providers.placeholder.optional_override"), text: $claude.opusModel)
                                    .frostedRoundedInput(cornerRadius: 10)
                            }
                            .frame(maxWidth: .infinity, alignment: .leading)

                            configField(label: L10n.tr("providers.field.max_output_tokens"), hint: nil, hintLabel: nil) {
                                TextField(L10n.tr("providers.placeholder.use_default"), text: $claude.maxOutputTokens)
                                    .frostedRoundedInput(cornerRadius: 10)
                            }
                            .frame(maxWidth: .infinity, alignment: .leading)
                        }
                        configField(label: L10n.tr("providers.field.timeout_ms"), hint: nil, hintLabel: nil) {
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
}
