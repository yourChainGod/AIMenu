import SwiftUI

struct NoticeBanner: View {
    let notice: NoticeMessage?

    var body: some View {
        if let notice {
            HStack(spacing: 8) {
                Image(systemName: iconName(for: notice.style))
                    .foregroundStyle(accentColor(for: notice.style))
                Text(notice.text)
                    .font(.subheadline)
                    .foregroundStyle(.primary)
                    .frame(maxWidth: .infinity, alignment: .leading)
            }
            .padding(.horizontal, 14)
            .padding(.vertical, 9)
            .cardSurface(cornerRadius: 10)
            .overlay(alignment: .leading) {
                RoundedRectangle(cornerRadius: 1.5, style: .continuous)
                    .fill(noticeAccentColor(notice.style))
                    .frame(width: 3)
                    .padding(.vertical, 8)
                    .padding(.leading, 7)
            }
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
