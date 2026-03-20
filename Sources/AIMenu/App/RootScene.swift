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

    var body: some View {
        VStack(spacing: 0) {
            AppTabToolbarSwitcher(selection: $selectedTab, tabs: AppTab.allCases)
                .frame(maxWidth: LayoutRules.tabSwitcherMaxWidth)
                .frame(maxWidth: .infinity, alignment: .center)
                .padding(.horizontal, LayoutRules.pagePadding)
                .padding(.top, 10)
                .padding(.bottom, 8)

            activePage
        }
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
                .padding(.horizontal, LayoutRules.pagePadding)
                .padding(.top, 6)
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
                        .foregroundStyle(selection == tab ? Color.primary : Color.secondary)
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
                    .fill(Color.accentColor.opacity(0.12))
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
