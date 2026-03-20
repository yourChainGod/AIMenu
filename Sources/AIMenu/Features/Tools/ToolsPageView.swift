import SwiftUI
import AppKit

struct ToolsPageView: View {
    enum PageMode {
        case tools
        case workbench
    }

    private enum ToolsOverviewSection: CaseIterable, Identifiable {
        case services
        case configs

        var id: Self { self }

        var title: String {
            switch self {
            case .services: return "本地服务"
            case .configs: return "本地配置"
            }
        }

        var iconName: String {
            switch self {
            case .services: return "switch.2"
            case .configs: return "folder.badge.gearshape"
            }
        }

        var tint: Color {
            switch self {
            case .services: return .teal
            case .configs: return .green
            }
        }
    }

    private enum SkillsFilter: String, CaseIterable, Identifiable {
        case all
        case installed
        case discoverable

        var id: String { rawValue }

        var title: String {
            switch self {
            case .all: return "全部"
            case .installed: return "已装"
            case .discoverable: return "可装"
            }
        }
    }

    @ObservedObject var model: ToolsPageModel
    let mode: PageMode

    @State private var mcpExpanded = true
    @State private var promptsExpanded = true
    @State private var hooksExpanded = true
    @State private var skillsExpanded = true
    @State private var selectedToolsOverviewSection: ToolsOverviewSection = .services
    @State private var showMCPPresets = false
    @State private var showMCPForm = false
    @State private var editingMCPServer: MCPServer?
    @State private var showPromptEditor = false
    @State private var editingPrompt: Prompt?
    @State private var showSkillRepoEditor = false
    @State private var hoveredMCPServer: String? = nil
    @State private var hoveredPrompt: String? = nil
    @State private var hoveredSkill: String? = nil
    @State private var hoveredDiscoverableSkill: String? = nil
    @State private var skillsSearchText = ""
    @State private var selectedSkillsFilter: SkillsFilter = .all

    var body: some View {
        ZStack {
            pageContent
                .blur(radius: hasActiveModal ? 2 : 0)
                .allowsHitTesting(!hasActiveModal)

            if showMCPForm {
                toolsModal(accent: .mint, onDismiss: closeMCPForm) {
                    MCPServerEditorSheet(
                        server: editingMCPServer,
                        onSave: { server in
                            Task { await model.saveMCPServer(server) }
                            closeMCPForm()
                        },
                        onCancel: closeMCPForm
                    )
                }
            } else if showPromptEditor {
                toolsModal(accent: .purple, onDismiss: closePromptEditor) {
                    PromptEditorSheet(
                        appType: model.selectedPromptApp,
                        prompt: editingPrompt,
                        onSave: { name, content in
                            Task {
                                if let editingPrompt {
                                    var updated = editingPrompt
                                    updated.name = name
                                    updated.content = content
                                    await model.updatePrompt(updated)
                                } else {
                                    await model.addPrompt(name: name, content: content)
                                }
                            }
                            closePromptEditor()
                        },
                        onCancel: closePromptEditor
                    )
                }
            } else if showSkillRepoEditor {
                toolsModal(accent: .orange, onDismiss: closeSkillRepoEditor) {
                    SkillRepoEditorSheet(
                        onSave: { owner, name, branch in
                            Task { await model.addSkillRepo(owner: owner, name: name, branch: branch) }
                            closeSkillRepoEditor()
                        },
                        onCancel: closeSkillRepoEditor
                    )
                }
            } else if let document = model.previewingDiscoverableSkillDocument {
                toolsModal(accent: .blue, onDismiss: closeDiscoverableSkillPreview) {
                    DiscoverableSkillPreviewSheet(
                        document: document,
                        previewLoading: model.previewingDiscoverableSkillKey == document.skill.key,
                        onInstall: {
                            Task { await model.installSkill(document.skill) }
                        },
                        onDismiss: closeDiscoverableSkillPreview
                    )
                }
            } else if let document = model.editingInstalledSkillDocument {
                toolsModal(accent: .orange, onDismiss: closeInstalledSkillEditor) {
                    InstalledSkillEditorSheet(
                        document: document,
                        onSave: { content in
                            Task { await model.saveInstalledSkill(directory: document.skill.directory, content: content) }
                        },
                        onCancel: closeInstalledSkillEditor
                    )
                }
            }
        }
        .task {
            switch mode {
            case .tools:
                await model.loadOverview()
            case .workbench:
                await model.loadWorkbench()
            }
        }
        .animation(.spring(response: 0.28, dampingFraction: 0.84), value: hasActiveModal)
    }

    private var pageContent: some View {
        ScrollView {
            VStack(spacing: LayoutRules.sectionSpacing) {
                contentSections
            }
            .padding(LayoutRules.pagePadding)
        }
        .scrollIndicators(.hidden)
    }

    private var hasActiveModal: Bool {
        showMCPForm ||
        showPromptEditor ||
        showSkillRepoEditor ||
        model.previewingDiscoverableSkillDocument != nil ||
        model.editingInstalledSkillDocument != nil
    }

    @ViewBuilder
    private func toolsModal<Content: View>(
        accent: Color,
        onDismiss: @escaping () -> Void,
        @ViewBuilder content: @escaping () -> Content
    ) -> some View {
        GeometryReader { geometry in
            ZStack {
                Color.black.opacity(0.24)
                    .ignoresSafeArea()
                    .contentShape(Rectangle())
                    .onTapGesture {}

                ToolsModalPanel(accent: accent, onClose: onDismiss) {
                    content()
                }
                .frame(
                    width: max(420, geometry.size.width - 22),
                    height: max(460, geometry.size.height - 22)
                )
                .padding(.horizontal, 11)
                .padding(.top, modalTopInset(for: geometry.size.height))
                .padding(.bottom, 12)
                .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .top)
                .transition(.move(edge: .top).combined(with: .scale(scale: 0.98)).combined(with: .opacity))
            }
            .zIndex(20)
        }
    }

    private func modalTopInset(for height: CGFloat) -> CGFloat {
        min(48, max(14, height * 0.08))
    }

    private func closeMCPForm() {
        showMCPForm = false
        editingMCPServer = nil
    }

    private func closePromptEditor() {
        showPromptEditor = false
        editingPrompt = nil
    }

    private func closeSkillRepoEditor() {
        showSkillRepoEditor = false
    }

    private func closeDiscoverableSkillPreview() {
        model.previewingDiscoverableSkillDocument = nil
    }

    private func closeInstalledSkillEditor() {
        model.editingInstalledSkillDocument = nil
    }

    @ViewBuilder
    private var contentSections: some View {
        switch mode {
        case .tools:
            toolsOverviewSwitcherRow
            toolsOverviewContent
        case .workbench:
            workbenchSwitcherRow
            workbenchContent
        }
    }

    private var workbenchSections: [ToolsPageModel.ToolsSection] {
        [.mcp, .prompts, .hooks, .skills]
    }

    private var activeWorkbenchSection: ToolsPageModel.ToolsSection {
        workbenchSections.contains(model.activeSection) ? model.activeSection : .mcp
    }

    private var isWorkbenchMode: Bool {
        mode == .workbench
    }

    private var toolsOverviewSwitcherRow: some View {
        HStack(spacing: LayoutRules.listRowSpacing) {
            ForEach(ToolsOverviewSection.allCases) { section in
                Button {
                    withAnimation(.easeInOut(duration: 0.18)) {
                        selectedToolsOverviewSection = section
                    }
                } label: {
                    HStack(spacing: 7) {
                        Image(systemName: section.iconName)
                            .font(.caption.weight(.semibold))

                        Text(section.title)
                            .font(.caption.weight(.semibold))
                    }
                    .frame(maxWidth: .infinity)
                    .lineLimit(1)
                }
                .frame(maxWidth: .infinity)
                .aimenuActionButtonStyle(
                    prominent: selectedToolsOverviewSection == section,
                    tint: selectedToolsOverviewSection == section ? section.tint : nil,
                    density: .compact
                )
            }
        }
        .frame(maxWidth: 360)
        .frame(maxWidth: .infinity, alignment: .center)
    }

    @ViewBuilder
    private var toolsOverviewContent: some View {
        switch selectedToolsOverviewSection {
        case .services:
            servicesSection
        case .configs:
            configsSection
        }
    }

    private var workbenchSwitcherRow: some View {
        HStack(spacing: LayoutRules.listRowSpacing) {
            ForEach(workbenchSections, id: \.self) { section in
                Button {
                    withAnimation(.easeInOut(duration: 0.18)) {
                        model.activeSection = section
                    }
                } label: {
                    HStack(spacing: 7) {
                        Image(systemName: workbenchSectionIcon(for: section))
                            .font(.caption.weight(.semibold))

                        Text(workbenchSectionTitle(for: section))
                            .font(.caption.weight(.semibold))
                    }
                    .frame(maxWidth: .infinity)
                    .lineLimit(1)
                }
                .frame(maxWidth: .infinity)
                .aimenuActionButtonStyle(
                    prominent: activeWorkbenchSection == section,
                    tint: activeWorkbenchSection == section ? workbenchSectionTint(for: section) : nil,
                    density: .compact
                )
            }
        }
        .frame(maxWidth: 460)
        .frame(maxWidth: .infinity, alignment: .center)
    }

    @ViewBuilder
    private var workbenchContent: some View {
        Group {
            switch activeWorkbenchSection {
            case .mcp:
                mcpSection
            case .prompts:
                promptsSection
            case .hooks:
                hooksSection
            case .skills:
                skillsSection
            }
        }
        .id(activeWorkbenchSection.rawValue)
    }

    private func workbenchSectionTitle(for section: ToolsPageModel.ToolsSection) -> String {
        switch section {
        case .mcp:
            return "MCP"
        case .prompts:
            return "Prompts"
        case .hooks:
            return "Hooks"
        case .skills:
            return "Skills"
        }
    }

    private func workbenchSectionIcon(for section: ToolsPageModel.ToolsSection) -> String {
        switch section {
        case .mcp:
            return "server.rack"
        case .prompts:
            return "text.bubble"
        case .hooks:
            return "point.3.connected.trianglepath.dotted"
        case .skills:
            return "wand.and.stars"
        }
    }

    private func workbenchSectionTint(for section: ToolsPageModel.ToolsSection) -> Color {
        switch section {
        case .mcp:
            return .blue
        case .prompts:
            return .purple
        case .hooks:
            return .indigo
        case .skills:
            return .orange
        }
    }

    private var promptAppPicker: some View {
        Picker("", selection: Binding(
            get: { model.selectedPromptApp },
            set: { app in Task { await model.switchPromptApp(app) } }
        )) {
            ForEach(PromptAppType.allCases) { app in
                Text(app.displayName).tag(app)
            }
        }
        .pickerStyle(.segmented)
    }

    private func workbenchMoreMenu<Content: View>(
        title: String = "更多",
        systemImage: String = "ellipsis",
        help text: String = "更多操作",
        @ViewBuilder content: () -> Content
    ) -> some View {
        Menu {
            content()
        } label: {
            Label(title, systemImage: systemImage)
                .lineLimit(1)
        }
        .menuStyle(.borderlessButton)
        .fixedSize()
        .aimenuActionButtonStyle(density: .compact)
        .help(text)
    }

    private func workbenchActionButton(
        _ title: String,
        systemImage: String,
        tint: Color? = nil,
        prominent: Bool = false,
        help: String? = nil,
        action: @escaping () -> Void
    ) -> some View {
        Button(action: action) {
            Label(title, systemImage: systemImage)
                .lineLimit(1)
        }
        .aimenuActionButtonStyle(prominent: prominent, tint: tint, density: .compact)
        .help(help ?? title)
    }

    private func workbenchStrip<Content: View>(
        tint: Color? = nil,
        minHeight: CGFloat = 0,
        @ViewBuilder content: () -> Content
    ) -> some View {
        HStack(spacing: 8) {
            content()
        }
        .padding(.horizontal, 11)
        .padding(.vertical, 9)
        .frame(maxWidth: .infinity, minHeight: minHeight == 0 ? nil : minHeight, alignment: .leading)
        .cardSurface(cornerRadius: 12, tint: tint?.opacity(0.05))
    }

    private func compactEmptyState(
        icon: String,
        title: String,
        message: String? = nil,
        tint: Color
    ) -> some View {
        VStack(spacing: 10) {
            RoundedRectangle(cornerRadius: 12, style: .continuous)
                .fill(tint.opacity(0.12))
                .overlay {
                    Image(systemName: icon)
                        .font(.system(size: 16, weight: .semibold))
                        .foregroundStyle(tint)
                }
                .frame(width: 36, height: 36)

            Text(title)
                .font(.subheadline.weight(.semibold))
                .foregroundStyle(.primary)

            if let message, !message.isEmpty {
                Text(message)
                    .font(.caption)
                    .foregroundStyle(.secondary)
                    .multilineTextAlignment(.center)
            }
        }
        .padding(.horizontal, 18)
        .padding(.vertical, 18)
        .frame(maxWidth: .infinity, minHeight: 104)
        .cardSurface(cornerRadius: 14, tint: tint.opacity(0.05))
    }

    private func overviewActionStrip(
        title: String,
        systemImage: String = "arrow.clockwise",
        tint: Color,
        help: String? = nil,
        action: @escaping () -> Void
    ) -> some View {
        HStack(spacing: LayoutRules.listRowSpacing) {
            workbenchActionButton(
                title,
                systemImage: systemImage,
                tint: tint,
                prominent: true,
                help: help ?? title,
                action: action
            )
        }
        .frame(maxWidth: .infinity, alignment: .center)
    }

    private var hasSkillsSearchQuery: Bool {
        skillsSearchText.trimmedNonEmpty != nil
    }

    private var filteredInstalledSkills: [InstalledSkill] {
        guard let query = skillsSearchText.trimmedNonEmpty else {
            return model.skills.installedSkills
        }

        return model.skills.installedSkills.filter { skill in
            matchesSkillsSearch(query: query, fields: [
                skill.name,
                skill.description,
                skill.directory,
                skill.repoOwner,
                skill.repoName
            ])
        }
    }

    private var filteredDiscoverableSkills: [DiscoverableSkill] {
        guard let query = skillsSearchText.trimmedNonEmpty else {
            return model.discoverableSkills
        }

        return model.discoverableSkills.filter { skill in
            matchesSkillsSearch(query: query, fields: [
                skill.name,
                skill.description,
                skill.directory,
                skill.repoOwner,
                skill.repoName,
                skill.repoBranch
            ])
        }
    }

    private var visibleInstalledSkills: [InstalledSkill] {
        switch selectedSkillsFilter {
        case .all, .installed:
            return filteredInstalledSkills
        case .discoverable:
            return []
        }
    }

    private var visibleDiscoverableSkills: [DiscoverableSkill] {
        switch selectedSkillsFilter {
        case .all, .discoverable:
            return filteredDiscoverableSkills
        case .installed:
            return []
        }
    }

    private var groupedClaudeHooks: [(event: String, hooks: [ClaudeHook])] {
        Dictionary(grouping: model.claudeHooks, by: \.event)
            .map { event, hooks in
                (
                    event: event,
                    hooks: hooks.sorted { lhs, rhs in
                        let lhsMatcher = lhs.matcher ?? ""
                        let rhsMatcher = rhs.matcher ?? ""
                        if lhsMatcher != rhsMatcher {
                            return lhsMatcher.localizedCaseInsensitiveCompare(rhsMatcher) == .orderedAscending
                        }
                        return lhs.command.localizedCaseInsensitiveCompare(rhs.command) == .orderedAscending
                    }
                )
            }
            .sorted { lhs, rhs in
                lhs.event.localizedCaseInsensitiveCompare(rhs.event) == .orderedAscending
            }
    }

    private func matchesSkillsSearch(query: String, fields: [String?]) -> Bool {
        fields.contains { field in
            guard let value = field?.trimmedNonEmpty else { return false }
            return value.localizedCaseInsensitiveContains(query)
        }
    }

    private func count(for filter: SkillsFilter) -> Int {
        switch filter {
        case .all:
            return filteredInstalledSkills.count + filteredDiscoverableSkills.count
        case .installed:
            return filteredInstalledSkills.count
        case .discoverable:
            return filteredDiscoverableSkills.count
        }
    }

    // MARK: - Managed Services

    private var servicesSection: some View {
        VStack(alignment: .leading, spacing: 12) {
            overviewActionStrip(
                title: "刷新服务",
                tint: .teal,
                help: "刷新本地服务状态"
            ) {
                Task { await model.refreshManagedToolStatus() }
            }

            VStack(spacing: 12) {
                cursor2APIServiceCard
                portToolsCard
            }
        }
    }

    private var cursor2APIServiceCard: some View {
        VStack(alignment: .leading, spacing: 10) {
            HStack(alignment: .top, spacing: 10) {
                ZStack {
                    RoundedRectangle(cornerRadius: 12, style: .continuous)
                        .fill(Color.blue.opacity(0.12))
                        .frame(width: 34, height: 34)
                    Image(systemName: "bolt.horizontal.circle.fill")
                        .font(.system(size: 16))
                        .foregroundStyle(.blue)
                }

                VStack(alignment: .leading, spacing: 4) {
                    HStack(spacing: 8) {
                        Text("Cursor2API")
                            .font(.headline)
                        ToolsStatusBadge(
                            text: model.cursor2APIStatus.running ? "运行中" : (model.cursor2APIStatus.installed ? "已安装" : "未安装"),
                            tint: model.cursor2APIStatus.running ? Color.mint : Color.secondary
                        )
                    }
                    Text("按默认配置托管 `cursor2api-go`，并一键切到 Claude Code 本地桥接。")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                    if let path = model.cursor2APIStatus.binaryPath {
                        Text(path)
                            .font(.caption2.monospaced())
                            .foregroundStyle(.tertiary)
                            .lineLimit(1)
                            .truncationMode(.middle)
                    }
                    Text(model.cursor2APIStatus.baseURL)
                        .font(.caption2.monospaced())
                        .foregroundStyle(.tertiary)
                        .lineLimit(1)
                        .truncationMode(.middle)
                }

                Spacer(minLength: 0)
            }

            HStack(spacing: 8) {
                serviceMetric(title: "端口", value: "\(model.cursor2APIStatus.port)", tint: .blue)
                serviceMetric(title: "API Key", value: maskedSecret(model.cursor2APIStatus.apiKey), tint: .mint)
                serviceMetric(
                    title: "模型",
                    value: model.cursor2APIStatus.models.first ?? "claude-sonnet-4.6",
                    tint: .secondary
                )
            }

            if let error = model.cursor2APIStatus.lastError?.trimmedNonEmpty {
                Text(error)
                    .font(.caption)
                    .foregroundStyle(.red)
            }

            HStack(spacing: 8) {
                Button(model.cursor2APIStatus.installed ? "重新安装" : "安装") {
                    Task { await model.installCursor2API() }
                }
                .aimenuActionButtonStyle(density: .compact)

                if model.cursor2APIStatus.running {
                    Button("停止") {
                        Task { await model.stopCursor2API() }
                    }
                    .aimenuActionButtonStyle(prominent: true, tint: .red, density: .compact)
                } else {
                    Button("启动") {
                        Task { await model.startCursor2API() }
                    }
                    .aimenuActionButtonStyle(prominent: true, tint: .blue, density: .compact)
                    .disabled(!model.cursor2APIStatus.installed)
                }

                Button("应用到 Claude") {
                    Task { await model.applyCursor2APIToClaude() }
                }
                .aimenuActionButtonStyle(prominent: true, tint: .mint, density: .compact)
                .disabled(!model.cursor2APIStatus.running)
            }
            .frame(maxWidth: .infinity, alignment: .center)

            if model.cursor2APIStatus.logPath != nil || model.cursor2APIStatus.configPath != nil {
                HStack(spacing: 8) {
                    if let logPath = model.cursor2APIStatus.logPath {
                        Button("日志") {
                            NSWorkspace.shared.selectFile(logPath, inFileViewerRootedAtPath: "")
                        }
                        .aimenuActionButtonStyle(density: .compact)
                    }

                    if let configPath = model.cursor2APIStatus.configPath {
                        Button("配置") {
                            NSWorkspace.shared.selectFile(configPath, inFileViewerRootedAtPath: "")
                        }
                        .aimenuActionButtonStyle(density: .compact)
                    }
                }
                .frame(maxWidth: .infinity, alignment: .center)
            }
        }
        .padding(12)
        .cardSurface(cornerRadius: 14, tint: Color.blue.opacity(0.03))
    }

    private var portToolsCard: some View {
        VStack(alignment: .leading, spacing: 10) {
            HStack(spacing: 8) {
                Label("端口管理", systemImage: "wave.3.right")
                    .font(.subheadline.weight(.semibold))
                ToolsStatusBadge(
                    text: "\(model.trackedPorts.filter { $0.occupied }.count)/\(model.trackedPorts.count)",
                    tint: model.trackedPorts.contains(where: \.occupied) ? .orange : .secondary
                )
            }

            portQuickControlStrip

            VStack(spacing: 6) {
                ForEach(model.trackedPorts) { status in
                    portStatusRow(status)
                }
            }
        }
        .padding(14)
        .cardSurface(cornerRadius: 14, tint: Color.orange.opacity(0.025))
    }

    private var portQuickControlStrip: some View {
        HStack(spacing: 8) {
            TextField("端口号", text: $model.customPortText)
                .font(.caption.monospaced())
                .multilineTextAlignment(.center)
                .frame(width: 92)
                .frostedRoundedInput(cornerRadius: 10)
                .onSubmit {
                    Task { await model.addTrackedPort() }
                }

            Button("关注") {
                Task { await model.addTrackedPort() }
            }
            .aimenuActionButtonStyle(prominent: true, tint: .orange, density: .compact)

            Button("刷新") {
                Task { await model.refreshTrackedPorts(showNotice: true) }
            }
            .aimenuActionButtonStyle(density: .compact)
        }
        .frame(maxWidth: .infinity, alignment: .center)
        .padding(.horizontal, 10)
        .padding(.vertical, 8)
        .cardSurface(cornerRadius: 12, tint: Color.orange.opacity(0.018))
    }

    private func portStatusRow(_ status: ManagedPortStatus) -> some View {
        let rowTint = status.occupied ? Color.orange : Color.mint

        return HStack(alignment: .center, spacing: 10) {
            Circle()
                .fill(rowTint)
                .frame(width: 8, height: 8)

            VStack(alignment: .leading, spacing: 6) {
                HStack(spacing: 6) {
                    Text("\(status.port)")
                        .font(.system(.subheadline, design: .monospaced).weight(.semibold))

                    if isDefaultTrackedPort(status.port) {
                        ToolsStatusBadge(text: "默认", tint: .secondary)
                    }
                }

                Text(status.command?.trimmedNonEmpty ?? "当前空闲")
                    .font(.caption)
                    .foregroundStyle(status.occupied ? .primary : .secondary)
                    .lineLimit(1)
            }

            Spacer(minLength: 0)

            HStack(spacing: 6) {
                Button("解除占用") {
                    Task { await model.releaseTrackedPort(status.port) }
                }
                .aimenuActionButtonStyle(prominent: true, tint: .orange, density: .compact)
                .disabled(!status.occupied)

                Button("强制解除") {
                    Task { await model.releaseTrackedPort(status.port, force: true) }
                }
                .aimenuActionButtonStyle(density: .compact)
                .disabled(!status.occupied)

                if !isDefaultTrackedPort(status.port) {
                    Button {
                        Task { await model.removeTrackedPort(status.port) }
                    } label: {
                        Image(systemName: "xmark")
                            .font(.caption2.weight(.bold))
                    }
                    .liquidGlassActionButtonStyle(density: .compact)
                    .help("移除此端口")
                }
            }
        }
        .padding(.horizontal, 10)
        .padding(.vertical, 9)
        .background(
            RoundedRectangle(cornerRadius: 10, style: .continuous)
                .fill(rowTint.opacity(0.025))
                .overlay(
                    RoundedRectangle(cornerRadius: 10, style: .continuous)
                        .strokeBorder(rowTint.opacity(0.06), lineWidth: 1)
                )
        )
    }

    private func isDefaultTrackedPort(_ port: Int) -> Bool {
        [8002, 8787].contains(port)
    }

    // MARK: - Local Config Overview

    private var configsSection: some View {
        VStack(alignment: .leading, spacing: 12) {
            overviewActionStrip(
                title: "刷新配置",
                tint: .green,
                help: "刷新本地配置状态"
            ) {
                Task { await model.refreshLocalConfigBundles() }
            }

            localConfigContent
        }
    }

    @ViewBuilder
    private var localConfigContent: some View {
        if model.localConfigBundles.isEmpty {
            compactEmptyState(
                icon: "folder.badge.gearshape",
                title: "暂无本地配置概览",
                message: "扫描到配置文件后会在这里汇总显示。",
                tint: .green
            )
        } else {
            LazyVGrid(columns: [GridItem(.adaptive(minimum: 220), spacing: 10)], spacing: 10) {
                ForEach(model.localConfigBundles) { bundle in
                    localConfigBundleCard(bundle)
                }
            }
        }
    }

    private func localConfigBundleCard(_ bundle: LocalConfigBundle) -> some View {
        VStack(alignment: .leading, spacing: 10) {
            HStack(alignment: .top, spacing: 10) {
                ZStack {
                    RoundedRectangle(cornerRadius: 12, style: .continuous)
                        .fill(localConfigAccent(for: bundle.app).opacity(0.12))
                        .frame(width: 38, height: 38)
                    Image(systemName: bundle.app.iconName)
                        .font(.system(size: 18, weight: .medium))
                        .foregroundStyle(localConfigAccent(for: bundle.app))
                }

                VStack(alignment: .leading, spacing: 4) {
                    HStack(spacing: 8) {
                        Text(bundle.app.displayName)
                            .font(.headline)
                        ToolsStatusBadge(
                            text: "\(bundle.existingFileCount)/\(bundle.files.count)",
                            tint: bundle.existingFileCount == bundle.files.count ? Color.mint : Color.orange
                        )
                    }
                    Text(tildePath(bundle.rootPath))
                        .font(.caption2.monospaced())
                        .foregroundStyle(.secondary)
                        .lineLimit(1)
                        .truncationMode(.middle)
                    if let latestText = localConfigLatestText(bundle.latestModifiedAt) {
                        Text(latestText)
                            .font(.caption2)
                            .foregroundStyle(.tertiary)
                    }
                }

                Spacer(minLength: 0)

                Button {
                    openDirectory(bundle.rootPath)
                } label: {
                    Image(systemName: "folder")
                }
                .liquidGlassActionButtonStyle(density: .compact)
                .disabled(bundle.existingFileCount == 0)
                .help("打开 \(bundle.app.displayName) 配置目录")
            }

            VStack(spacing: 6) {
                ForEach(bundle.files) { file in
                    localConfigFileRow(file)
                }
            }
        }
        .padding(14)
        .cardSurface(cornerRadius: 14, tint: localConfigAccent(for: bundle.app).opacity(0.05))
    }

    private func localConfigFileRow(_ file: LocalConfigFile) -> some View {
        HStack(alignment: .top, spacing: 10) {
            Circle()
                .fill(file.exists ? Color.mint : Color.secondary.opacity(0.3))
                .frame(width: 7, height: 7)
                .padding(.top, 6)

            VStack(alignment: .leading, spacing: 4) {
                HStack(spacing: 6) {
                    Text(file.label)
                        .font(.caption.weight(.semibold))
                    ToolsStatusBadge(text: file.kind.displayName, tint: localConfigKindTint(file.kind))
                    ToolsStatusBadge(
                        text: file.exists ? "可见" : "缺失",
                        tint: file.exists ? Color.mint : Color.secondary
                    )
                }

                Text(tildePath(file.path))
                    .font(.caption2.monospaced())
                    .foregroundStyle(.tertiary)
                    .lineLimit(1)
                    .truncationMode(.middle)

                if let metaText = localConfigMetaText(file) {
                    Text(metaText)
                        .font(.caption2)
                        .foregroundStyle(.secondary)
                }
            }

            Spacer(minLength: 0)

            if file.exists {
                Button {
                    NSWorkspace.shared.selectFile(file.path, inFileViewerRootedAtPath: "")
                } label: {
                    Image(systemName: "arrow.up.right.square")
                }
                .liquidGlassActionButtonStyle(density: .compact)
                .help("在 Finder 中定位 \(file.label)")
            }
        }
        .padding(.horizontal, 10)
        .padding(.vertical, 8)
        .background(Color.primary.opacity(0.025), in: RoundedRectangle(cornerRadius: 10, style: .continuous))
    }

    // MARK: - MCP Servers

    private var mcpSection: some View {
        SectionCard(
            title: "MCP 服务器",
            icon: "server.rack",
            iconColor: .blue,
            headerTrailing: {
                if !isWorkbenchMode {
                    CollapseChevronButton(isExpanded: mcpExpanded) {
                        withAnimation(.easeInOut(duration: 0.2)) { mcpExpanded.toggle() }
                    }
                }
            }
        ) {
            VStack(alignment: .leading, spacing: 8) {
                mcpActionButtons

                if isWorkbenchMode || mcpExpanded {
                    if showMCPPresets {
                        mcpPresetsGrid
                            .transition(.move(edge: .top).combined(with: .opacity))
                    }

                    if model.mcpServers.isEmpty {
                        mcpEmptyState
                    } else {
                        VStack(spacing: 2) {
                            ForEach(model.mcpServers) { server in
                                mcpServerRow(server)
                            }
                        }
                    }
                } else {
                    mcpCollapsedSummary
                }
            }
        }
    }

    private var mcpActionButtons: some View {
        HStack(spacing: LayoutRules.listRowSpacing) {
            Button {
                withAnimation(.spring(duration: 0.25)) { showMCPPresets.toggle() }
            } label: {
                Label(showMCPPresets ? "隐藏预设" : "预设", systemImage: showMCPPresets ? "square.grid.2x2.fill" : "square.grid.2x2")
                    .lineLimit(1)
            }
            .aimenuActionButtonStyle(prominent: true, tint: .blue, density: .compact)
            .help(showMCPPresets ? "收起 MCP 预设" : "显示 MCP 预设")

            Button {
                Task { await model.importLiveMCPServers() }
            } label: {
                Label("导入", systemImage: "square.and.arrow.down")
                    .lineLimit(1)
            }
            .aimenuActionButtonStyle(prominent: true, density: .compact)
            .help("从 Claude / Codex / Gemini 导入 MCP")

            Button {
                editingMCPServer = nil
                showMCPForm = true
            } label: {
                Label("添加", systemImage: "plus")
                    .lineLimit(1)
            }
            .aimenuActionButtonStyle(prominent: true, tint: .mint, density: .compact)
            .help("添加自定义 MCP 服务器")
        }
        .frame(maxWidth: .infinity, alignment: .center)
    }

    private var mcpEmptyState: some View {
        compactEmptyState(
            icon: "server.rack",
            title: "暂未配置 MCP 服务器",
            message: "可从上方预设、导入或添加自定义服务。",
            tint: .blue
        )
    }

    private var mcpPresetsGrid: some View {
        VStack(alignment: .leading, spacing: 6) {
            Text("从预设添加")
                .font(.caption.weight(.semibold))
                .foregroundStyle(.secondary)

            LazyVGrid(columns: [GridItem(.adaptive(minimum: 90), spacing: 6)], spacing: 6) {
                ForEach(ProviderPresets.mcpPresets) { preset in
                    let alreadyAdded = model.mcpServers.contains(where: { $0.name == preset.name })
                    Button {
                        Task { await model.addMCPFromPreset(preset) }
                    } label: {
                        HStack(spacing: 4) {
                            Image(systemName: presetIcon(for: preset))
                                .font(.caption2)
                            Text(preset.name)
                                .font(.caption)
                                .lineLimit(1)
                            if alreadyAdded {
                                Image(systemName: "checkmark")
                                    .font(.caption2)
                                    .foregroundStyle(.mint)
                            }
                        }
                    }
                    .aimenuActionButtonStyle(density: .compact)
                    .disabled(alreadyAdded)
                    .opacity(alreadyAdded ? 0.5 : 1)
                }

                Button {
                    editingMCPServer = nil
                    showMCPForm = true
                } label: {
                    HStack(spacing: 4) {
                        Image(systemName: "slider.horizontal.3")
                            .font(.caption2)
                        Text("自定义")
                            .font(.caption)
                            .lineLimit(1)
                    }
                }
                .aimenuActionButtonStyle(prominent: true, tint: .blue, density: .compact)
            }

            Divider()
        }
    }

    private func presetIcon(for preset: MCPPreset) -> String {
        let id = preset.id.lowercased()
        if id.contains("github") { return "chevron.left.forwardslash.chevron.right" }
        if id.contains("filesystem") || id.contains("file") { return "folder" }
        if id.contains("fetch") || id.contains("web") || id.contains("browser") { return "globe" }
        if id.contains("memory") { return "memorychip" }
        if id.contains("postgres") || id.contains("sqlite") || id.contains("db") { return "cylinder" }
        if id.contains("slack") { return "bubble.left.and.bubble.right" }
        if id.contains("time") { return "clock" }
        return "puzzlepiece.extension"
    }

    private var mcpCollapsedSummary: some View {
        let enabled = model.mcpServers.filter { $0.isEnabled }.count
        let total = model.mcpServers.count
        return Group {
            if total == 0 {
                Text("暂无服务器")
                    .font(.subheadline)
                    .foregroundStyle(.secondary)
            } else {
                HStack(spacing: 6) {
                    Circle()
                        .fill(enabled > 0 ? Color.mint : Color.secondary)
                        .frame(width: 6, height: 6)
                    Text("\(enabled) / \(total) 已启用")
                        .font(.subheadline)
                        .foregroundStyle(.secondary)
                }
            }
        }
    }

    @State private var expandedMCPServer: String? = nil

    private func mcpServerRow(_ server: MCPServer) -> some View {
        VStack(spacing: 0) {
            // 主行
            HStack(spacing: 10) {
                // 状态点
                Circle()
                    .fill(server.isEnabled ? Color.mint : Color.secondary.opacity(0.35))
                    .frame(width: 7, height: 7)

                // 名称 + 命令预览
                VStack(alignment: .leading, spacing: 2) {
                    Text(server.name)
                        .font(.subheadline.weight(.medium))
                        .foregroundStyle(server.isEnabled ? .primary : .secondary)

                    if !server.server.displayCommand.isEmpty {
                        Text(server.server.displayCommand)
                            .font(.system(.caption, design: .monospaced))
                            .foregroundStyle(.tertiary)
                            .lineLimit(1)
                            .truncationMode(.middle)
                    }
                }

                Spacer(minLength: 0)

                // 右侧操作区
                HStack(spacing: 6) {
                    // 展开/收起
                    Button {
                        withAnimation(.spring(duration: 0.25)) {
                            expandedMCPServer = expandedMCPServer == server.id ? nil : server.id
                        }
                    } label: {
                        Image(systemName: expandedMCPServer == server.id ? "chevron.up" : "chevron.down")
                            .font(.caption.weight(.semibold))
                    }
                    .liquidGlassActionButtonStyle(density: .compact)

                    Button {
                        editingMCPServer = server
                        showMCPForm = true
                    } label: {
                        Image(systemName: "pencil")
                            .font(.caption.weight(.semibold))
                    }
                    .liquidGlassActionButtonStyle(density: .compact)

                    // 删除（hover 才显示）
                    Button(role: .destructive) {
                        Task { await model.deleteMCPServer(id: server.id) }
                    } label: {
                        Image(systemName: "trash")
                            .foregroundStyle(.red.opacity(0.8))
                    }
                    .liquidGlassActionButtonStyle(density: .compact)
                    .accessibilityLabel("删除 \(server.name)")
                    .opacity(hoveredMCPServer == server.id ? 1 : 0.28)
                }
                .animation(.easeInOut(duration: 0.15), value: hoveredMCPServer)
            }
            .padding(.horizontal, 10)
            .padding(.vertical, 8)
            .contentShape(Rectangle())
            .onTapGesture {
                withAnimation(.spring(duration: 0.25)) {
                    expandedMCPServer = expandedMCPServer == server.id ? nil : server.id
                }
            }

            // 展开详情
            if expandedMCPServer == server.id {
                VStack(alignment: .leading, spacing: 10) {
                    Divider().padding(.horizontal, 10)

                    // 命令详情
                    VStack(alignment: .leading, spacing: 4) {
                        Text("命令")
                            .font(.caption.weight(.semibold))
                            .foregroundStyle(.secondary)
                        Text(server.server.displayCommand.isEmpty ? "—" : server.server.displayCommand)
                            .font(.system(.caption, design: .monospaced))
                            .foregroundStyle(.primary)
                            .textSelection(.enabled)
                            .padding(8)
                            .frame(maxWidth: .infinity, alignment: .leading)
                            .background(Color.primary.opacity(0.05), in: RoundedRectangle(cornerRadius: 6))
                    }
                    .padding(.horizontal, 10)

                    // 工作目录（若有）
                    if let cwd = server.server.cwd, !cwd.isEmpty {
                        VStack(alignment: .leading, spacing: 4) {
                            Text("工作目录")
                                .font(.caption.weight(.semibold))
                                .foregroundStyle(.secondary)
                            Text(cwd)
                                .font(.system(.caption, design: .monospaced))
                                .foregroundStyle(.primary)
                                .textSelection(.enabled)
                                .padding(8)
                                .frame(maxWidth: .infinity, alignment: .leading)
                                .background(Color.primary.opacity(0.05), in: RoundedRectangle(cornerRadius: 6))
                        }
                        .padding(.horizontal, 10)
                    }

                    // App 开关
                    VStack(alignment: .leading, spacing: 6) {
                        Text("启用应用")
                            .font(.caption.weight(.semibold))
                            .foregroundStyle(.secondary)
                        HStack(spacing: 8) {
                            mcpAppToggle(label: "Claude Code", app: .claude, isOn: server.apps.claude, onChange: { v in
                                Task { await model.toggleMCPApp(serverId: server.id, app: .claude, enabled: v) }
                            })
                            mcpAppToggle(label: "Codex", app: .codex, isOn: server.apps.codex, onChange: { v in
                                Task { await model.toggleMCPApp(serverId: server.id, app: .codex, enabled: v) }
                            })
                            mcpAppToggle(label: "Gemini", app: .gemini, isOn: server.apps.gemini, onChange: { v in
                                Task { await model.toggleMCPApp(serverId: server.id, app: .gemini, enabled: v) }
                            })
                        }
                    }
                    .padding(.horizontal, 10)
                    .padding(.bottom, 10)
                }
                .transition(.opacity.combined(with: .move(edge: .top)))
            }
        }
        .background {
            RoundedRectangle(cornerRadius: 8)
                .fill(hoveredMCPServer == server.id
                      ? Color.primary.opacity(0.05)
                      : Color.clear)
        }
        .animation(.easeInOut(duration: 0.15), value: hoveredMCPServer)
        .onHover { isHovered in hoveredMCPServer = isHovered ? server.id : nil }
    }

    private func mcpAppToggle(
        label: String,
        app: ProviderAppType,
        isOn: Bool,
        onChange: @escaping (Bool) -> Void
    ) -> some View {
        appMountChip(app: app, label: label, isOn: isOn, onChange: onChange)
    }

    // MARK: - Prompts

    private var promptsSection: some View {
        SectionCard(
            title: "提示词",
            icon: "text.bubble",
            iconColor: .purple,
            headerTrailing: {
                if isWorkbenchMode {
                    HStack(spacing: 6) {
                        workbenchActionButton(
                            "新建",
                            systemImage: "plus",
                            tint: .purple,
                            prominent: true,
                            help: "新建提示词"
                        ) {
                            editingPrompt = nil
                            showPromptEditor = true
                        }

                        workbenchMoreMenu(help: "更多 Prompt 操作") {
                            Button("从 \(model.selectedPromptApp.fileName) 导入") {
                                Task { await model.importLivePrompt() }
                            }
                            Button("打开 \(model.selectedPromptApp.fileName)") {
                                NSWorkspace.shared.selectFile(model.selectedPromptApp.filePath.path, inFileViewerRootedAtPath: "")
                            }
                        }
                    }
                } else {
                    HStack(spacing: 6) {
                        if promptsExpanded {
                            promptAppPicker
                                .frame(maxWidth: 160)

                            Button {
                                Task { await model.importLivePrompt() }
                            } label: {
                                Image(systemName: "square.and.arrow.down")
                            }
                            .liquidGlassActionButtonStyle(density: .compact)
                            .help("从 \(model.selectedPromptApp.fileName) 导入")

                            Button {
                                NSWorkspace.shared.selectFile(model.selectedPromptApp.filePath.path, inFileViewerRootedAtPath: "")
                            } label: {
                                Image(systemName: "doc.text")
                            }
                            .liquidGlassActionButtonStyle(density: .compact)
                            .help("打开 \(model.selectedPromptApp.fileName)")

                            Button {
                                editingPrompt = nil
                                showPromptEditor = true
                            } label: {
                                Image(systemName: "plus")
                            }
                            .liquidGlassActionButtonStyle(density: .compact)
                        }

                        CollapseChevronButton(isExpanded: promptsExpanded) {
                            withAnimation(.easeInOut(duration: 0.2)) { promptsExpanded.toggle() }
                        }
                    }
                }
            }
        ) {
            if isWorkbenchMode || promptsExpanded {
                promptsContent
            }
        }
    }

    @ViewBuilder
    private var promptsContent: some View {
        if isWorkbenchMode {
            workbenchStrip(tint: .purple) {
                promptAppPicker
                ToolsStatusBadge(text: "\(model.prompts.count) 条", tint: .purple)
            }
        }

        promptLiveFileBar

        if model.prompts.isEmpty {
            compactEmptyState(
                icon: "text.bubble",
                title: "暂无提示词",
                message: "点击新建，或从当前应用的文件直接导入。",
                tint: .purple
            )
        } else {
            VStack(spacing: 2) {
                ForEach(model.prompts) { prompt in
                    promptRow(prompt)
                }
            }
        }
    }

    private var promptLiveFileBar: some View {
        workbenchStrip {
            Label(model.selectedPromptApp.fileName, systemImage: "doc.text")
                .font(.caption.weight(.medium))
            Text(model.selectedPromptApp.filePath.path)
                .font(.caption2.monospaced())
                .foregroundStyle(.tertiary)
                .lineLimit(1)
                .truncationMode(.middle)
            Spacer(minLength: 0)
        }
    }

    private func promptRow(_ prompt: Prompt) -> some View {
        HStack(spacing: 10) {
            RoundedRectangle(cornerRadius: 2)
                .fill(prompt.isActive ? Color.purple : Color.clear)
                .frame(width: 3, height: 34)

            VStack(alignment: .leading, spacing: 2) {
                Text(prompt.name)
                    .font(.subheadline.weight(.medium))
                    .foregroundStyle(prompt.isActive ? .primary : .secondary)

                if let desc = prompt.description, !desc.isEmpty {
                    Text(desc)
                        .font(.caption)
                        .foregroundStyle(.secondary)
                        .lineLimit(1)
                } else if !prompt.content.isEmpty {
                    Text(prompt.content)
                        .font(.caption)
                        .foregroundStyle(.tertiary)
                        .lineLimit(1)
                        .truncationMode(.tail)
                }
            }

            Spacer(minLength: 0)

            HStack(spacing: 4) {
                if prompt.isActive {
                    Text(L10n.tr("tools.prompt.badge.active"))
                        .font(.caption2.weight(.medium))
                        .foregroundStyle(.purple)
                        .padding(.horizontal, 6)
                        .padding(.vertical, 2)
                        .background(Color.purple.opacity(0.12), in: Capsule())
                }

                Button {
                    Task { await model.activatePrompt(id: prompt.id) }
                } label: {
                    Image(systemName: prompt.isActive ? "checkmark.circle.fill" : "arrow.up.circle")
                        .foregroundStyle(prompt.isActive ? .purple : .secondary)
                }
                .liquidGlassActionButtonStyle(density: .compact)
                .help(
                    prompt.isActive
                        ? L10n.tr("tools.prompt.badge.active")
                        : L10n.tr("tools.prompt.help.activate_format", model.selectedPromptApp.fileName)
                )

                Button {
                    editingPrompt = prompt
                    showPromptEditor = true
                } label: {
                    Image(systemName: "pencil")
                }
                .liquidGlassActionButtonStyle(density: .compact)

                Button(role: .destructive) {
                    Task { await model.deletePrompt(id: prompt.id) }
                } label: {
                    Image(systemName: "trash")
                        .foregroundStyle(.red.opacity(0.8))
                }
                .liquidGlassActionButtonStyle(density: .compact)
                .opacity(hoveredPrompt == prompt.id ? 1 : 0.28)
                .accessibilityLabel(L10n.tr("tools.prompt.delete_accessibility_format", prompt.name))
            }
            .animation(.easeInOut(duration: 0.15), value: hoveredPrompt)
        }
        .padding(.horizontal, 8)
        .padding(.vertical, 6)
        .background {
            RoundedRectangle(cornerRadius: 8)
                .fill(hoveredPrompt == prompt.id
                      ? Color.primary.opacity(0.05)
                      : Color.clear)
        }
        .animation(.easeInOut(duration: 0.15), value: hoveredPrompt)
        .onHover { isHovered in hoveredPrompt = isHovered ? prompt.id : nil }
    }

    // MARK: - Hooks

    private var hooksSection: some View {
        SectionCard(
            title: "Hooks",
            icon: "point.3.connected.trianglepath.dotted",
            iconColor: .indigo,
            headerTrailing: {
                if isWorkbenchMode {
                    HStack(spacing: 6) {
                        workbenchActionButton(
                            "刷新",
                            systemImage: "arrow.clockwise",
                            tint: .indigo,
                            prominent: true,
                            help: "刷新 Hooks"
                        ) {
                            Task { await model.refreshClaudeHooks() }
                        }

                        workbenchMoreMenu(help: "更多 Hooks 操作") {
                            Button("打开 Claude settings.json") {
                                NSWorkspace.shared.selectFile(NSHomeDirectory() + "/.claude/settings.json", inFileViewerRootedAtPath: "")
                            }
                            Button("打开 Codex hooks.json") {
                                NSWorkspace.shared.selectFile(NSHomeDirectory() + "/.codex/hooks.json", inFileViewerRootedAtPath: "")
                            }
                            Button("打开 Gemini settings.json") {
                                NSWorkspace.shared.selectFile(NSHomeDirectory() + "/.gemini/settings.json", inFileViewerRootedAtPath: "")
                            }
                        }
                    }
                } else {
                    HStack(spacing: 6) {
                        Button {
                            Task { await model.refreshClaudeHooks() }
                        } label: {
                            Image(systemName: "arrow.clockwise")
                        }
                        .liquidGlassActionButtonStyle(density: .compact)
                        .help("刷新 Hooks")

                        Button {
                            NSWorkspace.shared.selectFile(NSHomeDirectory() + "/.claude/settings.json", inFileViewerRootedAtPath: "")
                        } label: {
                            Image(systemName: "doc.text")
                        }
                        .liquidGlassActionButtonStyle(density: .compact)
                        .help("打开 Claude settings.json")

                        CollapseChevronButton(isExpanded: hooksExpanded) {
                            withAnimation(.easeInOut(duration: 0.2)) { hooksExpanded.toggle() }
                        }
                    }
                }
            }
        ) {
            if isWorkbenchMode || hooksExpanded {
                hooksContent
            }
        }
    }

    @ViewBuilder
    private var hooksContent: some View {
        let hookGroups = groupedClaudeHooks

        workbenchStrip(tint: .indigo) {
            Label("已挂载", systemImage: "point.3.connected.trianglepath.dotted")
                .font(.caption.weight(.medium))
            ForEach(ProviderAppType.allCases) { app in
                if model.claudeHooks.contains(where: { $0.apps.isEnabled(for: app) }) {
                    ToolsStatusBadge(text: compactAppName(for: app), tint: localConfigAccent(for: app))
                }
            }
            Text("\(model.claudeHooks.count) 条")
                .font(.caption2.weight(.semibold))
                .foregroundStyle(.secondary)
                .padding(.horizontal, 7)
                .padding(.vertical, 4)
                .background(Color.primary.opacity(0.05), in: Capsule())
            if !hookGroups.isEmpty {
                Text("\(hookGroups.count) 组")
                    .font(.caption2.weight(.semibold))
                    .foregroundStyle(.secondary)
                    .padding(.horizontal, 7)
                    .padding(.vertical, 4)
                    .background(Color.indigo.opacity(0.08), in: Capsule())
            }
            Spacer(minLength: 0)
        }

        if model.claudeHooks.isEmpty {
            compactEmptyState(
                icon: "point.3.connected.trianglepath.dotted",
                title: "未扫描到 Hooks",
                message: "刷新后会读取 Claude、Codex 与 Gemini 的本地 Hooks。",
                tint: .indigo
            )
        } else {
            VStack(spacing: 8) {
                ForEach(hookGroups, id: \.event) { group in
                    claudeHookGroup(event: group.event, hooks: group.hooks)
                }
            }
        }
    }

    private func claudeHookGroup(event: String, hooks: [ClaudeHook]) -> some View {
        VStack(alignment: .leading, spacing: 6) {
            HStack(spacing: 8) {
                ToolsStatusBadge(text: event, tint: Color.indigo)
                Text("\(hooks.count) 条")
                    .font(.caption2.weight(.semibold))
                    .foregroundStyle(.secondary)
                Spacer(minLength: 0)
                if hooks.contains(where: { $0.scope == .project }) {
                    ToolsStatusBadge(text: "含项目级", tint: Color.orange)
                }
            }

            VStack(spacing: 4) {
                ForEach(hooks, id: \.identityKey) { hook in
                    claudeHookRow(hook)
                }
            }
        }
        .padding(8)
        .background(Color.indigo.opacity(0.035), in: RoundedRectangle(cornerRadius: 10, style: .continuous))
    }

    private func claudeHookRow(_ hook: ClaudeHook) -> some View {
        HStack(alignment: .top, spacing: 10) {
            Circle()
                .fill(hook.enabled ? Color.mint : Color.secondary.opacity(0.35))
                .frame(width: 7, height: 7)
                .padding(.top, 7)

            VStack(alignment: .leading, spacing: 5) {
                HStack(spacing: 6) {
                    if let matcher = hook.matcher?.trimmedNonEmpty {
                        ToolsStatusBadge(text: matcher, tint: Color.secondary)
                    }
                    ToolsStatusBadge(text: hook.scope.displayName, tint: Color.secondary)
                    if let commandType = hook.commandType?.trimmedNonEmpty {
                        ToolsStatusBadge(text: commandType, tint: Color.blue)
                    }
                    if let timeout = hook.timeout {
                        ToolsStatusBadge(text: "\(timeout)s", tint: Color.orange)
                    }
                }

                Text(hook.command)
                    .font(.system(.caption, design: .monospaced))
                    .foregroundStyle(.primary)
                    .lineLimit(2)
                    .truncationMode(.middle)

                HStack(spacing: 6) {
                    ForEach(ProviderAppType.allCases) { app in
                            appMountChip(
                                app: app,
                                isOn: hook.apps.isEnabled(for: app),
                                disabled: !hook.supports(app: app),
                                onChange: { enabled in
                                Task { await model.toggleHookApp(hookIdentity: hook.identityKey, app: app, enabled: enabled) }
                                }
                            )
                        }
                    Spacer(minLength: 0)
                }

                Text(hook.sourcePath)
                    .font(.caption2.monospaced())
                    .foregroundStyle(.tertiary)
                    .lineLimit(1)
                    .truncationMode(.middle)
            }

            Spacer(minLength: 0)
        }
        .padding(.horizontal, 8)
        .padding(.vertical, 7)
        .background(Color.primary.opacity(0.03), in: RoundedRectangle(cornerRadius: 8, style: .continuous))
    }

    // MARK: - Skills

    private var skillsSection: some View {
        SectionCard(
            title: "快捷技能",
            icon: "wand.and.stars",
            iconColor: .orange,
            headerTrailing: {
                if isWorkbenchMode {
                    HStack(spacing: 6) {
                        workbenchActionButton(
                            model.skillDiscoveryLoading ? "发现中" : "发现",
                            systemImage: "sparkles",
                            tint: .orange,
                            prominent: true,
                            help: "发现可安装技能"
                        ) {
                            Task { await model.discoverSkills() }
                        }
                        .disabled(model.skillDiscoveryLoading)

                        workbenchActionButton(
                            "扫描",
                            systemImage: "arrow.clockwise",
                            help: "扫描 ~/.claude/skills"
                        ) {
                            Task { await model.refreshSkillsFromDisk() }
                        }

                        workbenchMoreMenu(help: "更多 Skills 操作") {
                            Button("添加技能仓库") {
                                showSkillRepoEditor = true
                            }
                            Button("打开技能目录") {
                                NSWorkspace.shared.selectFile(
                                    NSHomeDirectory() + "/.claude/skills",
                                    inFileViewerRootedAtPath: ""
                                )
                            }
                        }
                    }
                } else {
                    HStack(spacing: 6) {
                        Button {
                            Task { await model.discoverSkills() }
                        } label: {
                            if model.skillDiscoveryLoading {
                                ProgressView()
                                    .controlSize(.small)
                            } else {
                                Image(systemName: "sparkles")
                            }
                        }
                        .liquidGlassActionButtonStyle(density: .compact)
                        .help("发现可安装技能")

                        Button {
                            showSkillRepoEditor = true
                        } label: {
                            Image(systemName: "plus")
                        }
                        .liquidGlassActionButtonStyle(density: .compact)
                        .help("添加技能仓库")

                        Button {
                            Task { await model.refreshSkillsFromDisk() }
                        } label: {
                            Image(systemName: "arrow.clockwise")
                        }
                        .liquidGlassActionButtonStyle(density: .compact)
                        .help("扫描 ~/.claude/skills")

                        Button {
                            NSWorkspace.shared.selectFile(
                                NSHomeDirectory() + "/.claude/skills",
                                inFileViewerRootedAtPath: ""
                            )
                        } label: {
                            Image(systemName: "folder")
                        }
                        .liquidGlassActionButtonStyle(density: .compact)
                        .help("打开技能目录")

                        CollapseChevronButton(isExpanded: skillsExpanded) {
                            withAnimation(.easeInOut(duration: 0.2)) { skillsExpanded.toggle() }
                        }
                    }
                }
            }
        ) {
            if isWorkbenchMode || skillsExpanded {
                skillsContent
            }
        }
    }

    @ViewBuilder
    private var skillsContent: some View {
        let installed = visibleInstalledSkills
        let discoverable = visibleDiscoverableSkills
        VStack(alignment: .leading, spacing: 10) {
            skillReposRow
            skillsSearchRow

            if selectedSkillsFilter != .installed && (model.skillDiscoveryLoading || !model.discoverableSkills.isEmpty) {
                discoverableSkillsPanel(skills: discoverable)
            }

            if hasSkillsSearchQuery && installed.isEmpty && discoverable.isEmpty && !model.skillDiscoveryLoading {
                compactEmptyState(
                    icon: "magnifyingglass",
                    title: "没有匹配的技能",
                    message: "换个关键词，或者切换到其他筛选试试。",
                    tint: .orange
                )
            } else if selectedSkillsFilter == .installed && model.skills.installedSkills.isEmpty {
                compactEmptyState(
                    icon: "wand.and.stars",
                    title: "暂未安装技能",
                    message: "可以先发现可安装技能，再按应用挂载。",
                    tint: .orange
                )
            } else if !installed.isEmpty {
                VStack(alignment: .leading, spacing: 8) {
                    HStack {
                        Text("已安装")
                            .font(.caption.weight(.semibold))
                            .foregroundStyle(.secondary)
                        Text("\(installed.count)")
                            .font(.caption2.weight(.semibold))
                            .foregroundStyle(.secondary)
                            .padding(.horizontal, 7)
                            .padding(.vertical, 4)
                            .background(Color.orange.opacity(0.08), in: Capsule())
                        Spacer(minLength: 0)
                    }

                    VStack(spacing: 2) {
                        ForEach(installed) { skill in
                            skillRow(skill)
                        }
                    }
                }
            } else if selectedSkillsFilter == .discoverable && discoverable.isEmpty && !model.skillDiscoveryLoading {
                EmptyView()
            }
        }
    }

    private var skillsSearchRow: some View {
        VStack(alignment: .leading, spacing: 8) {
            HStack(spacing: 10) {
                HStack(spacing: 8) {
                    Image(systemName: "magnifyingglass")
                        .font(.subheadline.weight(.semibold))
                        .foregroundStyle(Color.orange.opacity(0.9))

                    TextField("搜索技能、仓库或目录", text: $skillsSearchText)
                        .textFieldStyle(.plain)
                        .font(.subheadline)

                    if !skillsSearchText.isEmpty {
                        Button {
                            skillsSearchText = ""
                        } label: {
                            Image(systemName: "xmark.circle.fill")
                                .foregroundStyle(.tertiary)
                        }
                        .buttonStyle(.plain)
                    }
                }
                .padding(.horizontal, 12)
                .padding(.vertical, 9)
                .frame(maxWidth: .infinity)
                .background(
                    RoundedRectangle(cornerRadius: 12, style: .continuous)
                        .fill(Color.orange.opacity(0.08))
                        .overlay(
                            RoundedRectangle(cornerRadius: 12, style: .continuous)
                                .strokeBorder(Color.orange.opacity(0.14), lineWidth: 1)
                        )
                )

                if !model.skills.installedSkills.isEmpty {
                    skillCountBadge(title: "已装", count: filteredInstalledSkills.count, tint: .orange)
                }

                if model.skillDiscoveryLoading || !model.discoverableSkills.isEmpty {
                    skillCountBadge(title: "可装", count: filteredDiscoverableSkills.count, tint: .blue)
                }
            }

            ScrollView(.horizontal, showsIndicators: false) {
                HStack(spacing: 8) {
                    ForEach(SkillsFilter.allCases) { filter in
                        Button {
                            withAnimation(.easeInOut(duration: 0.16)) {
                                selectedSkillsFilter = filter
                            }
                        } label: {
                            HStack(spacing: 6) {
                                Text(filter.title)
                                    .font(.caption.weight(.semibold))
                                Text("\(count(for: filter))")
                                    .font(.caption2.weight(.bold))
                                    .foregroundStyle(selectedSkillsFilter == filter ? Color.white.opacity(0.88) : .secondary)
                            }
                            .padding(.horizontal, 10)
                            .padding(.vertical, 7)
                        }
                        .buttonStyle(.plain)
                        .background(
                            Capsule()
                                .fill(selectedSkillsFilter == filter ? Color.orange.opacity(0.92) : Color.primary.opacity(0.05))
                        )
                        .foregroundStyle(selectedSkillsFilter == filter ? Color.white : Color.primary)
                    }
                }
            }
        }
    }

    private func skillCountBadge(title: String, count: Int, tint: Color) -> some View {
        HStack(spacing: 6) {
            Text(title)
                .font(.caption.weight(.semibold))
            Text("\(count)")
                .font(.caption2.weight(.bold))
                .foregroundStyle(.secondary)
        }
        .padding(.horizontal, 10)
        .padding(.vertical, 8)
        .background(tint.opacity(0.08), in: Capsule())
    }

    private var skillReposRow: some View {
        ScrollView(.horizontal, showsIndicators: false) {
            HStack(spacing: 8) {
                ForEach(model.skills.repos) { repo in
                    HStack(spacing: 6) {
                        Button {
                            Task { await model.setSkillRepoEnabled(repo, enabled: !repo.isEnabled) }
                        } label: {
                            HStack(spacing: 6) {
                                Image(systemName: repo.isEnabled ? "checkmark.circle.fill" : "circle")
                                    .font(.caption.weight(.semibold))
                                    .foregroundStyle(repo.isEnabled ? .mint : .secondary)
                                Text("\(repo.owner)/\(repo.name)")
                                    .font(.caption.weight(.medium))
                                Text(repo.branch)
                                    .font(.caption2.monospaced())
                                    .foregroundStyle(.secondary)
                            }
                            .padding(.horizontal, 10)
                            .padding(.vertical, 7)
                            .background(repo.isEnabled ? Color.mint.opacity(0.08) : Color.primary.opacity(0.05), in: Capsule())
                        }
                        .buttonStyle(.plain)

                        if !repo.isDefault {
                            Button(role: .destructive) {
                                Task { await model.removeSkillRepo(repo) }
                            } label: {
                                Image(systemName: "xmark")
                                    .font(.caption2.weight(.bold))
                                    .foregroundStyle(.red.opacity(0.85))
                            }
                            .buttonStyle(.plain)
                        }
                    }
                    .opacity(repo.isEnabled ? 1 : 0.72)
                }
            }
        }
    }

    private func discoverableSkillsPanel(skills: [DiscoverableSkill]) -> some View {
        VStack(alignment: .leading, spacing: 8) {
            HStack {
                Text("可安装")
                    .font(.caption.weight(.semibold))
                    .foregroundStyle(.secondary)
                Text("\(skills.count)")
                    .font(.caption2.weight(.semibold))
                    .foregroundStyle(.secondary)
                    .padding(.horizontal, 7)
                    .padding(.vertical, 4)
                    .background(Color.blue.opacity(0.08), in: Capsule())
                Spacer(minLength: 0)
            }

            if model.skillDiscoveryLoading {
                workbenchStrip(tint: .blue) {
                    ProgressView()
                        .controlSize(.small)
                    Text("正在读取技能仓库…")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }
            } else if skills.isEmpty {
                workbenchStrip {
                    Image(systemName: "line.3.horizontal.decrease.circle")
                        .foregroundStyle(.secondary)
                    Text("当前筛选下没有可安装技能")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }
            } else {
                VStack(spacing: 2) {
                    ForEach(skills) { skill in
                        discoverableSkillRow(skill)
                    }
                }
            }
        }
    }

    private func discoverableSkillRow(_ skill: DiscoverableSkill) -> some View {
        HStack(spacing: 10) {
            ZStack {
                Circle()
                    .fill(Color.blue.opacity(0.12))
                    .frame(width: 32, height: 32)
                Image(systemName: skill.isInstalled ? "checkmark.seal.fill" : "sparkles")
                    .font(.system(size: 14, weight: .medium))
                    .foregroundStyle(skill.isInstalled ? .mint : .blue)
            }

            VStack(alignment: .leading, spacing: 2) {
                Text(skill.name)
                    .font(.subheadline.weight(.medium))
                if let description = skill.description?.trimmedNonEmpty {
                    Text(description)
                        .font(.caption)
                        .foregroundStyle(.secondary)
                        .lineLimit(1)
                }
                Text("\(skill.repoOwner)/\(skill.repoName) · \(skill.directory)")
                    .font(.caption2.monospaced())
                    .foregroundStyle(.tertiary)
                    .lineLimit(1)
                    .truncationMode(.middle)
                if skill.isInstalled {
                    Text(L10n.tr("tools.skill.mount_format", skill.apps.displayText))
                        .font(.caption2.weight(.medium))
                        .foregroundStyle(.secondary)
                } else {
                    HStack(spacing: 6) {
                        ForEach(ProviderAppType.allCases) { app in
                            appMountChip(
                                app: app,
                                isOn: skill.apps.isEnabled(for: app),
                                onChange: { enabled in
                                    model.toggleDiscoverableSkillApp(skillId: skill.id, app: app, enabled: enabled)
                                }
                            )
                        }
                    }
                }
            }

            Spacer(minLength: 0)

            HStack(spacing: 4) {
                Button {
                    Task { await model.previewDiscoverableSkill(skill) }
                } label: {
                    if model.previewingDiscoverableSkillKey == skill.key {
                        ProgressView()
                            .controlSize(.small)
                    } else {
                        Image(systemName: "doc.text.magnifyingglass")
                    }
                }
                .liquidGlassActionButtonStyle(density: .compact)
                .help(L10n.tr("tools.skill.preview_help"))
                .disabled(model.previewingDiscoverableSkillKey == skill.key)

                if let urlString = skill.readmeUrl, let url = URL(string: urlString) {
                    Button {
                        NSWorkspace.shared.open(url)
                    } label: {
                        Image(systemName: "arrow.up.right.square")
                    }
                    .liquidGlassActionButtonStyle(density: .compact)
                    .help(L10n.tr("tools.skill.open_repository_help"))
                }

                if skill.isInstalled {
                    Text(L10n.tr("tools.skill.installed"))
                        .font(.caption2.weight(.medium))
                        .foregroundStyle(.mint)
                        .padding(.horizontal, 8)
                        .padding(.vertical, 4)
                        .background(Color.mint.opacity(0.12), in: Capsule())
                } else {
                    Button(L10n.tr("common.install")) {
                        Task { await model.installSkill(skill) }
                    }
                    .aimenuActionButtonStyle(prominent: true, tint: .blue, density: .compact)
                }
            }
            .opacity(hoveredDiscoverableSkill == skill.id ? 1 : 0.92)
        }
        .padding(.horizontal, 8)
        .padding(.vertical, 6)
        .contentShape(Rectangle())
        .onTapGesture {
            Task { await model.previewDiscoverableSkill(skill) }
        }
        .background {
            RoundedRectangle(cornerRadius: 8)
                .fill(hoveredDiscoverableSkill == skill.id ? Color.primary.opacity(0.05) : Color.clear)
        }
        .onHover { hoveredDiscoverableSkill = $0 ? skill.id : nil }
    }

    private func skillRow(_ skill: InstalledSkill) -> some View {
        HStack(spacing: 10) {
            ZStack {
                Circle()
                    .fill(Color.orange.opacity(0.12))
                    .frame(width: 32, height: 32)
                Image(systemName: "wand.and.stars")
                    .font(.system(size: 14, weight: .medium))
                    .foregroundStyle(.orange)
            }

            VStack(alignment: .leading, spacing: 2) {
                Text(skill.name)
                    .font(.subheadline.weight(.medium))
                if let desc = skill.description, !desc.isEmpty {
                    Text(desc)
                        .font(.caption)
                        .foregroundStyle(.secondary)
                        .lineLimit(1)
                }
                Text(tildePath(installedSkillPath(for: skill)))
                    .font(.caption2.monospaced())
                    .foregroundStyle(.tertiary)
                    .lineLimit(1)
                    .truncationMode(.middle)
                HStack(spacing: 6) {
                    ForEach(ProviderAppType.allCases) { app in
                        appMountChip(
                            app: app,
                            isOn: skill.apps.isEnabled(for: app),
                            onChange: { enabled in
                                Task { await model.toggleInstalledSkillApp(directory: skill.directory, app: app, enabled: enabled) }
                            }
                        )
                    }
                }
            }

            Spacer(minLength: 0)

            if let repoLabel = skillRepoLabel(skill) {
                Text(repoLabel)
                    .font(.caption2)
                    .foregroundStyle(.tertiary)
                    .lineLimit(1)
                    .truncationMode(.middle)
            }

            HStack(spacing: 4) {
                Button {
                    Task { await model.openInstalledSkill(directory: skill.directory) }
                } label: {
                    Image(systemName: "pencil")
                }
                .liquidGlassActionButtonStyle(density: .compact)

                Button {
                    let path = installedSkillPath(for: skill)
                    NSWorkspace.shared.selectFile(path, inFileViewerRootedAtPath: "")
                } label: {
                    Image(systemName: "folder")
                }
                .liquidGlassActionButtonStyle(density: .compact)

                Button(role: .destructive) {
                    Task { await model.uninstallSkill(directory: skill.directory) }
                } label: {
                    Image(systemName: "trash")
                        .foregroundStyle(.red.opacity(0.8))
                }
                .liquidGlassActionButtonStyle(density: .compact)
                .opacity(hoveredSkill == skill.id ? 1 : 0.28)
            }
            .animation(.easeInOut(duration: 0.15), value: hoveredSkill)
        }
        .padding(.horizontal, 8)
        .padding(.vertical, 6)
        .contentShape(Rectangle())
        .onTapGesture {
            Task { await model.openInstalledSkill(directory: skill.directory) }
        }
        .background {
            RoundedRectangle(cornerRadius: 8)
                .fill(hoveredSkill == skill.id ? Color.primary.opacity(0.05) : Color.clear)
        }
        .onHover { hoveredSkill = $0 ? skill.id : nil }
    }

    private func skillRepoLabel(_ skill: InstalledSkill) -> String? {
        let owner = skill.repoOwner.trimmingCharacters(in: .whitespacesAndNewlines)
        let repo = skill.repoName.trimmingCharacters(in: .whitespacesAndNewlines)
        if !owner.isEmpty, !repo.isEmpty {
            return "\(owner)/\(repo)"
        }
        return L10n.tr("tools.skill.local")
    }

    private func compactAppName(for app: ProviderAppType) -> String {
        switch app {
        case .claude:
            return "Claude"
        case .codex:
            return "Codex"
        case .gemini:
            return "Gemini"
        }
    }

    private func appMountChip(
        app: ProviderAppType,
        label: String? = nil,
        isOn: Bool,
        disabled: Bool = false,
        onChange: @escaping (Bool) -> Void
    ) -> some View {
        let tint = localConfigAccent(for: app)
        let title = label ?? compactAppName(for: app)

        return Button {
            onChange(!isOn)
        } label: {
            HStack(spacing: 5) {
                Circle()
                    .fill(isOn ? tint : Color.secondary.opacity(0.28))
                    .frame(width: 6, height: 6)
                Text(title)
                    .font(.caption.weight(.medium))
                    .foregroundStyle(isOn ? .primary : .secondary)
            }
            .padding(.horizontal, 10)
            .padding(.vertical, 5)
            .background(
                RoundedRectangle(cornerRadius: 6, style: .continuous)
                    .fill(isOn ? tint.opacity(0.12) : Color.primary.opacity(0.05))
                    .overlay(
                        RoundedRectangle(cornerRadius: 6, style: .continuous)
                            .strokeBorder(isOn ? tint.opacity(0.22) : Color.clear, lineWidth: 1)
                    )
            )
        }
        .buttonStyle(.plain)
        .disabled(disabled)
        .opacity(disabled ? 0.42 : 1)
    }

    private func localConfigAccent(for app: ProviderAppType) -> Color {
        switch app {
        case .claude:
            return .green
        case .codex:
            return .blue
        case .gemini:
            return .orange
        }
    }

    private func localConfigKindTint(_ kind: LocalConfigKind) -> Color {
        switch kind {
        case .json:
            return .blue
        case .toml:
            return .purple
        case .env:
            return .orange
        case .markdown:
            return .secondary
        }
    }

    private func tildePath(_ path: String) -> String {
        let home = NSHomeDirectory()
        guard path.hasPrefix(home) else { return path }
        return "~" + path.dropFirst(home.count)
    }

    private func installedSkillPath(for skill: InstalledSkill) -> String {
        NSHomeDirectory() + "/Library/Application Support/\(FileSystemPaths.appSupportDirectoryName)/skills/\(skill.directory)"
    }

    private func openDirectory(_ path: String) {
        guard FileManager.default.fileExists(atPath: path) else { return }
        NSWorkspace.shared.open(URL(fileURLWithPath: path, isDirectory: true))
    }

    private func localConfigMetaText(_ file: LocalConfigFile) -> String? {
        guard file.exists else { return nil }

        var parts: [String] = []
        if let byteCount = file.byteCount {
            parts.append(ByteCountFormatter.string(fromByteCount: byteCount, countStyle: .file))
        }
        if let modifiedAt = file.modifiedAt {
            parts.append(relativeDateString(modifiedAt))
        }

        return parts.isEmpty ? nil : parts.joined(separator: " · ")
    }

    private func localConfigLatestText(_ timestamp: Int64?) -> String? {
        guard let timestamp else { return nil }
        return "最近更新 \(relativeDateString(timestamp))"
    }

    private func relativeDateString(_ timestamp: Int64) -> String {
        let formatter = RelativeDateTimeFormatter()
        formatter.unitsStyle = .short
        return formatter.localizedString(
            for: Date(timeIntervalSince1970: TimeInterval(timestamp)),
            relativeTo: Date()
        )
    }

    private func serviceMetric(title: String, value: String, tint: Color) -> some View {
        VStack(alignment: .leading, spacing: 2) {
            Text(title)
                .font(.caption2.weight(.semibold))
                .foregroundStyle(.secondary)
            Text(value)
                .font(.caption.weight(.medium))
                .foregroundStyle(tint == .secondary ? .primary : tint)
                .lineLimit(1)
                .truncationMode(.middle)
        }
        .padding(.horizontal, 10)
        .padding(.vertical, 8)
        .background(
            RoundedRectangle(cornerRadius: 10, style: .continuous)
                .fill((tint == .secondary ? Color.primary : tint).opacity(0.06))
        )
    }

    private func maskedSecret(_ value: String) -> String {
        let trimmed = value.trimmingCharacters(in: .whitespacesAndNewlines)
        guard trimmed.count > 8 else { return trimmed }
        return "\(trimmed.prefix(4))•••\(trimmed.suffix(4))"
    }

    private func portTitle(for port: Int) -> String {
        switch port {
        case 8002:
            return "Cursor2API 默认端口"
        case 8787:
            return "AIMenu 集中代理端口"
        case 3000:
            return "3000 Web 开发端口"
        case 5173:
            return "5173 Vite 默认端口"
        case 5432:
            return "5432 PostgreSQL 端口"
        case 6379:
            return "6379 Redis 端口"
        case 8080:
            return "8080 通用服务端口"
        default:
            return "端口 \(port)"
        }
    }
}
