import SwiftUI

// MARK: - AddProviderSheet + Preset Picker Step

extension AddProviderSheet {

    var presetPickerStep: some View {
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
                .providerInsetSurface(accent: accentTint)

                HStack(spacing: 8) {
                    if searchText.isEmpty {
                        presetScopeButton(
                            title: L10n.tr("providers.scope.featured"),
                            count: featuredPresetCount,
                            isActive: !showAllPresets
                        ) {
                            withAnimation(AnimationPreset.quick) {
                                showAllPresets = false
                            }
                        }

                        if hiddenPresetCount > 0 {
                            presetScopeButton(
                                title: L10n.tr("providers.scope.all"),
                                count: filteredPresets.count,
                                isActive: showAllPresets
                            ) {
                                withAnimation(AnimationPreset.quick) {
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
                            withAnimation(AnimationPreset.quick) {
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
            .background {
                ZStack {
                    Color(nsColor: .windowBackgroundColor).opacity(0.96)
                    LinearGradient(
                        colors: [
                            Color.white.opacity(0.015),
                            accentTint.opacity(0.008),
                            Color.clear
                        ],
                        startPoint: .topLeading,
                        endPoint: .bottomTrailing
                    )
                }
            }
            .overlay(alignment: .top) {
                Rectangle()
                    .fill(Color.primary.opacity(OpacityScale.subtle))
                    .frame(height: 1)
            }
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .top)
    }

    func presetScopeButton(
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
                    .background((isActive ? accentTint : Color.primary).opacity(isActive ? 0.10 : 0.06), in: Capsule())
            }
            .lineLimit(1)
        }
        .aimenuActionButtonStyle(
            prominent: isActive,
            tint: isActive ? accentTint : nil,
            density: .compact
        )
    }

    func presetMetaBadge(icon: String, text: String, tint: Color) -> some View {
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
                .fill((tint == .secondary ? Color.primary : tint).opacity(tint == .secondary ? 0.05 : 0.08))
                .overlay(
                    Capsule()
                        .strokeBorder((tint == .secondary ? Color.primary : tint).opacity(0.10), lineWidth: 1)
                )
        )
    }
}
