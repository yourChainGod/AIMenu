import SwiftUI

struct NoticeBanner: View {
    let notice: NoticeMessage?

    var body: some View {
        if let notice {
            HStack(spacing: 8) {
                RoundedRectangle(cornerRadius: 8, style: .continuous)
                    .fill(accentColor(for: notice.style).opacity(OpacityScale.muted))
                    .overlay {
                        Image(systemName: iconName(for: notice.style))
                            .font(.system(size: 12, weight: .bold))
                            .foregroundStyle(accentColor(for: notice.style))
                    }
                    .frame(width: 24, height: 24)
                Text(notice.text)
                    .font(.caption.weight(.medium))
                    .foregroundStyle(.primary)
                    .frame(maxWidth: .infinity, alignment: .leading)
            }
            .padding(.horizontal, 11)
            .padding(.vertical, 7)
            .cardSurface(cornerRadius: 12, tint: accentColor(for: notice.style).opacity(OpacityScale.faint))
            .overlay(alignment: .leading) {
                RoundedRectangle(cornerRadius: 1.5, style: .continuous)
                    .fill(noticeAccentColor(notice.style))
                    .frame(width: 2.5)
                    .padding(.vertical, 7)
                    .padding(.leading, 7)
            }
            .shadow(color: accentColor(for: notice.style).opacity(OpacityScale.muted), radius: 10, x: 0, y: 5)
            .transition(.opacity.combined(with: .move(edge: .top)))
        }
    }

    private func accentColor(for style: NoticeStyle) -> Color {
        switch style {
        case .success:
            return .mint
        case .info:
            return .blue
        case .error:
            return .red
        }
    }

    private func iconName(for style: NoticeStyle) -> String {
        switch style {
        case .success:
            return "checkmark.circle.fill"
        case .info:
            return "info.circle.fill"
        case .error:
            return "exclamationmark.triangle.fill"
        }
    }

    private func noticeAccentColor(_ style: NoticeStyle) -> Color {
        switch style {
        case .success:
            return .mint
        case .info:
            return .blue
        case .error:
            return .red
        }
    }
}
