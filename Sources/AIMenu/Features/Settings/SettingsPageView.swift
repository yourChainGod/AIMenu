import SwiftUI
import AppKit

struct SettingsPageView: View {
    @ObservedObject var model: SettingsPageModel
    private let repoURL = URL(string: "https://github.com/yourChainGod/AIMenu")!

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: LayoutRules.sectionSpacing) {
                settingsHeroCard
                launchSection
                routingSection
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
            .padding(LayoutRules.pagePadding)
        }
        .scrollIndicators(.hidden)
        .task {
            await model.loadIfNeeded()
        }
    }

    private var settingsHeroCard: some View {
        HStack(spacing: 12) {
            RoundedRectangle(cornerRadius: 14, style: .continuous)
                .fill(
                    LinearGradient(
                        colors: [.indigo.opacity(0.20), .blue.opacity(0.10)],
                        startPoint: .topLeading,
                        endPoint: .bottomTrailing
                    )
                )
                .overlay {
                    Image(systemName: "slider.horizontal.3")
                        .font(.system(size: 17, weight: .semibold))
                        .foregroundStyle(.indigo)
                }
                .frame(width: 40, height: 40)

            VStack(alignment: .leading, spacing: 5) {
                HStack(spacing: 8) {
                    Text("全局设置")
                        .font(.headline.weight(.semibold))
                    settingsBadge(text: "AIMenu", tint: .indigo)
                }

                Text("启动、代理与界面偏好统一在这里收口。")
                    .font(.caption)
                    .foregroundStyle(.secondary)
                    .lineLimit(2)
            }

            Spacer(minLength: 0)

            VStack(alignment: .trailing, spacing: 6) {
                settingsBadge(text: model.settings.autoStartApiProxy ? "代理自启" : "代理手动", tint: model.settings.autoStartApiProxy ? .mint : .secondary)
                settingsBadge(text: L10n.tr(AppLocale.resolve(model.settings.locale).displayNameKey), tint: .blue)
            }
        }
        .padding(14)
        .cardSurface(cornerRadius: LayoutRules.cardRadius, tint: .indigo.opacity(0.05))
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

    private var routingSection: some View {
        SectionCard(title: "智能接入", icon: "point.3.connected.trianglepath.dotted", iconColor: .blue) {
            VStack(spacing: 10) {
                settingsInfoRow(
                    icon: "arrow.triangle.branch",
                    title: "集中代理接管",
                    subtitle: "启用 API 代理后，Codex 自动切到 AIMenu 生成的代理提供商。",
                    tint: .blue
                )

                settingsInfoRow(
                    icon: "doc.badge.gearshape",
                    title: "配置自动同步",
                    subtitle: "`.codex/auth.json` 与 `config.toml` 会跟随代理状态更新。",
                    tint: .indigo
                )

                settingsInfoRow(
                    icon: "bolt.horizontal.circle",
                    title: "智能切换账号",
                    subtitle: "代理按额度、模型兼容性和失败重试自动选择可用账号。",
                    tint: .mint
                )
            }
        }
    }

    private var languageSection: some View {
        SectionCard(title: "界面", icon: "globe", iconColor: .indigo) {
            VStack(spacing: 10) {
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

                settingsInfoRow(
                    icon: "rectangle.and.text.magnifyingglass",
                    title: "更清爽的工作台",
                    subtitle: "设置页现在与主界面使用同一套卡片和悬浮按钮风格。",
                    tint: .orange
                )
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
                .fill(tint.opacity(0.08))
                .overlay(
                    RoundedRectangle(cornerRadius: 12, style: .continuous)
                        .strokeBorder(tint.opacity(0.10), lineWidth: 1)
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
                .fill(tint.opacity(0.12))
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
        .background(Color.primary.opacity(0.04), in: RoundedRectangle(cornerRadius: 12, style: .continuous))
    }

    private func settingsBadge(text: String, tint: Color) -> some View {
        Text(text)
            .font(.caption2.weight(.semibold))
            .foregroundStyle(tint == .secondary ? .secondary : tint)
            .padding(.horizontal, 8)
            .padding(.vertical, 4)
            .background((tint == .secondary ? Color.primary : tint).opacity(0.08), in: Capsule())
    }

    private func quitApp() {
        NSApp.terminate(nil)
    }
}
