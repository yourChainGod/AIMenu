import SwiftUI

// MARK: - AddProviderSheet + Gemini Configuration Section

extension AddProviderSheet {

    var geminiSection: some View {
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
}
