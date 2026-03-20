import SwiftUI
import AppKit

struct SectionCard<Content: View, HeaderTrailing: View>: View {
    let title: String
    let icon: String?
    let iconColor: Color
    @ViewBuilder let headerTrailing: HeaderTrailing
    @ViewBuilder let content: Content

    init(
        title: String,
        icon: String? = nil,
        iconColor: Color = .accentColor,
        @ViewBuilder content: () -> Content
    ) where HeaderTrailing == EmptyView {
        self.title = title
        self.icon = icon
        self.iconColor = iconColor
        self.headerTrailing = EmptyView()
        self.content = content()
    }

    init(
        title: String,
        icon: String? = nil,
        iconColor: Color = .accentColor,
        @ViewBuilder headerTrailing: () -> HeaderTrailing,
        @ViewBuilder content: () -> Content
    ) {
        self.title = title
        self.icon = icon
        self.iconColor = iconColor
        self.headerTrailing = headerTrailing()
        self.content = content()
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 9) {
            HStack(spacing: 6) {
                if let icon {
                    Image(systemName: icon)
                        .font(.system(size: 12, weight: .semibold))
                        .foregroundStyle(iconColor)
                }
                Text(title)
                    .font(.subheadline.weight(.semibold))
                Spacer(minLength: 0)
                headerTrailing
            }
            content
        }
        .padding(12)
        .cardSurface(
            cornerRadius: LayoutRules.cardRadius,
            tint: icon == nil ? nil : iconColor.opacity(OpacityScale.ghost)
        )
    }
}

struct CollapseChevronButton: View {
    let isExpanded: Bool
    let action: () -> Void

    var body: some View {
        Button(action: action) {
            Image(systemName: isExpanded ? "chevron.up" : "chevron.down")
        }
        .liquidGlassActionButtonStyle(density: .compact)
    }
}

struct CloseGlassButton: View {
    let action: () -> Void

    var body: some View {
        Button(action: action) {
            Image(systemName: "xmark")
        }
        .accessibilityLabel(L10n.tr("common.close"))
        .liquidGlassActionButtonStyle(density: .compact)
    }
}

struct LanguageMenuButton<Label: View>: View {
    let currentLocale: AppLocale
    let onSelectLocale: (AppLocale) -> Void
    @ViewBuilder let label: Label

    init(
        currentLocale: AppLocale,
        onSelectLocale: @escaping (AppLocale) -> Void,
        @ViewBuilder label: () -> Label
    ) {
        self.currentLocale = currentLocale
        self.onSelectLocale = onSelectLocale
        self.label = label()
    }

    var body: some View {
        Menu {
            ForEach(AppLocale.allCases) { locale in
                Button {
                    onSelectLocale(locale)
                } label: {
                    HStack {
                        Text(L10n.tr(locale.displayNameKey))
                        if locale == currentLocale {
                            Image(systemName: "checkmark")
                        }
                    }
                }
            }
        } label: {
            label
        }
        .accessibilityLabel(Text("settings.language"))
    }
}

struct ToolbarIconLabel: View {
    let systemImage: String
    var isSpinning = false
    var opticalScale = CGFloat(1)

    var body: some View {
        baseIcon
            .modifier(ToolbarIconSpinModifier(isSpinning: isSpinning))
    }

    private var baseIcon: some View {
        Image(systemName: systemImage)
            .font(.system(size: LayoutRules.toolbarIconPointSize, weight: .semibold))
            .foregroundStyle(.primary)
            .scaleEffect(opticalScale)
    }
}

private struct ToolbarIconSpinModifier: ViewModifier {
    let isSpinning: Bool

    func body(content: Content) -> some View {
        if #available(iOS 18.0, macOS 15.0, *) {
            content
                .symbolEffect(.rotate.byLayer, options: .repeating, isActive: isSpinning)
        } else {
            content
                .rotationEffect(.degrees(isSpinning ? 360 : 0))
                .animation(
                    isSpinning
                        ? .linear(duration: 1).repeatForever(autoreverses: false)
                        : .easeOut(duration: 0.2),
                    value: isSpinning
                )
        }
    }
}
