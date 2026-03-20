import SwiftUI
import AppKit
import UniformTypeIdentifiers

struct AccountsPageView: View {
    @State private var areCardsPresented = false
    @State private var didRunInitialCardEntrance = false
    @State private var activeProxySettings: ProxySettingsFocus?

    @ObservedObject var model: AccountsPageModel
    @ObservedObject var proxyModel: ProxyPageModel
    let currentLocale: AppLocale
    let onSelectLocale: (AppLocale) -> Void

    init(
        model: AccountsPageModel,
        proxyModel: ProxyPageModel,
        currentLocale: AppLocale,
        onSelectLocale: @escaping (AppLocale) -> Void
    ) {
        self.model = model
        self.proxyModel = proxyModel
        self.currentLocale = currentLocale
        self.onSelectLocale = onSelectLocale
        let hasResolvedInitialState = model.hasResolvedInitialState
        _areCardsPresented = State(initialValue: hasResolvedInitialState)
        _didRunInitialCardEntrance = State(initialValue: hasResolvedInitialState)
    }

    var body: some View {
        ZStack {
            VStack(alignment: .leading, spacing: LayoutRules.sectionSpacing) {
                actionBar
                    .padding(.horizontal, LayoutRules.pagePadding)

                ScrollView {
                    VStack(alignment: .leading, spacing: 0) {
                        contentView
                    }
                    .padding(.bottom, 12)
                    .frame(maxWidth: .infinity, alignment: .leading)
                }
                .scrollIndicators(.hidden)
            }
            .padding(.top, LayoutRules.pagePadding)
            .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
            .blur(radius: hasActiveOverlay ? 2 : 0)
            .allowsHitTesting(!hasActiveOverlay)

            if let focus = activeProxySettings {
                GeometryReader { geometry in
                    ZStack {
                        Color.black.opacity(OpacityScale.accent)
                            .ignoresSafeArea()
                            .contentShape(Rectangle())
                            .onTapGesture {}

                        ProxySettingsPanel(focus: focus, onClose: {
                            activeProxySettings = nil
                        }) {
                            ScrollView {
                                ProxyPanelSections(model: proxyModel, mode: focus.panelMode)
                                    .padding(14)
                            }
                            .scrollIndicators(.hidden)
                            .task {
                                await proxyModel.load()
                            }
                        }
                        .frame(maxWidth: 620, maxHeight: max(420, geometry.size.height - 44))
                        .padding(.horizontal, 26)
                        .padding(.top, modalTopInset(for: geometry.size.height))
                        .padding(.bottom, 22)
                        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .top)
                        .transition(.move(edge: .top).combined(with: .scale(scale: 0.97)).combined(with: .opacity))
                    }
                    .zIndex(10)
                }
            }
        }
        .task {
            await model.loadIfNeeded()
        }
        .onAppear {
            model.resetStuckStatesIfNeeded()
            triggerInitialCardEntranceIfNeeded(for: contentAccountCount)
        }
        .onChange(of: contentAccountCount) { _, newValue in
            triggerInitialCardEntranceIfNeeded(for: newValue)
        }
        .animation(AnimationPreset.sheet, value: hasActiveOverlay)
    }

    // MARK: - Overlay State

    private var hasActiveOverlay: Bool {
        activeProxySettings != nil
    }

    // MARK: - Action Bar

    private var actionBar: some View {
        ZStack {
            HStack {
                Spacer(minLength: 0)

                CollapseChevronButton(isExpanded: !model.areAllAccountsCollapsed) {
                    withAnimation(AnimationPreset.quick) {
                        model.toggleAllAccountsCollapsed()
                    }
                }
                .accessibilityLabel(
                    Text(
                        model.areAllAccountsCollapsed
                            ? L10n.tr("accounts.action.expand_all")
                            : L10n.tr("accounts.action.collapse_all")
                    )
                )
            }

            actionButtons
                .frame(maxWidth: .infinity)
        }
    }

    private var actionButtons: some View {
        HStack(spacing: LayoutRules.listRowSpacing) {
            Button {
                openImportPanel()
            } label: {
                Label("导入 JSON", systemImage: "doc.badge.plus")
                    .lineLimit(1)
            }
            .disabled(!model.canAddAccountAction)
            .aimenuActionButtonStyle(prominent: true, density: .compact)
            .frame(maxWidth: .infinity)

            Button {
                Task { await model.addAccountViaLogin() }
            } label: {
                Label(model.isAdding ? L10n.tr("accounts.action.waiting_for_login") : L10n.tr("accounts.action.add_account"), systemImage: "plus")
                    .lineLimit(1)
            }
            .disabled(!model.canAddAccountAction)
            .aimenuActionButtonStyle(prominent: true, density: .compact)
            .frame(maxWidth: .infinity)

            Button {
                Task { await model.refreshUsage() }
            } label: {
                Label {
                    Text(model.isRefreshing ? "刷新中" : "刷新")
                        .lineLimit(1)
                } icon: {
                    ToolbarIconLabel(
                        systemImage: "arrow.trianglehead.clockwise.rotate.90",
                        isSpinning: model.isRefreshing,
                        opticalScale: LayoutRules.toolbarRefreshIconOpticalScale
                    )
                }
            }
            .disabled(!model.canRefreshUsageAction)
            .aimenuActionButtonStyle(prominent: true, tint: .mint, density: .compact)
            .frame(maxWidth: .infinity)
        }
        .frame(maxWidth: 460)
        .frame(maxWidth: .infinity)
    }

    // MARK: - Content

    @ViewBuilder
    private var contentView: some View {
        VStack(alignment: .leading, spacing: LayoutRules.sectionSpacing) {
            proxyQuickControls
                .padding(.horizontal, LayoutRules.pagePadding)

            switch model.state {
            case .loading:
                ProgressView(L10n.tr("accounts.loading.message"))
                    .frame(maxWidth: .infinity, minHeight: 180)
            case .empty(let message):
                EmptyStateView(
                    title: L10n.tr("accounts.empty.title"),
                    message: message,
                    icon: "person.crop.rectangle.stack",
                    tint: .mint
                )
                    .padding(.horizontal, LayoutRules.pagePadding)
            case .error(let message):
                EmptyStateView(
                    title: L10n.tr("accounts.error.load_failed"),
                    message: message,
                    icon: "exclamationmark.triangle",
                    tint: .red
                )
                    .padding(.horizontal, LayoutRules.pagePadding)
            case .content(let accounts):
                let isOverviewMode = model.areAllAccountsCollapsed
                let columns = accountGridColumns(isOverviewMode: isOverviewMode)
                LazyVGrid(
                    columns: columns,
                    alignment: .leading,
                    spacing: LayoutRules.accountsRowSpacing
                ) {
                    ForEach(Array(accounts.enumerated()), id: \.element.id) { index, account in
                        AccountCardView(
                            account: account,
                            isCollapsed: model.isAccountCollapsed(account.id),
                            onDelete: { Task { await model.deleteAccount(id: account.id) } }
                        )
                        .aimenuCardEntrance(index: index, isPresented: areCardsPresented)
                    }
                }
                .padding(.horizontal, LayoutRules.pagePadding)
                .frame(maxWidth: .infinity, alignment: .leading)
            }
        }
    }

    // MARK: - Proxy Quick Controls

    private var proxyQuickControls: some View {
        HStack(alignment: .top, spacing: 12) {
            ProxyQuickControlRow(
                icon: "network",
                title: "API 代理",
                statusText: proxyModel.proxyStatus.running ? "开" : "关",
                statusTint: proxyModel.proxyStatus.running ? .mint : .secondary,
                isOn: Binding(
                    get: { proxyModel.proxyStatus.running },
                    set: { enabled in
                        Task {
                            if enabled {
                                await proxyModel.startProxy()
                            } else {
                                await proxyModel.stopProxy()
                            }
                        }
                    }
                ),
                loading: proxyModel.loading,
                onSettings: {
                    openProxySettings(.apiProxy)
                }
            )

            ProxyQuickControlRow(
                icon: "globe.asia.australia.fill",
                title: "公网访问",
                statusText: proxyModel.cloudflaredStatus.running ? "开" : nil,
                statusTint: publicAccessStatusTint,
                isOn: Binding(
                    get: { proxyModel.cloudflaredStatus.running },
                    set: { enabled in
                        if enabled {
                            guard !shouldOpenPublicAccessSettingsBeforeAction else {
                                openProxySettings(.publicAccess)
                                return
                            }
                            Task {
                                proxyModel.publicAccessEnabled = true
                                proxyModel.cloudflaredSectionExpanded = true
                                await proxyModel.startCloudflared()
                            }
                        } else {
                            Task {
                                await proxyModel.setPublicAccessEnabled(false)
                            }
                        }
                    }
                ),
                loading: proxyModel.loading,
                onSettings: {
                    openProxySettings(.publicAccess)
                }
            )
        }
    }

    private var publicAccessStatusTint: Color {
        if proxyModel.cloudflaredStatus.running { return .orange }
        return .secondary
    }

    private var shouldOpenPublicAccessSettingsBeforeAction: Bool {
        !proxyModel.cloudflaredStatus.running && !proxyModel.canStartCloudflared
    }

    // MARK: - Card Entrance

    private var contentAccountCount: Int? {
        guard case .content(let accounts) = model.state else { return nil }
        return accounts.count
    }

    private func triggerInitialCardEntranceIfNeeded(for count: Int?) {
        guard count != nil, !didRunInitialCardEntrance else { return }
        didRunInitialCardEntrance = true
        areCardsPresented = true
    }

    // MARK: - Grid Layout

    private func accountGridColumns(isOverviewMode: Bool) -> [GridItem] {
        if isOverviewMode {
            return Array(
                repeating: GridItem(
                    .flexible(minimum: 120, maximum: 200),
                    spacing: LayoutRules.accountsRowSpacing,
                    alignment: .top
                ),
                count: LayoutRules.accountsCollapsedColumns
            )
        }

        return Array(
            repeating: GridItem(
                .flexible(minimum: 200, maximum: 300),
                spacing: LayoutRules.accountsRowSpacing,
                alignment: .top
                ),
            count: LayoutRules.accountsExpandedColumns
        )
    }

    // MARK: - Modal Helpers

    private func modalTopInset(for height: CGFloat) -> CGFloat {
        min(54, max(18, height * 0.09))
    }

    private func openProxySettings(_ focus: ProxySettingsFocus) {
        switch focus {
        case .apiProxy:
            proxyModel.apiProxySectionExpanded = true
            proxyModel.cloudflaredSectionExpanded = false
        case .publicAccess:
            proxyModel.apiProxySectionExpanded = false
            proxyModel.cloudflaredSectionExpanded = true
            proxyModel.publicAccessEnabled = proxyModel.cloudflaredStatus.running || proxyModel.publicAccessEnabled
        }
        activeProxySettings = focus
    }

    // MARK: - Import

    private func openImportPanel() {
        activeProxySettings = nil
        guard let selectedURLs = presentImportOpenPanel() else { return }
        let jsonURLs = collectJSONFiles(from: selectedURLs)
        guard !jsonURLs.isEmpty else {
            model.reportImportSelectionFailure(AppError.invalidData("未找到可导入的 JSON 文件"))
            return
        }

        Task {
            await model.importMultipleAuthDocuments(from: jsonURLs)
        }
    }

    private func presentImportOpenPanel() -> [URL]? {
        let panel = NSOpenPanel()
        panel.title = "导入账号 JSON"
        panel.message = "可多选 JSON 文件，也可选择目录批量导入。"
        panel.prompt = "导入"
        panel.canChooseFiles = true
        panel.canChooseDirectories = true
        panel.allowsMultipleSelection = true
        panel.resolvesAliases = true
        panel.allowedContentTypes = [UTType.json, UTType.folder]

        NSApp.activate(ignoringOtherApps: true)
        let response = panel.runModal()
        guard response == .OK else { return nil }
        return panel.urls
    }

    private func collectJSONFiles(from urls: [URL]) -> [URL] {
        var result: [URL] = []
        var seen = Set<String>()
        let fm = FileManager.default
        for url in urls {
            let standardized = url.standardizedFileURL
            var isDir: ObjCBool = false
            if fm.fileExists(atPath: standardized.path, isDirectory: &isDir), isDir.boolValue {
                if let enumerator = fm.enumerator(
                    at: standardized,
                    includingPropertiesForKeys: [.isRegularFileKey],
                    options: [.skipsHiddenFiles]
                ) {
                    for case let fileURL as URL in enumerator {
                        guard fileURL.pathExtension.lowercased() == "json" else { continue }
                        let filePath = fileURL.standardizedFileURL.path
                        if seen.insert(filePath).inserted {
                            result.append(fileURL.standardizedFileURL)
                        }
                    }
                }
            } else if standardized.pathExtension.lowercased() == "json" {
                if seen.insert(standardized.path).inserted {
                    result.append(standardized)
                }
            }
        }
        return result
    }
}
