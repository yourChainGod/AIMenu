import SwiftUI
import AppKit

struct CardSurfaceModifier: ViewModifier {
    let cornerRadius: CGFloat
    let tint: Color?

    func body(content: Content) -> some View {
        content
            .background { backgroundSurface }
            .overlay(
                RoundedRectangle(cornerRadius: cornerRadius, style: .continuous)
                    .strokeBorder(separatorColor, lineWidth: 1)
            )
    }

    @ViewBuilder
    private var backgroundSurface: some View {
        ZStack {
            RoundedRectangle(cornerRadius: cornerRadius, style: .continuous)
                .fill(Color(nsColor: .controlBackgroundColor).opacity(OpacityScale.opaque))
            if let tint {
                RoundedRectangle(cornerRadius: cornerRadius, style: .continuous)
                    .fill(tint.opacity(OpacityScale.accent))
            }
        }
    }

    private var separatorColor: Color {
        Color(nsColor: .separatorColor).opacity(OpacityScale.muted)
    }
}

enum FrostedChromeTokens {
    static var separatorColor: Color {
        Color(nsColor: .separatorColor)
    }

    static func tintedGlass(prominent: Bool, tint: Color?) -> Color {
        if let tint {
            return tint.opacity(prominent ? OpacityScale.accent : OpacityScale.medium)
        }
        return Color.white.opacity(prominent ? OpacityScale.subtle : OpacityScale.faint)
    }

    static func fallbackFill(prominent: Bool, tint: Color?) -> AnyShapeStyle {
        if let tint {
            return AnyShapeStyle(tint.opacity(prominent ? OpacityScale.muted : OpacityScale.subtle))
        }
        return AnyShapeStyle(
            Color(nsColor: .controlBackgroundColor).opacity(prominent ? OpacityScale.opaque : OpacityScale.opaque)
        )
    }
}

struct FrostedCapsuleSurfaceModifier: ViewModifier {
    let prominent: Bool
    let tint: Color?

    func body(content: Content) -> some View {
        content
            .background { backgroundSurface }
            .overlay {
                Capsule()
                    .strokeBorder(FrostedChromeTokens.separatorColor.opacity(prominent ? OpacityScale.dense : 1), lineWidth: 1)
            }
    }

    @ViewBuilder
    private var backgroundSurface: some View {
        Capsule()
            .fill(FrostedChromeTokens.fallbackFill(prominent: prominent, tint: tint))
    }
}

struct FrostedRoundedSurfaceModifier: ViewModifier {
    let cornerRadius: CGFloat
    let prominent: Bool
    let tint: Color?

    func body(content: Content) -> some View {
        content
            .background { backgroundSurface }
            .overlay {
                RoundedRectangle(cornerRadius: cornerRadius, style: .continuous)
                    .strokeBorder(FrostedChromeTokens.separatorColor.opacity(prominent ? OpacityScale.dense : 1), lineWidth: 1)
            }
    }

    @ViewBuilder
    private var backgroundSurface: some View {
        RoundedRectangle(cornerRadius: cornerRadius, style: .continuous)
            .fill(FrostedChromeTokens.fallbackFill(prominent: prominent, tint: tint))
    }
}

struct FrostedRoundedInputModifier: ViewModifier {
    let cornerRadius: CGFloat

    func body(content: Content) -> some View {
        content
            .textFieldStyle(.plain)
            .padding(.horizontal, 12)
            .padding(.vertical, 9)
            .frostedRoundedSurface(cornerRadius: cornerRadius, prominent: true)
    }
}

struct GlassSelectableCardModifier: ViewModifier {
    let selected: Bool
    let cornerRadius: CGFloat
    let tint: Color

    func body(content: Content) -> some View {
        content
            .cardSurface(
                cornerRadius: cornerRadius,
                tint: selected ? tint.opacity(OpacityScale.medium) : nil
            )
            .overlay {
                RoundedRectangle(cornerRadius: cornerRadius, style: .continuous)
                    .strokeBorder(
                        selected
                            ? tint.opacity(OpacityScale.overlay)
                            : FrostedChromeTokens.separatorColor.opacity(OpacityScale.solid),
                        lineWidth: 1
                    )
            }
    }
}

struct FrostedCapsuleInputModifier: ViewModifier {
    func body(content: Content) -> some View {
        content
            .textFieldStyle(.plain)
            .padding(.horizontal, 12)
            .padding(.vertical, 8)
            .frostedCapsuleSurface()
    }
}

extension View {
    func cardSurface(cornerRadius: CGFloat = LayoutRules.cardRadius, tint: Color? = nil) -> some View {
        modifier(CardSurfaceModifier(cornerRadius: cornerRadius, tint: tint))
    }

    func frostedCapsuleSurface(
        prominent: Bool = false,
        tint: Color? = nil
    ) -> some View {
        modifier(FrostedCapsuleSurfaceModifier(prominent: prominent, tint: tint))
    }

    func frostedRoundedSurface(
        cornerRadius: CGFloat = 12,
        prominent: Bool = false,
        tint: Color? = nil
    ) -> some View {
        modifier(FrostedRoundedSurfaceModifier(cornerRadius: cornerRadius, prominent: prominent, tint: tint))
    }

    func frostedRoundedInput(cornerRadius: CGFloat = 12) -> some View {
        modifier(FrostedRoundedInputModifier(cornerRadius: cornerRadius))
    }

    func glassSelectableCard(
        selected: Bool,
        cornerRadius: CGFloat = 12,
        tint: Color = .accentColor
    ) -> some View {
        modifier(
            GlassSelectableCardModifier(
                selected: selected,
                cornerRadius: cornerRadius,
                tint: tint
            )
        )
    }

    func frostedCapsuleInput() -> some View {
        modifier(FrostedCapsuleInputModifier())
    }
}
