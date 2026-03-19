import SwiftUI
import AppKit

struct SettingsPageView: View {
    @ObservedObject var model: SettingsPageModel

    var body: some View {
        VStack(spacing: 0) {
            Form {
                launchSection
                proxySection
                routingSection
                languageSection
                aboutSection
            }
            .formStyle(.grouped)
            .scrollIndicators(.hidden)

            HStack(spacing: LayoutRules.listRowSpacing) {
                Spacer(minLength: 0)

                Button(role: .destructive) {
                    quitApp()
                } label: {
                    Text("退出 AIMenu")
                }
                .buttonStyle(.frostedCapsule(prominent: true, tint: .red))
            }
            .padding(.horizontal, LayoutRules.pagePadding)
            .padding(.top, 6)
            .padding(.bottom, 10)
        }
        .task {
            await model.loadIfNeeded()
        }
    }

    // MARK: - 启动

    private var launchSection: some View {
        Section("启动") {
            VStack(alignment: .leading, spacing: 4) {
                Toggle(isOn: Binding(
                    get: { model.settings.launchAtStartup },
                    set: { model.setLaunchAtStartup($0) }
                )) {
                    Text("开机启动")
                }
                .toggleStyle(.switch)

                Text("随系统自动启动 AIMenu")
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }

            VStack(alignment: .leading, spacing: 4) {
                Text("Codex 通过 AIMenu 集中代理接入后，不再从这里直接切换账号。")
                    .font(.caption)
                    .foregroundStyle(.secondary)
                    .fixedSize(horizontal: false, vertical: true)

                Text("账号池、模型兼容和失败重试由代理统一处理。")
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }
        }
    }

    // MARK: - 代理

    private var proxySection: some View {
        Section("代理") {
            VStack(alignment: .leading, spacing: 4) {
                Toggle(isOn: Binding(
                    get: { model.settings.autoStartApiProxy },
                    set: { model.setAutoStartProxy($0) }
                )) {
                    Text("自动启动 API 代理")
                }
                .toggleStyle(.switch)

                Text("启动时自动开启本地 API 代理服务")
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }
        }
    }

    // MARK: - 智能路由

    private var routingSection: some View {
        Section("智能路由") {
            VStack(alignment: .leading, spacing: 8) {
                Label("开启 API 代理后，AIMenu 会自动生成并切换到 Codex 的集中代理提供商。", systemImage: "point.3.connected.trianglepath.dotted")
                    .font(.subheadline)

                Label("本地代理会按额度、模型兼容性和失败重试自动选择可用账号。", systemImage: "arrow.triangle.branch")
                    .font(.subheadline)
                    .foregroundStyle(.secondary)

                Label("`.codex/auth.json` 和 `config.toml` 会随代理状态自动同步。", systemImage: "doc.badge.gearshape")
                    .font(.subheadline)
                    .foregroundStyle(.secondary)
            }
            .padding(.vertical, 4)
        }
    }

    // MARK: - 界面

    private var languageSection: some View {
        Section("界面") {
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

    // MARK: - 关于

    private var aboutSection: some View {
        let version = Bundle.main.infoDictionary?["CFBundleShortVersionString"] as? String ?? "--"
        return Section("关于") {
            HStack {
                Text("版本")
                Spacer()
                Text(version)
                    .foregroundStyle(.secondary)
            }

            Button {
                NSWorkspace.shared.open(URL(string: "https://github.com/yourChainGod/AIMenu")!)
            } label: {
                Text("在 GitHub 查看")
            }
        }
    }

    // MARK: - Actions

    private func quitApp() {
        NSApp.terminate(nil)
    }
}
