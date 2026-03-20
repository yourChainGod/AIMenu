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

    var body: some View {
        ZStack {
            panelChromeBackground

            VStack(spacing: 8) {
                AppTabToolbarSwitcher(selection: $selectedTab, tabs: AppTab.allCases, tint: currentTabAccent)
                    .frame(maxWidth: LayoutRules.tabSwitcherMaxWidth)
                    .frame(maxWidth: .infinity, alignment: .center)
                    .padding(.horizontal, 12)
                    .padding(.top, 16)

                pageStage
                    .padding(.horizontal, 10)
                    .padding(.bottom, 5)
            }
        }
        .padding(.horizontal, 8)
        .padding(.top, 8)
        .padding(.bottom, 5)
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
        window.isMovableByWindowBackground = false
        window.tabbingMode = .disallowed
        window.titleVisibility = .hidden
        window.titlebarAppearsTransparent = false
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
        Picker("导航分区", selection: $selection.animation(.easeInOut(duration: 0.18))) {
            ForEach(tabs, id: \.self) { tab in
                Text(L10n.tr(tab.titleTranslationKey))
                    .tag(tab)
                    .accessibilityLabel(Text(tab.titleKey))
            }
        }
        .pickerStyle(.segmented)
        .labelsHidden()
        .tint(tint)
        .frame(maxWidth: .infinity, minHeight: 32)
        .padding(4)
        .background {
            RoundedRectangle(cornerRadius: 16, style: .continuous)
                .fill(.ultraThinMaterial)
                .overlay(
                    RoundedRectangle(cornerRadius: 16, style: .continuous)
                        .fill(tint.opacity(0.05))
                )
        }
        .overlay {
            RoundedRectangle(cornerRadius: 16, style: .continuous)
                .strokeBorder(separatorColor, lineWidth: 1)
        }
        .clipShape(RoundedRectangle(cornerRadius: 16, style: .continuous))
        .accessibilityLabel(Text("导航分区"))
    }

    private var separatorColor: Color {
        Color(nsColor: .separatorColor).opacity(0.9)
    }
}

private extension AppTab {
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
}
