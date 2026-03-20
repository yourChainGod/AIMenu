import SwiftUI
import AppKit

struct ToolsMCPServersSection: View {
    @ObservedObject var model: ToolsPageModel
    let isWorkbenchMode: Bool

    @Binding var mcpExpanded: Bool
    @Binding var showMCPPresets: Bool
    @Binding var showMCPForm: Bool
    @Binding var editingMCPServer: MCPServer?
    @Binding var hoveredMCPServer: String?

    @State private var expandedMCPServer: String? = nil

    var body: some View {
        SectionCard(
            title: "MCP 服务器",
            icon: "server.rack",
            iconColor: .blue,
            headerTrailing: {
                if !isWorkbenchMode {
                    CollapseChevronButton(isExpanded: mcpExpanded) {
                        withAnimation(AnimationPreset.quick) { mcpExpanded.toggle() }
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
                withAnimation(AnimationPreset.quick) { showMCPPresets.toggle() }
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
        ToolsHelpers.compactEmptyState(
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
                    .opacity(alreadyAdded ? OpacityScale.overlay : 1)
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

    private func mcpServerRow(_ server: MCPServer) -> some View {
        VStack(spacing: 0) {
            HStack(spacing: 10) {
                Circle()
                    .fill(server.isEnabled ? Color.mint : Color.secondary.opacity(OpacityScale.accent))
                    .frame(width: 7, height: 7)

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

                HStack(spacing: 6) {
                    Button {
                        withAnimation(AnimationPreset.quick) {
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

                    Button(role: .destructive) {
                        Task { await model.deleteMCPServer(id: server.id) }
                    } label: {
                        Image(systemName: "trash")
                            .foregroundStyle(.red.opacity(OpacityScale.solid))
                    }
                    .liquidGlassActionButtonStyle(density: .compact)
                    .accessibilityLabel("删除 \(server.name)")
                    .opacity(hoveredMCPServer == server.id ? 1 : OpacityScale.accent)
                }
                .animation(AnimationPreset.hover, value: hoveredMCPServer)
            }
            .padding(.horizontal, 10)
            .padding(.vertical, 8)
            .contentShape(Rectangle())
            .onTapGesture {
                withAnimation(AnimationPreset.quick) {
                    expandedMCPServer = expandedMCPServer == server.id ? nil : server.id
                }
            }

            if expandedMCPServer == server.id {
                VStack(alignment: .leading, spacing: 10) {
                    Divider().padding(.horizontal, 10)

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
                            .background(Color.primary.opacity(OpacityScale.subtle), in: RoundedRectangle(cornerRadius: 6))
                    }
                    .padding(.horizontal, 10)

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
                                .background(Color.primary.opacity(OpacityScale.subtle), in: RoundedRectangle(cornerRadius: 6))
                        }
                        .padding(.horizontal, 10)
                    }

                    VStack(alignment: .leading, spacing: 6) {
                        Text("启用应用")
                            .font(.caption.weight(.semibold))
                            .foregroundStyle(.secondary)
                        HStack(spacing: 8) {
                            ToolsHelpers.appMountChip(app: .claude, label: "Claude Code", isOn: server.apps.claude, onChange: { v in
                                Task { await model.toggleMCPApp(serverId: server.id, app: .claude, enabled: v) }
                            })
                            ToolsHelpers.appMountChip(app: .codex, label: "Codex", isOn: server.apps.codex, onChange: { v in
                                Task { await model.toggleMCPApp(serverId: server.id, app: .codex, enabled: v) }
                            })
                            ToolsHelpers.appMountChip(app: .gemini, label: "Gemini", isOn: server.apps.gemini, onChange: { v in
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
                      ? Color.primary.opacity(OpacityScale.subtle)
                      : Color.clear)
        }
        .animation(AnimationPreset.hover, value: hoveredMCPServer)
        .onHover { isHovered in hoveredMCPServer = isHovered ? server.id : nil }
    }
}
