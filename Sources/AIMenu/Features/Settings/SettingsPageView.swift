import SwiftUI
import AppKit

struct SettingsPageView: View {
    @ObservedObject var model: SettingsPageModel
    private let repoURL = URL(string: "https://github.com/yourChainGod/AIMenu")!

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: LayoutRules.sectionSpacing) {
                launchSection
                languageSection
                aboutSection

                HStack {
                    Spacer(minLength: 0)

                    Button(role: .destructive) {
                        quitApp()
                    } label: {
                        Label("退出 AIMenu", systemImage: "power")
                            .lineLimit(1)
                    }
                    .aimenuActionButtonStyle(prominent: true, tint: .red, density: .compact)

                    Spacer(minLength: 0)
                }
            }
            .padding(.top, LayoutRules.pagePadding)
            .padding(.horizontal, LayoutRules.pagePadding)
            .padding(.bottom, 6)
            .frame(maxWidth: .infinity, alignment: .topLeading)
        }
        .scrollIndicators(.hidden)
        .overlay {
            PanelScrollChromeCleaner(bottomInset: 2)
                .frame(width: 0, height: 0)
        }
        .task {
            await model.loadIfNeeded()
        }
    }

    private var launchSection: some View {
        SectionCard(title: "启动与代理", icon: "bolt.badge.clock", iconColor: .teal) {
            VStack(spacing: 10) {
                settingsToggleRow(
                    title: "开机启动",
                    subtitle: "随系统自动启动 AIMenu",
                    tint: .teal,
                    isOn: Binding(
                        get: { model.settings.launchAtStartup },
                        set: { model.setLaunchAtStartup($0) }
                    )
                )

                settingsToggleRow(
                    title: "自动启动 API 代理",
                    subtitle: "打开小窗时同步拉起本地代理服务",
                    tint: .mint,
                    isOn: Binding(
                        get: { model.settings.autoStartApiProxy },
                        set: { model.setAutoStartProxy($0) }
                    )
                )
            }
        }
    }

    private var languageSection: some View {
        SectionCard(title: "界面", icon: "globe", iconColor: .indigo) {
            HStack(spacing: 10) {
                VStack(alignment: .leading, spacing: 4) {
                    Text("语言")
                        .font(.subheadline.weight(.semibold))
                    Text("切换 AIMenu 显示语言")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }

                Spacer(minLength: 0)

                Picker("语言", selection: Binding(
                    get: { AppLocale.resolve(model.settings.locale) },
                    set: { model.setLocale($0.identifier) }
                )) {
                    ForEach(AppLocale.allCases) { locale in
                        Text(L10n.tr(locale.displayNameKey)).tag(locale)
                    }
                }
                .pickerStyle(.menu)
            }
        }
    }

    private var aboutSection: some View {
        let version = Bundle.main.infoDictionary?["CFBundleShortVersionString"] as? String ?? "--"
        return SectionCard(
            title: "关于",
            icon: "info.circle",
            iconColor: .orange,
            headerTrailing: {
                settingsBadge(text: "v\(version)", tint: .orange)
            }
        ) {
            VStack(spacing: 10) {
                settingsInfoRow(
                    icon: "shippingbox",
                    title: "当前版本",
                    subtitle: "AIMenu \(version)",
                    tint: .orange
                )

                Button {
                    NSWorkspace.shared.open(repoURL)
                } label: {
                    Label("在 GitHub 查看", systemImage: "arrow.up.right.square")
                        .lineLimit(1)
                        .frame(maxWidth: .infinity)
                }
                .aimenuActionButtonStyle(prominent: true, tint: .orange, density: .compact)
            }
        }
    }

    private func settingsToggleRow(
        title: String,
        subtitle: String,
        tint: Color,
        isOn: Binding<Bool>
    ) -> some View {
        HStack(spacing: 10) {
            VStack(alignment: .leading, spacing: 4) {
                Text(title)
                    .font(.subheadline.weight(.semibold))
                Text(subtitle)
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }

            Spacer(minLength: 0)

            Toggle("", isOn: isOn)
                .labelsHidden()
                .toggleStyle(.switch)
        }
        .padding(.horizontal, 12)
        .padding(.vertical, 10)
        .background(
            RoundedRectangle(cornerRadius: 12, style: .continuous)
                .fill(tint.opacity(OpacityScale.muted))
                .overlay(
                    RoundedRectangle(cornerRadius: 12, style: .continuous)
                        .strokeBorder(tint.opacity(OpacityScale.muted), lineWidth: 1)
                )
        )
    }

    private func settingsInfoRow(
        icon: String,
        title: String,
        subtitle: String,
        tint: Color
    ) -> some View {
        HStack(spacing: 10) {
            RoundedRectangle(cornerRadius: 10, style: .continuous)
                .fill(tint.opacity(OpacityScale.muted))
                .overlay {
                    Image(systemName: icon)
                        .font(.system(size: 13, weight: .semibold))
                        .foregroundStyle(tint)
                }
                .frame(width: 30, height: 30)

            VStack(alignment: .leading, spacing: 3) {
                Text(title)
                    .font(.subheadline.weight(.semibold))
                Text(subtitle)
                    .font(.caption)
                    .foregroundStyle(.secondary)
                    .fixedSize(horizontal: false, vertical: true)
            }

            Spacer(minLength: 0)
        }
        .padding(.horizontal, 12)
        .padding(.vertical, 10)
        .background(Color.primary.opacity(OpacityScale.faint), in: RoundedRectangle(cornerRadius: 12, style: .continuous))
    }

    private func settingsBadge(text: String, tint: Color) -> some View {
        Text(text)
            .font(.caption2.weight(.semibold))
            .foregroundStyle(tint == .secondary ? .secondary : tint)
            .padding(.horizontal, 8)
            .padding(.vertical, 4)
            .background((tint == .secondary ? Color.primary : tint).opacity(OpacityScale.muted), in: Capsule())
    }

    private func quitApp() {
        NSApp.terminate(nil)
    }
}

private struct PanelScrollChromeCleaner: NSViewRepresentable {
    let bottomInset: CGFloat

    func makeNSView(context: Context) -> NSView {
        NSView(frame: .zero)
    }

    func updateNSView(_ nsView: NSView, context: Context) {
        DispatchQueue.main.async {
            guard let scrollView = nsView.enclosingScrollView else { return }
            scrollView.drawsBackground = false
            scrollView.backgroundColor = .clear
            scrollView.borderType = .noBorder
            scrollView.automaticallyAdjustsContentInsets = false
            scrollView.contentInsets = NSEdgeInsets(top: 0, left: 0, bottom: bottomInset, right: 0)
            scrollView.scrollerInsets = NSEdgeInsets(top: 0, left: 0, bottom: 0, right: 0)
        }
    }
}
