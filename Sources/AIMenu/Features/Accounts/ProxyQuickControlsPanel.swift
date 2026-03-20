import SwiftUI

// MARK: - ProxySettingsFocus

enum ProxySettingsFocus: String, Identifiable {
    case apiProxy
    case publicAccess

    var id: String { rawValue }

    var sheetTitle: String {
        switch self {
        case .apiProxy: return "API 代理配置"
        case .publicAccess: return "公网访问配置"
        }
    }

    var sheetSubtitle: String {
        switch self {
        case .apiProxy:
            return "端口、密钥与 Codex 接入"
        case .publicAccess:
            return "公网入口与 Tunnel 模式"
        }
    }

    var sheetIcon: String {
        switch self {
        case .apiProxy: return "network"
        case .publicAccess: return "globe.asia.australia.fill"
        }
    }

    var sheetTint: Color {
        switch self {
        case .apiProxy: return .mint
        case .publicAccess: return .orange
        }
    }

    var panelMode: ProxyPanelMode {
        switch self {
        case .apiProxy: return .apiProxyOnly
        case .publicAccess: return .publicAccessOnly
        }
    }
}

// MARK: - ProxyQuickControlRow

struct ProxyQuickControlRow: View {
    let icon: String
    let title: String
    let statusText: String?
    let statusTint: Color
    @Binding var isOn: Bool
    let loading: Bool
    let onSettings: () -> Void

    var body: some View {
        HStack(spacing: 10) {
            ZStack {
                RoundedRectangle(cornerRadius: 8, style: .continuous)
                    .fill(statusTint.opacity(isOn ? 0.16 : 0.08))
                RoundedRectangle(cornerRadius: 8, style: .continuous)
                    .strokeBorder(Color(nsColor: .separatorColor).opacity(0.38), lineWidth: 1)
                Image(systemName: icon)
                    .font(.system(size: 13, weight: .semibold))
                    .foregroundStyle(statusTint)
            }
            .frame(width: 28, height: 28)

            Text(title)
                .font(.subheadline.weight(.semibold))
                .lineLimit(1)

            if let statusText, !statusText.isEmpty {
                ProxyQuickStatusPill(text: statusText, tint: statusTint)
            }

            Spacer(minLength: 0)

            if loading {
                ProgressView()
                    .controlSize(.small)
            }
            Toggle("", isOn: $isOn)
                .labelsHidden()
                .toggleStyle(.switch)
                .controlSize(.small)
                .disabled(loading)

            Button(action: onSettings) {
                Image(systemName: "gearshape.fill")
            }
            .aimenuActionButtonStyle(density: .compact)
            .disabled(loading)
        }
        .frame(maxWidth: .infinity, minHeight: 56)
        .padding(.horizontal, 12)
        .padding(.vertical, 8)
        .cardSurface(cornerRadius: 14, tint: statusTint.opacity(isOn ? 0.06 : 0.02))
    }
}

// MARK: - ProxyQuickStatusPill

struct ProxyQuickStatusPill: View {
    let text: String
    let tint: Color

    var body: some View {
        Text(text)
            .font(.caption2.weight(.bold))
            .foregroundStyle(tint)
            .padding(.horizontal, 7)
            .padding(.vertical, 3)
            .background(tint.opacity(OpacityScale.muted), in: Capsule())
    }
}

// MARK: - ProxySettingsPanel

struct ProxySettingsPanel<Content: View>: View {
    let focus: ProxySettingsFocus
    let onClose: () -> Void
    @ViewBuilder let content: Content

    var body: some View {
        VStack(spacing: 0) {
            HStack(alignment: .center, spacing: 12) {
                RoundedRectangle(cornerRadius: 11, style: .continuous)
                    .fill(focus.sheetTint.opacity(OpacityScale.medium))
                    .overlay {
                        Image(systemName: focus.sheetIcon)
                            .font(.system(size: 15, weight: .semibold))
                            .foregroundStyle(focus.sheetTint)
                    }
                    .frame(width: 38, height: 38)

                VStack(alignment: .leading, spacing: 4) {
                    Text(focus.sheetTitle)
                        .font(.headline.weight(.semibold))
                    Text(focus.sheetSubtitle)
                        .font(.caption)
                        .foregroundStyle(.secondary)
                        .lineLimit(1)
                }

                Spacer(minLength: 0)

                CloseGlassButton {
                    onClose()
                }
            }
            .padding(.horizontal, 18)
            .padding(.top, 16)
            .padding(.bottom, 14)

            Divider()
                .overlay(Color.white.opacity(OpacityScale.muted))

            content
                .padding(10)
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .top)
        .background {
            RoundedRectangle(cornerRadius: 24, style: .continuous)
                .fill(.regularMaterial)
                .overlay(
                    RoundedRectangle(cornerRadius: 24, style: .continuous)
                        .strokeBorder(Color.white.opacity(0.32), lineWidth: 1)
                )
                .background(
                    RoundedRectangle(cornerRadius: 24, style: .continuous)
                        .fill(focus.sheetTint.opacity(OpacityScale.muted))
                        .blur(radius: 18)
                )
        }
        .overlay(alignment: .top) {
            RoundedRectangle(cornerRadius: 2, style: .continuous)
                .fill(focus.sheetTint.opacity(0.9))
                .frame(width: 72, height: 4)
                .padding(.top, 8)
        }
        .shadow(color: .black.opacity(OpacityScale.accent), radius: 28, x: 0, y: 14)
    }
}

// MARK: - Card Entrance Animation

struct CardEntranceModifier: ViewModifier {
    let index: Int
    let isPresented: Bool

    func body(content: Content) -> some View {
        content
            .opacity(isPresented ? 1 : 0)
            .offset(y: isPresented ? 0 : 22)
            .scaleEffect(isPresented ? 1 : 0.985)
            .animation(
                AnimationPreset.expand
                    .delay(min(0.28, Double(index) * 0.035)),
                value: isPresented
            )
    }
}

extension View {
    func aimenuCardEntrance(index: Int, isPresented: Bool) -> some View {
        modifier(CardEntranceModifier(index: index, isPresented: isPresented))
    }
}
