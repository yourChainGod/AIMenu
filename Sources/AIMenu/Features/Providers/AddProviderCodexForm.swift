import SwiftUI

// MARK: - AddProviderSheet + Codex Configuration Section

extension AddProviderSheet {

    var codexSection: some View {
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
                            selection: $codex.wireApi,
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
}
