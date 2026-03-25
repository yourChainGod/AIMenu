import SwiftUI

struct FormSectionCard<Content: View>: View {
    let title: String?
    let subtitle: String?
    let icon: String?
    let accent: Color
    var emphasis: Bool = false
    @ViewBuilder let content: () -> Content

    init(
        title: String? = nil,
        subtitle: String? = nil,
        icon: String? = nil,
        accent: Color,
        emphasis: Bool = false,
        @ViewBuilder content: @escaping () -> Content
    ) {
        self.title = title
        self.subtitle = subtitle
        self.icon = icon
        self.accent = accent
        self.emphasis = emphasis
        self.content = content
    }

    var body: some View {
        VStack(alignment: .leading, spacing: LayoutRules.spacing12) {
            if let title {
                HStack(alignment: .top, spacing: LayoutRules.spacing10) {
                    if let icon {
                        RoundedRectangle(cornerRadius: LayoutRules.radiusMedium, style: .continuous)
                            .fill(accent.opacity(OpacityScale.ghost))
                            .overlay {
                                Image(systemName: icon)
                                    .font(.system(size: 11, weight: .semibold))
                                    .foregroundStyle(accent)
                            }
                            .frame(width: 26, height: 26)
                    }
                    VStack(alignment: .leading, spacing: 3) {
                        Text(title)
                            .font(.callout.weight(.semibold))
                        if let subtitle {
                            Text(subtitle)
                                .font(.caption2)
                                .foregroundStyle(.secondary)
                        }
                    }
                    Spacer(minLength: 0)
                }
            }
            content()
        }
        .padding(13)
        .background(
            RoundedRectangle(cornerRadius: LayoutRules.radiusCard, style: .continuous)
                .fill(
                    LinearGradient(
                        colors: [
                            Color(nsColor: .controlBackgroundColor).opacity(OpacityScale.opaque),
                            Color.white.opacity(OpacityScale.ghost),
                            accent.opacity(emphasis ? OpacityScale.ghost : 0.015)
                        ],
                        startPoint: .topLeading,
                        endPoint: .bottomTrailing
                    )
                )
                .overlay(
                    RoundedRectangle(cornerRadius: LayoutRules.radiusCard, style: .continuous)
                        .strokeBorder(
                            emphasis
                                ? accent.opacity(OpacityScale.subtle)
                                : Color.primary.opacity(OpacityScale.subtle),
                            lineWidth: 1
                        )
                )
        )
        .shadow(
            color: .black.opacity(OpacityScale.ghost),
            radius: emphasis ? 8 : 3,
            x: 0,
            y: emphasis ? 4 : 2
        )
    }
}
