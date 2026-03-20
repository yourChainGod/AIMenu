import SwiftUI
import AppKit

struct ProxyPageView: View {
    @ObservedObject var model: ProxyPageModel

    var body: some View {
        ScrollView {
            ProxyPanelSections(model: model, mode: .all)
            .padding(LayoutRules.pagePadding)
        }
        .scrollIndicators(.hidden)
        .task {
            await model.load()
        }
    }
}

enum ProxyPanelMode {
    case all
    case apiProxyOnly
    case publicAccessOnly
}

struct ProxyPanelSections: View {
    @ObservedObject var model: ProxyPageModel
    var mode: ProxyPanelMode = .all

    var body: some View {
        VStack(spacing: LayoutRules.sectionSpacing) {
            if mode != .publicAccessOnly {
                apiProxySection
            }
            if mode != .apiProxyOnly {
                publicCapabilitySection
            }
        }
    }

    // MARK: - API Proxy Section

    private var apiProxySection: some View {
        SectionCard(
            title: "API 代理",
            icon: "network",
            iconColor: model.proxyStatus.running ? .mint : .secondary,
            headerTrailing: {
                HStack(spacing: 8) {
                    statusDot
                    CollapseChevronButton(isExpanded: model.apiProxySectionExpanded) {
                        withAnimation(AnimationPreset.quick) {
                            model.apiProxySectionExpanded.toggle()
                        }
                    }
                }
            }
        ) {
            if model.apiProxySectionExpanded {
                VStack(alignment: .leading, spacing: 12) {
                    proxyHeroCard
                    proxyControlRow
                    autoStartRow
                    proxyDetailCards
                }
            } else {
                collapsedStatusPill
            }
        }
    }

    // MARK: - Collapsed State

    private var collapsedStatusPill: some View {
        HStack(spacing: 8) {
            statusDot
            Text(model.proxyStatus.running ? "运行中" : "已停止")
                .font(.subheadline.weight(.medium))
        }
        .padding(.horizontal, 12)
        .padding(.vertical, 7)
        .frostedCapsuleSurface()
    }

    // MARK: - Hero Card

    private var proxyHeroCard: some View {
        HStack(alignment: .center, spacing: 16) {
            // Status icon with pulse
            ZStack {
                if model.proxyStatus.running {
                    PulsingCircle()
                }
                Image(systemName: model.proxyStatus.running ? "antenna.radiowaves.left.and.right" : "antenna.radiowaves.left.and.right.slash")
                    .font(.system(size: 28, weight: .semibold))
                    .foregroundStyle(model.proxyStatus.running ? Color.mint : Color.secondary)
            }
            .frame(width: 48, height: 48)

            VStack(alignment: .leading, spacing: 4) {
                Text(model.proxyStatus.running ? "代理运行中" : "代理已停止")
                    .font(.title3.weight(.bold))
                    .foregroundStyle(model.proxyStatus.running ? Color.mint : Color.primary)

                HStack(spacing: 8) {
                    // Port display
                    HStack(spacing: 4) {
                        Text(model.proxyStatus.port.map(String.init) ?? "--")
                            .font(.system(size: 22, weight: .bold, design: .monospaced))
                        Text("本地端口")
                            .font(.caption)
                            .foregroundStyle(.secondary)
                            .padding(.top, 4)
                    }

                    // Available accounts badge
                    accountsBadge
                }
            }

            Spacer(minLength: 0)
        }
        .padding(14)
        .cardSurface(cornerRadius: 12)
    }

    private var accountsBadge: some View {
        Text("\(model.proxyStatus.availableAccounts) 个账号")
            .font(.caption.weight(.semibold))
            .foregroundStyle(.white)
            .padding(.horizontal, 8)
            .padding(.vertical, 3)
            .background(
                Capsule()
                    .fill(model.proxyStatus.availableAccounts > 0 ? Color.mint : Color.gray)
            )
    }

    // MARK: - Control Row

    private var proxyControlRow: some View {
        HStack(spacing: 10) {
            TextField("8787", text: $model.preferredPortText)
                .frostedCapsuleInput()
                .frame(width: LayoutRules.proxyHeroPortFieldWidth)

            Button("刷新") {
                Task { await model.refreshStatus() }
            }
            .liquidGlassActionButtonStyle()
            .disabled(model.loading)

            Spacer(minLength: 0)

            startStopButton
        }
    }

    @ViewBuilder
    private var startStopButton: some View {
        if model.proxyStatus.running {
            Button("停止代理", role: .destructive) {
                Task { await model.stopProxy() }
            }
            .liquidGlassActionButtonStyle(prominent: true)
            .disabled(model.loading)
        } else {
            Button("启动代理") {
                Task { await model.startProxy() }
            }
            .liquidGlassActionButtonStyle(prominent: true)
            .disabled(model.loading)
        }
    }

    // MARK: - Auto Start Row

    private var autoStartRow: some View {
        HStack {
            Text("启动时自动运行代理")
                .font(.subheadline)
            Spacer(minLength: 0)
            Toggle("", isOn: Binding(
                get: { model.autoStartProxy },
                set: { value in
                    Task { await model.setAutoStartProxy(value) }
                }
            ))
            .labelsHidden()
            .toggleStyle(.switch)
            .controlSize(.small)
        }
    }

    // MARK: - Status Dot

    private var statusDot: some View {
        Circle()
            .fill(model.proxyStatus.running ? Color.mint : Color.gray)
            .frame(width: 7, height: 7)
    }

    // MARK: - Detail Cards

    private var proxyDetailCards: some View {
        LazyVStack(spacing: LayoutRules.proxyDetailCardSpacing) {
            CopyDetailCard(
                title: "基础 URL",
                value: model.proxyStatus.baseURL ?? "启动后自动生成",
                canCopy: model.proxyStatus.baseURL != nil,
                copyValue: model.proxyStatus.baseURL
            ) {
                EmptyView()
            }

            CopyDetailCard(
                title: "API 密钥",
                value: model.proxyStatus.apiKey ?? "首次启动后生成",
                canCopy: model.proxyStatus.apiKey != nil,
                copyValue: model.proxyStatus.apiKey
            ) {
                Button("刷新") {
                    Task { await model.refreshAPIKey() }
                }
                .liquidGlassActionButtonStyle()
                .disabled(model.loading)
            }

            infoCard(
                title: "Codex 接入",
                headline: "AIMenu 集中代理",
                body: model.proxyStatus.running
                    ? "已自动托管 .codex/auth.json 与 config.toml，Codex 将统一走本地代理。"
                    : "启动代理后会自动生成并切换到这个托管提供商。"
            )
            infoCard(
                title: "当前路由账号",
                headline: model.proxyStatus.activeAccountLabel ?? "暂无匹配请求",
                body: model.proxyStatus.activeAccountID ?? "有请求进入时将显示正在使用的账号"
            )
            infoCard(
                title: "最近错误",
                headline: model.proxyStatus.lastError ?? "无",
                body: ""
            )
        }
    }

    // MARK: - Public Capability Section

    private var cloudflaredSection: some View {
        PublicAccessSection(model: model, onCopy: copyToPasteboard)
    }

    @ViewBuilder
    private var publicCapabilitySection: some View {
        VStack(alignment: .leading, spacing: 8) {
            cloudflaredSection
            Text("开启后，局域网内其他设备可将此 Mac 作为 HTTP 代理使用。")
                .font(.caption)
                .foregroundStyle(.secondary)
                .padding(.horizontal, 4)
        }
    }

    // MARK: - Card Helpers

    private func infoCard(title: String, headline: String, body: String) -> some View {
        VStack(alignment: .leading, spacing: 6) {
            Text(title)
                .font(.caption2.weight(.bold))
                .foregroundStyle(.secondary)
            Text(headline)
                .font(.headline)
                .lineLimit(1)
                .truncationMode(.tail)
            if !body.isEmpty {
                Text(body)
                    .font(.caption)
                    .foregroundStyle(.secondary)
                    .lineLimit(1)
                    .truncationMode(.tail)
            }
        }
        .frame(maxWidth: .infinity, alignment: .topLeading)
        .padding(12)
        .cardSurface(cornerRadius: 12)
    }

    private func copyToPasteboard(_ value: String?) {
        guard let value else { return }
        NSPasteboard.general.clearContents()
        NSPasteboard.general.setString(value, forType: .string)
    }
}

// MARK: - CopyDetailCard (with copy feedback)

private struct CopyDetailCard<Trailing: View>: View {
    let title: String
    let value: String
    let canCopy: Bool
    let copyValue: String?
    @ViewBuilder let trailing: Trailing

    @State private var didCopy = false

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            HStack {
                Text(title)
                    .font(.caption2.weight(.bold))
                    .foregroundStyle(.secondary)
                Spacer(minLength: 0)
                trailing
                Button(didCopy ? "已复制" : "复制") {
                    guard let v = copyValue else { return }
                    NSPasteboard.general.clearContents()
                    NSPasteboard.general.setString(v, forType: .string)
                    didCopy = true
                    Task {
                        try? await Task.sleep(nanoseconds: 1_000_000_000)
                        didCopy = false
                    }
                }
                .liquidGlassActionButtonStyle()
                .disabled(!canCopy)
                .animation(AnimationPreset.hover, value: didCopy)
            }
            Text(value)
                .font(.caption.monospaced())
                .lineLimit(1)
                .truncationMode(.middle)
                .frame(maxWidth: .infinity, alignment: .leading)
                .textSelection(.enabled)
        }
        .frame(maxWidth: .infinity, alignment: .topLeading)
        .padding(12)
        .cardSurface(cornerRadius: 12)
    }
}

// MARK: - PulsingCircle

private struct PulsingCircle: View {
    @State private var scale: CGFloat = 1.0
    @State private var opacity: Double = 0.6

    var body: some View {
        Circle()
            .fill(Color.mint.opacity(opacity))
            .scaleEffect(scale)
            .onAppear {
                withAnimation(
                    .easeInOut(duration: 1.2)
                    .repeatForever(autoreverses: true)
                ) {
                    scale = 1.8
                    opacity = 0.0
                }
            }
    }
}
