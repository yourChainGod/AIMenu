import SwiftUI
import AppKit

struct ToolsPageView: View {
    enum PageMode {
        case tools
        case workbench
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

    @State private var servicesExpanded = true
    @State private var configsExpanded = true
    @State private var mcpExpanded = true
    @State private var promptsExpanded = true
    @State private var hooksExpanded = true
    @State private var skillsExpanded = true
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
        ScrollView {
            VStack(spacing: LayoutRules.sectionSpacing) {
                contentSections
            }
            .padding(LayoutRules.pagePadding)
        }
        .scrollIndicators(.hidden)
        .task { await model.load() }
        .sheet(isPresented: $showMCPForm) {
            MCPServerEditorSheet(
                server: editingMCPServer,
                onSave: { server in
                    Task { await model.saveMCPServer(server) }
                    showMCPForm = false
                    editingMCPServer = nil
                },
                onCancel: {
                    showMCPForm = false
                    editingMCPServer = nil
                }
            )
            .frame(width: 700, height: 680)
        }
        .sheet(isPresented: $showPromptEditor) {
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
                    showPromptEditor = false
                    editingPrompt = nil
                },
                onCancel: {
                    showPromptEditor = false
                    editingPrompt = nil
                }
            )
            .frame(width: 640, height: 500)
        }
        .sheet(isPresented: $showSkillRepoEditor) {
            SkillRepoEditorSheet(
                onSave: { owner, name, branch in
                    Task { await model.addSkillRepo(owner: owner, name: name, branch: branch) }
                    showSkillRepoEditor = false
                },
                onCancel: {
                    showSkillRepoEditor = false
                }
            )
            .frame(width: 520, height: 320)
        }
        .sheet(
            isPresented: Binding(
                get: { model.previewingDiscoverableSkillDocument != nil },
                set: { newValue in
                    if !newValue {
                        model.previewingDiscoverableSkillDocument = nil
                    }
                }
            )
        ) {
            if let document = model.previewingDiscoverableSkillDocument {
                DiscoverableSkillPreviewSheet(
                    document: document,
                    previewLoading: model.previewingDiscoverableSkillKey == document.skill.key,
                    onInstall: {
                        Task { await model.installSkill(document.skill) }
                    },
                    onDismiss: {
                        model.previewingDiscoverableSkillDocument = nil
                    }
                )
                .frame(width: 780, height: 640)
            }
        }
        .sheet(
            isPresented: Binding(
                get: { model.editingInstalledSkillDocument != nil },
                set: { newValue in
                    if !newValue {
                        model.editingInstalledSkillDocument = nil
                    }
                }
            )
        ) {
            if let document = model.editingInstalledSkillDocument {
                InstalledSkillEditorSheet(
                    document: document,
                    onSave: { content in
                        Task { await model.saveInstalledSkill(directory: document.skill.directory, content: content) }
                    },
                    onCancel: {
                        model.editingInstalledSkillDocument = nil
                    }
                )
                .frame(width: 760, height: 620)
            }
        }
    }

    @ViewBuilder
    private var contentSections: some View {
        switch mode {
        case .tools:
            servicesSection
            configsSection
        case .workbench:
            mcpSection
            promptsSection
            hooksSection
            skillsSection
        }
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
        SectionCard(
            title: "本地服务",
            icon: "switch.2",
            iconColor: .teal,
            headerTrailing: {
                HStack(spacing: 6) {
                    Button {
                        Task { await model.refreshManagedToolStatus() }
                    } label: {
                        Image(systemName: "arrow.clockwise")
                    }
                    .liquidGlassActionButtonStyle(density: .compact)
                    .help("刷新本地服务状态")

                    CollapseChevronButton(isExpanded: servicesExpanded) {
                        withAnimation(.easeInOut(duration: 0.2)) { servicesExpanded.toggle() }
                    }
                }
            }
        ) {
            if servicesExpanded {
                VStack(spacing: 12) {
                    cursor2APIServiceCard
                    portToolsCard
                }
            }
        }
    }

    private var cursor2APIServiceCard: some View {
        VStack(alignment: .leading, spacing: 10) {
            HStack(alignment: .top, spacing: 10) {
                ZStack {
                    RoundedRectangle(cornerRadius: 12, style: .continuous)
                        .fill(Color.blue.opacity(0.12))
                        .frame(width: 38, height: 38)
                    Image(systemName: "bolt.horizontal.circle.fill")
                        .font(.system(size: 18))
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
                }

                Spacer(minLength: 0)

                VStack(alignment: .trailing, spacing: 6) {
                    if let path = model.cursor2APIStatus.binaryPath {
                        Text(path)
                            .font(.caption2.monospaced())
                            .foregroundStyle(.tertiary)
                            .lineLimit(1)
                            .truncationMode(.middle)
                    }
                    Text(model.cursor2APIStatus.baseURL)
                        .font(.caption.weight(.medium))
                        .foregroundStyle(.secondary)
                }
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

                Spacer(minLength: 0)

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
            }
        }
        .padding(14)
        .cardSurface(cornerRadius: 14, tint: Color.blue.opacity(0.05))
    }

    private var portToolsCard: some View {
        VStack(alignment: .leading, spacing: 10) {
            HStack {
                VStack(alignment: .leading, spacing: 3) {
                    Text("端口工具")
                        .font(.headline)
                    Text("常用端口占用、一键释放、临时关注。")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }
                Spacer(minLength: 0)
            }

            HStack(spacing: 8) {
                TextField("添加端口", text: $model.customPortText)
                    .textFieldStyle(.plain)
                    .font(.caption.monospaced())
                    .padding(.horizontal, 10)
                    .padding(.vertical, 8)
                    .background(
                        RoundedRectangle(cornerRadius: 10, style: .continuous)
                            .fill(Color.primary.opacity(0.05))
                    )
                    .frame(width: 110)

                Button("关注") {
                    Task { await model.addTrackedPort() }
                }
                .aimenuActionButtonStyle(density: .compact)

                Spacer(minLength: 0)
            }

            VStack(spacing: 6) {
                ForEach(model.trackedPorts) { status in
                    portStatusRow(status)
                }
            }
        }
        .padding(14)
        .cardSurface(cornerRadius: 14, tint: Color.orange.opacity(0.05))
    }

    private func portStatusRow(_ status: ManagedPortStatus) -> some View {
        HStack(spacing: 10) {
            Circle()
                .fill(status.occupied ? Color.orange : Color.mint)
                .frame(width: 8, height: 8)

            VStack(alignment: .leading, spacing: 2) {
                Text(portTitle(for: status.port))
                    .font(.subheadline.weight(.medium))
                Text(status.occupied
                     ? "\(status.command ?? "未知进程") · PID \(status.processID.map(String.init) ?? "—")"
                     : "当前空闲")
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }

            Spacer(minLength: 0)

            if status.occupied {
                Button("释放端口") {
                    Task { await model.killPort(status.port) }
                }
                .aimenuActionButtonStyle(prominent: true, tint: .orange, density: .compact)

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
            } else {
                Text("空闲")
                    .font(.caption.weight(.medium))
                    .foregroundStyle(.mint)
                    .padding(.horizontal, 8)
                    .padding(.vertical, 4)
                    .background(Color.mint.opacity(0.12), in: Capsule())

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
        .padding(.vertical, 8)
        .background(Color.primary.opacity(0.04), in: RoundedRectangle(cornerRadius: 10, style: .continuous))
    }

    // MARK: - Local Config Overview

    private var configsSection: some View {
        SectionCard(
            title: "本地配置",
            icon: "folder.badge.gearshape",
            iconColor: .green,
            headerTrailing: {
                HStack(spacing: 6) {
                    Button {
                        Task { await model.refreshLocalConfigBundles() }
                    } label: {
                        Image(systemName: "arrow.clockwise")
                    }
                    .liquidGlassActionButtonStyle(density: .compact)
                    .help("刷新本地配置状态")

                    CollapseChevronButton(isExpanded: configsExpanded) {
                        withAnimation(.easeInOut(duration: 0.2)) { configsExpanded.toggle() }
                    }
                }
            }
        ) {
            if configsExpanded {
                localConfigContent
            } else {
                localConfigCollapsedSummary
            }
        }
    }

    @ViewBuilder
    private var localConfigContent: some View {
        if model.localConfigBundles.isEmpty {
            VStack(spacing: 8) {
                Image(systemName: "folder.badge.gearshape")
                    .font(.system(size: 28))
                    .foregroundStyle(.secondary.opacity(0.4))
                Text("暂无本地配置概览")
                    .font(.subheadline)
                    .foregroundStyle(.secondary)
            }
            .frame(maxWidth: .infinity, minHeight: 80, alignment: .center)
        } else {
            LazyVGrid(columns: [GridItem(.adaptive(minimum: 220), spacing: 10)], spacing: 10) {
                ForEach(model.localConfigBundles) { bundle in
                    localConfigBundleCard(bundle)
                }
            }
        }
    }

    private var localConfigCollapsedSummary: some View {
        let total = model.localConfigBundles.reduce(0) { $0 + $1.files.count }
        let existing = model.localConfigBundles.reduce(0) { $0 + $1.existingFileCount }
        return Group {
            if total == 0 {
                Text("暂无配置")
                    .font(.subheadline)
                    .foregroundStyle(.secondary)
            } else {
                HStack(spacing: 6) {
                    Circle()
                        .fill(existing == total ? Color.mint : Color.orange)
                        .frame(width: 6, height: 6)
                    Text("\(existing) / \(total) 可见")
                        .font(.subheadline)
                        .foregroundStyle(.secondary)
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
        .background(Color.primary.opacity(0.04), in: RoundedRectangle(cornerRadius: 10, style: .continuous))
    }

    // MARK: - MCP Servers

    private var mcpSection: some View {
        SectionCard(
            title: "MCP 服务器",
            icon: "server.rack",
            iconColor: .blue,
            headerTrailing: {
                HStack(spacing: 6) {
                    Button {
                        withAnimation(.spring(duration: 0.25)) { showMCPPresets.toggle() }
                    } label: {
                        Image(systemName: showMCPPresets ? "square.grid.2x2.fill" : "square.grid.2x2")
                    }
                    .liquidGlassActionButtonStyle(density: .compact)
                    .help(showMCPPresets ? "预设已展开" : "显示 MCP 预设")

                    Button {
                        Task { await model.importLiveMCPServers() }
                    } label: {
                        Image(systemName: "square.and.arrow.down")
                    }
                    .liquidGlassActionButtonStyle(density: .compact)
                    .help("从 Claude / Codex / Gemini 导入 MCP")

                    Button {
                        editingMCPServer = nil
                        showMCPForm = true
                    } label: {
                        Image(systemName: "plus")
                    }
                    .liquidGlassActionButtonStyle(density: .compact)
                    .help("添加自定义 MCP 服务器")

                    CollapseChevronButton(isExpanded: mcpExpanded) {
                        withAnimation(.easeInOut(duration: 0.2)) { mcpExpanded.toggle() }
                    }
                }
            }
        ) {
            if mcpExpanded {
                VStack(alignment: .leading, spacing: 8) {
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
                }
            } else {
                mcpCollapsedSummary
            }
        }
    }

    private var mcpEmptyState: some View {
        VStack(spacing: 8) {
            Image(systemName: "server.rack")
                .font(.system(size: 28))
                .foregroundStyle(.secondary.opacity(0.4))
            Text("暂未配置 MCP 服务器")
                .font(.subheadline)
                .foregroundStyle(.secondary)
            HStack(spacing: 8) {
                Button("从预设添加") {
                    withAnimation(.spring(duration: 0.25)) { showMCPPresets = true }
                }
                .liquidGlassActionButtonStyle(density: .compact)

                Button("导入本地") {
                    Task { await model.importLiveMCPServers() }
                }
                .liquidGlassActionButtonStyle(density: .compact)

                Button("新建自定义") {
                    editingMCPServer = nil
                    showMCPForm = true
                }
                .aimenuActionButtonStyle(prominent: true, tint: .blue, density: .compact)
            }
        }
        .frame(maxWidth: .infinity, minHeight: 80, alignment: .center)
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
                            mcpAppToggle(serverId: server.id, label: "Claude Code", isOn: server.apps.claude, onChange: { v in
                                Task { await model.toggleMCPApp(serverId: server.id, app: .claude, enabled: v) }
                            })
                            mcpAppToggle(serverId: server.id, label: "Codex", isOn: server.apps.codex, onChange: { v in
                                Task { await model.toggleMCPApp(serverId: server.id, app: .codex, enabled: v) }
                            })
                            mcpAppToggle(serverId: server.id, label: "Gemini", isOn: server.apps.gemini, onChange: { v in
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

    private func mcpAppToggle(serverId: String, label: String, isOn: Bool, onChange: @escaping (Bool) -> Void) -> some View {
        Button {
            onChange(!isOn)
        } label: {
            HStack(spacing: 5) {
                Circle()
                    .fill(isOn ? Color.mint : Color.secondary.opacity(0.3))
                    .frame(width: 6, height: 6)
                Text(label)
                    .font(.caption.weight(.medium))
                    .foregroundStyle(isOn ? .primary : .secondary)
            }
            .padding(.horizontal, 10)
            .padding(.vertical, 5)
            .background {
                RoundedRectangle(cornerRadius: 6)
                    .fill(isOn ? Color.mint.opacity(0.12) : Color.primary.opacity(0.05))
                    .overlay {
                        RoundedRectangle(cornerRadius: 6)
                            .strokeBorder(isOn ? Color.mint.opacity(0.3) : Color.clear, lineWidth: 1)
                    }
            }
        }
        .buttonStyle(.plain)
    }

    // MARK: - Prompts

    private var promptsSection: some View {
        SectionCard(
            title: "提示词",
            icon: "text.bubble",
            iconColor: .purple,
            headerTrailing: {
                HStack(spacing: 6) {
                    if promptsExpanded {
                        Picker("", selection: Binding(
                            get: { model.selectedPromptApp },
                            set: { app in Task { await model.switchPromptApp(app) } }
                        )) {
                            ForEach(PromptAppType.allCases) { app in
                                Text(app.displayName).tag(app)
                            }
                        }
                        .pickerStyle(.segmented)
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
        ) {
            if promptsExpanded {
                promptsContent
            }
        }
    }

    @ViewBuilder
    private var promptsContent: some View {
        promptLiveFileBar

        if model.prompts.isEmpty {
            VStack(spacing: 8) {
                Image(systemName: "text.bubble")
                    .font(.system(size: 28))
                    .foregroundStyle(.secondary.opacity(0.4))
                Text("暂无提示词")
                    .font(.subheadline)
                    .foregroundStyle(.secondary)
                Text("点击 + 新建，或点击 ↓ 从文件导入")
                    .font(.caption)
                    .foregroundStyle(.tertiary)
            }
            .frame(maxWidth: .infinity, minHeight: 80, alignment: .center)
        } else {
            VStack(spacing: 2) {
                ForEach(model.prompts) { prompt in
                    promptRow(prompt)
                }
            }
        }
    }

    private var promptLiveFileBar: some View {
        HStack(spacing: 8) {
            Label(model.selectedPromptApp.fileName, systemImage: "doc.text")
                .font(.caption.weight(.medium))
            Text(model.selectedPromptApp.filePath.path)
                .font(.caption2.monospaced())
                .foregroundStyle(.tertiary)
                .lineLimit(1)
                .truncationMode(.middle)
            Spacer(minLength: 0)
        }
        .padding(.horizontal, 10)
        .padding(.vertical, 8)
        .background(Color.primary.opacity(0.04), in: RoundedRectangle(cornerRadius: 10, style: .continuous))
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
                    Text("已写入")
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
                .help(prompt.isActive ? "已写入" : "写入 \(model.selectedPromptApp.fileName)")

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
                .accessibilityLabel("删除提示词 \(prompt.name)")
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
                HStack(spacing: 6) {
                    Button {
                        Task { await model.refreshClaudeHooks() }
                    } label: {
                        Image(systemName: "arrow.clockwise")
                    }
                    .liquidGlassActionButtonStyle(density: .compact)
                    .help("刷新 Claude Hooks")

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
        ) {
            if hooksExpanded {
                hooksContent
            }
        }
    }

    @ViewBuilder
    private var hooksContent: some View {
        let hookGroups = groupedClaudeHooks

        HStack(spacing: 8) {
            Label("~/.claude/settings.json", systemImage: "doc.text")
                .font(.caption.weight(.medium))
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
        .padding(.horizontal, 10)
        .padding(.vertical, 8)
        .background(Color.primary.opacity(0.04), in: RoundedRectangle(cornerRadius: 10, style: .continuous))

        if model.claudeHooks.isEmpty {
            VStack(spacing: 8) {
                Image(systemName: "point.3.connected.trianglepath.dotted")
                    .font(.system(size: 28))
                    .foregroundStyle(.secondary.opacity(0.4))
                Text("未扫描到 Claude Hooks")
                    .font(.subheadline)
                    .foregroundStyle(.secondary)
            }
            .frame(maxWidth: .infinity, minHeight: 80, alignment: .center)
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
                ForEach(hooks) { hook in
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
        ) {
            if skillsExpanded {
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
                VStack(spacing: 8) {
                    Image(systemName: "magnifyingglass")
                        .font(.system(size: 24))
                        .foregroundStyle(.secondary.opacity(0.45))
                    Text("没有匹配的技能")
                        .font(.subheadline)
                        .foregroundStyle(.secondary)
                }
                .frame(maxWidth: .infinity, minHeight: 80, alignment: .center)
            } else if selectedSkillsFilter == .installed && model.skills.installedSkills.isEmpty {
                VStack(spacing: 8) {
                    Image(systemName: "wand.and.stars")
                        .font(.system(size: 28))
                        .foregroundStyle(.secondary.opacity(0.4))
                    Text("暂未安装技能")
                        .font(.subheadline)
                        .foregroundStyle(.secondary)
                }
                .frame(maxWidth: .infinity, minHeight: 80, alignment: .center)
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
                HStack(spacing: 8) {
                    ProgressView()
                        .controlSize(.small)
                    Text("正在读取技能仓库…")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }
                .padding(.horizontal, 10)
                .padding(.vertical, 8)
                .background(Color.primary.opacity(0.04), in: RoundedRectangle(cornerRadius: 10, style: .continuous))
            } else if skills.isEmpty {
                HStack(spacing: 8) {
                    Image(systemName: "line.3.horizontal.decrease.circle")
                        .foregroundStyle(.secondary)
                    Text("当前筛选下没有可安装技能")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }
                .padding(.horizontal, 10)
                .padding(.vertical, 8)
                .background(Color.primary.opacity(0.04), in: RoundedRectangle(cornerRadius: 10, style: .continuous))
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
                .help("预览 SKILL.md")
                .disabled(model.previewingDiscoverableSkillKey == skill.key)

                if let urlString = skill.readmeUrl, let url = URL(string: urlString) {
                    Button {
                        NSWorkspace.shared.open(url)
                    } label: {
                        Image(systemName: "arrow.up.right.square")
                    }
                    .liquidGlassActionButtonStyle(density: .compact)
                    .help("打开仓库")
                }

                if skill.isInstalled {
                    Text("已安装")
                        .font(.caption2.weight(.medium))
                        .foregroundStyle(.mint)
                        .padding(.horizontal, 8)
                        .padding(.vertical, 4)
                        .background(Color.mint.opacity(0.12), in: Capsule())
                } else {
                    Button("安装") {
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

    private func isDefaultTrackedPort(_ port: Int) -> Bool {
        [8002, 8787].contains(port)
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
                Text("~/.claude/skills/\(skill.directory)")
                    .font(.caption2.monospaced())
                    .foregroundStyle(.tertiary)
                    .lineLimit(1)
                    .truncationMode(.middle)
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
                    let path = NSHomeDirectory() + "/.claude/skills/\(skill.directory)"
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
        return "本地技能"
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
                .fill((tint == .secondary ? Color.primary : tint).opacity(0.08))
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
        default:
            return "端口 \(port)"
        }
    }
}

private struct ToolsStatusBadge: View {
    let text: String
    let tint: Color

    var body: some View {
        Text(text)
            .font(.system(size: 10, weight: .semibold))
            .foregroundStyle(tint == Color.secondary ? AnyShapeStyle(.secondary) : AnyShapeStyle(tint))
            .padding(.horizontal, 8)
            .padding(.vertical, 4)
            .background(
                Capsule()
                    .fill((tint == Color.secondary ? Color.primary : tint).opacity(0.1))
            )
    }
}

private struct PromptEditorSheet: View {
    let appType: PromptAppType
    let prompt: Prompt?
    let onSave: (String, String) -> Void
    let onCancel: () -> Void

    @State private var name: String
    @State private var content: String

    init(
        appType: PromptAppType,
        prompt: Prompt?,
        onSave: @escaping (String, String) -> Void,
        onCancel: @escaping () -> Void
    ) {
        self.appType = appType
        self.prompt = prompt
        self.onSave = onSave
        self.onCancel = onCancel
        _name = State(initialValue: prompt?.name ?? "")
        _content = State(initialValue: prompt?.content ?? "")
    }

    var body: some View {
        VStack(spacing: 0) {
            HStack {
                VStack(alignment: .leading, spacing: 4) {
                    Text(prompt == nil ? "新建提示词" : "编辑提示词")
                        .font(.headline)
                    Text("写入 \(appType.fileName)")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }
                Spacer()
                Button("取消") { onCancel() }
                    .keyboardShortcut(.escape)
                Button(prompt == nil ? "添加" : "保存") {
                    onSave(name, content)
                }
                .disabled(name.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty)
                .keyboardShortcut(.return, modifiers: .command)
            }
            .padding(.horizontal, 20)
            .padding(.vertical, 14)

            Divider()

            VStack(alignment: .leading, spacing: 12) {
                VStack(alignment: .leading, spacing: 5) {
                    Text("名称")
                        .font(.caption.weight(.semibold))
                        .foregroundStyle(.secondary)
                    TextField("输入提示词名称", text: $name)
                        .frostedRoundedInput(cornerRadius: 10)
                }

                VStack(alignment: .leading, spacing: 5) {
                    Text("内容")
                        .font(.caption.weight(.semibold))
                        .foregroundStyle(.secondary)
                    TextEditor(text: $content)
                        .font(.body)
                        .padding(8)
                        .frame(minHeight: 320)
                        .background(
                            RoundedRectangle(cornerRadius: 12, style: .continuous)
                                .fill(Color.primary.opacity(0.05))
                                .overlay(
                                    RoundedRectangle(cornerRadius: 12, style: .continuous)
                                        .strokeBorder(Color.primary.opacity(0.08), lineWidth: 1)
                                )
                        )
                }
            }
            .padding(20)
        }
    }
}

private struct MCPServerEditorSheet: View {
    let server: MCPServer?
    let onSave: (MCPServer) -> Void
    let onCancel: () -> Void

    @State private var name: String
    @State private var transport: MCPTransportType
    @State private var command: String
    @State private var argsText: String
    @State private var urlText: String
    @State private var envText: String
    @State private var headersText: String
    @State private var cwd: String
    @State private var description: String
    @State private var homepage: String
    @State private var tags: String
    @State private var enabled = true
    @State private var enableClaude = true
    @State private var enableCodex = true
    @State private var enableGemini = true

    init(
        server: MCPServer?,
        onSave: @escaping (MCPServer) -> Void,
        onCancel: @escaping () -> Void
    ) {
        self.server = server
        self.onSave = onSave
        self.onCancel = onCancel
        _name = State(initialValue: server?.name ?? "")
        _transport = State(initialValue: server?.server.type ?? .stdio)
        _command = State(initialValue: server?.server.command ?? "")
        _argsText = State(initialValue: (server?.server.args ?? []).joined(separator: "\n"))
        _urlText = State(initialValue: server?.server.url ?? "")
        _envText = State(initialValue: Self.dictToMultiline(server?.server.env ?? [:]))
        _headersText = State(initialValue: Self.dictToMultiline(server?.server.headers ?? [:]))
        _cwd = State(initialValue: server?.server.cwd ?? "")
        _description = State(initialValue: server?.description ?? "")
        _homepage = State(initialValue: server?.homepage ?? "")
        _tags = State(initialValue: (server?.tags ?? []).joined(separator: ", "))
        _enabled = State(initialValue: server?.isEnabled ?? true)
        _enableClaude = State(initialValue: server?.apps.claude ?? true)
        _enableCodex = State(initialValue: server?.apps.codex ?? true)
        _enableGemini = State(initialValue: server?.apps.gemini ?? true)
    }

    var body: some View {
        VStack(spacing: 0) {
            HStack {
                VStack(alignment: .leading, spacing: 4) {
                    Text(server == nil ? "新建 MCP 服务器" : "编辑 MCP 服务器")
                        .font(.headline)
                    Text("支持 STDIO / HTTP / SSE 三种接入方式。")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }
                Spacer()
                Button("取消") { onCancel() }
                    .keyboardShortcut(.escape)
                Button(server == nil ? "添加" : "保存") {
                    onSave(buildServer())
                }
                .disabled(name.trimmedNonEmpty == nil)
                .keyboardShortcut(.return, modifiers: .command)
            }
            .padding(.horizontal, 20)
            .padding(.vertical, 14)

            Divider()

            ScrollView {
                VStack(alignment: .leading, spacing: 14) {
                    fieldGroup(title: "基本信息") {
                        HStack(alignment: .top, spacing: 12) {
                            labeledField("名称") {
                                TextField("例如：filesystem", text: $name)
                                    .frostedRoundedInput(cornerRadius: 10)
                            }
                            labeledField("Transport") {
                                Picker("", selection: $transport) {
                                    ForEach(MCPTransportType.allCases, id: \.self) { type in
                                        Text(type.displayName).tag(type)
                                    }
                                }
                                .pickerStyle(.segmented)
                            }
                        }
                        Toggle("启用此服务器", isOn: $enabled)
                            .toggleStyle(.checkbox)
                        HStack(spacing: 8) {
                            toggleChip("Claude", isOn: $enableClaude)
                            toggleChip("Codex", isOn: $enableCodex)
                            toggleChip("Gemini", isOn: $enableGemini)
                        }
                    }

                    fieldGroup(title: transport == .stdio ? "进程配置" : "远程地址") {
                        if transport == .stdio {
                            labeledField("命令") {
                                TextField("例如：npx", text: $command)
                                    .frostedRoundedInput(cornerRadius: 10)
                            }
                            labeledField("参数（每行一个）") {
                                TextEditor(text: $argsText)
                                    .frame(minHeight: 92)
                                    .padding(8)
                                    .background(editorBackground)
                            }
                            labeledField("工作目录") {
                                TextField("可选", text: $cwd)
                                    .frostedRoundedInput(cornerRadius: 10)
                            }
                        } else {
                            labeledField("URL") {
                                TextField("https://example.com/mcp", text: $urlText)
                                    .frostedRoundedInput(cornerRadius: 10)
                            }
                        }
                    }

                    fieldGroup(title: "环境与元数据") {
                        labeledField("环境变量（KEY=VALUE）") {
                            TextEditor(text: $envText)
                                .frame(minHeight: 92)
                                .padding(8)
                                .background(editorBackground)
                        }
                        labeledField("请求头（KEY=VALUE）") {
                            TextEditor(text: $headersText)
                                .frame(minHeight: 92)
                                .padding(8)
                                .background(editorBackground)
                        }
                        labeledField("描述") {
                            TextField("可选描述", text: $description)
                                .frostedRoundedInput(cornerRadius: 10)
                        }
                        HStack(alignment: .top, spacing: 12) {
                            labeledField("主页") {
                                TextField("https://", text: $homepage)
                                    .frostedRoundedInput(cornerRadius: 10)
                            }
                            labeledField("标签（逗号分隔）") {
                                TextField("web, tools", text: $tags)
                                    .frostedRoundedInput(cornerRadius: 10)
                            }
                        }
                    }
                }
                .padding(20)
            }
        }
    }

    private var editorBackground: some View {
        RoundedRectangle(cornerRadius: 12, style: .continuous)
            .fill(Color.primary.opacity(0.05))
            .overlay(
                RoundedRectangle(cornerRadius: 12, style: .continuous)
                    .strokeBorder(Color.primary.opacity(0.08), lineWidth: 1)
            )
    }

    private func fieldGroup<Content: View>(title: String, @ViewBuilder content: () -> Content) -> some View {
        VStack(alignment: .leading, spacing: 10) {
            Text(title)
                .font(.subheadline.weight(.semibold))
            content()
        }
        .padding(14)
        .background(Color.primary.opacity(0.04), in: RoundedRectangle(cornerRadius: 14, style: .continuous))
    }

    private func labeledField<Content: View>(_ title: String, @ViewBuilder content: () -> Content) -> some View {
        VStack(alignment: .leading, spacing: 6) {
            Text(title)
                .font(.caption.weight(.semibold))
                .foregroundStyle(.secondary)
            content()
        }
        .frame(maxWidth: .infinity, alignment: .leading)
    }

    private func toggleChip(_ title: String, isOn: Binding<Bool>) -> some View {
        Button {
            isOn.wrappedValue.toggle()
        } label: {
            HStack(spacing: 6) {
                Circle()
                    .fill(isOn.wrappedValue ? Color.mint : Color.secondary.opacity(0.3))
                    .frame(width: 6, height: 6)
                Text(title)
                    .font(.caption.weight(.medium))
            }
            .padding(.horizontal, 10)
            .padding(.vertical, 6)
            .background(
                Capsule()
                    .fill(isOn.wrappedValue ? Color.mint.opacity(0.12) : Color.primary.opacity(0.05))
            )
        }
        .buttonStyle(.plain)
    }

    private func buildServer() -> MCPServer {
        let now = Int64(Date().timeIntervalSince1970)
        return MCPServer(
            id: server?.id ?? UUID().uuidString,
            name: name.trimmingCharacters(in: .whitespacesAndNewlines),
            server: MCPServerSpec(
                type: transport,
                command: transport == .stdio ? command.trimmedNonEmpty : nil,
                args: transport == .stdio ? lines(from: argsText) : nil,
                env: dictionary(from: envText),
                cwd: transport == .stdio ? cwd.trimmedNonEmpty : nil,
                url: transport == .stdio ? nil : urlText.trimmedNonEmpty,
                headers: dictionary(from: headersText)
            ),
            apps: MCPAppToggles(
                claude: enableClaude,
                codex: enableCodex,
                gemini: enableGemini
            ),
            description: description.trimmedNonEmpty,
            tags: csvItems(from: tags),
            homepage: homepage.trimmedNonEmpty,
            createdAt: server?.createdAt ?? now,
            updatedAt: now,
            isEnabled: enabled
        )
    }

    private func lines(from text: String) -> [String] {
        text.components(separatedBy: .newlines)
            .compactMap { $0.trimmedNonEmpty }
    }

    private func csvItems(from text: String) -> [String]? {
        let values = text.split(separator: ",").map {
            $0.trimmingCharacters(in: .whitespacesAndNewlines)
        }.filter { !$0.isEmpty }
        return values.isEmpty ? nil : values
    }

    private func dictionary(from text: String) -> [String: String]? {
        var result: [String: String] = [:]
        for rawLine in text.components(separatedBy: .newlines) {
            let line = rawLine.trimmingCharacters(in: .whitespacesAndNewlines)
            guard !line.isEmpty, let separator = line.firstIndex(of: "=") else { continue }
            let key = String(line[..<separator]).trimmingCharacters(in: .whitespacesAndNewlines)
            let value = String(line[line.index(after: separator)...]).trimmingCharacters(in: .whitespacesAndNewlines)
            guard !key.isEmpty else { continue }
            result[key] = value
        }
        return result.isEmpty ? nil : result
    }

    private static func dictToMultiline(_ value: [String: String]) -> String {
        value.keys.sorted().map { "\($0)=\(value[$0] ?? "")" }.joined(separator: "\n")
    }
}

private struct DiscoverableSkillPreviewSheet: View {
    let document: DiscoverableSkillPreviewDocument
    let previewLoading: Bool
    let onInstall: () -> Void
    let onDismiss: () -> Void

    var body: some View {
        VStack(spacing: 0) {
            HStack(alignment: .top, spacing: 12) {
                VStack(alignment: .leading, spacing: 6) {
                    HStack(spacing: 8) {
                        Text(document.skill.name)
                            .font(.headline)
                        Text(repoLabel)
                            .font(.caption2.weight(.medium))
                            .foregroundStyle(.secondary)
                            .padding(.horizontal, 8)
                            .padding(.vertical, 4)
                            .background(Color.primary.opacity(0.05), in: Capsule())
                    }

                    if let description = document.skill.description?.trimmedNonEmpty {
                        Text(description)
                            .font(.caption)
                            .foregroundStyle(.secondary)
                    }

                    Text(document.sourcePath)
                        .font(.caption2.monospaced())
                        .foregroundStyle(.secondary)
                        .lineLimit(1)
                        .truncationMode(.middle)
                }

                Spacer(minLength: 0)

                HStack(spacing: 8) {
                    if let sourceURL = sourceURL {
                        Button("仓库") {
                            NSWorkspace.shared.open(sourceURL)
                        }
                        .aimenuActionButtonStyle(density: .compact)
                    }

                    if document.skill.isInstalled {
                        Text("已安装")
                            .font(.caption2.weight(.medium))
                            .foregroundStyle(.mint)
                            .padding(.horizontal, 10)
                            .padding(.vertical, 6)
                            .background(Color.mint.opacity(0.12), in: Capsule())
                    } else {
                        Button("安装") {
                            onInstall()
                        }
                        .aimenuActionButtonStyle(prominent: true, tint: .blue, density: .compact)
                    }

                    Button("关闭") {
                        onDismiss()
                    }
                    .keyboardShortcut(.escape)
                }
            }
            .padding(.horizontal, 20)
            .padding(.vertical, 14)

            Divider()

            VStack(alignment: .leading, spacing: 12) {
                HStack(spacing: 8) {
                    Text(verbatim: "SKILL.md")
                        .font(.caption.weight(.semibold))
                        .foregroundStyle(.secondary)
                    Spacer(minLength: 0)
                    if previewLoading {
                        ProgressView()
                            .controlSize(.small)
                    }
                }

                ScrollView {
                    Text(verbatim: document.content)
                        .font(.system(.body, design: .monospaced))
                        .foregroundStyle(.primary)
                        .frame(maxWidth: .infinity, alignment: .topLeading)
                        .textSelection(.enabled)
                        .padding(14)
                }
                .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
                .background(
                    RoundedRectangle(cornerRadius: 14, style: .continuous)
                        .fill(Color.primary.opacity(0.05))
                        .overlay(
                            RoundedRectangle(cornerRadius: 14, style: .continuous)
                                .strokeBorder(Color.primary.opacity(0.08), lineWidth: 1)
                        )
                )
            }
            .padding(20)
        }
    }

    private var repoLabel: String {
        "\(document.skill.repoOwner)/\(document.skill.repoName)"
    }

    private var sourceURL: URL? {
        guard let urlString = document.skill.readmeUrl else { return nil }
        return URL(string: urlString)
    }
}

private struct InstalledSkillEditorSheet: View {
    let document: InstalledSkillDocument
    let onSave: (String) -> Void
    let onCancel: () -> Void

    @State private var content: String

    init(
        document: InstalledSkillDocument,
        onSave: @escaping (String) -> Void,
        onCancel: @escaping () -> Void
    ) {
        self.document = document
        self.onSave = onSave
        self.onCancel = onCancel
        _content = State(initialValue: document.content)
    }

    var body: some View {
        VStack(spacing: 0) {
            HStack(alignment: .top) {
                VStack(alignment: .leading, spacing: 4) {
                    HStack(spacing: 8) {
                        Text(document.skill.name)
                            .font(.headline)
                        Text(repoLabel)
                            .font(.caption2.weight(.medium))
                            .foregroundStyle(.secondary)
                            .padding(.horizontal, 8)
                            .padding(.vertical, 4)
                            .background(Color.primary.opacity(0.05), in: Capsule())
                    }
                    Text(document.path)
                        .font(.caption2.monospaced())
                        .foregroundStyle(.secondary)
                        .lineLimit(1)
                        .truncationMode(.middle)
                }
                Spacer(minLength: 0)
                Button("取消") { onCancel() }
                    .keyboardShortcut(.escape)
                Button("保存") {
                    onSave(content)
                }
                .keyboardShortcut(.return, modifiers: .command)
            }
            .padding(.horizontal, 20)
            .padding(.vertical, 14)

            Divider()

            VStack(alignment: .leading, spacing: 12) {
                HStack(spacing: 8) {
                    Text(verbatim: "SKILL.md")
                        .font(.caption.weight(.semibold))
                        .foregroundStyle(.secondary)
                    Spacer(minLength: 0)
                    Button("在 Finder 中打开") {
                        NSWorkspace.shared.selectFile(document.path, inFileViewerRootedAtPath: "")
                    }
                    .aimenuActionButtonStyle(density: .compact)
                }

                TextEditor(text: $content)
                    .font(.system(.body, design: .monospaced))
                    .padding(10)
                    .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
                    .background(
                        RoundedRectangle(cornerRadius: 14, style: .continuous)
                            .fill(Color.primary.opacity(0.05))
                            .overlay(
                                RoundedRectangle(cornerRadius: 14, style: .continuous)
                                    .strokeBorder(Color.primary.opacity(0.08), lineWidth: 1)
                            )
                    )
            }
            .padding(20)
        }
    }

    private var repoLabel: String {
        let owner = document.skill.repoOwner.trimmingCharacters(in: .whitespacesAndNewlines)
        let repo = document.skill.repoName.trimmingCharacters(in: .whitespacesAndNewlines)
        if !owner.isEmpty, !repo.isEmpty {
            return "\(owner)/\(repo)"
        }
        return "本地技能"
    }
}

private struct SkillRepoEditorSheet: View {
    let onSave: (String, String, String) -> Void
    let onCancel: () -> Void

    @State private var owner = ""
    @State private var name = ""
    @State private var branch = "main"

    var body: some View {
        VStack(spacing: 0) {
            HStack {
                VStack(alignment: .leading, spacing: 4) {
                    Text("添加技能仓库")
                        .font(.headline)
                    Text("使用 GitHub 仓库中的 `SKILL.md` 目录作为发现来源。")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }
                Spacer()
                Button("取消") { onCancel() }
                    .keyboardShortcut(.escape)
                Button("保存") {
                    onSave(owner, name, branch)
                }
                .disabled(owner.trimmedNonEmpty == nil || name.trimmedNonEmpty == nil || branch.trimmedNonEmpty == nil)
                .keyboardShortcut(.return, modifiers: .command)
            }
            .padding(.horizontal, 20)
            .padding(.vertical, 14)

            Divider()

            VStack(alignment: .leading, spacing: 14) {
                VStack(alignment: .leading, spacing: 6) {
                    Text("Owner")
                        .font(.caption.weight(.semibold))
                        .foregroundStyle(.secondary)
                    TextField("例如：anthropics", text: $owner)
                        .frostedRoundedInput(cornerRadius: 10)
                }

                VStack(alignment: .leading, spacing: 6) {
                    Text("仓库名")
                        .font(.caption.weight(.semibold))
                        .foregroundStyle(.secondary)
                    TextField("例如：skills", text: $name)
                        .frostedRoundedInput(cornerRadius: 10)
                }

                VStack(alignment: .leading, spacing: 6) {
                    Text("分支")
                        .font(.caption.weight(.semibold))
                        .foregroundStyle(.secondary)
                    TextField("main", text: $branch)
                        .frostedRoundedInput(cornerRadius: 10)
                }

                Spacer(minLength: 0)
            }
            .padding(20)
        }
    }
}
