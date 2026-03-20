import SwiftUI

struct UnifiedBadge: View {
    enum Density { case compact, standard }

    let text: String
    var icon: String? = nil
    var tint: Color = .secondary
    var density: Density = .standard

    var body: some View {
        let isSecondary = (tint == .secondary)
        let effectiveTint = isSecondary ? Color.primary : tint

        HStack(spacing: 4) {
            if let icon {
                Image(systemName: icon)
                    .font(.system(size: 8, weight: .bold))
            }
            Text(text)
                .lineLimit(1)
        }
        .font(.system(size: 10, weight: .semibold))
        .foregroundStyle(isSecondary ? AnyShapeStyle(.secondary) : AnyShapeStyle(tint))
        .padding(.horizontal, density == .compact ? 6 : 8)
        .padding(.vertical, density == .compact ? 3 : 4)
        .background {
            Capsule()
                .fill(effectiveTint.opacity(OpacityScale.subtle))
                .overlay {
                    if density == .standard {
                        Capsule()
                            .strokeBorder(effectiveTint.opacity(OpacityScale.muted), lineWidth: 1)
                    }
                }
        }
    }
}
