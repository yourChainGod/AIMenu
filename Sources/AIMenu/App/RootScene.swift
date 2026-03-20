import SwiftUI
import Combine
import AppKit

struct RootScene: View {
    @State private var selectedTab: AppTab = .accounts
    @StateObject private var accountsModel: AccountsPageModel
    @StateObject private var providerModel: ProviderPageModel
    @StateObject private var proxyModel: ProxyPageModel
    @StateObject private var toolsModel: ToolsPageModel
    @StateObject private var settingsModel: SettingsPageModel
    @ObservedObject private var trayModel: TrayMenuModel

    init(container: AppContainer, trayModel: TrayMenuModel) {
        _accountsModel = StateObject(wrappedValue: container.accountsModel)
        _providerModel = StateObject(wrappedValue: container.providerModel)
        _proxyModel = StateObject(wrappedValue: container.proxyModel)
        _toolsModel = StateObject(wrappedValue: container.toolsModel)
        _settingsModel = StateObject(wrappedValue: container.settingsModel)
        self.trayModel = trayModel
    }

    private var runtimeLocale: Locale {
        Locale(identifier: AppLocale.resolve(settingsModel.settings.locale).identifier)
    }

    private var currentNotice: NoticeMessage? {
        switch selectedTab {
        case .accounts:
            return proxyModel.notice ?? accountsModel.notice
        case .providers:
            return providerModel.notice
        case .tools, .workbench:
            return toolsModel.notice
        case .settings:
            return settingsModel.notice
        }
    }

    private var currentAppLocale: AppLocale {
        AppLocale.resolve(settingsModel.settings.locale)
    }

    private var currentTabAccent: Color {
        switch selectedTab {
        case .accounts:
            return .mint
        case .providers:
            return .blue
        case .tools:
            return .teal
        case .workbench:
            return .orange
        case .settings:
            return .indigo
        }
    }

    private var currentTabSubtitle: String {
        switch selectedTab {
        case .accounts:
            return "账号、代理与状态"
        case .providers:
            return "提供商与接管配置"
        case .tools:
            return "本地服务与本地配置"
        case .workbench:
            return "MCP、提示词与工具挂载"
        case .settings:
            return "语言、启动与全局偏好"
        }
    }

    var body: some View {
        ZStack {
            panelChromeBackground

            VStack(spacing: 0) {
                panelWindowHandle
                    .padding(.top, 10)

                panelHeader
                    .padding(.horizontal, 12)
                    .padding(.top, 8)
                    .padding(.bottom, 6)

                pageStage
                    .padding(.horizontal, 10)
                    .padding(.bottom, 10)
            }
        }
        .padding(8)
        .environment(\.locale, runtimeLocale)
        .onAppear {
            L10n.setLocale(identifier: settingsModel.settings.locale)
        }
        .onChange(of: settingsModel.settings.locale) { _, value in
            L10n.setLocale(identifier: value)
        }
        .onChange(of: selectedTab) { _, tab in
            if tab == .accounts {
                Task { await proxyModel.refreshForTabEntry() }
            }
        }
        .onReceive(trayModel.$accounts.removeDuplicates()) { accounts in
            accountsModel.syncFromBackgroundRefresh(accounts)
        }
        .task {
            await settingsModel.loadIfNeeded()
            await proxyModel.bootstrapOnAppLaunch(using: settingsModel.settings)
        }
        .safeAreaInset(edge: .top, spacing: 0) {
            NoticeBanner(notice: currentNotice)
                .padding(.horizontal, LayoutRules.pagePadding + 2)
                .padding(.top, 8)
                .allowsHitTesting(false)
                .zIndex(10)
        }
        .background {
            WindowSizeEnforcer(
                minWidth: LayoutRules.minimumPanelWidth,
                maxWidth: LayoutRules.maximumPanelWidth,
                minHeight: LayoutRules.minimumPanelHeight,
                idealHeight: LayoutRules.defaultPanelHeight
            )
            .frame(width: 0, height: 0)
        }
        .frame(
            minWidth: LayoutRules.minimumPanelWidth,
            idealWidth: LayoutRules.defaultPanelWidth,
            maxWidth: LayoutRules.maximumPanelWidth,
            minHeight: LayoutRules.minimumPanelHeight
        )
        .animation(.spring(response: 0.26, dampingFraction: 0.86), value: selectedTab)
    }

    private var panelWindowHandle: some View {
        Capsule()
            .fill(Color.white.opacity(0.52))
            .frame(width: 68, height: 3.5)
            .overlay {
                Capsule()
                    .strokeBorder(currentTabAccent.opacity(0.18), lineWidth: 0.8)
            }
    }

    private var panelHeader: some View {
        VStack(spacing: 8) {
            HStack(spacing: 10) {
                ZStack {
                    RoundedRectangle(cornerRadius: 14, style: .continuous)
                        .fill(
                            LinearGradient(
                                colors: [
                                    currentTabAccent.opacity(0.24),
                                    currentTabAccent.opacity(0.10)
                                ],
                                startPoint: .topLeading,
                                endPoint: .bottomTrailing
                            )
                        )
                    RoundedRectangle(cornerRadius: 14, style: .continuous)
                        .strokeBorder(Color.white.opacity(0.28), lineWidth: 1)
                    Image(systemName: "drop.halffull")
                        .font(.system(size: 16, weight: .semibold))
                        .foregroundStyle(currentTabAccent)
                }
                .frame(width: 38, height: 38)

                VStack(alignment: .leading, spacing: 3) {
                    HStack(spacing: 8) {
                        Text("AIMenu")
                            .font(.caption2.weight(.semibold))
                            .foregroundStyle(.secondary)
                            .textCase(.uppercase)

                        Text(selectedTab.toolbarTitle)
                            .font(.headline.weight(.semibold))
                            .foregroundStyle(.primary)
                    }

                    Text(currentTabSubtitle)
                        .font(.caption2.weight(.medium))
                        .foregroundStyle(.secondary)
                        .padding(.horizontal, 7)
                        .padding(.vertical, 3)
                        .background(Color.primary.opacity(0.05), in: Capsule())
                        .lineLimit(1)
                }

                Spacer(minLength: 0)

                VStack(alignment: .trailing, spacing: 4) {
                    Text("\(AppTab.allCases.firstIndex(of: selectedTab).map { $0 + 1 } ?? 1)/\(AppTab.allCases.count)")
                        .font(.caption2.weight(.bold))
                        .foregroundStyle(currentTabAccent)
                        .padding(.horizontal, 7)
                        .padding(.vertical, 4)
                        .background(currentTabAccent.opacity(0.12), in: Capsule())

                    Circle()
                        .fill(currentTabAccent)
                        .frame(width: 6, height: 6)
                        .shadow(color: currentTabAccent.opacity(0.45), radius: 8, x: 0, y: 0)
                }
            }

            AppTabToolbarSwitcher(selection: $selectedTab, tabs: AppTab.allCases, tint: currentTabAccent)
                .frame(maxWidth: LayoutRules.tabSwitcherMaxWidth)
                .frame(maxWidth: .infinity, alignment: .center)
        }
        .padding(12)
        .background {
            RoundedRectangle(cornerRadius: 22, style: .continuous)
                .fill(.ultraThinMaterial)
                .overlay(
                    RoundedRectangle(cornerRadius: 22, style: .continuous)
                        .strokeBorder(Color.white.opacity(0.20), lineWidth: 1)
                )
                .background(
                    RoundedRectangle(cornerRadius: 22, style: .continuous)
                        .fill(currentTabAccent.opacity(0.08))
                        .blur(radius: 16)
                )
        }
    }

    private var pageStage: some View {
        ZStack(alignment: .top) {
            RoundedRectangle(cornerRadius: 24, style: .continuous)
                .fill(.thinMaterial)
                .overlay(
                    RoundedRectangle(cornerRadius: 24, style: .continuous)
                        .strokeBorder(Color.white.opacity(0.18), lineWidth: 1)
                )

            Circle()
                .fill(currentTabAccent.opacity(0.10))
                .frame(width: 180, height: 180)
                .blur(radius: 40)
                .offset(x: -120, y: -90)

            RoundedRectangle(cornerRadius: 2, style: .continuous)
                .fill(
                    LinearGradient(
                        colors: [
                            currentTabAccent.opacity(0.72),
                            currentTabAccent.opacity(0.08),
                            Color.clear
                        ],
                        startPoint: .leading,
                        endPoint: .trailing
                    )
                )
                .frame(height: 3)
                .padding(.top, 10)
                .padding(.horizontal, 24)

            activePage
                .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .top)
                .clipShape(RoundedRectangle(cornerRadius: 20, style: .continuous))
        }
        .shadow(color: .black.opacity(0.08), radius: 12, x: 0, y: 6)
    }

    private var panelChromeBackground: some View {
        ZStack {
            RoundedRectangle(cornerRadius: 30, style: .continuous)
                .fill(.ultraThinMaterial)

            RoundedRectangle(cornerRadius: 30, style: .continuous)
                .fill(
                    LinearGradient(
                        colors: [
                            currentTabAccent.opacity(0.16),
                            Color.white.opacity(0.04),
                            Color.clear
                        ],
                        startPoint: .topLeading,
                        endPoint: .bottomTrailing
                    )
                )

            Circle()
                .fill(currentTabAccent.opacity(0.14))
                .frame(width: 210, height: 210)
                .blur(radius: 52)
                .offset(x: -116, y: -172)

            Circle()
                .fill(currentTabAccent.opacity(0.10))
                .frame(width: 176, height: 176)
                .blur(radius: 46)
                .offset(x: 152, y: 214)

            RoundedRectangle(cornerRadius: 30, style: .continuous)
                .strokeBorder(Color.white.opacity(0.22), lineWidth: 1)

            RoundedRectangle(cornerRadius: 30, style: .continuous)
                .inset(by: 1.5)
                .strokeBorder(
                    LinearGradient(
                        colors: [
                            Color.white.opacity(0.30),
                            Color.clear,
                            currentTabAccent.opacity(0.12)
                        ],
                        startPoint: .topLeading,
                        endPoint: .bottomTrailing
                    ),
                    lineWidth: 1
                )
        }
        .clipShape(RoundedRectangle(cornerRadius: 30, style: .continuous))
        .shadow(color: .black.opacity(0.16), radius: 26, x: 0, y: 16)
    }

    @ViewBuilder
    private var activePage: some View {
        switch selectedTab {
        case .accounts:
            AccountsPageView(
                model: accountsModel,
                proxyModel: proxyModel,
                currentLocale: currentAppLocale,
                onSelectLocale: { locale in
                    settingsModel.setLocale(locale.identifier)
                }
            )
        case .providers:
            ProviderPageView(model: providerModel)
        case .tools:
            ToolsPageView(model: toolsModel, mode: .tools)
        case .workbench:
            ToolsPageView(model: toolsModel, mode: .workbench)
        case .settings:
            SettingsPageView(model: settingsModel)
        }
    }
}

private struct WindowSizeEnforcer: NSViewRepresentable {
    let minWidth: CGFloat
    let maxWidth: CGFloat
    let minHeight: CGFloat
    let idealHeight: CGFloat

    func makeNSView(context: Context) -> NSView {
        let view = NSView(frame: .zero)
        DispatchQueue.main.async {
            apply(on: view.window)
        }
        return view
    }

    func updateNSView(_ nsView: NSView, context: Context) {
        DispatchQueue.main.async {
            apply(on: nsView.window)
        }
    }

    private func apply(on window: NSWindow?) {
        guard let window else { return }
        if window.frameAutosaveName != "AIMenu.Panel" {
            window.setFrameAutosaveName("AIMenu.Panel")
        }
        window.isMovableByWindowBackground = true
        window.tabbingMode = .disallowed
        window.titleVisibility = .hidden
        window.titlebarAppearsTransparent = true
        window.isOpaque = false
        window.backgroundColor = .clear
        window.contentMinSize = NSSize(width: minWidth, height: minHeight)
        window.contentMaxSize = NSSize(width: maxWidth, height: .greatestFiniteMagnitude)

        var targetSize = window.contentLayoutRect.size
        let clampedWidth = min(max(targetSize.width, minWidth), maxWidth)
        let clampedHeight = max(targetSize.height, minHeight)

        guard clampedWidth != targetSize.width || clampedHeight != targetSize.height else { return }
        targetSize.width = clampedWidth
        targetSize.height = clampedHeight > 0 ? clampedHeight : idealHeight
        window.setContentSize(targetSize)
    }
}

private struct AppTabToolbarSwitcher: View {
    @Binding var selection: AppTab
    let tabs: [AppTab]
    let tint: Color

    var body: some View {
        HStack(spacing: 0) {
            ForEach(Array(tabs.enumerated()), id: \.element) { index, tab in
                Button {
                    withAnimation(.easeInOut(duration: 0.18)) {
                        selection = tab
                    }
                } label: {
                    Image(systemName: tab.iconName)
                        .font(.system(size: 16, weight: selection == tab ? .semibold : .medium))
                        .foregroundStyle(selection == tab ? tint : Color.secondary)
                        .frame(maxWidth: .infinity, minHeight: 40)
                }
                .buttonStyle(.plain)
                .help(L10n.tr(tab.titleTranslationKey))
                .background {
                    if selection == tab {
                        selectedBackground
                            .padding(3)
                    }
                }
                .overlay(alignment: .trailing) {
                    if shouldShowDivider(after: index) {
                        Rectangle()
                            .fill(separatorColor.opacity(0.55))
                            .frame(width: 1, height: 20)
                    }
                }
                .accessibilityAddTraits(selection == tab ? .isSelected : [])
                .accessibilityLabel(Text(tab.titleKey))
            }
        }
        .background {
            Capsule()
                .fill(.ultraThinMaterial)
        }
        .overlay {
            Capsule()
                .strokeBorder(separatorColor, lineWidth: 1)
        }
        .clipShape(Capsule())
        .accessibilityElement(children: .contain)
        .accessibilityLabel(Text("导航分区"))
    }

    @ViewBuilder
    private var selectedBackground: some View {
        Capsule()
            .fill(.regularMaterial)
            .overlay {
                Capsule()
                    .fill(tint.opacity(0.16))
            }
    }

    private func shouldShowDivider(after index: Int) -> Bool {
        guard index < tabs.count - 1 else { return false }
        let current = tabs[index]
        let next = tabs[index + 1]
        return selection != current && selection != next
    }

    private var separatorColor: Color {
        Color(nsColor: .separatorColor).opacity(0.9)
    }
}

private extension AppTab {
    var iconName: String {
        switch self {
        case .accounts: return "person.2"
        case .providers: return "arrow.triangle.swap"
        case .tools: return "wrench.and.screwdriver"
        case .workbench: return "square.grid.2x2"
        case .settings: return "gearshape"
        }
    }

    var titleTranslationKey: String {
        switch self {
        case .accounts: return "tab.accounts"
        case .providers: return "tab.providers"
        case .tools: return "tab.tools"
        case .workbench: return "tab.workbench"
        case .settings: return "tab.settings"
        }
    }

    var titleKey: LocalizedStringKey {
        switch self {
        case .accounts: return "tab.accounts"
        case .providers: return "tab.providers"
        case .tools: return "tab.tools"
        case .workbench: return "tab.workbench"
        case .settings: return "tab.settings"
        }
    }

    var toolbarTitle: String {
        L10n.tr(titleTranslationKey)
    }
}
