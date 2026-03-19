import SwiftUI
import AppKit

struct ToolsPageView: View {
    @ObservedObject var model: ToolsPageModel

    @State private var mcpExpanded = true
    @State private var promptsExpanded = true
    @State private var skillsExpanded = true
    @State private var showMCPPresets = false
    @State private var showAddPrompt = false
    @State private var newPromptName = ""
    @State private var newPromptContent = ""
    @State private var hoveredMCPServer: String? = nil
    @State private var hoveredPrompt: String? = nil

    var body: some View {
        ScrollView {
            VStack(spacing: LayoutRules.sectionSpacing) {
                mcpSection
                promptsSection
                skillsSection
            }
            .padding(LayoutRules.pagePadding)
        }
        .scrollIndicators(.hidden)
        .task { await model.load() }
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
                        Image(systemName: showMCPPresets ? "xmark" : "plus")
                    }
                    .liquidGlassActionButtonStyle(density: .compact)
                    .help(showMCPPresets ? "收起预设" : "添加 MCP 服务器")

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
            Button("从预设添加") {
                withAnimation(.spring(duration: 0.25)) { showMCPPresets = true }
            }
            .liquidGlassActionButtonStyle(density: .compact)
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

                    // 删除（hover 才显示）
                    Button(role: .destructive) {
                        Task { await model.deleteMCPServer(id: server.id) }
                    } label: {
                        Image(systemName: "trash")
                            .foregroundStyle(.red.opacity(0.8))
                    }
                    .liquidGlassActionButtonStyle(density: .compact)
                    .accessibilityLabel("删除 \(server.name)")
                    .opacity(hoveredMCPServer == server.id ? 1 : 0)
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
                            newPromptName = ""
                            newPromptContent = ""
                            showAddPrompt = true
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
        .sheet(isPresented: $showAddPrompt) {
            addPromptSheet
        }
    }

    @ViewBuilder
    private var promptsContent: some View {
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

                Button(role: .destructive) {
                    Task { await model.deletePrompt(id: prompt.id) }
                } label: {
                    Image(systemName: "trash")
                        .foregroundStyle(.red.opacity(0.8))
                }
                .liquidGlassActionButtonStyle(density: .compact)
                .opacity(hoveredPrompt == prompt.id ? 1 : 0)
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

    private var addPromptSheet: some View {
        VStack(spacing: 0) {
            HStack {
                Button("取消") { showAddPrompt = false }
                    .keyboardShortcut(.escape)
                Spacer()
                Text("新建提示词")
                    .font(.headline)
                Spacer()
                Button("添加") {
                    Task {
                        await model.addPrompt(name: newPromptName, content: newPromptContent)
                        showAddPrompt = false
                    }
                }
                .disabled(newPromptName.trimmingCharacters(in: .whitespaces).isEmpty)
                .keyboardShortcut(.return, modifiers: .command)
            }
            .padding(.horizontal, 20)
            .padding(.vertical, 14)

            Divider()

            VStack(alignment: .leading, spacing: 12) {
                VStack(alignment: .leading, spacing: 4) {
                    Text("名称")
                        .font(.caption.weight(.semibold))
                        .foregroundStyle(.secondary)
                    TextField("输入提示词名称", text: $newPromptName)
                        .textFieldStyle(.roundedBorder)
                }

                VStack(alignment: .leading, spacing: 4) {
                    Text("内容")
                        .font(.caption.weight(.semibold))
                        .foregroundStyle(.secondary)
                    ZStack(alignment: .topLeading) {
                        if newPromptContent.isEmpty {
                            Text("在此输入提示词内容（可选）")
                                .foregroundStyle(.tertiary)
                                .font(.body)
                                .padding(6)
                                .allowsHitTesting(false)
                        }
                        TextEditor(text: $newPromptContent)
                            .font(.body)
                            .frame(minHeight: 120)
                            .overlay(
                                RoundedRectangle(cornerRadius: 6)
                                    .strokeBorder(Color.secondary.opacity(0.3))
                            )
                    }
                }
            }
            .padding(20)
        }
        .frame(minWidth: 400, minHeight: 320)
    }

    // MARK: - Skills

    private var skillsSection: some View {
        SectionCard(
            title: "快捷技能",
            icon: "wand.and.stars",
            iconColor: .orange,
            headerTrailing: {
                CollapseChevronButton(isExpanded: skillsExpanded) {
                    withAnimation(.easeInOut(duration: 0.2)) { skillsExpanded.toggle() }
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
        let installed = model.skills.installedSkills
        if installed.isEmpty {
            VStack(spacing: 8) {
                Image(systemName: "wand.and.stars")
                    .font(.system(size: 28))
                    .foregroundStyle(.secondary.opacity(0.4))
                Text("暂未安装技能")
                    .font(.subheadline)
                    .foregroundStyle(.secondary)
            }
            .frame(maxWidth: .infinity, minHeight: 80, alignment: .center)
        } else {
            VStack(spacing: 2) {
                ForEach(installed) { skill in
                    skillRow(skill)
                }
            }
        }
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
            }

            Spacer(minLength: 0)

            Text("\(skill.repoOwner)/\(skill.repoName)")
                .font(.caption2)
                .foregroundStyle(.tertiary)
                .lineLimit(1)
                .truncationMode(.middle)
        }
        .padding(.horizontal, 8)
        .padding(.vertical, 6)
    }
}
