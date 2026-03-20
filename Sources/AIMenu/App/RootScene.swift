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
            RoundedRectangle(cornerRadius: 18, style: .continuous)
                .fill(Color(nsColor: .windowBackgroundColor).opacity(0.985))
                .overlay(
                    RoundedRectangle(cornerRadius: 18, style: .continuous)
                        .fill(currentTabAccent.opacity(0.018))
                )
                .overlay(
                    RoundedRectangle(cornerRadius: 18, style: .continuous)
                        .strokeBorder(Color(nsColor: .separatorColor).opacity(0.14), lineWidth: 1)
                )

            VStack(spacing: 0) {
                AppTabToolbarSwitcher(selection: $selectedTab, tabs: AppTab.allCases, tint: currentTabAccent)
                    .frame(maxWidth: LayoutRules.tabSwitcherMaxWidth)
                    .frame(maxWidth: .infinity, alignment: .center)
                    .padding(.horizontal, 14)
                    .padding(.top, 10)
                    .padding(.bottom, 8)

                Rectangle()
                    .fill(Color(nsColor: .separatorColor).opacity(0.12))
                    .frame(height: 1)
                    .padding(.horizontal, 14)

                activePage
                    .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .top)
                    .padding(.top, 2)
                    .padding(.bottom, 4)
            }
        }
        .shadow(color: .black.opacity(0.08), radius: 14, x: 0, y: 8)
        .padding(6)
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
        if !window.styleMask.contains(.fullSizeContentView) {
            window.styleMask.insert(.fullSizeContentView)
        }
        window.isMovableByWindowBackground = true
        window.tabbingMode = .disallowed
        window.titleVisibility = .hidden
        window.titlebarAppearsTransparent = true
        window.isOpaque = false
        window.backgroundColor = .clear
        window.toolbar = nil
        window.standardWindowButton(.closeButton)?.isHidden = true
        window.standardWindowButton(.miniaturizeButton)?.isHidden = true
        window.standardWindowButton(.zoomButton)?.isHidden = true
        if #available(macOS 11.0, *) {
            window.titlebarSeparatorStyle = .none
        }
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
        AppTabButtonBar(selection: $selection, tabs: tabs, tint: tint)
            .frame(maxWidth: .infinity, minHeight: 34, maxHeight: 34)
            .padding(2)
            .background(
                RoundedRectangle(cornerRadius: 11, style: .continuous)
                    .fill(Color.primary.opacity(0.028))
            )
            .overlay(
                RoundedRectangle(cornerRadius: 11, style: .continuous)
                    .strokeBorder(Color(nsColor: .separatorColor).opacity(0.10), lineWidth: 1)
            )
            .clipShape(RoundedRectangle(cornerRadius: 11, style: .continuous))
            .accessibilityLabel(Text("导航分区"))
    }
}

private struct AppTabButtonBar: NSViewRepresentable {
    @Binding var selection: AppTab
    let tabs: [AppTab]
    let tint: Color

    func makeCoordinator() -> Coordinator {
        Coordinator(parent: self)
    }

    func makeNSView(context: Context) -> FirstMouseTabBarHostView {
        let view = FirstMouseTabBarHostView()
        view.configure(
            labels: tabs.map { L10n.tr($0.titleTranslationKey) },
            selectedIndex: tabs.firstIndex(of: selection) ?? 0,
            tint: NSColor(tint),
            target: context.coordinator,
            action: #selector(Coordinator.tabPressed(_:))
        )
        return view
    }

    func updateNSView(_ nsView: FirstMouseTabBarHostView, context: Context) {
        context.coordinator.parent = self
        nsView.configure(
            labels: tabs.map { L10n.tr($0.titleTranslationKey) },
            selectedIndex: tabs.firstIndex(of: selection) ?? 0,
            tint: NSColor(tint),
            target: context.coordinator,
            action: #selector(Coordinator.tabPressed(_:))
        )
    }

    @MainActor
    final class Coordinator: NSObject {
        var parent: AppTabButtonBar

        init(parent: AppTabButtonBar) {
            self.parent = parent
        }

        @objc
        func tabPressed(_ sender: NSButton) {
            let index = sender.tag
            guard parent.tabs.indices.contains(index) else { return }
            withAnimation(.easeInOut(duration: 0.18)) {
                parent.selection = parent.tabs[index]
            }
        }
    }
}

private final class FirstMouseTabBarHostView: NSView {
    private let stackView = NSStackView()
    private var buttons: [FirstMouseTabButton] = []

    override init(frame frameRect: NSRect) {
        super.init(frame: frameRect)
        translatesAutoresizingMaskIntoConstraints = false
        wantsLayer = true
        layer?.backgroundColor = NSColor.clear.cgColor

        stackView.translatesAutoresizingMaskIntoConstraints = false
        stackView.orientation = .horizontal
        stackView.alignment = .centerY
        stackView.distribution = .fillEqually
        stackView.spacing = 4
        addSubview(stackView)

        NSLayoutConstraint.activate([
            stackView.leadingAnchor.constraint(equalTo: leadingAnchor),
            stackView.trailingAnchor.constraint(equalTo: trailingAnchor),
            stackView.topAnchor.constraint(equalTo: topAnchor),
            stackView.bottomAnchor.constraint(equalTo: bottomAnchor)
        ])
    }

    @available(*, unavailable)
    required init?(coder: NSCoder) {
        fatalError("init(coder:) has not been implemented")
    }

    override func acceptsFirstMouse(for event: NSEvent?) -> Bool {
        true
    }

    func configure(labels: [String], selectedIndex: Int, tint: NSColor, target: AnyObject, action: Selector) {
        if buttons.count != labels.count {
            rebuildButtons(count: labels.count)
        }

        for (index, label) in labels.enumerated() {
            let button = buttons[index]
            button.tag = index
            button.target = target
            button.action = action
            button.update(title: label, selected: index == selectedIndex, tint: tint)
        }
    }

    private func rebuildButtons(count: Int) {
        buttons.forEach { button in
            stackView.removeArrangedSubview(button)
            button.removeFromSuperview()
        }
        buttons.removeAll()

        for _ in 0..<count {
            let button = FirstMouseTabButton()
            buttons.append(button)
            stackView.addArrangedSubview(button)
        }
    }
}

private final class FirstMouseTabButton: NSButton {
    override init(frame frameRect: NSRect) {
        super.init(frame: frameRect)
        setButtonType(.momentaryChange)
        isBordered = false
        bezelStyle = .regularSquare
        focusRingType = .none
        wantsLayer = true
        layer?.cornerRadius = 8
        layer?.cornerCurve = .continuous
    }

    @available(*, unavailable)
    required init?(coder: NSCoder) {
        fatalError("init(coder:) has not been implemented")
    }

    override func acceptsFirstMouse(for event: NSEvent?) -> Bool {
        true
    }

    override var intrinsicContentSize: NSSize {
        NSSize(width: super.intrinsicContentSize.width + 16, height: 30)
    }

    func update(title: String, selected: Bool, tint: NSColor) {
        let textColor = selected ? tint.blended(withFraction: 0.1, of: .labelColor) ?? tint : NSColor.labelColor
        let font = NSFont.systemFont(ofSize: 13, weight: selected ? .semibold : .medium)
        attributedTitle = NSAttributedString(
            string: title,
            attributes: [
                .font: font,
                .foregroundColor: textColor
            ]
        )
        layer?.backgroundColor = (selected ? tint.withAlphaComponent(0.12) : NSColor.clear).cgColor
        layer?.borderColor = (selected ? tint.withAlphaComponent(0.14) : NSColor.clear).cgColor
        layer?.borderWidth = selected ? 1 : 0
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
