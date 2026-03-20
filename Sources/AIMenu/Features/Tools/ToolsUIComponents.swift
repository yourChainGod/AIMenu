import SwiftUI

struct ToolsModalPanel<Content: View>: View {
    let accent: Color
    let onClose: () -> Void
    @ViewBuilder let content: Content

    var body: some View {
        VStack(spacing: 0) {
            HStack {
                Spacer(minLength: 0)
                CloseGlassButton {
                    onClose()
                }
            }
            .padding(.horizontal, 14)
            .padding(.top, 12)
            .padding(.bottom, 4)

            content
                .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .top)
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .top)
        .background {
            ZStack {
                RoundedRectangle(cornerRadius: 22, style: .continuous)
                    .fill(Color(nsColor: .windowBackgroundColor).opacity(0.985))
                RoundedRectangle(cornerRadius: 22, style: .continuous)
                    .fill(accent.opacity(0.03))
                RoundedRectangle(cornerRadius: 22, style: .continuous)
                    .strokeBorder(Color(nsColor: .separatorColor).opacity(0.14), lineWidth: 1)
            }
        }
        .clipShape(RoundedRectangle(cornerRadius: 22, style: .continuous))
        .shadow(color: .black.opacity(0.14), radius: 18, x: 0, y: 10)
    }
}

struct ToolsStatusBadge: View {
    let text: String
    let tint: Color

    var body: some View {
        Text(text)
            .font(.system(size: 10, weight: .semibold))
            .foregroundStyle(tint == Color.secondary ? AnyShapeStyle(.secondary) : AnyShapeStyle(tint))
            .padding(.horizontal, 8)
            .padding(.vertical, 4)
            .background(
                Capsule()
                    .fill((tint == Color.secondary ? Color.primary : tint).opacity(0.1))
            )
    }
}
