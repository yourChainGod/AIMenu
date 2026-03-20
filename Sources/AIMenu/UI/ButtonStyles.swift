import SwiftUI
import AppKit

enum AIMenuActionButtonIOSStyle {
    case system
    case liquidGlass
}

struct FrostedCapsuleButtonStyle: ButtonStyle {
    enum Density {
        case regular
        case compact
    }

    let prominent: Bool
    let tint: Color?
    let density: Density

    @Environment(\.isEnabled) private var isEnabled

    func makeBody(configuration: Configuration) -> some View {
        configuration.label
            .font(font)
            .foregroundStyle(.primary)
            .padding(.horizontal, horizontalPadding)
            .padding(.vertical, verticalPadding)
            .frame(minHeight: minimumHeight)
            .contentShape(Capsule())
            .background(buttonBackground(isPressed: configuration.isPressed))
            .overlay {
                Capsule()
                    .strokeBorder(separatorColor, lineWidth: 1)
            }
            .opacity(isEnabled ? 1 : OpacityScale.overlay)
            .scaleEffect(configuration.isPressed ? 0.97 : 1)
            .animation(.easeOut(duration: 0.12), value: configuration.isPressed)
    }

    private func buttonBackground(isPressed: Bool) -> some View {
        Capsule()
            .fill(backgroundFill(isPressed: isPressed))
            .shadow(
                color: prominent ? effectiveTint.opacity(isPressed ? OpacityScale.faint : OpacityScale.subtle) : .clear,
                radius: prominent ? 4 : 0,
                x: 0,
                y: prominent ? 1 : 0
            )
    }

    private var font: Font {
        switch density {
        case .regular:
            return .subheadline.weight(prominent ? .semibold : .medium)
        case .compact:
            return .callout.weight(prominent ? .semibold : .medium)
        }
    }

    private var horizontalPadding: CGFloat {
        density == .compact ? 10 : 12
    }

    private var verticalPadding: CGFloat {
        density == .compact ? 5 : 7
    }

    private var minimumHeight: CGFloat {
        density == .compact ? 30 : 34
    }

    private var separatorColor: Color {
        if prominent {
            return effectiveTint.opacity(OpacityScale.medium)
        }
        return Color(nsColor: .separatorColor).opacity(OpacityScale.muted)
    }

    private var effectiveTint: Color {
        tint ?? .accentColor
    }

    private func backgroundFill(isPressed: Bool) -> Color {
        if prominent {
            return effectiveTint.opacity(isPressed ? OpacityScale.medium : OpacityScale.muted)
        }
        return Color.primary.opacity(isPressed ? OpacityScale.muted : OpacityScale.faint)
    }
}

extension ButtonStyle where Self == FrostedCapsuleButtonStyle {
    static func frostedCapsule(
        prominent: Bool = false,
        tint: Color? = nil,
        density: FrostedCapsuleButtonStyle.Density = .regular
    ) -> Self {
        FrostedCapsuleButtonStyle(prominent: prominent, tint: tint, density: density)
    }
}

extension View {
    func aimenuActionButtonStyle(
        prominent: Bool = false,
        tint: Color? = nil,
        density: FrostedCapsuleButtonStyle.Density = .regular,
        iOSStyle: AIMenuActionButtonIOSStyle = .system
    ) -> some View {
        self.buttonStyle(.frostedCapsule(prominent: prominent, tint: tint, density: density))
    }

    func liquidGlassActionButtonStyle(
        prominent: Bool = false,
        tint: Color? = nil,
        density: FrostedCapsuleButtonStyle.Density = .regular
    ) -> some View {
        aimenuActionButtonStyle(
            prominent: prominent,
            tint: tint,
            density: density,
            iOSStyle: .liquidGlass
        )
    }
}
