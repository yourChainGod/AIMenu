import SwiftUI

struct EmptyStateView: View {
    let title: String
    let message: String
    let icon: String
    let tint: Color

    init(
        title: String,
        message: String,
        icon: String = "tray",
        tint: Color = .secondary
    ) {
        self.title = title
        self.message = message
        self.icon = icon
        self.tint = tint
    }

    var body: some View {
        VStack(spacing: 12) {
            RoundedRectangle(cornerRadius: 12, style: .continuous)
                .fill(tint.opacity(0.12))
                .overlay {
                    Image(systemName: icon)
                        .font(.system(size: 18, weight: .semibold))
                        .foregroundStyle(tint)
                }
                .frame(width: 38, height: 38)
            Text(title)
                .font(.headline.weight(.semibold))
            Text(message)
                .font(.caption)
                .foregroundStyle(.secondary)
                .multilineTextAlignment(.center)
        }
        .frame(maxWidth: .infinity, minHeight: 180)
        .padding(18)
        .cardSurface(cornerRadius: LayoutRules.cardRadius, tint: tint.opacity(0.04))
    }
}
