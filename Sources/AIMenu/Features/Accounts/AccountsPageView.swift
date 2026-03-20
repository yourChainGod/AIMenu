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
                        Color.black.opacity(0.24)
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
        .animation(.spring(response: 0.28, dampingFraction: 0.84), value: hasActiveOverlay)
    }

    private var hasActiveOverlay: Bool {
        activeProxySettings != nil
    }

    private var actionBar: some View {
        ZStack {
            HStack {
                Spacer(minLength: 0)

                CollapseChevronButton(isExpanded: !model.areAllAccountsCollapsed) {
                    withAnimation(.easeInOut(duration: 0.2)) {
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
                        .frame(width: isOverviewMode ? LayoutRules.accountsCollapsedCardWidth : LayoutRules.accountsCardWidth)
                    }
                }
                .padding(.horizontal, LayoutRules.pagePadding)
                .frame(maxWidth: .infinity, alignment: .leading)
            }
        }
    }

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

    private var contentAccountCount: Int? {
        guard case .content(let accounts) = model.state else { return nil }
        return accounts.count
    }

    private func triggerInitialCardEntranceIfNeeded(for count: Int?) {
        guard count != nil, !didRunInitialCardEntrance else { return }
        didRunInitialCardEntrance = true
        areCardsPresented = true
    }

    private func accountGridColumns(isOverviewMode: Bool) -> [GridItem] {
        if isOverviewMode {
            return Array(
                repeating: GridItem(
                    .fixed(LayoutRules.accountsCollapsedCardWidth),
                    spacing: LayoutRules.accountsRowSpacing,
                    alignment: .top
                ),
                count: LayoutRules.accountsCollapsedColumns
            )
        }

        return Array(
            repeating: GridItem(
                .fixed(LayoutRules.accountsCardWidth),
                spacing: LayoutRules.accountsRowSpacing,
                alignment: .top
                ),
            count: LayoutRules.accountsExpandedColumns
        )
    }

    private func modalTopInset(for height: CGFloat) -> CGFloat {
        min(54, max(18, height * 0.09))
    }

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
}

private enum ProxySettingsFocus: String, Identifiable {
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

private struct ProxyQuickControlRow: View {
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

private struct ProxyQuickStatusPill: View {
    let text: String
    let tint: Color

    var body: some View {
        Text(text)
            .font(.caption2.weight(.bold))
            .foregroundStyle(tint)
            .padding(.horizontal, 7)
            .padding(.vertical, 3)
            .background(tint.opacity(0.12), in: Capsule())
    }
}

private struct ProxySettingsPanel<Content: View>: View {
    let focus: ProxySettingsFocus
    let onClose: () -> Void
    @ViewBuilder let content: Content

    var body: some View {
        VStack(spacing: 0) {
            HStack(alignment: .center, spacing: 12) {
                RoundedRectangle(cornerRadius: 11, style: .continuous)
                    .fill(focus.sheetTint.opacity(0.16))
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
                .overlay(Color.white.opacity(0.08))

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
                        .fill(focus.sheetTint.opacity(0.08))
                        .blur(radius: 18)
                )
        }
        .overlay(alignment: .top) {
            RoundedRectangle(cornerRadius: 2, style: .continuous)
                .fill(focus.sheetTint.opacity(0.9))
                .frame(width: 72, height: 4)
                .padding(.top, 8)
        }
        .shadow(color: .black.opacity(0.24), radius: 28, x: 0, y: 14)
    }
}

private struct CardEntranceModifier: ViewModifier {
    let index: Int
    let isPresented: Bool

    func body(content: Content) -> some View {
        content
            .opacity(isPresented ? 1 : 0)
            .offset(y: isPresented ? 0 : 22)
            .scaleEffect(isPresented ? 1 : 0.985)
            .animation(
                .spring(response: 0.5, dampingFraction: 0.86)
                    .delay(min(0.28, Double(index) * 0.035)),
                value: isPresented
            )
    }
}

private extension View {
    func aimenuCardEntrance(index: Int, isPresented: Bool) -> some View {
        modifier(CardEntranceModifier(index: index, isPresented: isPresented))
    }
}

private struct AccountCardView: View {
    let account: AccountSummary
    let isCollapsed: Bool
    let onDelete: () -> Void
    @Environment(\.locale) private var locale

    var body: some View {
        VStack(alignment: .leading, spacing: isCollapsed ? 8 : 8) {
            HStack {
                VStack(alignment: .leading, spacing: 6) {
                    HStack(spacing: 6) {
                        stamp(text: planLabel, tint: planTagTint, fg: planTagForeground)
                        if !isCollapsed, let teamNameTag {
                            stamp(text: teamNameTag, tint: workspaceTagTint, fg: workspaceTagForeground)
                        }
                    }
                }

                Spacer(minLength: 0)

                if !isCollapsed {
                    Button(role: .destructive, action: onDelete) {
                        Image(systemName: "trash")
                    }
                    .aimenuActionButtonStyle(
                        prominent: true,
                        tint: .red,
                        density: .compact
                    )
                    .tint(.red)
                }
            }

            Text(displayAccountName)
                .font(.headline)
                .foregroundStyle(account.isCurrent ? toneColor : .primary)
                .lineLimit(isCollapsed ? 1 : 2)
                .fixedSize(horizontal: false, vertical: true)
                .truncationMode(.tail)

            if isCollapsed {
                compactUsageSection
            } else {
                windowSection(title: L10n.tr("accounts.window.five_hour"), window: account.usage?.fiveHour, tint: .orange)
                windowSection(title: L10n.tr("accounts.window.one_week"), window: account.usage?.oneWeek, tint: .teal)

                HStack(spacing: 8) {
                    Text(L10n.tr("accounts.card.credits_format", creditsText))
                        .font(.caption)
                        .foregroundStyle(.secondary)
                        .padding(.trailing, bottomTrailingOverlayInset)
                    Spacer(minLength: 0)
                }

                if let usageError = account.usageError, !usageError.isEmpty {
                    Text(usageError)
                        .font(.caption)
                        .foregroundStyle(.red)
                        .lineLimit(2)
                }
            }
        }
        .padding(isCollapsed ? 8 : 10)
        .cardSurface(
            cornerRadius: 12,
            tint: currentCardSurfaceTint
        )
        .overlay(
            RoundedRectangle(cornerRadius: 12, style: .continuous)
                .strokeBorder(account.isCurrent ? toneColor.opacity(0.45) : .clear, lineWidth: 1)
        )
        .overlay(alignment: .bottomTrailing) {
            if !isCollapsed {
                stamp(
                    text: "代理池成员",
                    tint: toneColor.opacity(0.18),
                    fg: toneColor
                )
                .padding(8)
            }
        }
    }

    private var compactUsageSection: some View {
        HStack(spacing: 14) {
            CompactUsageRing(
                usedPercent: compactUsedPercent(account.usage?.fiveHour),
                tint: .orange
            )
            CompactUsageRing(
                usedPercent: compactUsedPercent(account.usage?.oneWeek),
                tint: .teal
            )
        }
        .frame(maxWidth: .infinity, alignment: .center)
    }

    @ViewBuilder
    private func windowSection(title: String, window: UsageWindow?, tint: Color) -> some View {
        let usedRaw = clamped(window?.usedPercent)
        let used = roundedPercent(usedRaw)
        let remain = max(0, 100 - used)
        VStack(alignment: .leading, spacing: 4) {
            HStack {
                Text(title)
                    .font(.caption.weight(.semibold))
                Spacer(minLength: 0)
                Text(L10n.tr("accounts.window.used_format", percent(used)))
                    .font(.caption.weight(.semibold))
                Text(L10n.tr("accounts.window.remaining_format", percent(remain)))
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }

            usageBar(usedPercent: used, tint: tint)

            Text(L10n.tr("accounts.window.reset_at_format", formatResetAt(window?.resetAt)))
                .font(.caption2)
                .foregroundStyle(.secondary)
        }
    }

    private var planLabel: String {
        let normalized = (account.planType ?? account.usage?.planType ?? "team").lowercased()
        switch normalized {
        case "free": return "FREE"
        case "plus": return "PLUS"
        case "pro": return "PRO"
        case "enterprise": return "ENTERPRISE"
        case "business": return "BUSINESS"
        default: return "TEAM"
        }
    }

    private var teamNameTag: String? {
        guard planLabel == "TEAM" else { return nil }
        return account.displayTeamName
    }

    private var toneColor: Color {
        switch planLabel {
        case "PRO": return .orange
        case "PLUS": return .pink
        case "FREE": return .gray
        case "ENTERPRISE", "BUSINESS": return .indigo
        default: return .teal
        }
    }

    private var planTagTint: Color { toneColor.opacity(0.18) }
    private var planTagForeground: Color { toneColor }
    private var workspaceTagTint: Color { toneColor.opacity(0.18) }
    private var workspaceTagForeground: Color { toneColor }

    private var currentCardSurfaceTint: Color? {
        guard account.isCurrent else { return nil }
        return .teal.opacity(0.14)
    }

    private var creditsText: String {
        guard let credits = account.usage?.credits else { return "--" }
        if credits.unlimited { return L10n.tr("accounts.card.unlimited") }
        return credits.balance ?? "--"
    }

    private var bottomTrailingOverlayInset: CGFloat {
        isCollapsed ? 0 : 64
    }

    private var displayAccountName: String {
        let raw = (account.email ?? account.accountID).trimmingCharacters(in: .whitespacesAndNewlines)
        guard isCollapsed,
              let atIndex = raw.firstIndex(of: "@"),
              atIndex > raw.startIndex else {
            return raw
        }
        return String(raw[..<atIndex])
    }

    private func stamp(text: String, tint: Color, fg: Color, maxWidth: CGFloat? = nil) -> some View {
        Text(text)
            .font(.caption2.weight(.bold))
            .padding(.horizontal, 8)
            .padding(.vertical, 4)
            .foregroundStyle(fg)
            .lineLimit(1)
            .truncationMode(.tail)
            .fixedSize(horizontal: true, vertical: false)
            .frame(maxWidth: maxWidth, alignment: .leading)
            .background(tint, in: Capsule())
    }

    private func clamped(_ value: Double?) -> Double {
        guard let value else { return 100 }
        return max(0, min(100, value))
    }

    private func compactUsedPercent(_ window: UsageWindow?) -> Double? {
        guard let used = window?.usedPercent else { return nil }
        return max(0, min(100, used))
    }

    private func roundedPercent(_ value: Double) -> Double {
        Double(Int(value.rounded()))
    }

    private func usageBar(usedPercent: Double, tint: Color) -> some View {
        LiquidProgressBar(
            progress: usedPercent / 100,
            tint: tint
        )
    }

    private func percent(_ value: Double) -> String {
        "\(Int(value.rounded()))%"
    }

    private func formatResetAt(_ epoch: Int64?) -> String {
        guard let epoch else { return "--" }
        let formatter = DateFormatter()
        formatter.locale = locale
        formatter.dateStyle = .short
        formatter.timeStyle = .medium
        return formatter.string(from: Date(timeIntervalSince1970: TimeInterval(epoch)))
    }
}

private struct CompactUsageRing: View {
    let usedPercent: Double?
    let tint: Color

    private var progress: Double {
        guard let usedPercent else { return 0 }
        return max(0, min(1, usedPercent / 100))
    }

    private var percentText: String {
        guard let usedPercent else { return "--" }
        return "\(Int(usedPercent.rounded()))%"
    }

    var body: some View {
        ZStack {
            LiquidProgressRing(
                progress: progress,
                tint: tint,
                lineWidth: 7
            )
            VStack(spacing: 1) {
                Text(percentText)
                    .font(.system(size: 10, weight: .bold))
                    .monospacedDigit()
                Text(L10n.tr("accounts.compact.used"))
                    .font(.system(size: 7, weight: .semibold))
                    .foregroundStyle(.secondary)
            }
        }
        .frame(width: 54, height: 54)
    }
}
